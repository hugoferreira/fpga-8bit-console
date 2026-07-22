## 1. Implementation

- [x] 1.1 Rework `rtl/sprite_compositor.sv`: sheet BRAM (256 plane slots), plane-fetch pipeline in the blit engine, new register map, 31-bit entries with pattern base
- [x] 1.2 Extend `rtl/sprite_pattern.bin` into the sheet init image (arrow 4bpp @0, disc 1bpp @4, diamond 2bpp @5, cross 1bpp @7)
- [x] 1.3 Update `rtl/sprite_compositor_tb.sv`: sheet upload via $4000-$4002, per-sprite pattern bases, mixed-depth stream
- [x] 1.4 Extend the Python golden model (sheet bytes, per-entry base) and verify frames bit-exact
- [x] 1.5 Update `src/main.asm`: sheet upload loop, per-sprite base/depth tables, 4-writes-per-sprite stream
- [x] 1.6 Verify end-to-end in the Verilator harness; yosys synth_ice40: 691 LUT4 / 277 FF / 8 BRAM (down from 1093 LUT4 / 531 FF / 4 BRAM - pattern store moved from FFs into the sheet BRAM)
