// Unsigned 24-by-8 restoring divider. A request takes 24 cycles and returns
// the quotient in d_res and remainder in d_rem; the sequencer is its only
// requester. Callers never submit a zero divisor.

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

  logic [31:0] d_p; // {remainder, dividend/quotient}
  logic [7:0]  d_d;
  logic [4:0]  d_cnt;

  // The shifted partial remainder needs nine bits for compare/subtract.
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
