// Multi-pumped multiplier transaction regression.
//
// Compares radix-2 and radix-4 fast-clock implementations with the shared
// single-clock service, checks their sequencer-visible busy windows, and
// freezes every transaction stage and acknowledge crossing through the core.

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
  logic               freeze = 0;

  wire [33:0] ref_res, r2_res, r4_res, hold_res;
  wire ref_busy, r2_busy, r4_busy, hold_busy;
  wire r2_seq_busy, r4_seq_busy;
  wire hold_seq_busy;

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

  psg_mulmp_core #(.RADIX_BITS(1)) hold_dut(
      .clk(clk), .fastclk(fastclk), .reset(reset), .freeze(freeze),
      .mul_start(start), .mul_start_a(a), .mul_start_b(b),
      .mul_start_mode(mode), .mul_start_short(short_req),
      .m_res(hold_res), .m_busy(hold_busy), .m_seq_busy(hold_seq_busy));

  int errors = 0;
  int cases = 0;
  int r2_wait, r4_wait;
  int r2_max = 0, r4_max = 0;
  int r2_short_max = 0;
  bit active = 0;
  bit edge_trace = 0;
  bit trace_enable = 0;
  bit trace_active = 0;
  int slow_edge = 0;
  int fast_edge = 0;
  int trace_case = 0;
  int slow_case = 0;
  int fast_subedge = 0;

  initial edge_trace = $test$plusargs("PSG_EDGE_TRACE");

  // bench_case/slow_edge/subedge are diagnostic coordinates only.  A trace
  // consumer must derive transactions from req/ack toggle transitions and
  // use time/domain/edge/phase for causal ordering.
  always @(posedge clk) begin
    fast_subedge = 0;
    if (edge_trace && trace_enable) begin
      trace_active = 1'b1;
      slow_case = trace_case;
      $display("PSGTRACE {\"schema\":\"psg_edge_v1\",\"svc\":\"mul\",\"domain\":\"slow\",\"phase\":\"pre\",\"edge\":%0d,\"bench_case\":%0d,\"time\":%0t,\"reset\":%0b,\"freeze\":%0b,\"start\":%0b,\"a_signed\":%0d,\"a_raw\":\"%0h\",\"b\":%0d,\"mode\":%0d,\"short\":%0b,\"req_a\":\"%0h\",\"req_b\":\"%0h\",\"req_steps\":%0d,\"req_tgl\":%0b,\"ack_tgl\":%0b,\"ack_meta\":%0b,\"ack_sync\":%0b,\"seq_pad\":%0d,\"m_p\":\"%0h\",\"m_cnt\":%0d,\"m_res\":\"%0h\",\"busy\":%0b,\"seq_busy\":%0b}",
             slow_edge, slow_case, $time, reset, freeze, start, $signed(a),
             a, b, mode, short_req, hold_dut.req_a, hold_dut.req_b,
             hold_dut.req_steps, hold_dut.req_tgl, hold_dut.ack_tgl,
             hold_dut.ack_meta, hold_dut.ack_sync, hold_dut.seq_pad,
             hold_dut.m_p, hold_dut.m_cnt, hold_res, hold_busy,
             hold_seq_busy);
      #1;
      $display("PSGTRACE {\"schema\":\"psg_edge_v1\",\"svc\":\"mul\",\"domain\":\"slow\",\"phase\":\"post\",\"edge\":%0d,\"bench_case\":%0d,\"time\":%0t,\"reset\":%0b,\"freeze\":%0b,\"start\":%0b,\"a_signed\":%0d,\"a_raw\":\"%0h\",\"b\":%0d,\"mode\":%0d,\"short\":%0b,\"req_a\":\"%0h\",\"req_b\":\"%0h\",\"req_steps\":%0d,\"req_tgl\":%0b,\"ack_tgl\":%0b,\"ack_meta\":%0b,\"ack_sync\":%0b,\"seq_pad\":%0d,\"m_p\":\"%0h\",\"m_cnt\":%0d,\"m_res\":\"%0h\",\"busy\":%0b,\"seq_busy\":%0b}",
             slow_edge, slow_case, $time, reset, freeze, start, $signed(a),
             a, b, mode, short_req, hold_dut.req_a, hold_dut.req_b,
             hold_dut.req_steps, hold_dut.req_tgl, hold_dut.ack_tgl,
             hold_dut.ack_meta, hold_dut.ack_sync, hold_dut.seq_pad,
             hold_dut.m_p, hold_dut.m_cnt, hold_res, hold_busy,
             hold_seq_busy);
      slow_edge++;
    end else begin
      trace_active = 1'b0;
    end
  end

  always @(posedge fastclk) begin
    if (edge_trace && trace_active) begin
      $display("PSGTRACE {\"schema\":\"psg_edge_v1\",\"svc\":\"mul\",\"domain\":\"fast\",\"phase\":\"pre\",\"edge\":%0d,\"bench_case\":%0d,\"time\":%0t,\"slow_edge\":%0d,\"subedge\":%0d,\"reset\":%0b,\"freeze\":%0b,\"start\":%0b,\"a_signed\":%0d,\"a_raw\":\"%0h\",\"b\":%0d,\"mode\":%0d,\"short\":%0b,\"req_a\":\"%0h\",\"req_b\":\"%0h\",\"req_steps\":%0d,\"req_tgl\":%0b,\"req_meta\":%0b,\"req_sync\":%0b,\"ack_tgl\":%0b,\"m_p\":\"%0h\",\"m_cnt\":%0d,\"busy\":%0b,\"seq_busy\":%0b}",
             fast_edge, slow_case, $time, slow_edge - 1, fast_subedge, reset,
             freeze, start, $signed(a), a, b, mode, short_req,
             hold_dut.req_a, hold_dut.req_b, hold_dut.req_steps,
             hold_dut.req_tgl, hold_dut.req_meta, hold_dut.req_sync,
             hold_dut.ack_tgl, hold_dut.m_p, hold_dut.m_cnt, hold_busy,
             hold_seq_busy);
      #1;
      $display("PSGTRACE {\"schema\":\"psg_edge_v1\",\"svc\":\"mul\",\"domain\":\"fast\",\"phase\":\"post\",\"edge\":%0d,\"bench_case\":%0d,\"time\":%0t,\"slow_edge\":%0d,\"subedge\":%0d,\"reset\":%0b,\"freeze\":%0b,\"start\":%0b,\"a_signed\":%0d,\"a_raw\":\"%0h\",\"b\":%0d,\"mode\":%0d,\"short\":%0b,\"req_a\":\"%0h\",\"req_b\":\"%0h\",\"req_steps\":%0d,\"req_tgl\":%0b,\"req_meta\":%0b,\"req_sync\":%0b,\"ack_tgl\":%0b,\"m_p\":\"%0h\",\"m_cnt\":%0d,\"busy\":%0b,\"seq_busy\":%0b}",
             fast_edge, slow_case, $time, slow_edge - 1, fast_subedge, reset,
             freeze, start, $signed(a), a, b, mode, short_req,
             hold_dut.req_a, hold_dut.req_b, hold_dut.req_steps,
             hold_dut.req_tgl, hold_dut.req_meta, hold_dut.req_sync,
             hold_dut.ack_tgl, hold_dut.m_p, hold_dut.m_cnt, hold_busy,
             hold_seq_busy);
      fast_edge++;
    end
    fast_subedge++;
  end

  always @(negedge clk) begin
    if (!reset) begin
      if (r2_seq_busy !== ref_busy) begin
        $error("radix-2 padded busy differs: reference=%0b multi-pumped=%0b",
               ref_busy, r2_seq_busy);
        errors++;
      end
      if (r4_seq_busy !== ref_busy) begin
        $error("radix-4 padded busy differs: reference=%0b multi-pumped=%0b",
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
      if (hold_res !== ref_res) begin
        $error("enabled-core mismatch A=%0d B=%0d mode=%0d short=%0b got=%h ref=%h",
               av, bv, mv, sv, hold_res, ref_res);
        errors++;
      end
      cases++;
    end
  endtask

  task automatic check_frozen_state;
    logic [17:0] saved_req_a;
    logic [12:0] saved_req_b;
    logic [3:0] saved_req_steps;
    logic saved_req_tgl, saved_ack_tgl;
    logic saved_ack_meta, saved_ack_sync, saved_req_meta, saved_req_sync;
    logic [2:0] saved_seq_pad;
    logic [33:0] saved_m_p;
    logic [3:0] saved_m_cnt;
    logic saved_busy, saved_seq_busy;
    begin
      saved_req_a = hold_dut.req_a;
      saved_req_b = hold_dut.req_b;
      saved_req_steps = hold_dut.req_steps;
      saved_req_tgl = hold_dut.req_tgl;
      saved_ack_tgl = hold_dut.ack_tgl;
      saved_ack_meta = hold_dut.ack_meta;
      saved_ack_sync = hold_dut.ack_sync;
      saved_req_meta = hold_dut.req_meta;
      saved_req_sync = hold_dut.req_sync;
      saved_seq_pad = hold_dut.seq_pad;
      saved_m_p = hold_dut.m_p;
      saved_m_cnt = hold_dut.m_cnt;
      saved_busy = hold_busy;
      saved_seq_busy = hold_seq_busy;
      repeat (18) begin
        @(posedge fastclk);
        #1;
        if (hold_dut.req_a !== saved_req_a
            || hold_dut.req_b !== saved_req_b
            || hold_dut.req_steps !== saved_req_steps
            || hold_dut.req_tgl !== saved_req_tgl
            || hold_dut.ack_tgl !== saved_ack_tgl
            || hold_dut.ack_meta !== saved_ack_meta
            || hold_dut.ack_sync !== saved_ack_sync
            || hold_dut.req_meta !== saved_req_meta
            || hold_dut.req_sync !== saved_req_sync
            || hold_dut.seq_pad !== saved_seq_pad
            || hold_dut.m_p !== saved_m_p || hold_dut.m_cnt !== saved_m_cnt
            || hold_busy !== saved_busy || hold_seq_busy !== saved_seq_busy)
          $fatal(1, "multi-pumped transaction aged during freeze");
      end
    end
  endtask

  task automatic run_freeze_case(input int target_count,
                                 input logic freeze_ack_crossing);
    logic signed [17:0] av;
    logic [11:0] bv;
    logic [33:0] expected;
    begin
      trace_case = freeze_ack_crossing ? 209 : 200 + target_count;
      av = -18'sd123457;
      bv = 12'd253;
      expected = 34'((18'(-av) * bv) << 4);
      @(negedge clk);
      a = {{7{av[17]}}, av};
      b = bv;
      mode = 2'd0;
      short_req = 1'b0;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
      if (freeze_ack_crossing)
        wait (hold_dut.m_cnt == 0
              && hold_dut.ack_tgl != hold_dut.ack_sync);
      else
        wait (hold_dut.m_cnt == 4'(target_count));
      @(negedge fastclk);
      #1;
      freeze = 1'b1;
      check_frozen_state();
      @(negedge fastclk);
      #1;
      freeze = 1'b0;
      wait (!hold_busy);
      @(negedge clk);
      if (hold_res !== expected)
        $fatal(1, "held multiplier result mismatch count=%0d ack=%0b got=%h expected=%h",
               target_count, freeze_ack_crossing, hold_res, expected);
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

    if (edge_trace) begin
      // Remove the random sweep's final state from the trace boundary.  This
      // preamble is untraced and leaves every retained field deterministic.
      run_case(18'sd0, 12'd0, 2'd0, 1'b0);
      trace_enable = 1'b1;
      for (int mv = 0; mv < 4; mv++) begin
        trace_case = 100 + mv;
        run_case(-18'sd12345, legal_b(mv[1:0], 1'b0,
                                     32'h35a5_17c3), mv[1:0], 1'b0);
      end
      trace_case = 104;
      run_case(18'sd23456, 12'd63, 2'd1, 1'b1);
    end

    if (edge_trace) trace_enable = 1'b1;
    for (int target = 8; target > 0; target--)
      run_freeze_case(target, 1'b0);
    run_freeze_case(0, 1'b1);
    if (edge_trace) begin
      trace_enable = 1'b0;
      wait (!trace_active);
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
