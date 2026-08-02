`timescale 1ns/1ps
`include "psg_execctl.sv"
`include "psg_execdp.sv"
`include "psg_execmove.sv"

// Production-image synchronous transaction proof for R.84G-F.  This is not
// a combinational action test: state_q advances only on memory clock edges and
// every fixed read override/write shares the controller's real one-port issue
// sequence.
module psg_execadv_tb;
  bit clk;
  bit reset;
  logic start, start_owner, hold;
  logic [7:0] start_pc;
  logic spar_bank, join_stage, trig_req, walk_tick, playing, ins_use;
  logic released, cpz;
  logic boundary_on_stop;

  logic active, done, owner, state_we;
  logic [2:0] slot, op;
  logic [8:0] state_ra, state_wa;
  logic [15:0] state_wd, ir;
  logic [6:0] action;
  logic [5:0] state_word;
  logic [7:0] pc;

  logic [15:0] state_q;
  logic [15:0] state_wd_dp, state_wd_fixed, state_wd_mux;
  logic [15:0] cond, acc;
  logic [3:0] flags, cond_adv;
  logic state_ra_override, state_we_extra, state_wd_override;
  logic [5:0] state_ra_word, state_wa_word;
  logic voice_stop, cpz_we, cpz_next;
  logic pend_stop;
  logic [15:0] mem[0:511];

  localparam logic [7:0]
    PC_V_LD0 = 8'h87,
    PC_T_FL  = 8'hcb,
    PC_EA0   = 8'h97,
    PC_ES0   = 8'h68,
    PC_K_NL  = 8'h44,
    PC_K_ROT = 8'h85,
    PC_I_NL  = 8'h81;

  always #5 clk = ~clk;

  psg_execdp u_dp(
    .clk(clk), .reset(reset), .active(active), .hold(hold), .op(op),
    .action(action), .state_q(state_q), .cond_ext({4'd0, cond_adv}),
    .state_wd(state_wd_dp), .cond(cond), .acc_dbg(acc), .flags_dbg(flags));

  psg_execmove u_move(
    .active(active), .hold(hold), .owner(owner), .op(op), .action(action),
    .state_word(state_word), .state_q(state_q), .acc(acc),
    .spar_bank(spar_bank), .join_stage(join_stage), .trig_req(trig_req),
    .walk_tick(walk_tick), .playing(playing), .ins_use(ins_use),
    .released(released), .cpz(cpz),
    .state_ra_override(state_ra_override), .state_ra_word(state_ra_word),
    .state_we_extra(state_we_extra), .state_wa_word(state_wa_word),
    .state_wd_override(state_wd_override), .state_wd_fixed(state_wd_fixed),
    .cond_adv(cond_adv), .voice_stop(voice_stop), .cpz_we(cpz_we),
    .cpz_next(cpz_next));

  always_comb state_wd_mux = state_wd_override ? state_wd_fixed : state_wd_dp;

  psg_execctl u_ctl(
    .clk(clk), .reset(reset), .start(start), .start_owner(start_owner),
    .start_pc(start_pc), .hold(hold), .cond(cond),
    .state_wd_i(state_wd_mux), .state_ra_override_i(state_ra_override),
    .state_ra_word_i(state_ra_word), .state_we_i(state_we_extra),
    .state_wa_word_i(state_wa_word), .active(active), .done(done),
    .owner(owner), .slot(slot), .state_ra(state_ra), .state_we(state_we),
    .state_wa(state_wa), .state_wd(state_wd), .action(action),
    .state_word(state_word), .op_dbg(op), .pc_dbg(pc), .ir_dbg(ir));

  // Same-edge ordering matches the existing psg_seq always_ff: the boundary
  // clear occurs first, then an executing VOICE_STOP sets pend_stop again.
  // playing therefore consumes the pre-edge pending bit.
  always_ff @(posedge clk) begin
    if (state_we)
      mem[state_wa] <= state_wd;
    state_q <= mem[state_ra];

    if (reset) begin
      pend_stop <= 1'b0;
      cpz <= 1'b0;
    end else begin
      if (boundary_on_stop && voice_stop) begin
        if (pend_stop)
          playing <= 1'b0;
        pend_stop <= 1'b0;
      end
      if (voice_stop)
        pend_stop <= 1'b1;
      if (cpz_we)
        cpz <= cpz_next;
    end
  end

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  task automatic reset_case;
    reset = 1'b1;
    start = 1'b0;
    start_owner = 1'b1;
    start_pc = PC_V_LD0;
    hold = 1'b0;
    spar_bank = 1'b0;
    join_stage = 1'b0;
    trig_req = 1'b0;
    walk_tick = 1'b1;
    playing = 1'b1;
    ins_use = 1'b0;
    released = 1'b0;
    boundary_on_stop = 1'b0;
    for (int n = 0; n < 512; n++)
      mem[n] = 16'd0;
    // Stable unrelated bits make preservation bugs observable.
    mem[3] = 16'ha53c;
    mem[4] = 16'h4a15;
    mem[5] = 16'ha321;
    mem[9] = 16'h1000;
    mem[26] = 16'h2611;
    mem[30] = 16'h30ee;
    mem[32] = 16'hc000;
    step();
    step();
    reset = 1'b0;
  endtask

  task automatic launch;
    start = 1'b1;
    step();
    start = 1'b0;
  endtask

  task automatic run_to(input logic [7:0] target,
                        input int limit);
    int cycles;
    cycles = 0;
    while (!(active && pc == target) && cycles < limit) begin
      step();
      cycles++;
    end
    if (!(active && pc == target))
      $fatal(1, "transaction missed pc=%h target=%h active=%b", pc,
             target, active);
  endtask

  task automatic set_voice(input logic [7:0] tcnt,
                           input logic [7:0] fcnt,
                           input logic [7:0] speed,
                           input logic [5:0] length,
                           input logic [7:0] lps,
                           input logic [7:0] lpe,
                           input logic [4:0] row);
    mem[0] = {tcnt, fcnt};
    mem[1] = {lpe, lps};
    mem[2] = {2'b0, length, speed};
    mem[32] = {11'h5a5, row};
  endtask

  task automatic set_instrument(input logic [7:0] tcnt,
                                input logic [7:0] fcnt,
                                input logic [7:0] speed,
                                input logic [7:0] lps,
                                input logic [7:0] lpe,
                                input logic [4:0] row,
                                input logic [5:0] pitch,
                                input logic [2:0] volume);
    mem[6] = {tcnt, fcnt};
    mem[7] = {lpe, lps};
    mem[8] = {2'b0, pitch, speed};
    mem[5][9:5] = row;
    mem[5][15:13] = volume;
    mem[9][13:12] = 2'b01; // on, not wavetable => ins_use
    ins_use = 1'b1;
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;

    // Trigger priority precedes both skip and advance.
    reset_case();
    set_voice(5, 0, 2, 0, 0, 0, 0);
    trig_req = 1'b1;
    launch();
    run_to(PC_T_FL, 40);
    if (mem[34] != 1 || mem[35] != 32)
      $fatal(1, "trigger path missed normalization constants");

    // Skip samples pre-edge playing and emits cpz without changing counters.
    reset_case();
    set_voice(5, 0, 2, 0, 0, 0, 0);
    walk_tick = 1'b0;
    playing = 1'b0;
    launch();
    run_to(PC_K_ROT, 40);
    if (!cpz || mem[0] != 16'h0500)
      $fatal(1, "skip path mismatch cpz=%b ctr=%h", cpz, mem[0]);

    // Voice no-roll, with and without instrument dispatch.
    reset_case();
    set_voice(5, 0, 2, 0, 0, 0, 0);
    launch();
    run_to(PC_ES0, 80);
    if (mem[0] != 16'h0601 || mem[53] != 16'h2611)
      $fatal(1, "voice no-roll mismatch ctr=%h par=%h", mem[0], mem[53]);

    reset_case();
    spar_bank = 1'b1;
    set_voice(5, 0, 2, 0, 0, 0, 0);
    set_instrument(3, 0, 2, 0, 0, 0, 6'd37, 3'd5);
    launch();
    run_to(PC_I_NL, 120);
    if (mem[0] != 16'h0601 || mem[6] != 16'h0401
        || mem[53] != 16'h30ee)
      $fatal(1, "instrument no-roll/bank-one mismatch %h/%h/%h",
             mem[0], mem[6], mem[53]);

    // Foreground length has priority over loop/end; rollover also updates the
    // raw previous-pitch/volume working words.
    reset_case();
    set_voice(5, 1, 2, 2, 1, 4, 4);
    launch();
    run_to(PC_K_NL, 140);
    if (mem[0] != 16'h0600 || mem[2][13:8] != 6'd1
        || mem[54][4:0] != 5'd5
        || mem[48][11:6] != mem[48][5:0]
        || mem[49][8:6] != mem[49][2:0])
      $fatal(1, "voice length advance mismatch");

    // Length one stops.  A simultaneous boundary clear must lose to the new
    // stop set, while playing observes the old pending bit.
    reset_case();
    set_voice(5, 1, 2, 1, 1, 4, 4);
    boundary_on_stop = 1'b1;
    launch();
    run_to(PC_K_ROT, 140);
    if (!pend_stop || !cpz || !playing)
      $fatal(1, "same-edge stop priority mismatch pend=%b cpz=%b play=%b",
             pend_stop, cpz, playing);

    // Loop-before-end, released-loop suppression, and ordinary row advance.
    reset_case();
    set_voice(5, 1, 2, 0, 1, 4, 3);
    launch();
    run_to(PC_K_NL, 160);
    if (mem[54][4:0] != 5'd1)
      $fatal(1, "voice loop mismatch row=%0d", mem[54][4:0]);

    reset_case();
    set_voice(5, 1, 2, 0, 1, 4, 1);
    launch();
    run_to(PC_K_NL, 160);
    if (mem[54][4:0] != 5'd2)
      $fatal(1, "voice ordinary row mismatch row=%0d", mem[54][4:0]);

    reset_case();
    set_voice(5, 1, 2, 0, 1, 4, 3);
    released = 1'b1;
    launch();
    run_to(PC_K_NL, 160);
    if (mem[54][4:0] != 5'd4)
      $fatal(1, "released loop suppression mismatch row=%0d", mem[54][4:0]);

    // Instrument rollover updates word-9 previous fields and its independent
    // row layout; invalid/end path sets word-4's done bit.
    reset_case();
    set_voice(5, 0, 2, 0, 0, 0, 0);
    set_instrument(3, 1, 2, 1, 4, 1, 6'd37, 3'd5);
    launch();
    run_to(PC_I_NL, 180);
    if (mem[6] != 16'h0400 || mem[50][9:5] != 5'd2
        || mem[52][5:0] != 6'd37 || mem[52][11:9] != 3'd5)
      $fatal(1, "instrument rollover/previous-field mismatch");

    reset_case();
    set_voice(5, 0, 2, 0, 0, 0, 0);
    set_instrument(3, 1, 2, 4, 4, 31, 6'd37, 3'd5);
    launch();
    run_to(PC_I_NL, 180);
    if (!mem[49][15])
      $fatal(1, "instrument done bit not set");

    $display("psg_execadv_tb: PASS (11 production-image synchronous paths)");
    $finish;
  end
endmodule
