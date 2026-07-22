## 1. Implementation

- [x] 1.1 Add overlay RAM, display-time mix, and $4005 bit1 / $4006 color registers to `rtl/sprite_compositor.sv`
- [x] 1.2 Add the $E000-$E9FF chip select to `rtl/memory_arbiter.sv` and route it in `rtl/chip.sv`
- [x] 1.3 Update testbench: overlay port task, border/diagonal/moving-bar content, golden model overlay layer; verify bit-exact
- [x] 1.4 Update `src/main.asm`: 4x6-font banner (two glyphs per byte), box border, bouncing dot with row-address tables
- [x] 1.5 Verify end-to-end in the Verilator harness; yosys synth_ice40: 923 LUT4 / 15 BRAM
- [x] 1.6 (found during bring-up) Fix missing `ZPX1/INDX1/INDX2/INDY1 -> AB = {ZEROPAGE, ADD}` case in cpu6502_arlet.sv's address generator: ZP,X / (ZP,X) / (ZP),Y read their pointer bytes from PC, so indirect stores used the next opcode as the target high byte; never exposed before because no program used those addressing modes
