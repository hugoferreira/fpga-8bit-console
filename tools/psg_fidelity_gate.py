#!/usr/bin/env python3
"""Fidelity gate: does the PSG match REAL PICO-8 where bytes cannot be compared?

tools/psg_oracle_bytecheck.py is a REGRESSION gate, not a fidelity one - it
byte-compares today's RTL against frozen renders of our OWN RTL, so it proves
"nothing changed", and anything already wrong when the set was frozen stays green
forever. That is exactly how wave-6 noise came to ignore the note pitch while
"byte-identical 59/59" was reported after every change.

Noise cannot be byte-compared against PICO-8 even in principle: its RNG is shared
across voices, so the sequence depends on what every other voice did. What CAN be
compared is the statistics, and specifically their PITCH DEPENDENCE - a single
pitch cannot show it, which is the other half of why the old probe was blind.

The probe sweeps eight pitches through one SFX and compares, per pitch:
  rms       does the noise get louder with pitch, as PICO-8's does
  centroid  does it get brighter
and then the TREND across the sweep (top pitch over bottom). A generator that is
right at one pitch and flat everywhere else passes every per-pitch tolerance you
would reasonably set, and fails the trend - which is the property that was
actually broken.

  psg_fidelity_gate.py --record      # capture the PICO-8 reference (needs PICO-8)
  psg_fidelity_gate.py               # gate against the cached reference
"""
from __future__ import annotations

import argparse
import struct
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

RATE = 22050
PITCHES = (4, 12, 20, 28, 36, 44, 52, 60)
ROWS_PER_PITCH = 4
SPEED = 16                      # ticks per row
ROW_SAMPLES = SPEED * 183
CLOCK = 28_125_000

WORK = ROOT / "build/psg_fidelity"
IMAGE = WORK / "noise-sweep.bin"
REFERENCE = ROOT / "tests/psg/pico8-noise-sweep.wav"

# Per-pitch tolerance is loose on purpose: two different noise realisations of the
# same process differ run to run. The TREND tolerance is what carries the gate.
PER_PITCH_TOL = 0.35
TREND_TOL = 0.30


def build_image(path: Path) -> None:
    """One SFX: wave 6, volume 7, eight pitches, four rows each."""
    img = bytearray(4608)
    img[0:4] = bytes([0x80, 0xC2, 0x43, 0x44])      # pattern 0, sfx0 on ch0
    sfx = 0x100
    for row in range(32):
        pitch = PITCHES[row // ROWS_PER_PITCH]
        word = (pitch & 0x3F) | (6 << 6) | (7 << 9)  # noise, volume 7
        struct.pack_into("<H", img, sfx + 2 * row, word)
    img[sfx + 65] = SPEED
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(img))


def load(path: Path) -> np.ndarray:
    with wave.open(str(path)) as handle:
        return np.frombuffer(handle.readframes(handle.getnframes()),
                             dtype="<i2").astype(float)


def per_pitch(samples: np.ndarray) -> list[tuple[float, float]]:
    """(rms, spectral centroid) per pitch, skipping each group's first row.

    The first row of a group carries the note change, so it mixes two pitches.
    """
    out = []
    for index in range(len(PITCHES)):
        lo = (index * ROWS_PER_PITCH + 1) * ROW_SAMPLES
        hi = (index * ROWS_PER_PITCH + ROWS_PER_PITCH) * ROW_SAMPLES
        seg = samples[lo:hi]
        if len(seg) < 1024:
            out.append((0.0, 0.0))
            continue
        spectrum = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
        freqs = np.fft.rfftfreq(len(seg), 1 / RATE)
        centroid = float((spectrum * freqs).sum() / max(spectrum.sum(), 1e-9))
        out.append((float(np.sqrt((seg ** 2).mean())), centroid))
    return out


def record_reference(out: Path) -> None:
    build_image(IMAGE)
    seconds = 32 * SPEED * 183 / RATE + 0.15
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [sys.executable, str(ROOT / "tools/p8_music_wav.py"),
         "--image", str(IMAGE), "--pattern", "0", "--mask", "1",
         "--seconds", f"{seconds:.2f}", "--out", str(out)],
        cwd=ROOT, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--record", action="store_true",
                        help="capture the PICO-8 reference (real time, audible)")
    parser.add_argument("--reference", type=Path, default=REFERENCE)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if args.record:
        record_reference(args.reference)
        print(f"recorded {args.reference}")
        return 0
    if not args.reference.exists():
        print(f"no reference at {args.reference}; run --record on a machine with "
              f"PICO-8 (real time, plays audibly)")
        return 1

    build_image(IMAGE)
    import psg_oracle_render
    binary = psg_oracle_render.build(CLOCK, ROOT / "build/psg_oracle", 8)
    ours = WORK / "noise-sweep-rtl.wav"
    subprocess.run(
        [str(binary), "--audio", str(IMAGE), "--music", "0", "--mask", "1",
         "--samples", str(32 * ROW_SAMPLES), "--clk", str(CLOCK),
         "--out", str(ours)],
        cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    ref = per_pitch(load(args.reference))
    cand = per_pitch(load(ours))

    print("pitch |    PICO-8 rms / centroid |       ours rms / centroid | ratios")
    failures = []
    for index, pitch in enumerate(PITCHES):
        (rr, rc), (cr, cc) = ref[index], cand[index]
        rms_ratio = cr / rr if rr else float("inf")
        cen_ratio = cc / rc if rc else float("inf")
        bad = (abs(rms_ratio - 1) > PER_PITCH_TOL
               or abs(cen_ratio - 1) > PER_PITCH_TOL)
        print(f"{pitch:>5} | {rr:10.0f} / {rc:8.0f} | {cr:10.0f} / {cc:8.0f} | "
              f"{rms_ratio:5.2f} {cen_ratio:5.2f}{'   MISMATCH' if bad else ''}")
        if bad:
            failures.append(f"pitch {pitch}")

    # The trend. This is the check the single-pitch probe could never make.
    def trend(rows, field):
        lo, hi = rows[0][field], rows[-1][field]
        return hi / lo if lo else float("inf")

    for field, label in ((0, "rms"), (1, "centroid")):
        ref_trend, cand_trend = trend(ref, field), trend(cand, field)
        ratio = cand_trend / ref_trend if ref_trend else float("inf")
        ok = abs(ratio - 1) <= TREND_TOL
        print(f"trend {label:8}: PICO-8 rises {ref_trend:5.2f}x across the sweep, "
              f"ours {cand_trend:5.2f}x  ({ratio:.2f} of it){'' if ok else '   FAIL'}")
        if not ok:
            failures.append(f"{label} trend")

    if failures:
        print(f"\nFAIL: {', '.join(failures)}")
        return 1
    print("\nPASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
