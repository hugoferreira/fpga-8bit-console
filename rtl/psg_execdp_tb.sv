`timescale 1ns/1ps
`include "psg_execdp.sv"

module psg_execdp_tb;
  bit clk;
  bit reset = 1;
  logic active;
  logic [2:0] op;
  logic [6:0] action;
  logic [15:0] state_q;
  logic [7:0] cond_ext;
  logic [15:0] state_wd, cond, acc;
  logic [3:0] flags;

  localparam logic [2:0] OP_EXEC = 3'd7;
  localparam logic [3:0]
    A_HOLD = 4'd0, A_LOAD = 4'd1, A_ADD = 4'd2, A_ADC = 4'd3,
    A_SUB  = 4'd4, A_SBC  = 4'd5, A_AND = 4'd6, A_OR  = 4'd7,
    A_XOR  = 4'd8, A_SHL  = 4'd9, A_ROL = 4'd10, A_SHR = 4'd11,
    A_ROR  = 4'd12, A_ASR = 4'd13, A_NEG = 4'd14, A_CMP = 4'd15;

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  psg_execdp dut(
    .clk(clk), .reset(reset), .active(active), .op(op), .action(action),
    .state_q(state_q), .cond_ext(cond_ext), .state_wd(state_wd),
    .cond(cond), .acc_dbg(acc), .flags_dbg(flags));

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  task automatic exec(input logic [3:0] fn, input logic [15:0] q);
    action = {3'd7, fn};
    state_q = q;
    step();
  endtask

  task automatic load(input logic [15:0] value);
    exec(A_LOAD, value);
    if (acc !== value || state_wd !== value)
      $fatal(1, "load mismatch got=%h expected=%h", acc, value);
  endtask

  task automatic set_c(input logic value);
    load(16'hffff);
    exec(A_ADD, value ? 16'h0001 : 16'h0000);
    if (flags[2] !== value)
      $fatal(1, "carry setup mismatch got=%b expected=%b", flags[2], value);
  endtask

  task automatic check_result(input logic [3:0] fn,
                              input logic [15:0] a,
                              input logic [15:0] q,
                              input logic carry_in,
                              input logic [15:0] expected,
                              input logic expected_c,
                              input logic expected_v,
                              input logic preserve_acc);
    set_c(carry_in);
    load(a); // LOAD deliberately preserves carry for multiword ADC/SBC.
    exec(fn, q);
    if ((!preserve_acc && acc !== expected)
        || (preserve_acc && acc !== a)
        || flags[0] !== (expected == 0)
        || flags[1] !== expected[15]
        || flags[2] !== expected_c
        || flags[3] !== expected_v)
      $fatal(1, "fn=%0d a=%h q=%h ci=%b got=%h f=%b expected=%h %b%b%b%b",
             fn, a, q, carry_in, acc, flags, expected, expected_v,
             expected_c, expected[15], expected == 0);
  endtask

  logic [15:0] a16, q16, expected;
  logic [16:0] wide;
  logic expected_c, expected_v;

  initial begin
    active = 1'b0;
    op = OP_EXEC;
    action = {3'd7, A_HOLD};
    state_q = 0;
    cond_ext = 8'ha5;
    repeat (2) step();
    reset = 1'b0;
    active = 1'b1;

    load(16'h1234);
    if (cond[15:8] !== 8'ha5 || cond[3:0] !== flags)
      $fatal(1, "condition map mismatch cond=%h", cond);

    // Exhaust every pair of low bytes while independently perturbing the
    // high bytes.  This crosses carry and signed-overflow boundaries in all
    // four arithmetic forms without reducing the datapath to an 8-bit proof.
    for (int ai = 0; ai < 256; ai++) begin
      for (int qi = 0; qi < 256; qi++) begin
        a16 = {8'(ai ^ 8'ha5), 8'(ai)};
        q16 = {8'(qi ^ 8'h5a), 8'(qi)};

        wide = {1'b0, a16} + {1'b0, q16};
        expected = wide[15:0];
        expected_c = wide[16];
        expected_v = ~(a16[15] ^ q16[15]) & (expected[15] ^ a16[15]);
        check_result(A_ADD, a16, q16, 1'b0, expected,
                     expected_c, expected_v, 1'b0);

        wide = {1'b0, a16} + {1'b0, q16} + 17'd1;
        expected = wide[15:0];
        expected_c = wide[16];
        expected_v = ~(a16[15] ^ q16[15]) & (expected[15] ^ a16[15]);
        check_result(A_ADC, a16, q16, 1'b1, expected,
                     expected_c, expected_v, 1'b0);

        wide = {1'b0, a16} + {1'b0, ~q16} + 17'd1;
        expected = wide[15:0];
        expected_c = wide[16];
        expected_v = (a16[15] ^ q16[15]) & (expected[15] ^ a16[15]);
        check_result(A_SUB, a16, q16, 1'b0, expected,
                     expected_c, expected_v, 1'b0);
        check_result(A_CMP, a16, q16, 1'b0, expected,
                     expected_c, expected_v, 1'b1);

        wide = {1'b0, a16} + {1'b0, ~q16};
        expected = wide[15:0];
        expected_c = wide[16];
        expected_v = (a16[15] ^ q16[15]) & (expected[15] ^ a16[15]);
        check_result(A_SBC, a16, q16, 1'b0, expected,
                     expected_c, expected_v, 1'b0);
      end
    end

    check_result(A_AND, 16'ha55a, 16'h0ff0, 1'b1, 16'h0550,
                 1'b1, 1'b0, 1'b0);
    check_result(A_OR, 16'ha55a, 16'h0ff0, 1'b0, 16'haffa,
                 1'b0, 1'b0, 1'b0);
    check_result(A_XOR, 16'ha55a, 16'h0ff0, 1'b1, 16'haaaa,
                 1'b1, 1'b0, 1'b0);
    check_result(A_SHL, 16'h8001, 0, 1'b0, 16'h0002,
                 1'b1, 1'b0, 1'b0);
    check_result(A_ROL, 16'h8001, 0, 1'b1, 16'h0003,
                 1'b1, 1'b0, 1'b0);
    check_result(A_SHR, 16'h8001, 0, 1'b0, 16'h4000,
                 1'b1, 1'b0, 1'b0);
    check_result(A_ROR, 16'h0001, 0, 1'b1, 16'h8000,
                 1'b1, 1'b0, 1'b0);
    check_result(A_ASR, 16'h8001, 0, 1'b0, 16'hc000,
                 1'b1, 1'b0, 1'b0);
    check_result(A_NEG, 16'h8000, 0, 1'b0, 16'h8000,
                 1'b1, 1'b1, 1'b0);

    load(16'h55aa);
    active = 1'b0;
    exec(A_ADD, 16'h1111);
    if (acc !== 16'h55aa)
      $fatal(1, "inactive datapath changed accumulator");
    active = 1'b1;
    op = 3'd0;
    exec(A_ADD, 16'h1111);
    if (acc !== 16'h55aa)
      $fatal(1, "non-exec instruction changed accumulator");

    $display("psg_execdp_tb: PASS (327680 arithmetic pairs)");
    $finish;
  end
endmodule
