/*
 * RAM Test Testbench
 * This testbench specifically tests reading from the RAM at vector locations
 */

`timescale 1ns/1ps

module ram_test_tb;
  // Clock generator
  reg clk = 0;
  always #5 clk = ~clk;
  
  // RAM signals
  reg cs = 0;
  reg rw = 0;
  reg [15:0] addr = 0;
  reg [7:0] di = 0;
  wire [7:0] dout;
  
  // Variables for storing read values
  reg [7:0] reset_low;
  reg [7:0] reset_high;
  reg [7:0] data;

  // Instantiate the RAM module
  ram_async #(
    .A(16),
    .D(8),
    .FILE("rtl/ram.hex")
  ) ram_inst (
    .clk(clk),
    .cs(cs),
    .rw(rw),
    .addr(addr),
    .di(di),
    .dout(dout)
  );
  
  initial begin
    // Initialize signals
    clk = 0;
    cs = 0;
    rw = 0;
    addr = 0;
    di = 0;
    
    #20; // Wait for initialization
    
    // Test 1: Read from address 0x0000
    cs = 1;
    rw = 0;
    addr = 16'h0000;
    #10;
    data = dout;
    cs = 0;
    $display("Address 0x0000: %02x", data);
    
    // Test 2: Read from program start (0x0300)
    cs = 1;
    rw = 0;
    addr = 16'h0300;
    #10;
    data = dout;
    cs = 0;
    $display("Address 0x0300: %02x", data);
    
    // Test 3: Read from vector table (FFFC-FFFD)
    // Display the reset vector values
    cs = 1;
    rw = 0;
    addr = 16'hFFFC;
    #10;
    reset_low = dout;
    addr = 16'hFFFD;
    #10;
    reset_high = dout;
    cs = 0;
    
    $display("Reset Vector: %02x%02x", reset_high, reset_low);
    
    // Finish test
    $display("=== Test Complete ===");
    $finish;
  end
  
  // Optional: Save waveform data
  initial begin
    $dumpfile("ram_test_tb.vcd");
    $dumpvars(0, ram_test_tb);
  end
endmodule 