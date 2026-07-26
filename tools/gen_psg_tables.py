#!/usr/bin/env python3
"""Generate the PSG's synthesis tables (all defined against the 22050 Hz
virtual sample rate, so they are independent of the system clock):

  rtl/psg_pitch.hex  64 x 24-bit phase increments, 2^24 * f(p) / 22050
  rtl/psg_waves.hex  8 waves x 256 x signed 8-bit, exact PICO-8 shapes
  rtl/psg_noise.hex  64 x unsigned 8-bit, noise gain per key (1.0 = 256)
                     (slots 6/7 zero: noise is an LFSR, phaser is summed
                     from two triangle reads)
  rtl/psg_recip.hex  256 x 16-bit, 65536/speed for Q8 row progress
"""
import math


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


with open("rtl/psg_pitch.hex", "w") as f:
    for p in range(64):
        f.write(f"{pico8_phase_increment(p):06x}\n")

with open("rtl/psg_waves.hex", "w") as f:
    for w in range(8):
        for i in range(256):
            s = max(-127, min(127, round(wave(w, i / 256.0) * 254.0)))
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

with open("rtl/psg_recip.hex", "w") as f:
    for s in range(256):
        f.write(f"{min(0xFFFF, round(65536 / max(1, s))):04x}\n")

print("pitch 33 -> PICO-8 dp", pico8_phase_increment(33) >> 8,
      "phase increment", pico8_phase_increment(33))
