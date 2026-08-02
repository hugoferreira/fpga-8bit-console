// Synchronous state-memory movement for the shared PSG executor.
//
// R.84E lowers the complete tick record load/store stream.  Each load action
// consumes the preceding synchronous read into a fixed scratch word.  The
// final publication/copy action primes one scratch read, then the store stream
// reads the next source while the current source is written back.  Addresses
// are fixed action metadata, not a general register index.

`timescale 1ns/1ps

`ifndef PSG_EXECMOVE_SV
`define PSG_EXECMOVE_SV

module psg_execmove(input  logic       active,
                    input  logic       hold,
                    input  logic       owner,
                    input  logic [2:0] op,
                    input  logic [6:0] action,

                    output logic       state_ra_override,
                    output logic [5:0] state_ra_word,
                    output logic       state_we_extra,
                    output logic [5:0] state_wa_word,
                    output logic       copy_state_q);

  localparam logic [2:0] OP_WRITE = 3'd1;
  localparam logic [6:0]
    K_ADV = 7'h40,
    P_W3  = 7'h56,
    PC3   = 7'h5a;

  wire tick = active && !hold && owner;
  wire [2:0] family = action[6:4];
  wire [3:0] subop = action[3:0];

  always_comb begin
    state_ra_override = 1'b0;
    state_ra_word = 6'd0;
    state_we_extra = 1'b0;
    state_wa_word = 6'd0;
    copy_state_q = 1'b0;

    if (tick) begin
      // V_LD0 primes persistent word 3.  V_LD1..7 consume words
      // 3,4,5,8,9,26,32; K_ADV consumes the final repeated word 26.
      if (family == 3'd0 && subop >= 4'd1 && subop <= 4'd7) begin
        state_we_extra = 1'b1;
        state_wa_word = 6'(47 + subop);
        copy_state_q = 1'b1;
      end else if (action == K_ADV) begin
        state_we_extra = 1'b1;
        state_wa_word = 6'd53;
        copy_state_q = 1'b1;
      end

      // P_W3 and PC3 are the two immediate predecessors of V_ST0.  Their
      // current state_q value has already been consumed, so both can issue
      // scratch word 48 without adding a hold clock.  V_ST0..3 write the
      // current source while reading the next; V_ST4 commits word 54.
      if (action == P_W3 || action == PC3) begin
        state_ra_override = 1'b1;
        state_ra_word = 6'd48;
      end else if (op == OP_WRITE && family == 3'd0
                   && subop >= 4'd8 && subop <= 4'd12) begin
        copy_state_q = 1'b1;
        case (subop)
          4'd8:  begin state_ra_override = 1'b1; state_ra_word = 6'd49; end
          4'd9:  begin state_ra_override = 1'b1; state_ra_word = 6'd50; end
          4'd10: begin state_ra_override = 1'b1; state_ra_word = 6'd52; end
          4'd11: begin state_ra_override = 1'b1; state_ra_word = 6'd54; end
          default: ;
        endcase
      end
    end
  end

endmodule

`endif
