// Full-schedule PSG microprogram controller foundation.
//
// The controller owns no wide arithmetic and no general register file.  Its
// program selects one per-slot state address at a time; the surrounding
// executor supplies operation-specific logic and commits results through the
// existing state-memory write port.  Sample and tick programs share this one
// PC because their execution windows are mutually exclusive.

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
                   input  logic [15:0] state_q,

                   output logic       active,
                   output logic       done,
                   output logic       owner,
                   output logic [2:0] slot,
                   output logic [8:0] state_ra,
                   output logic       state_we,
                   output logic [8:0] state_wa,
                   output logic [15:0] state_wd,
                   output logic [6:0] action,
                   output logic [5:0] state_word,
                   output logic [2:0] op_dbg,
                   output logic [7:0] pc_dbg,
                   output logic [15:0] ir_dbg);

  localparam logic [2:0]
    OP_READ   = 3'd0,
    OP_WRITE  = 3'd1,
    OP_BRANCH = 3'd2,
    OP_SLOT   = 3'd3,
    OP_JUMP   = 3'd4,
    OP_OWNER  = 3'd5,
    OP_DONE   = 3'd6,
    OP_EXEC   = 3'd7;

  // R.84 reserves the fifteenth and final permitted EBR for the complete
  // full-mode program.  start_pc remains dynamic so synthesis cannot prune
  // unvisited pages while the instruction format is being measured.
  (* ram_style = "block" *) logic [15:0] ucode[0:255];
  initial begin
    if (TEST_PROGRAM) begin
      for (int i = 0; i < 256; i++)
        ucode[i] = {OP_DONE, 13'd0};

      // A short self-checking path used by psg_execctl_tb.
      ucode[0] = {OP_READ,   7'd0, 6'd34};
      ucode[1] = {OP_WRITE,  7'd0, 6'd38};
      ucode[2] = {OP_BRANCH, 4'd0, 1'b1, 8'd5};
      ucode[3] = {OP_EXEC,   7'd17, 6'd9};
      ucode[4] = {OP_JUMP,   5'd0, 8'd6};
      ucode[5] = {OP_SLOT,   9'd0, 1'b0, 3'd3};
      ucode[6] = {OP_DONE,  13'd0};
      ucode[8] = {OP_OWNER, 12'd0, 1'b0};
      ucode[9] = {OP_SLOT,   9'd0, 1'b1, 3'd0};
      ucode[10] = {OP_DONE, 13'd0};
    end else begin
      $readmemh("./rtl/psg_exec.hex", ucode);
    end
  end

  logic [7:0] pc;
  logic [15:0] ir;
  wire [2:0] op = ir[15:13];
  wire branch_take = cond[ir[12:9]] == ir[8];
  logic [7:0] next_pc;
  wire launch = start && !active;
  wire advance = active && !hold && op != OP_DONE;
  wire ucode_ce = launch || advance;
  wire [7:0] ucode_addr = launch ? start_pc : next_pc;

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
    state_ra = {slot, ir[5:0]};
    state_wa = {slot, ir[5:0]};
    state_we = active && !hold && op == OP_WRITE;
    state_wd = state_q;
    action = (op == OP_READ || op == OP_WRITE || op == OP_EXEC)
               ? ir[12:6] : 7'd0;
    state_word = ir[5:0];
    op_dbg = op;
    pc_dbg = pc;
    ir_dbg = ir;
  end

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
