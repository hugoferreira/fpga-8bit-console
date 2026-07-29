// PSG shared declarations: the constants and record layouts that more than
// one of the psg_* submodules has to agree on.
//
// Everything here is compilation-unit scope ($unit), included ONCE from
// psg.sv above the module set, so `psg_seq`, `psg_walk` and `psg_state_mem`
// read the same numbers from the same place instead of each carrying a copy
// that can drift. The alternative - a localparam block re-included inside
// every module - cannot be include-guarded (the second module would get
// nothing), and a proper `psg_pkg` package buys namespacing this file set
// does not yet need (design.md, open questions).
//
// Nothing parameter-dependent belongs here: PLOSC/PWORK/PFOLD/PSTOR/PLAST
// are functions of REALTIME_PREVIEW and stay with the modules that take it.
`ifndef PSG_COMMON_SVH
`define PSG_COMMON_SVH

// ---- playback slots -------------------------------------------------
// Four public channels over EIGHT playback slots: slot c is channel c's
// foreground effect, slot 4+c is what the song scheduled there. See the
// commentary at psg.sv's channel-state section for why both run at once.
localparam int PSG_NV  = 8;              // playback slots
localparam int PSG_VW  = 3;              // bits to index one
localparam int PSG_NCH = 4;              // public channels

// Slot v carries music iff v >= NCH. Was a register (`music_owned`) back
// when any slot could be either; the fixed pairing makes it a wire.
function automatic bit is_mus(input logic [PSG_VW-1:0] v);
  is_mus = v[2];
endfunction

// The slot a channel is actually heard on: its foreground effect when that
// is playing, otherwise the song underneath. The playing bits come in as an
// explicit packed argument rather than being read from an enclosing scope,
// so the CPU read mux and the `dbg` view can live in the top level while
// the storage lives in the sequencer.
function automatic logic [PSG_VW-1:0] aud_sl(input logic [1:0] ch,
                                             input logic [PSG_NV-1:0] play);
  aud_sl = play[{1'b0, ch}] ? {1'b0, ch} : {1'b1, ch};
endfunction

// An SFX record's base byte address in audio RAM: 256 + n*68, as two shifts
// and an add. Every consumer recomputes it from its own id rather than
// storing it: 13 bits per slot of state plus the mux to read them costs more
// than the adders. Shared because the sequencer addresses records by channel
// and instrument id, and the walk addresses wavetables by sound id.
function automatic logic [12:0] rec_base(input logic [5:0] n);
  rec_base = 13'd256 + {1'b0, n, 6'b0} + {5'b0, n, 2'b0};
endfunction

// tz(v / 2^k): the proven biased arithmetic shift (psg_hw_forms tzpow).
// Shared because both the wave layer's composition scaling and the walk's
// wavetable lerp close their truncation with it.
function automatic logic signed [17:0] tzs(
    input logic signed [17:0] v, input logic [1:0] k);
  tzs = (v + (v[17] ? $signed((18'sd1 <<< k) - 18'sd1) : 18'sd0)) >>> k;
endfunction

// ---- the scheduled record store's layout ----------------------------
//   word  0.. 9  tick/note state
//   word 10..23  oscillator state
//   word 24..27  sounding parameter bank 0
//   word 28..31  sounding parameter bank 1
//   word 32      the sequencer's note position
localparam int PSG_TREC = 10;                        // tick/note words per slot
localparam int PSG_SPAR = 4;                         // sounding parameter words
localparam int PSG_SOSC = 14;                        // oscillator-state words
// 64 words per slot, not 32: the tick/oscillator/parameter families filled
// the first 32 exactly, and the per-slot arrays need a home. REVERB=0
// leaves the blocks for it - this costs one.
localparam int PSG_VSTR = 64;                        // all records for one slot
localparam int PSG_VADR = PSG_VW + 6;
localparam logic [5:0] PSG_V_OSC  = 6'd10;
localparam logic [5:0] PSG_V_PAR0 = 6'd24;
localparam logic [5:0] PSG_V_PAR1 = 6'd28;
localparam logic [5:0] PSG_V_SEQ  = 6'd32;

// ---- mirrored record field lists ------------------------------------
// Each list is spelled ONCE and expanded by both halves of its mirror pair,
// so a pack and its unpack cannot drift apart. They name the owning module's
// working registers, so they only expand inside that module: PSG_REC_* in
// the sequencer (vwdata pack / V_LD unpack), PSG_OSC_* in the walk (sosc_wd
// pack, the pph load case, and word 14's late dampen write-back).
//
// Register-resident record words 3/4/5/9. Flow-owned words never appear
// here: V_ST does not store them and V_LD does not unpack them (word 8's
// ins_pitch read-copy is the one exception, refreshed on load).
`define PSG_REC_W3 {w_ins_bass, w_cur_wave, w_prev_pitch, w_cur_pitch}
`define PSG_REC_W4 {w_ins_done, w_bf_rev, w_bf_det, w_bf_buzz, w_bf_noiz, \
                    w_prev_vol, w_cur_fx, w_cur_vol}
`define PSG_REC_W5 {w_ins_vol, w_ins_wave, w_ins_row, w_ins_id, w_bf_damp}
`define PSG_REC_W9 {w_ins_wt, w_ins_on, w_ins_prev_vol, w_ins_fx, \
                    w_ins_prev_pitch}

// Oscillator-record words 14/17/22.
`define PSG_OSC_W14 {s_lp[16], old_mode_r, s_brown}
`define PSG_OSC_W17 {bl_cnt, old_q0[16:8]}
`define PSG_OSC_W22 {old_alt_r, last_alt_r, last_mode_r, s_old_wave, \
                     s_last_G[7:0]}

`endif
