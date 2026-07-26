## 1. Preliminaries

- [x] 1.1 Attribution posture confirmed before writing code, following the
      convention at `src/main.asm:5-7`: original 6502 implementation of the game
      logic, cart art/map/SFX data used with attribution to Matt Thorson and
      Noel Berry. Recorded in `src/celeste/main.inlay.asm` and `docs/corpora.md`
- [x] 1.2 Cart extracted from the BBS thread (`tid=2145`) with the p8.png
      pipeline: `cposts/1/15133.p8.png`, the **"Fixed for P8 v0.1.2"** revision
      the task anticipated, posted 2015-10-08. Kept out of the repo at
      `~/Stuff/carts/celeste-15133.p8.png`, as the other carts are
- [x] 1.3 Lua read and the systems inventoried before porting — see
      `inventory.md`. Three findings contradicted this change's assumptions:
      the tilemap window is write-only so the port needs its own `mget`; the
      HUD belongs in the overlay, which frees the whole tile world for two
      resident rooms; and screen shake cannot be done with the camera registers
      because they move the tile layer only
- [x] 1.4 Stage-1 rooms chosen for tile-flag variety, not progression order:
      **0** (the first room, baseline), **11** ("old site", the only substantial
      ice room — 9 ice tiles against 19 solid, with ice adjacent to ordinary
      ground) and **20** (all four spike orientations against only 9 solid
      tiles). Reasoning in `inventory.md`

## 2. Asset extraction

- [x] 2.1 Spritemap converted — `tools/p8_celeste.py`. The console's palette
      **is** the PICO-8 palette, so 4bpp patterns upload with palette base 0 and
      pixel value == colour index: the art is the cart's, pixel for pixel, with
      no recolouring step at all
- [x] 2.2 The three rooms converted to tilemap cells. A room is 256 of the tile
      world's 512 cells, so **two rooms are resident** and a load never tears —
      the new room is written into the off-screen bank and the camera flips to
      it
- [x] 2.3 PICO-8 tile flags mapped. **Task as written was not possible**: a map
      cell's attribute byte is fully spent on {palette, bpp, flips}, with no bit
      free for `solid` or `ice`. The flags live in a 128-byte CPU-side table
      instead, which is what `fget` was anyway
- [x] 2.4 The cart's audio image uploads verbatim (`tools/p8_audio.py`), 4608
      bytes to PSG address $3100. The cart's own `music(0,0,7)` mask is honest —
      unlike nemo's — so it is used as the cart passes it
- [x] 2.4a **All of the cart's music is ported, and the game starts where the
      cart starts.** `title_screen` plays music 40 and loads level 31;
      `begin_game` plays music 0; `start_game` cuts it with `music(-1)`; all
      four `next_room` cues are a table (30/20/30/30 by level, 500 ms fade =
      31 PSG units); the `music_timer` countdown that restores music 10 is
      implemented. Asserted in `tools/test_celeste.py` by recording the PSG
      writes, not by ear
- [x] 2.5 Palette mapping confirmed by measurement rather than by eye: the tile
      layer matches a reference rendered straight from the cart ROM at **99.49%**
      over the whole 128x120 playfield (the residue is the player drawn over the
      terrain), and a real PICO-8 capture of the same room agrees modulo the
      effects layer
- [x] 2.5a **Sheet budget: 148 of 256 slots**, for 75 terrain tiles (the three
      playing rooms plus the title logo), 7 player frames, 3 smoke frames and 2
      hair blobs — with 108 slots spare for stage 2
- [x] 2.5b **The 2bpp terrain encoding, done.** Patterns store palette-relative
      values instead of PICO-8 colour indices, and a generated draw palette maps
      them back, so cost follows a tile's colour COUNT rather than its colour
      VALUES: 18 tiles at 1bpp, 47 at 2bpp, 2 at 3bpp, and 8 fully transparent
      tiles that now cost nothing at all. Terrain went from 268 slots to 118
      (56% saved) and the whole sheet from 255 to 148. The player dropped to
      3bpp as a side effect — its five colours fit a 7-entry window.
      Choosing the palette is a small combinatorial problem (14 distinct
      colours, 16 entries, every colour set needing to land inside some window);
      `tools/p8_celeste.py` hill-climbs it from a fixed seed, landing 2 slots
      above the theoretical floor of 144. **Verified by measurement, not by
      eye**: the tile layer still matches the cart at 99.5%, and both
      screenshots are pixel-identical to the 4bpp build

## 3. Stage 1 — the engine

- [x] 3.1 Object list: a 16-slot pool of 64-byte records, page-aligned, with
      per-type `init`/`update`/`draw`. **The dispatch is a jump table**, and the
      reason is recorded at the top of `src/celeste/obj.inlay.asm`: the cart's types
      are tables with optional methods and `load_room` already maps a tile id to
      a type, so a table was the shape of the data before it was the shape of
      the code. Cost: eight instructions per dispatch, of which one does work
