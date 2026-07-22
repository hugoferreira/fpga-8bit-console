// Testbench for ram_async module
`timescale 1ns/1ps

module ram_async_tb;
  // Parameters
  localparam A = 16;  // Address width
  localparam D = 8;   // Data width
  localparam FILE = "./rtl/ram.hex";  // Use actual file from the project

  // Signals
  logic clk;
  logic cs;
  logic rw; 
  logic [A-1:0] addr;
  logic [D-1:0] di;
  logic [D-1:0] dout;
  
  // Instantiate the RAM module
  ram_async #(
    .A(A),
    .D(D),
    .FILE(FILE)
  ) ram_inst (
    .clk(clk),
    .cs(cs),
    .rw(rw),
    .addr(addr),
    .di(di),
    .dout(dout)
  );
  
  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz clock
  end
  
  // Test sequence
  initial begin
    // Initialize signals
    cs = 0;
    rw = 0;  // Read mode
    addr = 0;
    di = 0;
    
    // Wait for memory initialization to complete
    #10;
    
    // Display test header
    $display("==== RAM Async Module Test ====");
    
    // Test 1: Read from reset vector
    cs = 1;
    rw = 0;  // Read mode
    addr = 16'hFFFC;
    #10;  // Wait for clock edge
    $display("Test 1: Read Reset Vector Low Byte ($FFFC) = %02X", dout);
    
    #10;
    addr = 16'hFFFD;
    #10;
    $display("Test 1: Read Reset Vector High Byte ($FFFD) = %02X", dout);
    
    // Test 2: Read from program start
    addr = 16'h0300;
    #10;
    $display("Test 2: Read Program Start ($0300) = %02X", dout);
    
    addr = 16'h0301;
    #10;
    $display("Test 2: Read Program Start+1 ($0301) = %02X", dout);
    
    // Test 3: Write and read from a RAM location
    addr = 16'h0200;
    rw = 1;  // Write mode
    di = 8'hAA;
    #10;
    $display("Test 3: Wrote %02X to $0200", di);
    
    rw = 0;  // Read mode
    #10;
    $display("Test 3: Read from $0200 = %02X", dout);
    
    // Test 4: Write pattern and read back
    $display("Test 4: Write and Read Pattern Test");
    for (int i = 0; i < 16; i++) begin
      addr = 16'h0100 + i;
      rw = 1;  // Write mode
      di = 8'h10 + i;
      #10;
      
      rw = 0;  // Read mode
      #10;
      $display("  Addr $%04X: Wrote %02X, Read %02X %s", 
               addr, 8'h10 + i, dout, 
               (dout == (8'h10 + i)) ? "[PASS]" : "[FAIL]");
    end
    
    // Test 5: CS disabled test
    cs = 0;
    addr = 16'h0100;
    #10;
    $display("Test 5: CS disabled, Read from $0100 = %02X (should maintain previous value)", dout);
    
    // Test complete
    #10;
    $display("==== RAM Test Complete ====");
    $finish;
  end
  
  // Optional: Create VCD file for waveform viewing
  initial begin
    $dumpfile("ram_async_tb.vcd");
    $dumpvars(0, ram_async_tb);
  end
  
endmodule 