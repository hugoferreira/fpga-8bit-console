`timescale 1ns/1ps

module psg_execctl_tb;
  bit clk;
  bit reset = 1;
  logic start, start_owner, hold;
  logic [7:0] start_pc;
  logic [15:0] cond;
  logic [15:0] state_q;
  wire [15:0] state_wd_i = state_q;
  logic state_ra_override_i;
  logic [5:0] state_ra_word_i;
  logic state_we_i;
  logic [5:0] state_wa_word_i;
  logic active, done, owner, state_re, state_we;
  logic [2:0] slot;
  logic [8:0] state_ra, state_wa;
  logic [15:0] state_wd, ir;
  logic [6:0] action;
  logic [5:0] state_word;
  logic [2:0] op_dbg;
  logic [7:0] pc;

  always #5 clk = ~clk;

  psg_execctl #(.TEST_PROGRAM(1)) dut(.*,
    .pc_dbg(pc), .ir_dbg(ir));

  task automatic step;
    @(posedge clk); #1;
  endtask

  task automatic launch(input logic [7:0] entry,
                        input logic initial_owner);
    start_pc = entry;
    start_owner = initial_owner;
    start = 1'b1;
    step();
    start = 1'b0;
  endtask

  initial begin
    clk = 0;
    start = 0;
    start_owner = 0;
    start_pc = 0;
    hold = 0;
    cond = 0;
    state_q = 16'h5a3c;
    state_ra_override_i = 1'b0;
    state_ra_word_i = 6'd0;
    state_we_i = 1'b0;
    state_wa_word_i = 6'd0;
    step();
    reset = 0;

    // READ 34 with movement overrides, WRITE the returned word to 38, take
    // branch 0 to slot=3, DONE.  The instruction metadata remains visible
    // while the addressed memory transaction is redirected.
    cond[0] = 1'b1;
    state_ra_override_i = 1'b1;
    state_ra_word_i = 6'd49;
    state_we_i = 1'b1;
    state_wa_word_i = 6'd50;
    launch(8'd0, 1'b1);
    if (!active || !owner || pc != 0 || ir != {3'd0, 7'd0, 6'd34}
        || state_ra != 9'd49 || !state_we || state_wa != 9'd50
        || state_word != 6'd34 || op_dbg != 3'd0)
      $fatal(1, "launch/redirected-read mismatch");
    state_ra_override_i = 1'b0;
    state_we_i = 1'b0;
    step();
    if (pc != 1 || ir != {3'd1, 7'd0, 6'd38}
        || !state_we || state_wa != 9'd38
        || state_wd != 16'h5a3c)
      $fatal(1, "direct state write mismatch");
    step();
    if (pc != 2 || state_we)
      $fatal(1, "branch issue mismatch");
    step();
    if (pc != 5)
      $fatal(1, "taken branch mismatch");
    step();
    if (slot != 3 || pc != 6)
      $fatal(1, "slot instruction mismatch");
    step();
    if (active || !done)
      $fatal(1, "done mismatch");

    // The false branch falls through NOP and JUMP, and hold freezes both PC
    // and all write/control effects.
    cond[0] = 1'b0;
    launch(8'd2, 1'b0);
    hold = 1'b1;
    step();
    if (pc != 2 || owner || !active || state_re || state_we
        || ir != {3'd2, 4'd0, 1'b1, 8'd5})
      $fatal(1, "hold mismatch");
    hold = 1'b0;
    step();
    if (pc != 3 || action != 7'd17 || state_word != 6'd9
        || op_dbg != 3'd7)
      $fatal(1, "untaken branch/action mismatch");
    step();
    if (pc != 4)
      $fatal(1, "execute mismatch");
    step();
    if (pc != 6)
      $fatal(1, "jump mismatch");
    step();
    if (active || !done)
      $fatal(1, "second done mismatch");

    // Owner and slot-increment formats are independently observable.
    launch(8'd8, 1'b1);
    step();
    if (owner || pc != 9 || ir != {3'd3, 9'd0, 1'b1, 3'd0})
      $fatal(1, "owner-bank transition mismatch");
    step();
    if (slot != 1 || pc != 10 || ir != {3'd6, 13'd0})
      $fatal(1, "slot increment mismatch");
    step();
    if (active || !done)
      $fatal(1, "third done mismatch");

    // The same logical PC addresses distinct instructions in the two banks.
    launch(8'd12, 1'b0);
    if (owner || pc != 12 || action != 7'd3 || state_word != 6'd12
        || op_dbg != 3'd7)
      $fatal(1, "sample-bank fetch mismatch");
    step();
    step();
    if (active || !done)
      $fatal(1, "sample-bank done mismatch");

    launch(8'd12, 1'b1);
    if (!owner || pc != 12 || action != 7'd5 || state_word != 6'd12
        || op_dbg != 3'd7)
      $fatal(1, "tick-bank fetch mismatch");
    hold = 1'b1;
    step();
    if (!owner || pc != 12 || action != 7'd5
        || ir != {3'd7, 7'd5, 6'd12})
      $fatal(1, "banked hold mismatch");
    hold = 1'b0;
    step();
    if (!owner || pc != 13 || ir != {3'd6, 13'd0})
      $fatal(1, "tick-bank release mismatch");
    step();
    if (active || !done)
      $fatal(1, "tick-bank done mismatch");

    $display("psg_execctl_tb: PASS");
    $finish;
  end
endmodule
