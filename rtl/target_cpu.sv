/*
 * Synthesis target: the CPU in its real bus.
 *
 * Answers: what does the CPU cost, and how fast does it close, WITH the memory
 * arbiter and the DMA controller in the loop - which is the configuration the
 * console actually ships. The arbiter's data-in mux sits on the CPU's critical
 * path, and memory_arbiter.sv:141-146 records that this exact path once formed
 * a combinational loop; a CPU number that excludes it is not a number about
 * this machine.
 *
 * Deliberately EXCLUDED: the PPU and the PSG.
 *
 * This is not the same question as `make cpu-fmax` (rtl/cpu_fmax_top.sv), which
 * measures one core with no arbiter so that a difference between two runs is a
 * difference between two CORES. Nor is it `make test-65x02`
 * (rtl/cpu6502_sst.sv), which is the conformance harness. All three are worth
 * having; see docs/build-targets.md.
 *
 *   make cpu-synth      area + Fmax at seed 1
 *   make cpu-fmax       core-only Fmax (the OTHER harness)
 */

`include "target_harness.sv"

module target_cpu (
    input  logic       clk,
    input  logic       psgclk,
    input  logic       rst,
    input  logic [7:0] buttons,
    output logic       probe
);
    target_harness #(.HAS_PPU(0), .HAS_PSG(0), .RAM_ADDR_BITS(11)) u_target (
        .clk(clk), .psgclk(psgclk), .rst(rst), .buttons(buttons), .probe(probe)
    );
endmodule
