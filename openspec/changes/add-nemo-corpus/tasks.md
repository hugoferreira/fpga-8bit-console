## 1. Preliminaries

- [x] 1.1 Confirm the attribution posture for **both** parties before writing code:
      mooon for the code and the 50 puzzle designs, Gruber for the music via
      *Pico-8 Tunes Volume 1*, following the convention at `src/main.asm:5-7`
- [x] 1.1a **Implement PXA decompression.** `tools/p8_audio.py`'s `pxa_decompress`
      was a `SystemExit` stub, so the pipeline could not read *any* PICO-8 0.2.x
      cart — NEMO included. Now implemented and self-checking: it verifies the
      consumed bit stream against the header's `com_size`
- [x] 1.2 Extract the cart (`nemonemo2-1.p8.png`) with the p8.png pipeline; cart
      revision recorded as `ver="1.01"`, `latest_update 2022/09/19`
- [x] 1.3 Read the Lua and inventory the systems before porting — see
      `inventory.md`. Two findings contradict this change's original assumptions and
      have been corrected in `proposal.md` and `design.md`
- [x] 1.4 Music: **included** (this reversed an earlier call to omit it). The
      cart's whole audio image uploads verbatim, all 18 music patterns and 7 SFX
      are wired from the cart's own call sites, and Gruber's attribution carries
      over. Omitting it had left the port obviously unfinished

## 2. Data extraction

- [x] 2.1 Decode the cart's string-encoded puzzle data and re-encode it for the port
      — `tools/p8_nemo.py`. Divergence recorded in the generated header: rows are
      padded to 2 bytes so the *bitmap* walk is shiftable, while the cell array the
      game plays on keeps the `y*w` stride
- [x] 2.2 Extract the 50 puzzle solutions and verify them. **Task as written was not
      possible** — the cart does not store clue sets, it derives them at runtime in
      `update_puzzle_numbers`, so there is nothing to compare against. Verified
      instead by rendering each bitmap and checking it against its own record name:
      `scissors`, `dino`, `mic` and `snake` are all unmistakable
- [x] 2.2a All 50 checked: 15 rows each, blank padding below the puzzle's height,
      and a fill fraction between 15% and 85% (so nothing is near-empty or
      near-solid). Spot-rendered `scissors`, `dino`, `mic`, `snake`, `super man`
      and `right x`; all recognisable. Four names contain spaces, which broke the
      first checker's pattern
