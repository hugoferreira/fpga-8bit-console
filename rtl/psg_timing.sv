// Fractional 22.05 kHz sample clock and the 183-sample sequencer cadence.

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

  // divd is the sample accumulator offset by its wrap threshold. Its sign
  // selects between adding 22050 and subtracting CLK_HZ-22050.
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
      if (!divd[27]) begin
        divd <= divd - $signed({1'b0, DIV_DOWN});
        sample_en <= 1;

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
      end else begin
        divd <= divd + 28'sd22050;
        sample_en <= 0;
      end
    end
  end

endmodule

`endif
