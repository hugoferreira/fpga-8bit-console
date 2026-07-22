## Why

PICO-8 roadmap step 4: a CPU-drawable pixel surface for `pset`/`line`/`circ`/`print`. The tilemap and sprite list cover structured graphics, but primitives and dense proportional text (e.g. a 4x6 font, which no 8-pixel grid can pitch) want a bitmap. This is the outcome of the variable-tile-size discussion: don't bend the tile grid - give free-form content its own layer.

## What Changes

- Add a **1bpp overlay bitmap** to the PPU: 160x120 pixels, 20 bytes per row (bit 0 = leftmost pixel of its byte), byte address = y*20 + x/8, stored in 5 EBRs.
- The overlay is mixed at **display time**, not composited: the display pipeline reads the overlay byte for the current lane in parallel with its line-buffer read and muxes per pixel - a set bit shows the overlay color above everything (tiles and sprites), a clear bit is transparent. Zero engine cycles, no per-line budget impact.
- New registers: $4005 bit1 enables the overlay; $4006 sets its 4-bit color. The color register is sampled per pixel, so mid-frame writes produce raster bands.
- New CPU window: $E000-$E95F, direct-addressed, **write-only** (one `sta` per byte). Read-modify-write happens on a CPU-RAM shadow - the same convention as the write-only tilemap, now uniform across all PPU memories.
- `memory_arbiter` gains the $E000-$E9FF chip select; `chip.sv` routes it to the PPU.
- Demo: the testbench draws a border, a diagonal, and a moving bar; `src/main.asm` renders a **4x6-font banner** (two glyphs packed per byte - the font never touches the sprite sheet), a box border, and a bouncing dot, all from the 6502.

## Impact

- Affected specs: sprite-rendering (overlay requirement added; CPU interface modified)
- Affected code: `rtl/sprite_compositor.sv`, `rtl/memory_arbiter.sv`, `rtl/chip.sv`, `rtl/sprite_compositor_tb.sv`, `src/main.asm`
- FPGA cost: +5 EBRs (2560x8 overlay RAM), a handful of LUTs for the display mux and the y*20 address adders. PPU total: 15 of the hx8k's 32 EBRs.
