#!/usr/bin/env python3
"""Compare a rendered SFX against the cart's own note data, row by row.

This is the systematic check for "the melody is wrong". It does not need
PICO-8: the cart already says what each row should be, so measuring the energy
of each row in a render and lining it up against that data localises a fault to
a row, and therefore to a waveform, a volume or an effect.

It is how the phaser bug was found - every silent row was wave 7 and no other
wave was affected, which pointed straight at the phaser rather than at
sequencing, pitch or the mixer.

Usage:
  make psg-wav CART=cart.p8.png SFX=8 SECONDS=5 WAV=build/sfx8.wav
  tools/psg_rows.py build/sfx8.wav --cart cart.p8.png --sfx 8
"""
import argparse
import math
import struct
import sys
import wave
from collections import defaultdict

from p8_audio import rom_from_png

NOTE = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
WAVE = ["tri", "tsaw", "saw", "square", "pulse", "organ", "noise", "phaser"]
FX = ["none", "slide", "vibrato", "drop", "fadein", "fadeout", "arp-fast",
      "arp-slow"]
TICK_HZ = 120.49


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wav")
    ap.add_argument("--cart", required=True)
    ap.add_argument("--sfx", type=int, required=True)
    ap.add_argument("--silent-below", type=float, default=40.0,
                    help="RMS under this counts as a missing note")
    a = ap.parse_args()

    rom = rom_from_png(a.cart)
    base = 0x3200 + a.sfx * 68
    speed = rom[base + 65]
    if speed == 0:
        raise SystemExit(f"sfx {a.sfx} has speed 0 - nothing to play")

    w = wave.open(a.wav)
    n = w.getnframes()
    sr = w.getframerate()
    d = struct.unpack(f"<{n}h", w.readframes(n))
    row_s = speed / TICK_HZ

    print(f"sfx {a.sfx}: speed {speed} ({row_s * 1000:.0f} ms/row), "
          f"loop {rom[base + 66]}..{rom[base + 67]}, "
          f"filter 0x{rom[base + 64]:02x}")
    print(f"{'row':>4} {'note':>5} {'wave':>7} {'vol':>4} {'effect':>9} "
          f"{'RMS':>7} {'peak':>7}  verdict")

    by_wave = defaultdict(lambda: [0, 0])     # wave -> [audible rows, silent]
    missing, leaked = 0, 0
    for i in range(32):
        v = rom[base + i * 2] | (rom[base + i * 2 + 1] << 8)
        pitch, wv, vol, fx = v & 0x3F, (v >> 6) & 7, (v >> 9) & 7, (v >> 12) & 7
        lo, hi = int(i * row_s * sr), int((i + 1) * row_s * sr)
        seg = d[lo:hi] if hi <= len(d) else d[lo:]
        if not seg:
            break
        rms = math.sqrt(sum(x * x for x in seg) / len(seg))
        peak = max(abs(x) for x in seg)

        if vol:
            by_wave[wv][0] += 1
            if rms < a.silent_below:
                by_wave[wv][1] += 1
                missing += 1
                verdict = "MISSING"
            else:
                verdict = "ok"
        else:
            verdict = "ok" if rms < a.silent_below else "leak"
            if verdict == "leak":
                leaked += 1
        print(f"{i:>4} {NOTE[pitch % 12]}{pitch // 12:<4} {WAVE[wv]:>7} "
              f"{vol:>4} {FX[fx]:>9} {rms:>7.0f} {peak:>7}  {verdict}")

    print()
    if missing:
        print("silent rows grouped by waveform - a waveform that is entirely "
              "silent is the fault, not the sequencing:")
        for wv, (tot, sil) in sorted(by_wave.items()):
            if sil:
                print(f"  {WAVE[wv]:>7}: {sil}/{tot} audible rows silent")
    print(f"{missing} audible row(s) silent, {leaked} silent row(s) leaking")
    return 1 if missing or leaked else 0


if __name__ == "__main__":
    sys.exit(main())
