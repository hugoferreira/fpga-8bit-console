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
        transition = next(c for c in cases
                          if c["name"] == "transition-pitch")
        gate = psg_oracle_matrix.tolerance(transition)
        check(gate["correlation_min"] == 0.999
              and gate["nrmse_max"] == 0.03,
              "transition probes carry the tightened deterministic gate")
        pattern = next(c for c in cases if c["name"] == "pattern-chain")
        check(psg_oracle_matrix.tolerance(pattern) == gate,
              "pattern handoff carries the tightened transition gate")
        for composite_name in ("effect-1-slide", "sfx-instrument",
                               "sfx-instrument-pitch-waveform"):
            composite = next(c for c in cases
                             if c["name"] == composite_name)
            composite_gate = psg_oracle_matrix.tolerance(composite)
            check(composite_gate["correlation_min"] == 0.999
                  and composite_gate["nrmse_max"] == 0.03,
                  f"{composite_name}: strict transition gate")
        for drop_name in ("effect-3-drop", "effect-drop-once"):
            drop = next(c for c in cases if c["name"] == drop_name)
            drop_gate = psg_oracle_matrix.tolerance(drop)
            check(drop_gate["correlation_min"] == 0.995
                  and drop_gate["nrmse_max"] == 0.08,
                  f"{drop_name}: strict drop gate")
        for secondary_name in ("filter-detune-high", "waveform-instrument"):
            secondary = next(c for c in cases
                             if c["name"] == secondary_name)
            secondary_gate = psg_oracle_matrix.tolerance(secondary)
            check(secondary_gate["fitted_gain_min"] == 0.99
                  and secondary_gate["fitted_gain_max"] == 1.01
                  and secondary_gate["nrmse_max"] == 0.03,
                  f"{secondary_name}: strict secondary-oscillator gate")
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
