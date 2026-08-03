// Related-clock multiplier phase regression.
//
// Sweeps the relative phase which the board PLL can impose between its 112.5
// MHz output and divided /6 output. Each configured offset checks that the
// multi-pumped result and padded busy window match the single-clock service.

`timescale 1ns/1ps

module psg_mulmp_phase_tb #(parameter integer SLOW_OFFSET_NS = 0);
  bit fastclk = 1'b0;
  bit clk = 1'b0;
  bit reset = 1'b1;

  always #5 fastclk = ~fastclk;
  initial begin
    #(20 + SLOW_OFFSET_NS) clk = 1'b1;
    forever #30 clk = ~clk;
  end

  logic               start = 1'b0;
  logic signed [24:0] a = 0;
  logic [11:0]        b = 0;
  logic [1:0]         mode = 0;
  logic               short_req = 1'b0;
  wire [33:0] ref_res, mp_res;
  wire ref_busy, mp_busy, mp_seq_busy;

  psg_mulsvc ref_dut(
      .clk, .reset, .mul_start(start), .mul_start_a(a), .mul_start_b(b),
      .mul_start_mode(mode), .mul_start_short(short_req),
      .m_res(ref_res), .m_busy(ref_busy));

  psg_mulmp #(.RADIX_BITS(1)) mp_dut(
      .clk, .fastclk, .reset, .mul_start(start), .mul_start_a(a),
      .mul_start_b(b), .mul_start_mode(mode),
      .mul_start_short(short_req), .m_res(mp_res), .m_busy(mp_busy),
      .m_seq_busy(mp_seq_busy));

  task automatic run_case(input logic signed [17:0] av,
                          input logic [11:0] bv,
                          input logic [1:0] mv,
                          input logic sv);
    begin
      @(negedge clk);
      a = {{7{av[17]}}, av};
      b = bv;
      mode = mv;
      short_req = sv;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
      wait (!ref_busy && !mp_busy);
      @(negedge clk);
      if (mp_res !== ref_res) begin
        $error("phase %0d: result mismatch mode=%0d short=%0b got=%h ref=%h",
               SLOW_OFFSET_NS, mv, sv, mp_res, ref_res);
        $fatal;
      end
    end
  endtask

  always @(negedge clk) begin
    if (!reset && mp_seq_busy !== ref_busy) begin
      $error("phase %0d: padded busy differs reference=%0b multi-pumped=%0b",
             SLOW_OFFSET_NS, ref_busy, mp_seq_busy);
      $fatal;
    end
  end

  initial begin
    repeat (4) @(negedge clk);
    reset = 1'b0;
    // Cover the longest radix-2 request plus the shortened request and every
    // result landing shape. Boundary magnitudes make corruption obvious.
    run_case(-18'sh20000, 12'hfff, 2'd0, 1'b0);
    run_case( 18'sh1ffff, 12'hfff, 2'd1, 1'b0);
    run_case(-18'sh20000, 12'hfff, 2'd2, 1'b0);
    run_case( 18'sh1ffff, 12'h1ff, 2'd3, 1'b0);
    run_case(-18'sh20000, 12'h03f, 2'd0, 1'b1);
    $display("PASS phase=%0d ns", SLOW_OFFSET_NS);
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "phase %0d: timeout", SLOW_OFFSET_NS);
  end
endmodule
