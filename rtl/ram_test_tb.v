// RAM test bench
// Simple testbench for ram_async module
`timescale 1ns/1ps

module ram_test_tb;
  // Parameters
  parameter ADDR_WIDTH = 16;
  parameter DATA_WIDTH = 8;
  parameter INIT_FILE = "./rtl/ram.hex";
  
  // Signals
  logic clk;
  logic cs;
  logic rw;
  logic [ADDR_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0] din;
  logic [DATA_WIDTH-1:0] dout;
  
  // Instance of RAM module
  ram_async #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .INIT_FILE(INIT_FILE)
  ) ram_inst (
    .clk(clk),
    .cs(cs),
    .rw(rw),
    .addr(addr),
    .din(din),
    .dout(dout)
  );
  
  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100 MHz clock
  end
  
  // Test sequence
  initial begin
    $display("Starting RAM Test");
    $dumpfile("ram_test.vcd");
    $dumpvars(0, ram_test_tb);
    
    // Initialize signals
    cs = 0;
    rw = 1; // Read mode
    addr = 16'h0000;
    din = 8'h00;
    
    // Wait for a few clock cycles
    repeat(3) @(posedge clk);
    
    // Test reading from reset vector at $FFFC-$FFFD
    cs = 1;
    addr = 16'hFFFC;
    #1 $display("Reading from $FFFC: %02X", dout);
    @(posedge clk);
    
    addr = 16'hFFFD;
    #1 $display("Reading from $FFFD: %02X", dout);
    @(posedge clk);
    
    // Test reading from program start at $0300
    addr = 16'h0300;
    #1 $display("Reading from $0300: %02X", dout);
    @(posedge clk);
    
    addr = 16'h0301;
    #1 $display("Reading from $0301: %02X", dout);
    @(posedge clk);
    
    // Test writing to RAM
    rw = 0; // Write mode
    addr = 16'h0400;
    din = 8'hAA;
    @(posedge clk);
    
    // Verify write by reading back
    rw = 1; // Read mode
    #1 $display("Reading from $0400 after write: %02X", dout);
    @(posedge clk);
    
    // Finish test
    cs = 0;
    repeat(3) @(posedge clk);
    $display("RAM Test Completed");
    $finish;
  end
endmodule 