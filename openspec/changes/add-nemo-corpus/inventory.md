# NEMO - Puzzle Pack II: systems inventory

Task 1.3. Source obtained from `nemonemo2-1.p8.png` (cart revision `ver="1.01"`,
`latest_update 2022/09/19`) and decompressed with `tools/p8_audio.py`.

**1587 lines, 36119 characters of Lua.** The decode is verified: the bit stream
consumed exactly the `com_size` recorded in the PXA header (12759 bytes), and the
output length matched `unc_size` (36119) exactly.

## Headline finding: this corpus is not small

`proposal.md` guessed "the code volume is likely modest… it will rarely clear G3's
≥8 threshold on its own". **That was wrong, and in the most useful direction.** NEMO
is not a flat script — it is an object-oriented program with a class system, a
prototype chain, an event bus and a retained scene graph. On the indirection axis it
is the most demanding of the three corpora, Celeste included.

```
event  = class()          -- 119
sprite = class(event)     -- 139   x/y, children, show/render/add_child/remove_self
  puzzle   = class(sprite)  -- 248
  cursor   = class(sprite)  -- 769
  popup    = class(sprite)  -- 895
  cover    = class(sprite)  -- 1094
  home     = class(sprite)  -- 1136
  selector = class(sprite)  -- 1248
```

`class(base)` (line 97) builds a metatable chain and its `new` walks that chain
collecting `init` functions so every ancestor's constructor runs in order. Eight
classes, three levels, 14 `:on(` handler registrations, 7 `add_child` calls, and 12
anonymous functions used as callbacks.

## Idiom families, and which slice each one calibrates

### 1. Variable-stride 2D indexing — the multiply evidence

This is the sharpest result of the inventory. `puzzle:set_puzzle` (line 286):

```lua
local n=(i-1)*pz_w+j
pz_t[i][j]=tonum(pz_str[n])
```

`pz_w` is the **puzzle's width, read at runtime** from the puzzle table — not a
constant. So this is a variable × variable multiply, which cannot be
strength-reduced to shifts at assembly time the way a constant stride can.

And it is not one awkward width but eight, across the 50 puzzles:

| Widths used | 7, 9, 10, 11, 12, 13, 14, 15 |
| --- | --- |
| Powers of two among them | **none** |
| Heights used | 7, 8, 9, 11, 12, 13, 14, 15 |

Every 2D structure in the other two corpora is power-of-two aligned — Breakout's
tilemap is 8-aligned, Celeste's rooms are 16×16 — so both index by shifting. **NEMO
has no shift-indexable puzzle at all.** The port must either build a row-base
pointer table per puzzle (pointer idiom) or synthesise a general multiply.

There is a second, weaker multiply: `map_tile_w * tile_size` with `tile_size = 6`
(line 298), a variable × constant that *is* strength-reducible.

→ First countable demand for the deferred `add-math-coprocessor`, and evidence for
`add-isa-pointer-ops` whichever way the port resolves it.

### 2. Bit-packed stream decode — pointer walk evidence

Puzzle bitmaps are stored **7 bits per character** against a 128-entry alphabet
(`encode_str`), decoded by `data_decode` → `num2bit` (lines 215-243): for each
character, find its index in the alphabet, emit 7 bits, concatenate. The result is
one cell per byte, consumed by the indexing above.

Payload across all 50 puzzles: **1281 encoded characters → 1120 bytes packed**,
expanding to **8811 cells**. Small data, real decoder.

→ `add-isa-pointer-ops`, in its purest sequential auto-increment form.

### 3. Class dispatch, scene graph and event bus — the strongest pointer evidence

- **Method dispatch** through a 3-level prototype chain: either per-class function
  pointer tables with a fallback chain, or flattened vtables at build time.
- **Constructor chaining**: `new` walks the ancestor chain and calls each `init`.
- **Scene graph**: `sprite` holds a child list; `add_child` / `remove_self` /
  `render` walk it recursively with inherited x/y offsets.
