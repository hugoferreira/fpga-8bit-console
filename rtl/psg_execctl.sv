// Full-schedule PSG microprogram controller foundation.
//
// The controller owns no wide arithmetic and no general register file.  Its
// program selects one per-slot state address at a time; the surrounding
// executor supplies operation-specific logic and commits results through the
// existing state-memory write port.  Sample and tick programs share this one
// PC because their windows are mutually exclusive. owner=0 selects the sample
// program and owner=1 the tick program, each with a full 256-word bank.

`timescale 1ns/1ps

`ifndef PSG_EXECCTL_SV
`define PSG_EXECCTL_SV

module psg_execctl #(parameter TEST_PROGRAM = 0)
                  (input  bit         clk,
                   input  bit         reset,
                   input  logic       start,
                   input  logic       start_owner,
                   input  logic [7:0] start_pc,
                   input  logic       hold,
                   input  logic [15:0] cond,
                   input  logic [15:0] state_wd_i,
                   input  logic       state_ra_override_i,
                   input  logic [5:0] state_ra_word_i,
                   input  logic       state_we_i,
                   input  logic [5:0] state_wa_word_i,

                   output logic       active,
                   output logic       done,
                   output logic       owner,
                   output logic [2:0] slot,
                   output logic       state_re,
                   output logic [8:0] state_ra,
                   output logic       state_we,
                   output logic [8:0] state_wa,
                   output logic [15:0] state_wd,
                   output logic [6:0] action,
                   output logic [5:0] state_word,
                   output logic [2:0] op_dbg,
                   output logic [7:0] pc_dbg,
                   output logic [15:0] ir_dbg);
  // ---- Instruction format ----
  localparam logic [2:0]
    OP_READ   = 3'd0,
    OP_WRITE  = 3'd1,
    OP_BRANCH = 3'd2,
    OP_SLOT   = 3'd3,
    OP_JUMP   = 3'd4,
    OP_OWNER  = 3'd5,
    OP_DONE   = 3'd6,
    OP_EXEC   = 3'd7;
  // ---- Owner-banked control store ----
  // The 512x16 control store occupies two EBRs as two owner-selected 256-word
  // banks. Keeping owner outside the logical PC leaves branch and jump targets
  // eight bits wide.
  (* ram_style = "block" *) logic [15:0] ucode[0:511];
  initial begin
    if (TEST_PROGRAM) begin
      for (int i = 0; i < 512; i++)
        ucode[i] = {OP_DONE, 13'd0};

      // Duplicate the base path so the test can enter it through either bank.
      for (int bank = 0; bank < 2; bank++) begin
        ucode[{bank[0], 8'd0}] = {OP_READ,   7'd0, 6'd34};
        ucode[{bank[0], 8'd1}] = {OP_WRITE,  7'd0, 6'd38};
        ucode[{bank[0], 8'd2}] = {OP_BRANCH, 4'd0, 1'b1, 8'd5};
        ucode[{bank[0], 8'd3}] = {OP_EXEC,   7'd17, 6'd9};
        ucode[{bank[0], 8'd4}] = {OP_JUMP,   5'd0, 8'd6};
        ucode[{bank[0], 8'd5}] = {OP_SLOT,   9'd0, 1'b0, 3'd3};
        ucode[{bank[0], 8'd6}] = {OP_DONE,  13'd0};
      end
      // Owner changes select the next instruction's bank on the same fetch.
      ucode[{1'b1, 8'd8}] = {OP_OWNER, 12'd0, 1'b0};
      ucode[{1'b0, 8'd9}] = {OP_SLOT,   9'd0, 1'b1, 3'd0};
      ucode[{1'b0, 8'd10}] = {OP_DONE, 13'd0};
      // Same logical PC, deliberately different contents in each bank.
      ucode[{1'b0, 8'd12}] = {OP_EXEC, 7'd3, 6'd12};
      ucode[{1'b1, 8'd12}] = {OP_EXEC, 7'd5, 6'd12};
      ucode[{1'b0, 8'd13}] = {OP_DONE, 13'd0};
      ucode[{1'b1, 8'd13}] = {OP_DONE, 13'd0};
    end else begin
      $readmemh("./rtl/psg_exec.hex", ucode);
    end
  end
  // ---- Prefetched instruction and successor selection ----
  logic [7:0] pc;
  logic [15:0] ir;
  wire [2:0] op = ir[15:13];
  wire branch_take = cond[ir[12:9]] == ir[8];
  logic [7:0] next_pc;
  wire launch = start && !active;
  wire advance = active && !hold && op != OP_DONE;
  wire ucode_ce = launch || advance;
  wire next_owner = op == OP_OWNER ? ir[0] : owner;
  wire [8:0] ucode_addr = launch ? {start_owner, start_pc}
                                 : {next_owner, next_pc};
  // ---- Synchronous fetch and state-memory transaction ----
  // One reset-free sequential read site is the physical EBR output register.
  always_ff @(posedge clk)
    if (ucode_ce)
      ir <= ucode[ucode_addr];

  always_comb begin
    next_pc = pc + 1'b1;
    case (op)
      OP_BRANCH: if (branch_take) next_pc = ir[7:0];
      OP_JUMP:   next_pc = ir[7:0];
      default: ;
    endcase
  end

  always_comb begin
    // The state EBR is a pipelined operand stream, not an OP_READ-only port.
    // Every executing instruction may prime state_q for its successor; hold
    // must freeze that output register together with the controller.
    state_re = active && !hold;
    state_ra = {slot, state_ra_override_i ? state_ra_word_i : ir[5:0]};
    state_wa = {slot, state_we_i ? state_wa_word_i : ir[5:0]};
    state_we = active && !hold && (op == OP_WRITE || state_we_i);
    state_wd = state_wd_i;
    action = (op == OP_READ || op == OP_WRITE || op == OP_EXEC)
               ? ir[12:6] : 7'd0;
    state_word = ir[5:0];
    op_dbg = op;
    pc_dbg = pc;
    ir_dbg = ir;
  end
  // ---- Run, owner, slot, and PC state ----
  always_ff @(posedge clk) begin
    if (reset) begin
      active <= 1'b0;
      done   <= 1'b0;
      owner  <= 1'b0;
      slot   <= 3'd0;
      pc     <= 8'd0;
    end else begin
      done <= 1'b0;
      if (launch) begin
        active <= 1'b1;
        owner  <= start_owner;
        slot   <= 3'd0;
        pc     <= start_pc;
      end else if (active && !hold) begin
        case (op)
          OP_SLOT:
            slot <= ir[3] ? slot + 1'b1 : ir[2:0];
          OP_OWNER:
            owner <= ir[0];
          default: ;
        endcase

        if (op == OP_DONE) begin
          active <= 1'b0;
          done   <= 1'b1;
        end else begin
          pc <= next_pc;
        end
      end
    end
  end

endmodule

`endif
