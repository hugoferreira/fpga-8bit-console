#!/usr/bin/env python3
"""Test the NEMO port's assembled code against an independent model.

Runs build/nemo.bin on tools/sim6502.py, calls the port's own routines, and
compares the results with clue derivation done separately in Python. Also
renders the overlay so the screen can be eyeballed.

Usage: test_nemo.py build/nemo.bin build/nemo.lbl
"""
import re
import sys

from sim6502 import Sim6502, UndocumentedOpcode

FAIL = []


def check(cond, msg):
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        FAIL.append(msg)


def load_labels(path):
    """ld65 -Ln output: 'al 001234 .name'."""
    sym = {}
    for line in open(path):
        m = re.match(r"al\s+([0-9A-Fa-f]+)\s+\.?(\S+)", line)
        if m:
            sym[m.group(2)] = int(m.group(1), 16)
    return sym


def mkcpu(image):
    cpu = Sim6502(image)
    # Fake the PPU: a stable frame counter and no buttons. The routines under
    # test never touch these, but reset does.
    cpu.readers[0x400D] = lambda: 0
    cpu.readers[0x4007] = lambda: 0
    for a in range(0x4000, 0x4200):
        cpu.writers.setdefault(a, lambda v: None)
    return cpu


def runs_of(cells):
    """Independent model: lengths of consecutive filled runs."""
    out, n = [], 0
    for c in cells:
        if c == 1:
            n += 1
        else:
            if n:
                out.append(n)
            n = 0
    if n:
        out.append(n)
    return out


