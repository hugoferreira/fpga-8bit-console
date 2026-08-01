#!/usr/bin/env python3
"""End-to-end test of the NEMO port's main loop, driven by fake button presses.

test_nemo.py calls the port's routines directly; this drives the whole program
from the reset vector through its vsync loop, so the state machine, frame sync,
input edge detection and event bus are all exercised.

Usage: test_nemo_loop.py build/nemo.bin build/nemo.lbl
"""
import re
import sys

from sim6502 import Sim6502

# zero-page addresses from src/nemo/memmap.asm
STATE, PZ_IDX, PZ_W, PZ_H = 0x30, 0x20, 0x21, 0x22
GRID_X, GRID_Y, CUR_X, CUR_Y = 0x25, 0x26, 0x28, 0x29
IS_CLEAR = 0x31
SOLUTION, BOARD, PROGRESS = 0x5000, 0x5100, 0x54A0
BTN_L, BTN_R, BTN_U, BTN_D, BTN_O, BTN_X = 1, 2, 4, 8, 0x10, 0x20

FAIL = []


def chk(cond, msg):
    print(f"  {'ok  ' if cond else 'FAIL'} {msg}")
    if not cond:
        FAIL.append(msg)


class Rig:
    def __init__(self, image, sym):
        self.sym = sym
        self.cpu = Sim6502(image)
        self.frame = 0
        self.buttons = 0
        self.ovl = bytearray(2400)
        self.cpu.readers[0x400D] = self._tick
        self.cpu.readers[0x4007] = lambda: self.buttons
        for a in range(0x4000, 0x4200):
            self.cpu.writers.setdefault(a, lambda v: None)
        for off in range(2400):
            self.cpu.writers[0xE000 + off] = self._ovl(off)
        self.cpu.pc = sym["reset"]

    def _tick(self):
        # The frame counter advances as the vsync spin polls it, so each pass
        # through main_loop is one frame.
        self.frame = (self.frame + 1) & 0xFF
        return self.frame

    def _ovl(self, off):
        def w(v):
            self.ovl[off] = v
        return w

    def frames(self, n, budget=8_000_000):
        hits = 0
        for _ in range(budget):
            self.cpu.step()
            if self.cpu.pc == self.sym["main_loop"]:
                hits += 1
                if hits >= n:
                    return
        raise TimeoutError(f"only {hits}/{n} frames in {budget} steps")

    def press(self, mask):
        self.buttons = mask
        self.frames(2)
        self.buttons = 0
        self.frames(2)

    def sub(self, addr, a=0):
        """Call a subroutine without disturbing the running main loop."""
        c = self.cpu
        save = (c.pc, c.a, c.x, c.y, c.s, c.p)
        c.a = a
        c.call(addr)
        ret = c.a
        c.pc, c.a, c.x, c.y, c.s, c.p = save
        return ret

    def lit(self):
        return sum(bin(b).count("1") for b in self.ovl)


