// Synchronous state-memory movement for the shared PSG executor.
//
// Tick-owner actions stream complete records, advance actions normalize row
// and counter fields, and sample-owner actions select active-parameter words.
// Each action has one fixed projection, merge, or address. The decoder owns no
// general register index, arithmetic chain, or result register; state movement
// stays visible as an address-selected transaction.

`timescale 1ns/1ps

`ifndef PSG_EXECMOVE_SV
`define PSG_EXECMOVE_SV

module psg_execmove(input  logic       active,
                    input  logic       hold,
                    input  logic       owner,
                    input  logic [2:0] op,
                    input  logic [6:0] action,
                    input  logic [5:0] state_word,
                    input  logic [15:0] state_q,
                    input  logic [15:0] acc,
                    input  logic       spar_bank,
                    input  logic       join_stage,
                    input  logic       trig_req,
                    input  logic       walk_tick,
                    input  logic       playing,
                    input  logic       ins_use,
                    input  logic       released,
                    input  logic       cpz,
                    // Address/write overrides and emitted sequencer effects.
                    output logic       state_ra_override,
                    output logic [5:0] state_ra_word,
                    output logic       state_we_extra,
                    output logic [5:0] state_wa_word,
                    output logic       state_wd_override,
                    output logic [15:0] state_wd_fixed,
                    output logic [3:0] cond_adv,
                    output logic       voice_stop,
                    output logic       cpz_we,
                    output logic       cpz_next);
  // ---- Fixed movement-action dictionary ----
  localparam logic [2:0]
    OP_READ  = 3'd0,
    OP_WRITE = 3'd1;
  localparam logic [6:0]
    K_ADV           = 7'h40,
    X_LO_FCNT       = 7'h47,
    X_HI_TCNT       = 7'h48,
    X_LO_SPEED      = 7'h49,
    X_LENGTH        = 7'h4a,
    SAVE44_R36      = 7'h4b,
    MERGE_CTR_V_NR  = 7'h4c,
    MERGE_CTR_V_ROLL= 7'h4d,
    PREV_V_PITCH    = 7'h4e,
    PREV_V_VOL      = 7'h4f,
    X_ROW_V         = 7'h0d,
    X_LPS           = 7'h0e,
    X_LPE           = 7'h0f,
    X_END           = 7'h1c,
    SAVE45_R39      = 7'h1d,
    SAVE44          = 7'h1e,
    MERGE_ROW_V     = 7'h1f,
    MERGE_LEN_V     = 7'h29,
    VOICE_STOP      = 7'h2a,
    SKIP_CPZ        = 7'h2b,
    MERGE_CTR_I_NR  = 7'h2c,
    MERGE_CTR_I_ROLL= 7'h2d,
    PREV_I_PITCH    = 7'h2e,
    PREV_I_VOL      = 7'h2f,
    X_ROW_I         = 7'h3d,
    MERGE_ROW_I     = 7'h3e,
    INS_DONE        = 7'h3f,
    P_W0            = 7'h53,
    P_W1            = 7'h54,
    P_W2            = 7'h55,
    P_W3            = 7'h56,
    PC0             = 7'h57,
    PC1             = 7'h58,
    PC2             = 7'h59,
    PC3             = 7'h5a,
    K_ROT           = 7'h5e;
  // ---- Owner, action-family, and parameter-bank decode ----
  wire sample = active && !hold && !owner;
  wire tick = active && !hold && owner;
  wire [2:0] family = action[6:4];
  wire [3:0] subop = action[3:0];
  wire copy_bank = spar_bank ^ join_stage;
  wire [5:0] par_copy0 = copy_bank ? 6'd28 : 6'd24;
  wire [5:0] par_copy1 = copy_bank ? 6'd29 : 6'd25;
  wire [5:0] par_copy2 = copy_bank ? 6'd30 : 6'd26;
  wire [5:0] par_copy3 = copy_bank ? 6'd31 : 6'd27;
  // ---- One-edge fixed write helper ----
  task automatic fixed_write(input logic [5:0] word,
                             input logic [15:0] data);
    begin
      state_we_extra = 1'b1;
      state_wa_word = word;
      state_wd_override = 1'b1;
      state_wd_fixed = data;
    end
  endtask
  // ---- Address-selected movement transaction ----
  always_comb begin
    state_ra_override = 1'b0;
    state_ra_word = 6'd0;
    state_we_extra = 1'b0;
    state_wa_word = 6'd0;
    state_wd_override = 1'b0;
    state_wd_fixed = state_q;
    cond_adv = {released, ins_use, walk_tick && playing, trig_req};
    voice_stop = 1'b0;
    cpz_we = 1'b0;
    cpz_next = cpz;

    // The sample program encodes parameter offsets 24..27 literally.  Select
    // the active bank by replacing only address bit two; all oscillator,
    // scratch and fold addresses pass straight through the instruction word.
    // No sample data is captured or selected by this movement layer.
    if (sample && op == OP_READ && state_word[5:2] == 4'b0110) begin
      state_ra_override = 1'b1;
      state_ra_word = {3'b011, spar_bank, state_word[1:0]};
    end

    if (tick) begin
      // V_LD0 has a free write edge and initializes the common +1 operand.
      // V_LD1..7 consume words 3,4,5,8,9,par+2,32 into scratch 48..54.
      // V_LD6 has already captured par+2, so K_ADV's repeated read is free to
      // initialize the exact row-end constant without another port or clock.
      if (op == OP_READ && family == 3'd0 && subop == 4'd0
          && state_word == 6'd3) begin
        fixed_write(6'd34, 16'd1);
      end else if (action == K_ADV) begin
        fixed_write(6'd35, 16'd32);
      end
      case (action)
        7'h01: fixed_write(6'd48, state_q);
        7'h02: fixed_write(6'd49, state_q);
        7'h03: fixed_write(6'd50, state_q);
        7'h04: fixed_write(6'd51, state_q);
        7'h05: begin
          fixed_write(6'd52, state_q);
          state_ra_override = 1'b1;
          state_ra_word = spar_bank ? 6'd30 : 6'd26;
        end
        7'h06: fixed_write(6'd53, state_q);
        7'h07: begin
          fixed_write(6'd54, state_q);
          state_ra_override = 1'b1;
          state_ra_word = spar_bank ? 6'd30 : 6'd26;
        end
        default: ;
      endcase

      // V_ST0..3 write the current source while reading the next; V_ST4
      // commits word 54.  P_W3 and PC3 issue scratch 48 after consuming their
      // own current state_q, so no priming cycle is added.
      if (op == OP_WRITE && family == 3'd0
                   && subop >= 4'd8 && subop <= 4'd12) begin
        state_wd_override = 1'b1;
        state_wd_fixed = state_q;
        case (subop)
          4'd8:  begin state_ra_override = 1'b1; state_ra_word = 6'd49; end
          4'd9:  begin state_ra_override = 1'b1; state_ra_word = 6'd50; end
          4'd10: begin state_ra_override = 1'b1; state_ra_word = 6'd52; end
          4'd11: begin state_ra_override = 1'b1; state_ra_word = 6'd54; end
          default: ;
        endcase
      end

      // Publication always writes the inactive bank.  Copy publication reads
      // the active bank, except a join-stage copy reads the just-staged bank.
      case (action)
        P_W0: begin
          state_we_extra = 1'b1;
          state_wa_word = spar_bank ? 6'd24 : 6'd28;
        end
        P_W1: begin
          state_we_extra = 1'b1;
          state_wa_word = spar_bank ? 6'd25 : 6'd29;
        end
        P_W2: begin
          state_we_extra = 1'b1;
          state_wa_word = spar_bank ? 6'd26 : 6'd30;
        end
        P_W3: begin
          state_we_extra = 1'b1;
          state_wa_word = spar_bank ? 6'd27 : 6'd31;
          state_ra_override = 1'b1;
          state_ra_word = 6'd48;
        end
        K_ROT: begin
          state_ra_override = 1'b1;
          state_ra_word = par_copy0;
        end
        PC0: begin
          fixed_write(spar_bank ? 6'd24 : 6'd28, state_q);
          state_ra_override = 1'b1;
          state_ra_word = par_copy1;
        end
        PC1: begin
          fixed_write(spar_bank ? 6'd25 : 6'd29, state_q);
          state_ra_override = 1'b1;
          state_ra_word = par_copy2;
        end
        PC2: begin
          fixed_write(spar_bank ? 6'd26 : 6'd30, state_q);
          state_ra_override = 1'b1;
          state_ra_word = par_copy3;
        end
        PC3: begin
          fixed_write(spar_bank ? 6'd27 : 6'd31,
                      cpz ? {state_q[15:8], 8'd0} : state_q);
          state_ra_override = 1'b1;
          state_ra_word = 6'd48;
        end
        default: ;
      endcase

      // Fixed normalization writes.  The READ instruction itself issues the
      // next raw/source address while this decoder consumes the preceding
      // synchronous state_q word.
      case (action)
        X_LO_FCNT:  fixed_write(6'd36, {8'd0, state_q[7:0]});
        X_HI_TCNT:  fixed_write(6'd37, {8'd0, state_q[15:8]});
        X_LO_SPEED: fixed_write(6'd38, {8'd0, state_q[7:0]});
        X_LENGTH:   fixed_write(6'd39, {10'd0, state_q[13:8]});
        X_ROW_V:    fixed_write(6'd40, {11'd0, state_q[4:0]});
        X_LPS:      fixed_write(6'd41, {8'd0, state_q[7:0]});
        X_LPE:      fixed_write(6'd42, {8'd0, state_q[15:8]});
        X_END: begin
          fixed_write(6'd43,
            state_q[15:8] == 0 && state_q[7:5] == 0 && state_q[4:0] != 0
              ? {11'd0, state_q[4:0]} : 16'd32);
        end
        X_ROW_I:    fixed_write(6'd40, {11'd0, state_q[9:5]});
        default: ;
      endcase

      // Whole-word ALU saves and fixed merges.  Address overrides feed the
      // following synchronous common action; they do not select an operand in
      // front of the arithmetic chain.
      case (action)
        SAVE44_R36: begin
          state_wd_override = 1'b1;
          state_wd_fixed = acc;
          state_ra_override = 1'b1;
          state_ra_word = 6'd36;
        end
        SAVE45_R39: begin
          state_wd_override = 1'b1;
          state_wd_fixed = acc;
          state_ra_override = 1'b1;
          state_ra_word = 6'd39;
        end
        SAVE44: begin
          state_wd_override = 1'b1;
          state_wd_fixed = acc;
        end
        MERGE_CTR_V_NR, MERGE_CTR_I_NR: begin
          state_wd_override = 1'b1;
          state_wd_fixed = {state_q[7:0], acc[7:0]};
        end
        MERGE_CTR_V_ROLL: begin
          state_wd_override = 1'b1;
          state_wd_fixed = {state_q[7:0], 8'd0};
          state_ra_override = 1'b1;
          state_ra_word = 6'd48;
        end
        MERGE_CTR_I_ROLL: begin
          state_wd_override = 1'b1;
          state_wd_fixed = {state_q[7:0], 8'd0};
          state_ra_override = 1'b1;
          state_ra_word = 6'd51;
        end
        PREV_V_PITCH: begin
          state_wd_override = 1'b1;
          state_wd_fixed = (state_q & 16'hf03f)
                         | {4'd0, state_q[5:0], 6'd0};
          state_ra_override = 1'b1;
          state_ra_word = 6'd49;
        end
        PREV_V_VOL: begin
          state_wd_override = 1'b1;
          state_wd_fixed = (state_q & 16'hfe3f)
                         | {7'd0, state_q[2:0], 6'd0};
          state_ra_override = 1'b1;
          state_ra_word = 6'd54;
        end
        MERGE_ROW_V: begin
          state_wd_override = 1'b1;
          state_wd_fixed = {state_q[15:5], acc[4:0]};
          state_ra_override = 1'b1;
          state_ra_word = 6'd44;
        end
        MERGE_LEN_V: begin
          state_wd_override = 1'b1;
          state_wd_fixed = {state_q[15:14], acc[5:0], state_q[7:0]};
        end
        PREV_I_PITCH: begin
          state_wd_override = 1'b1;
          state_wd_fixed = {state_q[15:6], acc[13:8]};
          state_ra_override = 1'b1;
          state_ra_word = 6'd50;
        end
        PREV_I_VOL: begin
          state_wd_override = 1'b1;
          state_wd_fixed = {state_q[15:12], acc[15:13], state_q[8:0]};
          state_ra_override = 1'b1;
          state_ra_word = 6'd50;
        end
        MERGE_ROW_I: begin
          state_wd_override = 1'b1;
          state_wd_fixed = {state_q[15:10], acc[4:0], state_q[4:0]};
        end
        INS_DONE: begin
          state_wd_override = 1'b1;
          state_wd_fixed = state_q | 16'h8000;
        end
        default: ;
      endcase

      // These outputs are sequencer effects. The sequencer's arbitrated
      // always_ff applies them so boundary clears retain explicit same-edge
      // nonblocking-assignment priority.
      if (action == VOICE_STOP) begin
        voice_stop = 1'b1;
        cpz_we = 1'b1;
        cpz_next = 1'b1;
      end else if (action == SKIP_CPZ) begin
        cpz_we = 1'b1;
        cpz_next = !playing;
      end
    end
  end

endmodule

`endif
