#!/usr/bin/env python3
"""Capture reference frames from a real PICO-8 cart, without human help.

Why it works this way:
  * extcmd("screenshot") does not reliably write a file on macOS (the default
    desktop_path fails, and PICO-8 will not create the directory), so the cart
    dumps its own framebuffer to stdout via printh instead. printh definitely
    reaches stdout, and the dump carries palette indices rather than RGB, which
    is what a port needs to compare against.
  * PICO-8 is launched in its own process group and killed in a finally block,
    so a cart that errors, hangs, or never reaches its exit hook cannot leave a
    window open.
  * A scratch -home directory is used, so the caller's PICO-8 config is never
    touched.
  * Carts near the 8192-token limit cannot carry a capture hook, so dev-only
    functions are stripped first. NEMO ships at 8186/8192 and needs this.

Usage:
  p8_capture.py cart.p8.png --frame 90 --out shot.png
  p8_capture.py cart.p8.png --frame 200 --keys 40:x,70:o,100:right --out play.png
  p8_capture.py cart.p8.png --frame 90 --ascii
"""
import argparse
import os
import re
import signal
import subprocess
import sys
import tempfile
import time

from p8_audio import rom_from_png, decompress_code
from p8_unpack import hexrows, trim, sfx_section, music_section

PICO8 = "/Applications/PICO-8.app/Contents/MacOS/pico8"
HEX = "0123456789abcdef"

# PICO-8's standard 16-colour palette.
PALETTE = [
    (0, 0, 0), (29, 43, 83), (126, 37, 83), (0, 135, 81),
    (171, 82, 54), (95, 87, 79), (194, 195, 199), (255, 241, 232),
    (255, 0, 77), (255, 163, 0), (255, 236, 39), (0, 228, 54),
    (41, 173, 255), (131, 118, 156), (255, 119, 168), (255, 204, 170),
]

# Dev-only functions worth stripping to make room for the hook. Removing these
# cannot change what the game draws.
STRIPPABLE = ["function puzzle:export(", "function log(", "function print_log(",
              "function print_system_info("]

KEYMAP = {"left": 0, "l": 0, "right": 1, "r": 1, "up": 2, "u": 2,
          "down": 3, "d": 3, "o": 4, "z": 4, "x": 5}


def strip_dev_code(lines):
    """Drop top-level dev functions and their obvious call sites."""
    dead = set()
    for marker in STRIPPABLE:
        for i, l in enumerate(lines):
            if l.startswith(marker):
                j = i
                while j < len(lines) and lines[j].rstrip() != "end":
                    j += 1
                dead.update(range(i, j + 1))
                break
    for i, l in enumerate(lines):
        s = l.strip()
        if (s.startswith("print_log()") or s.startswith("print_system_info()")
                or "export puzzle" in s):
            dead.add(i)
    return [l for i, l in enumerate(lines) if i not in dead], len(dead)


def build_hook(frame, keys, step):
    """Scripted input, a framebuffer dump at `frame`, then shutdown."""
    press = "\n".join(
        f" if(__n>{f} and __n<{f + 4})__k={k}" for f, k in keys)
    return f"""
-- capture harness (tools/p8_capture.py); not part of the cart
__n=0
__k=-1
btnp=function(i) return i==__k end
btn=function(i) return i==__k end
__pp="{HEX}"
__d=_draw
_draw=function()
 __d()
 __n+=1
 __k=-1
{press}
 if __n=={frame} then
  printh("@@BEGIN")
  for y=0,127,{step} do
   local s=""
   for x=0,127,{step} do
    local c=pget(x,y)
    s=s..sub(__pp,c+1,c+1)
   end
   printh(s)
  end
  printh("@@END")
  extcmd("shutdown")
 end
 if(__n=={frame + 120})extcmd("shutdown")
end
"""


