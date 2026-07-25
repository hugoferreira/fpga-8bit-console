## Why

`rtl/sprite_compositor.sv` is 620 lines and one module. It holds the register
file, the tilemap walk, the sprite scan, the pattern fetch, the blit datapath,
the line buffer, the overlay and the display mux, all in a single `always_ff`
with a ten-state FSM. Four features have been added to it since it was written
(behind-split `$36`, draw state `$10-$35`, the overlay, the repeat count `$37`)
and each one has been a patch into the middle of that FSM.

**Measured, not asserted.** Synthesised standalone for the hx8k:

| | | |
| --- | --- | --- |
| LUT4 | 1846 | logic cells 2623 of 7680 — **34%** |
| Carry | 340 | |
| Flip-flops | 678 | |
| **Block RAM** | **16 of 32** | **50% of the whole device** |
| Fmax | 62.6 MHz | critical path `entry_q` → `bmask` → line-buffer write data |

Two of those numbers set the agenda:

- **The PPU owns half the device's block RAM** (sheet 16 kbit, overlay 20 kbit,
  tilemap 8 kbit, line buffer 2 kbit — and the PSG takes another 36 kbit).
  Every feature discussed next needs storage: a second overlay plane
  (`hardware-gaps.md` entry 9) is +5 BRAMs, and there are five left.
- **The critical path is the blit**, and nextpnr names it: from the entry
  register through `bmask`, the per-pixel palette lookup, the 64-bit barrel
  shift and the merge, into the line-buffer write port — all in one clock.
  That is also the only path that gets *longer* when pixel formats grow.

**Why now.** The PSG went through exactly this and came out able to absorb
filters, fades and a mixer rewrite (`4e5f84c`, "refold the datapath"). The PPU
is where the next several features land, and it is currently the least
modular part of the console. Refactoring after those features is strictly more
expensive than before them.

**What makes it safe now, and did not before.** The compositor's testbench
renders 96 frames and dumps PPMs — it has never *compared* them to anything, so
every change to date has been justified by reading the diff rather than by
evidence. This change builds the net first: a golden-frame harness that renders
a fixed scene and asserts the output is bit-identical. The repeat field already
proved the pattern works (one entry with rep=8 versus the eight entries it
replaces, 19200 pixels, zero differences); this generalises it to the whole
renderer. **No restructuring lands until the net is green and pinned.**

## What Changes

- **A golden-frame regression net, first.** A scene exercising every path —
  tiles at each bpp, the palette base, both flips, the behind-split, repeat
  runs, the clip rectangle, transparency, the overlay, camera scroll — rendered
  to reference frames that are committed and compared bit-for-bit. Plus a
  cycle-accounting assertion per line, so a change that silently overruns the
  line budget fails instead of dropping sprites.
- **The module splits** into `ppu_regs`, `ppu_map`, `ppu_scan`, `ppu_fetch`,
  `ppu_blit`, `ppu_line`, `ppu_display`, with the FSM's shared state becoming
  explicit interfaces. Behaviour is bit-identical at every step.
- **The blit datapath is pipelined** so that pattern decode, palette lookup,
  shift and merge sit in separate stages instead of one clock. This is the
  Fmax item and the one that makes wider pixel formats affordable later.
- **Block RAM is re-costed.** Where the 16 BRAMs actually go, which are forced
  by port width rather than capacity, and what a second overlay plane would
  really cost. Any reduction found is taken; the point is to know the number.
- **Prefetch and caching are assessed, then decided.** The engine re-fetches
  pattern planes for every entry even when consecutive entries share a pattern,
  and stalls on `!disp_slot` twice per cell. Both are measured against the line
  budget before anything is built — and the honest outcome may be "not worth
  it", as it was for the hardware multiplier.
- **Not a feature change.** No new registers, no new capability, no behaviour
  difference. `breakout`, `nemo` and `celeste` must render bit-identically
  before and after, and that is the acceptance test.

## Capabilities

### New Capabilities

- `ppu-core`: the compositor's internal structure and timing contract — module
  boundaries, the per-line cycle budget and what may consume it, the blit
  pipeline's stages, and the golden-frame regression net that pins rendering
  behaviour. This capability is about *how the PPU is built*, not what it
  draws; the register-level behaviour it must preserve is already implied by
  the existing hardware and is captured by the golden frames.

### Modified Capabilities

None. This change is explicitly behaviour-preserving: no register map change,
no new drawing capability, no spec-level behaviour difference.

## Impact

- **Affected code**: `rtl/sprite_compositor.sv` (split into the modules above),
  `rtl/sprite_compositor_tb.sv` (golden frames and cycle assertions),
  `Makefile` (a `ppu-check` target, and resource/timing reporting).
- **Not affected**: `rtl/chip.sv`'s instantiation and the `$4000-$403F` register
  map stay as they are. The three ports need no change; they are the acceptance
  test.
- **Depends on**: nothing. It can land alongside `refactor-cpu-core`, which
  touches a different module — but see the sequencing note in `design.md`,
  because the two changes share a clock and only one of them is currently the
  chip's limiter.
- **Blocks**: `hardware-gaps.md` entries 8 and 9 (overlay blit modes, overlay
  layer priority) both add fields to the display path, which is the part most
  entangled today.
