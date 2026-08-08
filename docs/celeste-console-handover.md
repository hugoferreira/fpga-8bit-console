# Handover: the Celeste console — performance, fidelity, and the new PPU controls

State as of `0f70da9` (2026-08-08), covering the eight-commit arc from
`853bfd2`. Everything below is measured, not estimated; re-measure before
trusting any number on different hardware or after unrelated changes.

## Where things stand

- **`make run game=celeste` is real-time with clean audio.** Free-running
  gameplay measures 86–90 fps against the 60.0 the live audio queue needs;
  the interactive run delivers 44,099 samples/s to the 44,100 Hz device
  with zero drops (was 52 drops + 1,200 near-dry frames per two minutes
  before `7424576`).
- **`PSG_CLK_DIV=2` is the simulator default.** The preview walk's worst
  case is 1 + 8×9 + 3 = 76 clocks against the 79.5 supplied
  (`853bfd2`); the acceptance test is
  `make test-psg-preview-recovery PSG_RECOVERY_CLK=1753290`, never the
  pitch gate alone.
- **The game tick fits its display frame.** 896/898 ticks on time under
  aggressive play in the fall-floor room (was ~13% late). The two
  residuals are room entry and death respawn — `load_room` in one tick.
- **Fidelity against the cart** (reference: `tools/p8_unpack.py` on the
  `.p8.png`) is close: death burst, room banner with black panels and the
  h:mm:ss clock, spring/fall-floor couplings both ways, full-hair recolour,
  three-frame key spin, lifeup "1000" with the white/red flash, platforms
  behind terrain, cart-exact snow (colours 6/7, 80% single-pixel), title
  centred on the 160-column display.

## The mental model that matters

**The 30 Hz game tick's budget is ONE display frame, not two.** `update`
writes `game.frames` right after a vsync boundary; if update+draw spill
past that frame's end (~58,443 CPU clocks minus DMA), the two `wait_frame`
calls quantize the tick to three frames. The second display frame is idle
by construction — `Game.frame` runs one `Draw.overlay_phase` there, which
is why the overlay rebuild (clear / glyphs / blit, ~50–60k cycles total)
no longer competes with update+draw. Bursts break ticks; average load
never has.

**The simulator's host cost has no big single target.** Per-module
attribution (`--prof-cfuncs` + macOS `sample`): psg_seq 10.4%,
cpu6502_core 8.8%, the whole PPU family ~16% across seven modules of ≤5%
each, ~48% in Verilator's eval machinery and unattributed inlines.
Verilator `--threads 2` collapses this model to 8.6 fps (per-eval sync ≫
microsecond evals); `-O3` beats `-O2` by ~3%; `-march=native` adds
nothing. If a future game needs more headroom, psg_seq and the 6502 core
are the only ~10% doors.

## New PPU register map entries (`ef3bae6`)

- `$38` overlay row-colour index (auto-increments on `$39` writes);
  `$39` data — bit 7 override, bits 3:0 the colour that row's overlay
  pixels take instead of the global `$06`. 128×5 RAM in `ppu_display`;
  zeroed rows fall back to `$06`, so untouched programs are bit-identical.
- `$3A` staged sprite control, bit 0 = composite behind the tile layer,
  latched into each committed entry (the list is 35 bits now). Additive
  with the `$36` split: behind ⇔ `index < split || bit`. While no
  committed entry carries the bit (latch cleared by a `$0C` write), the
  scan is the original single partitioned walk at the original cost —
  the unconditional double-walk broke the 128-entry stress line's
  483-clock budget, so the price is paid only in use.
- Golden scene 10 (`rowlut`) freezes both. `make ppu-check` is the gate;
  `PPUARGS=+regen` re-freezes deliberately, and frames 0–9 must come out
  byte-identical when the change claims compatibility.

Celeste uses all three: black `rectfill` panels are colour-0 solid
sprites under the overlay text, the lifeup flashes rows 7/8 through the
LUT (clearing its previous rows every draw, on destroy, and wholesale in
`Room.load`), platforms set the behind bit around their two cells.

## Traps that already cost time here

1. **The `$4000` code overflow.** Celeste's code starts at `$0300` and
   grew into the MMIO window: `title_tick` assembled over the video
   registers. Boots, ticks, reads registers normally — then executes
   register bytes at the first keypress. On the console it looked like
   dead input and missing sprites; the python rig named it (BrkTrap at
   `$4057`). `main.inlay.asm` now splits code at `$4200` and asserts both
   region bounds (`#assert label <= bound`; there is no `le()`). If the
   console misbehaves after a game edit but the rig passes early frames,
   **check `build/celeste.lbl` for symbols in `$4000-$41FF` first.**
