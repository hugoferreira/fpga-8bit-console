#!/usr/bin/env python3
"""Unpack a .p8.png cart into PICO-8's plain-text .p8 format.

Useful for two things: reading a cart's source without opening PICO-8, and
producing a cart that can be instrumented (e.g. to take a reference screenshot
at a fixed frame) and re-run under the real PICO-8 for comparison against a
port.

ROM layout:
    0x0000-0x1fff  spritesheet   (128x128, 4bpp, low nibble = left pixel)
    0x2000-0x2fff  map           (128x32 tiles)
    0x3000-0x30ff  sprite flags
    0x3100-0x31ff  music         (64 patterns x 4 bytes)
    0x3200-0x42ff  sfx           (64 records x 68 bytes)
    0x4300-0x7fff  compressed code

Usage: p8_unpack.py cart.p8.png out.p8
"""
import sys

from p8_audio import rom_from_png, decompress_code


def hexrows(data, row_len, count, swap_nibbles=False):
    out = []
    for r in range(count):
        row = data[r * row_len:(r + 1) * row_len]
        if swap_nibbles:
            # The spritesheet stores the LEFT pixel in the low nibble, but the
            # .p8 text form lists pixels left to right.
            s = "".join(f"{b & 0xF:x}{b >> 4:x}" for b in row)
        else:
            s = "".join(f"{b:02x}" for b in row)
        out.append(s)
    return out


def trim(rows):
    """Drop wholly-zero rows from the end, as PICO-8 itself does."""
    while rows and set(rows[-1]) <= {"0"}:
        rows.pop()
    return rows


def sfx_section(rom):
    """Each record: 32 notes (2 bytes LE) then filter, speed, loop lo, loop hi.

    The text form writes the four control bytes first, then 32 notes as
    5 hex chars each: pitch(2) waveform(1) volume(1) effect(1).
    """
    out = []
    for n in range(64):
        base = 0x3200 + n * 68
        notes = rom[base:base + 64]
        filt, speed, lo, hi = rom[base + 64:base + 68]
        s = f"{filt:02x}{speed:02x}{lo:02x}{hi:02x}"
        for i in range(32):
            w = notes[i * 2] | (notes[i * 2 + 1] << 8)
            pitch = w & 0x3F
            wave = (w >> 6) & 0x7
            vol = (w >> 9) & 0x7
            eff = (w >> 12) & 0x7
            custom = (w >> 15) & 1
            # a custom-instrument note sets bit 3 of the waveform nibble
            s += f"{pitch:02x}{wave | (custom << 3):x}{vol:x}{eff:x}"
        out.append(s)
    return out


def music_section(rom):
    out = []
    for n in range(64):
        b = rom[0x3100 + n * 4:0x3100 + n * 4 + 4]
        # flags live in the high bits of each byte; the text form puts them in
        # a leading nibble pair and masks them out of the channel bytes
        flags = ((b[0] >> 7) & 1) | (((b[1] >> 7) & 1) << 1) | (((b[2] >> 7) & 1) << 2)
        out.append(f"{flags:02x} " + "".join(f"{x & 0x7F:02x}" for x in b))
    return out


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    rom = rom_from_png(sys.argv[1])
    code = decompress_code(rom)

    gfx = trim(hexrows(rom[0x0000:0x2000], 64, 128, swap_nibbles=True))
    gff = trim(hexrows(rom[0x3000:0x3100], 128, 2))
    mapd = trim(hexrows(rom[0x2000:0x3000], 128, 32))
    sfx = sfx_section(rom)
    mus = music_section(rom)
    # trim trailing empty sfx / music
    while sfx and set(sfx[-1][8:]) <= {"0"}:
        sfx.pop()
    while mus and mus[-1] == "00 00000000":
        mus.pop()

    with open(sys.argv[2], "w", encoding="latin-1") as f:
        f.write("pico-8 cartridge // http://www.pico-8.com\nversion 42\n")
        f.write("__lua__\n")
        f.write(code if code.endswith("\n") else code + "\n")
        for name, rows in (("__gfx__", gfx), ("__gff__", gff),
                           ("__map__", mapd), ("__sfx__", sfx),
                           ("__music__", mus)):
            if rows:
                f.write(name + "\n")
                f.write("\n".join(rows) + "\n")
    print(f"wrote {sys.argv[2]}: {len(code)} chars of Lua, {len(gfx)} gfx rows, "
          f"{len(sfx)} sfx, {len(mus)} music patterns")


if __name__ == "__main__":
    main()
