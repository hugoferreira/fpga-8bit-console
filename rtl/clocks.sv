// Clock tree. One source: the PLL at 112.5 MHz (see rtl/pll.v).
//
//   psgclk    112.5 / PSGDIV          the PSG
//   masterclk 3.515625 MHz            CPU, PPU, sprite compositor  (112.5 / 32)
//   videoclk  3.515625 MHz            video timing                 (112.5 / 32)
//   cpuclk    3.515625 MHz            kept for the existing chip port
//
// Everything is an integer division of one PLL output, so every clock here is
// phase-locked to every other. That is the point: the PSG samples CPU-side
// register writes directly, and a masterclk-domain signal is stable for at
// least floor(32/PSGDIV) complete PSG clocks. Power-of-two divisions are bits
// of the /32 counter. Non-power-of-two PSG edges come from a registered modulo
// divider on the PLL's falling edge, so a PSG rising edge can never coincide
// with the CPU/master rising edge generated on a PLL rising edge.
//
// PSGDIV EXISTS BECAUSE THE UNDIVIDED CLOCK DOES NOT CLOSE.
// This file used to hand the PSG the full 112.5 MHz and assert in a comment
// that it therefore had 5102 clocks per 22050 Hz sample. `make synth-psg`
// measures the PSG at Fmax 27.98 MHz (critical path prun -> n_res, the
// sample x volume multiply), so 112.5 missed by 4x and the comment documented
// a rate the hardware never had. PSGDIV = 4 gives 28.125 MHz, the first
// division that closes. The bounded 578-clock schedule is render-exact at /6,
// 18.75 MHz and at least 850 clocks/sample; together with the fixed 272
// sequencer credits it exactly fills the minimum interval. The interactive
// Verilated console runs a different lowering for
// host throughput; that host execution rate is not a synthesized scheduling
// constraint.
//
// The rate is ONE knob: rtl/top.sv derives its CLK_HZ from the same PSGDIV, so
// the divider and the frequency the PSG computes its sample rate from cannot
// drift apart. They are two facts about the same clock and getting them out of
// step detunes the audio silently.
module clocks #(parameter int PSGDIV = 6)
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

  // One free-running counter supplies the /32 clocks. Bit k toggles every 2^k
  // source clocks, so bit k is the source divided by 2^(k+1) at exact 50% duty.
  localparam int CW = $clog2(DIV);      // DIV = 32 -> 5 bits, bit 4 is /32
  logic [CW-1:0] ctr = 0;
  always_ff @(posedge clk) ctr <= ctr + 1;

  // Power-of-two PSG divisions reuse the same counter. A non-power-of-two
  // division uses a registered modulo counter: no combinational decode drives
  // a clock, and odd divisors have the unavoidable one-source-cycle duty
  // asymmetry. Its falling-edge source phase keeps every PSG rising edge half
  // a PLL cycle away from every CPU/master rising edge.
  generate
    if (PSGDIV <= 1) begin : g_psg_direct
      assign psgclk = clk;
    end else if ((PSGDIV & (PSGDIV - 1)) == 0) begin : g_psg_pow2
      assign psgclk = ctr[$clog2(PSGDIV) - 1];
    end else begin : g_psg_mod
      localparam int PCW = $clog2(PSGDIV);
      localparam int PHI = PSGDIV / 2;
      logic [PCW-1:0] pctr = 0;
      logic           pclk = 0;

      always_ff @(negedge clk) begin
        if (pctr == PCW'(PSGDIV - 1)) begin
          pctr <= 0;
          pclk <= 1;
        end else begin
          pctr <= pctr + 1'b1;
          if (pctr == PCW'(PHI - 1))
            pclk <= 0;
        end
      end
      assign psgclk = pclk;
    end
  endgenerate

  assign masterclk = ctr[CW-1];
  assign videoclk  = ctr[CW-1];
  assign cpuclk    = ctr[CW-1];
endmodule
