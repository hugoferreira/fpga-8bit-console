`include "cpu6502_defs.sv"
`include "cpu6502_alu.sv"
`include "cpu6502_arlet.sv"

`define SIM
`define DEBUG

module debug_test;
  // Clock and reset signals
  reg clk = 0;
  reg reset = 1;
  
  // CPU interface
  wire [15:0] address;
  reg [7:0] data_in;
  wire [7:0] data_out;
  wire write;
  
  // Create a simple memory for testing
  reg [7:0] memory[0:65535];
  
  // Initialize memory with our program and reset vectors
  initial begin
    // Load some initialization code for debugging
    memory[16'h0300] = 8'hA9;  // LDA #$42
    memory[16'h0301] = 8'h42;
    memory[16'h0302] = 8'h8D;  // STA $F000
    memory[16'h0303] = 8'h00;
    memory[16'h0304] = 8'hF0;
    memory[16'h0305] = 8'hA9;  // LDA #$41
    memory[16'h0306] = 8'h41;
    memory[16'h0307] = 8'h8D;  // STA $F001
    memory[16'h0308] = 8'h01;
    memory[16'h0309] = 8'hF0;
    
    // Add our reset vector pointing to $0300
    memory[16'hFFFC] = 8'h00;
    memory[16'hFFFD] = 8'h03;
    
    $display("Memory initialized. Reset vector: $%02X%02X", memory[16'hFFFD], memory[16'hFFFC]);
  end
  
  // Memory read logic
  always @(posedge clk) begin
    data_in <= memory[address];
    
    if (address == 16'hFFFC || address == 16'hFFFD) begin
      $display("CPU reading from $%04X = $%02X", address, memory[address]);
    end
  end
  
  // Memory write logic
  always @(posedge clk) begin
    if (write) begin
      memory[address] <= data_out;
      $display("CPU writing $%02X to $%04X", data_out, address);
    end
  end
  
  // Instantiate the CPU
  cpu6502_arlet cpu0(
    .clk(clk),
    .reset(reset),
    .AB(address),
    .DI(data_in),
    .DO(data_out),
    .WE(write),
    .IRQ(1'b0),
    .NMI(1'b0),
    .RDY(1'b1)
  );
  
  // Clock generation
  always #5 clk = ~clk;
  
  // Reset pulse
  initial begin
    reset = 1;
    #20 reset = 0;
    $display("Reset released");
  end
  
  // Run simulation
  initial begin
    $dumpfile("cpu_debug.vcd");
    $dumpvars(0, debug_test);
    
    // Wait for some time
    #2000;
    
    // Print final state
    $display("Simulation finished");
    $finish;
  end
endmodule 