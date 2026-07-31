#!/usr/bin/env python3
"""Trace a cart's MUSIC SEQUENCING under real PICO-8, for diffing against the PSG.

The console can already dump its own sequencer state per frame:

    build/obj_dir/console --headless --frames N --psg-trace
    @@<frame> <sfx c0..c3> <row c0..c3> <pattern> mus=<n> own=<mask>

This produces the same shape from the real thing, so "the music is wrong" can
be turned into "pattern 3 runs for 8.5 s here and 4.3 s there".

The trace cart carries only the cart's audio sections and a few lines of Lua -
no game code at all - so nothing the game does can perturb the sequencer, and
there is no token limit to worry about.

Usage:
  p8_music_trace.py cart.p8.png --pattern 0 --mask 7 --frames 600
  p8_music_trace.py cart.p8.png --pattern 0 --summary
"""
import argparse
import os
import re
import sys
import tempfile

from p8_audio import rom_from_png
from p8_capture import run_pico8
from p8_unpack import sfx_section, music_section

LUA_REC = """
t=0
function _init()
 extcmd("audio_rec")
 music({pattern},0,{mask})
end
function _update()
 t+=1
 if t=={frames} then
  extcmd("audio_end")
 end
 -- do NOT signal the harness immediately: it kills PICO-8 on @@END, and the
 -- wav is still being written. Ninety frames of grace is plenty.
 if t>={frames}+90 then
  printh("@@END")
  stop()
 end
end
function _draw() cls() print("rec",1,1,7) end
"""

LUA = """
t=0
function _init()
 music({pattern},0,{mask})
end
function _update()
 local s=""
 for c=0,3 do s=s..stat(16+c).."," end
 for c=0,3 do s=s..stat(20+c).."," end
 printh("@@"..t..","..s..stat(24)..","..stat(26))
 t+=1
 if t>={frames} then
  printh("@@END")
  stop()
 end
end
function _draw() cls() end
"""


def make_trace_cart(cart_png, path, pattern, mask, frames, record=False,
                    solo_channel=None):
    rom = rom_from_png(cart_png)
    sfx = sfx_section(rom)
    mus = music_section(rom)
    if solo_channel is not None:
        isolated = []
        for row in mus:
            flags, packed = row.split()
            channels = [int(packed[i:i + 2], 16) for i in range(0, 8, 2)]
            for ch in range(4):
                if ch != solo_channel:
                    channels[ch] |= 0x40
            isolated.append(flags + " " + "".join(f"{v:02x}" for v in channels))
        mus = isolated
    while sfx and set(sfx[-1][8:]) <= {"0"}:
        sfx.pop()
    while mus and mus[-1] == "00 00000000":
        mus.pop()
    with open(path, "w", encoding="latin-1") as f:
        f.write("pico-8 cartridge // http://www.pico-8.com\nversion 42\n__lua__\n")
        lua = LUA_REC if record else LUA
        f.write(lua.format(pattern=pattern, mask=mask, frames=frames))
        for sec, rows in (("__sfx__", sfx), ("__music__", mus)):
            if rows:
                f.write("\n" + sec + "\n" + "\n".join(rows) + "\n")


def parse(text):
    out = []
    for line in text.split("\n"):
        m = re.match(r"@@(\d+),(.*)", line.strip())
        if not m:
            continue
        vals = [int(v) for v in m.group(2).rstrip(",").split(",")]
        out.append({"frame": int(m.group(1)), "sfx": vals[0:4],
                    "row": vals[4:8], "pat": vals[8], "tick": vals[9]})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cart")
    ap.add_argument("--pattern", type=int, default=0)
    ap.add_argument("--mask", type=int, default=7)
    ap.add_argument("--frames", type=int, default=600)
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--summary", action="store_true",
                    help="pattern durations only, in PICO-8 frames (30/s)")
    ap.add_argument("--record", metavar="DIR",
                    help="record PICO-8's own audio to a .wav in DIR, for A/B "
                         "against sim/psg_wav.cpp's rendering")
    ap.add_argument("--solo-channel", type=int, choices=range(4),
                    help="disable the other three music bytes in every pattern")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as home:
        cart = os.path.join(home, "carts", "trace.p8")
        os.makedirs(os.path.dirname(cart), exist_ok=True)
        make_trace_cart(args.cart, cart, args.pattern, args.mask, args.frames,
                        record=bool(args.record),
                        solo_channel=args.solo_channel)
        if args.record:
            # PICO-8 will not create the directory it writes into, which is
            # why extcmd("screenshot") silently fails on macOS too.
            os.makedirs(args.record, exist_ok=True)
            with open(os.path.join(home, "config.txt"), "w") as f:
                f.write("windowed 1\nsound_volume 128\nwindow_size 128 128\n"
                        f"desktop_path {args.record}\n")
            text = run_pico8(cart, home, args.timeout)
            made = sorted(os.listdir(args.record))
            print("PICO-8 wrote:", made or "(nothing - check desktop_path)")
            return 0 if made else 1
        text = run_pico8(cart, home, args.timeout)

    rows = parse(text)
    if not rows:
        sys.stderr.write("no trace rows; PICO-8 output was:\n" + text[:2000])
        return 1

    if args.summary:
        print(f"{'pattern':>8} {'frames':>7} {'seconds':>8}   channels (sfx)")
        run_pat, run_len, first = rows[0]["pat"], 0, rows[0]
        for r in rows + [None]:
            if r is not None and r["pat"] == run_pat:
                run_len += 1
                continue
            print(f"{run_pat:>8} {run_len:>7} {run_len / 30:>8.2f}   "
                  f"{first['sfx']}")
            if r is None:
                break
            run_pat, run_len, first = r["pat"], 1, r
        return 0

    print("# frame sfx0..3 row0..3 pattern tick   (PICO-8, 30 fps)")
    for r in rows:
        print(f"@@{r['frame']} {' '.join(map(str, r['sfx']))} "
              f"{' '.join(map(str, r['row']))} {r['pat']} tick={r['tick']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