def main():
    image = open(sys.argv[1], "rb").read()
    sym = {}
    for line in open(sys.argv[2]):
        m = re.match(r"al\s+([0-9A-Fa-f]+)\s+\.?(\S+)", line)
        if m:
            sym[m.group(2)] = int(m.group(1), 16)

    r = Rig(image, sym)
    m = r.cpu.m

    print("== boot ==")
    r.frames(3)
    chk(m[STATE] == 0, f"reached the select screen (state={m[STATE]})")
    chk(r.lit() > 20, f"select screen drew {r.lit()} pixels")

    print("\n== select ==")
    for _ in range(3):
        r.press(BTN_R)
    chk(m[PZ_IDX] == 3, f"right x3 -> pz_idx={m[PZ_IDX]}")
    r.press(BTN_L)
    chk(m[PZ_IDX] == 2, f"left -> pz_idx={m[PZ_IDX]}")
    for _ in range(4):
        r.press(BTN_L)
    chk(m[PZ_IDX] == 0, f"clamps at the first puzzle (pz_idx={m[PZ_IDX]})")
    for _ in range(2):
        r.press(BTN_R)

    print("\n== start ==")
    r.press(BTN_X)
    w, h = m[PZ_W], m[PZ_H]
    chk(m[STATE] == 1, f"entered play (state={m[STATE]})")
    chk((w, h) == (14, 12), f"puzzle 2 is {w}x{h}")
    chk((m[GRID_X], m[GRID_Y]) == (91 - w * 6, 91 - h * 6),
        f"grid bottom-right anchored at ({m[GRID_X]},{m[GRID_Y]})")

    print("\n== cursor and editing ==")
    r.press(BTN_R)
    r.press(BTN_D)
    chk((m[CUR_X], m[CUR_Y]) == (1, 1),
        f"right+down -> cursor=({m[CUR_X]},{m[CUR_Y]})")
    r.press(BTN_O)
    chk(m[BOARD + w + 1] == 1, "O fills")
    r.press(BTN_O)
    chk(m[BOARD + w + 1] == 0, "O again clears")
    r.press(BTN_X)
    chk(m[BOARD + w + 1] == 2, "X marks")
    r.press(BTN_X)
    chk(m[BOARD + w + 1] == 0, "X again clears")

    print("\n== cursor clamping ==")
    for _ in range(20):
        r.press(BTN_L)
    chk(m[CUR_X] == 0, f"clamped left (cur_x={m[CUR_X]})")
    for _ in range(20):
        r.press(BTN_R)
    chk(m[CUR_X] == w - 1, f"clamped right (cur_x={m[CUR_X]}, w-1={w - 1})")
    for _ in range(20):
        r.press(BTN_U)
    chk(m[CUR_Y] == 0, f"clamped up (cur_y={m[CUR_Y]})")
    for _ in range(20):
        r.press(BTN_D)
    chk(m[CUR_Y] == h - 1, f"clamped down (cur_y={m[CUR_Y]})")

    print("\n== win: leave one cell for the game to place ==")
    last = None
    for y in range(h):
        for x in range(w):
            if m[SOLUTION + y * w + x] == 1:
                last = (x, y)
    lx, ly = last
    for y in range(h):
        for x in range(w):
            m[BOARD + y * w + x] = 1 if m[SOLUTION + y * w + x] == 1 else 0
    m[BOARD + ly * w + lx] = 0
    r.sub(sym["match_all"])
    chk(m[IS_CLEAR] == 0, "one cell short is not a win")

    m[CUR_X], m[CUR_Y] = lx, ly
    r.press(BTN_O)
    chk(m[BOARD + ly * w + lx] == 1, f"game filled the last cell ({lx},{ly})")
    chk(m[IS_CLEAR] == 1, "win detected through the event bus")
    chk(m[STATE] == 2, f"entered the cleared state (state={m[STATE]})")
    chk(bool(m[PROGRESS] & 0x04),
        f"progress bit set: {[hex(b) for b in m[PROGRESS:PROGRESS + 7]]}")

    print("\n== dismiss and reload ==")
    r.press(BTN_X)
    chk(m[STATE] == 0, f"back to select (state={m[STATE]})")
    chk(r.sub(sym["progress_get"], 2) != 0, "progress_get(2) = completed")
    chk(r.sub(sym["progress_get"], 5) == 0, "progress_get(5) = not completed")

    m[PZ_IDX] = 9
    r.sub(sym["puzzle_load"])
    chk((m[PZ_W], m[PZ_H]) == (15, 15), f"puzzle 9 is {m[PZ_W]}x{m[PZ_H]}")
    chk(all(m[BOARD + i] == 0 for i in range(225)), "board cleared on load")
    chk(m[IS_CLEAR] == 0, "is_clear reset on load")

    print("\n== 400 idle frames (exercises the blink redraw path) ==")
    before = m[STATE]
    r.frames(400)
    chk(m[STATE] == before, f"stable in state {m[STATE]}")

    print()
    if FAIL:
        print(f"FAILED: {len(FAIL)} check(s)")
        return 1
    print("all main-loop checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
