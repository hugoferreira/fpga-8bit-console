## Why

The current `sprite.sv` renders a single hardware sprite using a race-the-beam comparator. Drawing many sprites would require one module instance each, scaling linearly in LUTs and BRAM ports. We want to draw a large number of copies of the *same* 8x8 pattern at different coordinates, with cheap X/Y flip transforms.

## What Changes

- Add `sprite_compositor.sv`: a scanline compositor that renders up to 128 instances of a shared 8x8 1bpp pattern per frame.
  - One shared pattern store (8 bytes, register-based, combinational read).
  - A 128-entry sprite list ({X, Y, xflip, yflip} per entry) written via an indexed register interface.
  - A double-buffered 160-pixel line buffer: while line N displays, the engine composites line N+1 by walking the sprite list at one entry per clock (pipelined), OR-inserting 8-bit rows via a barrel shift.
  - X flip = reversed bit order on the fetched row (pure wiring); Y flip = row index XOR 3'b111. Both are zero-cycle.
- Replace the `sprite s0` instance in `chip.sv` with `sprite_compositor`, keeping the same chip-select/DMA port shape and the $400x register window.
- Add `sprite_compositor_tb.sv`: standalone testbench that drives 160x120 video timing, animates the sprite list, and dumps frames as PPM images for visual verification.

## Impact

- Affected specs: sprite-rendering (new capability)
- Affected code: `rtl/chip.sv` (instance swap), new `rtl/sprite_compositor.sv`, new `rtl/sprite_compositor_tb.sv`, new `rtl/sprite_pattern.bin`. `rtl/sprite.sv` remains in-tree but is no longer instantiated.
