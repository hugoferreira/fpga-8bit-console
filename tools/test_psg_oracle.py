#!/usr/bin/env python3
"""Unit tests for the PSG oracle generator and WAV diagnostics."""

from __future__ import annotations

import array
import json
from pathlib import Path
import tempfile
import wave

import psg_oracle
import psg_oracle_matrix


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def write_wav(path: Path, samples: list[int]) -> None:
    data = array.array("h", samples)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(psg_oracle.RATE)
        wav.writeframes(data.tobytes())


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="test-psg-oracle.") as raw:
        root = Path(raw)
        manifest = psg_oracle.generate(root)
        cases = manifest["cases"]
        check(len(cases) >= 30, "expected a broad generated corpus")
        check(any(c["stochastic"] for c in cases), "noise cases are marked")
        check(any(c["long"] for c in cases), "loop-cap case is marked long")
        names = {case["name"] for case in cases}
        check({"transition-pitch", "transition-volume",
               "transition-waveform"} <= names,
              "isolated transition probes are generated")
        check({"effect-slide-once", "effect-slide-fractional",
               "effect-drop-once", "filter-reverb-impulse",
               "filter-dampen-impulse", "sfx-instrument-pitch",
               "sfx-instrument-volume",
               "sfx-instrument-waveform", "filter-detune-low",
               "filter-detune-high"} <= names,
              "remaining-fidelity isolation probes are generated")
        check({"filter-reverb-2", "filter-dampen-2",
               "filter-dampen-reverb"} <= names,
              "level-2 and filter-order probes are generated")
        for case in cases:
            gate = psg_oracle_matrix.tolerance(case)
            if case["stochastic"]:
                check("mismatches_max" not in gate
                      and gate["rms_mean_relative_max"] == 0.10,
                      f"{case['name']}: statistical gate at the shared-RNG "
                      "boundary")
            else:
                check(gate == {"duration_samples": 0, "mismatches_max": 0},
                      f"{case['name']}: deterministic cases gate on exact "
                      "byte equality")
        impulse = next(c for c in cases
                       if c["name"] == "filter-reverb-impulse")
        check(impulse["alignment_max_shift"] == 256,
              "impulse alignment rejects lower-energy repeat aliases")
        for case in cases:
            audio = (root / case["audio"]).read_bytes()
            check(len(audio) == 4608, f"{case['name']}: audio image size")
            cart = (root / case["cart"]).read_text(encoding="ascii")
            check("__sfx__" in cart and "__music__" in cart,
                  f"{case['name']}: cartridge sections")

        state = 1
        signal = []
        for _ in range(12_000):
            state = (1103515245 * state + 12345) & 0x7fffffff
            signal.append((state >> 16) - 16384)
        shifted = [0] * 37 + [int(x * 0.75 + 120) for x in signal]
        metrics = psg_oracle.deterministic_metrics(signal, shifted, len(signal))
        check(abs(metrics["alignment_samples"] + 37) <= 1,
              f"alignment: {json.dumps(metrics)}")
        check(metrics["nrmse"] < 1e-4, f"gain/DC fit: {json.dumps(metrics)}")
        check(metrics["mismatches"] > 0,
              "a rescaled signal is not byte-exact")
        same = psg_oracle.deterministic_metrics(signal, list(signal),
                                                len(signal))
        check(same["mismatches"] == 0
              and same["aligned_overlap"] == len(signal),
              "an identical signal is byte-exact over the full overlap")

        a = root / "a.wav"
        b = root / "b.wav"
        write_wav(a, signal)
        write_wav(b, signal)
        check(psg_oracle.read_wav(a) == psg_oracle.read_wav(b),
              "WAV round trip")
        noise = psg_oracle.stochastic_metrics(signal, signal, len(signal))
        check(noise["relative_error"]["rms_mean"] == 0,
              "identical stochastic signal")
    print("psg oracle tests: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
