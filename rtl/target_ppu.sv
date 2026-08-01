/*
 * Synthesis target: the PPU, plus a CPU that can drive it.
 *
 * Answers: what does the compositor cost in the console, and how fast does it
 * close, with the arbiter and the tilemap/overlay/register windows wired the
 * way they ship.
 *
 * This is NOT the same measurement as `make ppu-synth` gave before this change,
 * which synthesised rtl/sprite_compositor.sv on its own (1846 LUT4, 2623 logic
 * cells, 16 BRAM, 62.6 MHz - refactor-ppu-core design.md). That number is the
 * compositor in isolation and is the right one for judging a change INSIDE the
 * compositor. This one adds the bus it hangs off, and is the right one for
 * judging whether the console fits. Both are kept; `ppu-synth` keeps the old
 * meaning so the PPU change's committed baselines stay comparable.
 *
 * Deliberately EXCLUDED: the PSG.
 *
 *   make ppu-synth      the compositor alone (unchanged meaning)
 *   make synth-ppu      this target - compositor plus its bus
 *   make ppu-check      golden frames; the functional gate
 *
 * Yes, `ppu-synth` and `synth-ppu` are different measurements with similar
 * names. `ppu-synth` could not be re-pointed at this target without silently
 * changing what refactor-ppu-core's committed baselines mean; design.md D5
 * has the reasoning.
 */

`include "target_harness.sv"

module target_ppu (
    input  logic       clk,
    input  logic       psgclk,
    input  logic       fastclk,
    input  logic       rst,
    input  logic [7:0] buttons,
    output logic       probe
);
    target_harness #(.HAS_PPU(1), .HAS_PSG(0), .RAM_ADDR_BITS(11)) u_target (
        .clk(clk), .psgclk(psgclk), .fastclk(fastclk),
        .rst(rst), .buttons(buttons), .probe(probe)
    );
endmodule
