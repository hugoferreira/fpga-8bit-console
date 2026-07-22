/*
 * CPU Reset Testbench
 * This testbench specifically tests the CPU's reset sequence and vector reads
 */

`timescale 1ns/1ps

module cpu_reset_tb;
  // Signals for clock and reset
  logic clk;
  logic reset;
  
  // Signals for CPU
  logic [15:0] cpu_address;
  logic [7:0] cpu_data_in;
  logic [7:0] cpu_data_out;
  logic cpu_rw;
  
  // Signals for RAM
  logic ram_cs;
  
  // RAM instance
  ram_async #(
    .A(16),
    .D(8),
    .FILE("./rtl/ram.hex")
  ) ram (
    .clk(clk),
    .cs(ram_cs),
    .rw(cpu_rw),
    .addr(cpu_address),
    .di(cpu_data_out),
    .dout(cpu_data_in)
  );
  
  // Simple address decoder
  always_comb begin
    // Default values
    ram_cs = 0;
    
    // RAM is always selected for now
    if (cpu_address >= 16'h0000 && cpu_address <= 16'hFFFF) begin
      ram_cs = 1;
    end
    
    // Special handling for vector area
    if (cpu_address >= 16'hFFFA && cpu_address <= 16'hFFFF) begin
      ram_cs = 1;
      $display("Vector Access: addr=%04x, ram_cs=%b", cpu_address, ram_cs);
    end
  end
  
  // CPU instance
  cpu6502_arlet cpu (
    .clk(clk),
    .reset(reset),
    .AB(cpu_address),
    .DI(cpu_data_in),
    .DO(cpu_data_out),
    .WE(cpu_rw),
    .IRQ(1'b0),
    .NMI(1'b0),
    .RDY(1'b1)
  );
  
  // Clock generation
  always begin
    #5 clk = ~clk;
  end
  
  // Test sequence
  initial begin
    // Initialize signals
    clk = 0;
    reset = 1;
    
    // Keep reset active for a while
    #50;
    
    // Display header
    $display("=== CPU Reset Sequence Test ===");
    $display("Time | Reset | Address | RW | Data In | Data Out");
    
    // Sample current state
    #10;
    $display("%4t | %b     | %04x    | %b  | %02x      | %02x", 
             $time, reset, cpu_address, cpu_rw, cpu_data_in, cpu_data_out);
    
    // Release reset
    reset = 0;
    
    // Log CPU behavior after reset
    repeat (20) begin
      #10;
      $display("%4t | %b     | %04x    | %b  | %02x      | %02x", 
               $time, reset, cpu_address, cpu_rw, cpu_data_in, cpu_data_out);
    end
    
    // Finish test
    $display("=== Test Complete ===");
    $finish;
  end
  
  // Optional: Save waveform data
  initial begin
    $dumpfile("cpu_reset_tb.vcd");
    $dumpvars(0, cpu_reset_tb);
  end
endmodule 