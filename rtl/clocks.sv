// Clock tree. One source: the PLL at 112.5 MHz (see rtl/pll.v).
//
//   psgclk    112.5 MHz      the PSG, undivided
//   masterclk 3.515625 MHz   CPU, PPU, sprite compositor  (112.5 / 32)
//   videoclk  3.515625 MHz   video timing                 (112.5 / 32)
//   cpuclk    3.515625 MHz   kept for the existing chip port
//
// Everything is an integer division of one PLL output, so every clock here is
// phase-locked to every other. That is the point: the PSG samples CPU-side
// register writes directly, and a masterclk-domain signal is stable for 32
// psgclk edges, so there is no asynchronous crossing anywhere and no
// synchroniser chain.
//
// Why the PSG wants the fast clock: at 112.5 MHz it gets 5102 clocks per
// 22050 Hz sample instead of 159. Sixteen voices with their state streamed
// from block RAM cost about 320 of those - 6% of budget. At the video clock
// they cost 201% and could not be fitted at all, which forced the voice state
// into flip-flops: synthesis put sixteen voices' worth at 9378 LUT4 against
// an HX8K's 7680.
module clocks(input bit clk, output bit reset, output bit masterclk,
              output bit videoclk, output bit cpuclk, output bit psgclk);

  localparam int DIV = 32;              // 112.5 MHz -> 3.515625 MHz

  logic [15:0] reset_counter = 16'hFFFF;  // Start with reset active
  logic reset_complete = 0;

  always_ff @(posedge clk) begin
    if (reset_counter != 0) begin
      reset_counter <= reset_counter - 1;

      // Print progress messages
      if (reset_counter == 16'hFFFF)
        $display("Clocks: Reset period starting.");
      else if (reset_counter == 16'h8000)
        $display("Clocks: Reset period 50%% complete.");
      else if (reset_counter == 16'h0100)
        $display("Clocks: Reset period 99%% complete.");
      else if (reset_counter == 1) begin
        $display("Clocks: Reset period complete. CPU should now start execution.");
        reset_complete <= 1;
      end
    end else if (reset_complete) begin
      // Reset is complete, print a message just once
      $display("Clocks: System running with clean clocks.");
      reset_complete <= 0;
    end
  end

  assign reset = (reset_counter != 0);  // Reset active during counter period

  // /32 at 50% duty: toggle every DIV/2 source clocks. A counter and a
  // comparison, not a ripple of flops clocking each other the way
  // slower_clk.sv does - that keeps one clock root for the whole design.
  logic [3:0] divcnt = 0;
  logic       slow = 0;
  always_ff @(posedge clk) begin
    if (divcnt == 4'(DIV / 2 - 1)) begin
      divcnt <= 0;
      slow <= ~slow;
    end else
      divcnt <= divcnt + 1;
  end

  assign psgclk    = clk;
  assign masterclk = slow;
  assign videoclk  = slow;
  assign cpuclk    = slow;
endmodule
