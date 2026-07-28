#!/usr/bin/env python3
"""Grade an iCE40 synthesis netlist by PLACED logic cells, not mapped LUT4s.

An iCE40 logic cell is one LUT4 plus one flip-flop, but the flop can only
share the cell with the LUT that drives its own D input, and only when
that LUT drives nothing else. Every flop that fails the test occupies a
whole cell whose LUT4 half is wasted - and a mapped LUT4 count never
shows those. That gap is why "no measurable gains" kept being reported
against mapped numbers while placed cells stayed flat.

Reports, for a yosys JSON:

  totals      LUT4s, carries, flops, and the packed/unpackable split
  families    unpackable flops grouped by register name, worst first -
              these are the route-through families a microengine or a
              BRAM-backed store can retire wholesale
  cones       LUT4s grouped by the driven net's name, worst first - the
              combinational bulk, where consolidation has to come from
              arithmetic leaving with the register rather than from
              renaming it

CAVEAT, measured 2026-07-28: placed cells are DETERMINISTIC (identical
across five nextpnr seeds - only Fmax moves, by ~2.4 MHz) but they are
not INSENSITIVE. Adding an unused module parameter, which leaves the
pre-mapping netlist bit-for-bit identical at 14,398 cells and 1,610
flops, moved placed cells by 59. That is abc9's LUT covering being
order- and naming-sensitive, not placement noise. So a placed-cell delta
below roughly 60 on this design does not distinguish a real saving from
a mapping reshuffle.

The structural number that does not move:

    yosys -p "read_verilog -Irtl -sv rtl/target_psg.sv; \
              synth_ice40 -top target_psg -run :map_luts; stat"

Judge a change on THAT delta - it counts the gates, carries and flops
the change actually removed - and use placed cells only for the fit
verdict.

Usage: psg_ff_census.py [netlist.json] [--top N]
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

DFF = "SB_DFF"
LUT = "SB_LUT4"
CARRY = "SB_CARRY"


def family(name: str) -> str:
    """The register/net family a signal belongs to.

    yosys names an intermediate net after the whole cell chain that
    produced it - `arp_r_SB_DFFESR_Q_2_D_SB_LUT4_O_...` - so the family
    is everything before the first mapped-cell tag. Without that cut,
    every LUT in a cone counts as its own family and the ranking is
    noise.
    """
    n = name.lstrip("\\$")
    n = n.rsplit(".", 1)[-1]
    n = re.split(r"_SB_(?:LUT4|CARRY|DFF|RAM)", n, maxsplit=1)[0]
    n = re.sub(r"\[\d+(:\d+)?\]$", "", n)
    n = re.sub(r"_\d+$", "", n)
    return n or "<anon>"


def load_top(path: Path) -> dict:
    mods = json.loads(path.read_text())["modules"]
    for name, mod in mods.items():
        if mod.get("attributes", {}).get("top"):
            return mod
    raise SystemExit(f"{path}: no top module")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    top_n = 20
    for a in sys.argv[1:]:
        if a.startswith("--top"):
            top_n = int(a.split("=", 1)[1]) if "=" in a else 20
    path = Path(args[0]) if args else Path("build/targets/psg.json")
    mod = load_top(path)
    cells = mod["cells"]

    # net bit -> the cell that drives it, and how many sinks it has
    driver: dict[int, tuple[str, dict]] = {}
    fanout: Counter[int] = Counter()
    for cname, cell in cells.items():
        for port, bits in cell["connections"].items():
            direction = cell.get("port_directions", {}).get(port)
            for b in bits:
                if not isinstance(b, int):
                    continue
                if direction == "output":
                    driver[b] = (cname, cell)
                else:
                    fanout[b] += 1

    # net bit -> a readable name, for grouping
    label: dict[int, str] = {}
    for nname, net in mod.get("netnames", {}).items():
        if net.get("hide_name"):
            continue
        for b in net["bits"]:
            if isinstance(b, int):
                label.setdefault(b, nname)

    packed = unpacked = 0
    fam_unpacked: Counter[str] = Counter()
    for cname, cell in cells.items():
        if not cell["type"].startswith(DFF):
            continue
        d = cell["connections"].get("D", [])
        bit = d[0] if d and isinstance(d[0], int) else None
        drv = driver.get(bit) if bit is not None else None
        if drv and drv[1]["type"] == LUT and fanout[bit] == 1:
            packed += 1
        else:
            unpacked += 1
            q = cell["connections"].get("Q", [])
            qb = q[0] if q and isinstance(q[0], int) else None
            fam_unpacked[family(label.get(qb, cname))] += 1

    fam_lut: Counter[str] = Counter()
    for cname, cell in cells.items():
        if cell["type"] != LUT:
            continue
        o = cell["connections"].get("O", [])
        ob = o[0] if o and isinstance(o[0], int) else None
        fam_lut[family(label.get(ob, cname))] += 1

    n_lut = sum(1 for c in cells.values() if c["type"] == LUT)
    n_car = sum(1 for c in cells.values() if c["type"] == CARRY)
    n_ff = packed + unpacked
    print(f"{path}")
    print(f"  LUT4 {n_lut}   CARRY {n_car}   FF {n_ff} "
          f"({packed} packed, {unpacked} unpackable = whole cells)")
    print(f"\n  unpackable flops by family (top {top_n}):")
    for name, n in fam_unpacked.most_common(top_n):
        print(f"    {n:5d}  {name}")
    print(f"\n  LUT4s by driven net family (top {top_n}):")
    for name, n in fam_lut.most_common(top_n):
        print(f"    {n:5d}  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
