#!/usr/bin/env python3
"""Build and run the PSG-only Verilator model at the hardware oracle clock."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CLK = 28_125_000


def build(clock_hz: int, build_dir: Path, jobs: int) -> Path:
    object_dir = build_dir / f"obj_{clock_hz}"
    binary = object_dir / "psg_wav"
    sources = (ROOT / "rtl/psg.sv", ROOT / "sim/psg_wav.cpp")
    if binary.exists() and binary.stat().st_mtime >= max(
            source.stat().st_mtime for source in sources):
        return binary
    object_dir.mkdir(parents=True, exist_ok=True)
    command = [
        "verilator", "--cc", str(ROOT / "rtl/psg.sv"),
        "--top-module", "psg", f"-I{ROOT / 'rtl'}", "-O3",
        f"-GCLK_HZ={clock_hz}",
        "--x-assign", "fast", "--x-initial", "fast",
        "-Wno-DEFOVERRIDE", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC",
        "--exe", str(ROOT / "sim/psg_wav.cpp"), "-o", "psg_wav",
        "--build", "-j", str(jobs), "-Mdir", str(object_dir),
        "-CFLAGS", "-O2",
    ]
    subprocess.run(command, cwd=ROOT, check=True)
    return binary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--samples", type=int, required=True)
    parser.add_argument("--music", type=int, default=0)
    parser.add_argument("--mask", type=int, default=7)
    parser.add_argument("--clock", type=int, default=DEFAULT_CLK)
    parser.add_argument("--build-dir", type=Path,
                        default=ROOT / "build/psg_oracle")
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()
    binary = build(args.clock, args.build_dir, args.jobs)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        str(binary), "--audio", str(args.audio.resolve()),
        "--music", str(args.music), "--mask", str(args.mask),
        "--samples", str(args.samples), "--clk", str(args.clock),
        "--out", str(args.out.resolve()),
    ], cwd=ROOT, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
