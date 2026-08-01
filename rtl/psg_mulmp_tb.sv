`timescale 1ns/1ps

module psg_mulmp_tb;
  bit fastclk = 0;
  bit clk = 0;
  bit reset = 1;

  // Six fast clocks per PSG clock. PSG rising edges coincide with fast-clock
  // falling edges, matching clocks.sv's odd-divider phase relationship.
  always #5 fastclk = ~fastclk;
  initial begin
    #10;
    forever #30 clk = ~clk;
  end

  logic               start = 0;
  logic signed [24:0] a = 0;
  logic [11:0]        b = 0;
  logic [1:0]         mode = 0;
  logic               short_req = 0;

  wire [33:0] ref_res, r2_res, r4_res;
  wire ref_busy, r2_busy, r4_busy;
  wire r2_seq_busy, r4_seq_busy;

  psg_mulsvc ref_dut(
      .clk(clk), .reset(reset),
      .mul_start(start), .mul_start_a(a), .mul_start_b(b),
      .mul_start_mode(mode), .mul_start_short(short_req),
      .m_res(ref_res), .m_busy(ref_busy));

  psg_mulmp #(.RADIX_BITS(1)) r2_dut(
      .clk(clk), .fastclk(fastclk), .reset(reset),
      .mul_start(start), .mul_start_a(a), .mul_start_b(b),
      .mul_start_mode(mode), .mul_start_short(short_req),
      .m_res(r2_res), .m_busy(r2_busy), .m_seq_busy(r2_seq_busy));

  psg_mulmp #(.RADIX_BITS(2)) r4_dut(
      .clk(clk), .fastclk(fastclk), .reset(reset),
      .mul_start(start), .mul_start_a(a), .mul_start_b(b),
      .mul_start_mode(mode), .mul_start_short(short_req),
      .m_res(r4_res), .m_busy(r4_busy), .m_seq_busy(r4_seq_busy));

  int errors = 0;
  int cases = 0;
  int r2_wait, r4_wait;
  int r2_max = 0, r4_max = 0;
  int r2_short_max = 0;
  bit active = 0;

  always @(negedge clk) begin
    if (!reset) begin
      if (r2_seq_busy !== ref_busy) begin
        $error("radix-2 padded busy differs: ref=%0b candidate=%0b",
               ref_busy, r2_seq_busy);
        errors++;
      end
      if (r4_seq_busy !== ref_busy) begin
        $error("radix-4 padded busy differs: ref=%0b candidate=%0b",
               ref_busy, r4_seq_busy);
        errors++;
      end
      if (!ref_busy && (r2_busy || r4_busy)) begin
        $error("multi-pumped result was not ready before reference busy fell");
        errors++;
      end
      if (active) begin
        if (r2_busy) r2_wait++;
        if (r4_busy) r4_wait++;
      end
    end
  end

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
      start = 1;
      r2_wait = 0;
      r4_wait = 0;
      active = 1;
      @(negedge clk);
      start = 0;
      wait (!ref_busy && !r2_busy && !r4_busy);
      @(negedge clk);
      active = 0;
      if (r2_wait > r2_max) r2_max = r2_wait;
      if (r4_wait > r4_max) r4_max = r4_wait;
      if (sv && r2_wait > r2_short_max) r2_short_max = r2_wait;
      if (r2_wait >= (sv ? r2_dut.SHORT_CONSUME_GAP
                         : r2_dut.NORMAL_CONSUME_GAP)) begin
        $error("radix-2 missed consume gap mode=%0d short=%0b busy observations=%0d",
               mv, sv, r2_wait);
        errors++;
      end
      if (r2_res !== ref_res) begin
        $error("radix-2 mismatch A=%0d B=%0d mode=%0d short=%0b got=%h ref=%h",
               av, bv, mv, sv, r2_res, ref_res);
        errors++;
      end
      if (r4_res !== ref_res) begin
        $error("radix-4 mismatch A=%0d B=%0d mode=%0d short=%0b got=%h ref=%h",
               av, bv, mv, sv, r4_res, ref_res);
        errors++;
      end
      cases++;
    end
  endtask

  function automatic logic [11:0] legal_b(input logic [1:0] mv,
                                           input logic sv,
                                           input logic [31:0] raw);
    if (sv) legal_b = {6'b0, raw[5:0]};
    else case (mv)
      2'd2: legal_b = raw[11:0];
      2'd1: legal_b = {2'b0, raw[9:0]};
      2'd3: legal_b = {3'b0, raw[8:0]};
      default: legal_b = {4'b0, raw[7:0]};
    endcase
  endfunction

  initial begin
    repeat (4) @(negedge clk);
    reset = 0;

    for (int mv = 0; mv < 4; mv++) begin
      run_case(18'sd0, 12'd0, mv[1:0], 1'b0);
      run_case(18'sd1, legal_b(mv[1:0], 1'b0, 32'hffff_ffff),
               mv[1:0], 1'b0);
      run_case(-18'sd1, legal_b(mv[1:0], 1'b0, 32'hffff_ffff),
               mv[1:0], 1'b0);
      run_case(18'sh1ffff, legal_b(mv[1:0], 1'b0, 32'hffff_ffff),
               mv[1:0], 1'b0);
      run_case(-18'sh20000, legal_b(mv[1:0], 1'b0, 32'hffff_ffff),
               mv[1:0], 1'b0);
    end

    for (int i = 0; i < 6000; i++) begin
      logic [1:0] mv;
      logic sv;
      logic signed [17:0] av;
      mv = 2'($urandom);
      sv = ($urandom_range(0, 7) == 0);
      av = 18'($urandom);
      run_case(av, legal_b(mv, sv, $urandom), mv, sv);
    end

    if (errors == 0)
      $display("psg_mulmp: PASS %0d transactions, true busy max r2=%0d short=%0d r4=%0d PSG clocks",
               cases, r2_max, r2_short_max, r4_max);
    else
      $fatal(1, "psg_mulmp: FAIL %0d errors across %0d transactions",
             errors, cases);
    $finish;
  end
endmodule
