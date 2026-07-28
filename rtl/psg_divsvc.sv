// PSG divide service: one restoring divider, requested by the sequencer only.
//
// Exact truncated division (adopt-pico8-integer-audio 3.2a). The effect
// recurrences divide by the SFX speed, and recip[s] = round(65536/s) is not
// exact truncated division. A 24-bit dividend field over an 8-bit divisor,
// 24 shift-subtract steps, the partial remainder held in the top byte.
//
// Its own unit rather than a mode on the multiply service so a divide can
// overlap the next product: the 9-bit compare-subtract is cheaper than muxing
// the 26-bit accumulator's shift direction either way.
`ifndef PSG_DIVSVC_SV
`define PSG_DIVSVC_SV

module psg_divsvc (input  bit          clk,
                   input  bit          reset,
                   input  logic        div_start,
                   input  logic [23:0] div_n,
                   input  logic [7:0]  div_d,
                   output logic [23:0] d_res,
                   output logic [7:0]  d_rem,
                   output logic        d_busy);

  logic [31:0] d_p;                  // {remainder[7:0], dividend/quotient}
  logic [7:0]  d_d;
  logic [4:0]  d_cnt;
  // rem < d holds from rem = 0, so the shifted partial is 9 bits and the
  // restored remainder is always back under a byte.
  wire  [8:0]  d_rsh = {d_p[31:24], d_p[23]};
  wire  [9:0]  d_sub = {1'b0, d_rsh} - {2'b0, d_d};
  wire         d_fit = !d_sub[9];

  assign d_res  = d_p[23:0];
  assign d_rem  = d_p[31:24];
  assign d_busy = (d_cnt != 0);

  always_ff @(posedge clk) begin
    if (reset)
      d_cnt <= 0;
    else if (d_cnt != 0) begin
      d_p   <= {(d_fit ? d_sub[7:0] : d_rsh[7:0]), d_p[22:0], d_fit};
      d_cnt <= d_cnt - 5'd1;
    end else if (div_start) begin
      d_p   <= {8'b0, div_n};
      d_d   <= div_d;
      d_cnt <= 5'd24;
    end
  end

endmodule

`endif
