## Why

PICO-8 roadmap step 2: a scrolling tile background (`map()` + `camera()`). The console's background story today is the fixed-position textbuffer, a separate video engine with its own char/attr/font RAMs and a 4-state-per-pixel renderer. A tile layer that reads the sprite sheet subsumes it: text is just font tiles, and the whole textbuffer subsystem retires.

## What Changes

- Add a **tilemap layer** to the PPU: 32x16 cells of 16 bits `{pal[3:0], bppm1[1:0], yflip, xflip, base[7:0]}` - tiles reference the sprite sheet by the same plane-slot base addressing as sprites, with per-tile depth, palette, and flips. Cell value $0000 means empty (skipped, costs 2 cycles).
- Add `camera_x`/`camera_y` registers ($4003/$4004, latched per scanline) for smooth pixel scrolling with wraparound (map spans 256x128 world pixels); `$4005` bit0 enables the layer.
- The tile fetcher runs between the line clear and the sprite scan, synthesizing one pseudo-entry per visible tile column (21 per line) and pushing it through the existing plane-fetch + 2-word RMW blit pipeline - no second datapath. Sprites composite after tiles, so they draw on top; tile pixel value 0 is transparent over the cleared background.
- **BREAKING**: remove `textbuffer.sv` from `chip.sv`. The $F000-$F7FF window routes to the map instead: $F000-$F1FF cell low bytes (pattern base - the analogue of the old character code), $F200-$F3FF cell high bytes (color/depth/flips - the analogue of the old attribute). The map is CPU-write-only (reads return 0). The final pixel is the PPU's palette output alone.
- Sheet init image gains the CP437 font (chars 0-127, bit-reversed to the PPU's bit0-leftmost convention) at plane slots 128-255, so text cells are `base = 128 + charcode` at 1bpp.
- `src/main.asm` and the testbench build a scrolling world (sparse decorative tiles + a text banner living in the world) under the bouncing sprites; golden model extended with the tile layer.

## Impact

- Affected specs: sprite-rendering (tilemap requirements added; CPU interface modified)
- Affected code: `rtl/sprite_compositor.sv`, `rtl/chip.sv` (textbuffer instance and its palette removed), `rtl/sprite_pattern.bin`, `rtl/sprite_compositor_tb.sv`, `src/main.asm`. `rtl/textbuffer.sv` stays in-tree but is no longer instantiated.
- FPGA cost: +2 EBRs for the map (two 512x8 RAMs); the textbuffer's char/attr/font RAMs and second palette are removed from the build.
