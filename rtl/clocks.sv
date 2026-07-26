// Clock tree. One source: the PLL at 112.5 MHz (see rtl/pll.v).
//
//   psgclk    112.5 / PSGDIV          the PSG
//   masterclk 3.515625 MHz            CPU, PPU, sprite compositor  (112.5 / 32)
//   videoclk  3.515625 MHz            video timing                 (112.5 / 32)
//   cpuclk    3.515625 MHz            kept for the existing chip port
//
// Everything is an integer division of one PLL output, so every clock here is
// phase-locked to every other. That is the point: the PSG samples CPU-side
// register writes directly, and a masterclk-domain signal is stable for
// 32/PSGDIV psgclk edges, so there is no asynchronous crossing anywhere and no
// synchroniser chain. Both clocks are taken as bits of ONE counter rather than
// from separate dividers, so that relationship holds by construction.
//
// PSGDIV EXISTS BECAUSE THE UNDIVIDED CLOCK DOES NOT CLOSE.
// This file used to hand the PSG the full 112.5 MHz and assert in a comment
// that it therefore had 5102 clocks per 22050 Hz sample. `make synth-psg`
// measures the PSG at Fmax 27.98 MHz (critical path prun -> n_res, the
// sample x volume multiply), so 112.5 missed by 4x and the comment documented
// a rate the hardware never had. PSGDIV = 4 gives 28.125 MHz, the first
// division that closes, and 1275 clocks per sample - still 8x what the console
// simulator's 159 affords, which is the budget the PSG is designed against.
//
// The rate is ONE knob: rtl/top.sv derives its CLK_HZ from the same PSGDIV, so
// the divider and the frequency the PSG computes its sample rate from cannot
// drift apart. They are two facts about the same clock and getting them out of
// step detunes the audio silently. Set PSGDIV back to 1 only against a fresh
// `make synth-psg` Fmax that actually clears 112.5 MHz.
module clocks #(parameter int PSGDIV = 4)
             (input bit clk, output bit reset, output bit masterclk,
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

  // One free-running counter, and both clocks are bits of it. Bit k toggles
  // every 2^k source clocks, so bit k is the source divided by 2^(k+1) at an
  // exact 50% duty - and every derived clock shares the counter's edges, which
  // is what makes the phase-lock structural rather than something to verify.
  localparam int CW = $clog2(DIV);      // DIV = 32 -> 5 bits, bit 4 is /32
  logic [CW-1:0] ctr = 0;
  always_ff @(posedge clk) ctr <= ctr + 1;

  // PSGDIV = 1 takes the source directly; otherwise bit log2(PSGDIV)-1, which
  // is the source divided by PSGDIV.
  generate
    if (PSGDIV <= 1) assign psgclk = clk;
    else             assign psgclk = ctr[$clog2(PSGDIV) - 1];
  endgenerate

  assign masterclk = ctr[CW-1];
  assign videoclk  = ctr[CW-1];
  assign cpuclk    = ctr[CW-1];
endmodule
