# ISA calibration corpora

The ISA ergonomic gates (`openspec/changes/add-isa-ergonomic-gates`) score
instructions against real hand-written programs. A gate that can reject an
instruction on evidence can also *accept* one on evidence that only holds for
one kind of program, so the corpus set is deliberately diverse and every gate is
reported **per corpus**. Counts are never pooled: the frequency threshold is an
absolute number of sites, so pooling would let a large corpus carry a threshold
that a small one fails.

Measure with `make metrics`.

## Registered corpora

| Corpus | Program | Frame-bound | Instructions | Plumbing |
| --- | --- | --- | --- | --- |
| `breakout` | Breakout Hero (Krystman / Lazy Devs) | **yes** | 1928 | 32.9% |
| `nemo` | NEMO - Puzzle Pack II (mooon) | **no** | 1811 | 34.2% |
| `celeste` | Celeste Classic (Thorson / Berry), stage 1 | **yes** | 2539 | 24.8% — but read §The pointer-setup blind spot |

### breakout

`src/main.asm` and its data files. A 60 fps action game: fixed arena, flat state
arrays, tilemap bricks, byte counters, a bounded `X` index, table-driven angle
vectors with integer positions.

- **Good at measuring**: the accumulator toll booth, flag ceremony, per-frame
  work, the frame-work cycle budget (gate G8).
- **Poor at measuring**: pointers (19 `(zp),Y` sites), routine-local state (every
  temporary is one of 141 hand-allocated globals), and anything needing indirect
  dispatch — the genre simply does not call for it.
- **Divergences from the original**: game logic is an original 6502
  implementation; level layouts and paddle/ball art come from the cart. See the
  header of `src/main.asm`.

### nemo

`src/nemo/`. A nonogram puzzle game: 50 puzzles, grids from 7x7 to 15x15,
bit-packed solution data, clue derivation and validation, an object system with a
class chain and an event bus.