2. **`bpl` after `cmp` reads the subtraction's sign, not A's.** This
   sequencing kept the room banner from ever rendering, invisibly to
   every gate. Sign-test A before any `cmp`.
3. **Stale builds.** After editing `src/celeste/**`:
   `rm -f build/inlay/celeste.asm build/inlay/.celeste-prepared`, rebuild,
   and only then trust a green run (one-second mtime race).
4. **The generator is byte-reproducible — verify before trusting a
   regen** (`--out` to a scratch dir, diff). Adding a colour set to
   `wanted` before `search_palette` is mandatory or the fit can shift.
   The Inlay frontend resolves enum immediates only in `mov`/`cmp`
   spellings, and `inc`/`dec` do not take indexed overlay operands.
5. **Same-session A/B only.** A 69.8 fps "baseline" measured beside
   running test suites cost an afternoon of false conclusions; the same
   build idles at 86.
6. **"Near-dry" is an operating-level statistic, not an audible event.**
   The audible events are "dropped" and "truly starved" in the delivery
   line. Do not chase near-dry.

## The intentional-change pins (re-freeze, in this order, after any game edit)

`make test-celeste` runs both halves. `tools/inlay/test_conformance.py`
pins: module/export/label manifests (Draw, Gfx), gfx table boundaries,
`EXPECTED_CELESTE_{TYPED,OVERLAY}_OPERATIONS`, `_SEMANTIC_OFFSETS`,
`_RAW_OBJECT_INDIRECTS`, `_COUNTED_SHIFTS`, and
`EXPECTED_CELESTE_ROM_SHA256`. `tools/test_celeste.py` pins four
deterministic `VISUAL_CHECKPOINTS` — re-freeze them only after their
neighbouring content checks pass. The boot settle is `frames(6)` because
the staged overlay blits credits on the third tick.

## Diagnostic tooling built for this work

- `console --peek <addr>`: per-display-frame change-interval histogram of
  one RAM byte. Point at `$30` to separate emulated slowdown (3+ frame
  ticks) from host slowdown.
- `console --profile-from <frame> --sym build/celeste.sym`: emulated-CPU
  PC sampling with symbol aggregation; combined with `--peek` it also
  emits an overrun-only histogram — the work profile of exactly the late
  ticks, which is what convicted the overlay rebuild when the average
  profile pointed at collision.
- The python rig (`tools/test_celeste.py`) runs the real binary with the
  PPU faked and exposes ovl/map/objects/registers — probe new mechanics
  there before hunting them in Verilator screenshots. Room-4 boot for
  screenshots: patch `begin_play`'s `lda #1` to `lda #4`, never commit it.

## Known remaining deviations from the cart (deliberate or bounded)

- Banner/lifeup text carries no per-element colour beyond the row LUT;
  the overlay remains one colour per row per frame.
- Fruit bob period 64 frames vs the cart's 40; cloud heights constant
  8 px vs 4..16; freeze skips update but not the (identical) redraw;
  the banner panel does not shake with the screen for the ~5 overlap
  frames of a spawn.
- The sidebar TIME/DEAD HUD is deliberate port design in the 32 columns
  the cart never had (documented at `Draw.hud`).
- Two-dash hair flash variants are absent: the ten-room slice never
  grants a second dash. Rooms beyond level 9 (message, big chest, orb,
  flag) are outside the resident campaign.
- Pre-existing and unrelated to this arc: oracle `mix-four` differs from
  the frozen set (accepted H165 onset delta, re-freeze authorized), and
  the hardware-schedule `psg_budget_tb` functional suite fails the same
  4 checks it failed before ([14] start row/length, [20d] eight slots).

## If the next task is more speed

Ranked by measured ceiling: psg_seq host cost (10.4%, a 63-state FSM
evaluated per psgclk), cpu6502_core (8.8%), then nothing bigger than 5%.
The PPU is done: the blit enable (`0f70da9`) was the one concentrated
target and it was host-neutral (kept for −10 LC / +1.4 MHz on hx8k).
For emulated speed, the residual burst is `load_room`'s single-tick room
rebuild (~one 3-frame tick per entry/death); stage it like the overlay if
a cart ever makes transitions frequent.
