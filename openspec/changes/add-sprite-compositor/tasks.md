## 1. Implementation

- [x] 1.1 Create `rtl/sprite_pattern.bin` default 8x8 pattern
- [x] 1.2 Implement `rtl/sprite_compositor.sv` (pattern store, sprite list, line buffers, scan engine, register/DMA interface)
- [x] 1.3 Implement `rtl/sprite_compositor_tb.sv` (video timing, animated list writes, PPM frame dump)
- [x] 1.4 Run testbench, verify frames visually (sprite count, flips, motion, clipping) — also verified bit-exact against a Python golden model
- [x] 1.5 Swap `sprite` for `sprite_compositor` in `rtl/chip.sv`, verify the design still compiles (Verilator lint identical to pre-change tree)
