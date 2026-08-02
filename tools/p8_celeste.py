#!/usr/bin/env python3
"""Extract Celeste Classic's art, rooms and tile flags for the 6502 port.

The console's sprite sheet is 256 slots of one 8x8 bitplane each (2KB), and
patterns are referenced by slot BASE with a bpp field that doubles as the
footprint. So a 4bpp pattern costs 4 slots and there are 64 of them in the
whole sheet, shared between tiles and sprites. This tool allocates only the
patterns the chosen rooms actually use, and reports the budget.

The console's hardware palette IS the PICO-8 palette (rtl/palette888.bin), so
no colour is ever converted. What IS converted is the encoding: patterns store
palette-relative values rather than colour indices, and a generated draw
palette maps them back, so a three-colour tile costs two sheet slots instead of
four. See the block comment above fit_pattern().

Emits, all to src/celeste/:
    gfx.inlay.asm    sheet image, tile-id -> (slot base, attributes) tables
    rooms.inlay.asm  resident rooms as tile ids, plus the tile flag table

Usage: p8_celeste.py cart.p8.png [--rooms 31,0,1,2,3,4,5,6,7,8,9] [--out src/celeste]
"""
import argparse
import collections
import os
import random
import sys

from p8_audio import rom_from_png

# The cart's own object-marker tiles: they spawn an object and are never drawn
# as terrain (init_object is keyed on them in load_room).
OBJ_TILES = {1: "player_spawn", 8: "key", 11: "platform_left", 12: "platform_right",
             18: "spring", 20: "chest", 22: "balloon", 23: "fall_floor",
             26: "fruit", 28: "fly_fruit", 64: "fake_wall", 86: "message",
             96: "big_chest", 118: "flag"}
SPIKES = {17: "down", 27: "up", 43: "right", 59: "left"}

# Sprites the port needs that are not terrain: the player's seven frames and
# smoke's three. player_spawn reuses player frames 3 and 6.
PLAYER_SPRITES = [1, 2, 3, 4, 5, 6, 7]
SMOKE_SPRITES = [29, 30, 31]

# Extra sprite art required by each marker kind in the first ten-room campaign.
# Several objects animate through tiles that never occur in the map, and fake
# walls/platforms are two cells wide, so marker ids alone are not a sufficient
# art manifest.
CONTENT_SPRITES = {
    "key": [8, 9, 10],
    "platform_left": [11, 12],
    "platform_right": [11, 12],
    "balloon": [13, 14, 15, 22],
    "spring": [18, 19],
    "chest": [20],
    "fall_floor": [23, 24, 25, 26],
    "fruit": [26],
    "fly_fruit": [28, 45, 46, 47],
    "fake_wall": [64, 65, 80, 81],
}

# Hand-authored, because the cart draws hair with circfill and this console has
# no circle primitive. Two radii, 1bpp; the sprite entry's palette base picks
# the colour, which is how pal(8,...) is reproduced.
HAIR_BLOBS = [
    # r=2: a 5x5 disc, left-aligned in the 8-pixel row (bit 0 is leftmost)
    [0b00001110, 0b00011111, 0b00011111, 0b00011111, 0b00001110, 0, 0, 0],
    # r=1: a 3x3 disc, centred on pixel (1,1)
    [0b00000010, 0b00000111, 0b00000010, 0, 0, 0, 0, 0],
]

# The colours the cart's set_hair_color() can ask for: red at one dash, white
# and green alternating at two, blue at none.
HAIR_COLOURS = [8, 7, 11, 12]

# Colours the background effects need as flat 1bpp fills: cloud navy, the two
# particle greys, and the death burst's pinks. Listed so the palette search
# guarantees they are reachable from some base even if no tile uses them.
FX_COLOURS = [1, 6, 7, 14, 15]

