## 1. Implementation

- [x] 1.1 Widen the PPU register address to [5:0]; add draw/screen palettes, clip, and transparency-mask registers with identity defaults
- [x] 1.2 Blit datapath: palt mask lookup for opacity, draw-palette lookup in packed colors, clip comparators in the merge mask; screen palette at the display mux
- [x] 1.3 Regression: existing testbench content bit-exact with reset defaults
- [x] 1.4 Testbench + golden model: visible draw state (inset clip, extra transparent value, palette swaps); verify bit-exact
- [x] 1.5 main.asm: same draw state from the 6502; verified end-to-end in the Verilator harness; yosys synth_ice40: 1740 LUT4 / 15 BRAM (draw state ~+800 LUT4, zero BRAM)
