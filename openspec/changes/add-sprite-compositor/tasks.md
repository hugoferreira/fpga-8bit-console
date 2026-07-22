## 1. Implementation

- [x] 1.1 Create `rtl/sprite_pattern.bin` default 8x8 pattern
- [x] 1.2 Implement `rtl/sprite_compositor.sv` (pattern store, sprite list, line buffers, scan engine, register/DMA interface)
- [x] 1.3 Implement `rtl/sprite_compositor_tb.sv` (video timing, animated list writes, PPM frame dump)
- [x] 1.4 Run testbench, verify frames visually (sprite count, flips, motion, clipping) — also verified bit-exact against a Python golden model
- [x] 1.5 Swap `sprite` for `sprite_compositor` in `rtl/chip.sv`, verify the design still compiles (Verilator lint identical to pre-change tree)

## 2. PPU v2: per-sprite 1-4 bpp and BRAM line buffer

- [x] 2.1 Rework line buffer: 20 lanes x 32 bits (8px x 4bpp) in BRAM, double-banked by address bit, 2-word read-modify-write blits
- [x] 2.2 4-bitplane pattern store with $400E plane-select; per-sprite {bpp-1, palette base} packed into the flags byte
- [x] 2.3 Update testbench to the 4-clock-pixel timing contract; verify bit-exact against extended golden model (mixed depths, painter's order, transparency)
- [x] 2.4 Quantify FPGA cost with yosys synth_ice40: naive 4bpp scaling of v1 = 2288 LUT4/1661 FF; v2 = 1093 LUT4/531 FF + 2 extra BRAMs
- [x] 2.5 Update main.asm (plane loading, per-sprite depth/palette table) and verify in the full-system simulator
