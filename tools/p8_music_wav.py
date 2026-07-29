#!/usr/bin/env python3
"""Record a cart's FULL music track from real PICO-8, as a 22050 Hz mono wav.

This is the ground-truth reference for the whole audio chain. tools/psg_oracle.py
covers one assumption at a time over a few seconds; this covers a real song for
its whole loop, which is the only thing that catches sequencer-level drift
(pattern lengths, loop points, effect state carried across rows).

Why extcmd and not the editor's EXPORT command: EXPORT needs the music editor to
be on the right pattern, so tools/p8_music_export.py has to drive physical key
events and needs Accessibility permission. `extcmd("audio_rec")` needs neither -
the cart asks for the recording itself, and `desktop_path` in the isolated
config decides where the wav lands.

Two things this must never get wrong, because both were observed:
  * Do not wait on printh. PICO-8's stdout is block-buffered through a pipe, so a
    cart that prints one line prints it nowhere the harness can see, and the
    harness then waits out its whole timeout with PICO-8 on screen. Wait for the
    WAV FILE to appear and stop growing instead.
  * Kill the process group, then pkill, in a finally. PICO-8 must never be left
    running.

Recording is real time: a 55 s track takes 55 s.

Usage:
  p8_music_wav.py cart.p8.png --pattern 40 --out ref-40.wav
  p8_music_wav.py cart.p8.png --pattern 20 --loops 1 --mask 7 --out ref-20.wav
  p8_music_wav.py cart.p8.png --tracks            # list tracks and durations
"""
from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p8_audio import rom_from_png
from p8_unpack import sfx_section, music_section

PICO8 = "/Applications/PICO-8.app/Contents/MacOS/pico8"
MUSIC_BASE, SFX_BASE = 0x3100, 0x3200
RATE = 22050
# One PICO-8 audio tick is 183 samples at 22050 Hz; a row lasts `speed` ticks
# and a pattern is 32 rows.
TICK = 183 / RATE

LUA_REC = """
t=0
function _init()
 extcmd("audio_rec")
 music({pattern},0,{mask})
end
function _update()
 t+=1
 if t=={frames} then
  music(-1)
  extcmd("audio_end")
 end
end
function _draw() cls() print("rec "..t,1,1,7) end
"""


def track_plan(rom, start):
    """Patterns of the track at `start`, and its length in seconds."""
    pats, total = [], 0.0
    p = start
    while p < 64:
        row = rom[MUSIC_BASE + 4 * p: MUSIC_BASE + 4 * p + 4]
        flags = ((row[0] >> 7) & 1) | ((row[1] >> 7) & 1) << 1 | ((row[2] >> 7) & 1) << 2
        chans = [row[i] & 0x7F for i in range(4)]
        # The pattern's duration is set by its first sounding channel: PICO-8
        # advances the whole pattern when that channel runs out of rows.
        speed = None
        for c in chans:
            if c < 64:
                speed = rom[SFX_BASE + 68 * c + 65]
                break
        if speed is None:
            break
        dur = 32 * speed * TICK
        pats.append((p, chans, flags, dur))
        total += dur
        if flags & 2:
            break
        p += 1
    return pats, total


def tracks(rom):
    """Every pattern flagged BEGIN, i.e. every track head."""
    out = []
    for p in range(64):
        row = rom[MUSIC_BASE + 4 * p: MUSIC_BASE + 4 * p + 4]
        if (row[0] >> 7) & 1 and (row[0] & 0x7F) < 64:
            out.append(p)
    return out


def make_cart(rom, path, pattern, mask, frames):
    sfx = sfx_section(rom)
    mus = music_section(rom)
    while sfx and set(sfx[-1][8:]) <= {"0"}:
        sfx.pop()
    while mus and mus[-1] == "00 00000000":
        mus.pop()
    with open(path, "w", encoding="latin-1") as f:
        f.write("pico-8 cartridge // http://www.pico-8.com\nversion 42\n__lua__\n")
        f.write(LUA_REC.format(pattern=pattern, mask=mask, frames=frames))
        for sec, rows in (("__sfx__", sfx), ("__music__", mus)):
            if rows:
                f.write("\n" + sec + "\n" + "\n".join(rows) + "\n")


