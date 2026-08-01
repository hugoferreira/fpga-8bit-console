#!/usr/bin/env python3
"""Fidelity against PICO-8, as a REGRESSION gate.

tools/psg_track_gate.py already compares a render to a real PICO-8 recording,
but its verdict is an ABSOLUTE tolerance: a change that moves music 20's lock
from 0.83 to 0.73 still passes it. That is exactly how two changes in this
campaign degraded timing fidelity while every gate stayed green - the numbers
had to be diffed by hand out of two logs to see it.

This renders every Celeste entry point with the CURRENT RTL, measures it
against the committed PICO-8 references, and compares the measurements to a
recorded baseline. A metric that moves by more than its tolerance FAILS, so
"the gate passed" and "fidelity did not regress" stop being different claims.

  make test-psg-pico8                     # gate
  make test-psg-pico8 RECORD=1            # re-baseline (state why in the commit)

The baseline is fidelity against PICO-8, NOT against our own previous render.
Our previous render is not ground truth; the recordings are. A change that
moves samples but not fidelity is a schedule change, and this says so.
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import psg_oracle_render                                   # noqa: E402
import psg_ref_check as R                                  # noqa: E402
from p8_audio import rom_from_png                          # noqa: E402

BASELINE = os.path.join(ROOT, "tests", "psg", "pico8-fidelity.json")
ENTRIES = (0, 10, 20, 30, 40)

# Per-metric tolerances. Lock is the one that catches sequencer timing drift,
# so it is the tight one; band levels are in dB and already have a guard band
# in the absolute gate.
TOL = {
    "lock_median": 0.04,        # correlation at the best lag
    "lock_tracked": 0.06,       # fraction of half-second blocks holding lag
    "contour": 0.01,            # loudness/timbre trajectory, the noise metric
    "band_db": 0.30,            # absolute band level, dB render/reference
}


def render(entry, audio_path, samples, clock=28_125_000):
    out = os.path.join(ROOT, "build", "psg_pico8_fidelity",
                       f"music{entry}.wav")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    binary = psg_oracle_render.build(
        clock, pathlib.Path(ROOT) / "build" / "psg_oracle", 8)
    subprocess.run([str(binary), "--audio", audio_path, "--music", str(entry),
                    "--mask", "7", "--samples", str(samples), "--clk",
                    str(clock), "--out", out], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)
    return out


def measure(reference, candidate):
    """The numbers that moved when this campaign degraded fidelity."""
    out = {}
    pitched = R.reference_pitchiness(reference) >= R.PITCHED_MIN
    lag = R.align(reference, candidate) if pitched else \
        R.align_envelope(reference, candidate)
    shifted = R.shift(candidate, lag)

    if pitched:
        locks = R.lock(reference, candidate)
        if locks:
            held = [c for _, _, c in locks]
            good = [c > 0.70 for _, _, c in locks]
            out["lock_median"] = float(np.median(held))
            out["lock_tracked"] = sum(good) / len(good)

    rows = R.contour(reference, shifted)
    if rows is not None:
        out["contour"] = float(rows if np.isscalar(rows) else np.mean(rows))

    bands = R.band_balance(reference, shifted)
    for b in bands:
        for scope in ("whole", "local", "quiet"):
            v = getattr(b, f"{scope}_db")
            if v is not None:
                out[f"band:{b.label}:{scope}"] = float(v)
    return out


def compare(base, now):
    """Regressions only: a metric that IMPROVED is never a failure."""
    bad = []
    for key, was in base.items():
        if key not in now:
            bad.append(f"{key}: no longer measured (was {was:.3f})")
            continue
        is_ = now[key]
        if key.startswith("band:"):
            tol, worse = TOL["band_db"], abs(is_) - abs(was)
        else:
            tol = TOL.get(key.split(":")[0], 0.05)
            worse = was - is_          # these metrics are better when larger
        if worse > tol:
            bad.append(f"{key}: {was:.3f} -> {is_:.3f} "
                       f"(worse by {worse:.3f}, tolerance {tol:.3f})")
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cart", required=True)
    ap.add_argument("--reference-dir", default=os.path.join(ROOT, "build", "p8ref"))
    ap.add_argument("--entries", help="comma-separated subset, for smoke tests")
    ap.add_argument("--clock", type=int, default=28_125_000,
                    help="PSG clock to render at; the baseline is at the "
                         "shipping clock, so a sweep is informational")
    ap.add_argument("--record", action="store_true",
                    help="rewrite the baseline instead of gating against it")
    args = ap.parse_args()

    audio = bytes(rom_from_png(args.cart)[0x3100:0x4300])
    audio_path = os.path.join(ROOT, "build", "psg_pico8_fidelity", "audio.bin")
    os.makedirs(os.path.dirname(audio_path), exist_ok=True)
    open(audio_path, "wb").write(audio)

    base = {}
    if not args.record:
        if not os.path.exists(BASELINE):
            raise SystemExit(f"no baseline at {BASELINE}; run with RECORD=1")
        base = json.load(open(BASELINE))

    entries = ([int(x) for x in args.entries.split(",")]
               if args.entries else ENTRIES)
    results, failures = {}, []
    for entry in entries:
        ref_path = os.path.join(args.reference_dir, f"pico8-{entry}.wav")
        if not os.path.exists(ref_path):
            raise SystemExit(f"missing PICO-8 reference: {ref_path}")
        reference = R.load(ref_path)
        cand = R.load(render(entry, audio_path, len(reference),
                             clock=args.clock))
        m = measure(reference, cand)
        results[str(entry)] = m
        print(f"=== music {entry} vs PICO-8 ===")
        for k in sorted(m):
            was = base.get(str(entry), {}).get(k)
            delta = "" if was is None else f"   (baseline {was:+.3f})"
            print(f"    {k:<28} {m[k]:+.3f}{delta}")
        if not args.record:
            for line in compare(base.get(str(entry), {}), m):
                failures.append(f"music {entry}: {line}")

    if args.record:
        os.makedirs(os.path.dirname(BASELINE), exist_ok=True)
        json.dump(results, open(BASELINE, "w"), indent=1, sort_keys=True)
        print(f"\nbaseline written to {BASELINE}")
        return 0

    print()
    if failures:
        print("FIDELITY REGRESSED against PICO-8:")
        for f in failures:
            print(f"  {f}")
        return 1
    print("fidelity against PICO-8 is within tolerance of the baseline")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