- [x] 3.2 `move()` with 16-bit sub-pixel remainders, per axis, per object, in
      8.8. Not hand-optimised into integer tables — the idiom is the point. In
      8.8 the cart's `flr(rem + 0.5)` is one 16-bit add and one byte subtract,
      because `flr()` of an 8.8 word is its high byte
- [x] 3.3 Collision: `is_solid`, `is_ice`, `tile_flag_at` over the RAM room
      copy, and `spikes_at` with all four orientations and their edge tests.
      The cart's `is_solid` also consults fall_floor/fake_wall/platform; those
      types do not exist in stage 1, so those checks are **absent rather than
      stubbed** — dead code would be counted by the corpus metrics as if it were
      real
- [x] 3.4 Player entity: run, ice and air acceleration, wall slide, grace,
      jump buffer, wall jump, dash in eight directions with its freeze and
      shake, animation frames, death and respawn
- [x] 3.5 Room transitions and the camera, including the vertical follow that
      covers 128 lines in a 120-line window via camera Y at `$4004`
- [x] 3.5a **The title screen.** Level 31 is resident as room slot 0, drawn 4
      pixels left the way the cart's `map(..., off, 0, ...)` draws it (camera X
      + 4, clip 4 short so the neighbouring bank cannot show through), with the
      credits on the overlay and no room title. Jump or dash arms the cart's
      80-frame flash, which is the one effect the port reproduces by the *same
      mechanism* as the original: `pal(6,c) pal(12,c) ...` is the console's
      screen palette at `$4020`, applied to every displayed pixel
- [x] 3.6 HUD in the 32 spare columns, in the overlay rather than the tile layer
      (finding 1.3): clock and death count
- [x] 3.7 Header comment recording the attribution and every divergence
- [x] 3.8 **Gate C1.** Runs in the Verilator simulator at 60 fps display / 30 Hz
      logic — the cart defines `_update`, which PICO-8 runs at 30 fps, so the
      physics constants are the cart's own numbers. `make run GAME=celeste`
      plays it; `make shot GAME=celeste` captures headlessly. Player moves,
      dashes, collides, dies and rooms transition. **Not yet run on real
      hardware** — see 7.1
- [x] 3.9 `make test-celeste`: the whole program driven from the reset vector
      under `tools/sim6502.py` with the PPU faked — spawn animation handover,
      gravity and landing, sub-pixel accumulation, maxrun clamping, facing,
      jump, dash into a wall (which stops at exactly the pixel the room data
      says it should), smoke lifetime, sprite staging, spikes, restart, the
      clock, the HUD read back **out of the overlay bitmap**, room transition,
      the title screen, the start-game flash and every music cue (asserted from
      recorded PSG writes). 39 checks

## 4. Measurement

- [x] 4.1 Corpus registered in `tools/isa_metrics.py` — one entry, the
      hand-written files only. Generated data contributes no instructions and
      listing it would only inflate the file count
- [x] 4.2 Gates are already reported per corpus and never pooled; celeste
      appears as its own row and column (**gate C4**)
- [x] 4.4 The three weak slices' counts reported specifically (**gate C3**), in
      `docs/corpora.md` §What each slice gets from which corpus:
      **word-ops 117 high-half operands with literal chains** (36 `sec`/`sbc`,
      64 `clc`/`adc`), **pointer-ops 233 `(zp),Y` plus 169 `ldy #field`** (6.6% of the program),
      **frame-pointer 12 file-scope bytes that are `local`s in the cart, live
      across four `jsr`s each**
- [x] 4.4a **C3 did not fail informatively — it passed.** The design flagged
      that if Celeste also showed no 16-bit chains, word-ops would need
      re-arguing rather than re-measuring. It shows them: six 16-bit add chains
      per object per frame in `move()` alone. `add-isa-word-ops` G3 is now a
      pattern count
- [x] 4.4b **The pointer-setup blind spot** — the finding this corpus produced
      that nobody asked for. The plumbing metric counts the accumulator toll,
      ceremony, transfers and spills, but not the `ldy #FIELD` that must precede
      every `(zp),Y` struct access: 6 sites in breakout, 22 in nemo, **169 in
      celeste (7.0% of the program)**. So celeste's reported 24.9% is not a
      program with little plumbing, it is plumbing the metric cannot see;
      corrected it is 31.9%, in line with the others. Recorded in
      `docs/corpora.md`, with the metric deliberately **not** changed — see 5.6
- [ ] 4.3 Record the pre-slice baseline in `docs/isa-baseline.json` (**gate
      C2**). Blocked on `add-isa-ergonomic-gates` creating that file; the
      numbers are produced by `make metrics` today. Same blocker as nemo's 7.2
