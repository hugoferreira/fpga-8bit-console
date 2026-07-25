#!/usr/bin/env python3
"""Gowin area report, read from a yosys JSON netlist.

    make tangnano20k-synth      # runs this
    python3 tools/gowin_stat.py build/gowin/top.json

The counterpart of tools/ppu_bram.py for the Tang Nano 20K's GW2AR-18C.

**This is a pre-check, not the authority.** `nextpnr-himbaechel` prints its own
"Device utilisation" after packing and that is the number to quote; it differs
from this one because nextpnr packs first (LUT1/2/3 become LUT4 bels, ALU cells
get padded to fill a chain). The two agreed on the constraint that matters -
45 of 46 block RAMs - and differed by ~1% on LUT4 and by 600 on ALU. This target
exists because it answers "does it still fit" in 40 seconds where the full
place-and-route takes minutes.

Denominators are nextpnr's own, so the two reports can be read side by side.
Note LUT4 and ALU have *different* totals: an ALU cell occupies a particular
position in a slice, so the device has 20736 LUT4 bels and 15552 ALU bels, and
they are not interchangeable. Adding them up gives a number that means nothing.

Block RAM is broken down by consumer, which the other report does not do, and
which is the interesting column here: it is what says the 64 KB main memory is
32 of the 45 blocks in use.
"""
import json
import sys
from collections import Counter

# GW2AR-LV18QN88C8/I7. Totals as nextpnr-himbaechel reports them for this part.
DEVICE = "GW2AR-18C"
LIMITS = {
    "LUT4": 20736, "ALU": 15552, "DFF": 15552, "BSRAM": 46,
    "MULT18X18": 48, "MULT9X9": 96, "rPLL": 2, "IOB": 384,
    "RAM16SDP4": 648,
}

BSRAM = ("SP", "SPX9", "DP", "DPB", "DPX9B", "SDP", "SDPB", "SDPX9B",
         "ROM", "ROMX9", "pROM")
IOB = ("IBUF", "OBUF", "IOBUF", "TBUF")


def consumer(cell_name):
    """The declared array a block RAM cell was inferred from.

    After flattening, a cell is named `<instance>.<array>.<slice>.<block>`, so
    the array is the last path component that is not a number - keeping the
    instance prefix, since `psg0.aram` says more than `aram`.
    """
    parts = [p for p in cell_name.lstrip("$").split(".") if not p.isdigit()]
    return ".".join(parts).split("[")[0]


def row(label, used, total):
    return f"    {label:<12} {used:>6} of {total:<6} {100.0 * used / total:5.1f}%"


def main(path):
    with open(path) as f:
        design = json.load(f)

    for mod_name, mod in design["modules"].items():
        if mod.get("attributes", {}).get("blackbox"):
            continue
        cells = Counter(c["type"] for c in mod["cells"].values())
        if not cells:
            continue

        counted = {
            # yosys emits LUT1..LUT4; every one of them occupies a LUT4 bel.
            "LUT4": sum(n for t, n in cells.items()
                        if t in ("LUT1", "LUT2", "LUT3", "LUT4")),
            "ALU": cells.get("ALU", 0),
            "DFF": sum(n for t, n in cells.items()
                       if t.startswith("DFF") or t.startswith("DL")),
            "BSRAM": sum(n for t, n in cells.items() if t in BSRAM),
            "MULT18X18": cells.get("MULT18X18", 0),
            "MULT9X9": cells.get("MULT9X9", 0),
            "rPLL": cells.get("rPLL", 0) + cells.get("PLLVR", 0),
            "IOB": sum(n for t, n in cells.items() if t in IOB),
            "RAM16SDP4": sum(n for t, n in cells.items()
                             if t.startswith("RAM16S")),
        }

        print(f"  {mod_name} on the {DEVICE} (yosys estimate; "
              f"nextpnr's own report is the authority):")
        for label, total in LIMITS.items():
            if counted[label] or label in ("LUT4", "ALU", "DFF", "BSRAM"):
                print(row(label, counted[label], total))

        blocks = Counter(consumer(name) for name, cell in mod["cells"].items()
                         if cell["type"] in BSRAM)
        if not blocks:
            continue
        print("    block RAM by consumer:")
        for name, n in sorted(blocks.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"      {name:<34} {n:>2} block{'' if n == 1 else 's'}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/gowin/top.json")
