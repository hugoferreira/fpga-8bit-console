#!/usr/bin/env python3
"""Generate the PSG's synthesis tables (all defined against the 22050 Hz
virtual sample rate, so they are independent of the system clock):

  rtl/psg_pitch.hex  64 x 24-bit phase increments, 2^24 * f(p) / 22050
  rtl/psg_waves.hex  8 waves x 256 x signed 8-bit, exact PICO-8 shapes
  rtl/psg_waves_compact.hex
                     triangle and organ only; tilted saw and saw use bounded
                     integer phase formulae in RTL, and square and pulse are
                     exact threshold functions
  rtl/psg_noise.hex  64 x unsigned 8-bit, noise gain per key (1.0 = 256)
                     (slots 6/7 zero: noise is an LFSR, phaser is summed
                     from two triangle reads)
"""
import math
import os
import sys


def pitch_hz(p):
    return 440.0 * 2.0 ** ((p - 33) / 12.0)


# Shipping PICO-8 does not calculate equal temperament in floating point. Its
# _get_dx_for_note routine indexes this twelve-entry integer table, applies a
# fixed-point reciprocal multiply, then octave-shifts the 16-bit oscillator
# increment. rtl/psg.sv uses a 24-bit phase, hence the final << 8.
NOTE_DX = [523, 554, 587, 622, 659, 698,
           740, 784, 831, 880, 932, 984]


def pico8_phase_increment(p):
    octave, chromatic = divmod(p, 12)
    dp = ((NOTE_DX[chromatic] << 16) * 0x2F8DF18F) >> 44
    dp = dp >> (3 - octave) if octave < 3 else dp << (octave - 3)
    return dp << 8


def wave(w, t):
    if w == 0:  # triangle
        return 0.5 * (1.0 - abs(4.0 * t - 2.0))
    if w == 1:  # tilted saw
        a = 0.875
        x = 2.0 * t / a - 1.0 if t < a else 2.0 * (1.0 - t) / (1.0 - a) - 1.0
        return 0.5 * x
    if w == 2:  # saw
        return 0.653 * (t - 0.5)
    if w == 3:  # square
        return -0.25 if t < 0.5 else 0.25
    if w == 4:  # pulse: PICO-8 transition at phase 0xb000
        return -0.25 if t < 0.6875 else 0.25
    if w == 5:  # organ
        x = 3.0 - abs(24.0 * t - 6.0) if t < 0.5 else 1.0 - abs(16.0 * t - 12.0)
        return x / 9.0
    return 0.0  # 6 noise (LFSR), 7 phaser (dual triangle) - not from ROM


def quantized_wave(w, phase):
    return max(-127, min(127, round(wave(w, phase / 256.0) * 254.0)))


def triangle_formula(phase):
    # NOT WIRED UP: the exact form, measured and rejected (design 5.1 - it
    # placed +82 to +193 across three variants, and the cheaper folded
    # approximation failed the effect-3-drop gate, so triangle stays in
    # ROM). Kept, with its assert, as documentation of the exactness result.
    # Fold to 0..128..1. The recovered 127/64 ramp then reduces to two phase
    # thresholds: subtract one from 2*u-127 at u=32, and another at u=97.
    folded = 256 - phase if phase & 0x80 else phase
    return (2 * folded - 127
            - (folded >= 32) - (folded >= 97))


def tilted_saw_formula(phase):
    # The recovered slopes are 127/112 and -127/16. The nearest one-add
    # shift forms stay within three sample units.
    if phase < 224:
        return phase + (phase >> 3) - 127
    return 127 - ((phase - 224) << 3)


def saw_formula(phase):
    # A two-chain 5/8 ramp retains the recovered saw's shape and stays within
    # four sample units; the oracle's fitted-gain gate adjudicates its level.
    signed_phase = phase - 128
    return signed_phase - (signed_phase >> 2) - (signed_phase >> 3)


assert all(triangle_formula(p) == quantized_wave(0, p) for p in range(256))
assert max(abs(tilted_saw_formula(p) - quantized_wave(1, p))
           for p in range(256)) <= 3