def make_cart(cart_png, path, frame, keys, step):
    rom = rom_from_png(cart_png)
    code, ndead = strip_dev_code(decompress_code(rom).split("\n"))
    gfx = trim(hexrows(rom[0:0x2000], 64, 128, swap_nibbles=True))
    gff = trim(hexrows(rom[0x3000:0x3100], 128, 2))
    mp = trim(hexrows(rom[0x2000:0x3000], 128, 32))
    sfx = sfx_section(rom)
    mus = music_section(rom)
    while sfx and set(sfx[-1][8:]) <= {"0"}:
        sfx.pop()
    while mus and mus[-1] == "00 00000000":
        mus.pop()
    with open(path, "w", encoding="latin-1") as f:
        f.write("pico-8 cartridge // http://www.pico-8.com\nversion 42\n__lua__\n")
        f.write("\n".join(code) + "\n" + build_hook(frame, keys, step).strip() + "\n")
        for sec, rows in (("__gfx__", gfx), ("__gff__", gff), ("__map__", mp),
                          ("__sfx__", sfx), ("__music__", mus)):
            if rows:
                f.write(sec + "\n" + "\n".join(rows) + "\n")
    return ndead


def run_pico8(cart, home, timeout):
    """Run the cart and return its stdout. Always kills the process group."""
    os.makedirs(os.path.join(home, "carts"), exist_ok=True)
    with open(os.path.join(home, "config.txt"), "w") as f:
        f.write("windowed 1\nsound_volume 0\nwindow_size 128 128\n")
    proc = subprocess.Popen(
        [PICO8, "-home", home, "-run", cart],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, errors="replace", start_new_session=True)
    out = []
    try:
        deadline = time.time() + timeout
        while True:
            if proc.poll() is not None:
                out.append(proc.stdout.read() or "")
                break
            if time.time() > deadline:
                sys.stderr.write(f"timeout after {timeout}s; killing PICO-8\n")
                break
            line = proc.stdout.readline()
            if line:
                out.append(line)
                if "@@END" in line:
                    # got what we came for; do not wait for a clean exit
                    break
            else:
                time.sleep(0.01)
    finally:
        # Kill the whole group: PICO-8 must never be left on screen.
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass
        subprocess.run(["pkill", "-x", "pico8"], capture_output=True)
    return "".join(out)


def parse_frame(text):
    m = re.search(r"@@BEGIN\n(.*?)@@END", text, re.S)
    if not m:
        return None
    return [l for l in m.group(1).split("\n") if l.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cart")
    ap.add_argument("--frame", type=int, default=90)
    ap.add_argument("--keys", default="",
                    help="comma list of frame:key, e.g. 40:x,70:o")
    ap.add_argument("--step", type=int, default=1,
                    help="pixel stride when dumping (1 = full 128x128)")
    ap.add_argument("--out", help="write a PNG here")
    ap.add_argument("--ascii", action="store_true")
    ap.add_argument("--timeout", type=float, default=90)
    a = ap.parse_args()

    keys = []
    for tok in filter(None, a.keys.split(",")):
        f, k = tok.split(":")
        if k not in KEYMAP:
            raise SystemExit(f"unknown key {k!r}; use {sorted(KEYMAP)}")
        keys.append((int(f), KEYMAP[k]))

    with tempfile.TemporaryDirectory() as td:
        cart = os.path.join(td, "ref.p8")
        ndead = make_cart(a.cart, cart, a.frame, keys, a.step)
        print(f"built capture cart (stripped {ndead} lines of dev code)",
              file=sys.stderr)
        text = run_pico8(cart, os.path.join(td, "home"), a.timeout)

    rows = parse_frame(text)
    if rows is None:
        sys.stderr.write("no framebuffer dump found. PICO-8 said:\n")
        sys.stderr.write("\n".join(text.strip().split("\n")[-15:]) + "\n")
        return 1

    if a.ascii:
        for r in rows:
            print(r)
    if a.out:
        try:
            from PIL import Image
        except ImportError:
            raise SystemExit("PNG output needs Pillow")
        h, w = len(rows), len(rows[0])
        img = Image.new("RGB", (w, h))
        img.putdata([PALETTE[HEX.index(c)] for r in rows for c in r])
        img.save(a.out)
        print(f"wrote {a.out} ({w}x{h})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
