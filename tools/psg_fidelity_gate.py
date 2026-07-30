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

It also measures three held-note properties:
  wander    stddev of overlapping-window centroids
  repeats   adjacent equal-sample rate (the walk's holds)
  hf share  fraction of power above 4 kHz
The latter two are deliberately sharp regression instruments: the former
combinational publication bug collapsed repeats and roughly doubled HF share
while still passing the broad RMS and centroid checks.

  psg_fidelity_gate.py --record      # capture the PICO-8 reference (needs PICO-8)
  psg_fidelity_gate.py               # gate against the cached reference
  psg_fidelity_gate.py --candidate x.wav  # gate a pre-rendered candidate
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
# Two volumes because kick magnitude and output quantisation both depend on
# amplitude. A probe at one volume is blind the same way a probe at one pitch
# was; Celeste's swept-noise track exercises the quiet bank in real material.
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
# Held-note wander, candidate over PICO-8. This is calibrated from the exact
# listing model, not selected around this RTL: with 2205-sample windows at a
# 441-sample hop, the reference is 59.4/39.3 Hz at volumes 7/1 and twelve model
# RNG seeds span 47.8..62.0 / 31.4..41.9 Hz. The 1.10 target clears that measured
# upper spread; 1.25 is a regression guard. The lower side is intentionally not
# gated: periodic noise can score artificially "better" on this statistic.
WANDER_WINDOW = 2205
WANDER_HOP = 441
WANDER_TOL = 1.10
WANDER_GUARD = 1.25

# The exact model's twelve-seed spread is 0.992..1.009 of the reference repeat
# rate and 0.975..1.021 of its >4 kHz power share. A 25% guard is deliberately
# wider than that realization spread yet nowhere near the publication bug's
# measured 0.04..0.05x repeats and 1.50..1.96x HF share under this estimator.
REPEAT_TOL = 0.25
HF_SHARE_TOL = 0.25
HF_CUTOFF = 4000.0


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


def held_note_metrics(samples: np.ndarray) -> list[tuple[float, float, float]]:
    """(centroid stddev, repeat rate, HF power share) for each held pitch.

    The per-pitch averages below can match while the sound still wobbles inside
    a note. Overlapping windows give each note fifteen observations instead of
    the old three disjoint ones; standard deviation uses all observations
    instead of making the result depend only on two extrema.

    Repeats operate on sample DELTAS, so the reference recorder's drifting DC
    does not disturb them. HF share is power, not magnitude, with per-note DC
    removed before the Hann-windowed transform.
    """
    out = []
    for index in range(len(PITCHES) * len(VOLUMES)):
        lo = (index * ROWS_PER_PITCH + 1) * ROW_SAMPLES
        hi = (index * ROWS_PER_PITCH + ROWS_PER_PITCH) * ROW_SAMPLES
        held = samples[lo:hi]
        cents = []
        for start in range(0, len(held) - WANDER_WINDOW + 1, WANDER_HOP):
            seg = held[start:start + WANDER_WINDOW]
            spectrum = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
            freqs = np.fft.rfftfreq(len(seg), 1 / RATE)
            cents.append(float((spectrum * freqs).sum() / max(spectrum.sum(), 1e-9)))
        wander = float(np.std(cents, ddof=1)) if len(cents) > 1 else 0.0
        repeats = float(np.mean(np.diff(held) == 0)) if len(held) > 1 else 0.0
        ac = held - held.mean()
        power = np.abs(np.fft.rfft(ac * np.hanning(len(ac)))) ** 2
        freqs = np.fft.rfftfreq(len(ac), 1 / RATE)
        hf_share = float(power[freqs >= HF_CUTOFF].sum()
                         / max(power.sum(), 1e-9))
        out.append((wander, repeats, hf_share))
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
    parser.add_argument("--candidate", type=Path,
                        help="gate this pre-rendered WAV instead of rendering RTL")
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

    if args.candidate is None:
        build_image(IMAGE)
        import psg_oracle_render
        binary = psg_oracle_render.build(CLOCK, ROOT / "build/psg_oracle", 8)
        ours = WORK / "noise-sweep-rtl.wav"
        subprocess.run(
            [str(binary), "--audio", str(IMAGE), "--music", "0", "--mask", "1",
             "--samples", str(len(VOLUMES) * 32 * ROW_SAMPLES), "--clk", str(CLOCK),
             "--out", str(ours)],
            cwd=ROOT, check=True, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL)
    else:
        ours = args.candidate
        if not ours.exists():
            parser.error(f"candidate does not exist: {ours}")

    ref_samples, cand_samples = load(args.reference), load(ours)
    ref = per_pitch(ref_samples)
    cand = per_pitch(cand_samples)

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
    ref_held = held_note_metrics(ref_samples)
    cand_held = held_note_metrics(cand_samples)
    for v, volume in enumerate(VOLUMES):
        lo, hi = v * len(PITCHES), (v + 1) * len(PITCHES)
        r_mean = float(np.mean([row[0] for row in ref_held[lo:hi]]))
        c_mean = float(np.mean([row[0] for row in cand_held[lo:hi]]))
        wander = c_mean / r_mean if r_mean else float("inf")
        state = ("" if wander <= WANDER_TOL
                 else "   KNOWN GAP" if wander <= WANDER_GUARD
                 else "   FAIL (above the regression guard)")
        print(f"held-note wander, volume {volume}: PICO-8 {r_mean:5.0f} Hz, "
              f"ours {c_mean:5.0f} Hz ({wander:.2f}x, target {WANDER_TOL:.2f}x, "
              f"guard {WANDER_GUARD:.2f}x){state}")
        if wander > WANDER_GUARD:
            failures.append(f"held-note wander at volume {volume}")

        for field, label, tolerance in (
                (1, "repeat rate", REPEAT_TOL),
                (2, ">4 kHz power share", HF_SHARE_TOL)):
            ref_value = float(np.mean([row[field] for row in ref_held[lo:hi]]))
            cand_value = float(np.mean([row[field] for row in cand_held[lo:hi]]))
            ratio = cand_value / ref_value if ref_value else float("inf")
            ok = abs(ratio - 1.0) <= tolerance
            print(f"{label}, volume {volume}: PICO-8 {100 * ref_value:5.1f}%, "
                  f"ours {100 * cand_value:5.1f}% ({ratio:.2f}x, "
                  f"guard {1 - tolerance:.2f}..{1 + tolerance:.2f}x)"
                  f"{'' if ok else '   FAIL'}")
            if not ok:
                failures.append(f"{label} at volume {volume}")

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
