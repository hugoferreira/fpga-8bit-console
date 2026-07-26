/*
 * Synthesis target: the whole console.
 *
 * Answers: does it fit, and where does the logic go. Today it does NOT fit -
 * 10731 of 7680 logic cells (139%) and 48 of 32 BRAM per docs/cpu-baseline.json
 * - and this target is not expected to place until add-memory-subsystem moves
 * the 64 KB map off-chip. It reports the utilisation rather than failing
 * without a number, which is the difference between "we know the gap" and the
 * total blackout that held before the split.
 *
 * RAM_ADDR_BITS is 13 (8 KB) rather than the 11 the subsystem targets use, so
 * this stays directly comparable to what rtl/top.sv builds today. That is still
 * a truncated map and still not functional - see the warning in top.sv.
 *
 *   make soc-synth      utilisation, and Fmax if it ever places
 */

`include "target_harness.sv"

module target_soc (
    input  logic       clk,
    input  logic       psgclk,
    input  logic       rst,
    input  logic [7:0] buttons,
    output logic       probe
);
    target_harness #(.HAS_PPU(1), .HAS_PSG(1), .RAM_ADDR_BITS(13)) u_target (
        .clk(clk), .psgclk(psgclk), .rst(rst), .buttons(buttons), .probe(probe)
    );
endmodule
