/*
 * Simple Verilog testbench to validate reset vector content in RAM
 */

`timescale 1ns/1ps

module simple_reset_tb();
  // Clock and control
  reg clk = 0;
  
  // Memory interface
  reg [15:0] addr;
  wire [7:0] data_out;
  
  // Test control
  integer cycle_count = 0;
  
  // Instantiate the RAM module
  ram_async #(
    .A(16),
    .D(8),
    .FILE("test_ram.hex")
  ) ram (
    .clk(clk),
    .cs(1'b1),        // Always selected
    .rw(1'b1),        // Always read
    .addr(addr),
    .di(8'h00),       // Not writing
    .dout(data_out)
  );
  
  // Clock generation
  always #5 clk = ~clk;
  
  // Count cycles
  always @(posedge clk) cycle_count = cycle_count + 1;
  
  // Test sequence
  initial begin
    // Setup waveform dumping
    $dumpfile("dump.vcd");
    $dumpvars(0, simple_reset_tb);
    
    $display("TB: Starting RAM reset vector test");
    
    // Read from reset vector addresses
    addr = 16'hFFFC;
    #10;  // Wait for one clock cycle
    $display("TB: Reset vector low byte at $FFFC = $%02X", data_out);
    
    addr = 16'hFFFD;
    #10;  // Wait for one clock cycle
    $display("TB: Reset vector high byte at $FFFD = $%02X", data_out);
    
    // Verify reset vector points to $0300
    if (data_out == 8'h03) begin
      $display("TB: Reset vector high byte OK ($03)");
    end
    else begin
      $display("TB: ERROR: Reset vector high byte = $%02X, expected $03", data_out);
    end
    
    // Read the instruction at the reset vector destination
    addr = 16'h0300;
    #10;  // Wait for one clock cycle
    $display("TB: First instruction at $0300 = $%02X", data_out);
    
    if (data_out == 8'hA9) begin  // LDA #
      $display("TB: First instruction OK (LDA #)");
    end
    else begin
      $display("TB: ERROR: First instruction = $%02X, expected $A9 (LDA #)", data_out);
    end
    
    // Read next byte (immediate value)
    addr = 16'h0301;
    #10;  // Wait for one clock cycle
    $display("TB: Second byte at $0301 = $%02X", data_out);
    
    if (data_out == 8'h42) begin
      $display("TB: Second byte OK ($42)");
    end
    else begin
      $display("TB: ERROR: Second byte = $%02X, expected $42", data_out);
    end
    
    $display("TB: Test complete");
    $finish;
  end
endmodule 