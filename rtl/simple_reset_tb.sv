/*
 * Simple testbench to validate reset vector content in RAM
 */

`timescale 1ns/1ps

module simple_reset_tb;
  // Signals for RAM module
  logic clk;
  logic cs;
  logic rw;
  logic [15:0] addr;
  logic [7:0] di;
  logic [7:0] dout;
  
  // Instantiate RAM module
  ram_async #(
    .A(16),
    .D(8),
    .FILE("test_ram.hex")
  ) ram_instance (
    .clk(clk),
    .cs(cs),
    .rw(rw),
    .addr(addr),
    .di(di),
    .dout(dout)
  );
  
  // Clock generation
  always begin
    #5 clk = ~clk;
  end
  
  // Test sequence
  initial begin
    // Initialize signals
    clk = 0;
    cs = 0;
    rw = 0; // Read operation (0=read in this module)
    addr = 16'h0000;
    di = 8'h00;
    
    // Wait for RAM to initialize
    #10;
    
    // Display header
    $display("=== RAM Reset Vector Test ===");
    $display("Time | Address | CS | RW | Data Out");
    
    // Test reading reset vector low byte
    addr = 16'hFFFC;
    cs = 1;
    #10;
    $display("%4t | %04x    | %b  | %b  | %02x", $time, addr, cs, rw, dout);
    
    // Test reading reset vector high byte
    addr = 16'hFFFD;
    #10;
    $display("%4t | %04x    | %b  | %b  | %02x", $time, addr, cs, rw, dout);
    
    // Read from program start address (0x0300)
    addr = 16'h0300;
    #10;
    $display("%4t | %04x    | %b  | %b  | %02x", $time, addr, cs, rw, dout);
    
    addr = 16'h0301;
    #10;
    $display("%4t | %04x    | %b  | %b  | %02x", $time, addr, cs, rw, dout);
    
    addr = 16'h0302;
    #10;
    $display("%4t | %04x    | %b  | %b  | %02x", $time, addr, cs, rw, dout);
    
    // Test a write operation
    di = 8'hAA;
    rw = 1; // Write operation (1=write in this module)
    #10;
    $display("%4t | %04x    | %b  | %b  | %02x (Write %02x)", $time, addr, cs, rw, dout, di);
    
    // Read back to verify
    rw = 0; // Read operation
    #10;
    $display("%4t | %04x    | %b  | %b  | %02x", $time, addr, cs, rw, dout);
    
    // Finish test
    $display("=== Test Complete ===");
    $finish;
  end
  
  // Optional: Save waveform data
  initial begin
    $dumpfile("simple_reset_tb.vcd");
    $dumpvars(0, simple_reset_tb);
  end
endmodule 