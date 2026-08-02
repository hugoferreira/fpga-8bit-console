`include "psg_common.svh"
`include "psg_execctl.sv"
`include "psg_execdp.sv"
`include "psg_execmove.sv"
`include "psg_execwave.sv"
`include "psg_wave.sv"
`include "psg_aram.sv"

// Measurement-only paired wrapper.  WITH_ADAPTER=0 keeps the accepted H-B
// executor and drives the retained service cores from raw top-level inputs;
// WITH_ADAPTER=1 inserts H-C and drives those same cores from its fixed roles.
module target_psg_execwave_services #(parameter WITH_ADAPTER = 1)
                       (input bit clk,
                        input bit reset,
                        input logic start,
                        input logic start_owner,
                        input logic [7:0] start_pc,
                        input logic hold,
                        input logic [7:0] cond_ext,
                        input logic spar_bank,
                        input logic join_stage,
                        input logic trig_req,
                        input logic walk_tick,
                        input logic playing,
                        input logic ins_use,
                        input logic released,
                        input logic cpz,
                        input logic [15:0] state_q,
                        input logic [12:0] seq_addr,
                        input logic seq_hold,
                        input logic aram_cs,
                        input logic aram_rw,
                        input logic [7:0] aram_addr,
                        input logic [7:0] aram_di,
                        output logic [15:0] probe);
  (* keep *) logic active, done, owner, state_re, state_we;
  (* keep *) logic [2:0] slot;
  (* keep *) logic [8:0] state_ra, state_wa;
  (* keep *) logic [15:0] state_wd, ir;
  (* keep *) logic [6:0] action;
  (* keep *) logic [5:0] state_word;
  (* keep *) logic [2:0] op_dbg;
  (* keep *) logic [7:0] pc;
  (* keep *) logic [15:0] cond, state_wd_dp, acc_dbg;
  (* keep *) logic [3:0] flags_dbg;
  logic move_ra_override, state_we_extra, state_wd_override;
  logic [5:0] move_ra_word, state_wa_word;
  logic [15:0] state_wd_fixed, state_wd_mux;
  logic [7:0] cond_exec;
  logic [3:0] cond_adv;
  logic voice_stop, cpz_we, cpz_next;

  (* keep *) logic wave_ra_override;
  (* keep *) logic [5:0] wave_ra_word;
  (* keep *) logic wave_ce, wave_issue, wave_take;
  (* keep *) logic [15:0] wave_phase;
  (* keep *) logic [2:0] wave_sel;
  (* keep *) logic wave_alt, wave_secondary;
  (* keep *) logic aram_req, aram_adjacent, aram_take;
  (* keep *) logic [2:0] aram_id;
  (* keep *) logic [5:0] aram_index;
  logic state_ra_override;
  logic [5:0] state_ra_word;

  psg_execdp u_dp(
    .clk(clk), .reset(reset), .active(active), .hold(hold), .op(op_dbg),
    .action(action), .state_q(state_q), .cond_ext(cond_exec),
    .state_wd(state_wd_dp), .cond(cond), .acc_dbg(acc_dbg),
    .flags_dbg(flags_dbg));

  psg_execmove u_move(
    .active(active), .hold(hold), .owner(owner), .op(op_dbg),
    .action(action), .state_word(state_word), .state_q(state_q),
    .acc(acc_dbg), .spar_bank(spar_bank), .join_stage(join_stage),
    .trig_req(trig_req), .walk_tick(walk_tick), .playing(playing),
    .ins_use(ins_use), .released(released), .cpz(cpz),
    .state_ra_override(move_ra_override),
    .state_ra_word(move_ra_word), .state_we_extra(state_we_extra),
    .state_wa_word(state_wa_word), .state_wd_override(state_wd_override),
    .state_wd_fixed(state_wd_fixed), .cond_adv(cond_adv),
    .voice_stop(voice_stop), .cpz_we(cpz_we), .cpz_next(cpz_next));

  generate
    if (WITH_ADAPTER) begin : g_adapter
      psg_execwave u_adapter(
        .clk(clk), .active(active), .hold(hold), .owner(owner),
        .action(action), .state_q(state_q), .play(playing),
        .state_ra_override(wave_ra_override),
        .state_ra_word(wave_ra_word), .wave_ce(wave_ce),
        .wave_issue(wave_issue), .wave_take(wave_take),
        .wave_phase(wave_phase), .wave_sel(wave_sel), .wave_alt(wave_alt),
        .wave_secondary(wave_secondary), .aram_req(aram_req),
        .aram_id(aram_id), .aram_index(aram_index),
        .aram_adjacent(aram_adjacent), .aram_take(aram_take));
    end else begin : g_no_adapter
      always_comb begin
        wave_ra_override = 1'b0;
        wave_ra_word = 6'd0;
        wave_ce = playing;
        wave_issue = playing;
        wave_take = playing;
        wave_phase = state_q;
        wave_sel = cond_ext[2:0];
        wave_alt = cond_ext[3];
        wave_secondary = cond_ext[4];
        aram_req = trig_req;
        aram_id = cond_ext[7:5];
        aram_index = start_pc[5:0];
        aram_adjacent = cpz;
        aram_take = trig_req;
      end
    end
  endgenerate

  always_comb begin
    cond_exec = owner ? {cond_ext[7:4], cond_adv} : cond_ext;
    state_wd_mux = state_wd_override ? state_wd_fixed : state_wd_dp;
    state_ra_override = wave_ra_override | move_ra_override;
    state_ra_word = wave_ra_override ? wave_ra_word : move_ra_word;
  end

  psg_execctl u_ctl(
    .clk(clk), .reset(reset), .start(start), .start_owner(start_owner),
    .start_pc(start_pc), .hold(hold), .cond(cond),
    .state_wd_i(state_wd_mux), .state_ra_override_i(state_ra_override),
    .state_ra_word_i(state_ra_word), .state_we_i(state_we_extra),
    .state_wa_word_i(state_wa_word), .active(active), .done(done),
    .owner(owner), .slot(slot), .state_re(state_re), .state_ra(state_ra),
    .state_we(state_we), .state_wa(state_wa), .state_wd(state_wd),
    .action(action), .state_word(state_word), .op_dbg(op_dbg),
    .pc_dbg(pc), .ir_dbg(ir));

  logic [5:0] effective_index;
  logic [12:0] syn_addr;
  always_comb begin
    effective_index = aram_index + {5'd0, aram_adjacent};
    syn_addr = 13'd256 + {4'b0, aram_id, 6'b0}
                         + {8'b0, aram_id, 2'b0}
                         + {7'd0, effective_index};
  end

  logic signed [17:0] z_eval;
  logic [7:0] seq_q;
  logic seq_frozen;
  psg_wave_ctx u_wave(
    .clk(clk), .ce(wave_ce), .ctx_phase(wave_phase),
    .ctx_wave(wave_sel), .ctx_alt(wave_alt),
    .ctx_secondary(wave_secondary), .z_eval(z_eval));
  psg_aram_core u_aram(
    .clk(clk), .reset(reset), .cs(aram_cs), .rw(aram_rw),
    .addr(aram_addr), .di(aram_di), .seq_addr(seq_addr),
    .cpu_rd(1'b0), .cpu_q(),
    .syn_rd(aram_req), .syn_addr(syn_addr),
    .syn_freeze(active && !owner && hold), .seq_hold(seq_hold),
    .seq_q(seq_q), .seq_frozen(seq_frozen));

  always_comb
    probe = ir ^ state_wd ^ z_eval[15:0] ^ {8'd0, seq_q}
            ^ {15'd0, seq_frozen};
endmodule
