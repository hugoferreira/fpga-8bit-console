#!/usr/bin/env python3
"""Capture, render and diagnose the generated PSG oracle matrix."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

import p8_music_export
import psg_oracle
import psg_oracle_render

ROOT = Path(__file__).resolve().parents[1]

DETERMINISTIC_TOLERANCE = {
    "duration_samples": 0,
    "fitted_gain_min": 0.90,
    "fitted_gain_max": 1.10,
    "correlation_min": 0.99,
    "nrmse_max": 0.10,
}
TRANSITION_TOLERANCE = {
    **DETERMINISTIC_TOLERANCE,
    "correlation_min": 0.999,
    "nrmse_max": 0.03,
}
STOCHASTIC_TOLERANCE = {
    "duration_samples": 0,
    "rms_mean_relative_max": 0.10,
    "peak_mean_relative_max": 0.10,
    "zero_crossing_absolute_max": 0.15,
    "autocorrelation_absolute_max": 0.15,
}


def tolerance(case: dict) -> dict:
    """Return the explicit diagnostic gate carried with this case's result."""
    if case["stochastic"]:
        return dict(STOCHASTIC_TOLERANCE)
    if case["name"].startswith("transition-"):
        return dict(TRANSITION_TOLERANCE)
    return dict(DETERMINISTIC_TOLERANCE)


def classify(case: dict, metrics: dict) -> list[str]:
    failures = []
    if metrics.get("reference_sample_error") != 0:
        failures.append("reference-duration")
    if metrics.get("candidate_sample_error") != 0:
        failures.append("sequencer/timing")
    if case["stochastic"]:
        rel = metrics["relative_error"]
        gate = tolerance(case)
        if (rel["rms_mean"] > gate["rms_mean_relative_max"]
                or rel["peak_mean"] > gate["peak_mean_relative_max"]):
            failures.append("noise/filter-level")
        if (rel["zero_crossing_density"]
                > gate["zero_crossing_absolute_max"]
                or max(rel["autocorrelation"].values())
                > gate["autocorrelation_absolute_max"]):
            failures.append("noise/filter-shape")
        return failures
    gate = tolerance(case)
    gain = abs(metrics["fitted_gain"])
    if not gate["fitted_gain_min"] <= gain <= gate["fitted_gain_max"]:
        failures.append("mixer/amplitude")
    if (metrics["correlation"] < gate["correlation_min"]
            or metrics["nrmse"] > gate["nrmse_max"]):
        if case["name"].startswith("effect-"):
            failures.append("effect")
        elif case["name"].startswith("filter-"):
            failures.append("filter")
        elif case["name"].startswith("pattern-"):
            failures.append("oscillator/transition")
        elif "instrument" in case["name"]:
            failures.append("instrument")
        elif case["name"].startswith("mix-"):
            failures.append("mixer")
        else:
            failures.append("oscillator")
    return failures


def write_results(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case_dir", type=Path)
    parser.add_argument("--out-dir", type=Path)
    parser.add_argument("--case", action="append", dest="cases")
    parser.add_argument("--include-long", action="store_true")
    parser.add_argument("--skip-reference", action="store_true")
    parser.add_argument("--skip-rtl", action="store_true")
    parser.add_argument("--clock", type=int, default=psg_oracle_render.DEFAULT_CLK)
    parser.add_argument("--pico8", type=Path,
                        default=p8_music_export.DEFAULT_PICO8)
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()

    case_dir = args.case_dir.resolve()
    out_dir = (args.out_dir or case_dir.parent / "matrix").resolve()
    refs, rtl = out_dir / "reference", out_dir / "rtl"
    refs.mkdir(parents=True, exist_ok=True)
    rtl.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((case_dir / "manifest.json").read_text())
    selected = [
        case for case in manifest["cases"]
        if (not args.cases or case["name"] in args.cases)
        and (args.include_long or not case["long"])
    ]
    results = {
        "clock_hz": args.clock,
        "oracle": "PICO-8 MUSIC-mode offline WAV export",
        "cases": [],
    }
    result_path = out_dir / "results.json"
    binary = None
    if not args.skip_rtl:
        binary = psg_oracle_render.build(
            args.clock, ROOT / "build/psg_oracle", 8)

    for index, case in enumerate(selected, 1):
        name = case["name"]
        reference = refs / f"{name}.wav"
        candidate = rtl / f"{name}.wav"
        print(f"[{index}/{len(selected)}] {name}", flush=True)
        if not args.skip_reference or not reference.exists():
            p8_music_export.export(
                case_dir / case["cart"], reference, args.pico8, args.timeout)
        if not args.skip_rtl or not candidate.exists():
            assert binary is not None
            subprocess.run([
                str(binary), "--audio", str((case_dir / case["audio"]).resolve()),
                "--music", "0", "--mask", "7",
                "--samples", str(case["expected_samples"]),
                "--clk", str(args.clock), "--out", str(candidate),
            ], cwd=ROOT, check=True)
        ref_samples = psg_oracle.read_wav(reference)
        rtl_samples = psg_oracle.read_wav(candidate)
        metrics = (psg_oracle.stochastic_metrics(
                       ref_samples, rtl_samples, case["expected_samples"])
                   if case["stochastic"] else
                   psg_oracle.deterministic_metrics(
                       ref_samples, rtl_samples, case["expected_samples"]))
        entry = dict(case)
        entry["metrics"] = metrics
        entry["tolerance"] = tolerance(case)
        entry["classification"] = classify(case, metrics)
        results["cases"].append(entry)
        write_results(result_path, results)
        print("  " + (", ".join(entry["classification"]) or "diagnostic-clean"),
              flush=True)
    print(f"wrote {result_path}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
