#!/usr/bin/env python3
"""Measure the pitch the PSG actually renders, and diff it against the cart.

sim/psg_wav.cpp renders one SFX (or a whole pattern) to a WAV. This reads that
WAV back, estimates the fundamental in each note slot by autocorrelation, and
prints it next to the pitch the cart's SFX data asked for. A port that plays
the right notes at the wrong speed, or the right speed at the wrong octave,
looks completely different here - which is the point.

  psg_notes.py build/sfx21.wav --cart cart.p8.png --sfx 21

PICO-8 pitch p is 440 * 2^((p-33)/12) Hz.
"""
import argparse
import math
import struct
import sys
import wave

from p8_audio import rom_from_png

RATE = 22050


def read_wav(path):
    with wave.open(path, "rb") as w:
        n, width, rate = w.getnframes(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    if width == 1:
        return [b - 128 for b in raw], rate
    return list(struct.unpack(f"<{n}h", raw)), rate


def fundamental(x, rate, fmin=55.0, fmax=2200.0):
    """Autocorrelation pitch estimate; None if the window is silent."""
    n = len(x)
    if n < 64:
        return None
    mean = sum(x) / n
    x = [v - mean for v in x]
    energy = sum(v * v for v in x) / n
    if energy < 1.0:
        return None
    lo = max(2, int(rate / fmax))
    hi = min(n - 2, int(rate / fmin))
    r0 = sum(v * v for v in x) / n
    if r0 <= 0:
        return None

    corr = {}
    for lag in range(lo, hi):
        s = 0.0
        for i in range(0, n - lag, 2):        # stride 2: fast enough, no worse
            s += x[i] * x[i + lag]
        corr[lag] = s / ((n - lag) / 2) / r0

    if not corr:
        return None
    best = max(corr.values())
    if best < 0.25:
        return None

    # Octave correction, done twice-carefully because both naive versions of
    # this lie in opposite directions:
    #
    #   * taking the global maximum locks onto 2x or 3x the true period, and
    #     reports notes exactly -12.00 or -19.02 semitones out;
    #   * taking the shortest lag above a threshold lands on the RISING FLANK
    #     of the first real peak, and reports everything uniformly sharp.
    #
    # Only local maxima are candidates, and the shortest strong one wins.
    lags = sorted(corr)
    peaks = [l for i, l in enumerate(lags[1:-1], 1)
             if corr[l] >= corr[lags[i - 1]] and corr[l] >= corr[lags[i + 1]]]
    strong = [l for l in peaks if corr[l] >= 0.9 * best]
    if not strong:
        return None
    lag = strong[0]

    # Parabolic interpolation: the period is rarely a whole number of samples,
    # and at 200 Hz one sample is already a sixth of a semitone.
    if lag - 1 in corr and lag + 1 in corr:
        y0, y1, y2 = corr[lag - 1], corr[lag], corr[lag + 1]
        d = y0 - 2 * y1 + y2
        if d != 0:
            lag = lag + 0.5 * (y0 - y2) / d
    return rate / lag


def pitch_of(hz):
    return 33 + 12 * math.log2(hz / 440.0)


def sfx_notes(rom, s):
    rec = rom[0x3200 + s * 68: 0x3200 + (s + 1) * 68]
    notes = []
    for r in range(32):
        b0, b1 = rec[r * 2], rec[r * 2 + 1]
        notes.append({"pitch": b0 & 0x3F,
                      "wave": (b0 >> 6) | ((b1 & 1) << 2),
                      "vol": (b1 >> 1) & 7,
                      "eff": (b1 >> 4) & 7,
                      "custom": (b1 >> 7) & 1})
    return notes, rec[65], rec[66], rec[67]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wav")
    ap.add_argument("--cart", required=True)
    ap.add_argument("--sfx", type=int, required=True)
    args = ap.parse_args()

    x, rate = read_wav(args.wav)
    rom = rom_from_png(args.cart)
    notes, speed, ls, le = sfx_notes(rom, args.sfx)

    # PICO-8: one row lasts `speed` sequencer ticks at 120.4788 Hz.
    tick = 1.0 / 120.4788
    row_s = speed * tick
    print(f"sfx {args.sfx}: speed {speed} -> {row_s * 1000:.1f} ms/row, "
          f"loop {ls}..{le}, wav {len(x) / rate:.2f}s")
    print(f"{'row':>4} {'want':>5} {'wave':>5} {'vol':>4} {'eff':>4} "
          f"{'want Hz':>9} {'got Hz':>9} {'got pitch':>10}  {'error':>8}")

    bad = tested = 0
    for r in range(32):
        n = notes[r]
        a = int(r * row_s * rate)
        b = int((r + 1) * row_s * rate)
        if b > len(x):
            break
        mid = x[a + (b - a) // 4: b - (b - a) // 8]   # skip attack and release
        want_hz = 440.0 * 2.0 ** ((n["pitch"] - 33) / 12.0)
        got = fundamental(mid, rate)
        if n["vol"] == 0:
            got_s = "silent" if got is None else f"{got:.1f}"
            print(f"{r:>4} {'-':>5} {'-':>5} {0:>4} {'-':>4} "
                  f"{'-':>9} {got_s:>9} {'-':>10}  {'-':>8}")
            continue
        tested += 1
        if got is None:
            print(f"{r:>4} {n['pitch']:>5} {n['wave']:>5} {n['vol']:>4} "
                  f"{n['eff']:>4} {want_hz:>9.1f} {'SILENT':>9} {'-':>10}  "
                  f"{'MISSING':>8}")
            bad += 1
            continue
        gp = pitch_of(got)
        err = gp - n["pitch"]
        flag = "" if abs(err) < 0.5 else ("  <-- " + f"{err:+.1f} semitones")
        if abs(err) >= 0.5:
            bad += 1
        print(f"{r:>4} {n['pitch']:>5} {n['wave']:>5} {n['vol']:>4} "
              f"{n['eff']:>4} {want_hz:>9.1f} {got:>9.1f} {gp:>10.2f}  "
              f"{err:>+8.2f}{flag}")

    print(f"\n{tested - bad}/{tested} audible rows within half a semitone")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())


# ---------------------------------------------------------------------------
# Waveform identification. Pitch being right does not mean the note sounds
# right: if the wave field is misread, every instrument is wrong and the music
# is "completely different" while every note is in tune.
# ---------------------------------------------------------------------------
def load_waves(path="rtl/psg_waves.hex"):
    vals = [int(l, 16) for l in open(path) if l.strip()]
    vals = [v - 256 if v > 127 else v for v in vals]
    return [vals[w * 256:(w + 1) * 256] for w in range(8)]


def norm(v):
    m = sum(v) / len(v)
    v = [x - m for x in v]
    e = math.sqrt(sum(x * x for x in v)) or 1.0
    return [x / e for x in v]


def identify_wave(x, rate, hz, waves):
    """Best-matching wave slot for one period of x, and its correlation."""
    period = rate / hz
    if period < 8 or len(x) < 2 * period:
        return None, 0.0
    start = int(period)
    cyc = [x[start + int(i * period / 256)] for i in range(256)]
    cyc = norm(cyc)
    best, bestw = -2.0, None
    for w, tbl in enumerate(waves):
        if not any(tbl):
            continue                     # 6 noise, 7 phaser: not table-driven
        t = norm(tbl)
        # try every rotation: the capture has no phase reference
        for shift in range(0, 256, 4):
            s = sum(cyc[i] * t[(i + shift) % 256] for i in range(256))
            if s > best:
                best, bestw = s, w
    return bestw, best
