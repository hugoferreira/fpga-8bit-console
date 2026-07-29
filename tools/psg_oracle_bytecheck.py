#!/usr/bin/env python3
"""Render every oracle case's RTL side at the hardware clock and byte-compare
it against the frozen adopt-exact renders.

This is the "hardware is bit-identical" gate, and it needs no PICO-8: the
frozen set IS the reference. tools/psg_oracle_matrix.py cannot serve here
because it re-exports the PICO-8 reference (which fails headless) unless the
reference file already exists.
"""
import json, subprocess, sys, filecmp
from pathlib import Path

ROOT = Path("/Users/bytter/Development/iot/fpga/fpga-8bit-console")
CASES = ROOT / "build/psg_oracle/cases"
FROZEN = ROOT / "build/psg_oracle/adopt-exact/rtl"
OUT = ROOT / "build/psg_oracle/bytecheck"
OUT.mkdir(parents=True, exist_ok=True)
CLOCK = 28_125_000

sys.path.insert(0, str(ROOT / "tools"))
import psg_oracle_render

binary = psg_oracle_render.build(CLOCK, ROOT / "build/psg_oracle", 8)
manifest = json.loads((CASES / "manifest.json").read_text())
cases = [c for c in manifest["cases"] if not c["long"]]

same = diff = missing = 0
for i, case in enumerate(cases, 1):
    name = case["name"]
    frozen = FROZEN / f"{name}.wav"
    cand = OUT / f"{name}.wav"
    if not frozen.exists():
        print(f"[{i}/{len(cases)}] {name}: NO FROZEN REFERENCE")
        missing += 1
        continue
    subprocess.run([
        str(binary), "--audio", str((CASES / case["audio"]).resolve()),
        "--music", "0", "--mask", "7",
        "--samples", str(case["expected_samples"]),
        "--clk", str(CLOCK), "--out", str(cand),
    ], cwd=ROOT, check=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if filecmp.cmp(frozen, cand, shallow=False):
        same += 1
    else:
        diff += 1
        print(f"[{i}/{len(cases)}] {name}: BYTES DIFFER")

print(f"\nbyte-identical {same}/{len(cases)}   differing {diff}   "
      f"no-reference {missing}")
sys.exit(1 if diff else 0)
