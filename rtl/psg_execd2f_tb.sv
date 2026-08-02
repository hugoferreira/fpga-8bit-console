`timescale 1ns/1ps
`include "psg_execctl.sv"

// Candidate-only controller proof.  This bench replaces the controller's
// time-zero production image after time zero and before the first clock.  It
// deliberately supplies synthetic write data and claims no sample semantics.
module psg_execd2f_tb;
  bit clk;
  bit reset;
  logic start, start_owner, hold;
  logic [7:0] start_pc;
  logic [15:0] cond;
  logic [15:0] state_q;

  logic active, done, owner, state_re, state_we;
  logic [2:0] slot, op;
  logic [8:0] state_ra, state_wa;
  logic [15:0] state_wd, ir;
  logic [6:0] action;
  logic [5:0] state_word;
  logic [7:0] pc;

  logic [15:0] accepted_image[0:511];
  logic [15:0] candidate_image[0:511];
  logic [15:0] state_mem[0:511];
  bit changed_pc[0:255];
  bit changed_held[0:255];
  integer changed_seen[0:255][0:7];
  integer op_hist[0:7];
  integer changed_count, changed_holds, upper_changes, lower_nonzero;
  integer executed, ir_checks, state_origin_checks, cycle_guard;
  integer i, j;
  string candidate_path;

  always #5 clk = ~clk;

  always_comb begin
    cond = 16'd0;
    cond[8] = slot == 3'd0;
  end

  psg_execctl u_ctl(
    .clk(clk), .reset(reset), .start(start), .start_owner(start_owner),
    .start_pc(start_pc), .hold(hold), .cond(cond),
    .state_wd_i({slot, action, pc[5:0]}),
    .state_ra_override_i(1'b0), .state_ra_word_i(6'd0),
    .state_we_i(1'b0), .state_wa_word_i(6'd0),
    .active(active), .done(done), .owner(owner), .slot(slot),
    .state_re(state_re), .state_ra(state_ra), .state_we(state_we),
    .state_wa(state_wa), .state_wd(state_wd), .action(action),
    .state_word(state_word), .op_dbg(op), .pc_dbg(pc), .ir_dbg(ir));

  // The old-data read ordering matches the synchronous state-store contract.
  always_ff @(posedge clk) begin
    if (reset)
      state_q <= 16'd0;
    else if (state_re)
      state_q <= state_mem[state_ra];
    if (state_we)
      state_mem[state_wa] <= state_wd;
  end

  task automatic step_and_check_origin;
    logic pre_re;
    logic [8:0] pre_ra;
    logic [15:0] pre_data;
    begin
      #0;  // settle hold/start changes before sampling the pre-edge contract
      pre_re = state_re;
      pre_ra = state_ra;
      pre_data = state_mem[state_ra];
      @(posedge clk);
      #1;
      if (pre_re) begin
        if (state_q !== pre_data)
          $fatal(1, "state-q origin mismatch: addr=%0d got=%04x want=%04x",
                 pre_ra, state_q, pre_data);
        state_origin_checks = state_origin_checks + 1;
      end
    end
  endtask

  task automatic check_candidate_ir;
    begin
      if (!active || owner)
        $fatal(1, "candidate controller left owner-zero execution");
      if (ir !== candidate_image[pc])
        $fatal(1, "candidate fetch mismatch: slot=%0d pc=%02x got=%04x want=%04x",
               slot, pc, ir, candidate_image[pc]);
      ir_checks = ir_checks + 1;
    end
  endtask

  task automatic hold_changed_pc;
    logic stable_active, stable_owner;
    logic [2:0] stable_slot;
    logic [7:0] stable_pc;
    logic [15:0] stable_ir, stable_q;
    integer hold_edge;
    begin
      stable_active = active;
      stable_owner = owner;
      stable_slot = slot;
      stable_pc = pc;
      stable_ir = ir;
      stable_q = state_q;
      hold = 1'b1;
      for (hold_edge = 0; hold_edge < 3; hold_edge = hold_edge + 1) begin
        step_and_check_origin();
        if (active !== stable_active || owner !== stable_owner
            || slot !== stable_slot || pc !== stable_pc || ir !== stable_ir
            || state_q !== stable_q || state_re || state_we
            || u_ctl.ucode_ce)
          $fatal(1, "three-cycle hold drift at changed pc=%02x edge=%0d",
                 stable_pc, hold_edge);
      end
      hold = 1'b0;
      changed_held[stable_pc] = 1'b1;
      changed_holds = changed_holds + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    start = 1'b0;
    start_owner = 1'b0;
    start_pc = 8'h01;
    hold = 1'b0;
    changed_count = 0;
    changed_holds = 0;
    upper_changes = 0;
    lower_nonzero = 0;
    executed = 0;
    ir_checks = 0;
    state_origin_checks = 0;
    cycle_guard = 0;

    if (!$value$plusargs("PSG_EXEC_CANDIDATE=%s", candidate_path))
      $fatal(1, "missing +PSG_EXEC_CANDIDATE=<complete-512-word-image>");
    $readmemh("./rtl/psg_exec.hex", accepted_image);
    $readmemh(candidate_path, candidate_image);

    for (i = 0; i < 512; i = i + 1) begin
      state_mem[i] = 16'h5a00 ^ i;
      if (i < 256) begin
        changed_pc[i] = candidate_image[i] != accepted_image[i];
        changed_held[i] = 1'b0;
        changed_count = changed_count + changed_pc[i];
        lower_nonzero = lower_nonzero + (candidate_image[i] != 16'd0);
        for (j = 0; j < 8; j = j + 1)
          changed_seen[i][j] = 0;
      end else begin
        upper_changes = upper_changes
                        + (candidate_image[i] != accepted_image[i]);
      end
    end
    for (i = 0; i < 8; i = i + 1)
      op_hist[i] = 0;
    if (changed_count != 44 || upper_changes != 0 || lower_nonzero != 222)
      $fatal(1, "candidate topology mismatch: changed=%0d upper=%0d nonzero=%0d",
             changed_count, upper_changes, lower_nonzero);

    // psg_execctl has already loaded the accepted image at time zero.  This
    // is the only candidate injection seam and it runs before the first clock.
    #1;
    $readmemh(candidate_path, u_ctl.ucode);
    #1;
    for (i = 0; i < 512; i = i + 1)
      if (u_ctl.ucode[i] !== candidate_image[i])
        $fatal(1, "hierarchical candidate load mismatch at word %0d", i);

    step_and_check_origin();
    reset = 1'b0;
    start = 1'b1;
    step_and_check_origin();
    start = 1'b0;

    while (active && cycle_guard < 2000) begin
      check_candidate_ir();
      if (changed_pc[pc]) begin
        changed_seen[pc][slot] = changed_seen[pc][slot] + 1;
        if (!changed_held[pc])
          hold_changed_pc();
      end
      op_hist[op] = op_hist[op] + 1;
      executed = executed + 1;
      cycle_guard = cycle_guard + 1;
      step_and_check_origin();
    end

    if (cycle_guard >= 2000 || active || !done)
      $fatal(1, "candidate did not terminate cleanly");
    if (executed != 782 || ir_checks != 782 || state_origin_checks != 782)
      $fatal(1, "candidate totals mismatch: exec=%0d ir=%0d q=%0d",
             executed, ir_checks, state_origin_checks);
    if (op_hist[0] != 172 || op_hist[1] != 158 || op_hist[2] != 8
        || op_hist[3] != 29 || op_hist[4] != 8 || op_hist[5] != 0
        || op_hist[6] != 1 || op_hist[7] != 406)
      $fatal(1, "candidate opcode histogram mismatch: %0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d",
             op_hist[0], op_hist[1], op_hist[2], op_hist[3], op_hist[4],
             op_hist[5], op_hist[6], op_hist[7]);

    for (i = 0; i < 256; i = i + 1) begin
      if (changed_pc[i]) begin
        if (!changed_held[i])
          $fatal(1, "changed pc %02x never received its hold", i);
        for (j = 0; j < 8; j = j + 1)
          if (changed_seen[i][j] == 0)
            $fatal(1, "changed pc %02x unreachable in slot %0d", i, j);
      end
    end
    if (changed_holds != 44)
      $fatal(1, "changed-PC hold count mismatch: %0d", changed_holds);

    step_and_check_origin();
    if (done)
      $fatal(1, "done did not pulse for exactly one cycle");
    $display("psg_execd2f_tb: PASS (512 words, 44 changed PCs x 8 slots, 44 three-cycle holds, 782 fetch/state origins, histogram 172/158/8/29/8/0/1/406)");
    $finish;
  end
endmodule
