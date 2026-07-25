/*
 * SingleStepTests/65x02 harness top level.
 *
 * Simulation-only. Nothing instantiates this in the console; it exists so
 * `tools/65x02/harness.cpp` has one stable interface to drive, whichever core
 * is underneath. Select the core with `-DSST_CORE_ARLET` (the default) or
 * `-DSST_CORE_V2`.
 *
 * Two things the golden suite needs that a 6502 bus does not expose:
 *
 *   - the architectural state at the end of an instruction. Read out here as
 *     hierarchical references, so the core itself needs no test ports. This is
 *     a read-only coupling to the core's internals and it is the ONLY one.
 *
 *   - a retire marker. `o_sync` is high during the cycle that fetches an
 *     opcode, which is how the harness knows where one case's instruction
 *     ends. `o_decode` is high during the cycle that opcode is decoded in,
 *     which for the Arlet core is where the *previous* instruction's register
 *     and flag writes land - so the harness samples state at the end of it.
 *
 * State is *set* through the bus (see the preamble in harness.cpp), not
 * through this interface, so the harness stays usable on a core that has no
 * forcing interface at all.
 *
 * Hugo Sereno, <bytter@gmail.com>
 */

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSED */

`include "cpu6502_core.sv"

module cpu6502_sst (
    input  logic        clk,
    input  logic        reset,
    output logic [15:0] ab,
    input  logic [7:0]  di,
    output logic [7:0]  dout,
    output logic        we,
    input  logic        irq,
    input  logic        nmi,
    input  logic        rdy,

    // Architectural state, sampled by the harness. Read-only.
    output logic [15:0] o_pc,
    output logic [7:0]  o_a,
    output logic [7:0]  o_x,
    output logic [7:0]  o_y,
    output logic [7:0]  o_s,
    output logic [7:0]  o_p,
    // Cycle markers.
    output logic        o_sync,    // this cycle is an opcode fetch
    output logic        o_decode,  // this cycle decodes a fetched opcode
    // 1 if the architectural state above is only final at the END of the
    // decode cycle (the Arlet core retires the previous instruction there);
    // 0 if it is already final when the decode cycle begins. The harness reads
    // this once and samples accordingly, so neither core needs a special case
    // in C++.
    output logic        o_late_writeback,
    output logic        o_trap
);


  // The new core has a real test interface, so nothing here reaches into it.
  cpu6502_core u_cpu (
      .clk(clk), .reset(reset),
      .AB(ab), .DI(di), .DO(dout), .WE(we),
      .IRQ(irq), .NMI(nmi), .RDY(rdy),
      .dbg_pc(o_pc), .dbg_a(o_a), .dbg_x(o_x), .dbg_y(o_y),
      .dbg_s(o_s), .dbg_p(o_p),
      .dbg_sync(o_decode), .dbg_trap(o_trap),
      .dbg_trap_ir(), .dbg_trap_pc()
  );

  assign o_sync           = o_decode;
  // Every register write lands before the decode cycle it retires into.
  assign o_late_writeback = 1'b0;


endmodule

/* verilator lint_on DECLFILENAME */
/* verilator lint_on UNUSED */