assert max(abs(saw_formula(p) - quantized_wave(2, p))
           for p in range(256)) <= 4


with open("rtl/psg_pitch.hex", "w") as f:
    for p in range(64):
        f.write(f"{pico8_phase_increment(p):06x}\n")

# The constants block RAM (rtl/psg_const.hex): one 256x16 EBR in the block
# freed by the computed waveforms. Words 0..63 hold the pitch increment's
# effective bits - every pinc is dp << 8 and dp fits 13 bits, so the RTL
# reconstructs {3'b0, word[12:0], 8'b0}.
#
# Words 64..111 hold the SLIDE's affine table, four words per chromatic:
# _get_dx_for_note_fine's 57-bit product is affine in the 16-bit
# fraction, so per chromatic it collapses to
#   dp_pre = base_c + ((r_c + frac*b_c) >> 29)
# and the RTL needs one 16-bit multiply instead of three service passes
# against a 56-bit accumulator. The words are split exactly as the two
# 12-bit multiplier passes consume them. base_c needs no word of its own:
# octave 3 applies no shift, so base_c IS word 36+c. The derivation and
# its exhaustive proof live in tools/psg_hw_forms.py (slide.affine_table)
# and are imported rather than restated here.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from psg_hw_forms import slide_affine_table            # noqa: E402

AFFINE = slide_affine_table()
assert AFFINE is not None, "no feasible slide affine table"
with open("rtl/psg_const.hex", "w") as f:
    for p in range(64):
        dp = pico8_phase_increment(p) >> 8
        assert dp < (1 << 13)
        f.write(f"{dp:04x}\n")
    for c, (base, r, b) in enumerate(AFFINE):
        assert base == pico8_phase_increment(36 + c) >> 8, (
            "base_c must equal the octave-3 pitch word")
        assert r < (1 << 29) and b < (1 << 21)
        for w in (b & 0xFFF, b >> 12, r & 0xFFFF, r >> 16):
            f.write(f"{w:04x}\n")
    for _ in range(64 + 4 * len(AFFINE), 256):
        f.write("0000\n")

with open("rtl/psg_waves.hex", "w") as f:
    for w in range(8):
        for i in range(256):
            s = quantized_wave(w, i)
            f.write(f"{s & 0xFF:02x}\n")

with open("rtl/psg_waves_compact.hex", "w") as f:
    for w in (0, 5):
        for i in range(256):
            s = quantized_wave(w, i)
            f.write(f"{s & 0xFF:02x}\n")

# Noise gain per key.
#
# PICO-8's noise is one-pole-filtered white whose cutoff follows the pitch, then
# a key-dependent make-up gain of 1.5*(1+(1-key/63)^2) (zepto-8 synth.cpp
# INST_NOISE). The filter attenuates low pitches more than that gain lifts them,
# so the NET amplitude still rises with pitch: RMS 0.22 of full scale at key 8,
# 0.50 at key 63.
#
# This PSG generates noise as a sample-and-hold of an LFSR at the pitch rate.
# That gets the spectral shaping roughly right but its amplitude does not vary
# with pitch at all - it sat flat at 0.433, about 2x too loud at the bottom of
# the range and slightly quiet at the top. This table restores the slope.
#
# The steady-state RMS of new = (last + s*r)/(1 + s), r uniform on [-1,1], is
# sqrt(s/(3(s+2))), so the curve is analytic and needs no simulation.
def noise_gain(key):
    s = pitch_hz(key) / 22050.0 * 8.858923
    base = math.sqrt(s / (3.0 * (s + 2.0)))
    f = 1.0 - key / 63.0
    target = base * 1.5 * (1.0 + f * f)      # zepto-8 RMS, fraction of full scale
    return target / (1.0 / math.sqrt(3.0))   # nz_hold is uniform, RMS = 1/sqrt(3)


with open("rtl/psg_noise.hex", "w") as f:
    for k in range(64):
        f.write(f"{max(0, min(255, round(noise_gain(k) * 256.0))):02x}\n")

print("pitch 33 -> PICO-8 dp", pico8_phase_increment(33) >> 8,
      "phase increment", pico8_phase_increment(33))