def record(cart_png, pattern, mask, seconds, out, volume, grace):
    rom = rom_from_png(cart_png)
    frames = int(round(seconds * 30))
    home = tempfile.mkdtemp(prefix="p8-music-wav.")
    drop = tempfile.mkdtemp(prefix="p8-music-out.")
    try:
        os.makedirs(os.path.join(home, "carts"))
        cart = os.path.join(home, "carts", "rec.p8")
        make_cart(rom, cart, pattern, mask, frames)
        with open(os.path.join(home, "config.txt"), "w") as f:
            f.write(f"windowed 1\nwindow_size 128 128\nsound_volume {volume}\n"
                    f"desktop_path {drop}\n"
                    # A backgrounded PICO-8 that sleeps between frames still
                    # renders audio in its own thread, so the frame counter and
                    # the recording would drift apart. Do not let it sleep.
                    "background_sleep_ms 0\nforeground_sleep_ms 0\n")
        proc = subprocess.Popen(
            [PICO8, "-home", home, "-run", cart],
            stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT,
            start_new_session=True)
        try:
            deadline = time.time() + seconds + grace
            stable, previous = 0, None
            while time.time() < deadline:
                if proc.poll() is not None:
                    break
                found = [os.path.join(drop, n) for n in sorted(os.listdir(drop))
                         if n.endswith(".wav")]
                if found:
                    size = os.path.getsize(found[0])
                    stable = stable + 1 if size == previous and size > 44 else 0
                    previous = size
                    if stable >= 3:
                        shutil.copy2(found[0], out)
                        return out
                time.sleep(0.25)
            raise TimeoutError(
                f"no stable wav in {drop} within {seconds + grace:.0f}s")
        finally:
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
    finally:
        shutil.rmtree(home, ignore_errors=True)
        shutil.rmtree(drop, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cart")
    ap.add_argument("--pattern", type=int, help="track head pattern")
    ap.add_argument("--mask", type=int, default=7, help="channel mask (default 7)")
    ap.add_argument("--out")
    ap.add_argument("--seconds", type=float,
                    help="override the computed track length")
    ap.add_argument("--loops", type=float, default=1.0,
                    help="how many times through the chain (default 1)")
    # PICO-8 records POST-volume, so this scales the reference. 256 is PICO-8's
    # own maximum and the only setting whose amplitudes can be compared against a
    # render directly; at 128 a correct render reads as exactly 2x too loud, and
    # at 0 the wav is silent (which is what the clobbered config in
    # p8_capture.run_pico8 produced).
    ap.add_argument("--volume", type=int, default=256,
                    help="PICO-8 sound_volume, 0..256 (default 256: full scale, "
                         "audible; do NOT lower it, it scales the reference)")
    ap.add_argument("--grace", type=float, default=20.0)
    ap.add_argument("--tracks", action="store_true",
                    help="list track heads with lengths, record nothing")
    args = ap.parse_args()

    rom = rom_from_png(args.cart)
    if args.tracks:
        for head in tracks(rom):
            pats, total = track_plan(rom, head)
            print(f"pattern {head:>2}  {total:6.2f}s  {len(pats)} patterns  "
                  + " ".join(str(p) for p, _, _, _ in pats))
        return 0
    if args.pattern is None or not args.out:
        ap.error("--pattern and --out are required unless --tracks")

    seconds = args.seconds
    if seconds is None:
        _, total = track_plan(rom, args.pattern)
        seconds = total * args.loops
    path = record(args.cart, args.pattern, args.mask, seconds, args.out,
                  args.volume, args.grace)
    with wave.open(path) as w:
        print(f"{path}: {w.getnframes()} frames, {w.getframerate()} Hz, "
              f"{w.getnchannels()} ch, {w.getnframes() / w.getframerate():.2f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
