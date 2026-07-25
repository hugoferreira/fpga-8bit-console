#!/usr/bin/env python3
"""Check that rtl/cpu6502_decode.sv and the opcode policy agree.

refactor-cpu-core task 3.2. The decode table is the hardware's opinion of what
each opcode is; `tools/65x02/opcodes.txt` is the registry the assembler and the
conformance harness work from (and, once it lands, `docs/opcodes.md` will be).
Two files can disagree silently forever, so this fails on any disagreement:

  - a documented NMOS opcode in one and not the other,
  - a different mnemonic,
  - a different addressing mode,
  - a row in a slot the allocation policy reserves for 65C02 compatibility,
  - a row in a slot no slice has been assigned.

Extension rows are expected, not errors: the policy in
`tools/65x02/gen_opcodes_md.py` says which slices own which slots, and this
reports what each has claimed.

    python3 tools/65x02/check_decode.py
"""

import re
import sys

sys.path.insert(0, "tools/65x02")
from gen_opcodes_md import RESERVED, EXTENSION            # the allocation policy

DECODE = "rtl/cpu6502_decode.sv"
REGISTRY = "tools/65x02/opcodes.txt"

# Addressing modes the registry names, and the AM_* the table uses for them.
# Several instructions get their own AM_ because their *sequence* is peculiar,
# even though the registry classifies them by operand shape.
AM_TO_MODE = {
    "AM_IMP": "imp", "AM_ACC": "acc", "AM_IMM": "imm",
    "AM_ZP": "zp", "AM_ZPX": "zpx", "AM_ZPY": "zpy",
    "AM_ABS": "abs", "AM_ABSX": "absx", "AM_ABSY": "absy",
    "AM_INDX": "indx", "AM_INDY": "indy", "AM_REL": "rel",
    "AM_PUSH": "imp", "AM_PULL": "imp", "AM_RTS": "imp",
    "AM_RTI": "imp", "AM_BRK": "imp",
    "AM_JSR": "abs", "AM_JMPA": "abs", "AM_JMPI": "ind",
}

ROW = re.compile(
    r"8'h([0-9A-F]{2}):\s*d\s*=\s*row\(\s*(AM_\w+)\s*,\s*(OP_\w+)\s*,"
    r"\s*(\w+)\s*,\s*(\w+)\s*\);\s*//\s*(\S+)"
)


def read_registry(path):
    out = {}
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        out[int(parts[0], 16)] = (parts[1].upper(), parts[2])
    return out


def read_decode(path):
    out = {}
    for line in open(path):
        m = ROW.search(line)
        if not m:
            continue
        op = int(m.group(1), 16)
        if op in out:
            print(f"decode table lists opcode ${op:02X} twice", file=sys.stderr)
            sys.exit(1)
        out[op] = (m.group(6).upper(), AM_TO_MODE.get(m.group(2), m.group(2)))
    return out


def main():
    reg = read_registry(REGISTRY)
    dec = read_decode(DECODE)
    problems = []
    claimed = {}

    for op in sorted(set(reg) | set(dec)):
        if op not in dec:
            problems.append(f"${op:02X} {reg[op][0]} is in the registry but has "
                            f"no row in the decode table")
        elif op not in reg:
            # Not NMOS. Legal only where the allocation policy says so.
            if op in RESERVED:
                problems.append(f"${op:02X} {dec[op][0]} claims a slot reserved "
                                f"for {RESERVED[op]}")
            elif op in EXTENSION:
                claimed.setdefault(EXTENSION[op], []).append((op, dec[op][0]))
            else:
                problems.append(f"${op:02X} {dec[op][0]} claims a slot no slice "
                                f"has been assigned - add it to the policy first")
        else:
            rm, rmode = reg[op]
            dm, dmode = dec[op]
            if rm != dm:
                problems.append(f"${op:02X}: registry says {rm}, decode says {dm}")
            elif rmode != dmode:
                problems.append(f"${op:02X} {rm}: registry says {rmode}, "
                                f"decode says {dmode}")

    if problems:
        print(f"{DECODE} and {REGISTRY} disagree:", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1

    print(f"decode table agrees with {REGISTRY} on all {len(reg)} documented "
          f"opcodes")
    for slice_name, ops in sorted(claimed.items()):
        print(f"  {slice_name}: " +
              ", ".join(f"${o:02X} {m}" for o, m in sorted(ops)))
    n_ext = sum(len(v) for v in claimed.values())
    print(f"  {len(reg)} documented + {n_ext} extension = {len(dec)} implemented; "
          f"{256 - len(dec)} slots trap")
    return 0


if __name__ == "__main__":
    sys.exit(main())
