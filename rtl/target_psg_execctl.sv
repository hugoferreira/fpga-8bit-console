`include "psg_execctl.sv"

module target_psg_execctl(input  bit          clk,
                          input  bit          reset,
                          input  logic        start,
                          input  logic        start_owner,
                          input  logic [7:0]  start_pc,
                          input  logic        hold,
                          input  logic [3:0]  cond,
                          input  logic [15:0] state_q,
                          output logic [64:0] probe);
  logic active, done, owner, state_we;
  logic [2:0] slot;
  logic [8:0] state_ra, state_wa;
  logic [15:0] state_wd, ir;
  logic [7:0] pc;

  psg_execctl dut(
    .clk(clk), .reset(reset), .start(start), .start_owner(start_owner),
    .start_pc(start_pc), .hold(hold), .cond(cond), .state_q(state_q),
    .active(active), .done(done), .owner(owner), .slot(slot),
    .state_ra(state_ra), .state_we(state_we), .state_wa(state_wa),
    .state_wd(state_wd), .pc_dbg(pc), .ir_dbg(ir));

  // Keep every controller field observable so the isolated area result cannot
  // become a constant-trim result.
  always_comb
    probe = {active, done, owner, slot, state_we, state_ra, state_wa,
             state_wd, pc, ir};
endmodule