- [ ] 4.5 Deterministic input replay for the frame-work cycle counter (gate G8).
      The key script in `sim/console.cpp --keys` is the mechanism; what is
      missing is the cycle counter, which belongs to the gates change
- [ ] 4.6 G5/G6 regression enforcement — the report exists, the failure
      condition does not. Belongs to `add-isa-ergonomic-gates`
- [ ] 4.7 Fail the metrics run on a corpus that is measured but not registered

## 5. Documentation and coordination

- [x] 5.1 `docs/corpora.md`: celeste registered with what it is, which systems
      are implemented, what it measures well and badly, and its divergences
      (**gate C5**)
- [x] 5.5 Two agents are working in this checkout at once; the file ownership
      and shared-file protocol are in `docs/agent-coordination.md`, along with
      the requests raised in both directions
- [x] 5.6 **Proposed, not taken**: the plumbing metric should count pointer
      setup. `plumbing` is shared by all three corpora and every recorded
      baseline, so changing it moves every number in `docs/corpora.md` at once.
      It belongs to `add-isa-ergonomic-gates`, with all three corpora
      re-measured in the same commit
- [x] 5.7 Filed against `sim/console.cpp`: the framebuffer is shifted one pixel
      right and captured 121 rows tall, because `hpos` is incremented before the
      pixel is stored. Measured, not inferred — the tile layer matches at 90.1%
      as captured and 99.65% offset by one. nemo's file, nemo's fix; celeste's
      screenshot comparisons allow the offset and say so
- [ ] 5.2 Amend `add-isa-ergonomic-gates`: resolve the second-corpus open
      question, restate the one-corpus risk mitigation, and restate G3/G5/G6/G8
      as per-corpus gates
- [ ] 5.3 Record in the opcode registry, for every instruction whose G3 evidence
      is asymmetric, the count in each corpus
- [ ] 5.4 Re-score any ISA slice that landed before this corpus existed

## 6. Stage 2 — content (optional, not gating)

- [ ] 6.1 The remaining rooms, which need the 2bpp terrain encoding (2.5a)
- [ ] 6.2 Strawberries and the collection count
- [ ] 6.3 Balloons, springs, fake walls, the key and chest, platforms. These
      bring back `obj_collide` and the three object checks `is_solid` drops in
      stage 1 (3.3), so they are the first thing that will change the
      pointer-ops counts
- [x] 6.4a **Clouds and particles, done — with no hardware change at all.**
      The first reading of this said clouds needed a background-capable
      framebuffer layer (`hardware-gaps.md` entry 9). That was wrong: the sprite
      list is ORDERED, and the behind-split at `$4036` already partitions it, so
      clouds staged before the split composite behind the tile layer and
      particles staged after it land in front. `src/celeste/fx.inlay.asm`. The
      particles also put the stars back on the title screen, which the cart
      draws unconditionally.
      Counts were first reduced to 12/16 because a cloud is a run of 8x8 cells
      and the cart's 17/25 came to 133 entries; the repeat field in 6.4b then
      removed that limit and the cart's counts went back in
- [x] 6.4b **The repeat field, built** — `rtl/sprite_compositor.sv` `$4037`,
      and the port now runs **the cart's own 17 clouds and 25 particles**, at
      46 list entries instead of 133. A cloud is one entry whatever its width.
      Hardware cost as estimated: entry 31 -> 34 bits, a staging register, a
      3-bit counter and one state transition at `E_WR1` that re-blits the row
      already in `prow` instead of re-fetching it. Reset value 1 keeps breakout
      and nemo bit-identical. Proved by an equivalence test in the compositor's
      own testbench: rep=8 is pixel-identical to eight entries across all
      19200 pixels
- [ ] 6.4c Snow, the death burst and the ending sequences
- [ ] 6.5 Re-measure and confirm no gate verdict flips as the corpus grows

## 7. Remaining before this change can be archived

- [ ] 7.1 Run on the FPGA
- [ ] 7.2 Decide the `move_x`/`move_y` off-by-one. The cart's loop is
      `for i = start, abs(amount)`, which is `abs+1` iterations, so an
      unobstructed object travels one pixel further than its speed says. It is
      transliterated as-is and flagged in `obj.asm`; a frame-by-frame comparison
      against `tools/p8_capture.py` would settle whether the original really
      plays that way or whether the cart's `rem` bookkeeping hides it
- [ ] 7.3 The room title has no black panel behind it, and the title credits
      are white rather than colour 5 (the overlay has one colour register).
      Same gap as nemo's text shadow — `hardware-gaps.md` entry 8
- [x] 7.5 **The sheet is no longer full** — see 2.5b. 148 of 256 slots, so a
      stage-2 room set has room to land
- [ ] 7.4 Sprites partially off the top of the screen are dropped rather than
      clipped, because `SPR_Y` is 7 bits and a negative y would reappear at the
      bottom. Visible for a frame or two when the player exits upward