# Flat patterns for the effects the cart draws with rectfill(). A cloud is a
# run of solid cells; a particle is a 2x2 dot.
FX_PATTERNS = [
    ("SPR_SOLID", [0xFF] * 8),
    ("SPR_DOT",   [0b00000011, 0b00000011, 0, 0, 0, 0, 0, 0]),
]

SLOT_BYTES = 8
SHEET_SLOTS = 256
FIRST_SLOT = 4      # slots 0-3 stay zero so "base 0, attr 0" means "empty cell"


def mget(rom, x, y):
    """The cart's map. Rows 32-63 share the spritesheet's lower half."""
    if y < 32:
        return rom[0x2000 + y * 128 + x]
    return rom[0x1000 + (y - 32) * 128 + x]


def sprite_rows(rom, n):
    """Sprite n as 8 rows of 8 pixel values (0-15)."""
    sx, sy = (n % 16) * 8, (n // 16) * 8
    rows = []
    for r in range(8):
        row = []
        for c in range(8):
            px, py = sx + c, sy + r
            b = rom[py * 64 + px // 2]
            row.append(b & 0xF if px % 2 == 0 else b >> 4)
        rows.append(row)
    return rows


def planes(rows, bpp):
    """Bitplanes for one pattern: plane p, row r, bit j = pixel j's bit p.

    Bit 0 is the LEFTMOST pixel, matching the compositor's blit
    (sprite_compositor.sv: pix = {prow[3][jj]..prow[0][jj]}, jj = j).
    """
    out = []
    for p in range(bpp):
        for r in range(8):
            byte = 0
            for j in range(8):
                if rows[r][j] >> p & 1:
                    byte |= 1 << j
            out.append(byte)
    return out


class Sheet:
    """Slot allocator over the 2KB sheet."""

    def __init__(self):
        self.data = bytearray(SHEET_SLOTS * SLOT_BYTES)
        self.next = FIRST_SLOT
        self.entries = []           # (name, base, bpp)

    def add(self, name, rows, bpp):
        base = self.next
        if base + bpp > SHEET_SLOTS:
            sys.exit(f"sheet full: {name} needs {bpp} slots at {base}")
        for i, b in enumerate(planes(rows, bpp)):
            self.data[base * SLOT_BYTES + i] = b
        self.next += bpp
        self.entries.append((name, base, bpp))
        return base

    def add_raw(self, name, plane, bpp=1):
        base = self.next
        for i, b in enumerate(plane):
            self.data[base * SLOT_BYTES + i] = b
        self.next += bpp
        self.entries.append((name, base, bpp))
        return base


def bpp_for(rows):
    """Fewest planes that still reproduce every pixel value in the pattern."""
    top = max(max(r) for r in rows)
    return max(1, top.bit_length())


def colours_of(rows):
    return frozenset(p for row in rows for p in row) - {0}


def mono_colour(rows):
    """The single non-zero colour in this pattern, or None if it has several."""
    cs = colours_of(rows)
    return next(iter(cs)) if len(cs) == 1 else None


# ---------------------------------------------------------------------------
# The draw palette, and why the art is not stored as PICO-8 colour indices.
#
# The compositor computes `palette base + pixel value` and then runs the result
# through the 16-entry DRAW PALETTE at $4010. Storing colour indices directly -
# 4bpp, base 0, identity palette - is the obvious encoding and it is what this
# tool did first, but it costs 4 slots for every tile no matter how few colours
# the tile has, and the sheet is only 64 four-plane patterns deep.
#
# Since this tool generates the bitplanes, it also chooses what the pixel
# VALUES mean. A tile with three colours can store them as values 1, 2, 3 and
# pick a base whose next three palette entries hold exactly those colours - two
# slots instead of four. The whole program uses 14 distinct colours across
# every tile, the player, smoke and the hair, so a 16-entry palette has two
# spare slots to duplicate with, and a good arrangement puts every needed
# colour set inside some window.
#
# Finding that arrangement is a small combinatorial problem, solved here by
# hill-climbing from a fixed seed so the output is reproducible. The art is
# still the cart's exactly: only the encoding changes, never a colour.
# ---------------------------------------------------------------------------
def fit_pattern(dpal, colours):
    """Cheapest (bpp, base, {colour: value}) that renders `colours`, or None."""
    for bpp in (1, 2, 3, 4):
        n = (1 << bpp) - 1
        if len(colours) > n:
            continue
        for base in range(16):
            win = [dpal[(base + v) % 16] for v in range(1, n + 1)]
            mapping, taken = {}, set()
            for c in sorted(colours):
                for i, x in enumerate(win):
                    if x == c and i + 1 not in taken:
                        mapping[c] = i + 1
                        taken.add(i + 1)
                        break
                else:
                    break
            else:
                return bpp, base, mapping
    return None


def palette_cost(dpal, wanted):
    """Total sheet slots for these (colour set, count) pairs, or None if any
    set cannot be rendered at all."""
    total = 0
    for cs, mult in wanted:
        f = fit_pattern(dpal, cs)
        if f is None:
            return None
        total += f[0] * mult
    return total


def search_palette(wanted, seeds=8):
    """Hill-climb a 16-entry draw palette that minimises sheet slots."""
    allc = sorted({c for cs, _ in wanted for c in cs})
    best_dpal, best = None, None
    for seed in range(seeds):
        rnd = random.Random(seed)
        dpal = [rnd.choice(allc) for _ in range(16)]
        for c in allc:                      # every colour has to appear once
            if c not in dpal:
                dpal[rnd.randrange(16)] = c
        cur = palette_cost(dpal, wanted)
        while cur is None:
            dpal = [rnd.choice(allc) for _ in range(16)]
            for c in allc:
                if c not in dpal:
                    dpal[rnd.randrange(16)] = c
            cur = palette_cost(dpal, wanted)
        improved = True
        while improved:
            improved = False
            for i in range(16):             # single-entry moves
                keep = dpal[i]
                for c in allc:
                    if c == keep:
                        continue
                    dpal[i] = c
                    v = palette_cost(dpal, wanted)
                    if v is not None and v < cur:
                        cur, keep, improved = v, c, True
                dpal[i] = keep
            for i in range(16):             # pair swaps, to leave the plateaus
                for j in range(i + 1, 16):
                    if dpal[i] == dpal[j]:
                        continue
                    dpal[i], dpal[j] = dpal[j], dpal[i]
                    v = palette_cost(dpal, wanted)
                    if v is not None and v < cur:
                        cur, improved = v, True
                    else:
                        dpal[i], dpal[j] = dpal[j], dpal[i]
        if best is None or cur < best:
            best, best_dpal = cur, list(dpal)
    return best_dpal, best


def encode(sheet, dpal, name, rows):
    """Allocate one pattern through the draw palette. Returns (base, attr).

    A pattern with no colours at all is not allocated: the map cell keeps
    {base 0, attr 0}, which the compositor skips.
    """
    cs = colours_of(rows)
    if not cs:
        return 0, 0
    bpp, pbase, mapping = fit_pattern(dpal, cs)
    remapped = [[mapping[p] if p else 0 for p in row] for row in rows]
    slot = sheet.add(name, remapped, bpp)
    return slot, (pbase << 4) | ((bpp - 1) << 2)


def asm_bytes(f, data, per_line=16):
    for i in range(0, len(data), per_line):
        f.write("    #d8 " + ", ".join(f"${b:02X}" for b in data[i:i + per_line]) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cart")
    ap.add_argument("--rooms", default="31,0,1,2,3,4,5,6,7,8,9",
                    help="resident level indices (default: title and playable rooms 0-9)")
    ap.add_argument("--out", default="src/celeste")
    args = ap.parse_args()

    rom = rom_from_png(args.cart)
    flags = rom[0x3000:0x3100]
    levels = [int(s) for s in args.rooms.split(",")]

    # --- what the chosen rooms contain ------------------------------------
    room_ids = {}
    used = set()
    for lvl in levels:
        rx, ry = lvl % 8, lvl // 8
        ids = [mget(rom, rx * 16 + tx, ry * 16 + ty)
               for ty in range(16) for tx in range(16)]
        room_ids[lvl] = ids
        used |= {t for t in ids if t}

    # A tile is drawn as terrain iff the cart's own _draw would draw it: the
    # map() calls select flag bit 1 (main) and bit 2 (background). Marker tiles
    # have neither and become objects instead.
    art = sorted(t for t in used if flags[t] & 0x06)
    markers = sorted(t for t in used if not flags[t] & 0x06)
    marker_names = {OBJ_TILES[t] for t in markers if t in OBJ_TILES}
    content_sprites = sorted({sprite
                              for name in marker_names
                              for sprite in CONTENT_SPRITES.get(name, [])})
    stray = [t for t in markers if t not in OBJ_TILES]
    # A tile can sit in the map, carry no draw flag and spawn nothing: the
    # cart's own map() calls skip it, so this port skips it too. Tile 78 in the
    # title room is one - a hole inside the CELESTE logo. Reported rather than
    # treated as an error, because silently dropping map data is how a port
    # ends up missing scenery nobody can find later.
    if stray:
        print(f"  note: {len(stray)} tile(s) in the map are never drawn by the "
              f"cart and spawn nothing, so they are left out: {stray}")

    # --- choose the draw palette ------------------------------------------
    # Every colour set the program has to render, with how many patterns share
    # it, so the search optimises for total sheet slots rather than tile count.
    wanted = collections.Counter()
    for t in art:
        cs = colours_of(sprite_rows(rom, t))
        if cs:
            wanted[cs] += 1
    player_cols = frozenset().union(*(colours_of(sprite_rows(rom, n))
                                      for n in PLAYER_SPRITES))
    wanted[player_cols] += len(PLAYER_SPRITES)
    for n in SMOKE_SPRITES:
        wanted[colours_of(sprite_rows(rom, n))] += 1
    for n in content_sprites:
        wanted[colours_of(sprite_rows(rom, n))] += 1
    for c in HAIR_COLOURS + FX_COLOURS:
        wanted[frozenset({c})] += 1

    dpal, slots = search_palette(list(wanted.items()))
    print(f"draw palette: {dpal}  ({slots} slots of pattern data)")

    # --- allocate the sheet -----------------------------------------------
    sheet = Sheet()
    tile_base = [0] * 128
    tile_attr = [0] * 128
    for t in art:
        # attributes: {pal[7:4], bpp-1[3:2], yflip[1], xflip[0]}
        tile_base[t], tile_attr[t] = encode(sheet, dpal, f"tile{t}",
                                            sprite_rows(rom, t))

    player = [encode(sheet, dpal, f"player{n}", sprite_rows(rom, n))
              for n in PLAYER_SPRITES]
    player_base = [b for b, _ in player]
    player_attr = player[0][1]
    if len({a for _, a in player}) != 1:
        sys.exit("player frames disagree on encoding; the draw code assumes one")

    smoke = [encode(sheet, dpal, f"smoke{n}", sprite_rows(rom, n))
             for n in SMOKE_SPRITES]
    smoke_base = [b for b, _ in smoke]
    smoke_attr = smoke[0][1]
    if len({a for _, a in smoke}) != 1:
        sys.exit("smoke frames disagree on encoding; the draw code assumes one attribute")

    content = {n: encode(sheet, dpal, f"object{n}", sprite_rows(rom, n))
               for n in content_sprites}
    sprite_base = [0] * 128
    sprite_attr = [0] * 128
    for n, (base, attr) in zip(PLAYER_SPRITES, player):
        sprite_base[n], sprite_attr[n] = base, attr
    for n, (base, attr) in zip(SMOKE_SPRITES, smoke):
        sprite_base[n], sprite_attr[n] = base, attr
    for n, (base, attr) in content.items():
        sprite_base[n], sprite_attr[n] = base, attr

    # The hair blobs are one plane each; their colour comes from the palette
    # base the game picks at draw time, so each blob is uploaded once and the
    # four bases the cart's set_hair_color() can ask for are emitted as
    # constants.
    hair_base = [sheet.add_raw(f"hair{i}", b) for i, b in enumerate(HAIR_BLOBS)]
    fx_base = [(n, sheet.add_raw(n, b)) for n, b in FX_PATTERNS]

    # Every flat colour a 1bpp pattern might want, as a ready-made attribute
    # byte. Which base reaches which colour is a property of the generated
    # palette, so it cannot be computed in the game code any more.
    flat_attr = {}
    for c in sorted(set(HAIR_COLOURS) | set(FX_COLOURS)):
        f = fit_pattern(dpal, frozenset({c}))
        if f is None or f[0] != 1:
            sys.exit(f"colour {c} is not reachable from a 1bpp pattern")
        flat_attr[c] = f[1] << 4
    hair_attr = flat_attr

    used_slots = sheet.next
    tail = len(sheet.data)
    while tail and sheet.data[tail - 1] == 0:
        tail -= 1
    upload = sheet.data[:max(tail, used_slots * SLOT_BYTES)]

    os.makedirs(args.out, exist_ok=True)

    # --- gfx.inlay.asm ----------------------------------------------------
    with open(os.path.join(args.out, "gfx.inlay.asm"), "w") as f:
        f.write(f"""; ------------------------------------------------------------------------------
; GENERATED by tools/p8_celeste.py - do not edit.
;
; Celeste Classic's art, allocated into the console's 2KB sprite sheet. The
; The console's hardware palette is the PICO-8 palette. Pattern pixels are
; stored palette-relative so low-colour art uses fewer bitplanes, then the draw
; palette maps them back to the cart's exact colours. Slots 0-3 are left zero
; so that a map cell of {{base 0, attr 0}} means "empty".
;
; Rooms resident: {levels}
; Sheet: {used_slots} of {SHEET_SLOTS} slots used ({used_slots * 100 // SHEET_SLOTS}%).
; ------------------------------------------------------------------------------

namespace Gfx
    export upload_bytes
    export hair_big
    export hair_small
    export solid
    export dot
    export palette_1
    export palette_6
    export palette_7
    export palette_8
    export palette_11
    export palette_12
    export palette_14
    export palette_15
    export draw_palette
    export sprite_base
    export sprite_attr
    export sheet
    export tile_base
    export tile_attr

    sheet_bytes = {len(upload)}
    upload_bytes = sheet_bytes
""")
        f.write(f"    hair_big = {hair_base[0]}\n")
        f.write(f"    hair_small = {hair_base[1]}\n")
        for name, b in fx_base:
            f.write(f"    {name.removeprefix('SPR_').lower()} = {b}\n")
        for c in sorted(flat_attr):
            f.write(f"    palette_{c} = ${flat_attr[c]:02X}\n")
        f.write("\n; The draw palette: post-base colour -> real PICO-8 colour. Uploaded to\n"
                "; $4010 at reset. Patterns store palette-relative values, not colour\n"
                "; indices, which is what lets a three-colour tile cost two slots\n"
                "; instead of four.\ndraw_palette:\n")
        asm_bytes(f, dpal)
        f.write("\n; Cart sprite id -> generated slot/attribute. Entries not needed by the\n"
                "; resident campaign are zero. This is shared by player, effects and\n"
                "; stage-2 object drawing.\nsprite_base:\n")
        asm_bytes(f, sprite_base)
        f.write("\n; Cart sprite id -> map/sprite attribute byte.\nsprite_attr:\n")
        asm_bytes(f, sprite_attr)
        f.write("\n; The sheet image, in slot order.\nsheet:\n")
        asm_bytes(f, upload)
        f.write("\n; tile id -> pattern slot base (0 = not drawn as terrain)\n"
                "tile_base:\n")
        asm_bytes(f, tile_base)
        f.write("\n; tile id -> map attribute byte {pal[7:4], bpp-1[3:2], yflip, xflip}\n"
                "tile_attr:\n")
        asm_bytes(f, tile_attr)
        f.write("end\n")

    # --- rooms.inlay.asm --------------------------------------------------
    # The cart's flag bits, kept as the cart numbers them: bit 0 solid,
    # bit 1 draw-main, bit 2 draw-background, bit 4 ice.
    flag_table = [flags[t] for t in range(128)]
    with open(os.path.join(args.out, "rooms.inlay.asm"), "w") as f:
        f.write(f"""; ------------------------------------------------------------------------------
; GENERATED by tools/p8_celeste.py - do not edit.
;
; The resident rooms as the cart's own tile ids, one 256-byte array each, row
; major. The port keeps these in RAM because the console's tilemap window is
; WRITE-ONLY, so `mget` cannot read the map back the way the cart's does - and
; tile_flag_at calls it up to six times a frame.
;
; Level index is the cart's: room.x % 8 + room.y * 8.
; ------------------------------------------------------------------------------

    ROOM_COUNT = {len(levels)}
""")
        for i, lvl in enumerate(levels):
            f.write(f"    ROOM_LEVEL{i} = {lvl}\n")
        f.write("\n; level index of each resident room, in the order the port cycles them\n"
                "room_levels:\n")
        asm_bytes(f, levels)
        low = ", ".join(
            f"(room{i}_tiles)[7:0]" for i in range(len(levels))
        )
        high = ", ".join(
            f"(room{i}_tiles)[15:8]" for i in range(len(levels))
        )
        f.write(f"\nroom_ptr_lo:\n    #d8 {low}\n")
        f.write(f"room_ptr_hi:\n    #d8 {high}\n")
        for i, lvl in enumerate(levels):
            f.write(f"\n; level {lvl} - room ({lvl % 8},{lvl // 8})\nroom{i}_tiles:\n")
            asm_bytes(f, room_ids[lvl])
        f.write("\n; tile id -> the cart's flag byte: bit0 solid, bit1 draw, "
                "bit2 draw-bg, bit4 ice\ntile_flags:\n")
        asm_bytes(f, flag_table)

    # --- report -----------------------------------------------------------
    print(f"rooms {levels}: {len(art)} terrain tiles, {len(markers)} marker tiles")
    print(f"  solid {sum(1 for t in art if flags[t] & 1)}, "
          f"ice {sum(1 for t in art if flags[t] & 0x10)}, "
          f"spikes {sorted(t for t in art if t in SPIKES)}")
    print(f"  markers in these rooms: "
          f"{sorted(OBJ_TILES[t] for t in markers if t in OBJ_TILES)}")
    print(f"  content sprite ids: {content_sprites}")
    bpps = collections.Counter()
    blank = 0
    for t in art:
        cs = colours_of(sprite_rows(rom, t))
        if not cs:
            blank += 1
            continue
        bpps[fit_pattern(dpal, cs)[0]] += 1
    for b in sorted(bpps):
        print(f"  {bpps[b]} terrain tiles at {b}bpp ({bpps[b] * b} slots)")
    if blank:
        print(f"  {blank} terrain tiles are entirely transparent and cost nothing")
    naive = sum(4 for t in art if colours_of(sprite_rows(rom, t)))
    got = sum(b * n for b, n in bpps.items())
    print(f"  terrain: {got} slots, against {naive} if every tile were 4bpp "
          f"({100 - got * 100 // naive}% saved)")
    print(f"sheet: {used_slots}/{SHEET_SLOTS} slots, {len(upload)} bytes to upload")
    print(
        f"wrote {args.out}/gfx.inlay.asm and "
        f"{args.out}/rooms.inlay.asm"
    )


if __name__ == "__main__":
    main()
