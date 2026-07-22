/*
 * SystemVerilog wrapper for Arlet Ottens' 6502 CPU implementation.
 *
 * This wrapper adapts the more complete Arlet implementation to the
 * interface used in the current design.
 *
 * Original implementation by Arlet Ottens, <arlet@c-scape.nl>
 * Wrapper by Hugo Sereno, <bytter@gmail.com>
 */

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off DECLFILENAME */
/* verilator lint_off MODDUP */
/* verilator lint_off UNUSED */

// Include files conditionally - Verilator needs them, iverilog gets them via command line
`ifdef VERILATOR
  // Include the Arlet 6502 implementation directly to ensure Verilator finds it
  `include "cpu6502_arlet.sv"
  `include "cpu6502_alu.sv"
`endif

module cpu6502(
  input  bit         clk,
  input  bit         reset,
  output logic [15:0] address,
  input  logic [7:0] data_in,
  output logic [7:0] data_out,
  output bit         write,
  // New signal - exposes RDY pin for memory arbiter
  input  bit         rdy
);

  // Additional signals required by Arlet's implementation
  wire IRQ = 1'b0;  // Always keep IRQ disabled 
  wire NMI = 1'b0;  // Always keep NMI disabled
  // RDY is now controlled externally
  
  // Debug memory access to identify if BRK instructions are being fetched
  always_ff @(posedge clk) begin
    if (!write && address < 16'h0400) begin
      if (data_in == 8'h00) begin
        $display("CPU Wrapper: WARNING - Reading BRK instruction (0x00) from address $%04X", address);
      end
    end
    
    // Log RDY state changes for debugging
    if (rdy == 0) begin
      $display("CPU Wrapper: CPU is halted (RDY=0) at address $%04X", address);
    end
  end

  // Instantiate Arlet's 6502 CPU with appropriate signal mappings
  // The module in cpu6502_arlet.sv is named "cpu"
  cpu cpu_arlet(
    .clk(clk),
    .reset(reset),
    .AB(address),     // Address bus
    .DI(data_in),     // Data in
    .DO(data_out),    // Data out
    .WE(write),       // Write enable
    .IRQ(IRQ),        // Interrupt request (always 0)
    .NMI(NMI),        // Non-maskable interrupt (always 0)
    .RDY(rdy)         // Ready signal - now controlled by memory arbiter
  );

endmodule

/* verilator lint_on PINCONNECTEMPTY */
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
/* verilator lint_on MODDUP */
/* verilator lint_on UNUSED */ 