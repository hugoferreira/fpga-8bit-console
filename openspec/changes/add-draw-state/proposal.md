## Why

PICO-8 roadmap step 3 (the last): the draw state - clip(), palt(), and pal() in both its draw-palette and screen-palette forms. All are merge-stage or display-stage tweaks with near-zero memory cost; together they complete the PICO-8-shaped feature set (sheet, sprites, map+camera, overlay, draw state).

## What Changes

- Expand the PPU register window from $400x to $4000-$403F (the arbiter already decodes $4000-$40FF; the extra address bits stop aliasing):
  - $4010-$401F **draw palette**: 16x4 LUT applied per blit to the post-palette-base color index of tiles and sprites (identity at reset)
  - $4020-$402F **screen palette**: 16x4 LUT applied to every displayed pixel, including the overlay and background - whole-screen fades and flashes for one register write per entry (identity at reset)
  - $4030-$4033 **clip rectangle** (x0, y0, x1, y1 inclusive; full screen at reset): gates the blit merge mask per pixel, so tiles and sprites never write outside it. The overlay is exempt - clipping applies to compositing, and overlay drawing is CPU-side
  - $4034/$4035 **transparency mask** (palt): 16 bits, bit v = pixel value v is transparent, replacing the hardcoded "value 0 only" (reset = $0001)
- Blit datapath: opacity becomes a mask lookup on the raw pixel value; packed colors pass through the draw palette; the clip comparators AND into the merge mask (the 8-bit x wraparound keeps left-edge partial tiles correct).
- Testbench and main.asm configure a visible draw state (inset clip window, an extra transparent value, a draw-palette swap, a navy screen background); golden model extended to match.

## Impact

- Affected specs: sprite-rendering (draw-state requirement added; CPU interface modified)
- Affected code: `rtl/sprite_compositor.sv`, `rtl/chip.sv` (register address width), `rtl/sprite_compositor_tb.sv`, `src/main.asm`
- FPGA cost: ~130 flip-flop bits of state, a few hundred LUTs of muxes/comparators, zero BRAM
