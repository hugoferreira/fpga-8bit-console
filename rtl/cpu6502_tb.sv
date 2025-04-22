/*
 * Simple testbench for the wrapped 6502 CPU implementation
 */

`ifndef SIMULATION
`define SIMULATION 1
`endif

module cpu6502_tb();
  // Clock and reset signals
  bit clk = 0;
  bit reset = 1;
  
  // Memory interface signals
  wire [15:0] address;
  wire [7:0] data_out;
  reg [7:0] data_in;
  wire write;
  
  // Counter for test control
  int cycle_count = 0;
  
  // Create a simple memory
  reg [7:0] memory[0:65535];
  
  // Initialize memory with reset vectors
  initial begin
    // Set the reset vector to point to 0xC000
    memory[16'hFFFC] = 8'h00;
    memory[16'hFFFD] = 8'hC0;
    
    // Add a simple program at 0xC000 (just a NOP)
    memory[16'hC000] = 8'hEA;  // NOP
  end
  
  // Memory read logic
  always @(posedge clk) begin
    data_in <= memory[address];
  end
  
  // Memory write logic
  always @(posedge clk) begin
    if (write) begin
      memory[address] <= data_out;
    end
  end
  
  // Instantiate the CPU
  cpu6502 cpu(
    .clk(clk),
    .reset(reset),
    .address(address),
    .data_in(data_in),
    .data_out(data_out),
    .write(write)
  );
  
  // Clock generation
  always begin
    #5 clk = ~clk;
    if (clk) cycle_count++;
  end
  
  // Reset pulse
  initial begin
    reset = 1;
    #15 reset = 0;
  end
  
  // Monitor simulation
  initial begin
    $display("Starting CPU test...");
    
    // Wait for reset to complete and a few cycles to pass
    #50;
    
    // Check if the CPU is reading from the correct address after reset
    if (address == 16'hC000) begin
      $display("TEST PASSED: CPU reset to correct address");
    end else begin
      $display("TEST FAILED: CPU did not reset to the expected address");
      $display("  Expected: 0xC000, Actual: 0x%04X", address);
    end
    
    // Wait a few more cycles and finish
    #50;
    $finish;
  end
endmodule 