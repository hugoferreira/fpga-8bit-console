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
  // Latched rather than sampled: "the CPU is at $0300 exactly 50 cycles after
  // reset" is an assertion about how fast the core is, not about whether it
  // honoured the reset vector. A faster core is not a broken one.
  bit saw_reset_target = 0;
  bit saw_program_loop = 0;
  
  // Instantiate the RAM module - using a parameter to pass the hex file name
  ram_async #(
    .A(16),
    .D(8),
    .FILE("rtl/test_ram.hex")  // relative to the working directory, not to this file
  ) ram (
    .clk(clk),
    .cs(1'b1),        // Always selected in testbench
    .rw(WE),          // ram_async reads on ~rw, so rw follows WE - as
                      // chip.sv wires it. This bench had it inverted, so
                      // the RAM never drove a read and the bus stayed X.
    .addr(AB),
    .di(DO),
    .dout(DI)
  );
  
  // The core, driven directly rather than through the wrapper, so this bench
  // sees the same signal names the conformance harness does.
  cpu6502_core cpu_inst(
    .clk(clk),
    .reset(reset),
    .AB(AB),        // Address bus
    .DI(DI),        // Data in from RAM
    .DO(DO),        // Data out to RAM
    .WE(WE),        // Write enable
    .WE_PEND(),     // ungated write intent; unused here
    .IRQ(IRQ),
    .NMI(NMI),
    .RDY(RDY),
    .dbg_pc(), .dbg_a(), .dbg_x(), .dbg_y(), .dbg_s(), .dbg_p(), .dbg_b(),
    .dbg_sync(), .dbg_trap(), .dbg_trap_ir(), .dbg_trap_pc()
  );
  
  // Clock generation - 10ns period (100MHz)
  always #5 clk = ~clk;
  
  // Count cycles on positive clock edge
  always @(posedge clk) cycle_count = cycle_count + 1;

  always @(posedge clk) if (!reset) begin
    if (AB === 16'h0300) saw_reset_target <= 1;   // reset vector honoured
    if (AB === 16'h0314) saw_program_loop <= 1;   // reached the JMP at the end
  end
  
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
    
    // Check if CPU is at the correct address.
    //
    // This used to $display "TEST FAILED" and carry on, so `make test` exited
    // 0 whether it passed or not - which is why nothing in this repo could be
    // regressed against it. $fatal makes the check a check.
    // Run long enough for any plausible core to get through the program.
    repeat(50) @(posedge clk);

    $display("TB: After reset, CPU address bus showing: $%04X", AB);
    if (!saw_reset_target) begin
      $display("TEST FAILED: CPU never fetched from $0300 - reset vector not honoured");
      $fatal(1);
    end
    if (!saw_program_loop) begin
      $display("TEST FAILED: CPU reached $0300 but never got to the JMP at $0314");
      $fatal(1);
    end
    $display("TEST PASSED: reset vector honoured and the program ran to its loop");

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