- **Good at measuring**: pointer cost (44 `(zp),Y` sites, more than twice
  breakout's), indirect dispatch, variable-stride array addressing, bit-stream
  decoding, and — because nothing here is written to fit a frame — plumbing that
  is attributable to the instruction set rather than to hand-optimisation.
- **Poor at measuring**: multi-byte arithmetic (29 high-half operands against
  breakout's 119 — no physics, no sub-pixel anything), the frame-work budget
  (**gate G8 is structurally inapplicable**: the program idles waiting for input
  and has no per-frame work), and the sprite list (it uses exactly one sprite, for
  the cursor).
- **Systems implemented**: puzzle load and bitmap expansion, variable-stride grid
  addressing, tri-state board, clue derivation, match tracking, win detection,
  cursor and editing, puzzle select with on-demand preview, RAM progress
  tracking, class chain / scene graph / event bus.
- **Systems not implemented**: the cart's scrolling 50-box selector strip (one
  puzzle is shown at a time), puzzle-create mode, the QR code screen, and the
  popup and cover transition classes. Music and sound effects **are** implemented:
  the cart's audio image uploads verbatim and all 18 music patterns plus the 7
  SFX are triggered from the cart's own event map.
- **Divergences from the original**:
  - Solution data is re-packed from the cart's 7-bits-per-character alphabet to
    8-bit-packed rows. The 7-bit scheme only existed to survive being a Lua
    string literal.
  - **Three layers, split by what each can express.** The tilemap carries colour
    (the green field, the wordmark blocks, the black banner and footer bars); the
    overlay carries everything on a 6- or 4-pixel grid that an 8-pixel tile grid
    cannot place (the puzzle grid, clue digits, all text); one sprite carries the
    cursor.
  - **Text is in the overlay, not the tile layer.** The sheet does carry a 1bpp
    font at slot 128 + ASCII, but it is 8x8 and a PICO-8 port wants a 4x6 look.
    Breakout reached the same conclusion, so both corpora render text by blitting
    a framebuffer. The consequence is that the overlay has a single colour
    register, so **every label is white** where the cart uses several colours -
    including the cart's grey-for-satisfied clue strips, which here become
    drawn/not-drawn instead.
  - **The wordmark is re-laid on the tile grid.** The cart draws NEMO with the
    same 6-pixel blocks as its puzzle cells, so it does not land on 8-pixel
    tiles. Rasterising it pixel-exactly costs ~108 of the 127 free sheet slots,
    so instead it is redrawn one block per tile, 15 blocks wide, using the same
    3x5 letterforms as the labels. Same word, same orange bordered blocks,
    slightly wider proportions.
  - The wordmark is drawn as one sprite per block (44 of the 128 list entries),
    each bobbing on its own phase so the word ripples as the cart's does. The
    checkered drop shadow is baked into the same 8x8 pattern rather than costing
    a second sprite, which works because blocks sit on an 8-pixel pitch.
  - The cart's cat icon is not reproduced, and the puzzle boxes do not yet bob.
  - Text has no drop shadow: the overlay has one colour register. See
    `hardware-gaps.md` entry 8 for the blit-mode fix that would allow it.
  - Rounded boxes, dotted lines and drop shadows are not reproduced; the console
    has no line or circle primitive.
  - Progress is kept in RAM and lost on power-off — see `hardware-gaps.md`.
  - The music channel mask is set to the channels the cart's patterns actually
    use (0 and 1), not the value the cart passes to `music()` (which reserves
    only channel 1). This console's PSG treats the mask as binding in a way
    PICO-8 does not — see `hardware-gaps.md`. Channel allocation was verified
    against the real cart: PICO-8 puts the music on channels 0 and 1 and a
    cursor SFX on channel 2, and so does this port.

### celeste

`src/celeste/`. Stage 1 of a port of Celeste Classic: a 30 fps precision
platformer with an object list, per-type dispatch, and sub-pixel physics that
accumulates a 16-bit remainder per axis per object per frame.

- **Good at measuring**: 16-bit arithmetic (**117 high-half operands and, unlike
  either other corpus, literal add/subtract chains** — 37 `sec`/`sbc` pairs
  against breakout's 10), pointers (**233 `(zp),Y` sites**, five times nemo's),
  per-type indirect dispatch, and per-object state that cannot be flattened into
  globals because the objects are a pool.
- **Poor at measuring**: anything to do with data volume. The program is small
  and the room data is generated; there is no decode loop, no bit-stream, no
  variable-stride array. It also has no general multiply at all, so it says
  nothing about `add-math-coprocessor`.
- **Systems implemented**: the title screen, its theme and the flash that hands
  over to the game; every `music()` cue the cart makes; the object pool and its
  jump-table dispatch;
  `move()` with 8.8 sub-pixel remainders; `is_solid`/`is_ice`/`tile_flag_at`
  over a RAM copy of the room; `spikes_at` with all four orientations; the
  player (run, ice accel, wall slide, grace, jump buffer, wall jump, dash with
  eight directions, animation); the spawn animation; smoke; room load,
  transition and restart; the vertical camera; hair; the HUD.
- **Systems not implemented** (stage 2, and they are data and dispatch breadth
  rather than new idioms): the other eleven object types — springs, balloons,
  fall floors, fruit, fake walls, the key and chest, platforms, the message, the
  big chest, the orb and the flag — the title screen, and the effects layer
  (clouds, particles, the death burst).
- **Divergences from the original**:
  - **Vertical camera follow.** A room is 128 lines and the display is 120, so
    the camera tracks the player through the missing 8. The cart's camera is
    static per room. This is the one divergence that changes how the game feels
    and it was chosen deliberately over cropping the bottom half-tile row, which
    in a precision platformer carries floors, spikes and room boundaries.
  - **Three rooms, cycled, plus the title room.** Levels 0, 11 ("old site") and
    20, chosen for tile-flag variety rather than adjacency: between them they
    cover 25 solid tiles, 9 ice tiles and all four spike orientations. Level 31
    is resident as slot 0 and is only entered from reset, so `next_room` wraps
    to the first *playing* room and never back to the title.
  - **The music is complete, the rooms that cue it are not.** All four of the
    cart's `next_room` music cues are ported as a table; this room set reaches
    two of them (leaving 11 cues music 20, leaving 20 cues music 30). The
    `music_timer` countdown that restores the climb is implemented, but only
    the orb starts it, and the orb is stage 2.
  - **The hair is sprites, not circles**, and chases at 0.625 rather than the
    cart's 1/1.5 — two shifts and an add instead of a divide. The recolour that
    shows the dash state is free, because a sprite entry carries its own palette
    base.
  - **No screen-space effects.** The console has no line, circle or rectangle
    primitive, so the clouds, the particles, the death burst and the black panel
    behind the room title are absent.
  - **Screen shake moves sprites, not the camera.** The camera registers scroll
    the tile layer only; shaking with them would slide the terrain out from
    under the player. The offset is added to each sprite as the list is built.
  - **The art is stored palette-relative, not as colour indices.** The console
    computes `palette base + pixel value` and then runs the result through a
    16-entry draw palette, so a pattern's pixel values do not have to *be* the
    PICO-8 colours - they only have to point at them. A three-colour tile
    therefore costs two sheet slots instead of four. The whole program uses 14
    distinct colours, so a 16-entry palette has two spare entries to duplicate
    with, and `tools/p8_celeste.py` hill-climbs an arrangement in which every
    colour set the program needs lands inside some window. Terrain fell from
    268 slots to 118 (56%), and the sheet from 255 of 256 to **148**. No colour
    changed: the tile layer still matches the cart at 99.5%.
  - The title screen has no stars: the cart's `particles` are drawn with
    `rectfill`, and the console has no rectangle primitive. Its credits are
    white rather than colour 5, because the overlay has one colour register.

  **Fidelity, measured rather than asserted**: the tile layer matches the
  cart's own pixels at **99.49%** over the whole 128x120 playfield, against a
  reference rendered straight from the cart ROM, the residue being the player
  and its hair drawn over the terrain. A real PICO-8 capture of the same room
  via `tools/p8_capture.py` agrees, modulo the effects layer above. (Until the
  framebuffer off-by-one in `sim/console.cpp` was fixed, the same comparison
  read 90.1% as captured and 99.65% offset by one pixel.)

  The **music** is verified the same way, against real PICO-8 rather than
  against expectation: `tools/p8_music_trace.py` traces the cart's own
  sequencer, and pattern durations match this console's to within a frame
  (8.53 / 4.25 / 4.25 / 8.50 / 8.50 / 4.25 s against 8.50 / 4.27 / 4.20 / 8.50
  / 8.47 / 4.27). `make psg-analyze` confirms rendered pitch and requested waveform against
  the cart's note data — 31/31 rows within 0.05 semitones.

## The frame-pressure result

This is why a non-frame-bound corpus was added, and the answer is worth
recording plainly.

A programmer working against a frame budget hand-optimises, and
hand-optimisation *is* plumbing: values are kept in registers across statements,
stores are hoisted, loops are unrolled to keep `A` live. So it was entirely
possible that breakout's 32.9% was mostly an artifact of the frame budget rather
than a property of the instruction set — which would have meant the ISA slices'
projected savings were overstated.

| | Plumbing ratio |
| --- | --- |
| frame-bound (`breakout`) | 32.9% |
| not frame-bound (`nemo`) | 34.2% |
| difference | **+1.3%** |

**The ratio holds.** A program with no frame pressure at all, written in a
different genre with different data structures, lands within half a percentage
point - and it stayed within that band across three separate measurements as the
corpus grew from 1450 to 1811 instructions (32.6%, 33.3%, 34.2%) while the audio
and presentation layers were written. That stability across a near-30% growth in
code, by a programmer not tracking the metric, is a useful check that the figure
is a property of the instruction set and not of one snapshot. The accumulator toll booth and the flag ceremony are the instruction
set's doing, not the programmer's, and the ISA programme is aimed correctly.

Note the comparison is only legitimate *between* a frame-bound and a
non-frame-bound corpus for this specific question. For gate scoring, each corpus
is compared against its own recorded baseline; `isa_metrics.py` groups by class
and does not compare ratios across it.

**Registering `celeste` (frame-bound, 24.9%) drags the frame-bound average down
to 28.4% and makes `make metrics` print the opposite conclusion — +5.8% the
other way.** Do not read that number: it is a measurement artifact, and the next
section is the explanation. Corrected, celeste sits at 31.9% and the finding
above stands. The comparison table has been left as it was because the argument
it records was made against `breakout` and `nemo`, and it is still the argument
those two support.

## The pointer-setup blind spot

**The plumbing metric does not count pointer setup, and until a pointer-heavy
corpus existed there was nothing to notice.**

`plumbing` is defined as the accumulator toll (adjacent `lda`→`sta`), flag
ceremony, register transfers and stack spills. What it does not include is the
`ldy #FIELD` that has to precede every `(zp),Y` access to a struct field. In
breakout and nemo that is a rounding error. In celeste it is not:

| | `(zp),Y` sites | `ldy #imm` feeding one | as % of the program |
| --- | --- | --- | --- |
| `breakout` | 16 | 6 | 0.3% |
| `nemo` | 45 | 22 | 1.3% |
| `celeste` | 233 | **169** | **6.6%** |

Those 169 instructions do no work. They exist only to name a field of the
record the pointer already points at, and they are pure instruction-set cost —
the same kind of cost as the accumulator toll, arriving through a different
door. Adding them back:

| | reported | + pointer setup | corrected |
| --- | --- | --- | --- |
| `breakout` | 32.8% | 0.3% | 33.1% |
| `nemo` | 34.2% | 1.3% | 35.5% |
| `celeste` | 24.9% | 6.6% | **31.5%** |

So celeste is not a program with unusually little plumbing; it is a program
whose plumbing the metric was not built to see. Two consequences:

1. **`add-isa-pointer-ops` is understated by every measurement taken so far.**
   Its case is not only the 233 indirect accesses, it is the 169 immediate
   loads that address them. An addressing mode carrying a constant displacement
   would remove both halves.
2. **The metric definition should change**, and deliberately has not been
   changed here. `plumbing` is shared across all three corpora and every
   recorded baseline; moving it moves every number in this document at once.
   It belongs to `add-isa-ergonomic-gates` to decide, with all three corpora
   re-measured in the same commit.

Recorded by `add-celeste-corpus`, which is the corpus that could produce it.

## What each slice gets from which corpus

| Slice | breakout | nemo | celeste | Verdict |
| --- | --- | --- | --- | --- |
| `add-isa-core-ergonomics` | 232 `lda`→`sta`, 70 `clc`/`adc` | 194 `lda`→`sta`, 50 `clc`/`adc` | 225 `lda`→`sta`, 65 `clc`/`adc` | Confirmed three times over |
| `add-isa-test-and-branch` | 31 + 16 test-and-branch | 31 + 13 | 29 + 22 | Confirmed three times over |
| `add-isa-pointer-ops` | 19 `(zp),Y` — G3 not satisfied | **44 `(zp),Y`** plus indirect dispatch | **233 `(zp),Y`** plus 169 `ldy #field` and a jump-table dispatch | **Satisfied and then some.** See §The pointer-setup blind spot: the real cost is roughly double what the counts show |
| `add-isa-word-ops` | 119 high-half operands, no literal chains | 29 high-half operands | **117 high-half operands WITH the literal chains**: 37 `sec`/`sbc`, 65 `clc`/`adc`, six 16-bit add chains per object per frame in `move()` alone | **Satisfied.** G3 is now a pattern count, not a rewrite argument — which is what this corpus was commissioned for |
| `add-isa-frame-pointer` | 141 flat globals | 9 more, declared in one module purely to survive `jsr` | 12 file-scope bytes for `player_update`'s `local`s, live across four `jsr`s each; per-object state kept on the object instead | Improving; celeste gives the first case where the globals are demonstrably *locals* |
| `add-math-coprocessor` | — | one `mul8` per puzzle load, none per access | **none at all** — the two irrational dash constants are selected from a table, not computed | **Weakened again** — see below |

## The multiply finding

`add-nemo-corpus` expected this corpus to produce the first countable demand for
a hardware multiplier: the cart indexes cells as `(i-1)*pz_w+j` with `pz_w` read
at runtime, and none of the 50 puzzle widths (7, 9, 10, 11, 12, 13, 14, 15) is a
power of two, so the stride cannot be reached by shifting or strength-reduced at
assembly time.

**Written idiomatically, the multiply disappears.** A cell array is at most
15x15 = 225 bytes, so it fits in a page; both arrays are page-aligned; a row base
is therefore a single byte; and that byte table is built once per puzzle by
adding `pz_w` fifteen times. Every cell access is then one indexed load and one
`(zp),Y`. See the recorded decision at the top of `src/nemo/grid.asm`.

The port contains exactly one general multiply (`mul8`), called three times per
puzzle load. So this corpus is evidence *against* a math coprocessor for array
indexing, and evidence *for* cheap pointer setup. The naive reading — "a
non-power-of-two stride needs a multiply" — is wrong on this machine, and finding
that out is what the corpus was for.

## Two notes on the measurement

**The published breakout figures were slightly low.** `add-isa-ergonomic-gates`
records 1919 instructions and 460 toll for breakout; `tools/isa_metrics.py`
measures 1928 and 464. The whole difference is nine instructions that share a
line with a ca65 local label:

```
@wf: cmp SPR_FRAME      @cc: sta (ptr2),y      @r: lda #0
@w:  stx pnext          @ch: sta (ptr2),y      @c: sta (ptr),y
@cp: sta PLIFE,x        @cs: sta shadow,y      @n: dex
```

The earlier parser's label pattern did not admit `@name:`, so it skipped those
lines; two of them are the second half of an `lda`/`sta` pair, which accounts for
464 toll against 460. The corrected figures are the ones in the table above. The
gates' 2% parser-drift tolerance would have absorbed this, but it is better
explained than absorbed.

**The data files contribute nothing.** `breakout_data.asm`,
`breakout_tables.asm` and `breakout_sfx.asm` contain zero instructions - they are
pure `.byte` tables - so breakout's count comes entirely from `src/main.asm`.

## Frame-pointer evidence that is not a count

`add-isa-frame-pointer` has no pattern to count: a corpus cannot show demand for
a feature it has no way to express. Writing this port produced the next best
thing - two bugs that cost real debugging time, both caused by a routine keeping
a value in a shared zero-page byte across a `jsr`:

1. `map_box` used `box_i`/`box_n` as its loop counters. It is called *from* the
   puzzle-box strip loop, which used the same two bytes, so the call overwrote
   its caller's counter and the program hung. The whole menu went blank because
   `sel_draw` never returned to blit the overlay.
2. `glyph_at` kept its glyph-row counter in `t3` and its row bitmap in `t4`.
   Scaling a glyph made it call `ovl_hline`, which uses `t3` as a length and `t4`
   as a step - so at any scale above 1 the row counter was zeroed on every pixel
   plotted, and it looped forever. At scale 1 the code short-circuits past
   `ovl_hline`, which is why it worked until the moment it was scaled.

3. `sfx_play` used `t0` for its channel-busy mask. `ev_emit` keeps its loop
   counter in `t0`, and an event handler calls `sfx_play` - so the first cursor
   move in a puzzle hung the game.
4. `glyph_at`'s row counter again, after the wordmark became sprites: the same
   `t3`/`ovl_hline` collision reappeared in a second caller.

None of these is exotic. All are the direct consequence of having no
callee-private storage, all presented as a hang rather than a wrong pixel, and
all were found by bisecting with an instruction-level tracer rather than by
reading the code. Four occurrences in one 1700-instruction program, by a
programmer who knew the hazard and was watching for it. The port now declares **28 bytes** of zero page whose only
purpose is to not be someone else's temporary - see the comments in
`src/nemo/memmap.asm`. On a machine with a frame pointer, all 28 would be stack
slots and neither bug could have happened.

## A fourth corpus?

The three registered corpora between them cover frame-bound and not, action and
puzzle, pointer-light and pointer-heavy. The gap they share: **none of them
exercises multi-byte arithmetic heavily**, which is why `add-celeste-corpus` is
still needed before `add-isa-word-ops` can be scored on a literal pattern count
rather than a rewrite argument.

Beyond that, a fourth corpus would need to add something these do not. Candidates
worth considering only if a slice needs them: a program with deep call nesting
(for `add-isa-frame-pointer`), or one that is genuinely CPU-bound (none of the
three is).

## Attribution

Each port is an original 6502 implementation of the game's logic, written for
this hardware. Art, level and puzzle data are extracted from the original carts
and used with attribution to their authors:

- **Breakout Hero** — (c) Krystman / Lazy Devs Academy, PICO-8 BBS cart 53976.
- **NEMO - Puzzle Pack II** — (c) mooon, PICO-8 BBS `pid=109965`, cart revision
  1.01 (2022-09-19). Puzzle designs are the author's. The cart's music is from
  Gruber's *Pico-8 Tunes Volume 1* and is used by this port as the cart shipped
  it, so that attribution carries over.

Extraction tooling: `tools/p8_audio.py` (cart ROM and code decompression, both
the old `:c:` and the 0.2.x `pxa` formats) and `tools/p8_nemo.py` (puzzle table).
