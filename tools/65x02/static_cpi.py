#!/usr/bin/env python3
"""Static mean CPI of a corpus, weighted by the instructions it actually contains.

refactor-cpu-core task 3.8. The uniform mean over the 151 opcodes says what a
core does on average; this says what it does on *this program*, which is the
number the ISA slices budget against.

The opcode histogram comes from customasm's annotated listing, so the opcodes
are the assembler's, not a re-implementation of its parser. Only lines whose
source text begins with a 6502 mnemonic are counted, which is what separates
instructions from the corpus's data tables.

    make hex GAME=breakout          # or run customasm -f annotated yourself
    python3 tools/65x02/static_cpi.py build/breakout.lst docs/cpu-timing-v2.json ...
"""

import json
import re
import sys

MNEMONICS = set()
for line in open("tools/65x02/opcodes.txt"):
    line = line.strip()
    if line and not line.startswith("#"):
        MNEMONICS.add(line.split()[1].lower())

LINE = re.compile(r"^\s*[0-9a-f]+:\d+\s*\|\s*[0-9a-f]+\s*\|\s*([0-9a-f ]*)\|?\s*;\s*(.*)$")


def histogram(listing):
    hist = {}
    total = 0
    for line in open(listing):
        m = LINE.match(line)
        if not m:
            continue
        data, src = m.group(1).split(), m.group(2).strip()
        if not data:
            continue
        head = src.split()[0].lower().rstrip(":") if src else ""
        if head not in MNEMONICS:
            continue
        op = int(data[0], 16)
        hist[op] = hist.get(op, 0) + 1
        total += 1
    return hist, total


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    listing = argv[1]
    hist, total = histogram(listing)
    if not total:
        print(f"{listing}: no instructions recognised", file=sys.stderr)
        return 1

    print(f"{listing}: {total} instructions, {len(hist)} distinct opcodes\n")
    for table in argv[2:]:
        t = json.load(open(table))["opcodes"]
        missing = sorted(op for op in hist if f"{op:02X}" not in t)
        if missing:
            print(f"{table}: no cycle data for "
                  f"{', '.join(f'${o:02X}' for o in missing)}", file=sys.stderr)
            return 1
        cycles = sum(t[f"{op:02X}"]["cpi_mean"] * n for op, n in hist.items())
        print(f"  {table:<32} static mean CPI {cycles / total:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
