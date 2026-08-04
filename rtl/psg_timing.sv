// Fractional 22.05 kHz sample clock and the 183-sample sequencer cadence.

`ifndef PSG_TIMING_SV
`define PSG_TIMING_SV

module psg_timing #(
    parameter CLK_HZ = 32'd3_506_580
) (
    input  bit         clk,
    input  bit         reset,
    output logic       sample_en,
    output logic       tick_en,
    output logic       tick_en_d,
    output logic       pre_tick,
    output logic [7:0] scnt
);

  // divd is the sample accumulator offset by its wrap threshold. Its sign
  // selects between adding 22050 and subtracting CLK_HZ-22050.
  //
  // Both steps are multiples of gcd(CLK_HZ, 22050), and a Bresenham sign
  // sequence is invariant under uniform scaling of (up, down, init) — by
  // induction divd_reduced == divd/g at every clock, so the strobe pattern
  // is cycle-identical while the adder spans only CLK_HZ/g.
  function automatic integer gcd_f(input integer a, input integer b);
    integer t;
    begin
      while (b != 0) begin
        t = a % b;
        a = b;
        b = t;
      end
      gcd_f = a;
    end
  endfunction
  localparam integer DIV_GCD = gcd_f(CLK_HZ, 32'd22050);
  localparam int DIV_W = $clog2(CLK_HZ / DIV_GCD) + 1;
  localparam logic signed [DIV_W-1:0] DIV_DOWN =
      DIV_W'((CLK_HZ - 32'd22050) / DIV_GCD);
  localparam logic signed [DIV_W-1:0] DIV_UP = DIV_W'(32'd22050 / DIV_GCD);
  logic signed [DIV_W-1:0] divd;
  // scnt is the 0..182 tick cadence; tick_hold produces the delayed boundary
  // used to publish the bank prepared by the preceding tick program.
  logic [1:0] tick_hold;
  wire logic signed [DIV_W-1:0] div_step = divd[DIV_W-1]
      ? DIV_UP : -DIV_DOWN;

  always_ff @(posedge clk) begin
    if (reset) begin
      divd <= -DIV_DOWN;
      sample_en <= 0;
      scnt <= 0;
      tick_en <= 0;
      tick_en_d <= 0;
      tick_hold <= 2'd0;
      pre_tick <= 0;
    end else begin
      divd <= divd + div_step;
      sample_en <= !divd[DIV_W-1];
      tick_en <= 0;
      tick_en_d <= 0;
      pre_tick <= 0;
      if (!divd[DIV_W-1]) begin
        tick_en_d <= (tick_hold == 2'd1);
        if (tick_hold != 2'd0)
          tick_hold <= tick_hold - 2'd1;
        if (scnt == 8'd182) begin
          scnt <= 0;
          tick_en <= 1;
          tick_hold <= 2'd2;
        end else begin
          scnt <= scnt + 1;

          // Start the tick program six sample intervals before tick_en.
          if (scnt == 8'd176)
            pre_tick <= 1;
        end
      end
    end
  end

endmodule

`endif
