#!/usr/bin/env python3
"""Generate the PSG's synthesis tables (all defined against the 22050 Hz
virtual sample rate, so they are independent of the system clock):

  rtl/psg_pitch.hex  64 x 24-bit phase increments, 2^24 * f(p) / 22050
  rtl/psg_waves.hex  8 waves x 256 x signed 8-bit, exact PICO-8 shapes
                     (slots 6/7 zero: noise is an LFSR, phaser is summed
                     from two triangle reads)
  rtl/psg_recip.hex  256 x 16-bit, 65536/speed for Q8 row progress
"""
import math


def pitch_hz(p):
    return 440.0 * 2.0 ** ((p - 33) / 12.0)


def wave(w, t):
    if w == 0:  # triangle
        return 0.5 * (1.0 - abs(4.0 * t - 2.0))
    if w == 1:  # tilted saw
        a = 0.875
        x = 2.0 * t / a - 1.0 if t < a else 2.0 * (1.0 - t) / (1.0 - a) - 1.0
        return 0.5 * x
    if w == 2:  # saw
        return 0.653 * (t if t < 0.5 else t - 1.0)
    if w == 3:  # square
        return 0.25 if t < 0.5 else -0.25
    if w == 4:  # pulse ~31.6%
        return 0.25 if t < 0.316 else -0.25
    if w == 5:  # organ
        x = 3.0 - abs(24.0 * t - 6.0) if t < 0.5 else 1.0 - abs(16.0 * t - 12.0)
        return x / 9.0
    return 0.0  # 6 noise (LFSR), 7 phaser (dual triangle) - not from ROM


with open("rtl/psg_pitch.hex", "w") as f:
    for p in range(64):
        f.write(f"{round((1 << 24) * pitch_hz(p) / 22050.0):06x}\n")

with open("rtl/psg_waves.hex", "w") as f:
    for w in range(8):
        for i in range(256):
            s = max(-127, min(127, round(wave(w, i / 256.0) * 254.0)))
            f.write(f"{s & 0xFF:02x}\n")

with open("rtl/psg_recip.hex", "w") as f:
    for s in range(256):
        f.write(f"{min(0xFFFF, round(65536 / max(1, s))):04x}\n")

print("pitch 33 ->", pitch_hz(33), "Hz; inc", round((1 << 24) * pitch_hz(33) / 22050.0))
