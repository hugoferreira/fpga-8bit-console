## Context

Tiles and sprites want the same pixels: 8x8 patterns from the sheet, positioned, flipped, palette-shifted, clipped into the line buffer. The design question is how much new hardware a background layer needs. Answer: almost none - a tile is a sprite whose position comes from arithmetic instead of a list.

## Goals / Non-Goals

- Goals: pixel-smooth scrolling background; per-tile pattern/depth/palette/flips; text as tiles (textbuffer absorbed); one shared blit datapath; deterministic per-line cost.
- Non-Goals: multiple map layers, maps larger than 32x16 (parameterizable later), map readback by CPU, tile sizes other than 8x8.

## Decisions

- **Reuse the sprite blit pipeline.** The tile phase synthesizes a pseudo-entry per visible column: x = k*8 - (camera_x & 7), pattern/depth/palette/flips from the cell, and y chosen so the existing `dy = line_y - y` row math lands on `world_y[2:0]`. The 8-bit x wraparound already handles the partial left-edge tile: x = -offset wraps to lane 31 (word0 clipped) with word1 wrapping to lane 0, which is exactly the visible fragment. Zero new datapath, one new FSM phase.
- **16-bit cells, split as two byte planes.** `{pal, bppm1, yflip, xflip}` high byte at $F200+, `base` low byte at $F000+ - deliberately the same window split as the old textbuffer's attr/char RAMs, so text code ports by changing row stride (32 vs 20) and adding 128 to character codes. Two 512x8 BRAMs, each with the CPU write port and the fetcher read port; CPU readback is dropped (would need a third port or arbitration - the old readback existed only for the disabled DMA self-copy).
- **Cell $0000 = empty** and is skipped in 2 cycles. Slot 0 as a tile pattern is still usable with any nonzero high byte; the convention mirrors PICO-8's "sprite 0 is empty".
- **Camera latched per line** (position at line start wins) so mid-frame camera writes shear at worst by one line instead of tearing within a line.
- **Budget.** Per line, worst case: 20 clear + 21 tiles x (2 + bpp+1 + 4) + 128 scan + hits x (bpp+5) cycles. With 1bpp font tiles and a typical ~9 sprite hits/line this is ~420 of 644 cycles; an all-4bpp tile row with ~25 sprite hits saturates the budget and drops the deepest list entries for that line - an era-authentic per-line limit that degrades gracefully (the engine re-arms cleanly at every line start).

## Risks / Trade-offs

- Map is write-only to the CPU; games must shadow it in RAM if they need readback. Accepted: saves a port, and the disabled DMA was the only reader.
- $F400-$F7FF aliases the map window (address bit 10 ignored). Documented, matches the arbiter's existing decode granularity.
- Text now consumes sheet slots 128-255 for the font; games wanting all 256 slots for art give up hardware text. That is the plane-slot allocator working as intended.

## Migration Plan

Single change: PPU, chip.sv, sheet image, testbench, golden model, main.asm land together. `textbuffer.sv` remains in-tree (unreferenced) one change longer in case anything needs to be salvaged, then can be deleted at archive time.

## Open Questions

- Step 3 will want `palt()`-style per-color transparency and `clip()`; both slot into the merge mask with no memory cost.
