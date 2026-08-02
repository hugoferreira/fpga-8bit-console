`timescale 1ns/1ps
`include "psg_execctl.sv"

// Address/control-only proof adapter.  The generated action-indexed control
// byte carries fixed_commit, CAP_W51_read and a six-bit destination.  It has
// no operand, write data, sampled value, result state or PC input.
module psg_execbind_adapter(
    input  logic       active,
    input  logic       hold,
    input  logic       owner,
    input  logic [2:0] op,
    input  logic [6:0] action,
    input  logic [5:0] state_word,
    input  logic       spar_bank,
    input  logic [7:0] binding,
    output logic       fixed_commit,
    output logic [5:0] fixed_destination,
    output logic       state_ra_override,
    output logic [5:0] state_ra_word);

  localparam logic [2:0] OP_WRITE = 3'd1, OP_EXEC = 3'd7;

  logic enabled;
  always_comb begin
    enabled = active && !hold && !owner;
    fixed_commit = enabled && binding[7] && op == OP_WRITE;
    fixed_destination = fixed_commit ? binding[5:0] : 6'd0;
    state_ra_override = enabled && binding[6] && op == OP_EXEC
                        && state_word == 6'd26;
    state_ra_word = state_ra_override
                  ? (spar_bank ? 6'd30 : 6'd26) : 6'd0;
  end
endmodule


