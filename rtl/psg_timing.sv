// PSG timing: the 22050 Hz virtual sample rate and the 120.49 Hz sequencer
// tick, derived from CLK_HZ by one fractional divider.
//
// Owns divd/scnt/tick_hold and the five strobes everything else in the chip
// is scheduled against. Nothing here reads any other part of the PSG, which
// is why it is the first thing the split takes out.
`ifndef PSG_TIMING_SV
`define PSG_TIMING_SV

module psg_timing #(parameter CLK_HZ = 32'd3_506_580)
                   (input  bit   clk,
                    input  bit   reset,
                    output logic sample_en,
                    output logic tick_en,
                    output logic tick_en_d,
                    output logic pre_tick,
                    output logic [7:0] scnt);

  // The accumulator is stored OFFSET by the wrap threshold: divd is the
  // classical divacc minus (CLK_HZ - 22050), so "time to emit a sample" is
  // simply divd's sign bit. The unsigned form spent a 27-bit comparator AND
  // separate 27-bit add and subtract networks on the same decision; this is
  // one adder whose second operand is a mux of two constants. The clock-for-
  // clock sample_en/tick_en sequence is unchanged - same Bresenham, same
  // phase - and sim/psg_wav.cpp mirrors the recurrence, not the register.
  // 28 bits: the fastest clock this design can be given is the 112.5 MHz PLL
  // output, and the offset form needs its magnitude plus a sign.
  localparam logic [26:0] DIV_DOWN = 27'(CLK_HZ - 32'd22050);
  logic signed [27:0] divd;
  logic [1:0]  tick_hold;

  always_ff @(posedge clk) begin
    if (reset) begin
      divd <= -$signed({1'b0, DIV_DOWN});
      sample_en <= 0;
      scnt <= 0;
      tick_en <= 0;
      tick_en_d <= 0;
      tick_hold <= 2'd0;
      pre_tick <= 0;
    end else begin
      tick_en <= 0;
      tick_en_d <= 0;
      pre_tick <= 0;
      if (!divd[27]) begin             // divacc >= CLK_HZ - 22050
        divd <= divd - $signed({1'b0, DIV_DOWN});
        sample_en <= 1;
        // The grid effects (bank flip, deferred stops) land two SAMPLES
        // after tick_en, which is where the capture pipeline puts stream
        // tick boundaries (adjudicated by the transition cases).
        tick_en_d <= (tick_hold == 2'd1);
        if (tick_hold != 2'd0)
          tick_hold <= tick_hold - 2'd1;
        if (scnt == 8'd182) begin
          scnt <= 0;
          tick_en <= 1;
          tick_hold <= 2'd2;
        end else begin
          scnt <= scnt + 1;
          // Six intervals of pre-run window. The engine's advance and
          // staging sequences grew the tick program past one interval's
          // slack, and section 3's exact divides (two for a slide, one
          // for the volume, one for an instrument's seventh) grew it
          // past four: psg_tb's all-eight-slots case measures 5,044
          // clocks, which four intervals clear by only 56. The pre_tick
          // constant is exactly the knob the 3.0 handshake left for that
          // (design 3, staging constraints). The cost is that a CPU
          // write landing inside the window is observed one tick
          // evaluation later, over a wider window than before.
          if (scnt == 8'd176)
            pre_tick <= 1;
        end
      end else begin
        divd <= divd + 28'sd22050;
        sample_en <= 0;
      end
    end
  end

endmodule

`endif
