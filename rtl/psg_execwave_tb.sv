`timescale 1ns/1ps
`include "psg_common.svh"
`include "psg_execctl.sv"
`include "psg_execmove.sv"
`include "psg_execwave.sv"
`include "psg_wave.sv"
`include "psg_aram.sv"

// Production-image proof of H-C's addressed waveform and ARAM cadence.
module psg_execwave_tb;
  bit clk;
  bit reset;
  logic start, start_owner, hold, spar_bank;
  logic [7:0] start_pc;
  logic [7:0] play_mask;

  logic active, done, owner, state_re, state_we;
  logic [2:0] slot, op;
  logic [8:0] state_ra, state_wa;
  logic [15:0] state_q, state_wd, ir;
  logic [6:0] action;
  logic [5:0] state_word;
  logic [7:0] pc;
  logic [15:0] cond;

  logic move_ra_override, move_we_extra, move_wd_override;
  logic [5:0] move_ra_word, move_wa_word;
  logic [15:0] move_wd_fixed;
  logic [3:0] cond_adv;
  logic voice_stop, cpz_we, cpz_next;
  logic wave_ra_override;
  logic [5:0] wave_ra_word;
  logic wave_ce, wave_issue, wave_take;
  logic [15:0] wave_phase;
  logic [2:0] wave_sel;
  logic wave_alt, wave_secondary;
  logic aram_req, aram_adjacent, aram_take;
  logic [2:0] aram_id;
  logic [5:0] aram_index;
  logic state_ra_override;
  logic [5:0] state_ra_word;

  logic signed [17:0] z_eval;
  logic [12:0] syn_addr;
  logic [7:0] seq_q;
  logic seq_frozen;
  localparam logic [12:0] SEQ_ADDR = 13'h055;

  logic [15:0] mem[0:511];
  logic [15:0] cur_phase[0:7];
  logic [15:0] cur_phase2[0:7];
  logic [15:0] old_phase[0:7];
  logic [15:0] old_q_value[0:7];
  logic [2:0] live_wave[0:7], prior_wave[0:7], live_id[0:7];
  logic [1:0] live_mode[0:7], prior_mode[0:7];
  logic live_alt[0:7], prior_alt[0:7], live_wt[0:7];

  integer op_count[0:7];
  integer active_edges, semantic_reads, semantic_writes;
  integer wave_issues, wave_takes, aram_issues, aram_takes;
  logic aram_pending;
  logic [12:0] aram_pending_addr;
  logic [6:0] hold_action;
  logic hold_injected;
  bit edge_trace, trace_active;
  integer trace_case, trace_edge, trace_pre_rows, trace_post_rows;
  logic [41:0] candidate_pc_seen;
  integer state_origin_checks, wave_tag_checks, aram_tag_checks;
  integer total_state_origin_checks, total_wave_tag_checks;
  integer total_aram_tag_checks;

  // Proof-only state is driven exclusively by real RTL events.  It provides
  // provenance in the trace but is not a production valid/tag interface.
  logic q_origin_valid;
  logic [8:0] q_origin_addr;
  logic [7:0] q_origin_pc;
  logic [15:0] q_origin_ir, q_origin_data;
  logic q_origin_owner;
  logic [2:0] q_origin_slot;

  logic wave_tag1_valid, wave_tag2_valid;
  logic [2:0] wave_tag1_slot, wave_tag2_slot;
  logic [7:0] wave_tag1_pc, wave_tag2_pc;
  logic [6:0] wave_tag1_action, wave_tag2_action;
  logic [15:0] wave_tag1_phase, wave_tag2_phase;
  logic [2:0] wave_tag1_sel, wave_tag2_sel;
  logic wave_tag1_alt, wave_tag2_alt;
  logic wave_tag1_secondary, wave_tag2_secondary;

  logic aram_tag_valid;
  logic [2:0] aram_tag_slot;
  logic [7:0] aram_tag_pc;
  logic [6:0] aram_tag_action;
  logic [12:0] aram_tag_addr;
  wire [37:0] adapter_context =
      {u_cadence.old_q, u_cadence.u_core.phase_index_hold,
       u_cadence.u_core.snd_id, u_cadence.u_core.snd_wt,
       u_cadence.u_core.snd_wave, u_cadence.u_core.snd_mode,
       u_cadence.u_core.snd_alt, u_cadence.old_wave,
       u_cadence.old_mode, u_cadence.old_alt};
  logic signed [17:0] expected_wave_z[0:7][0:3];

  localparam logic [2:0] OP_READ = 3'd0;
  localparam logic [6:0]
    CAP_W0 = 7'h22, CAP_W1 = 7'h23, CAP_W2 = 7'h24,
    CAP_W3 = 7'h25, CAP_W4 = 7'h26, CAP_W5 = 7'h27,
    HOLD_ACTION = 7'h70;

  always #5 clk = ~clk;

  // bench_case/edge are diagnostic coordinates only.  Causality comes from
  // the emitted RTL strobes and the explicitly labelled proof_* provenance.
  task automatic emit_edge_trace(input string phase_name);
    begin
      $display("PSGTRACE {\"schema\":\"psg_edge_v1\",\"svc\":\"execwave\",\"domain\":\"clk\",\"phase\":\"%s\",\"edge\":%0d,\"bench_case\":%0d,\"time\":%0t,\"reset\":%0b,\"start\":%0b,\"active\":%0b,\"done\":%0b,\"hold\":%0b,\"owner\":%0b,\"slot\":%0d,\"pc\":\"%0h\",\"ir\":\"%0h\",\"op\":%0d,\"action\":\"%0h\",\"state_word\":%0d,\"launch\":%0b,\"advance\":%0b,\"ucode_ce\":%0b,\"next_pc\":\"%0h\",\"branch_take\":%0b,\"state_re\":%0b,\"state_ra\":%0d,\"state_q\":\"%0h\",\"state_we\":%0b,\"state_wa\":%0d,\"state_wd\":\"%0h\",\"proof_q_valid\":%0b,\"proof_q_addr\":%0d,\"proof_q_pc\":\"%0h\",\"proof_q_ir\":\"%0h\",\"proof_q_owner\":%0b,\"proof_q_slot\":%0d,\"proof_q_data\":\"%0h\",\"wave_ce\":%0b,\"wave_issue\":%0b,\"wave_take\":%0b,\"wave_phase\":\"%0h\",\"wave_sel\":%0d,\"wave_alt\":%0b,\"wave_secondary\":%0b,\"wave_z\":\"%0d\",\"proof_wave_v1\":%0b,\"proof_wave_v2\":%0b,\"proof_wave_pc2\":\"%0h\",\"proof_wave_action2\":\"%0h\",\"proof_wave_slot2\":%0d,\"proof_wave_phase2\":\"%0h\",\"proof_wave_sel2\":%0d,\"proof_wave_alt2\":%0b,\"proof_wave_secondary2\":%0b,\"aram_req\":%0b,\"aram_id\":%0d,\"aram_index\":%0d,\"aram_adjacent\":%0b,\"syn_addr\":%0d,\"aram_take\":%0b,\"aram_rd\":%0b,\"aram_addr\":%0d,\"aram_replay\":%0b,\"seq_frozen\":%0b,\"seq_q\":\"%0h\",\"proof_aram_valid\":%0b,\"proof_aram_pc\":\"%0h\",\"proof_aram_action\":\"%0h\",\"proof_aram_slot\":%0d,\"proof_aram_addr\":%0d}",
               phase_name, trace_edge, trace_case, $time, reset, start,
               active, done, hold, owner, slot, pc, ir, op, action,
               state_word, u_ctl.launch, u_ctl.advance, u_ctl.ucode_ce,
               u_ctl.next_pc, u_ctl.branch_take, state_re, state_ra, state_q,
               state_we, state_wa, state_wd, q_origin_valid, q_origin_addr,
               q_origin_pc, q_origin_ir, q_origin_owner, q_origin_slot,
               q_origin_data, wave_ce, wave_issue, wave_take, wave_phase,
               wave_sel, wave_alt, wave_secondary, $signed(z_eval),
               wave_tag1_valid, wave_tag2_valid, wave_tag2_pc,
               wave_tag2_action, wave_tag2_slot, wave_tag2_phase,
               wave_tag2_sel, wave_tag2_alt, wave_tag2_secondary, aram_req,
               aram_id, aram_index, aram_adjacent, syn_addr, aram_take,
               u_aram.aram_rd, u_aram.aram_addr, u_aram.replay, seq_frozen,
               seq_q, aram_tag_valid, aram_tag_pc, aram_tag_action,
               aram_tag_slot, aram_tag_addr);
    end
  endtask

  always @(posedge clk) if (edge_trace && trace_active && active && !owner
                            && pc >= 8'h13 && pc <= 8'h3c) begin
    emit_edge_trace("pre");
    trace_pre_rows = trace_pre_rows + 1;
    #1;
    emit_edge_trace("post");
    trace_post_rows = trace_post_rows + 1;
    trace_edge = trace_edge + 1;
  end

  function automatic logic [15:0] synthetic_wd(
      input logic [2:0] fn_slot,
      input logic [6:0] fn_action,
      input logic [7:0] fn_pc);
    synthetic_wd = {fn_slot, fn_action, fn_pc[5:0]};
  endfunction

  function automatic logic [15:0] qview(
      input logic [15:0] raw,
      input logic [2:0] fn_wave,
      input logic [1:0] fn_mode,
      input logic fn_wt);
    begin
      if (!fn_wt && (fn_wave == 3'd0 || fn_wave == 3'd7))
        qview = raw;
      else if (fn_mode == 2'd2)
        qview = {raw[14:0], 1'b0};
      else
        qview = raw;
    end
  endfunction

  function automatic logic [12:0] sample_addr(
      input logic [2:0] fn_id,
      input logic [5:0] fn_index,
      input logic fn_adjacent);
    logic [5:0] effective_index;
    begin
      effective_index = fn_index + {5'd0, fn_adjacent};
      sample_addr = 13'd256 + {4'b0, fn_id, 6'b0}
                              + {8'b0, fn_id, 2'b0}
                              + {7'd0, effective_index};
    end
  endfunction

  always_comb begin
    cond = 16'd0;
    cond[8] = slot == 3'd0;
    state_ra_override = wave_ra_override | move_ra_override;
    state_ra_word = wave_ra_override ? wave_ra_word : move_ra_word;
    syn_addr = sample_addr(aram_id, aram_index, aram_adjacent);
  end

  psg_execmove u_move(
    .active(active), .hold(hold), .owner(owner), .op(op), .action(action),
    .state_word(state_word), .state_q(state_q), .acc(16'd0),
    .spar_bank(spar_bank), .join_stage(1'b0), .trig_req(1'b0),
    .walk_tick(1'b0), .playing(1'b0), .ins_use(1'b0), .released(1'b0),
    .cpz(1'b0), .state_ra_override(move_ra_override),
    .state_ra_word(move_ra_word), .state_we_extra(move_we_extra),
    .state_wa_word(move_wa_word), .state_wd_override(move_wd_override),
    .state_wd_fixed(move_wd_fixed), .cond_adv(cond_adv),
    .voice_stop(voice_stop), .cpz_we(cpz_we), .cpz_next(cpz_next));

  psg_execwave u_cadence(
    .clk(clk), .active(active), .hold(hold), .owner(owner), .action(action),
    .state_q(state_q), .play(play_mask[slot]),
    .state_ra_override(wave_ra_override), .state_ra_word(wave_ra_word),
    .wave_ce(wave_ce), .wave_issue(wave_issue), .wave_take(wave_take),
    .wave_phase(wave_phase), .wave_sel(wave_sel), .wave_alt(wave_alt),
    .wave_secondary(wave_secondary), .aram_req(aram_req),
    .aram_id(aram_id), .aram_index(aram_index),
    .aram_adjacent(aram_adjacent), .aram_take(aram_take));

  psg_wave_ctx u_wave(
    .clk(clk), .ce(wave_ce), .ctx_phase(wave_phase),
    .ctx_wave(wave_sel), .ctx_alt(wave_alt),
    .ctx_secondary(wave_secondary), .z_eval(z_eval));

  // Static reference cores turn the separately exhaustive wave-core proof
  // into an end-to-end cadence check: every W2--W5 take must expose the
  // result belonging to the corresponding W0--W3 addressed context.
  generate
    for (genvar ref_slot = 0; ref_slot < 8; ref_slot++) begin : g_ref_slot
      psg_wave_ctx u_ref_current(
        .clk(clk), .ce(1'b1), .ctx_phase(cur_phase[ref_slot]),
        .ctx_wave(live_wave[ref_slot]), .ctx_alt(live_alt[ref_slot]),
        .ctx_secondary(1'b0), .z_eval(expected_wave_z[ref_slot][0]));
      psg_wave_ctx u_ref_current_secondary(
        .clk(clk), .ce(1'b1),
        .ctx_phase(qview(cur_phase2[ref_slot], live_wave[ref_slot],
                         live_mode[ref_slot], live_wt[ref_slot])),
        .ctx_wave(live_wave[ref_slot]), .ctx_alt(live_alt[ref_slot]),
        .ctx_secondary(1'b1), .z_eval(expected_wave_z[ref_slot][1]));
      psg_wave_ctx u_ref_old(
        .clk(clk), .ce(1'b1), .ctx_phase(old_phase[ref_slot]),
        .ctx_wave(prior_wave[ref_slot]), .ctx_alt(prior_alt[ref_slot]),
        .ctx_secondary(1'b0), .z_eval(expected_wave_z[ref_slot][2]));
      psg_wave_ctx u_ref_old_secondary(
        .clk(clk), .ce(1'b1),
        .ctx_phase(qview(old_q_value[ref_slot], prior_wave[ref_slot],
                         prior_mode[ref_slot], 1'b0)),
        .ctx_wave(prior_wave[ref_slot]), .ctx_alt(prior_alt[ref_slot]),
        .ctx_secondary(1'b1), .z_eval(expected_wave_z[ref_slot][3]));
    end
  endgenerate

  psg_aram_core u_aram(
    .clk(clk), .reset(reset), .cs(1'b0), .rw(1'b0), .addr(8'd0), .di(8'd0),
    .seq_addr(SEQ_ADDR), .syn_rd(aram_req), .syn_addr(syn_addr),
    .syn_freeze(active && !owner && hold), .seq_hold(1'b1),
    .seq_q(seq_q), .seq_frozen(seq_frozen));

  psg_execctl u_ctl(
    .clk(clk), .reset(reset), .start(start), .start_owner(start_owner),
    .start_pc(start_pc), .hold(hold), .cond(cond),
    .state_wd_i(synthetic_wd(slot, action, pc)),
    .state_ra_override_i(state_ra_override),
    .state_ra_word_i(state_ra_word), .state_we_i(move_we_extra),
    .state_wa_word_i(move_wa_word), .active(active), .done(done),
    .owner(owner), .slot(slot), .state_re(state_re), .state_ra(state_ra),
    .state_we(state_we), .state_wa(state_wa), .state_wd(state_wd),
    .action(action), .state_word(state_word), .op_dbg(op), .pc_dbg(pc),
    .ir_dbg(ir));

  always_ff @(posedge clk) begin
    if (reset)
      state_q <= 16'd0;
    else if (state_re)
      state_q <= mem[state_ra];
    if (state_we)
      mem[state_wa] <= state_wd;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      candidate_pc_seen <= '0;
      state_origin_checks <= 0;
      wave_tag_checks <= 0;
      aram_tag_checks <= 0;
      q_origin_valid <= 1'b0;
      q_origin_addr <= '0;
      q_origin_pc <= '0;
      q_origin_ir <= '0;
      q_origin_owner <= 1'b0;
      q_origin_slot <= '0;
      q_origin_data <= '0;
      wave_tag1_valid <= 1'b0;
      wave_tag2_valid <= 1'b0;
      wave_tag1_slot <= '0;
      wave_tag2_slot <= '0;
      wave_tag1_pc <= '0;
      wave_tag2_pc <= '0;
      wave_tag1_action <= '0;
      wave_tag2_action <= '0;
      wave_tag1_phase <= '0;
      wave_tag2_phase <= '0;
      wave_tag1_sel <= '0;
      wave_tag2_sel <= '0;
      wave_tag1_alt <= 1'b0;
      wave_tag2_alt <= 1'b0;
      wave_tag1_secondary <= 1'b0;
      wave_tag2_secondary <= 1'b0;
      aram_tag_valid <= 1'b0;
      aram_tag_slot <= '0;
      aram_tag_pc <= '0;
      aram_tag_action <= '0;
      aram_tag_addr <= '0;
    end else begin
      // This is a range/IR identity check, not a hand-authored PC/action map.
      if (active && !hold && !owner && pc >= 8'h13 && pc <= 8'h3c) begin
        candidate_pc_seen[pc - 8'h13] <= 1'b1;
        if (ir !== u_ctl.ucode[{owner, pc}])
          $fatal(1, "candidate PC/IR mismatch pc=%h ir=%h image=%h", pc, ir,
                 u_ctl.ucode[{owner, pc}]);
        if (!q_origin_valid || state_q !== q_origin_data)
          $fatal(1,
                 "candidate state-q lost read origin pc=%h q=%h origin=%h/%h",
                 pc, state_q, q_origin_addr, q_origin_data);
        state_origin_checks <= state_origin_checks + 1;
      end

      if (wave_take) begin
        if (!wave_tag2_valid || wave_tag2_slot != slot)
          $fatal(1,
                 "wave take lost issue provenance pc/action=%h/%h tag=%b/%h/%h",
                 pc, action, wave_tag2_valid, wave_tag2_pc,
                 wave_tag2_action);
        if (u_wave.wsel_r2 !== wave_tag2_sel
            || u_wave.wsec_r2 !== wave_tag2_secondary
            || u_wave.walt_r2 !== wave_tag2_alt)
          $fatal(1, "wave RTL pipeline/tag mismatch at pc=%h action=%h", pc,
                 action);
        wave_tag_checks <= wave_tag_checks + 1;
      end

      if (aram_take) begin
        if (!aram_tag_valid || aram_tag_slot != slot)
          $fatal(1,
                 "ARAM take lost request provenance pc/action=%h/%h tag=%b/%h/%h",
                 pc, action, aram_tag_valid, aram_tag_pc, aram_tag_action);
        if (seq_q !== u_aram.aram[aram_tag_addr])
          $fatal(1, "ARAM RTL result/origin mismatch pc=%h addr=%h", pc,
                 aram_tag_addr);
        aram_tag_checks <= aram_tag_checks + 1;
      end
      if (aram_req && (!u_aram.aram_rd || u_aram.aram_addr != syn_addr))
        $fatal(1, "ARAM request did not drive physical read pc=%h", pc);

      if (state_re) begin
        q_origin_valid <= 1'b1;
        q_origin_addr <= state_ra;
        q_origin_pc <= pc;
        q_origin_ir <= ir;
        q_origin_owner <= owner;
        q_origin_slot <= slot;
        q_origin_data <= mem[state_ra];
      end

      if (wave_ce) begin
        if (wave_tag1_valid
            && (u_wave.wx_r !== wave_tag1_phase
                || u_wave.wsel_r !== wave_tag1_sel
                || u_wave.wsec_r !== wave_tag1_secondary
                || u_wave.walt_r !== wave_tag1_alt))
          $fatal(1, "wave first-stage/tag mismatch at pc=%h action=%h", pc,
                 action);
        wave_tag2_valid <= wave_tag1_valid;
        wave_tag2_slot <= wave_tag1_slot;
        wave_tag2_pc <= wave_tag1_pc;
        wave_tag2_action <= wave_tag1_action;
        wave_tag2_phase <= wave_tag1_phase;
        wave_tag2_sel <= wave_tag1_sel;
        wave_tag2_alt <= wave_tag1_alt;
        wave_tag2_secondary <= wave_tag1_secondary;
        wave_tag1_valid <= wave_issue;
        if (wave_issue) begin
          wave_tag1_slot <= slot;
          wave_tag1_pc <= pc;
          wave_tag1_action <= action;
          wave_tag1_phase <= wave_phase;
          wave_tag1_sel <= wave_sel;
          wave_tag1_alt <= wave_alt;
          wave_tag1_secondary <= wave_secondary;
        end
      end

      if (aram_req) begin
        aram_tag_valid <= 1'b1;
        aram_tag_slot <= slot;
        aram_tag_pc <= pc;
        aram_tag_action <= action;
        aram_tag_addr <= syn_addr;
      end else if (aram_take) begin
        aram_tag_valid <= 1'b0;
      end
    end
  end

  task automatic check_context;
    logic [15:0] expected_phase;
    logic [2:0] expected_wave;
    logic expected_alt, expected_secondary;
    begin
      expected_phase = 16'd0;
      expected_wave = 3'd0;
      expected_alt = 1'b0;
      expected_secondary = 1'b0;
      case (action)
        CAP_W0: begin
          expected_phase = cur_phase[slot];
          expected_wave = live_wave[slot];
          expected_alt = live_alt[slot];
        end
        CAP_W1: begin
          expected_phase = qview(cur_phase2[slot], live_wave[slot],
                                 live_mode[slot], live_wt[slot]);
          expected_wave = live_wave[slot];
          expected_alt = live_alt[slot];
          expected_secondary = 1'b1;
        end
        CAP_W2: begin
          expected_phase = old_phase[slot];
          expected_wave = prior_wave[slot];
          expected_alt = prior_alt[slot];
        end
        default: begin
          expected_phase = qview(old_q_value[slot], prior_wave[slot],
                                 prior_mode[slot], 1'b0);
          expected_wave = prior_wave[slot];
          expected_alt = prior_alt[slot];
          expected_secondary = 1'b1;
        end
      endcase
      if (wave_phase !== expected_phase || wave_sel !== expected_wave
          || wave_alt !== expected_alt
          || wave_secondary !== expected_secondary)
        $fatal(1, "wave context slot/action=%0d/%h got=%h/%0d/%b/%b expected=%h/%0d/%b/%b",
               slot, action, wave_phase, wave_sel, wave_alt, wave_secondary,
               expected_phase, expected_wave, expected_alt,
               expected_secondary);
    end
  endtask

  task automatic check_event;
    logic [12:0] expected_addr;
    logic [5:0] expected_index;
    logic expected_adjacent;
    logic [15:0] expected_q_phase;
    logic signed [17:0] expected_z;
    begin
      if (!active || hold)
        return;
      if (!state_re || owner)
        $fatal(1, "active sample instruction lost state CE/owner");
      active_edges = active_edges + 1;
      op_count[op] = op_count[op] + 1;
      if (op == OP_READ)
        semantic_reads = semantic_reads + 1;
      if (state_we)
        semantic_writes = semantic_writes + 1;

      if (action == HOLD_ACTION) begin
        if (!wave_ra_override || wave_ra_word != 6'd10)
          $fatal(1, "HOLD did not prefetch phase word 10");
      end
      if (action == CAP_W0) begin
        if (!wave_ra_override || wave_ra_word != 6'd12
            || state_q !== cur_phase[slot])
          $fatal(1, "W0 phase stream mismatch slot=%0d q=%h", slot, state_q);
      end
      if (action == CAP_W1) begin
        if (!wave_ra_override || wave_ra_word != 6'd16
            || state_q !== cur_phase2[slot])
          $fatal(1, "W1 phase stream mismatch slot=%0d q=%h", slot, state_q);
      end
      if (action == CAP_W2 && state_q !== old_phase[slot])
        $fatal(1, "W2 phase stream mismatch slot=%0d q=%h", slot, state_q);

      if (wave_issue) begin
        if (live_wt[slot] || !(action >= CAP_W0 && action <= CAP_W3))
          $fatal(1, "unexpected wave issue slot/action=%0d/%h", slot, action);
        check_context();
        wave_issues = wave_issues + 1;
      end
      if (wave_take) begin
        if (live_wt[slot] || !(action >= CAP_W2 && action <= CAP_W5))
          $fatal(1, "unexpected wave take slot/action=%0d/%h", slot, action);
        case (action)
          CAP_W2: expected_z = expected_wave_z[slot][0];
          CAP_W3: expected_z = expected_wave_z[slot][1];
          CAP_W4: expected_z = expected_wave_z[slot][2];
          default: expected_z = expected_wave_z[slot][3];
        endcase
        if (z_eval !== expected_z)
          $fatal(1,
                 "wave result mismatch slot/action=%0d/%h got=%h expected=%h",
                 slot, action, z_eval, expected_z);
        wave_takes = wave_takes + 1;
      end

      if (aram_take) begin
        if (!aram_pending)
          $fatal(1, "ARAM take without request slot/action=%0d/%h", slot,
                 action);
        if (seq_q !== u_aram.aram[aram_pending_addr])
          $fatal(1, "ARAM data mismatch address=%h got=%h expected=%h",
                 aram_pending_addr, seq_q, u_aram.aram[aram_pending_addr]);
        aram_pending = 1'b0;
        aram_takes = aram_takes + 1;
      end
      if (aram_req) begin
        if (!live_wt[slot] || !play_mask[slot]
            || !(action >= CAP_W0 && action <= CAP_W3))
          $fatal(1, "unexpected ARAM request slot/action=%0d/%h", slot,
                 action);
        expected_q_phase = qview(cur_phase2[slot], live_wave[slot],
                                 live_mode[slot], live_wt[slot]);
        expected_index = (action == CAP_W0 || action == CAP_W1)
                           ? cur_phase[slot][15:10]
                           : expected_q_phase[15:10];
        expected_adjacent = action == CAP_W1 || action == CAP_W3;
        if (aram_id !== live_id[slot] || aram_index !== expected_index
            || aram_adjacent !== expected_adjacent)
          $fatal(1, "ARAM context mismatch slot/action=%0d/%h got=%0d/%0d/%b expected=%0d/%0d/%b",
                 slot, action, aram_id, aram_index, aram_adjacent,
                 live_id[slot], expected_index, expected_adjacent);
        expected_addr = sample_addr(live_id[slot], expected_index,
                                    expected_adjacent);
        if (syn_addr !== expected_addr)
          $fatal(1, "ARAM address mismatch got=%h expected=%h", syn_addr,
                 expected_addr);
        aram_pending_addr = expected_addr;
        aram_pending = 1'b1;
        aram_issues = aram_issues + 1;
      end
      if (action == CAP_W5 && live_wt[slot] && play_mask[slot]
          && seq_q !== u_aram.aram[SEQ_ADDR])
        $fatal(1, "ARAM replay did not restore sequencer byte");
    end
  endtask

  task automatic init_case(input logic use_wavetable,
                           input logic bank,
                           input logic amp_nonzero);
    integer n, s;
    logic [5:0] par_base;
    begin
      for (n = 0; n < 512; n++)
        mem[n] = 16'(16'h9000 + n * 16'h31);
      for (n = 0; n < 4608; n++)
        u_aram.aram[n] = 8'(n ^ (n >> 5) ^ 8'ha5);
      for (s = 0; s < 8; s++) begin
        cur_phase[s] = {s[2:0], 7'h35, s[5:0]};
        cur_phase2[s] = {~s[2:0], 7'h12, s[5:0]};
        old_phase[s] = {s[2:0], 7'h63, ~s[5:0]};
        old_q_value[s] = {~s[2:0], 7'h29, ~s[5:0]};
        live_wave[s] = s[2:0];
        prior_wave[s] = 3'(7 - s);
        live_mode[s] = 2'(s % 3);
        prior_mode[s] = 2'((s + 1) % 3);
        live_alt[s] = s[0];
        prior_alt[s] = ~s[0];
        live_wt[s] = use_wavetable;
        live_id[s] = 3'(7 - s);

        mem[{s[2:0], 6'd10}] = cur_phase[s];
        mem[{s[2:0], 6'd11}] = {8'h5a, old_q_value[s][7:0]};
        mem[{s[2:0], 6'd12}] = cur_phase2[s];
        mem[{s[2:0], 6'd14}] = {1'b0, prior_mode[s], 13'h123};
        mem[{s[2:0], 6'd16}] = old_phase[s];
        mem[{s[2:0], 6'd17}] = {7'h2a, 1'b0, old_q_value[s][15:8]};
        mem[{s[2:0], 6'd22}] = {1'b0, prior_alt[s], 3'b000,
                                 prior_wave[s], 8'h35};
        par_base = bank ? 6'd28 : 6'd24;
        mem[{s[2:0], par_base + 6'd1}] =
            {1'b0, live_id[s], live_wt[s], live_wave[s], 8'h4c};
        mem[{s[2:0], par_base + 6'd2}] =
            {6'd0, live_mode[s], live_alt[s], 7'h29};
        mem[{s[2:0], par_base + 6'd3}] =
            amp_nonzero ? 16'h1fff : 16'h0000;
      end
      // Slot zero is active in every wavetable case.  Its primary-adjacent
      // request therefore proves that six-bit index 63 wraps to zero.
      cur_phase[0] = 16'hfc35;
      mem[{3'd0, 6'd10}] = cur_phase[0];
    end
  endtask

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  task automatic run_case(input logic use_wavetable,
                          input logic bank,
                          input logic amp_nonzero,
                          input logic [6:0] inject_action);
    integer n, cycles;
    logic [7:0] saved_pc;
    logic [15:0] saved_ir, saved_state_q;
    logic [37:0] saved_adapter_context;
    logic [7:0] saved_seq_q;
    logic saved_replay;
    begin
      trace_case = trace_case + 1;
      trace_active = 1'b0;
      reset = 1'b1;
      start = 1'b0;
      start_owner = 1'b0;
      start_pc = 8'd1;
      hold = 1'b0;
      spar_bank = bank;
      play_mask = use_wavetable ? 8'b01010101 : 8'b10100101;
      hold_action = inject_action;
      hold_injected = 1'b0;
      active_edges = 0;
      semantic_reads = 0;
      semantic_writes = 0;
      wave_issues = 0;
      wave_takes = 0;
      aram_issues = 0;
      aram_takes = 0;
      aram_pending = 1'b0;
      for (n = 0; n < 8; n++)
        op_count[n] = 0;
      init_case(use_wavetable, bank, amp_nonzero);
      step();
      step();
      reset = 1'b0;
      start = 1'b1;
      step();
      start = 1'b0;
      trace_active = edge_trace;

      cycles = 0;
      while (!done && cycles < 900) begin
        @(negedge clk);
        if (active && !hold && !hold_injected && slot == 3'd0
            && action == hold_action) begin
          saved_pc = pc;
          saved_ir = ir;
          saved_state_q = state_q;
          saved_adapter_context = adapter_context;
          saved_seq_q = seq_q;
          saved_replay = u_aram.replay;
          hold = 1'b1;
          hold_injected = 1'b1;
          repeat (3) begin
            step();
            if (pc != saved_pc || ir != saved_ir || state_q != saved_state_q
                || adapter_context != saved_adapter_context
                || seq_q != saved_seq_q || u_aram.replay != saved_replay
                || state_re || state_we || wave_ce || wave_issue || wave_take
                || aram_req || aram_take)
              $fatal(1, "external hold changed H-C state/action %h", action);
          end
          @(negedge clk);
          hold = 1'b0;
          #1;
          check_event();
        end else begin
          check_event();
        end
        cycles = cycles + 1;
      end
      if (!done)
        $fatal(1, "production sample program did not complete");
      if (inject_action != 7'h7f && !hold_injected)
        $fatal(1, "requested hold action %h was not reached", inject_action);
      if (active_edges != 782 || semantic_reads != 172
          || semantic_writes != 158)
        $fatal(1, "program counts got active/read/write=%0d/%0d/%0d",
               active_edges, semantic_reads, semantic_writes);
      if (op_count[0] != 172 || op_count[1] != 158
          || op_count[2] != 8 || op_count[3] != 29
          || op_count[4] != 8 || op_count[5] != 0
          || op_count[6] != 1 || op_count[7] != 406)
        $fatal(1, "production instruction histogram changed");
      if (candidate_pc_seen !== {42{1'b1}})
        $fatal(1, "candidate PC coverage incomplete mask=%h",
               candidate_pc_seen);
      if (state_origin_checks < 42)
        $fatal(1, "candidate state-q origin coverage too small: %0d",
               state_origin_checks);
      if (wave_tag_checks != wave_takes)
        $fatal(1, "wave issue/take proof mismatch tags/takes=%0d/%0d",
               wave_tag_checks, wave_takes);
      if (aram_tag_checks != aram_takes)
        $fatal(1, "ARAM request/take proof mismatch tags/takes=%0d/%0d",
               aram_tag_checks, aram_takes);
      total_state_origin_checks = total_state_origin_checks
                                  + state_origin_checks;
      total_wave_tag_checks = total_wave_tag_checks + wave_tag_checks;
      total_aram_tag_checks = total_aram_tag_checks + aram_tag_checks;
      if (use_wavetable) begin
        if (wave_issues != 0 || wave_takes != 0
            || aram_issues != 16 || aram_takes != 16)
          $fatal(1, "wavetable counts wave=%0d/%0d aram=%0d/%0d",
                 wave_issues, wave_takes, aram_issues, aram_takes);
      end else if (wave_issues != 32 || wave_takes != 32
                   || aram_issues != 0 || aram_takes != 0) begin
        $fatal(1, "built-in counts wave=%0d/%0d aram=%0d/%0d",
                 wave_issues, wave_takes, aram_issues, aram_takes);
      end
      trace_active = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    edge_trace = 1'b0;
    trace_active = 1'b0;
    trace_case = 0;
    trace_edge = 0;
    trace_pre_rows = 0;
    trace_post_rows = 0;
    total_state_origin_checks = 0;
    total_wave_tag_checks = 0;
    total_aram_tag_checks = 0;
    edge_trace = $test$plusargs("PSG_EDGE_TRACE");
    run_case(1'b0, 1'b0, 1'b0, 7'h7f);
    run_case(1'b0, 1'b0, 1'b1, CAP_W0);
    run_case(1'b0, 1'b1, 1'b0, CAP_W1);
    run_case(1'b0, 1'b0, 1'b1, CAP_W2);
    run_case(1'b0, 1'b1, 1'b0, CAP_W3);
    run_case(1'b0, 1'b0, 1'b1, CAP_W4);
    run_case(1'b0, 1'b1, 1'b0, CAP_W5);
    run_case(1'b1, 1'b0, 1'b0, CAP_W0);
    run_case(1'b1, 1'b1, 1'b1, CAP_W1);
    run_case(1'b1, 1'b0, 1'b1, CAP_W2);
    run_case(1'b1, 1'b1, 1'b0, CAP_W3);
    run_case(1'b1, 1'b0, 1'b1, CAP_W4);
    run_case(1'b1, 1'b1, 1'b0, CAP_W5);
    if (edge_trace && trace_pre_rows != trace_post_rows)
      $fatal(1, "trace pre/post rows differ: %0d/%0d", trace_pre_rows,
             trace_post_rows);
    $display("psg_execwave_tb: PASS (production image, 8 slots, W0-W5 holds, q/wave/ARAM joins %0d/%0d/%0d)",
             total_state_origin_checks, total_wave_tag_checks,
             total_aram_tag_checks);
    $finish;
  end
endmodule