- [x] 2.3 Presentation assets. The cart's spritesheet is nearly empty (twelve UI
      glyphs and a box) because it draws procedurally, so there is no sprite art to
      port - but "no assets" was the wrong conclusion to draw from that, and the
      first cut of this port was 1bpp white-on-black as a result. Now: tiles carry
      colour, the overlay carries a 36-glyph 4x6 font (letters taken from
      Breakout's `font46`, with J/Q/Z added), and the wordmark is re-laid on the
      tile grid. See `src/nemo/tiles.asm`
- [x] 2.4 Dropped with the music decision (1.4)

## 3. The port

- [x] 3.1 Grid representation - `grid.asm`. A byte per cell rather than a packed
      bitfield: the board is read far more often than written, so a byte keeps the
      match-check inner loop branch-free
- [x] 3.2 **Grid addressing.** Row-base byte table, built once per puzzle by repeated
      addition; every access is one indexed load plus `(zp),Y`. Decision and full
      reasoning recorded at the top of `src/nemo/grid.asm`. It overturns this
      change's own multiply prediction, which is the evidence it existed to produce
- [x] 3.3 Puzzle decoder - `bitmap_expand` in `puzzle.asm`
- [x] 3.4 Clue derivation and validation - `clues.asm`
- [x] 3.5 Cursor and input - `input.asm`, `draw_cursor`. The colour highlight
      becomes a blinking outline plus suppression of matched clue strips (1bpp)
- [x] 3.6 Clue rendering and puzzle select - `scene.asm`, `select.asm`
- [x] 3.7 Progress tracking in RAM - `progress_get/set` in `puzzle.asm`, 7 bytes.
      A completed puzzle shows a bar on the select screen; there is no
      "not saved" notice yet
- [x] 3.8 Header comment in `src/nemo/main.asm`
- [x] 3.9 Plays end to end (**gate N1**). `make test-nemo` runs two suites on the
      assembled binary under `tools/sim6502.py`:
      `test_nemo.py` calls the routines directly (mul8, all 50 puzzles' expansion
      and clue derivation against an independent model, win detection, a rendered
      overlay dump), and `test_nemo_loop.py` drives the whole program from the reset
      vector through its vsync loop with fake button presses - select, clamping,
      start, cursor movement, fill/mark toggling in all four combinations, edge
      clamping on all four sides, the winning move detected through the event bus,
      the progress bit, dismissal, reload, and 400 idle frames.
      **Still not run on real hardware or in the Verilator simulator** - see 7.1

## 4. Hardware gaps

- [x] 4.1 Record the **persistent storage** gap in `docs/hardware-gaps.md`: the
      original uses PICO-8 `cartdata()`; nothing in `rtl/` implements EEPROM, flash or
      NVRAM; the port keeps progress in RAM. Note that the smallest useful fix is a
      few bytes behind an MMIO window, not a filesystem (**gate N4**)
- [x] 4.2 Record the **multiply** finding. It landed as a *NOT recommended* entry
      rather than a gap: written idiomatically the per-access multiply disappears
      (one `mul8` per puzzle load, none per cell). The entry also records that the
      hx8k has no `SB_MAC16` cells, so any multiplier would be a LUT-based shift-add
      sequencer rather than an inferred DSP block (**gate N4**)
- [x] 4.3 Feed both entries to their downstream proposals: the multiply gap is the
      first measured demand for the deferred `add-math-coprocessor`, and changes its
      cost basis from "infer a DSP block" to "spend LUTs on a shift-add sequencer"
- [x] 4.4 Confirm no behaviour was quietly degraded without an entry

## 5. Measurement

- [x] 5.1 Register the corpus in `docs/corpora.md` with `frame_bound: false`, its
      implemented systems, its divergences, and which gates it can and cannot inform
- [x] 5.2 Add the `frame_bound` flag to the corpus manifest and carry it through
      `tools/isa_metrics.py` onto every derived ratio
- [x] 5.3 Group plumbing ratios by `frame_bound` in the gate report, and never compare
      across the classes directly (**gate N5**)
- [x] 5.4 Report the frame-work gate as *structurally inapplicable* for this corpus,
      distinctly from *not yet measured*
- [x] 5.6 Report counts for the new idiom families: non-power-of-two 2D
      indexing, sequential stream decode, packed bitfield test/set/clear
      (**gate N3**)
- [x] 5.7 **Compared: 32.9% frame-bound vs 33.3% not - a +0.4% difference.** The
      ratio holds without frame pressure, so it is the instruction set's doing rather
      than hand-optimisation, and the slices' projected savings stand. Recorded with
      the reasoning in `docs/corpora.md`

## 6. Cross-corpus integration

- [x] 6.1 Amend `add-celeste-corpus`: its residual single-genre risk is addressed
      here; update the deferred "non-game third corpus" note to record that a puzzle
      game was chosen over a utility, and why
- [x] 6.2 State in `docs/corpora.md` what a **fourth** corpus would have to add that
      these three do not; if the answer is nothing, close the question
- [x] 6.3 Note in `docs/corpora.md` that this corpus exercises the PPU thinly, so it
      complements the action carts on the CPU axis and tells us less about the PPU
- [ ] 6.4 Confirm every ISA slice's migration and measurement covers all
      registered corpora, and update the slice task lists that assume one. Two are
      registered today; `add-celeste-corpus` makes it three

## 7. Remaining before this change can be archived

- [x] 7.1 Run in the Verilator simulator. `make run-nemo` plays it; the headless
      mode added to `sim/console.cpp` (`--headless --frames N --shot f.ppm --keys
      20:x,60:o`) captures frames without a display, and the menu, wordmark, bars,
      text, green field, puzzle grid, cells, marks, sprite cursor and clue strips
      were all verified against the real compositor. Audio verified as PCM
      activity. **Not yet run on real hardware.**
- [ ] 7.1a Run on the FPGA
- [ ] 7.2 Record the pre-slice baseline in `docs/isa-baseline.json` (**gate N2**).
      Blocked on `add-isa-ergonomic-gates` creating that file; the numbers are
      already produced by `make metrics`
- [x] 7.3 Reconciled. The gates' 1919/460 undercounts by exactly nine
      instructions that share a line with a ca65 local label (`@wf: cmp
      SPR_FRAME` and eight others); the earlier parser's label pattern did not
      admit `@name:`. Two of the nine are the `sta` half of an `lda`/`sta` pair,
      which is the 464-vs-460 toll gap. Written up in `docs/corpora.md`
- [x] 7.4 **Decided against** an in-game "progress not saved" notice. The cart has
      no such text and adding it would be the port inventing UI to apologise for
      the hardware. The gap is recorded in `docs/hardware-gaps.md` and
      `docs/corpora.md`, which is where a hardware limitation belongs
- [x] 7.5 Amended `add-isa-pointer-ops`: G3 satisfied by nemo's `(zp),Y` count
- [x] 7.6 Amended the `add-math-coprocessor` premise in `add-isa-ergonomic-gates`
- [x] 7.7 Presentation gaps closed: the numbered puzzle-box strip (a three-wide
      window on the list, selected box orange-filled and tethered to the call to
      action) and the checkered drop shadow under the wordmark
- [x] 7.8a Wordmark animated: 44 sprites, one per block, each bobbing on its own
      phase; the checkered shadow is baked into the same pattern
- [ ] 7.8b Puzzle boxes do not bob yet. Their orange fill is a tile, so smooth
      motion needs them as sprites too (9 per box x 3 = 27 more entries)
- [ ] 7.8c Text drop shadow: needs overlay blit modes (hardware-gaps entry 8) or
      sprite-based text. The cat icon is still missing.
