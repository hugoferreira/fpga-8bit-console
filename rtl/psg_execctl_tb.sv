`timescale 1ns/1ps

module psg_execctl_tb;
  bit clk;
  bit reset = 1;
  logic start, start_owner, hold;
  logic [7:0] start_pc;
  logic [3:0] cond;
  logic [15:0] state_q;
  logic active, done, owner, state_we;
  logic [2:0] slot;
  logic [8:0] state_ra, state_wa;
  logic [15:0] state_wd, ir;
  logic [7:0] pc;

  always #5 clk = ~clk;

  psg_execctl dut(.*,
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
    step();
    reset = 0;

    // READ 34, WRITE the returned word to 38, take branch 0 to slot=3, DONE.
    cond[0] = 1'b1;
    launch(8'd0, 1'b1);
    if (!active || !owner || pc != 0 || ir != {3'd0, 7'd0, 6'd34}
        || state_ra != 9'd34)
      $fatal(1, "launch/read mismatch");
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
    if (pc != 2 || !active || state_we)
      $fatal(1, "hold mismatch");
    hold = 1'b0;
    step();
    if (pc != 3)
      $fatal(1, "untaken branch mismatch");
    step();
    if (pc != 4)
      $fatal(1, "nop mismatch");
    step();
    if (pc != 6)
      $fatal(1, "jump mismatch");
    step();
    if (active || !done)
      $fatal(1, "second done mismatch");

    // Owner and slot-increment formats are independently observable.
    launch(8'd8, 1'b1);
    step();
    if (owner || pc != 9)
      $fatal(1, "owner instruction mismatch");
    step();
    if (slot != 1 || pc != 10)
      $fatal(1, "slot increment mismatch");
    step();
    if (active || !done)
      $fatal(1, "third done mismatch");

    $display("psg_execctl_tb: PASS");
    $finish;
  end
endmodule
