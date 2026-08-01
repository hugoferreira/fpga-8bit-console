`include "psg_mulmp.sv"

module target_psg_mulmp #(parameter int RADIX_BITS = 1) (
    input  logic               clk,
    input  logic               fastclk,
    input  logic               reset,
    input  logic               start_i,
    input  logic signed [24:0] a_i,
    input  logic [11:0]        b_i,
    input  logic [1:0]         mode_i,
    input  logic               short_i,
    output logic [33:0]        result_o,
    output logic               busy_o,
    output logic               seq_busy_o
);
  logic start_r;
  logic signed [24:0] a_r;
  logic [11:0] b_r;
  logic [1:0] mode_r;
  logic short_r;
  wire [33:0] result_w;
  wire busy_w, seq_busy_w;

  always_ff @(posedge clk) begin
    start_r <= start_i;
    a_r <= a_i;
    b_r <= b_i;
    mode_r <= mode_i;
    short_r <= short_i;
    if (!busy_w)
      result_o <= result_w;
    busy_o <= busy_w;
    seq_busy_o <= seq_busy_w;
  end

  psg_mulmp #(.RADIX_BITS(RADIX_BITS)) dut(
      .clk(clk), .fastclk(fastclk), .reset(reset),
      .mul_start(start_r), .mul_start_a(a_r), .mul_start_b(b_r),
      .mul_start_mode(mode_r), .mul_start_short(short_r),
      .m_res(result_w), .m_busy(busy_w), .m_seq_busy(seq_busy_w));
endmodule
