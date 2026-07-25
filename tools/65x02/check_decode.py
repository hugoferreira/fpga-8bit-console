#!/usr/bin/env python3
"""Check that rtl/cpu6502_decode.sv and the opcode registry agree.

refactor-cpu-core task 3.2. The decode table is the hardware's opinion of what
each opcode is; `tools/65x02/opcodes.txt` is the registry the assembler and the
conformance harness work from (and, once it lands, `docs/opcodes.md` will be).
Two files can disagree silently forever, so this fails on any disagreement:

  - an opcode in one and not the other,
  - a different mnemonic,
  - a different addressing mode.

    python3 tools/65x02/check_decode.py
"""

import re
import sys

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

    for op in sorted(set(reg) | set(dec)):
        if op not in dec:
            problems.append(f"${op:02X} {reg[op][0]} is in the registry but has "
                            f"no row in the decode table")
        elif op not in reg:
            problems.append(f"${op:02X} {dec[op][0]} has a decode row but is not "
                            f"in the registry")
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

    print(f"decode table agrees with {REGISTRY} on all {len(reg)} opcodes; "
          f"the other {256 - len(reg)} slots trap")
    return 0


if __name__ == "__main__":
    sys.exit(main())
