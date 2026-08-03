// Shared PSG constants, address helpers, and packed record layouts.
// This header is included once at compilation-unit scope by psg.sv.

`ifndef PSG_COMMON_SVH
`define PSG_COMMON_SVH

// Public geometry: eight playback slots, a three-bit slot index, and four
// audible channel pairs.
localparam int PSG_NV  = 8;
localparam int PSG_VW  = 3;
localparam int PSG_NCH = 4;

// Slots 0..3 are foreground SFX; slots 4..7 are the corresponding music
// voices. A foreground voice masks, but does not stop, its music voice.
function automatic bit is_mus(input logic [PSG_VW-1:0] v);
  is_mus = v[2];
endfunction

function automatic logic [PSG_VW-1:0] aud_sl(input logic [1:0] ch,
                                             input logic [PSG_NV-1:0] play);
  aud_sl = play[{1'b0, ch}] ? {1'b0, ch} : {1'b1, ch};
endfunction

// Audio RAM contains 256 pattern bytes followed by 64 68-byte SFX records.
function automatic logic [12:0] rec_base(input logic [5:0] n);
  rec_base = 13'd256 + {1'b0, n, 6'b0} + {5'b0, n, 2'b0};
endfunction

// Signed division by 2^k truncated toward zero.
function automatic logic signed [17:0] tzs(
    input logic signed [17:0] v, input logic [1:0] k);
  logic signed [17:0] q;
  logic rem_nz;
  begin
    q = v >>> k;
    case (k)
      2'd0: rem_nz = 1'b0;
      2'd1: rem_nz = v[0];
      2'd2: rem_nz = |v[1:0];
      default: rem_nz = |v[2:0];
    endcase
    tzs = q + $signed({17'b0, v[17] && rem_nz});
  end
endfunction

// Per-slot state-memory map:
//   0..9 tick state, 10..23 oscillator state, 24..31 double-buffered
//   sounding parameters, 32 current note row plus clear token. Each slot
//   reserves 64 words.
localparam int PSG_TREC = 10;
localparam int PSG_SPAR = 4;
localparam int PSG_SOSC = 14;

localparam int PSG_VSTR = 64;
localparam int PSG_VADR = PSG_VW + 6;
localparam logic [5:0] PSG_V_OSC  = 6'd10;
localparam logic [5:0] PSG_V_PAR0 = 6'd24;
localparam logic [5:0] PSG_V_PAR1 = 6'd28;
localparam logic [5:0] PSG_V_SEQ  = 6'd32;

// Packed record fields are listed most-significant first. The macro suffix is
// the per-slot state-memory word written or read by the sequencer.
`define PSG_REC_W3 {w_ins_fx[0], w_cur_wave, w_prev_pitch, w_cur_pitch}
`define PSG_REC_W4 {w_ins_done, w_bf_rev, w_bf_det, w_bf_buzz, w_bf_noiz, \
                    w_prev_vol, w_cur_fx, w_cur_vol}
`define PSG_REC_W5 {w_ins_vol, w_ins_wave, w_ins_row, w_ins_id, w_bf_damp}
`define PSG_REC_W9 {w_ins_wt, w_ins_on, w_ins_prev_vol, w_ins_fx, \
                    w_ins_prev_pitch}

// Oscillator-record packs follow the same convention: the suffix is the
// per-slot state-memory word used by the sample walk.
`define PSG_OSC_W14 {s_lp[16], old_mode_r, s_brown}
`define PSG_OSC_W17 {bl_cnt, old_q0[16:8]}
`define PSG_OSC_W22 {old_alt_r, last_alt_r, last_mode_r, s_old_wave, \
                     s_last_G[7:0]}

`endif