// Execute the real complete D2F candidate controller while observing only the
// generated address/control binding.  State write data remains the controller
// bench's synthetic payload and is not checked as sample semantics.
module psg_execbind_tb;
  bit clk;
  logic reset, start, start_owner, hold, spar_bank;
  logic [7:0] start_pc;
  logic [15:0] cond, state_q;

  logic active, done, owner, state_re, state_we;
  logic [2:0] slot, op;
  logic [8:0] state_ra, state_wa;
  logic [15:0] state_wd, ir;
  logic [6:0] action;
  logic [5:0] state_word;
  logic [7:0] pc;

  logic [15:0] candidate_image[0:511];
  logic [7:0] binding_map[0:127];
  logic [15:0] state_mem[0:511];
  string candidate_path, binding_path;

  logic probe;
  logic probe_active, probe_hold, probe_owner, probe_bank;
  logic [2:0] probe_op;
  logic [6:0] probe_action;
  logic [5:0] probe_word;
  wire bind_active = probe ? probe_active : active;
  wire bind_hold = probe ? probe_hold : hold;
  wire bind_owner = probe ? probe_owner : owner;
  wire [2:0] bind_op = probe ? probe_op : op;
  wire [6:0] bind_action = probe ? probe_action : action;
  wire [5:0] bind_word = probe ? probe_word : state_word;
  wire bind_bank = probe ? probe_bank : spar_bank;
  wire [7:0] binding = binding_map[bind_action];
  logic fixed_commit, state_ra_override;
  logic [5:0] fixed_destination, state_ra_word;

  bit binding_seen[0:1][0:127][0:7];
  bit binding_held[0:1][0:127];
  integer op_hist[0:1][0:7];
  integer executed[0:1];
  integer ir_checks[0:1];
  integer state_origin_checks[0:1];
  integer binding_count, commit_count, cap_count, held_count;
  integer i, j, bank_index;

  localparam logic [2:0] OP_WRITE = 3'd1, OP_EXEC = 3'd7;

  always #5 clk = ~clk;

  always_comb begin
    cond = 16'd0;
    cond[8] = slot == 3'd0;
  end

  psg_execctl u_ctl(
    .clk(clk), .reset(reset), .start(start), .start_owner(start_owner),
    .start_pc(start_pc), .hold(hold), .cond(cond),
    .state_wd_i({slot, action, pc[5:0]}),
    .state_ra_override_i(state_ra_override),
    .state_ra_word_i(state_ra_word),
    .state_we_i(fixed_commit),
    .state_wa_word_i(fixed_destination),
    .active(active), .done(done), .owner(owner), .slot(slot),
    .state_re(state_re), .state_ra(state_ra), .state_we(state_we),
    .state_wa(state_wa), .state_wd(state_wd), .action(action),
    .state_word(state_word), .op_dbg(op), .pc_dbg(pc), .ir_dbg(ir));

  psg_execbind_adapter u_bind(
    .active(bind_active), .hold(bind_hold), .owner(bind_owner),
    .op(bind_op), .action(bind_action), .state_word(bind_word),
    .spar_bank(bind_bank), .binding(binding),
    .fixed_commit(fixed_commit),
    .fixed_destination(fixed_destination),
    .state_ra_override(state_ra_override), .state_ra_word(state_ra_word));

  always_ff @(posedge clk) begin
    if (reset)
      state_q <= 16'd0;
    else if (state_re)
      state_q <= state_mem[state_ra];
    if (state_we)
      state_mem[state_wa] <= state_wd;
  end

  task automatic step_and_check_origin(input integer run_bank);
    logic pre_re;
    logic [8:0] pre_ra;
    logic [15:0] pre_data;
    begin
      #0;
      pre_re = state_re;
      pre_ra = state_ra;
      pre_data = state_mem[state_ra];
      @(posedge clk);
      #1;
      if (pre_re) begin
        if (state_q !== pre_data)
          $fatal(1,
            "state-q origin mismatch bank=%0d addr=%0d got=%04x want=%04x",
            run_bank, pre_ra, state_q, pre_data);
        state_origin_checks[run_bank] = state_origin_checks[run_bank] + 1;
      end
    end
  endtask

  task automatic check_live_binding(input integer run_bank);
    logic [7:0] control;
    begin
      control = binding_map[action];
      if (control[7]) begin
        if (!fixed_commit || op != OP_WRITE
            || fixed_destination != control[5:0])
          $fatal(1,
            "fixed binding mismatch bank=%0d slot=%0d pc=%02x action=%02x got=%0b/%0d want=%0d",
            run_bank, slot, pc, action, fixed_commit, fixed_destination,
            control[5:0]);
        if (!state_we || state_wa != {slot, control[5:0]})
          $fatal(1,
            "fixed write transaction mismatch bank=%0d slot=%0d pc=%02x action=%02x wa=%0d",
            run_bank, slot, pc, action, state_wa);
        binding_seen[run_bank][action][slot] = 1'b1;
      end else if (fixed_commit) begin
        $fatal(1, "unbound action committed bank=%0d pc=%02x action=%02x",
               run_bank, pc, action);
      end else if (fixed_destination != 6'd0) begin
        $fatal(1, "inert action exposed destination bank=%0d pc=%02x action=%02x",
               run_bank, pc, action);
      end
      if (control[6]) begin
        if (!state_ra_override
            || state_ra_word != (run_bank[0] ? 6'd30 : 6'd26)
            || op != OP_EXEC || state_word != 6'd26)
          $fatal(1,
            "CAP_W51 remap mismatch bank=%0d slot=%0d pc=%02x got=%0b/%0d",
            run_bank, slot, pc, state_ra_override, state_ra_word);
        binding_seen[run_bank][action][slot] = 1'b1;
      end else if (state_ra_override) begin
        $fatal(1, "unbound action overrode read bank=%0d pc=%02x action=%02x",
               run_bank, pc, action);
      end else if (state_ra_word != 6'd0) begin
        $fatal(1, "inert action exposed read word bank=%0d pc=%02x action=%02x",
               run_bank, pc, action);
      end
    end
  endtask

  task automatic hold_live_binding(input integer run_bank);
    logic stable_active, stable_owner;
    logic [2:0] stable_slot;
    logic [7:0] stable_pc;
    logic [15:0] stable_ir, stable_q;
    logic [6:0] stable_action;
    begin
      stable_active = active;
      stable_owner = owner;
      stable_slot = slot;
      stable_pc = pc;
      stable_ir = ir;
      stable_q = state_q;
      stable_action = action;
      hold = 1'b1;
      #1;
      if (fixed_commit || fixed_destination != 6'd0
          || state_ra_override || state_ra_word != 6'd0)
        $fatal(1, "binding output remained active at hold entry action=%02x",
               stable_action);
      repeat (3) begin
        step_and_check_origin(run_bank);
        if (active !== stable_active || owner !== stable_owner
            || slot !== stable_slot || pc !== stable_pc || ir !== stable_ir
            || state_q !== stable_q || action !== stable_action
            || state_re || state_we || fixed_commit
            || fixed_destination != 6'd0 || state_ra_override
            || state_ra_word != 6'd0
            || u_ctl.ucode_ce)
          $fatal(1, "held binding drift bank=%0d action=%02x",
                 run_bank, stable_action);
      end
      hold = 1'b0;
      #1;
      check_live_binding(run_bank);
      binding_held[run_bank][stable_action] = 1'b1;
      held_count = held_count + 1;
    end
  endtask

  task automatic run_candidate(input integer run_bank);
    integer guard;
    begin
      spar_bank = run_bank[0];
      reset = 1'b1;
      start = 1'b0;
      hold = 1'b0;
      repeat (2) step_and_check_origin(run_bank);
      reset = 1'b0;
      start = 1'b1;
      step_and_check_origin(run_bank);
      start = 1'b0;
      guard = 0;
      while (active && guard < 2000) begin
        if (ir !== candidate_image[{1'b0, pc}])
          $fatal(1,
            "candidate fetch mismatch bank=%0d slot=%0d pc=%02x got=%04x want=%04x",
            run_bank, slot, pc, ir, candidate_image[{1'b0, pc}]);
        ir_checks[run_bank] = ir_checks[run_bank] + 1;
        check_live_binding(run_bank);
        if (binding_map[action] != 8'd0
            && !binding_held[run_bank][action])
          hold_live_binding(run_bank);
        op_hist[run_bank][op] = op_hist[run_bank][op] + 1;
        executed[run_bank] = executed[run_bank] + 1;
        guard = guard + 1;
        step_and_check_origin(run_bank);
      end
      if (guard >= 2000 || active || !done)
        $fatal(1, "candidate did not terminate bank=%0d", run_bank);
      if (executed[run_bank] != 782 || ir_checks[run_bank] != 782
          || state_origin_checks[run_bank] != 782)
        $fatal(1, "candidate totals bank=%0d exec/ir/q=%0d/%0d/%0d",
               run_bank, executed[run_bank], ir_checks[run_bank],
               state_origin_checks[run_bank]);
      if (op_hist[run_bank][0] != 172 || op_hist[run_bank][1] != 158
          || op_hist[run_bank][2] != 8 || op_hist[run_bank][3] != 29
          || op_hist[run_bank][4] != 8 || op_hist[run_bank][5] != 0
          || op_hist[run_bank][6] != 1 || op_hist[run_bank][7] != 406)
        $fatal(1, "candidate histogram changed bank=%0d", run_bank);
      step_and_check_origin(run_bank);
      if (done)
        $fatal(1, "done did not pulse for one cycle bank=%0d", run_bank);
    end
  endtask

  task automatic probe_inert_and_op_qualification;
    logic [2:0] correct_op, wrong_op;
    begin
      probe = 1'b1;
      probe_active = 1'b1;
      probe_hold = 1'b0;
      probe_owner = 1'b0;
      probe_bank = 1'b0;
      probe_word = 6'd26;
      for (int code = 0; code < 128; code++) begin
        probe_action = 7'(code);
        correct_op = binding_map[code][6] ? OP_EXEC : OP_WRITE;
        wrong_op = (correct_op == OP_EXEC) ? OP_WRITE : OP_EXEC;
        probe_op = wrong_op;
        #1;
        if (fixed_commit || fixed_destination != 6'd0
            || state_ra_override || state_ra_word != 6'd0)
          $fatal(1, "wrong op activated binding action=%02x", code);
        probe_op = correct_op;
        #1;
        if (fixed_commit !== binding_map[code][7]
            || fixed_destination !== (binding_map[code][7]
                                      ? binding_map[code][5:0] : 6'd0)
            || state_ra_override !== binding_map[code][6]
            || state_ra_word !== (binding_map[code][6] ? 6'd26 : 6'd0))
          $fatal(1, "control-map decode mismatch action=%02x", code);
        probe_hold = 1'b1;
        #1;
        if (fixed_commit || fixed_destination != 6'd0
            || state_ra_override || state_ra_word != 6'd0)
          $fatal(1, "held probe activated action=%02x", code);
        probe_hold = 1'b0;
        probe_owner = 1'b1;
        #1;
        if (fixed_commit || fixed_destination != 6'd0
            || state_ra_override || state_ra_word != 6'd0)
          $fatal(1, "owner-one probe activated action=%02x", code);
        probe_owner = 1'b0;
        probe_active = 1'b0;
        #1;
        if (fixed_commit || fixed_destination != 6'd0
            || state_ra_override || state_ra_word != 6'd0)
          $fatal(1, "inactive probe activated action=%02x", code);
        probe_active = 1'b1;
      end
      // The one CAP_W51 flag is additionally qualified by literal word 26.
      for (int code = 0; code < 128; code++) if (binding_map[code][6]) begin
        probe_action = 7'(code);
        probe_op = OP_EXEC;
        probe_word = 6'd25;
        #1;
        if (state_ra_override)
          $fatal(1, "CAP_W51 accepted a non-26 instruction word");
        probe_word = 6'd26;
        probe_bank = 1'b1;
        #1;
        if (!state_ra_override || state_ra_word != 6'd30)
          $fatal(1, "CAP_W51 bank-one probe did not select word 30");
      end
      probe = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    start = 1'b0;
    start_owner = 1'b0;
    start_pc = 8'h01;
    hold = 1'b0;
    spar_bank = 1'b0;
    probe = 1'b0;
    binding_count = 0;
    commit_count = 0;
    cap_count = 0;
    held_count = 0;
    if (!$value$plusargs("PSG_EXEC_CANDIDATE=%s", candidate_path))
      $fatal(1, "missing +PSG_EXEC_CANDIDATE=<complete-512-word-image>");
    if (!$value$plusargs("PSG_EXEC_BIND_CONTROL=%s", binding_path))
      $fatal(1, "missing +PSG_EXEC_BIND_CONTROL=<128-word-control-map>");
    $readmemh(candidate_path, candidate_image);
    $readmemh(binding_path, binding_map);
    for (i = 0; i < 512; i++)
      state_mem[i] = 16'h6c00 ^ 16'(i);
    for (i = 0; i < 128; i++) begin
      binding_count = binding_count + (binding_map[i] != 8'd0);
      commit_count = commit_count + binding_map[i][7];
      cap_count = cap_count + binding_map[i][6];
      if (binding_map[i][7]
          && !(i[6:4] == 3'd2 || i[6:4] == 3'd3 || i[6:4] == 3'd4))
        $fatal(1, "fixed commit has unsupported action family action=%02x", i);
      for (j = 0; j < 8; j++) begin
        binding_seen[0][i][j] = 1'b0;
        binding_seen[1][i][j] = 1'b0;
      end
      binding_held[0][i] = 1'b0;
      binding_held[1][i] = 1'b0;
    end
    if (binding_count != 19 || commit_count != 18 || cap_count != 1)
      $fatal(1, "binding map topology got total/commit/cap=%0d/%0d/%0d",
             binding_count, commit_count, cap_count);
    for (bank_index = 0; bank_index < 2; bank_index++) begin
      executed[bank_index] = 0;
      ir_checks[bank_index] = 0;
      state_origin_checks[bank_index] = 0;
      for (i = 0; i < 8; i++) op_hist[bank_index][i] = 0;
    end

    // Replace the controller's time-zero accepted image before its first edge.
    #1;
    $readmemh(candidate_path, u_ctl.ucode);
    #1;
    for (i = 0; i < 512; i++)
      if (u_ctl.ucode[i] !== candidate_image[i])
        $fatal(1, "candidate load mismatch at word %0d", i);

    run_candidate(0);
    run_candidate(1);
    for (bank_index = 0; bank_index < 2; bank_index++)
      for (i = 0; i < 128; i++) if (binding_map[i] != 8'd0) begin
        if (!binding_held[bank_index][i])
          $fatal(1, "binding action %02x not held in bank %0d", i, bank_index);
        for (j = 0; j < 8; j++)
          if (!binding_seen[bank_index][i][j])
            $fatal(1, "binding action %02x unseen bank=%0d slot=%0d",
                   i, bank_index, j);
      end
    if (held_count != 38)
      $fatal(1, "held binding total got=%0d expected=38", held_count);
    probe_inert_and_op_qualification();

    $display("psg_execbind_tb: PASS (128 actions, 18 fixed commits + CAP_W51, 2 banks x 8 slots, 38 held bindings, 1564 fetch/state origins)");
    $finish;
  end
endmodule
