/*
 * Adapts the 6502 core to the signal names the rest of the chip uses.
 *
 * The core is `rtl/cpu6502_core.sv` with its decode table in
 * `rtl/cpu6502_decode.sv`. It replaced Arlet Ottens' implementation, which
 * this project ran from the beginning and which is recorded, with its measured
 * behaviour and the one defect the golden suite found in it, in
 * docs/cpu-core.md.
 *
 * Hugo Sereno, <bytter@gmail.com>
 */

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off DECLFILENAME */
/* verilator lint_off MODDUP */
/* verilator lint_off UNUSED */

// Pull the core in for every tool that resolves modules through includes,
// which both yosys and Verilator do. Only iverilog is excluded: it gets these
// files on its command line and would see duplicate modules.
// (Do not start a comment line with the word Verilator - it is read as a
// pragma and the build fails with BADVLTPRAGMA.)
`ifndef __ICARUS__
  `include "cpu6502_core.sv"
`endif

module cpu6502(
  input  bit         clk,
  input  bit         reset,
  output logic [15:0] address,
  input  logic [7:0] data_in,
  output logic [7:0] data_out,
  output bit         write,
  // `write` before the RDY gate. A stall predicate that reads `write` is a
  // combinational loop through the core; see the comment on WE_PEND in
  // rtl/cpu6502_core.sv.
  output bit         write_pend,
  // New signal - exposes RDY pin for memory arbiter
  input  bit         rdy,
  // The interrupt request line. Its one consumer today is the WAI wake; the
  // vector path remains refactor-cpu-core section 5.
  input  bit         irq
);

  wire IRQ = irq;
  wire NMI = 1'b0;

  cpu6502_core core(
    .clk(clk),
    .reset(reset),
    .AB(address),     // Address bus
    .DI(data_in),     // Data in
    .DO(data_out),    // Data out
    .WE(write),       // Write enable
    .WE_PEND(write_pend), // ...and the same, ungated by RDY
    .IRQ(IRQ),
    .NMI(NMI),
    .RDY(rdy),        // Ready - the memory arbiter stalls the core with this

    // Test interface. Synthesis trims it; the simulator can watch it.
    .dbg_pc(), .dbg_a(), .dbg_x(), .dbg_y(), .dbg_s(), .dbg_p(), .dbg_b(),
    .dbg_sync(), .dbg_trap(), .dbg_trap_ir(), .dbg_trap_pc()
  );

endmodule

/* verilator lint_on PINCONNECTEMPTY */
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
/* verilator lint_on MODDUP */
/* verilator lint_on UNUSED */ 