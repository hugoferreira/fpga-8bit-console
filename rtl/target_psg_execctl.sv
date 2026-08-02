`include "psg_execctl.sv"
`include "psg_execdp.sv"
`include "psg_execmove.sv"

module target_psg_execctl(input  bit          clk,
                          input  bit          reset,
                          input  logic        start,
                          input  logic        start_owner,
                          input  logic [7:0]  start_pc,
                          input  logic        hold,
                          input  logic [7:0]  cond_ext,
                          input  logic [15:0] state_q,
                          output logic [15:0] probe);
  // These wires deliberately stay internal: keep preserves the complete
  // controller interface for synthesis without spending TQ144 package pins.
  /* verilator lint_off UNUSEDSIGNAL */
  (* keep *) logic active, done, owner, state_we;
  (* keep *) logic [2:0] slot;
  (* keep *) logic [8:0] state_ra, state_wa;
  (* keep *) logic [15:0] state_wd, ir;
  (* keep *) logic [6:0] action;
  (* keep *) logic [5:0] state_word;
  (* keep *) logic [2:0] op_dbg;
  (* keep *) logic [7:0] pc;
  (* keep *) logic [15:0] cond, state_wd_dp, acc_dbg;
  (* keep *) logic [3:0] flags_dbg;
  (* keep *) logic state_ra_override, state_we_extra, copy_state_q;
  (* keep *) logic [5:0] state_ra_word, state_wa_word;
  (* keep *) logic [15:0] state_wd_mux;
  /* verilator lint_on UNUSEDSIGNAL */

  psg_execdp u_dp(
    .clk(clk), .reset(reset), .active(active), .hold(hold), .op(op_dbg),
    .action(action), .state_q(state_q), .cond_ext(cond_ext),
    .state_wd(state_wd_dp), .cond(cond), .acc_dbg(acc_dbg),
    .flags_dbg(flags_dbg));

  psg_execmove u_move(
    .active(active), .hold(hold), .owner(owner), .op(op_dbg),
    .action(action), .state_ra_override(state_ra_override),
    .state_ra_word(state_ra_word), .state_we_extra(state_we_extra),
    .state_wa_word(state_wa_word), .copy_state_q(copy_state_q));

  always_comb state_wd_mux = copy_state_q ? state_q : state_wd_dp;

  (* keep *)
  psg_execctl dut(
    .clk(clk), .reset(reset), .start(start), .start_owner(start_owner),
    .start_pc(start_pc), .hold(hold), .cond(cond),
    .state_wd_i(state_wd_mux),
    .state_ra_override_i(state_ra_override),
    .state_ra_word_i(state_ra_word), .state_we_i(state_we_extra),
    .state_wa_word_i(state_wa_word),
    .active(active), .done(done), .owner(owner), .slot(slot),
    .state_ra(state_ra), .state_we(state_we), .state_wa(state_wa),
    .state_wd(state_wd), .action(action), .state_word(state_word),
    .op_dbg(op_dbg), .pc_dbg(pc), .ir_dbg(ir));

  // The keep-marked controller interface prevents constant trimming without
  // turning the isolated TQ144 measurement into an artificial 126-pin target.
  always_comb probe = ir;
endmodule
