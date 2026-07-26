#!/usr/bin/env python3
"""Host-only repeatable workspace and translation-time measurement."""

from __future__ import annotations

import json
import statistics
import subprocess
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAASM = ROOT / "build/laasm/laasm"
CELESTE = ROOT / "tests/layout_aware/celeste.la.asm"


def synthetic_source() -> str:
    lines: list[str] = []
    for index in range(120):
        lines.append(f"struct Stress{index} packed")
        for field in range(8):
            lines.append(f"    field{field} : u8")
        lines.append("end")
    for index in range(120):
        lines.append(f"location ptr{index} : ptr Stress{index}")
        lines.append(f"lda [ptr{index} + Stress{index}.field7]")
    return "\n".join(lines) + "\n"


def measure(source: Path, directory: Path) -> dict[str, object]:
    output = directory / "generated.asm"
    source_map = directory / "generated.map.json"
    command = [
        str(LAASM), "--target", "console6502", "--output", str(output),
        "--map", str(source_map), "--stats", str(source),
    ]
    samples: list[float] = []
    stats: dict[str, int] = {}
    for _ in range(21):
        started = time.perf_counter()
        result = subprocess.run(
            command, cwd=ROOT, text=True, capture_output=True, check=True
        )
        samples.append((time.perf_counter() - started) * 1000.0)
        stats = json.loads(result.stdout)
    return {
        "medianMilliseconds": round(statistics.median(samples[1:]), 3),
        "minimumMilliseconds": round(min(samples[1:]), 3),
        **stats,
    }


def main() -> int:
    with tempfile.TemporaryDirectory(
        prefix="laasm-measure-", dir=ROOT / "build"
    ) as raw:
        directory = Path(raw)
        stress = directory / "stress.la.asm"
        stress.write_text(synthetic_source())
        result = {
            "format": 1,
            "hostMeasurementOnly": True,
            "iterations": 20,
            "celeste": measure(CELESTE, directory),
            "synthetic": measure(stress, directory),
        }
    print(json.dumps(result, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