def main():
    binpath, lblpath = sys.argv[1], sys.argv[2]
    image = open(binpath, "rb").read()
    sym = load_labels(lblpath)
    need = ["puzzle_load", "nemo_w", "nemo_h", "nemo_bitmaps", "reset",
            "clues_derive", "match_all", "board_set", "draw_board",
            "render_init", "grid_setup", "mul8"]
    missing = [n for n in need if n not in sym]
    if missing:
        raise SystemExit(f"labels missing from {lblpath}: {missing}")

    SOLUTION, BOARD, ROWOFF = 0x5000, 0x5100, 0x5200
    CLUE_H, CLUE_V = 0x5220, 0x5320
    MATCH_H, MATCH_V = 0x5420, 0x5430
    pz_idx, pz_w, pz_h, is_clear = 0x20, 0x21, 0x22, 0x31
    t1, t2, t3 = 0x01, 0x02, 0x03

    print("== mul8 ==")
    cpu = mkcpu(image)
    for a, b in ((15, 15), (7, 14), (13, 13), (0, 9), (1, 200), (30, 8)):
        cpu.m[0x16], cpu.m[0x17] = a, b
        cpu.call(sym["mul8"])
        got = cpu.m[0x18] | (cpu.m[0x19] << 8)
        check(got == a * b, f"{a}*{b} = {got}")

    print("\n== per-puzzle: expand, ROWOFF, clue derivation ==")
    bad = 0
    for idx in range(50):
        cpu = mkcpu(image)
        cpu.call(sym["render_init"])
        cpu.m[pz_idx] = idx
        cpu.call(sym["puzzle_load"])

        w, h = cpu.m[pz_w], cpu.m[pz_h]
        ew = image[sym["nemo_w"] - 0x0000 + idx] if False else None
        ew = cpu.m[sym["nemo_w"] + idx]
        eh = cpu.m[sym["nemo_h"] + idx]
        if (w, h) != (ew, eh):
            print(f"  FAIL puzzle {idx}: size {w}x{h} != {ew}x{eh}")
            bad += 1
            continue

        # ROWOFF must be y*w
        if any(cpu.m[ROWOFF + y] != (y * w) & 0xFF for y in range(15)):
            print(f"  FAIL puzzle {idx}: ROWOFF is not y*w")
            bad += 1
            continue

        # independent expansion of the packed bitmap
        base = sym["nemo_bitmaps"] + idx * 30
        want = []
        for y in range(h):
            b0, b1 = cpu.m[base + y * 2], cpu.m[base + y * 2 + 1]
            row = []
            for x in range(w):
                bit = (b0 if x < 8 else b1) >> (7 - (x & 7)) & 1
                row.append(bit)
            want.append(row)

        got = [[cpu.m[SOLUTION + y * w + x] for x in range(w)]
               for y in range(h)]
        if got != want:
            print(f"  FAIL puzzle {idx}: expanded solution differs")
            bad += 1
            continue

        # clue tables
        ok = True
        for y in range(h):
            exp = runs_of(want[y])
            p = CLUE_H + y * 16
            n = cpu.m[p]
            act = [cpu.m[p + 1 + i] for i in range(n)]
            if act != exp:
                print(f"  FAIL puzzle {idx} row {y}: {act} != {exp}")
                ok = False
                break
        if ok:
            for x in range(w):
                col = [want[y][x] for y in range(h)]
                exp = runs_of(col)
                p = CLUE_V + x * 16
                n = cpu.m[p]
                act = [cpu.m[p + 1 + i] for i in range(n)]
                if act != exp:
                    print(f"  FAIL puzzle {idx} col {x}: {act} != {exp}")
                    ok = False
                    break
        if not ok:
            bad += 1
    check(bad == 0, f"all 50 puzzles expand and derive correctly "
                    f"({50 - bad}/50)")

    print("\n== win detection: play a puzzle to completion ==")
    cpu = mkcpu(image)
    cpu.call(sym["render_init"])
    cpu.m[pz_idx] = 8                      # 'mic', 7x14 - the smallest
    cpu.call(sym["puzzle_load"])
    w, h = cpu.m[pz_w], cpu.m[pz_h]
    check(cpu.m[is_clear] == 0, "empty board is not complete")

    for y in range(h):
        for x in range(w):
            if cpu.m[SOLUTION + y * w + x] == 1:
                cpu.m[t1], cpu.m[t2], cpu.m[t3] = x, y, 1
                cpu.call(sym["board_set"])
    cpu.call(sym["match_all"])
    check(cpu.m[is_clear] == 1, "filled-in solution is detected as complete")
    check(all(cpu.m[MATCH_H + y] == 1 for y in range(h)), "all rows match")
    check(all(cpu.m[MATCH_V + x] == 1 for x in range(w)), "all columns match")

    # marks must not count as filled
    cpu.m[t1], cpu.m[t2], cpu.m[t3] = 0, 0, 2
    cpu.call(sym["board_set"])
    cpu.call(sym["match_all"])
    print(f"  info after marking (0,0): is_clear={cpu.m[is_clear]} "
          f"(solution cell there = {cpu.m[SOLUTION]})")

    print("\n== render: draw a board and dump the overlay ==")
    cpu = mkcpu(image)
    ovl = bytearray(2400)

    def mkw(off):
        def w(v):
            ovl[off] = v
        return w
    for off in range(2400):
        cpu.writers[0xE000 + off] = mkw(off)
    cpu.call(sym["render_init"])
    cpu.m[pz_idx] = 8
    cpu.call(sym["puzzle_load"])
    # fill in half the solution so cells, marks and clues all appear
    n = 0
    for y in range(cpu.m[pz_h]):
        for x in range(cpu.m[pz_w]):
            if cpu.m[SOLUTION + y * cpu.m[pz_w] + x] == 1:
                n += 1
                if n % 2 == 0:
                    cpu.m[t1], cpu.m[t2], cpu.m[t3] = x, y, 1
                    cpu.call(sym["board_set"])
    cpu.call(sym["match_all"])
    cpu.m[0x2A] = 0                        # cur_blink: cursor visible
    cpu.call(sym["draw_board"])
    cpu.call(sym["ovl_blit"]) if "ovl_blit" in sym else None

    lit = sum(bin(b).count("1") for b in ovl)
    check(lit > 200, f"overlay has content ({lit} pixels lit)")
    for y in range(0, 120, 2):
        row = "".join(
            "#" if ovl[y * 20 + (x >> 3)] & (1 << (x & 7)) else "."
            for x in range(0, 160, 2))
        if row.strip("."):
            print("  " + row)

    print()
    if FAIL:
        print(f"FAILED: {len(FAIL)} check(s)")
        for f in FAIL:
            print("  - " + f)
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except UndocumentedOpcode as e:
        print(f"\nEMULATOR HIT: {e}")
        sys.exit(2)
