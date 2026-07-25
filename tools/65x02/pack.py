#!/usr/bin/env python3
"""Pack SingleStepTests/65x02 `6502/v1/*.json` into one binary fixture.

The suite is 1,082 MB of JSON and parsing it dominates every run - the
simulation itself is seconds. So this runs ONCE per pinned suite commit, and
`tools/65x02/harness.cpp` reads the packed form from then on.

    python3 tools/65x02/pack.py <suite-dir> <out.fx> [--commit SHA]

The output carries the case count and the suite commit in its header, so any
result the harness prints can state exactly what it was measured against.

Format (little-endian throughout):

    header, 64 bytes
        char magic[8]     "65X02FX\\0"
        u32  version      1
        u32  n_opcodes    256
        char commit[41]   suite commit, nul-padded
        u8   pad[7]

    directory, 256 x 12 bytes
        u32  count        cases for this opcode
        u64  offset       byte offset of the first case, from file start

    cases, packed back to back, variable length, in opcode order

        u16 pc  u8 s  u8 a  u8 x  u8 y  u8 p        initial
        u16 pc  u8 s  u8 a  u8 x  u8 y  u8 p        final
        u8  n   then n x (u16 addr, u8 val)         initial ram
        u8  n   then n x (u16 addr, u8 val)         final ram
        u8  n   then n x (u16 addr, u8 val, u8 rw)  cycles, rw: 0 read 1 write

Cases are read sequentially within an opcode, so they need no per-case index:
the harness's fast-subset mode takes the first N of each opcode and stops.
"""

import argparse
import json
import os
import struct
import sys
import time

MAGIC = b"65X02FX\0"
VERSION = 1
N_OPCODES = 256
HEADER_SIZE = 64
DIRENT_SIZE = 12


def pack_state(st):
    return struct.pack("<HBBBBB", st["pc"], st["s"], st["a"], st["x"], st["y"], st["p"])


def pack_ram(ram):
    if len(ram) > 255:
        raise ValueError(f"ram list of {len(ram)} entries exceeds the u8 count")
    out = [struct.pack("<B", len(ram))]
    for addr, val in ram:
        out.append(struct.pack("<HB", addr, val))
    return b"".join(out)


def pack_cycles(cycles):
    if len(cycles) > 255:
        raise ValueError(f"cycle list of {len(cycles)} entries exceeds the u8 count")
    out = [struct.pack("<B", len(cycles))]
    for addr, val, kind in cycles:
        if val is None:
            raise ValueError("cycle with a null bus value; the format has no encoding for it")
        out.append(struct.pack("<HBB", addr, val, 1 if kind == "write" else 0))
    return b"".join(out)


def pack_case(t):
    return b"".join(
        (
            pack_state(t["initial"]),
            pack_state(t["final"]),
            pack_ram(t["initial"]["ram"]),
            pack_ram(t["final"]["ram"]),
            pack_cycles(t["cycles"]),
        )
    )


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("suite", help="directory holding 00.json .. ff.json")
    ap.add_argument("out", help="fixture to write")
    ap.add_argument("--commit", default="", help="suite commit, recorded in the header")
    ap.add_argument("--max-cases", type=int, default=0,
                    help="keep only the first N cases per opcode (0 = all). For a "
                         "small fixture to develop the harness against; a result "
                         "measured on one is not a sweep.")
    args = ap.parse_args(argv)

    counts = [0] * N_OPCODES
    offsets = [0] * N_OPCODES
    body = HEADER_SIZE + N_OPCODES * DIRENT_SIZE

    tmp = args.out + ".tmp"
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    started = time.time()
    total = 0

    with open(tmp, "wb") as fh:
        fh.seek(body)
        for op in range(N_OPCODES):
            path = os.path.join(args.suite, f"{op:02x}.json")
            if not os.path.exists(path):
                print(f"missing {path}", file=sys.stderr)
                return 1
            with open(path, "rb") as jf:
                cases = json.load(jf)
            if args.max_cases:
                cases = cases[: args.max_cases]
            blob = b"".join(pack_case(t) for t in cases)
            offsets[op] = fh.tell()
            counts[op] = len(cases)
            fh.write(blob)
            total += len(cases)
            if op % 32 == 31:
                print(
                    f"  {op + 1:3d}/256 opcodes, {total:>9,} cases, "
                    f"{time.time() - started:5.1f}s",
                    file=sys.stderr,
                )

        fh.seek(0)
        commit = args.commit.encode()[:41]
        fh.write(
            struct.pack("<8sII41s7x", MAGIC, VERSION, N_OPCODES, commit)
        )
        for op in range(N_OPCODES):
            fh.write(struct.pack("<IQ", counts[op], offsets[op]))

    os.replace(tmp, args.out)
    size = os.path.getsize(args.out)
    print(
        f"{args.out}: {total:,} cases, {size / 1e6:.0f} MB, "
        f"{time.time() - started:.0f}s, suite {args.commit or '(unrecorded)'}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
