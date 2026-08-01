#!/usr/bin/env python3
"""REGRESSION gate: has the RTL's output changed since the set was frozen?

Read the next paragraph before quoting this gate's result as evidence of
anything. The frozen set IS the reference, and it is a render of OUR OWN RTL -
so a green run proves "nothing changed", NOT "the chip matches PICO-8". Anything
already wrong when the set was frozen stays wrong and stays green, forever.

That is not hypothetical: wave-6 noise ignores the note pitch entirely, and this
gate reported byte-identical 59/59 across every change while it did. It also
ignores each case's `stochastic` flag and byte-compares everything, which is
sound for a regression check and worthless as a fidelity one - a noise case can
never be byte-compared against PICO-8, whose RNG is shared across voices.

For fidelity against real PICO-8 use tools/psg_fidelity_gate.py (statistics and
their pitch dependence) and tools/audio_analysis.py (a full track against a
recording). Keep this one: catching an unintended change is exactly what it is
good at, and it needs no PICO-8 to run.
"""
import argparse, json, subprocess, sys, filecmp
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "build/psg_oracle/cases"
# R.39 is the latest accepted byte-exact checkpoint. Earlier pre-area renders
# are not a valid regression anchor after the adjudicated waveform/schedule
# changes recorded by reduce-psg-ice40-area.
FROZEN = ROOT / "build/psg_oracle/lifetime/rtl"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--clock", type=int, default=28_125_000,
                    help="declared PSG clock (default: frozen 28.125 MHz anchor)")
args = parser.parse_args()
CLOCK = args.clock
OUT = ROOT / f"build/psg_oracle/bytecheck-{CLOCK}"
OUT.mkdir(parents=True, exist_ok=True)

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

print(f"\nunchanged vs frozen {same}/{len(cases)}   differing {diff}   "
      f"no-reference {missing}")
print("this is a REGRESSION result against our own frozen renders - it says "
      "nothing about PICO-8 fidelity (tools/psg_fidelity_gate.py does)")
sys.exit(1 if diff else 0)
