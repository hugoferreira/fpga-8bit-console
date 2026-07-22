/*
 * Testbench for 6502 CPU with async RAM to validate reset sequence
 */

`ifndef SIMULATION
`define SIMULATION 1
`endif

// Add timescale directive for simulation
`timescale 1ns/1ps

module cpu6502_tb();
  // Clock and reset signals
  bit clk = 0;
  bit reset = 1;
  
  // Memory interface signals
  wire [15:0] AB;      // Address bus
  wire [7:0] DI;       // Data input to CPU
  wire [7:0] DO;       // Data output from CPU
  wire WE;             // Write enable
  wire RDY = 1;        // Ready signal (always ready for testbench)
  wire IRQ = 0;        // Interrupt (disabled for test)
  wire NMI = 0;        // NMI (disabled for test)
  
  // Test control
  int cycle_count = 0;
  
  // Instantiate the RAM module - using a parameter to pass the hex file name
  ram_async #(
    .A(16),
    .D(8),
    .FILE("test_ram.hex")  // This file should be pre-created before running the test
  ) ram (
    .clk(clk),
    .cs(1'b1),        // Always selected in testbench
    .rw(~WE),         // rw=1 for read, WE=0 for read
    .addr(AB),
    .di(DO),
    .dout(DI)
  );
  
  // Instantiate the 6502 CPU - module name is "cpu" in cpu6502_arlet.sv
  cpu cpu_inst(
    .clk(clk),
    .reset(reset),
    .AB(AB),        // Address bus
    .DI(DI),        // Data in from RAM
    .DO(DO),        // Data out to RAM
    .WE(WE),        // Write enable
    .IRQ(IRQ),
    .NMI(NMI),
    .RDY(RDY)
  );
  
  // Clock generation - 10ns period (100MHz)
  always #5 clk = ~clk;
  
  // Count cycles on positive clock edge
  always @(posedge clk) cycle_count = cycle_count + 1;
  
  // Test sequence
  initial begin
    // Setup waveform dumping
    $dumpfile("dump.vcd");
    $dumpvars(0, cpu6502_tb);
    
    $display("TB: Starting 6502 CPU reset vector test");
    
    // Make sure test memory has been pre-initialized with:
    // - Reset vector at $FFFC-$FFFD = 00 03 (pointing to $0300)
    // - Program at $0300: A9 42 A2 69 EA EA 4C 06 03 ...
    
    // Start reset sequence
    reset = 1;
    $display("TB: Reset asserted at cycle %0d", cycle_count);
    
    // Hold reset for a few cycles
    repeat(10) @(posedge clk);
    
    // Release reset and observe CPU behavior
    reset = 0;
    $display("TB: Reset released at cycle %0d", cycle_count);
    
    // Give CPU time to read reset vector and start execution
    repeat(50) @(posedge clk);
    
    // Check if CPU is at the correct address
    $display("TB: After reset, CPU address bus showing: $%04X", AB);
    if (AB == 16'h0300) begin
      $display("TEST PASSED: CPU reset to correct address $0300");
    end else begin
      $display("TEST FAILED: CPU did not reset to expected address");
      $display("  Expected: $0300, Actual: $%04X", AB);
    end
    
    // Run for a bit longer to see execution of program
    repeat(50) @(posedge clk);
    
    $display("TB: Test complete after %0d cycles", cycle_count);
    $finish;
  end
  
  // Monitor CPU execution
  always @(posedge clk) begin
    if (!reset && AB >= 16'h0300 && AB <= 16'h0310) begin
      $display("TB: CPU accessing program area at cycle %0d: Address=$%04X, Data=%02X, WE=%b", 
               cycle_count, AB, DI, WE);
    end
    
    if (!reset && AB >= 16'hFFFA && AB <= 16'hFFFF) begin
      $display("TB: CPU accessing vector area at cycle %0d: Address=$%04X, Data=%02X, WE=%b", 
               cycle_count, AB, DI, WE);
    end
  end
endmodule 