#!/usr/bin/env python3
"""Where a corpus's CPU cycles go, and what more bus bandwidth would buy.

The question this answers is whether pipelining is worth anything. It is not,
if every cycle is already a byte crossing a bus that carries one byte per
cycle - and for this core it very nearly is.

    make cpu-bandwidth GAME=breakout

Data accesses are modelled from the addressing mode and destination in
`rtl/cpu6502_decode.sv`, NOT derived from the measured CPI: deriving them from
CPI forces every instruction onto the bus floor by construction and hides
exactly the overhead worth finding.
"""
import json
import re
import sys

DECODE = "rtl/cpu6502_decode.sv"
REGISTRY = "tools/65x02/opcodes.txt"


def load_registry():
    nbytes, mnemonics = {}, set()
    for line in open(REGISTRY):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        p = line.split()
        nbytes[int(p[0], 16)] = int(p[3])
        mnemonics.add(p[1].lower())
    return nbytes, mnemonics


def load_decode():
    am, op, dst = {}, {}, {}
    pat = re.compile(r"8'h([0-9A-F]{2}):\s*d\s*=\s*row\(\s*(AM_\w+)\s*,\s*(OP_\w+)"
                     r"\s*,\s*(\w+)\s*,\s*(\w+)")
    for line in open(DECODE):
        m = pat.search(line)
        if m:
            o = int(m.group(1), 16)
            am[o], op[o], dst[o] = m.group(2), m.group(3), m.group(5)
    return am, op, dst


def accesses(o, am, op, dst):
    """Data accesses an opcode performs, excluding instruction fetch."""
    mode = am[o]
    rmw = dst[o] == "D_MEM" and op[o] != "OP_PASS"
    mem = 2 if rmw else 1                      # read, write, or read+write
    if mode in ("AM_IMP", "AM_ACC", "AM_IMM", "AM_REL", "AM_JMPA"):
        return 0
    if mode in ("AM_ZP", "AM_ZPX", "AM_ZPY", "AM_ABS", "AM_ABSX", "AM_ABSY"):
        return mem
    if mode in ("AM_INDX", "AM_INDY"):
        return 2 + mem                         # pointer low, pointer high, data
    return {"AM_PUSH": 1, "AM_PULL": 1, "AM_JSR": 2, "AM_RTS": 2,
            "AM_RTI": 3, "AM_BRK": 5, "AM_JMPI": 2}[mode]


def histogram(listing, mnemonics):
    line_re = re.compile(r"^\s*[0-9a-f]+:\d+\s*\|\s*[0-9a-f]+\s*\|"
                         r"\s*([0-9a-f ]*)\|?\s*;\s*(.*)$")
    hist = {}
    for line in open(listing):
        m = line_re.match(line)
        if not m:
            continue
        data, src = m.group(1).split(), m.group(2).strip()
        if not data or not src:
            continue
        if src.split()[0].lower().rstrip(":") not in mnemonics:
            continue
        o = int(data[0], 16)
        hist[o] = hist.get(o, 0) + 1
    return hist


def main(argv):
    if len(argv) < 3:
        print("usage: bandwidth.py <listing> <cycle-table.json>", file=sys.stderr)
        return 2
    nbytes, mnemonics = load_registry()
    am, op, dst = load_decode()
    cpi = json.load(open(argv[2]))["opcodes"]
    hist = histogram(argv[1], mnemonics)
    total = sum(hist.values())
    if not total:
        print(f"{argv[1]}: no instructions recognised", file=sys.stderr)
        return 1

    rows = []
    for o, n in hist.items():
        b = 1 if am[o] == "AM_BRK" else nbytes[o]   # BRK skips its signature unread
        rows.append((o, n, b, accesses(o, am, op, dst), cpi[f"{o:02X}"]["cpi_mean"]))

    def w(f):
        return sum(f(b, d, c) * n for _, n, b, d, c in rows) / total

    xfer = {"AM_REL", "AM_JMPA", "AM_JMPI", "AM_JSR", "AM_RTS", "AM_RTI", "AM_BRK"}
    n_x = sum(n for o, n in hist.items() if am[o] in xfer)
    n_rel = sum(n for o, n in hist.items() if am[o] == "AM_REL")

    print(f"{argv[1]}: {total} instructions\n")
    print(f"  instruction bytes / instruction   {w(lambda b, d, c: b):.3f}")
    print(f"  data accesses / instruction       {w(lambda b, d, c: d):.3f}")
    print(f"  bus accesses / instruction        {w(lambda b, d, c: b + d):.3f}"
          f"   <- one-port floor")
    print(f"  CPI now                           {w(lambda b, d, c: c):.3f}")
    over = [(n, c - b - d) for _, n, b, d, c in rows if c > b + d + 1e-6]
    print(f"  above the floor                   "
          f"{sum(n for n, _ in over)}/{total} instructions, "
          f"{sum(n * x for n, x in over) / total:.3f} CPI\n")
    print(f"  fetch is {100 * w(lambda b, d, c: b) / w(lambda b, d, c: b + d):.0f}%"
          f" of all bus traffic\n")
    print( "  ceilings if fetch stops competing with data:")
    print(f"    16-bit fetch    ceil(b/2)+d     {w(lambda b, d, c: -(-b // 2) + d):.3f}")
    print(f"    second port     1+d             {w(lambda b, d, c: 1 + d):.3f}")
    print(f"    second port     max(1,d)        {w(lambda b, d, c: max(1, d)):.3f}\n")
    print(f"  control transfers  {n_x}/{total} = {100 * n_x / total:.1f}%"
          f"  (branches {100 * n_rel / total:.1f}%)")
    flush = (n_rel * 0.5 + (n_x - n_rel)) / total
    for pen in (1, 2, 3):
        print(f"    flush penalty {pen} cycle -> +{flush * pen:.3f} CPI")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
