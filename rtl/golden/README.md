# PPU golden frames

Reference output for `rtl/ppu_golden_tb.sv`, compared bit-for-bit by
`make ppu-check`. These files *are* the definition of what the compositor
draws: before they existed, every change to the engine was justified by
reading the diff.

- `ppu_<n>_<scene>.txt` — one scene, 120 lines of 160 hex digits, one digit
  per pixel, leftmost pixel first. The value is the 4-bit colour index the PPU
  emits, after the screen palette, so it is what the display gets.
- `ppu_cycles.txt` — one integer per scene: the worst-case engine occupancy of
  any scanline in that scene, in system clocks, against a budget of
  161 pixels x 3 clocks = 483. A scene that gets *slower* fails; a scene that
  gets faster prints a note and asks to be regenerated.

## Regenerating

    make ppu-check PPUARGS=+regen

This is meant to be a deliberate act. A change that is supposed to alter
rendering regenerates these files **in the same commit as the change**, so the
diff shows exactly which pixels moved and the reviewer can see whether that
was the intent. A change that is not supposed to alter rendering — every step
of `refactor-ppu-core`, for instance — must leave them untouched.

## What the scenes cover

| # | Scene | Path |
| --- | --- | --- |
| 0 | `bpp` | 1, 2, 3 and 4 bpp sprites at all 16 palette bases |
| 1 | `flips` | xflip, yflip and both, at every depth |
| 2 | `tiles` | the tile layer at camera (0,0), mixed depths, flips, empty cells |
| 3 | `camera` | sub-cell scroll on both axes (x&7=3, y&7=5) and world wrap |
| 4 | `bsplit` | six entries behind the tile layer, six in front |
| 5 | `repeat` | `$37` runs of 2 to 8 cells, off the right edge, unaligned, flipped |
| 6 | `clip` | sprites straddling all four edges of an inset clip rectangle |
| 7 | `palt` | values 0, 3 and 7 transparent; three draw-palette remaps |
| 8 | `overlay` | overlay set and clear, non-zero overlay colour, screen palette |
| 9 | `all` | every path at once, and the busiest lines in the suite |

Two checks are not frames:

- **Register readback** — every readable register in `$00-$37`, including the
  `$37` clamp and the `$0B` commit auto-increment.
- **The overrun probe** — 128 four-bpp sprites stacked on one scanline, to
  prove the cycle accounting actually detects an overrun and can say by how
  many clocks. Without it, a net that has never failed is not known to work.
