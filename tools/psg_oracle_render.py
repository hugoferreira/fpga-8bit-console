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
    # EVERY file psg.sv textually includes, not just psg.sv. Listing only the
    # top file let this cache hand back an executable built from a different
    # revision of the datapath, and this builder feeds
    # tools/psg_oracle_bytecheck.py - the 59/59 gate - and the hardware
    # reference in tools/psg_preview_check.py. A stale binary there does not
    # fail; it agrees with itself and reports a green gate. The same defect in
    # the Makefile's psg_wav targets invented a "159 clocks/sample collapses"
    # result that cost a full investigation.
    sources = (ROOT / "sim/psg_wav.cpp", *sorted(ROOT.glob("rtl/psg*.sv")),
               *sorted(ROOT.glob("rtl/psg*.svh")))
    if binary.exists() and binary.stat().st_mtime >= max(
            source.stat().st_mtime for source in sources):
        return binary
    object_dir.mkdir(parents=True, exist_ok=True)
    multipump = clock_hz == 18_750_000
    cflags = "-O2 -DPSG_FAST_RATIO=6" if multipump else "-O2"
    command = [
        "verilator", "--cc", str(ROOT / "rtl/psg.sv"),
        "--top-module", "psg", f"-I{ROOT / 'rtl'}", "-O3",
        f"-GCLK_HZ={clock_hz}",
        "--x-assign", "fast", "--x-initial", "fast",
        "-Wno-DEFOVERRIDE", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC",
        "--exe", str(ROOT / "sim/psg_wav.cpp"), "-o", "psg_wav",
        "--build", "-j", str(jobs), "-Mdir", str(object_dir),
        "-CFLAGS", cflags,
    ]
    # Multi-pumping belongs only to the accepted iCE40 /6 clock pair. Older
    # 28.125 MHz oracle models and PREVIEW builds retain the single-clock
    # multiplier even though psg_wav.cpp harmlessly drives fastclk for both.
    if multipump:
        command.insert(6, "-GMULTIPUMP=1")
    subprocess.run(command, cwd=ROOT, check=True)
    return binary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--samples", type=int, required=True)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--music", type=int)
    source.add_argument("--sfx", type=int)
    parser.add_argument("--mask", type=int, default=7)
    parser.add_argument("--clock", type=int, default=DEFAULT_CLK)
    parser.add_argument("--build-dir", type=Path,
                        default=ROOT / "build/psg_oracle")
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()
    binary = build(args.clock, args.build_dir, args.jobs)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    launch = (["--sfx", str(args.sfx)] if args.sfx is not None
              else ["--music", str(args.music if args.music is not None else 0)])
    subprocess.run([
        str(binary), "--audio", str(args.audio.resolve()),
        *launch, "--mask", str(args.mask),
        "--samples", str(args.samples), "--clk", str(args.clock),
        "--out", str(args.out.resolve()),
    ], cwd=ROOT, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
