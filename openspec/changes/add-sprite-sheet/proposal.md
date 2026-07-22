## Why

Every sprite currently renders the same 8x8 pattern - the compositor is a "many copies of one shape" engine. A PICO-8-class console needs a sprite *sheet*: many distinct patterns that entries reference by index. This is step 1 of the PICO-8-shaped PPU roadmap (sheet -> tilemap/camera -> draw state -> primitives overlay).

## What Changes

- Replace the single 4-bitplane register-file pattern store with a 2KB block-RAM **sprite sheet** organized as 256 *plane slots* of 8 bytes (one 8x8 bitplane each).
- **BREAKING**: each sprite list entry gains an 8-bit pattern base (a plane-slot address); a pattern occupies `bpp` consecutive slots starting there. Register map reshuffles: the old $4000-$4007 pattern-row window and $400E plane-select are replaced by a sheet upload port ($4000 addr-lo, $4001 addr-hi, $4002 data with auto-increment) and a staged pattern base at $400E committed by the existing $400B flags write.
- The blit engine fetches the `bpp` plane rows from sheet BRAM (one read per plane, pipelined) instead of reading a register file combinationally; blit cost becomes bpp+1 fetch cycles + the existing 4-cycle line-buffer read-modify-write.
- `src/main.asm` and the testbench upload a multi-pattern sheet (4bpp arrow, 1bpp disc, 2bpp diamond, 1bpp cross) and give each sprite a pattern; golden model extended to match.

## Impact

- Affected specs: sprite-rendering (modifies requirements added by `add-sprite-compositor`, which is implemented but not yet archived)
- Affected code: `rtl/sprite_compositor.sv`, `rtl/sprite_pattern.bin` (becomes the sheet init image), `rtl/sprite_compositor_tb.sv`, `src/main.asm`
- FPGA cost: +4 iCE40 EBRs for the sheet; the 256 pattern-plane flip-flops and their 4-way combinational read mux are removed
