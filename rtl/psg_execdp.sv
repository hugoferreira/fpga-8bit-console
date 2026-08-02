// Address-selected accumulator for the shared full-mode PSG executor.
//
// One synchronous state-memory word is the only operand and acc is the only
// result register.  Wider operations chain through carry; there is no source
// register index, context bundle or destination selector.  Owner-specific
// macro actions use families 0..6.  Family 7 is the common primitive substrate
// measured by R.84D.

`timescale 1ns/1ps

`ifndef PSG_EXECDP_SV
`define PSG_EXECDP_SV

module psg_execdp(input  bit          clk,
                  input  bit          reset,
                  input  logic        active,
                  input  logic [2:0]  op,
                  input  logic [6:0]  action,
                  input  logic [15:0] state_q,
                  input  logic [7:0]  cond_ext,

                  output logic [15:0] state_wd,
                  output logic [15:0] cond,
                  output logic [15:0] acc_dbg,
                  output logic [3:0]  flags_dbg);

  localparam logic [2:0] OP_EXEC = 3'd7;
  localparam logic [2:0] FAMILY_COMMON = 3'd7;

  localparam logic [3:0]
    A_HOLD = 4'd0,
    A_LOAD = 4'd1,
    A_ADD  = 4'd2,
    A_ADC  = 4'd3,
    A_SUB  = 4'd4,
    A_SBC  = 4'd5,
    A_AND  = 4'd6,
    A_OR   = 4'd7,
    A_XOR  = 4'd8,
    A_SHL  = 4'd9,
    A_ROL  = 4'd10,
    A_SHR  = 4'd11,
    A_ROR  = 4'd12,
    A_ASR  = 4'd13,
    A_NEG  = 4'd14,
    A_CMP  = 4'd15;

  logic [15:0] acc;
  logic flag_z, flag_n, flag_c, flag_v;
  logic [15:0] result;
  logic result_c, result_v, write_acc, write_flags;
  logic [16:0] wide;
  logic [15:0] arith_lhs, arith_operand, arith_rhs;
  logic arith_sub, arith_cin;

  wire exec = active && op == OP_EXEC && action[6:4] == FAMILY_COMMON;
  wire [3:0] fn = action[3:0];

  always_comb begin
    result = acc;
    result_c = flag_c;
    result_v = flag_v;
    write_acc = 1'b1;
    write_flags = 1'b1;
    arith_lhs = (fn == A_NEG) ? 16'd0 : acc;
    arith_operand = (fn == A_NEG) ? acc : state_q;
    arith_sub = fn == A_SUB || fn == A_SBC || fn == A_CMP
                || fn == A_NEG;
    arith_rhs = arith_sub ? ~arith_operand : arith_operand;
    arith_cin = (fn == A_SUB || fn == A_CMP || fn == A_NEG) ? 1'b1
                : (fn == A_ADC || fn == A_SBC) ? flag_c : 1'b0;
    // This is the one physical arithmetic chain.  ADD/ADC/SUB/SBC/CMP/NEG
    // select inversion and carry-in before it instead of spelling six adders.
    wide = {1'b0, arith_lhs} + {1'b0, arith_rhs} + 17'(arith_cin);

    case (fn)
      A_HOLD: begin
        write_acc = 1'b0;
        write_flags = 1'b0;
      end
      A_LOAD: begin
        result = state_q;
      end
      A_ADD, A_ADC, A_SUB, A_SBC, A_CMP, A_NEG: begin
        result = wide[15:0];
        result_c = (fn == A_NEG) ? acc != 0 : wide[16];
        if (fn == A_NEG)
          result_v = acc == 16'h8000;
        else if (arith_sub)
          result_v = (acc[15] ^ state_q[15]) & (result[15] ^ acc[15]);
        else
          result_v = ~(acc[15] ^ state_q[15]) & (result[15] ^ acc[15]);
        if (fn == A_CMP)
          write_acc = 1'b0;
      end
      A_AND: begin
        result = acc & state_q;
      end
      A_OR: begin
        result = acc | state_q;
      end
      A_XOR: begin
        result = acc ^ state_q;
      end
      A_SHL: begin
        result = {acc[14:0], 1'b0};
        result_c = acc[15];
        result_v = 1'b0;
      end
      A_ROL: begin
        result = {acc[14:0], flag_c};
        result_c = acc[15];
        result_v = 1'b0;
      end
      A_SHR: begin
        result = {1'b0, acc[15:1]};
        result_c = acc[0];
        result_v = 1'b0;
      end
      A_ROR: begin
        result = {flag_c, acc[15:1]};
        result_c = acc[0];
        result_v = 1'b0;
      end
      A_ASR: begin
        result = {acc[15], acc[15:1]};
        result_c = acc[0];
        result_v = 1'b0;
      end
      default: begin
        write_acc = 1'b0;
        write_flags = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      acc    <= 16'd0;
      flag_z <= 1'b1;
      flag_n <= 1'b0;
      flag_c <= 1'b0;
      flag_v <= 1'b0;
    end else if (exec) begin
      if (write_acc)
        acc <= result;
      if (write_flags) begin
        flag_z <= result == 0;
        flag_n <= result[15];
        flag_c <= result_c;
        flag_v <= result_v;
      end
    end
  end

  always_comb begin
    state_wd = acc;
    // Branches consume generic arithmetic flags or eight owner-specific
    // external predicates.  Complements come from the instruction sense bit.
    // Comparisons are explicit A_CMP operations.  Keeping live equality and
    // ordering comparators here would rebuild three parallel arithmetic cones
    // beside the serialized accumulator.
    cond = {cond_ext, 4'b0, flag_v, flag_c, flag_n, flag_z};
    acc_dbg = acc;
    flags_dbg = {flag_v, flag_c, flag_n, flag_z};
  end

endmodule

`endif
