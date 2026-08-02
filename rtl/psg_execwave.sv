// Fixed owner-zero waveform and wavetable cadence for the shared PSG executor.
//
// The synchronous state output is the phase-context stream: existing HOLD
// instructions prime current phase word 10, W0 primes phase2 word 12, and W1
// primes old-phase word 16.  Only old-q, fixed wave controls, and one six-bit
// phase index survive in flops.  Wave and ARAM results remain streaming
// events; this module owns no result register or scratch-memory write.

`timescale 1ns/1ps

`ifndef PSG_EXECWAVE_SV
`define PSG_EXECWAVE_SV

module psg_execwave(input  logic        clk,
                    input  logic        active,
                    input  logic        hold,
                    input  logic        owner,
                    input  logic [6:0]  action,
                    input  logic [15:0] state_q,
                    input  logic        play,

                    output logic        state_ra_override,
                    output logic [5:0]  state_ra_word,

                    output logic        wave_ce,
                    output logic        wave_issue,
                    output logic        wave_take,
                    output logic [15:0] wave_phase,
                    output logic [2:0]  wave_sel,
                    output logic        wave_alt,
                    output logic        wave_secondary,

                    output logic        aram_req,
                    output logic [2:0]  aram_id,
                    output logic [5:0]  aram_index,
                    output logic        aram_adjacent,
                    output logic        aram_take);

  localparam logic [6:0]
    LOAD_OSC_11 = 7'h02,
    LOAD_OSC_14 = 7'h05,
    LOAD_OSC_17 = 7'h08,
    LOAD_OSC_22 = 7'h0d,
    LOAD_PAR_1  = 7'h11,
    LOAD_PAR_2  = 7'h12,
    CAP_W0      = 7'h22,
    CAP_W1      = 7'h23,
    CAP_W2      = 7'h24,
    CAP_W3      = 7'h25,
    CAP_W4      = 7'h26,
    CAP_W5      = 7'h27,
    HOLD_ACTION = 7'h70;

  // Exactly 38 bits of service-owned context.
  logic [15:0] old_q;
  logic [5:0]  phase_index_hold;
  logic [2:0]  snd_id;
  logic        snd_wt;
  logic [2:0]  snd_wave;
  logic [1:0]  snd_mode;
  logic        snd_alt;
  logic [2:0]  old_wave;
  logic [1:0]  old_mode;
  logic        old_alt;

  wire sample_step = active && !hold && !owner;
  wire at_w0 = sample_step && action == CAP_W0;
  wire at_w1 = sample_step && action == CAP_W1;
  wire at_w2 = sample_step && action == CAP_W2;
  wire at_w3 = sample_step && action == CAP_W3;
  wire at_w4 = sample_step && action == CAP_W4;
  wire at_w5 = sample_step && action == CAP_W5;

  function automatic logic [15:0] phase_view(
      input logic [15:0] raw,
      input logic [2:0] wave,
      input logic [1:0] mode,
      input logic wt);
    begin
      if (!wt && (wave == 3'd0 || wave == 3'd7))
        phase_view = raw;
      else if (mode == 2'd2)
        phase_view = {raw[14:0], 1'b0};
      else
        phase_view = raw;
    end
  endfunction

  wire [15:0] current_q = phase_view(state_q, snd_wave, snd_mode, snd_wt);
  wire [15:0] old_q_view = phase_view(old_q, old_wave, old_mode, 1'b0);

  // The LOAD actions consume the preceding synchronous state word.  No reset
  // is required: every field is overwritten before the first W0 of a slot.
  always_ff @(posedge clk) begin
    if (sample_step) begin
      case (action)
        LOAD_OSC_11: old_q[7:0] <= state_q[7:0];
        LOAD_OSC_14: old_mode <= state_q[14:13];
        LOAD_OSC_17: old_q[15:8] <= state_q[7:0];
        LOAD_OSC_22: begin
          old_alt <= state_q[14];
          old_wave <= state_q[10:8];
        end
        LOAD_PAR_1: begin
          snd_id <= state_q[14:12];
          snd_wt <= state_q[11];
          snd_wave <= state_q[10:8];
        end
        LOAD_PAR_2: begin
          snd_mode <= state_q[9:8];
          snd_alt <= state_q[7];
        end
        default: ;
      endcase

      if (action == CAP_W0)
        phase_index_hold <= state_q[15:10];
      else if (action == CAP_W1)
        phase_index_hold <= current_q[15:10];
    end
  end

  always_comb begin
    state_ra_override = 1'b0;
    state_ra_word = 6'd0;

    // These are physical read primes, not new semantic READ instructions.
    if (sample_step && action == HOLD_ACTION) begin
      state_ra_override = 1'b1;
      state_ra_word = 6'd10;
    end else if (at_w0) begin
      state_ra_override = 1'b1;
      state_ra_word = 6'd12;
    end else if (at_w1) begin
      state_ra_override = 1'b1;
      state_ra_word = 6'd16;
    end

    wave_ce = !snd_wt && (at_w0 || at_w1 || at_w2 || at_w3 || at_w4);
    wave_issue = !snd_wt && (at_w0 || at_w1 || at_w2 || at_w3);
    wave_take = !snd_wt && (at_w2 || at_w3 || at_w4 || at_w5);
    wave_phase = state_q;
    wave_sel = snd_wave;
    wave_alt = snd_alt;
    wave_secondary = 1'b0;
    if (at_w1) begin
      wave_phase = current_q;
      wave_secondary = 1'b1;
    end else if (at_w2) begin
      wave_phase = state_q;
      wave_sel = old_wave;
      wave_alt = old_alt;
    end else if (at_w3) begin
      wave_phase = old_q_view;
      wave_sel = old_wave;
      wave_alt = old_alt;
      wave_secondary = 1'b1;
    end

    aram_id = snd_id;
    aram_index = state_q[15:10];
    if (at_w1 || at_w2 || at_w3)
      aram_index = phase_index_hold;
    aram_adjacent = at_w1 || at_w3;
    aram_req = snd_wt && play && (at_w0 || at_w1 || at_w2 || at_w3);
    aram_take = snd_wt && play && (at_w1 || at_w2 || at_w3 || at_w4);
  end

endmodule

`endif
