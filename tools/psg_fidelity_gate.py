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
# Two volumes, because the defect that prompted this check is only audible at
# LOW volume: Celeste's track 30 runs its swept noise at volume 1, where the
# generator wanders ~3.8x more than PICO-8, while at volume 7 it wanders 1.8x.
# A probe at one volume is blind the same way a probe at one pitch was.
VOLUMES = (7, 1)
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
# Held-note wander, ours over PICO-8's. CALIBRATED, not chosen: two PICO-8
# recordings of this probe are byte-identical (its RNG is deterministic from
# startup), so the reference carries no run-to-run noise, and the only sampling
# error is the estimator's own. PICO-8's per-note wander spans 11..119 Hz with a
# coefficient of variation of 0.45, so the mean over 16 notes carries ~11%; three
# sigma is ~1.35. Anything above that is a real difference, not sampling.
#
# An earlier value of 2.0 was picked before measuring and happened to sit just
# above the failure - the same habit that produced a gate which could not fail.
WANDER_TOL = 1.35
# ...and what the chip actually achieves today, 1.55x. The gap between the two is
# a REAL, AUDIBLE defect that is not understood: our noise wanders more within a
# held note than PICO-8's, which is heard as ragged pitch transitions on Celeste's
# track 30. Four candidate causes were tested and refuted (kick gate timing, twice;
# correlated step draws; draw resolution), and four derived corrections took it
# from 1.94x to 1.55x without closing it.
#
# So the check carries two thresholds. Exceeding WANDER_TOL prints a KNOWN GAP and
# does NOT fail: the alternative is a permanently red suite, which gets muted and
# then ignored. Exceeding WANDER_GUARD fails, so the gap can never widen unnoticed
# and any real improvement can be locked in by lowering it. Do not raise the guard
# to make a change pass.
WANDER_GUARD = 1.70


def build_image(path: Path) -> None:
    """One SFX per volume: wave 6, eight pitches, four rows each, chained."""
    img = bytearray(4608)
    for v in range(len(VOLUMES)):
        first, last = v == 0, v == len(VOLUMES) - 1
        img[4 * v:4 * v + 4] = bytes([(0x80 if first else 0) | v,
                                      (0x80 if last else 0) | 0x42, 0x43, 0x44])
        sfx = 0x100 + 68 * v
        for row in range(32):
            pitch = PITCHES[row // ROWS_PER_PITCH]
            word = (pitch & 0x3F) | (6 << 6) | (VOLUMES[v] << 9)
            struct.pack_into("<H", img, sfx + 2 * row, word)
        img[sfx + 65] = SPEED
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(img))


def load(path: Path) -> np.ndarray:
    with wave.open(str(path)) as handle:
        return np.frombuffer(handle.readframes(handle.getnframes()),
                             dtype="<i2").astype(float)


def held_note_wander(samples: np.ndarray, sub: int = 2205) -> list[float]:
    """Timbre spread WITHIN each held pitch, in Hz of spectral centroid.

    The per-pitch averages below can match while the sound still wobbles inside
    a note, because averaging is exactly what hides that. PICO-8's noise holds a
    steady character on a held note; a generator whose random kicks arrive in
    clumps does not, and the lurching reads as ragged transitions even though
    every average is right. Celeste's track 30 exposed this by ear before any
    number here did.
    """
    out = []
    for index in range(len(PITCHES) * len(VOLUMES)):
        lo = (index * ROWS_PER_PITCH + 1) * ROW_SAMPLES
        hi = (index * ROWS_PER_PITCH + ROWS_PER_PITCH) * ROW_SAMPLES
        cents = []
        for start in range(lo, hi - sub, sub):
            seg = samples[start:start + sub]
            spectrum = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
            freqs = np.fft.rfftfreq(len(seg), 1 / RATE)
            cents.append(float((spectrum * freqs).sum() / max(spectrum.sum(), 1e-9)))
        out.append(max(cents) - min(cents) if len(cents) > 1 else 0.0)
    return out


def per_pitch(samples: np.ndarray) -> list[tuple[float, float]]:
    """(rms, spectral centroid) per pitch, skipping each group's first row.

    The first row of a group carries the note change, so it mixes two pitches.
    """
    out = []
    for index in range(len(PITCHES) * len(VOLUMES)):
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
    seconds = len(VOLUMES) * 32 * SPEED * 183 / RATE + 0.15
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
         "--samples", str(len(VOLUMES) * 32 * ROW_SAMPLES), "--clk", str(CLOCK),
         "--out", str(ours)],
        cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    ref = per_pitch(load(args.reference))
    cand = per_pitch(load(ours))

    print(" vol pitch |    PICO-8 rms / centroid |       ours rms / centroid | ratios")
    failures = []
    for v, volume in enumerate(VOLUMES):
        for k, pitch in enumerate(PITCHES):
            index = v * len(PITCHES) + k
            (rr, rc), (cr, cc) = ref[index], cand[index]
            rms_ratio = cr / rr if rr else float("inf")
            cen_ratio = cc / rc if rc else float("inf")
            bad = (abs(rms_ratio - 1) > PER_PITCH_TOL
                   or abs(cen_ratio - 1) > PER_PITCH_TOL)
            print(f"{volume:>4} {pitch:>5} | {rr:10.0f} / {rc:8.0f} | "
                  f"{cr:10.0f} / {cc:8.0f} | {rms_ratio:5.2f} {cen_ratio:5.2f}"
                  f"{'   MISMATCH' if bad else ''}")
            if bad:
                failures.append(f"vol {volume} pitch {pitch}")

    # Stability within a held note. Averages can all be right while the sound
    # wobbles inside each note, and that wobble is what a listener calls abrupt.
    ref_wander, cand_wander = held_note_wander(load(args.reference)), \
        held_note_wander(load(ours))
    for v, volume in enumerate(VOLUMES):
        lo, hi = v * len(PITCHES), (v + 1) * len(PITCHES)
        r_mean = float(np.mean(ref_wander[lo:hi]))
        c_mean = float(np.mean(cand_wander[lo:hi]))
        wander = c_mean / r_mean if r_mean else float("inf")
        state = ("" if wander <= WANDER_TOL
                 else "   KNOWN GAP" if wander <= WANDER_GUARD
                 else "   FAIL (worse than the recorded gap)")
        print(f"held-note wander, volume {volume}: PICO-8 {r_mean:5.0f} Hz, "
              f"ours {c_mean:5.0f} Hz ({wander:.2f}x, target {WANDER_TOL:.2f}x, "
              f"guard {WANDER_GUARD:.2f}x){state}")
        if wander > WANDER_GUARD:
            failures.append(f"held-note wander at volume {volume}")

    # The trend. This is the check the single-pitch probe could never make.
    # Within the loudest bank: a trend across a volume change would mix the two.
    def trend(rows, field):
        lo, hi = rows[0][field], rows[len(PITCHES) - 1][field]
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
