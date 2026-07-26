#!/usr/bin/env python3
"""Differential test: a migrated corpus must behave exactly like its original.

    python3 tools/65x02/migrate_check.py before.bin before.lbl after.bin after.lbl

Drives both builds through the same inputs on tools/sim6502.py and compares the
player's position and velocity frame by frame. It exists because celeste's own
suite passed a build whose jumps were a third of their proper height: the suite
checks that physics happens, not that it is unchanged, and a migration needs the
second.

The bug it was written for: the migration tool loaded its mnemonic list from the
documented-151 registry, so once `mov`/`add`/`sub` entered the corpus those
lines became invisible and two instructions either side of one looked adjacent.
`neg16` lost its subtraction, gravity stopped halving at the jump apex, and the
only visible symptom was that Celeste could not jump.
"""
import importlib.util
import re
import sys

spec = importlib.util.spec_from_file_location("tc", "tools/test_celeste.py")
tc = importlib.util.module_from_spec(spec)
sys.path.insert(0, "tools")
spec.loader.exec_module(tc)


def trace(binp, lblp):
    sym = {}
    for line in open(lblp):
        m = re.match(r"al\s+([0-9A-Fa-f]+)\s+\.?(\S+)", line)
        if m:
            sym[m.group(2)] = int(m.group(1), 16)
    r = tc.Rig(open(binp, "rb").read(), sym)
    m = r.cpu.m
    r.frames(2)
    r.buttons = tc.BTN_JUMP
    r.frames(1)
    r.buttons = 0
    for _ in range(85):
        r.frames(1)
        if m[tc.LEVEL] != 31:
            break
    for _ in range(60):
        r.frames(1)
    out = []
    for f in range(24):
        r.buttons = tc.BTN_JUMP if f < 8 else 0
        r.frames(1)
        p = r.player()
        if p is None:
            out.append(None)
            continue
        out.append((tc.s8(r.field(p, tc.O_X)), tc.s8(r.field(p, tc.O_Y)),
                    tc.s16(r.word(p, tc.O_SPDX)), tc.s16(r.word(p, tc.O_SPDY))))
    return out


def main(argv):
    if len(argv) < 5:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    a = trace(argv[1], argv[2])
    b = trace(argv[3], argv[4])
    bad = [(i, x, y) for i, (x, y) in enumerate(zip(a, b)) if x != y]
    rise = max((s[1] for s in a if s), default=0) - min((s[1] for s in a if s), default=0)
    if bad:
        print(f"  DIFFER at {len(bad)} of {len(a)} frames "
              f"(x, y, spdx, spdy):")
        for i, x, y in bad[:6]:
            print(f"    frame {i:>3}  before {x}   after {y}")
        return 1
    print(f"  identical over {len(a)} frames of a jump "
          f"(peak rise {rise} px) - physics unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
