#!/usr/bin/env python3
"""Differential test for a migrated corpus, without needing to know the game.

    python3 tools/65x02/corpus_diff.py before.bin before.lbl after.bin after.lbl \
        [--frames N] [--loop main_loop]

Runs both builds on tools/sim6502.py with identical stubbed hardware and
compares two things after every frame:

  - **zero page**, which is where this console's programs keep their variables
    and which sits at fixed addresses in any build;
  - **the stream of writes to the peripherals**, in order - every sprite, tile,
    overlay and sound register the program touches. That is the program's
    entire observable output, so two builds that produce the same stream do the
    same thing.

Neither depends on where the code ended up, which matters: a migration changes
the instruction encoding, so labels move and anything compared by absolute
address above zero page is comparing the layout rather than the behaviour. An
earlier version of this file compared all written RAM and reported a "failure"
in breakout's particle pool that was nothing but uninitialised image bytes
shifting with the code.

That artefact turned out to be worth chasing anyway. The pool was uninitialised
because it sat *inside* the program image - `PPX = $2100`, in the middle of
`audio_data` ($1C12-$2E11) - so it read its "live" flags out of sfx bytes, and
writing to it overwrote sfx 14-16 and 18-20 every frame. The scratch has since
moved to $8000 (see `src/isa/console.asm`) and is cleared at startup. The
lesson for this tool: a divergence it reports is not automatically a migration
defect, but it is always *something*.

To reproduce the breakout run, `make corpus-diff-breakout`, or by hand:

    git show f5be1c7:src/main.asm > /tmp/ref/main.asm   # last pre-ISA breakout
    ln -s $PWD/src/isa /tmp/ref/isa; ln -s ... the three data .asm files
    customasm /tmp/ref/main.asm -f binary -o pre.bin -- -f symbols -o pre.sym
    python3 tools/sym_to_lbl.py pre.sym pre.lbl          # and the same for now
    python3 tools/65x02/corpus_diff.py pre.bin pre.lbl now.bin now.lbl

This is the general form of tools/65x02/migrate_check.py, which knows celeste's
object layout and reports in terms of position and speed. Use this one for a
corpus that has no functional test of its own, which is why it exists: breakout
had only a screenshot, and a screenshot cannot tell a timing artefact from a
defect.

The hardware stubs are deliberately deterministic - in particular the LFSR at
`SPR_RND` is a fixed sequence driven by read count, not by cycle timing. Both
builds therefore see the same "random" numbers at the same logical points, so a
difference is a difference in the program and never in the seed. On real
hardware the LFSR free-runs, which is exactly why screenshots of two builds
differ in the dust and prove nothing.
"""

import re
import sys

sys.path.insert(0, "tools")
from sim6502 import Sim6502            # noqa: E402

SPR_BTN, SPR_FRAME, SPR_RND = 0x4007, 0x400D, 0x400F
MMIO = [(0x4000, 0x4200), (0xE000, 0xEA00), (0xF000, 0xF800)]


class Rig:
    """A console with its peripherals stubbed, deterministically."""

    def __init__(self, image, sym, loop):
        self.cpu = Sim6502(image)
        self.sym = sym
        self.frame = 0
        self.rnd = 1
        self.buttons = 0
        c = self.cpu
        c.readers[SPR_FRAME] = self._tick
        c.readers[SPR_BTN] = lambda: self.buttons
        c.readers[SPR_RND] = self._rnd
        for lo, hi in MMIO:
            for a in range(lo, hi):
                c.readers.setdefault(a, lambda: 0)
                c.writers.setdefault(a, lambda v: None)
        c.pc = sym["reset"] if "reset" in sym else sym[loop]
        self.loop = sym[loop]
        # The peripheral write stream: the program's observable output.
        self.io = []
        inner = c.wr

        def wr(a, v, _inner=inner):
            a &= 0xFFFF
            if any(lo <= a < hi for lo, hi in MMIO):
                self.io.append((a, v & 0xFF))
            _inner(a, v)
        c.wr = wr

    def _tick(self):
        self.frame = (self.frame + 1) & 0xFF
        return self.frame

    def _rnd(self):
        self.rnd = (self.rnd * 5 + 13) & 0xFF
        return self.rnd

    def frames(self, n, budget=60_000_000):
        hits = 0
        for _ in range(budget):
            self.cpu.step()
            if self.cpu.pc == self.loop:
                hits += 1
                if hits > n:
                    return True
        return False

    def zp(self):
        return bytes(self.cpu.m[0:0x100])


def load_sym(path):
    sym = {}
    for line in open(path):
        m = re.match(r"al\s+([0-9A-Fa-f]+)\s+\.?(\S+)", line)
        if m:
            sym[m.group(2)] = int(m.group(1), 16)
    return sym


def main(argv):
    if len(argv) < 5:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    frames = int(argv[argv.index("--frames") + 1]) if "--frames" in argv else 40
    loop = argv[argv.index("--loop") + 1] if "--loop" in argv else "main_loop"
    keys = [a for a in argv[1:5]]

    a = Rig(open(keys[0], "rb").read(), load_sym(keys[1]), loop)
    b = Rig(open(keys[2], "rb").read(), load_sym(keys[3]), loop)

    # a fixed input script, applied identically to both
    script = {0: 0x00, 8: 0x10, 12: 0x00, 18: 0x02, 26: 0x01, 32: 0x00, 38: 0x10}

    for f in range(frames):
        if f in script:
            a.buttons = b.buttons = script[f]
        if not a.frames(1) or not b.frames(1):
            print(f"  a build stopped reaching {loop} at frame {f}", file=sys.stderr)
            return 1
        za, zb = a.zp(), b.zp()
        if za != zb:
            diff = [i for i in range(0x100) if za[i] != zb[i]]
            print(f"  DIFFER at frame {f}: {len(diff)} zero-page bytes")
            names = {v: n for n, v in a.sym.items() if v < 0x100}
            for i in diff[:12]:
                print(f"    ${i:02X} before ${za[i]:02X} after ${zb[i]:02X}"
                      f"  ({names.get(i, '')})")
            return 1
        if a.io != b.io:
            k = next(i for i in range(min(len(a.io), len(b.io)) + 1)
                     if i >= len(a.io) or i >= len(b.io) or a.io[i] != b.io[i])
            print(f"  DIFFER at frame {f}: peripheral write {k} of "
                  f"{len(a.io)}/{len(b.io)}")
            for i in range(max(0, k - 2), min(k + 3, max(len(a.io), len(b.io)))):
                x = f"${a.io[i][0]:04X}=${a.io[i][1]:02X}" if i < len(a.io) else "-"
                y = f"${b.io[i][0]:04X}=${b.io[i][1]:02X}" if i < len(b.io) else "-"
                print(f"    {i:>6}  before {x:<14} after {y}"
                      f"{'   <-- here' if i == k else ''}")
            return 1
        a.io.clear()
        b.io.clear()
    print(f"  identical over {frames} frames of scripted input: zero page and "
          f"every peripheral write - behaviour unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