- **Event bus**: `on` / `remove_handler` / `emit` store `{function, context}` pairs
  in per-event lists — arrays of function pointers with an associated object
  pointer.

→ Substantially heavier indirection than Celeste's per-type `update`/`draw`
dispatch, which was the pointer-ops justification.

### 4. Grid state, clue derivation and validation

- `set_tile` / `get_tile` (553-558) over `map_data[y][x]`; cells are tri-state
  (empty / filled / marked).
- `update_puzzle_numbers` (393) with the nested `is_definite(arr,num)` helper —
  derives row and column clue runs.
- `update_matchdata` (622), `check_is_clear` (649), `update_uncleared_data` (667) —
  per-row and per-column run-length accumulation compared against the clues.
- `draw_num` / `draw_numbers` (478, 493) — clue rendering with an `on_cursor`
  highlight.

→ `add-isa-test-and-branch` (mask-and-branch over cell state) and
`add-isa-frame-pointer` (nested helpers with per-row temporaries).

## Persistence: confirmed, and it has nowhere to go

```lua
cartdata("nemonemo2_seimon")   -- 1544
pz_cleared[i]=dget(i)          -- 1515, cartdata_load
dset(i,v)                      -- 1521, cartdata_save
dset(i,nil)                    -- 1526, cartdata_reset
```

Fifty per-puzzle completion flags, saved on clear (`cartdata_save` called from
`puzzle:on_clear`'s path at line 761) and resettable from a menu item. Nothing in
`rtl/` implements EEPROM, flash or NVRAM, so this is gap entry 4.1: the port keeps
progress in RAM and loses it on power-off.

The demand is small and specific — **50 bits**, i.e. 7 bytes — which makes the
minimum useful fix genuinely tiny: a handful of bytes behind an MMIO window, not a
filesystem.

## Presentation

- `tile_size = 6`, `cursor_size = 8`. A 15×15 grid is 90×90 pixels, so the playfield
  fits the console's 160×120 comfortably — **no geometry problem**, unlike Celeste.
- Rounded-box popups drawn procedurally (`draw_r_box`, twice — 1011 and 1470),
  dotted lines (`draw_dotline_h/v`), drop-shadowed rectangles and text
  (`rect_shadowed`, `printa` with align and shadow).
- A **QR code renderer** (`draw_qr`, 548) over the `qr_data_zip` binary blob — one
  of the two PXA raw-literal blocks in the cart. Decorative; a candidate to drop.
- `selector` renders a scrollable strip of 50 puzzle boxes with per-puzzle previews
  decoded on demand (1352).

Procedural drawing is the one area where the console is *less* capable than PICO-8:
there is no line or circle primitive, only tiles, sprites and the 1bpp overlay. The
rounded boxes and dotted lines need either overlay-bitmap plotting or pre-baked
tiles.

## Audio

Music is from Gruber's *Pico-8 Tunes Volume 1*. The PSG takes a verbatim audio-RAM
upload, so including it costs almost nothing on the CPU axis — but it is the second
attribution party (task 1.1), and task 1.4 leans include on that basis.

## Consequences for the change

1. **Retract the "probably small" caveat** in `proposal.md` and the matching risk in
   `design.md`. The corpus is substantial and its indirection is the heaviest of the
   three.
2. **Strengthen the multiply claim.** It is not "a 15-wide grid needs `y*15+x`" — it
   is a runtime-variable stride over eight non-power-of-two widths, none
   strength-reducible.
3. **Add a fifth idiom family**: class dispatch / scene graph / event bus. This was
   not anticipated and it is the best pointer-ops evidence available anywhere in the
   corpus set.
4. **Add a gap candidate**: procedural drawing primitives (lines, circles, rounded
   rectangles). Not required for the port — pre-baked tiles work — but it is a real
   difference from PICO-8 and belongs in `docs/hardware-gaps.md` for the record.
5. **`docs/corpora.md` should note** that this corpus exercises the PPU thinly in
   *sprite* terms but leans on the overlay layer harder than either action cart.
