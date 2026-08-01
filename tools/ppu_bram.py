#!/usr/bin/env python3
"""PPU resource report, read from a yosys JSON netlist.

    make ppu-synth              # runs this
    python3 tools/ppu_bram.py build/ppu/ppu.json

Logic and flip-flops are totals; block RAM is broken down **by consumer**,
because that is the number that decides what the PPU can afford next. The PPU
owns half the hx8k's 32 blocks, and the interesting part is not the total but
the split: storage forced by *capacity* is a fact about the data, while storage
forced by *port width* is a fact about how the array was declared, and only the
latter can be recovered by restructuring.

An SB_RAM40_4K is 4096 bits and at most 16 bits wide (256x16, 512x8, 1024x4,
2048x2). An array wider than 16 bits is therefore split across blocks by width,
and each of those blocks is only as deep as the array - the rest of its
capacity is unreachable. This report names that waste per consumer.

A caveat worth knowing before reading a small delta as a result: yosys's abc9
LUT mapping is reproducible for a given *file list*, but adding an unrelated
module to the command line moves the total by a few LUT4s (6, measured, when
ppu_regs.sv was added and then removed again by `hierarchy`). Treat anything
under ~10 LUT4 as noise, and compare runs made with the same PPU_RTL.
"""
import json
import sys
from collections import Counter

BLOCK_BITS = 4096
BLOCK_MAX_WIDTH = 16
DEVICE_BLOCKS = 32


def consumer(cell_name):
    """The declared array a block RAM cell was inferred from.

    After flattening, a cell is named `<instance>.<array>.<slice>.<block>`, so
    the array is the last path component that is not a number - keeping the
    instance prefix, since `display.ovl` says more than `ovl`.
    """
    parts = [p for p in cell_name.lstrip("$").split(".") if not p.isdigit()]
    return ".".join(parts).split("[")[0]


def main(path):
    with open(path) as f:
        design = json.load(f)

    for mod_name, mod in design["modules"].items():
        if mod.get("attributes", {}).get("blackbox"):
            continue
        cells = Counter(c["type"] for c in mod["cells"].values())
        if not cells:
            continue
        blocks = Counter(
            consumer(name)
            for name, cell in mod["cells"].items()
            if cell["type"] == "SB_RAM40_4K"
        )

        luts = cells.get("SB_LUT4", 0)
        carry = cells.get("SB_CARRY", 0)
        ffs = sum(n for t, n in cells.items() if t.startswith("SB_DFF"))

        print(f"  {mod_name}: {luts} LUT4, {carry} carry, {ffs} FF")
        if not blocks:
            continue
        print("  block RAM by consumer:")
        total = 0
        for name, n in sorted(blocks.items(), key=lambda kv: (-kv[1], kv[0])):
            total += n
            print(f"    {name:<12} {n:>2} block{' ' if n == 1 else 's'}")
        print(f"    {'total':<12} {total:>2} of {DEVICE_BLOCKS} on the hx8k")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/ppu/ppu.json")
