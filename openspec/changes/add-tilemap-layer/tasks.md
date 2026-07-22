## 1. Implementation

- [x] 1.1 Add tilemap to `rtl/sprite_compositor.sv`: map BRAMs, camera/control registers, tile-fetch phase feeding the shared blit pipeline, map CPU write port
- [x] 1.2 Remove textbuffer from `rtl/chip.sv`; route $F000 window to the PPU map port; single palette output
- [x] 1.3 Regenerate `rtl/sprite_pattern.bin` with the CP437 font (bit-reversed) at slots 128-255
- [x] 1.4 Update testbench: tile world + camera animation + sprites; extend golden model with the tile layer; verify bit-exact
- [x] 1.5 Update `src/main.asm`: build the map (decor + text banner), animate the camera, keep sprite stream
- [x] 1.6 Verify end-to-end in the Verilator harness; yosys synth_ice40: 822 LUT4 / 314 FF / 10 BRAM (+2 EBR for the map; textbuffer RAMs and second palette removed from the chip)
