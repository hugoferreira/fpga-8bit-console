// PSG v2: a PICO-8-equivalent audio chip.
//
// The chip holds PICO-8's audio RAM image verbatim: 64 music patterns
// (PICO-8 $3100-$31FF, 4 bytes each) and 64 SFX records ($3200-$42FF,
// 68 bytes each: 32 x 16-bit notes {custom[15], fx[14:12], vol[11:9],
// wave[8:6], pitch[5:0]}, then filter/speed/loop-start/loop-end). Cart
// bytes upload unchanged through the auto-increment port, which takes
// PICO-8 addresses.
//
// Timing is PICO-8's: a fractional divider derives a 22050 Hz virtual
// sample rate from CLK_HZ, and a sequencer tick fires every 183 samples
// (~120.49 Hz). An SFX row lasts `speed` ticks. Loop semantics follow the
// record: loop rows [start,end) when start < end; when end = 0 and
// start > 0, start is the SFX length in rows; else 32 rows and stop.
//
// Synthesis: 8 waveforms (four non-trivial shapes from a generated wave
// ROM, exact square/pulse phase thresholds, pitched sample-and-hold LFSR
// noise and dual-oscillator phaser) and all 8 note effects evaluated per
// tick (slide, vibrato, drop, fade in/out, fast/slow arpeggio). Channels
// are serialized through one datapath between samples; the mix clips
// PICO-8-style (one full-volume triangle = half scale).
//
// A note with bit 15 set plays through a custom instrument: SFX 0-7,
// picked by the note's waveform field, runs as a second playhead on the
// channel. Its row supplies the waveform, its pitch adds to the note's
// relative to pitch 24 (C-2), its volume multiplies the note's and its
// filter byte is folded into the channel's filters. The playhead is only
// retriggered when the note's pitch changes, the previous note's volume
// was 0, or the note carries effect 3 (which means "retrigger", not
// "drop"). An instrument SFX whose loop-start byte has bit 7 set is a
// 64-sample wavetable read straight out of audio RAM instead, an octave
// down when its speed byte has bit 0 set.
//
// The music sequencer is hardware: writing a pattern number fetches the
// 4 pattern bytes, launches the enabled channels' SFX, ends the pattern
// by the left-most non-looping channel rule, and follows the loop-start /
// loop-back / stop flag bits with zero CPU work.
//
// Registers (byte window at $4100):
//   $00/$01 upload address lo/hi (PICO-8 address), $02 data (auto-inc)
//   $03 (read) playing bits [3:0], music playing bit 7
//   $10+c write: play SFX n (0-63) on channel c; $80 stops the channel,
//                $81 releases it from looping
//         read: {playing, 2'b0, row}
//   $14+c write: start row for the next trigger on channel c (auto-clears)
//         read: {playing, 1'b0, sfx number}
//   $18+c write: rows to play for the next trigger, 0 = whole record
//                (auto-clears; a nonzero length overrides the loop points)
//   $20 write: start music at pattern m (0-63); $80 stops music
//       read: current pattern
//   $21 channels reserved for music (advisory: the CPU consults it when
//       auto-picking a channel for an SFX; reset $00)
//   $22 music fade length in 16 ms units, applied to the next music start
//       (fade in) or stop (fade out), then cleared

// Slot counts, the scheduled record's word layout and the audible-slot rule,
// at compilation-unit scope so the functional submodules share one copy.
`include "psg_common.svh"

// The functional submodules. Every consumer of the PSG composes it with a
// single `include "psg.sv"` (chip.sv, target_psg.sv), so the module set has
// to arrive through this file; each is include-guarded, so listing one
// explicitly alongside psg.sv stays harmless.
`include "psg_timing.sv"
`include "psg_aram.sv"
`include "psg_mulsvc.sv"
`include "psg_divsvc.sv"
`include "psg_state_mem.sv"
`include "psg_wave.sv"
`include "psg_walk.sv"

module psg #(parameter CLK_HZ = 32'd3_506_580, parameter REVERB = 1,
             parameter REALTIME_PREVIEW = 0, parameter DBG_PORT = 1)
          (input bit clk, input bit reset,
           input bit cs, input bit rw, input logic [7:0] addr, input logic [7:0] di,
           output logic [7:0] dout,
           output logic signed [15:0] pcm,
           // Verification only: per-channel state for the simulator's
           // --psg-trace. Nothing on hardware reads it, so DBG_PORT=0
           // removes the cone that drives it rather than relying on the
           // synthesiser to notice the port is unconnected - which also
           // stops it constraining what the per-slot state may become
           // (it is the only reader that ever wanted four slots at once).
           // Exists because there was no way to tell whether an audio
           // fidelity complaint was allocation, sequencing or synthesis
           // without seeing inside.
           output logic [63:0] dbg);

  // Every waveform is computed (adopt-pico8-integer-audio 2.2): the wave
  // ROM retires. The constants block keeps the pitch increments; words
  // 64..255 stay reserved for microcode and scheduled tables.
  logic [15:0] crom[0:255];
  initial begin
    $readmemh("./rtl/psg_const.hex", crom);
  end

  // ------------------------------------------------------------------
  // Timing: 22050 Hz virtual sample rate, sequencer tick every 183
  // ------------------------------------------------------------------
  // All five strobes come from u_timing (rtl/psg_timing.sv), which owns the
  // fractional divider and the sample counter.
  //
  // pre_tick fires one sample before tick_en (task 3.0): the tick program
  // EVALUATES during the preceding sample interval into the inactive bank,
  // and the boundary edge itself only flips spar_bank. That hands the tick
  // microprogram a full sample interval instead of sharing the boundary
  // sample's 1,275 clocks with synthesis. A CPU write landing inside the
  // pre-run window is observed one tick evaluation later than before -
  // accepted deliberately, see design section 3.
  //
  // tick_en has no RTL consumer: the sequencer runs off pre_tick and
  // tick_en_d. It stays because psg_tb measures the tick window with it.
  logic        sample_en;
  logic [7:0]  scnt;
  logic        tick_en, tick_en_d;
  logic        pre_tick;

  psg_timing #(.CLK_HZ(CLK_HZ)) u_timing(
    .clk(clk), .reset(reset),
    .sample_en(sample_en), .tick_en(tick_en), .tick_en_d(tick_en_d),
    .pre_tick(pre_tick), .scnt(scnt));

  // ------------------------------------------------------------------
  // Channel state
  // ------------------------------------------------------------------
  // Four public channels over EIGHT playback slots, which is what PICO-8
  // actually is (pico8-psg-re.md, "Observable behavior and compatibility
  // boundary"). Each channel c owns two independent playback states:
  //
  //   slot c     foreground - what sfx(n, c) plays
  //   slot 4+c   music      - what the pattern scheduled on channel c
  //
  // Both advance every tick. Only one is audible:
  //
  //   audible[c] = foreground[c] if it is playing, else music[c]
  //
  // The muted music slot keeps running, so when the sound effect ends the song
  // reappears *at its current position* rather than resuming where it was
  // interrupted. That is the whole reason the real thing keeps two records per
  // channel, and it is why this file no longer has borrow-and-restore.
  //
  // Sixteen slots would be wrong, not merely wasteful: PICO-8's upper eight
  // belong to the generic sound-object player and to an alternate mixer mode
  // that normal startup disables. The reference's own compatibility table
  // lists slots 8-15 as NOT required of a classic-only replica.
  //
  // A slot's channel is `v[1:0]` and "is this the music slot" is `v[2]`, both
  // by construction, so neither needs storage.
  // PSG_NV / PSG_VW / PSG_NCH, is_mus() and aud_sl() live in psg_common.svh:
  // the sequencer owns the storage, but the walk and the CPU read mux both
  // need the numbers and the audible-slot rule.
  logic        playing[0:PSG_NV-1];
  // The packed view of `playing`, and the only form that crosses a module
  // boundary: an unpacked array port would be one, and this design has none.
  // Bit v is slot v, so `play_bits[pc_ch]` and `playing[pc_ch]` are the same
  // flop read two ways.
  wire [PSG_NV-1:0] play_bits = {playing[7], playing[6], playing[5], playing[4],
                                 playing[3], playing[2], playing[1], playing[0]};
  logic [5:0]  sfx_id[0:PSG_NV-1];
  logic [4:0]  w_row;        // this visit's note position
  // eff_vol used to be an addressable array because the music-stop, fade-out
  // and channel-stop paths zeroed it for slots other than the one being walked.
  // Those writes were redundant: every one of them also clears `playing`, and
  // the mixer leaf is gated on playing (mx_play/mx_aud), so a stale level on a
  // stopped slot is never heard. Dropping them lets the level ride the spar
  // record the synthesis walk already loads, at no extra cycles - measured 141
  // LC of flops and read mux.
  // The slot a CPU channel register acts on: the channel's foreground slot,
  // which is slot c. Spelled out because the arrays are PSG_NV deep and addr is a
  // 2-bit channel - an implicit widening here is the kind of thing that only
  // shows up as a warning in one of the three builds.
  wire [PSG_VW-1:0] fg_sl = {1'b0, addr[1:0]};

  // Trigger parameters latched for the next trigger on a channel, and the
  // resulting play limits (sfx(n, ch, offset, length) / release from loop)
  // Pending trigger parameters. These are addressed by CHANNEL, not by slot:
  // sfx(n, ch, offset, length) names a channel, and only a foreground slot can
  // ever carry a pending request - a music slot is scheduled by the pattern and
  // never has an offset or a length. So four sets suffice however many slots
  // exist, and holding eight was holding four of them permanently at zero.
  // The audible-slot report behind $10-$17 and the trace port. PICO-8
  // specifies stat(46..53) as "a history of mixer state at each tick to
  // give a higher resolution estimate of the currently audible state" -
  // a sampled view, not a live probe - so refreshing it as each slot's
  // visit ends is faithful, and it is what lets row leave the flops.
  logic [4:0]  aud_row[0:PSG_NCH-1];
  logic [4:0]  trg_row[0:PSG_NCH-1];
  // Borrow-and-restore (`sav_sfx`/`sav_row`/`sav_valid`) is gone. It saved the
  // displaced music SFX and relaunched it at the row it was interrupted on,
  // which is the one thing PICO-8 does not do: the hidden music slot keeps
  // advancing while inaudible, so the song comes back where it *now* is. The
  // foreground/music pairing gives that for free and cannot desynchronise the
  // song, so there is nothing left to save.
  logic [5:0]  trg_len[0:PSG_NCH-1];
  logic        released[0:PSG_NV-1];

  // ------------------------------------------------------------------
  // Per-slot note and instrument state: a BRAM register file
  // ------------------------------------------------------------------
  // These 154 bits per slot are touched by exactly one thing - the per-tick
  // sequencer walk - and only ever for the slot it is currently visiting. Held
  // as `name[PSG_NV]` arrays they cost a flop per bit AND an PSG_NV:1 mux per read, and
  // the muxes are the larger half: measured across PSG_NV=2/4/8/16 the marginal
  // cost of a slot was 379 LUT4, against 336 bits of state.
  //
  // So the walk loads the visited slot's record into working registers, works
  // on those, and writes it back on the way out. The array becomes one memory
  // with a synchronous read - which is what makes yosys infer an SB_RAM40_4K
  // rather than a wall of LUTs - and the per-slot cost drops to roughly zero.
  //
  // The walk has 183 samples of slack between ticks, so the ~21 extra cycles a
  // visit now costs are free. That is why THIS half moves and the per-sample
  // synthesis state does not: the synthesis walk runs every sample and has no
  // such slack.
  //
  // Reset: a block RAM cannot be cleared the way an array of flops can, so the
  // record is garbage until the slot's first trigger. That is safe, and not by
  // luck - K_ADV reads nothing from the record unless `trig_req` or `playing`
  // is set, both of which are flops that reset to 0, and a trigger runs
  // T_FL..T_LD which writes every field the note path can reach before it is
  // read. The one field that would be dangerous, `ins_on`, is written by T_FL.
  // The record layout itself (PSG_TREC/PSG_SPAR/PSG_SOSC/PSG_VREC/PSG_VSTR/
  // PSG_VADR and the PSG_V_* word bases) is in psg_common.svh: the store,
  // the sequencer and the walk all address it and none of them may hold a
  // private copy. The schedule constants below are parameter-dependent and
  // stay here.
  //
  // PSG_V_SEQ is the sequencer's per-slot note position. An array of these
  // is eight flops sharing one D behind per-slot enables, so every one of
  // them is unpackable AND the decode rides along; as a record word it is a
  // working register loaded at V_LD and stored at V_ST, like every other
  // family section 3 moved.
  localparam int PLOSC = REALTIME_PREVIEW ? 7  : PSG_SOSC;
  localparam int PWORK = REALTIME_PREVIEW ? 12 : 19;
  localparam int PFOLD = REALTIME_PREVIEW ? 23 : 108;
  localparam int PSTOR = REALTIME_PREVIEW ? 16 : 52;
  localparam int PLAST = REALTIME_PREVIEW ? 23 : 108;

  // The scheduled record store is u_state (rtl/psg_state_mem.sv), which owns
  // the memory and the two-owner port priority. The sequencer writes the
  // inactive parameter bank and flips spar_bank only after the complete
  // eight-slot walk, so synthesis never observes a partly published tick.
  wire  [15:0] state_q;
  logic        spar_bank;
  // this trigger pass writes the bank a tick pass already staged
  logic        join_stage;
  logic [15:0] vwdata;
  logic [3:0]  vcnt;                           // word within the record
  logic [6:0]  pph;                            // sample micro-phase

  // The working copy: the record of the slot the walk is visiting. The
  // counter/loop family (tcnt/fcnt, sp, lps/lpe, play_len, both banks) has
  // no working registers any more: those fields are flow-owned record words
  // (0..2 and 6..8) that the tick engine reads, modifies and writes in
  // place. Only identity and filter fields remain register-resident.
  logic [5:0]  w_cur_pitch, w_prev_pitch;
  logic [2:0]  w_cur_wave, w_cur_vol, w_cur_fx, w_prev_vol;
  logic        w_bf_noiz, w_bf_buzz;
  logic [1:0]  w_bf_det, w_bf_rev, w_bf_damp;
  logic        w_ins_on, w_ins_wt, w_ins_bass, w_ins_done;
  logic [2:0]  w_ins_id;
  logic [4:0]  w_ins_row;
  logic [5:0]  w_ins_pitch, w_ins_prev_pitch;
  logic [2:0]  w_ins_wave, w_ins_vol, w_ins_fx, w_ins_prev_vol;

  // The tick engine (3.1): two word registers, a 9-bit compare unit and
  // flags. acc/wrd are datapath (no reset; every sequence loads them before
  // reading them). One physical write site: the engine's stores go through
  // the same scheduled state-memory port as V_ST, with the word address and
  // data selected before it.
  logic [15:0] acc, wrd;
  logic        abank;                // 0 = note words 0..2, 1 = ins words 6..8
  logic        froll;                // fcnt+1 >= sp: the row rolls over
  logic        ge_lpe;               // row+1 >= lpe
  // Effect staging: the family fields the effect path consumes, deposited
  // by the EFFSEL steps after the note/instrument dispatch settles which
  // bank supplies the effect. Replaces the e_sp/e_tcnt/e_fcnt bank muxes.
  logic [7:0]  eff_sp, eff_fcnt;
  logic [4:0]  eff_tcnt;

  // The PSG_REC_W* field lists (record words 3/4/5/9) are in psg_common.svh
  // with the rest of the record layout. The always_comb form below MUST stay
  // - not a function called from a continuous assign: iverilog does not infer
  // sensitivity to signals a function reads internally, so
  // `assign vwdata = vpack(vcnt)` held 0 forever and every store wrote zeros.
  always_comb begin
    case (vcnt)
      4'd0: vwdata = `PSG_REC_W3;
      4'd1: vwdata = `PSG_REC_W4;
      4'd2: vwdata = `PSG_REC_W5;
      4'd4: vwdata = {11'b0, w_row};
      default: vwdata = {2'b0, `PSG_REC_W9};
    endcase
  end

  // ------------------------------------------------------------------
  // Per-slot synthesis state: working copies of the scheduled store
  // ------------------------------------------------------------------

  // The sequencer's working copy of the parameters: what it is building for the
  // slot it is visiting, published to the inactive bank when the visit ends.
  // The former w_eff_inc/w_snd_*/w_eff_vol publication staging is gone:
  // arp_r, vol_r and the final product hold the results until the P_W
  // steps write the bank words directly.
  logic        w_ch_noiz, w_ch_buzz;
  logic [1:0]  w_ch_det, w_ch_rev, w_ch_damp;


  // Per-slot filter state: bf_* comes from the played SFX's filter byte at
  // trigger and lives in the sequencer's record; ch_* is that folded together
  // with the instrument's and lives in the active parameter bank.

  logic [PSG_NV-1:0] trig_req;
  logic [PSG_NV-1:0] clr_tog;   // toggled to ask the synth walk to reset lp/brown
  // Deferred stops (task 3.0 completed for arbitrary pre-run depth): the
  // tick program mutates playing[] while it evaluates, but the render must
  // observe those clears exactly when it did before the pre-run. Note-end,
  // length-stop and fade-out stops were visible from the BOUNDARY sample
  // (class 1, applied at tick_en); the music-flow stops ran after V_ST
  // behind the frozen boundary render and were visible one sample later
  // (class 2, applied at the scnt==1 sample). A trigger overrides both.
  logic [PSG_NV-1:0] pend_stop, pend_stop2;
  logic          ml_cpu;    // ML_STOP reached from a CPU launch, not the song

  // Music state
  logic        mus_playing, mus_launch;
  logic [5:0]  mus_pat;
  logic [3:0]  mus_mask;
  logic [PSG_NV-1:0] launched;
  logic        tch_seen, ptick_seen, f_lb, f_stop;
  // A pattern's length in ticks, fixed when the pattern launches, and the
  // tick position within it. PICO-8 paces a song the same way - the song
  // scheduler records the pattern length and a global pattern-tick position -
  // rather than asking any one voice whether it is still playing.
  logic [12:0] pticks, ptick_tgt;
  logic        ptick_pend;           // w_sp * pat_rows in flight on m service

  // Music fade: an 8-bit gain ramped at tick rate. fade_len is in 16 ms
  // units and a tick is ~8.3 ms, so stepping a 16-bit accumulator by
  // 4096/(fade_len/8) each tick overflows within a few percent of the
  // requested time (the length quantises to 128 ms, finer than a fade needs)
  // without needing a divider or a second port on the reciprocal table.
  logic [7:0]  fade_len, mus_gain;
  logic [1:0]  fade_dir;             // 0 none, 1 fading in, 2 fading out
  logic [15:0] fade_acc;
  logic [12:0] fade_step;
  function automatic logic [12:0] fstep(input logic [4:0] n);  // 4096/n
    case (n)
      5'd1:  fstep = 13'd4096;  5'd2:  fstep = 13'd2048;
      5'd3:  fstep = 13'd1365;  5'd4:  fstep = 13'd1024;
      5'd5:  fstep = 13'd819;   5'd6:  fstep = 13'd682;
      5'd7:  fstep = 13'd585;   5'd8:  fstep = 13'd512;
      5'd9:  fstep = 13'd455;   5'd10: fstep = 13'd409;
      5'd11: fstep = 13'd372;   5'd12: fstep = 13'd341;
      5'd13: fstep = 13'd315;   5'd14: fstep = 13'd292;
      5'd15: fstep = 13'd273;   5'd16: fstep = 13'd256;
      5'd17: fstep = 13'd240;   5'd18: fstep = 13'd227;
      5'd19: fstep = 13'd215;   5'd20: fstep = 13'd204;
      5'd21: fstep = 13'd195;   5'd22: fstep = 13'd186;
      5'd23: fstep = 13'd178;   5'd24: fstep = 13'd170;
      5'd25: fstep = 13'd163;   5'd26: fstep = 13'd157;
      5'd27: fstep = 13'd151;   5'd28: fstep = 13'd146;
      5'd29: fstep = 13'd141;   5'd30: fstep = 13'd136;
      5'd31: fstep = 13'd132;   default: fstep = 13'd8191;
    endcase
  endfunction

  // ------------------------------------------------------------------
  // Sequencer FSM (note fetch, per-tick effects, music flow control)
  // ------------------------------------------------------------------
  typedef enum logic [5:0] {
    S_IDLE,
    T_FL, T_SP, T_LS, T_LE, T_NL, T_NH, T_LD,
    K_ADV, K_NL, K_NH, K_LD, K_ARP, K_ARPC,
    K_PF0, K_FX,
    K_SL0, K_SL1, K_SL2, K_SL3, K_SL4, K_SL5, K_SL6, K_SL7, K_SL8,
    // The tick engine's advance sequence, one for both banks (abank picks
    // note words 0..2 or instrument words 6..8), and the effect staging
    // steps that replace the e_sp/e_tcnt/e_fcnt bank muxes.
    EA0, EA1, EA2, EA3, EA4, EA5,
    ES0, ES1, ES2,
    P_W0, P_W1, P_W2, P_W3,
    PC0, PC1, PC2, PC3,
    I_TR0, I_TR1, I_TR2, I_TR3, I_TR4, I_TW, I_NL, I_NH, I_LD,
    W_MUS,
    K_ROT, V_LD, V_ST,
    ML_STOP, ML_RD0, ML_L0, ML_L1, ML_L2, ML_L3,
    MS_RD, MS_CK
  } sst_t;
  sst_t sst;

  logic [PSG_VW-1:0] c;                  // voice being processed

  // The engine's one 9-bit compare unit: A+1 >= B, operands keyed by the
  // advance step. EA2 compares fcnt+1 against the speed landing in state_q;
  // EA4 compares row+1 against the loop end; EA5 against the end-of-record
  // bound. arow is the bank's row.
  wire [4:0] arow = abank ? w_ins_row : w_row;
  // acc holds {lpe, lps} from EA3 on: the end-of-record rule's bound.
  wire [7:0] ea_end_bound = (acc[7:0] != 0 && acc[15:8] == 0)
                              ? ((acc[7:0] < 8'd32) ? acc[7:0] : 8'd32)
                              : 8'd32;
  logic [7:0] ta_a, ta_b;
  always_comb begin
    case (sst)
      EA2:     begin ta_a = acc[7:0];     ta_b = state_q[7:0]; end
      EA4:     begin ta_a = {3'b0, arow}; ta_b = acc[15:8];    end
      default: begin ta_a = {3'b0, arow}; ta_b = ea_end_bound; end
    endcase
  end
  wire ta_ge = ({1'b0, ta_a} + 9'd1) >= {1'b0, ta_b};

  // Publication is direct-to-bank now: the P_W steps write the four
  // inactive sounding words straight through the engine's store site, and
  // a skipped slot's K_ROT/PC steps copy them verbatim from the active
  // bank (its cone inputs are unchanged, so the copy equals the old
  // register re-publication; a stop path zeroes the volume byte via cpz).
  // V_ST stores only the four register-resident tick words.
  logic        cpz;                  // this copy publishes a stopped slot
  logic        walk_tick;            // this pass was started by a tick
  logic        tickpend;
  // Pre-run publication handshake: a completed tick pass stages its bank
  // (bank_ready) and the boundary performs the flip. flip_pend covers the
  // collision where a trigger pass was in flight at pre_tick and the tick
  // pass is still running when the boundary arrives - it then flips late at
  // its own V_ST completion rather than holding the tick a whole period.
  logic        bank_ready, flip_pend;
  logic [5:0]  scan_p;
  logic [7:0]  note_lo;
  logic [5:0]  arp_p;

  wire [12:0] ch_base  = rec_base(sfx_id[c]);
  wire [12:0] ins_base = rec_base({3'b0, w_ins_id});

  // The note's instrument voice: a playhead (ins_use) or a wavetable
  wire ins_use = w_ins_on & ~w_ins_wt;
  // The note cedes effect control to the instrument when it carries no
  // effect of its own: fx 0, or fx 3 (retrigger) on an instrument note.
  wire fx_dfl = (w_cur_fx == 3'd0) || (w_cur_fx == 3'd3);

  // Effect 3 on a custom-instrument note means "retrigger", not "drop"; the
  // instrument's own effect is used when the note carries none of its own.
  wire [2:0] nfx      = (w_ins_on && w_cur_fx == 3'd3) ? 3'd0 : w_cur_fx;
  wire       e_insfx  = ins_use && nfx == 3'd0 && w_ins_fx != 3'd0;
  wire [2:0] e_fx     = e_insfx ? w_ins_fx   : nfx;
  // The effect path's counter/speed reads come from the EFFSEL staging
  // (eff_sp/eff_tcnt/eff_fcnt), deposited from the flow-owned words after
  // the dispatch settles which bank supplies the effect. e_insfx picks the
  // bank the ES states read.

  // Arpeggio source row: (tick / period) & 3, period from fx and speed
  logic [1:0] arp_idx;
  always_comb begin
    if (e_fx == 3'd6)
      arp_idx = (eff_sp <= 8) ? eff_tcnt[2:1] : eff_tcnt[3:2];
    else
      arp_idx = (eff_sp <= 8) ? eff_tcnt[3:2] : eff_tcnt[4:3];
  end

  // Audio RAM read port, shared: u_aram (rtl/psg_aram.sv) owns the array and
  // the borrow/replay contract; these are the wires the two requesters and
  // the freeze aggregation below need.
  wire  [12:0] seq_addr;
  wire  [7:0]  seq_q;
  wire         syn_rd;
  wire  [12:0] syn_addr;
  wire         seq_frozen;
  // u_state's export: the sequencer's synchronous read was displaced by a
  // sample and has to be re-issued.
  wire         state_replay;
  // The walk-freeze contract itself, and the reason it is formed HERE: its
  // four terms come from three different owners (u_aram's borrow, u_walk's
  // sample pass and fold chain, u_state's replay), so the top level is the
  // only place that can see all of them. Every consumer reads it from here.
  wire         prun, fold_busy;
  wire         walk_frozen = seq_frozen | prun | state_replay | fold_busy;

  psg_aram u_aram(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di),
    .seq_addr(seq_addr), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .seq_q(seq_q), .seq_frozen(seq_frozen));

  // One adder, not one per state. Every SFX-record address is the same shape -
  // a record base plus a byte offset - but writing it out per state built a
  // separate 13-bit adder in each branch: 23 of them in the cell dump, all to
  // compute base + offset. Choosing the base and the offset first and adding
  // once leaves the muxes (which are cheap) and a single adder (which is not).
  logic [12:0] sa_base;
  logic [7:0]  sa_off;
  logic        sa_pat;                 // pattern bytes are not record-relative
  always_comb begin
    sa_base = ch_base;
    sa_off  = 8'd0;
    sa_pat  = 1'b0;
    case (sst)
      T_FL:   sa_off = 8'd64;
      T_SP:   sa_off = 8'd65;
      T_LS:   sa_off = 8'd66;
      T_LE:   sa_off = 8'd67;
      T_NL,
      K_NL:   sa_off = {2'b0, w_row, 1'b0};
      T_NH,
      K_NH:   sa_off = {2'b0, w_row, 1'b1};
      K_ARP:  begin
                sa_base = e_insfx ? ins_base : ch_base;
                sa_off  = e_insfx ? {2'b0, w_ins_row[4:2], arp_idx, 1'b0}
                                  : {2'b0, w_row[4:2],    arp_idx, 1'b0};
              end
      I_TR0:  begin sa_base = ins_base; sa_off = 8'd64; end
      I_TR1:  begin sa_base = ins_base; sa_off = 8'd65; end
      I_TR2:  begin sa_base = ins_base; sa_off = 8'd66; end
      I_TR3:  begin sa_base = ins_base; sa_off = 8'd67; end
      I_NL:   begin sa_base = ins_base; sa_off = {2'b0, w_ins_row, 1'b0}; end
      I_NH:   begin sa_base = ins_base; sa_off = {2'b0, w_ins_row, 1'b1}; end
      default: sa_pat = 1'b1;
    endcase
  end

  // The music pattern table lives at 0 and is addressed directly, so those
  // states bypass the base+offset adder entirely.
  logic [12:0] sa_pataddr;
  always_comb begin
    sa_pataddr = 13'd0;
    case (sst)
      ML_RD0: sa_pataddr = {5'b0, mus_pat, 2'd0};
      ML_L0:  sa_pataddr = {5'b0, mus_pat, 2'd1};
      ML_L1:  sa_pataddr = {5'b0, mus_pat, 2'd2};
      ML_L2:  sa_pataddr = {5'b0, mus_pat, 2'd3};
      MS_RD:  sa_pataddr = {5'b0, scan_p, 2'd0};
      default: ;
    endcase
  end
  assign seq_addr = sa_pat ? sa_pataddr : (sa_base + {5'b0, sa_off});

  // Filter-byte decode, valid when seq_q holds the byte at record offset
  // 64: noiz=bit1, buzz=bit2, and the top five bits are the base-3 digits
  // det/rev/damp, each taken mod 3. Spelling that as /9, %3 and (/3)%3 cost
  // ~60 LUTs of divider for a five-bit input; the lookup is a few.
  function automatic logic [5:0] fdec(input logic [4:0] n);  // {damp,rev,det}
    case (n)
      5'd0 : fdec = 6'b000000;  5'd1 : fdec = 6'b000001;  5'd2 : fdec = 6'b000010;
      5'd3 : fdec = 6'b000100;  5'd4 : fdec = 6'b000101;  5'd5 : fdec = 6'b000110;
      5'd6 : fdec = 6'b001000;  5'd7 : fdec = 6'b001001;  5'd8 : fdec = 6'b001010;
      5'd9 : fdec = 6'b010000;  5'd10: fdec = 6'b010001;  5'd11: fdec = 6'b010010;
      5'd12: fdec = 6'b010100;  5'd13: fdec = 6'b010101;  5'd14: fdec = 6'b010110;
      5'd15: fdec = 6'b011000;  5'd16: fdec = 6'b011001;  5'd17: fdec = 6'b011010;
      5'd18: fdec = 6'b100000;  5'd19: fdec = 6'b100001;  5'd20: fdec = 6'b100010;
      5'd21: fdec = 6'b100100;  5'd22: fdec = 6'b100101;  5'd23: fdec = 6'b100110;
      5'd24: fdec = 6'b101000;  5'd25: fdec = 6'b101001;  5'd26: fdec = 6'b101010;
      5'd27: fdec = 6'b000000;  5'd28: fdec = 6'b000001;  5'd29: fdec = 6'b000010;
      5'd30: fdec = 6'b000100;  default: fdec = 6'b000101;
    endcase
  endfunction
  // Rows an SFX record plays before it ends, valid in T_NL where w_lps holds
  // the loop start and seq_q the loop end. Mirrors the end-of-record rule the
  // per-tick walk applies, so a pattern's tick length matches the sound that
  // paces it.
  // Valid in T_NL: acc[7:0] holds the loop start captured at T_LE and
  // seq_q the loop-end byte landing now.
  wire [5:0] pat_rows = (acc[7:0] != 0 && seq_q == 0)
                          ? ((acc[7:0] < 8'd32) ? acc[5:0] : 6'd32) : 6'd32;

  wire [5:0] fdv    = fdec(seq_q[7:3]);
  wire [1:0] f_det  = fdv[1:0];
  wire [1:0] f_rev  = fdv[3:2];
  wire [1:0] f_damp = fdv[5:4];

  // The sounded note is the row's note plus the instrument's: pitch adds
  // relative to 24 (C-2) and volume multiplies (nv*iv*36/7 on the 0-252
  // scale the mixer uses, as nv*iv*1317 >> 8).
  function automatic logic [5:0] pclamp(input logic signed [8:0] v);
    pclamp = (v < 9'sd0) ? 6'd0 : (v > 9'sd63) ? 6'd63 : 6'(v);
  endfunction

  wire signed [8:0] pc_raw = $signed({3'b0, w_cur_pitch})
                           + $signed({3'b0, w_ins_pitch}) - 9'sd24;
  wire signed [8:0] pp_raw = $signed({3'b0, w_prev_pitch})
                           + $signed({3'b0, w_ins_prev_pitch}) - 9'sd24;
  wire [5:0] e_pitch = ins_use ? pclamp(pc_raw) : w_cur_pitch;
  wire [5:0] e_prevp = ins_use ? pclamp(pp_raw) : w_prev_pitch;


  // The pitch/constants table is read through one synchronous port, so
  // it infers as block RAM instead of ~750 LUTs of address mux. The
  // reciprocal table that sat beside it is gone: every effect now
  // divides exactly (3.1/3.2), and round(65536/s) had no other reader.
  // The three pitch lookups an evaluation needs (this note, the previous
  // one for slide, the arpeggio row) are prefetched into registers by the
  // K_PF states before K_FX runs.
  // Eight bits: the slide's affine table lives in words 64..111 of the
  // same constants ROM (four per chromatic, base from pitch word 36+c).
  logic [7:0]  pinc_addr;
  logic [15:0] crom_q;
  // Every pitch increment is dp << 8 with dp in 13 bits, so the 24-bit
  // value is a wiring reconstruction of the constants word.
  wire [23:0] pinc_q = {3'b000, crom_q[12:0], 8'h00};
  logic [20:0] arp_r;
  wire signed [8:0] arp_raw =
      e_insfx ? ($signed({3'b0, w_cur_pitch}) + $signed({3'b0, arp_p}) - 9'sd24)
    : ins_use ? ($signed({3'b0, arp_p}) + $signed({3'b0, w_ins_pitch}) - 9'sd24)
              :  $signed({3'b0, arp_p});
  wire [5:0] e_arp = pclamp(arp_raw);

  always_comb begin
    case (sst)
      // K_PF0 issues the arpeggio row's increment; xs 0 captures it one
      // cycle later. Deliberately the same one-cycle issue-to-capture shape
      // as before (then at K_PF2): a walk freeze landing exactly in that
      // window lets pinc_q drift to e_pitch before the capture - a latent,
      // deterministic hazard the reference renders share. Fixing it changes
      // renders and is its own adjudicated stage.
      K_PF0:   pinc_addr = {2'b0, e_arp};
      // Four affine words per chromatic, then the octave-3 pitch word
      // that IS base_c.
      K_SL2:   pinc_addr = 8'd64 + {2'b0, sl_chr[3:0], 2'd0};
      K_SL3:   pinc_addr = 8'd64 + {2'b0, sl_chr[3:0], 2'd1};
      K_SL4:   pinc_addr = 8'd64 + {2'b0, sl_chr[3:0], 2'd2};
      K_SL5,
      K_SL6:   pinc_addr = 8'd64 + {2'b0, sl_chr[3:0], 2'd3};
      K_SL7,
      K_SL8:   pinc_addr = 8'd36 + {2'b0, sl_chr};
      default: pinc_addr = {2'b0, e_pitch};
    endcase
  end
  always_ff @(posedge clk) begin
    crom_q  <= crom[pinc_addr];
  end

  // The base pitch increment is the LIVE table port: pinc_addr idles at
  // e_pitch through every K_FX step, and the earliest consumer (the xs4
  // product) runs tens of cycles after the port settles - including after
  // the slide detour, whose K_SLP2/K_SLPM states already restore the
  // default address. The base_r/prev_r prefetch registers this replaces
  // were a leftover of the phase-increment slide: prev_r had no consumer
  // at all.
  wire [20:0] base_inc = pinc_q[20:0];
  // The binary's amplitude is vol<<8 exactly (a0 in _calculate_osc_state).
  wire [11:0] vol_direct  = w_ins_done ? 12'd0 : {1'b0, w_cur_vol, 8'b0};
  wire [11:0] pvol_direct = {1'b0, w_prev_vol, 8'b0};

  // The arpeggiating voice contributes arp_p; the other voice still adds
  // its pitch relative to 24, so an arpeggio inside an instrument
  // transposes with the note and vice versa.

  // ------------------------------------------------------------------
  // The shared services: one multiplier, one divider, both in their own
  // modules (u_mul, u_div). Requesters keep their request selection; these
  // are the response wires the consume steps read.
  // ------------------------------------------------------------------
  wire  [31:0] m_res;
  wire  [33:0] m_res_wide;
  wire  [27:0] m_res12;
  wire         m_busy;

  // Effect microinstruction contract (xs is the micro-PC):
  //   0 row fraction, 1 current volume, 2 previous volume,
  //   3 pitch effect, 4 volume effect, 5 music fade, 6 atomic publish.
  // A step consumes the preceding m_res, updates only the documented
  // working register, and starts at most one new eight-cycle product.
  // Products retain the original truncation points: 24-bit effects use
  // m_res[31:8], and volumes use m_res[15:8].
  logic [3:0]  xs;
  // The binary's amplitude is 12-bit `a` = vol<<8 carried through the
  // effect arithmetic (2.3/3.1). The Q8 row fraction it replaces cost
  // a fixed 252/256 = 0.984375 of exact on every effect path.
  logic [11:0] vol_r, pvol_r;

  // The divider's request comes from the sequencer alone, so there is no
  // merge to make: div_start / div_n / div_d go straight to u_div.
  wire         div_start;
  logic [23:0] div_n;
  logic [7:0]  div_d;
  wire  [23:0] d_res;
  wire  [7:0]  d_rem;
  wire         d_busy;

  psg_divsvc u_div(
    .clk(clk), .reset(reset),
    .div_start(div_start), .div_n(div_n), .div_d(div_d),
    .d_res(d_res), .d_rem(d_rem), .d_busy(d_busy));

  // PICO-8's vibrato multiplier is
  //   [128,129,130,129,128,127,126,127]
  // with each entry held for two synthesis ticks.  Keep only the signed
  // delta from 128 here; the shared multiplier applies it below.
  logic signed [2:0] lfo;
  always_comb begin
    case (eff_tcnt[3:1])
      3'd1, 3'd3: lfo =  3'sd1;
      3'd2:       lfo =  3'sd2;
      3'd5, 3'd7: lfo = -3'sd1;
      3'd6:       lfo = -3'sd2;
      default:    lfo =  3'sd0;
    endcase
  end
  wire       lfo_neg = lfo[2];
  wire [1:0] lfo_mag = lfo_neg ? 2'(-lfo) : 2'(lfo);

  // Signed differences are fed in as magnitude plus sign, so the shared
  // unit only ever has to do unsigned work.
  wire signed [12:0] vl_d   = $signed({1'b0, vol_r}) - $signed({1'b0, pvol_r});
  wire               vl_neg = vl_d[12];
  wire signed [6:0]  slp_d = $signed({1'b0, e_pitch})
                            - $signed({1'b0, e_prevp});
  wire               slp_neg = slp_d[6];
  // The slide's pitch is 16.16, not Q8 (3.2). p_1616 = ps + tz(t*D, d)
  // with D the signed semitone delta, and the whole quotient splits as
  // (q1 << 16) + tz((r1 << 16), d) over the divider's own remainder -
  // two 24-bit dividends where the literal numerator needs 30 bits. A
  // negative delta truncates toward zero the other way, so its second
  // numerator carries the d-1 round-up.
  logic [5:0]  sl_q1;                 // whole semitones of the delta
  logic [5:0]  sl_int;                // p_1616[21:16], always in 0..63
  logic [15:0] sl_frac;               // p_1616[15:0]
  wire  [15:0] sl_fmag = d_res[15:0];
  wire  [5:0]  sl_int_n = slp_neg
                            ? e_prevp - sl_q1 - 6'((|sl_fmag))
                            : e_prevp + sl_q1;
  // The octave and chromatic of an integer pitch: /12 and %12 as five
  // compares and one subtract of a multiple of twelve.
  wire [2:0] sl_oct = (sl_int >= 6'd60) ? 3'd5 : (sl_int >= 6'd48) ? 3'd4
                    : (sl_int >= 6'd36) ? 3'd3 : (sl_int >= 6'd24) ? 3'd2
                    : (sl_int >= 6'd12) ? 3'd1 : 3'd0;
  wire [5:0] sl_chr = sl_int - {sl_oct, 3'b0} - {1'b0, sl_oct, 2'b0};
  // dp_pre = base_c + ((r_c + frac*b_c) >> 29), proved exhaustively in
  // psg_hw_forms as slide.affine_table. frac*b_c is two passes of the
  // 12-bit B port; the low twelve bits of the first sum cannot carry
  // across the >>29, which is why the second accumulate is 26 bits and
  // not 38 (slide.affine_two_pass).
  // r[28:16] and base_c are never registered: each is the LAST word its
  // read address selects, and the address holds through the stall that
  // waits on the product, so crom_q still carries it at the consume.
  logic [8:0]  sl_bhi;                // b[20:12], for the second pass
  logic [15:0] sl_rlo;                // r[15:0]
  logic [17:0] sl_uhi;                // (r + frac*b[11:0]) >> 12
  wire  [29:0] sl_u = {crom_q[12:0], sl_rlo} + {2'b0, m_res[27:0]};
  wire  [25:0] sl_w = {8'b0, sl_uhi} + m_res[25:0];
  wire  [12:0] sl_dp_pre = crom_q[12:0] + {4'b0, sl_w[25:17]};
  // dx_for_note_fine's octave shift, folded onto the pre-octave value:
  // nested floors compose, so shifting after the >>29 is the binary's
  // own >> (3 - octave). Pitches 0..63 keep dp inside 13 bits and never
  // reach either clamp bound (8 and 32768), so dx_clamped is inert here.
  logic [12:0] sl_dp;
  always_comb begin
    case (sl_oct)
      3'd0:    sl_dp = {3'b0, sl_dp_pre[12:3]};
      3'd1:    sl_dp = {2'b0, sl_dp_pre[12:2]};
      3'd2:    sl_dp = {1'b0, sl_dp_pre[12:1]};
      3'd3:    sl_dp = sl_dp_pre;
      3'd4:    sl_dp = {sl_dp_pre[11:0], 1'b0};
      default: sl_dp = {sl_dp_pre[10:0], 2'b0};
    endcase
  end

  // Step results (fxv_next also feeds the last product's operand)
  wire [23:0] p24 = m_res[31:8];
  wire [7:0]  p8  = m_res[15:8];
  // Vibrato and DROP corrections on ONE 24-bit carry chain. The old spelling
  // built three: vib_ceil's round-up increment, an add and a subtract behind
  // the sign mux, and DROP's own subtract. All of them are the same modular
  // sum: base - (floor + cb) is base + ~floor + !cb, and base - p24 is
  // base + ~p24 + 1, so the round-up and the negations ride the carry-in.
  // Two's-complement identities - the results are bit-for-bit unchanged.
  wire        vib_cb  = |m_res[6:0];
  wire [20:0] fxp_op  = m_res[27:7];
  wire [20:0] fxp_res = base_inc + (lfo_neg ? ~fxp_op : fxp_op)
                      + {20'b0, (lfo_neg & ~vib_cb)};
  logic [20:0] fxi_next;
  logic [11:0] fxv_next;

  // Operands for the product started at step xs
  logic signed [24:0] mul_a;
  logic [11:0] mul_b;
  logic [1:0]  mul_md;
  logic        mul_go;               // this step actually has operands
  always_comb begin
    mul_a = 25'sd0;
    mul_b = 12'd0;
    mul_md = 2'd0;
    mul_go = 1'b0;
    case (xs)

      4'd1: if (e_fx == 3'd1) begin
              // |semitone delta| * t: the numerator of the slide's exact
              // pitch quotient, not a Q8 fraction to scale by.
              mul_a = 25'(slp_d);
              mul_b = {4'b0, eff_fcnt};
              mul_go = 1'b1;
            end
      // The volume NUMERATOR (3.1): the binary interpolates in the
      // amplitude domain and divides by the speed, so these products
      // feed the divider rather than a Q8 fraction. Slide rides the
      // identity tz((d-t)a_s + t*a0, d) = a_s + tz(t*(a0-a_s), d), which
      // needs one product and one divide instead of two of each.
      4'd5: case (e_fx)
              3'd1: begin mul_a = 25'(vl_d); mul_b = {4'b0, eff_fcnt};
                          mul_go = 1'b1; end
              3'd4: begin mul_a = {13'b0, vol_r};  mul_b = {4'b0, eff_fcnt};
                          mul_go = 1'b1; end
              3'd5: begin mul_a = {13'b0, vol_r};
                          mul_b = eff_rem;
                          mul_go = 1'b1; end
              default: ;
            endcase
      // The instrument's exact sevenths (3.1b): a = tz(a * iv, 7), with
      // the note's own effect ALREADY applied - the binary composes in
      // that order, and the outer note supplies the multiplicand only
      // when the instrument row is the one carrying the effect.
      4'd8: if (ins_use) begin
              mul_a = e_insfx ? {14'b0, w_cur_vol, 8'b0} : {13'b0, vol_r};
              mul_b = e_insfx ? {8'b0, vol_r[11:8]} : {9'b0, w_ins_vol};
              mul_go = 1'b1;
            end
      4'd10: begin mul_a = {13'b0, a_post};
                   mul_b = {4'b0, mus_gain} + 12'd1; mul_md = 2'd1;
                   mul_go = 1'b1; end
      4'd4: case (e_fx)
              3'd2: begin mul_a = {4'b0, base_inc}; mul_b = {10'b0, lfo_mag};
                          mul_go = 1'b1; end
              // DROP (3.1): tz(dp * (d - t), d) on the binary's INTEGER
              // dp, which is base_inc's [20:8] - multiplying the 24-bit
              // increment instead would divide on a finer grid than the
              // binary's and drift.
              3'd3: begin mul_a = {12'b0, base_inc[20:8]};
                          mul_b = eff_rem;
                          mul_go = 1'b1; end
              default: ;
            endcase
      default: ;
    endcase
  end

  // The amplitude after the instrument seventh. By step 10 d_res holds
  // the SEVENTH's quotient, not the effect's, so the non-instrument arm
  // reads vol_r - which step 7 already captured - rather than fxv_next.
  wire [11:0] a_post = ins_use ? d_res[11:0] : vol_r;

  // Steps 6 and 9 launch a divide on the product the preceding step left
  // in m_res, on the same cycle the micro-PC advances - so each fires
  // exactly once, with its product settled. Step 6 is the effect's
  // divide by the speed; step 9 is the instrument's exact seventh.
  // The slide adds two: its whole-semitone quotient launches on the same
  // cycle the detour is taken (m_res still holds |D| * t), and the
  // fraction's launches when that one lands.
  // The volume effects divide at step 6; DROP has no volume product, so
  // its pitch quotient takes step 5 and is consumed at step 7 alongside
  // them. Step 6 must then NOT fire for drop, or it would overwrite the
  // quotient before that consume.
  wire vol_div = (e_fx == 3'd1) || (e_fx == 3'd4) || (e_fx == 3'd5);
  // d - t, the "rows remaining" multiplier fade-out and drop share.
  wire [11:0] eff_rem = {4'b0, eff_sp} - {4'b0, eff_fcnt};
  assign div_start = !walk_frozen
                     && ((sst == K_FX && !m_busy
                          && ((xs == 4'd5 && e_fx == 3'd3)
                              || (xs == 4'd6 && vol_div)
                              || (xs == 4'd9 && ins_use)
                              || (xs == 4'd2 && e_fx == 3'd1)))
                         || (sst == K_SL0 && !d_busy));

  // A negative slide delta truncates the OTHER way - tz of a negative
  // quotient is -ceil of its magnitude - so that numerator carries the
  // d-1 round-up.
  // Every numerator is one of two sources plus, on the two sites that
  // need a ceil rather than a floor, the same d-1. Spelling it that way
  // is ONE 24-bit adder behind a two-way mux; the literal per-site form
  // built two adders behind a three-way one, and at 24 bits wide that
  // is the arm cost THE LAW warns about.
  wire div_ceil = (sst == K_SL0) ? slp_neg
                                 : (xs == 4'd6 && e_fx == 3'd1 && vl_neg);
  wire [23:0] div_base = (sst == K_SL0) ? {d_rem, 16'b0} : m_res[23:0];
  always_comb begin
    div_d = (sst == K_FX && xs == 4'd9) ? 8'd7 : eff_sp;
    div_n = div_base + (div_ceil ? ({16'b0, eff_sp} - 24'd1) : 24'd0);
  end

  always_comb begin
    fxi_next = base_inc;
    case (e_fx)
      3'd1: fxi_next = arp_r;
      // PICO-8 multiplies its integer `dp`, then the FPGA phase convention
      // expands that result by eight bits.  Multiplying base_inc directly is
      // otherwise subtly more precise and accumulates audible phase drift.
      3'd2: fxi_next = {fxp_res[20:8], 8'b0};
      3'd3: fxi_next = {d_res[12:0], 8'b0};
      3'd6, 3'd7: fxi_next = arp_r;
      default: ;
    endcase
    // The exact quotients (3.1). Fade in/out ARE the quotient; slide
    // adds its signed correction to the previous row's amplitude.
    fxv_next = vol_r;
    case (e_fx)
      3'd1: fxv_next = pvol_r + (vl_neg ? ~d_res[11:0] : d_res[11:0])
                     + {11'b0, vl_neg};
      3'd4: fxv_next = d_res[11:0];
      3'd5: fxv_next = d_res[11:0];
      default: ;
    endcase
  end

  // The publication pack, one inactive sounding word per P_W step. The
  // operands hold across all four cycles: arp_r and vol_r are the effect
  // program's result slots, the music fade is the xs 7 product (the m
  // service is idle until the next slot's first launch), and everything
  // else is a register or a cone over registers.
  wire [20:0] pub_inc = (w_ins_on && w_ins_wt && w_ins_bass)
                          ? {1'b0, arp_r[20:1]} : arp_r;
  // The published amplitude (2.3/3.1): the binary's 12-bit `a`, carried
  // exactly through the effect arithmetic now that the recurrences
  // divide rather than scale by a Q8 fraction. vol_r is a REGISTER, not
  // a slice of m_res: publication spans four cycles that a sample walk
  // can freeze, and the synthesis products reuse the m service from
  // PWORK+4 - so the music fade lands in vol_r at step 8 rather than
  // being read live at P_W3. The playhead-instrument path still folds
  // vol*ivol at the 8-bit calibration and is pre-scaled by 7 into
  // vol_r, so it publishes what it did before - section 3's instrument
  // sevenths retire that.
  wire [11:0] a_pub = vol_r;
  logic [15:0] pub_wd;
  always_comb begin
    case (sst)
      P_W0:    pub_wd = pub_inc[15:0];
      P_W1:    pub_wd = {1'b0, w_ins_id, (w_ins_on & w_ins_wt),
                         (ins_use ? w_ins_wave
                          : (w_ins_on && w_ins_wt) ? 3'd0 : w_cur_wave),
                         3'b0, pub_inc[20:16]};
      P_W2:    pub_wd = {1'b0,
                         (w_cur_fx == 3'd1
                          || (ins_use && fx_dfl && w_ins_fx == 3'd1)),
                         w_ch_damp, w_ch_rev, w_ch_det, w_ch_buzz,
                         w_ch_noiz, e_pitch};
      default: pub_wd = {(ins_use && fx_dfl
                          && (w_ins_fx == 3'd0
                              || w_ins_fx == 3'd4
                              || w_ins_fx == 3'd5)),
                         ((!w_ins_on && w_cur_fx == 3'd3)
                          || (ins_use && fx_dfl && w_ins_fx == 3'd3)),
                         clr_tog[c],
                         ((!w_ins_on
                           && (w_cur_fx == 3'd0
                               || w_cur_fx == 3'd4
                               || w_cur_fx == 3'd5))
                          || (ins_use && fx_dfl
                              && (w_ins_fx == 3'd0
                                  || w_ins_fx == 3'd4
                                  || w_ins_fx == 3'd5))
                          || (ins_use
                              && (w_cur_fx == 3'd4
                                  || w_cur_fx == 3'd5))),
                         a_pub};
    endcase
  end

  // The row note's wave field, assembled from the byte pair (T_NH/K_NH
  // leave the low byte in note_lo while the high byte lands in seq_q).
  wire [2:0] note_wave = {seq_q[0], note_lo[7:6]};

  // T_NL's pattern-length product, launched once per pattern by its
  // left-most launched non-looping channel. The FSM's capture arm, the
  // m-service launch arm and the schedule check all test this predicate.
  wire tnl_len_launch = launched[c] && !tch_seen && !(acc[7:0] < seq_q);

  // The note register load, identical at T_LD and K_LD: pitch and wave
  // from the byte pair, volume and effect from the high byte.
  task cur_note_load();
    w_cur_pitch <= note_lo[5:0];
    w_cur_wave  <= note_wave;
    w_cur_vol   <= seq_q[3:1];
    w_cur_fx    <= seq_q[6:4];
  endtask

  // One pattern-byte launch on a channel's MUSIC slot - {1'b1, ch} is
  // slot PSG_NCH+ch under the fixed pairing is_mus() states - called by the
  // ML_L0..ML_L3 walk as each byte lands in seq_q.
  task ml_launch(input logic [1:0] ch);
    if (!seq_q[6]) begin
      trig_req[{1'b1, ch}] <= 1;
      sfx_id[{1'b1, ch}] <= seq_q[5:0];
      launched[{1'b1, ch}] <= 1;
    end
  endtask

  // Stop the four music slots. `how` picks the visibility class of task
  // 3.0: 0 = immediately (a CPU action, arrival-relative), 1 = from the
  // boundary sample (class 1), 2 = one sample past it (class 2).
  task mus_stop(input logic [1:0] how);
    for (int i = PSG_NCH; i < PSG_NV; i++)
      case (how)
        2'd0:    playing[i] <= 0;
        2'd1:    pend_stop[i] <= 1;
        default: pend_stop2[i] <= 1;
      endcase
  endtask

  always_ff @(posedge clk) begin
    if (reset) begin
      sst <= S_IDLE;
      c <= 0;
      walk_tick <= 0;
      tickpend <= 0;
      bank_ready <= 0;
      flip_pend <= 0;
      pend_stop <= 0;
      pend_stop2 <= 0;
      ml_cpu <= 0;
      trig_req <= 0;
      clr_tog <= 0;
      mus_playing <= 0;
      mus_launch <= 0;
      tch_seen <= 0;
      ptick_seen <= 0;
      mus_pat <= 0;
      launched <= 0;
      f_lb <= 0;
      f_stop <= 0;
      pticks <= 0;
      ptick_tgt <= 0;
      ptick_pend <= 0;
      scan_p <= 0;
      note_lo <= 0;
      arp_p <= 0;
      fade_dir <= 0;
      fade_acc <= 0;
      fade_step <= 0;
      fade_len <= 0;
      mus_gain <= 8'd255;
      for (int i = 0; i < PSG_NV; i++) begin
        playing[i] <= 0;
        sfx_id[i] <= 0;
        released[i] <= 0;
      end
      for (int i = 0; i < PSG_NCH; i++) begin
        trg_row[i] <= 0;
        trg_len[i] <= 0;
      end
      // The record and parameter memories cannot reset per slot.  The working
      // copies do not need reset hardware either: V_LD replaces every record
      // field before K_ADV, and playing/trig_req validity gates the parameter
      // fields until T_/K_FX has produced them.
      vcnt <= 0;
      spar_bank <= 0;
      join_stage <= 0;
      xs <= 0;
    end else begin
      // Deferred pattern-length capture: T_NL launched w_sp * pat_rows on the
      // m service and moved on. Ungated by walk_frozen deliberately - the
      // product completes even if a sample walk freezes the sequencer, and it
      // must be read before that sample's own PWORK+4 product reuses m_res.
      // The launch-to-capture gap is at most nine cycles; the first sample
      // product launches at PWORK+4, so the capture always wins.
      if (ptick_pend && !m_busy) begin
        // m_res holds the product in place (m_res[k] is product bit k); the
        // [15:8] slice volume steps use is a semantic Q8 scale, not a
        // placement offset, so the 13-bit tick count is the low 13 bits.
        ptick_tgt <= m_res[12:0];
        ptick_pend <= 0;
      end
`ifndef SYNTHESIS
      if (!walk_frozen && sst == T_NL && tnl_len_launch && m_busy)
        $error("T_NL pattern-length product blocked by a busy m service");
`endif
      // Boundary publication for the pre-run tick pass: the evaluation ran
      // during the preceding sample interval, so the tick edge itself only
      // flips the staged bank. No bank_ready means a trigger pass collided
      // with pre_tick and the tick pass has not finished; V_ST then flips
      // late via flip_pend. Placed before the state case deliberately: when
      // the pass completes on the boundary edge itself, V_ST's textually
      // later assignments win and the flip happens once, immediately.
      if (tick_en_d) begin
        // A joined trigger pass writes the SAME staged bank, so flipping
        // mid-pass would publish it half-updated: defer to its own V_ST.
        if (bank_ready && !(join_stage && sst != S_IDLE)) begin
          spar_bank <= ~spar_bank;
          bank_ready <= 0;
        end else if (tickpend || ((walk_tick || join_stage) && sst != S_IDLE))
          flip_pend <= 1;
        // Class-1 deferred stops become audible from the boundary sample
        // (the delayed grid).
        for (int i = 0; i < PSG_NV; i++)
          if (pend_stop[i]) playing[i] <= 0;
        pend_stop <= 0;
      end
      // Class-2 deferred stops (music flow) become audible one sample
      // later, where the frozen walk used to land them.
      if (sample_en && scnt == 8'd3) begin
        for (int i = 0; i < PSG_NV; i++)
          if (pend_stop2[i]) playing[i] <= 0;
        pend_stop2 <= 0;
      end
      if (!walk_frozen)
      case (sst)
        // One pass over the slots in order, servicing any pending trigger and,
        // when the pass was started by a tick, advancing the row. Each visit is
        // now load / work / store: V_LD streams the slot's record out of the
        // register file into the working copy, the K_/T_/I_ states work on that
        // copy exactly as they did on `name[c]`, and V_ST writes it back.
        S_IDLE: begin
          // While a staged publication awaits its boundary, hold new TICK
          // work: a tick pass dispatched now would rewrite the staged bank
          // and publish it immediately, leaking its results early.
          //
          // A trigger pass is different, and the music pattern advance is
          // exactly why. W_MUS sets the next pattern's trig_req at the end
          // of the tick pass that staged the bank, so holding the trigger
          // until the boundary pushed the new pattern's parameters one
          // sample PAST it: the boundary sample rendered silence (class-2
          // stop) and the pattern started a sample late. Instead the
          // trigger pass JOINS the staged bank - it writes the same
          // inactive words, skipped slots copy from the staged bank
          // rather than the active one, and the boundary flip publishes
          // the tick and its triggers together. Only a plain trigger
          // pass may join: a CPU music() launch stops slots outside the
          // bank and still waits for the boundary, as before.
          if (bank_ready && (trig_req == 0 || mus_launch)) begin
          end else if (mus_launch) begin
            mus_launch <= 0;
            ml_cpu <= 1;
            sst <= ML_STOP;
          end else if (trig_req != 0 || tickpend) begin
            walk_tick <= tickpend && !bank_ready;
            join_stage <= bank_ready;
            if (!bank_ready)
              tickpend <= 0;
            c <= 0;
            vcnt <= 0;
            sst <= V_LD;
          end
        end

        // ---- record load: word vcnt-1 has landed in state_q -----------
        // The read is synchronous, so the data for the address issued at vcnt
        // arrives at vcnt+1. That one cycle of skew is the whole reason this
        // infers as block RAM instead of the LUT muxes it replaces.
        V_LD: begin
          case (vcnt)
            4'd1: `PSG_REC_W3 <= state_q;
            4'd2: `PSG_REC_W4 <= state_q;
            4'd3: `PSG_REC_W5 <= state_q;
            4'd4: w_ins_pitch <= state_q[13:8];   // word 8 read-copy refresh
            4'd5: `PSG_REC_W9 <= state_q[13:0];
            // The carried channel filters: an instrument that continues
            // without a retrigger passes no filter-writing state, so the
            // active bank's word refreshes the w_ch_* registers the P_W2
            // publication reads.
            4'd6: {w_ch_damp, w_ch_rev, w_ch_det, w_ch_buzz, w_ch_noiz}
                    <= state_q[13:6];
            4'd7: w_row <= state_q[4:0];
            default: ;
          endcase
          if (vcnt == 4'd7) begin
            vcnt <= 0;
            sst <= K_ADV;
          end else
            vcnt <= vcnt + 1;
        end

        // ---- record store: one word per cycle, then on to the next slot ---
        V_ST: begin
          // The audible slot's row, sampled as its visit ends - the grid
          // stat(46..53) is specified on.
          if (vcnt == 4'd4 && aud_sl(c[1:0], play_bits) == c)
            aud_row[c[1:0]] <= w_row;
          if (vcnt == 4'd4) begin
            vcnt <= 0;
            if (c == PSG_VW'(PSG_NV-1)) begin
              c <= 0;
              // A standalone trigger pass publishes at once, as before.
              // A JOINED trigger pass leaves the bank staged: its words
              // are already in the same inactive bank the boundary is
              // about to flip (unless the boundary went past while it
              // ran, which flip_pend records).
              join_stage <= 0;
              if (join_stage) begin
                if (flip_pend) begin
                  spar_bank <= ~spar_bank;
                  flip_pend <= 0;
                  bank_ready <= 0;
                end
              end else if (!walk_tick)
                spar_bank <= ~spar_bank;
              else if (tick_en_d | flip_pend) begin
                spar_bank <= ~spar_bank;
                flip_pend <= 0;
              end else
                bank_ready <= 1;
              sst <= W_MUS;
            end else begin
              c <= c + 1;
              sst <= V_LD;
            end
          end else
            vcnt <= vcnt + 1;
        end

        // ---- trigger: filter byte, metadata, then the first note ------
        T_FL: begin
          trig_req[c] <= 0;
          pend_stop[c] <= 0;                // a trigger overrides a pending stop
          pend_stop2[c] <= 0;
          // A music slot has no pending parameters, so it starts at row 0 with
          // no length override; only a foreground slot consults the set.
          w_row <= is_mus(c) ? 5'd0 : trg_row[c[1:0]];
          // play_len stages in wrd's high byte until T_NH writes word 2;
          // speed joins it in the low byte at T_LS.
          wrd[15:8] <= is_mus(c) ? 8'd0 : {2'b0, trg_len[c[1:0]]};
          if (!is_mus(c)) begin
            trg_row[c[1:0]] <= 0;           // parameters are one-shot
            trg_len[c[1:0]] <= 0;
          end
          released[c] <= 0;
          w_prev_pitch <= 6'd24;
          w_prev_vol <= 0;
          playing[c] <= 1;
          w_ins_on <= 0;
          w_ins_done <= 0;
          clr_tog[c] <= ~clr_tog[c];        // synth walk clears lp/brown
          sst <= T_SP;
        end
        T_SP: begin
          w_bf_noiz <= seq_q[1];
          w_bf_buzz <= seq_q[2];
          w_bf_det  <= f_det;
          w_bf_rev  <= f_rev;
          w_bf_damp <= f_damp;
          w_ch_noiz <= seq_q[1];
          w_ch_buzz <= seq_q[2];
          w_ch_det  <= f_det;
          w_ch_rev  <= f_rev;
          w_ch_damp <= f_damp;
          sst <= T_LS;
        end
        T_LS: begin
          // Speed stages in wrd's low byte for the word-2 write at T_NH.
          // The engine write this cycle seeds word 0: fcnt 0, tcnt from the
          // mod-32 seed product (only tcnt[4:0] is ever observed - arp_idx
          // tops out at bit 4, the vibrato LFO at bit 3 - and the per-tick
          // increment preserves residues mod 32, so the 8x8 array shrank to
          // its 5x5 corner).
          wrd[7:0] <= (seq_q == 0) ? 8'd1 : seq_q;
          sst <= T_LE;
        end
        T_LE: begin
          acc[7:0] <= seq_q;               // loop start, for the word-1 write
          sst <= T_NL;
        end
        T_NL: begin
          // The pattern's length is taken from its left-most launched
          // non-looping channel; the walk reaches channels in order, so the
          // first one that qualifies wins. An all-looping pattern falls back
          // to 32 rows at the first launched channel's speed.
          //
          // Only a channel the pattern itself launched may set this, which is
          // why `launched` is cleared when the CPU borrows a channel: a sound
          // effect triggered on a music channel runs through these same states
          // and would otherwise redefine the pattern's length as its own.
          if (launched[c]) begin
            if (!ptick_seen) begin
              ptick_seen <= 1;
              ptick_tgt <= {wrd[7:0], 5'b0};
            end
            if (tnl_len_launch) begin
              tch_seen <= 1;
              // The w_sp * pat_rows product runs on the shared m service
              // (launch in the mul_start mux, capture below when it lands).
              // Nothing reads ptick_tgt before the pattern's first tick
              // check, and K_FX already stalls on m_busy, so the nine busy
              // cycles cost nothing and the 13-bit array multiplier is gone.
              ptick_pend <= 1;
            end
          end
          sst <= T_NH;
        end
        T_NH: begin
          note_lo <= seq_q;
          sst <= T_LD;
        end
        T_LD: begin
          cur_note_load();
          if (seq_q[7]) begin               // custom instrument: always new
            w_ins_on <= 1;
            w_ins_id <= note_wave;
            sst <= I_TR0;
          end else
            sst <= ES0;
        end

        // ---- per-tick walk: the engine's advance sequence -------------
        // One sequence for both banks. The note pass runs it on words 0..2
        // with w_row, playing and play_len; the instrument pass on words
        // 6..8 with w_ins_row and w_ins_done. Word addresses replace the
        // note/instrument destination muxes the register file forced.
        K_ADV: begin
          if (trig_req[c]) begin
            sst <= T_FL;                    // this channel wants a new SFX
          end else if (!walk_tick || !playing[c]) begin
            // Not evaluated this pass: publish by copy. A stopped slot's
            // volume byte is forced to zero - a CPU stop clears playing
            // without a publishing pass, so the active byte may still hold
            // the sounding level. The cone bits copy verbatim: no trigger
            // has run since the last evaluation, so their inputs and
            // clr_tog are unchanged.
            cpz <= !playing[c];
            sst <= K_ROT;
          end else begin
            abank <= 0;
            sst <= EA0;
          end
        end
        EA0: sst <= EA1;                    // issue {tcnt, fcnt}
        EA1: begin                          // consume it, issue {-, plen, sp}
          acc <= state_q;
          sst <= EA2;
        end
        EA2: begin                          // consume speed word, issue loops
          wrd <= state_q;
          froll <= ta_ge;                   // fcnt+1 >= sp
          // The engine write this cycle puts the advanced counters back.
          sst <= EA3;
        end
        EA3: begin                          // consume {lpe, lps}
          acc <= state_q;
          if (!froll) begin
            // the row holds, but the instrument playhead still advances
            if (!abank) begin
              if (ins_use) begin
                abank <= 1;
                sst <= EA0;
              end else
                sst <= ES0;
            end else
              sst <= I_NL;
          end else begin
            // row finished: latch the sounding note as the previous one
            if (!abank) begin
              w_prev_pitch <= w_cur_pitch;
              w_prev_vol <= w_cur_vol;
            end else begin
              w_ins_prev_pitch <= w_ins_pitch;
              w_ins_prev_vol <= w_ins_vol;
            end
            sst <= EA4;
          end
        end
        EA4: begin
          ge_lpe <= ta_ge;                  // row+1 >= lpe
          sst <= EA5;
        end
        EA5: begin
          // Decide: explicit length (note bank only), loop, end, advance.
          // ta_ge here is row+1 >= the end-of-record bound.
          if (!abank && wrd[13:8] != 0) begin
            // an explicit length overrides the record's loop points
            if (wrd[13:8] == 6'd1 || w_row == 5'd31) begin
              pend_stop[c] <= 1;             // visible from the boundary
              cpz <= 1;                      // publish a zero volume
              sst <= K_ROT;
            end else begin
              // the engine write this cycle decrements the length in place
              w_row <= w_row + 1;
              sst <= K_NL;
            end
          end else if (acc[7:0] < acc[15:8] && (abank || !released[c])
                       && ge_lpe) begin
            if (!abank) begin
              w_row <= acc[4:0];
              sst <= K_NL;
            end else begin
              w_ins_row <= acc[4:0];
              sst <= I_NL;
            end
          end else if (ta_ge) begin
            if (!abank) begin
              pend_stop[c] <= 1;           // visible from the boundary
              cpz <= 1;                    // publish a zero volume
              sst <= K_ROT;
            end else begin
              w_ins_done <= 1;             // instrument over: note silent
              sst <= I_NL;
            end
          end else begin
            if (!abank) begin
              w_row <= w_row + 1;
              sst <= K_NL;
            end else begin
              w_ins_row <= w_ins_row + 1;
              sst <= I_NL;
            end
          end
        end
        K_NL: sst <= K_NH;                  // note lo lands next cycle
        K_NH: begin
          note_lo <= seq_q;
          sst <= K_LD;
        end
        K_LD: begin
          cur_note_load();
          if (seq_q[7]) begin
            w_ins_on <= 1;
            w_ins_id <= note_wave;
            // retrigger on a pitch change, after a silent note, on a new
            // instrument, or when the note asks for it with effect 3
            if (!w_ins_on || w_ins_id != note_wave ||
                note_lo[5:0] != w_prev_pitch || w_prev_vol == 0 ||
                seq_q[6:4] == 3'd3)
              sst <= I_TR0;
            else if (w_ins_wt)
              sst <= ES0;
            else begin
              abank <= 1;                  // instrument advance on words 6..8
              sst <= EA0;
            end
          end else begin
            w_ins_on <= 0;                 // back to the note's own filters
            w_ch_noiz <= w_bf_noiz;
            w_ch_buzz <= w_bf_buzz;
            w_ch_det  <= w_bf_det;
            w_ch_rev  <= w_bf_rev;
            w_ch_damp <= w_bf_damp;
            sst <= ES0;
          end
        end

        // ---- custom instrument: retrigger, then per-tick advance -------
        I_TR0: begin
          // The engine write this cycle zeroes word 6 ({ins_tcnt, ins_fcnt}).
          w_ins_row <= 0;
          w_ins_done <= 0;
          w_ins_prev_pitch <= 6'd24;
          w_ins_prev_vol <= 0;
          sst <= I_TR1;
        end
        I_TR1: begin                        // the instrument's filters join
          w_ch_noiz <= w_bf_noiz | seq_q[1];
          w_ch_buzz <= w_bf_buzz | seq_q[2];
          w_ch_det  <= (f_det  > w_bf_det)  ? f_det  : w_bf_det;
          w_ch_rev  <= (f_rev  > w_bf_rev)  ? f_rev  : w_bf_rev;
          w_ch_damp <= (f_damp > w_bf_damp) ? f_damp : w_bf_damp;
          sst <= I_TR2;
        end
        I_TR2: begin
          // The engine writes word 8 = {2'b0, ins_pitch copy, speed} this
          // cycle; the speed also stages in wrd's low byte, which every path
          // into I_LD keeps holding (the EA path reloads it from word 8).
          wrd[7:0]   <= (seq_q == 0) ? 8'd1 : seq_q;
          w_ins_bass <= seq_q[0];          // wavetable: down an octave
          sst <= I_TR3;
        end
        I_TR3: begin
          acc[7:0]  <= seq_q;              // ins loop start, for the w7 write
          w_ins_wt  <= seq_q[7];           // loop start bit 7 = wavetable
          sst <= I_TR4;
        end
        I_TR4: begin
          // The engine writes word 7 = {loop end, loop start} this cycle.
          if (w_ins_wt) begin              // no playhead: the record is PCM
            w_ins_pitch <= 6'd24;
            w_ins_prev_pitch <= 6'd24;
            w_ins_vol <= 3'd7;
            w_ins_prev_vol <= 3'd7;
            w_ins_fx <= 0;
            w_ins_wave <= 0;
            sst <= I_TW;
          end else
            sst <= I_NL;
        end
        I_TW: begin
          // Wavetable default pitch lands in word 8 through the engine
          // write; the register copy was set at I_TR4.
          sst <= ES0;
        end
        // The instrument's per-tick advance is the same EA0..EA5 sequence
        // with abank = 1; there is no separate I_ADV any more.
        I_NL: sst <= I_NH;
        I_NH: begin
          note_lo <= seq_q;
          sst <= I_LD;
        end
        I_LD: begin
          // The engine writes word 8 = {2'b0, new pitch, speed} this cycle;
          // wrd's low byte still holds the speed on every path here (staged
          // at I_TR2, or reloaded from word 8 by the EA sequence).
          w_ins_pitch <= note_lo[5:0];
          w_ins_wave  <= note_wave;
          w_ins_vol   <= seq_q[3:1];
          w_ins_fx    <= seq_q[6:4];
          sst <= ES0;
        end

        // ---- effect staging: the family fields the effect path reads ----
        ES0: sst <= ES1;                    // issue the bank's counter word
        ES1: begin                          // consume it, issue the speed word
          eff_tcnt <= state_q[12:8];
          eff_fcnt <= state_q[7:0];
          sst <= ES2;
        end
        ES2: begin
          eff_sp <= state_q[7:0];
          sst <= K_ARP;
        end

        K_ARP:
          if (e_fx == 3'd6 || e_fx == 3'd7)
            sst <= K_ARPC;                  // arp row's note lo lands next
          else
            sst <= K_PF0;
        K_ARPC: begin
          arp_p <= seq_q[5:0];
          sst <= K_PF0;
        end
        // Issue the arpeggio row's increment; the base increment needs no
        // prefetch at all - it is the table port's idle read.
        K_PF0: sst <= K_FX;
        // Effect evaluation, one microinstruction per completed product.
        K_FX: if (!m_busy && !((xs == 4'd7 || xs == 4'd10) && d_busy)) begin
          if (xs == 0) arp_r <= pinc_q[20:0];
          case (xs)
            // The effect runs on the note's OWN amplitude, or on the
            // instrument row's when the instrument is the one carrying
            // the effect. The instrument fold used to happen here, ahead
            // of the effect; the binary composes the other way round.
            4'd3: vol_r  <= (w_ins_done && ins_use) ? 12'd0
                          : e_insfx ? {1'b0, w_ins_vol, 8'b0}
                                    : vol_direct;
            4'd4: pvol_r <= e_insfx ? {1'b0, w_ins_prev_vol, 8'b0}
                                    : pvol_direct;
            // arp_r and vol_r are dead after their respective effect
            // calculations, so they become the publication result slots.
            4'd5: if (e_fx != 3'd3) arp_r <= fxi_next;
            4'd7: begin
              vol_r <= fxv_next;
              if (e_fx == 3'd3) arp_r <= fxi_next;   // the drop quotient
            end
            4'd10: vol_r <= a_post;
            4'd11: if (is_mus(c)) vol_r <= m_res[19:8];
            default: ;
          endcase
          if (xs == 4'd2 && e_fx == 3'd1) begin
            // Product 1 is |pitch delta| x t. The detour turns it into a
            // 16.16 pitch and runs _get_dx_for_note_fine exactly, then
            // rejoins the ordinary effect program.
            sst <= K_SL0;
          end else if (xs == 4'd11) begin
              // Publication runs P_W0..P_W3, writing the four inactive
              // sounding words directly; arp_r, vol_r, the final product
              // and the identity registers hold every operand.
              xs <= 0;
              sst <= P_W0;
          end else begin
            xs    <= xs + 1;
          end
        end
        // ---- slide: the exact 16.16 pitch and its fine increment -----
        // The binary interpolates the NOTE_DX TABLE by the 16-bit
        // fraction and only then applies the reciprocal and the octave
        // shift; interpolating final increments - what this detour used
        // to do, at Q8 - is a different function. Two divides make the
        // fraction, four ROM words plus one multiply make the increment.
        K_SL0: if (!d_busy) begin
          sl_q1 <= d_res[5:0];            // whole semitones of the delta
          sst   <= K_SL1;                 // the fraction's divide launches
        end
        K_SL1: if (!d_busy) begin
          // Negating the magnitude borrows into the integer part exactly
          // when the fraction is nonzero.
          sl_frac <= slp_neg ? (16'd0 - sl_fmag) : sl_fmag;
          sl_int  <= sl_int_n;
          sst     <= K_SL2;
        end
        K_SL2: sst <= K_SL3;              // b[11:0] issued
        K_SL3: sst <= K_SL4;              // it lands, and pass 1 launches
        K_SL4: begin sl_bhi <= crom_q[8:0]; sst <= K_SL5; end
        K_SL5: begin sl_rlo <= crom_q;     sst <= K_SL6; end
        K_SL6: if (!m_busy) begin
          sl_uhi <= sl_u[29:12];          // (r + frac*b[11:0]) >> 12
          sst    <= K_SL7;                // pass 2 launches
        end
        K_SL7: sst <= K_SL8;              // base_c issued
        K_SL8: if (!m_busy) begin
          arp_r <= {sl_dp, 8'b0};
          // Resume after micro-op 2 by starting its current-volume product.
          xs    <= 4'd3;
          sst   <= K_FX;
        end

        // Direct publication for an evaluated slot: one inactive sounding
        // word per step through the engine's store site.
        P_W0: sst <= P_W1;
        P_W1: sst <= P_W2;
        P_W2: sst <= P_W3;
        P_W3: begin
          vcnt <= 0;
          sst <= V_ST;
        end

        // A skipped slot's publication is a verbatim copy of its active
        // sounding words (its cone inputs are unchanged, so this equals
        // the old register re-publication); cpz zeroes the volume byte
        // when the slot stopped this pass. K_ROT issues the first read.
        K_ROT: sst <= PC0;
        PC0: sst <= PC1;               // write inactive+0, issue active+1
        PC1: sst <= PC2;
        PC2: sst <= PC3;
        PC3: begin
          vcnt <= 0;
          sst <= V_ST;
        end

        // ---- music: pattern-end check and flow control ---------------
        W_MUS: begin
          sst <= S_IDLE;
          // The pattern clock free-runs; only the boundary itself waits for
          // pending triggers to be serviced, so a channel change cannot make
          // the song lose or gain ticks.
          if (walk_tick && mus_playing && !mus_launch) begin
            pticks <= pticks + 1;
            // pticks is the zero-based tick just rendered by this walk.
            // Advance after rendering tick ptick_tgt-1; waiting for the old
            // counter to equal ptick_tgt inserted one silent 183-sample tick
            // between adjacent MUSIC patterns.
            if (trig_req == 0 && pticks + 13'd1 >= ptick_tgt) begin
              if (f_stop) begin
                mus_playing <= 0;
                mus_stop(2'd2);            // visible one sample past the boundary
              end else if (f_lb) begin
                scan_p <= mus_pat;
                ml_cpu <= 0;
                sst <= MS_RD;
              end else if (mus_pat == 6'd63) begin
                mus_playing <= 0;
                mus_stop(2'd2);
              end else begin
                mus_pat <= mus_pat + 1;
                ml_cpu <= 0;
                sst <= ML_STOP;
              end
            end
          end
        end
        MS_RD: sst <= MS_CK;                // pattern byte 0 lands next
        MS_CK:
          if (seq_q[7]) begin
            mus_pat <= scan_p;
            sst <= ML_STOP;
          end else if (scan_p == 0) begin
            mus_pat <= 0;
            sst <= ML_STOP;
          end else begin
            scan_p <= scan_p - 1;
            sst <= MS_RD;
          end

        // ---- music: launch pattern mus_pat ---------------------------
        ML_STOP: begin
          // A CPU launch stops the old slots at once (arrival-relative, as
          // before); the song's own pattern advance defers to class 2 so
          // the boundary sample still renders the old pattern's tail.
          mus_stop(ml_cpu ? 2'd0 : 2'd2);
          launched <= 0;
          sst <= ML_RD0;
        end
        // Each channel launches from its byte as it lands - the pattern
        // staging registers are gone. Every enabled channel launches on its
        // MUSIC slot (PSG_NCH+c), never the foreground slot: a sound effect on
        // channel c cannot be disturbed by the song, and vice versa. The
        // four trig_req bits now set over four cycles, which nothing
        // observes: the walk cannot dispatch mid-chain and $03 reads only
        // the foreground bits. $21 stays readable but advisory.
        ML_RD0: sst <= ML_L0;
        ML_L0: begin
          ml_launch(2'd0);
          sst <= ML_L1;
        end
        ML_L1: begin
          f_lb <= seq_q[7];
          ml_launch(2'd1);
          sst <= ML_L2;
        end
        ML_L2: begin
          f_stop <= seq_q[7];
          ml_launch(2'd2);
          sst <= ML_L3;
        end
        ML_L3: begin
          ml_launch(2'd3);
          mus_playing <= 1;
          tch_seen <= 0;                    // the walk fills the length in
          ptick_seen <= 0;
          pticks <= 0;
          sst <= S_IDLE;
        end
        default: sst <= S_IDLE;
      endcase

      // ---- tick: queue the walk, step the music fade ------------------
      // Queued at pre_tick, one sample before the boundary: the walk
      // evaluates during the preceding interval and only the bank flip
      // remains on the tick edge. The fade steps here too, so the walk
      // reads the same post-step mus_gain sequence as before.
      if (pre_tick) begin
        tickpend <= 1;
        if (fade_dir != 2'd0) begin
          if ({1'b0, fade_acc} + {4'b0, fade_step} >= 17'h10000) begin
            fade_acc <= 0;
            fade_dir <= 0;
            mus_gain <= 8'd255;
            if (fade_dir == 2'd2) begin       // faded out: stop the music
              mus_playing <= 0;
              mus_launch <= 0;
              mus_stop(2'd1);                 // visible from the boundary
            end
          end else begin
            fade_acc <= fade_acc + {3'b0, fade_step};
            mus_gain <= (fade_dir == 2'd1)
                          ? 8'((fade_acc + {3'b0, fade_step}) >> 8)
                          : 8'd255 - 8'((fade_acc + {3'b0, fade_step}) >> 8);
          end
        end
      end

      // ---- CPU control writes (override sequencer state) -------------
      if (cs && rw && addr[7:4] == 4'h1) begin
        case (addr[3:2])
          // $10-$13 address the FOREGROUND slot of channel c, which is slot c.
          // Nothing here touches the music slot: taking a channel for a sound
          // effect no longer stops, saves or relaunches the song, it just makes
          // the foreground slot audible in its place.
          2'd0:
            if (di == 8'h81)
              released[fg_sl] <= 1;      // sfx(-2): finish, don't loop
            else if (di[7]) begin
              // Stopping the foreground slot uncovers the music slot, which has
              // been advancing all along - so the song resumes where it now is,
              // not where it was when the effect started.
              playing[fg_sl] <= 0;
              trig_req[fg_sl] <= 0;
            end else begin
              trig_req[fg_sl] <= 1;
              sfx_id[fg_sl] <= di[5:0];
              // Silence the slot until the walk services the trigger. This used
              // to zero eff_vol directly; clearing `playing` does the same job
              // through the mixer gate, and $03 still reads busy via trig_req.
              playing[fg_sl] <= 0;
            end
          2'd1: trg_row[addr[1:0]] <= di[4:0];        // $14-$17: start row
          2'd2:                                       // $18-$1B: length
            trg_len[addr[1:0]] <= (di > 8'd32) ? 6'd32 : di[5:0];
          default: ;
        endcase
      end
      if (cs && rw && addr == 8'h20) begin
        if (di[7]) begin
          if (fade_len >= 8'd8) begin        // music(-1, fade): fade out
            fade_dir <= 2'd2;
            fade_acc <= 0;
            fade_step <= fstep(fade_len[7:3]);
            fade_len <= 0;
          end else begin
            mus_playing <= 0;
            mus_launch <= 0;
            fade_dir <= 0;
            mus_gain <= 8'd255;
            mus_stop(2'd0);
          end
        end else begin
          mus_pat <= di[5:0];
          mus_launch <= 1;
          if (fade_len >= 8'd8) begin        // music(n, fade): fade in
            fade_dir <= 2'd1;
            fade_acc <= 0;
            fade_step <= fstep(fade_len[7:3]);
            mus_gain <= 0;
            fade_len <= 0;
          end else begin
            fade_dir <= 0;
            mus_gain <= 8'd255;
          end
        end
      end
      if (cs && rw && addr == 8'h22)
        fade_len <= di;
    end
  end


  // Load and store sequences over the register-resident words. The
  // flow-owned family words (0..2 and 6..8) never appear here: the engine
  // reads, modifies and writes them in place through the same two port
  // sites. The bank is an explicit argument so simulators include it in
  // combinational sensitivity.
  function automatic logic [5:0] tick_load_word(
      input logic [3:0] n, input logic bank);
    case (n)
      4'd0: tick_load_word = 6'd3;
      4'd1: tick_load_word = 6'd4;
      4'd2: tick_load_word = 6'd5;
      4'd3: tick_load_word = 6'd8;         // ins_pitch read-copy refresh
      4'd4: tick_load_word = 6'd9;
      4'd6: tick_load_word = PSG_V_SEQ;        // the note position
      // Active filter word for the carried w_ch_* refresh.
      default: tick_load_word = (bank ? PSG_V_PAR1 : PSG_V_PAR0) + 6'd2;
    endcase
  endfunction
  function automatic logic [5:0] tick_store_word(
      input logic [3:0] n, input logic bank);
    case (n)
      4'd0: tick_store_word = 6'd3;
      4'd1: tick_store_word = 6'd4;
      4'd2: tick_store_word = 6'd5;
      4'd4: tick_store_word = PSG_V_SEQ;
      default: tick_store_word = 6'd9;
    endcase
  endfunction

  // Engine read requests: addresses are pure functions of the held state,
  // so a read displaced by a sample walk re-issues itself, and a consume
  // state re-issues the displaced word during the replay cycle (the V_LD
  // pattern, generalized).
  wire [5:0] par_act = spar_bank ? PSG_V_PAR1 : PSG_V_PAR0;   // active bank base
  wire [5:0] par_ina = spar_bank ? PSG_V_PAR0 : PSG_V_PAR1;   // inactive (publish)
  // A skipped slot re-publishes its ACTIVE words - except in a joined
  // trigger pass, where the staged (inactive) bank already holds the tick
  // results for that slot and copying the active bank would revert them.
  wire [5:0] par_cpy = join_stage ? par_ina : par_act;
  logic       eng_rd;
  logic [5:0] eng_word;
  always_comb begin
    eng_rd = 1'b1;
    eng_word = 6'd0;
    case (sst)
      EA0:  eng_word = abank ? 6'd6 : 6'd0;
      EA1:  eng_word = state_replay ? (abank ? 6'd6 : 6'd0)
                                    : (abank ? 6'd8 : 6'd2);
      EA2:  eng_word = state_replay ? (abank ? 6'd8 : 6'd2)
                                    : (abank ? 6'd7 : 6'd1);
      EA3:  begin
              eng_word = abank ? 6'd7 : 6'd1;
              eng_rd = state_replay;
            end
      ES0:  eng_word = e_insfx ? 6'd6 : 6'd0;
      ES1:  eng_word = state_replay ? (e_insfx ? 6'd6 : 6'd0)
                                    : (e_insfx ? 6'd8 : 6'd2);
      ES2:  begin
              eng_word = e_insfx ? 6'd8 : 6'd2;
              eng_rd = state_replay;
            end
      // The skipped-slot copy reads the ACTIVE sounding words (the
      // STAGED ones in a joined trigger pass - see par_cpy).
      K_ROT: eng_word = par_cpy;
      PC0:   eng_word = state_replay ? par_cpy : par_cpy + 6'd1;
      PC1:   eng_word = state_replay ? par_cpy + 6'd1 : par_cpy + 6'd2;
      PC2:   eng_word = state_replay ? par_cpy + 6'd2 : par_cpy + 6'd3;
      PC3:   begin
               eng_word = par_cpy + 6'd3;
               eng_rd = state_replay;
             end
      default: eng_rd = 1'b0;
    endcase
  end

  // Engine store requests, one per state, selected before the single
  // physical write site below.
  logic        eng_we;
  logic [5:0]  eng_wa;
  logic [15:0] eng_wd;
  wire [7:0] sp_in = (seq_q == 0) ? 8'd1 : seq_q;
  // The mod-32 trigger seed: row * speed's low bits (design 5b, stage 4).
  wire [4:0] seed5 = 5'(w_row * sp_in[4:0]);
  always_comb begin
    eng_we = 1'b1;
    eng_wa = 6'd0;
    eng_wd = 16'd0;
    case (sst)
      T_LS:  begin eng_wa = 6'd0; eng_wd = {3'b0, seed5, 8'b0}; end
      T_NL:  begin eng_wa = 6'd1; eng_wd = {seq_q, acc[7:0]}; end
      T_NH:  begin eng_wa = 6'd2; eng_wd = {2'b0, wrd[13:8], wrd[7:0]}; end
      I_TR0: begin eng_wa = 6'd6; eng_wd = 16'd0; end
      I_TR2: begin eng_wa = 6'd8; eng_wd = {2'b0, w_ins_pitch, sp_in}; end
      I_TR4: begin eng_wa = 6'd7; eng_wd = {seq_q, acc[7:0]}; end
      I_TW:  begin eng_wa = 6'd8; eng_wd = {2'b0, 6'd24, wrd[7:0]}; end
      I_LD:  begin eng_wa = 6'd8; eng_wd = {2'b0, note_lo[5:0], wrd[7:0]}; end
      EA2:   begin
               eng_wa = abank ? 6'd6 : 6'd0;
               eng_wd = {acc[15:8] + 8'd1,
                         ta_ge ? 8'd0 : acc[7:0] + 8'd1};
             end
      EA5:   begin
               // The explicit-length decrement, note bank only; the other
               // EA5 outcomes write no word.
               eng_wa = 6'd2;
               eng_wd = {2'b0, wrd[13:8] - 6'd1, wrd[7:0]};
               eng_we = !abank && wrd[13:8] != 0
                        && !(wrd[13:8] == 6'd1 || w_row == 5'd31);
             end
      // Direct publication and the skipped-slot copy.
      P_W0:  begin eng_wa = par_ina;         eng_wd = pub_wd; end
      P_W1:  begin eng_wa = par_ina + 6'd1;  eng_wd = pub_wd; end
      P_W2:  begin eng_wa = par_ina + 6'd2;  eng_wd = pub_wd; end
      P_W3:  begin eng_wa = par_ina + 6'd3;  eng_wd = pub_wd; end
      PC0:   begin eng_wa = par_ina;         eng_wd = state_q; end
      PC1:   begin eng_wa = par_ina + 6'd1;  eng_wd = state_q; end
      PC2:   begin eng_wa = par_ina + 6'd2;  eng_wd = state_q; end
      PC3:   begin eng_wa = par_ina + 6'd3;
               eng_wd = cpz ? {state_q[15:8], 8'd0} : state_q;
             end
      default: eng_we = 1'b0;
    endcase
    if (walk_frozen)
      eng_we = 1'b0;
  end

  wire state_tick_we = (sst == V_ST) && !walk_frozen;
  logic [3:0] tick_issue;

  // Owner 2, the tick engine and the V_LD/V_ST record visit. Both are the
  // sequencer's, and they never overlap: the engine's states and the
  // load/store states are disjoint FSM states.
  logic [PSG_VADR-1:0] etk_ra, etk_wa;
  logic [15:0]         etk_wd;
  wire                 etk_we = eng_we | state_tick_we;
  always_comb begin
    // Normal V_LD issues word n while consuming word n-1. If a sample stole
    // the port, replay n-1 once, then normal addressing resumes on the cycle
    // that consumes it.
    tick_issue = vcnt;
    if (state_replay && sst == V_LD && vcnt != 0)
      tick_issue = vcnt - 1'b1;

    etk_ra = eng_rd ? {c, eng_word}
                    : {c, tick_load_word(tick_issue, spar_bank)};
    if (eng_we) begin
      etk_wa = {c, eng_wa};
      etk_wd = eng_wd;
    end else begin
      etk_wa = {c, tick_store_word(vcnt, spar_bank)};
      etk_wd = vwdata;
    end
  end

  // The store, and the fixed sample-walk-first priority between the two
  // owner bundles above.
  psg_state_mem u_state(
    .clk(clk), .reset(reset),
    .wlk_rd(state_sample_read), .wlk_ra(wlk_ra),
    .wlk_we(state_sample_we), .wlk_wa(wlk_wa), .wlk_wd(wlk_wd),
    .etk_ra(etk_ra), .etk_we(etk_we), .etk_wa(etk_wa), .etk_wd(etk_wd),
    .prun(prun), .state_replay(state_replay), .state_q(state_q));

  // ---- the per-sample synthesis walk ---------------------------------
  // u_walk (rtl/psg_walk.sv) runs one pass over the eight slots per sample.
  // It owns prun and pph - the signals the freeze contract is written
  // against - and every streaming oscillator register.
  psg_walk #(.REVERB(REVERB), .REALTIME_PREVIEW(REALTIME_PREVIEW)) u_walk(
    .clk(clk), .reset(reset), .sample_en(sample_en),
    .play_bits(play_bits), .mus_playing(mus_playing),
    .spar_bank(spar_bank), .clr_tog(clr_tog), .clr_ack(clr_ack),
    .seq_q(seq_q), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .state_q(state_q),
    .state_sample_read(state_sample_read), .wlk_ra(wlk_ra),
    .state_sample_we(state_sample_we), .wlk_wa(wlk_wa), .wlk_wd(wlk_wd),
    .m_res(m_res), .m_res_wide(m_res_wide), .m_res12(m_res12),
    .m_busy(m_busy),
    .wmul_start(wmul_start), .wmul_a(wmul_a), .wmul_b(wmul_b),
    .wmul_mode(wmul_mode),
    .iss_sec(iss_sec), .iss_om(iss_om), .iss_os(iss_os),
    .dq_old_ctx(dq_old_ctx),
    .s_snd_wave(s_snd_wave), .s_snd_wt(s_snd_wt), .s_ch_det(s_ch_det),
    .s_ch_buzz(s_ch_buzz), .s_phase(s_phase), .s_phase2(s_phase2),
    .s_eff_inc(s_eff_inc), .s_old_wave(s_old_wave),
    .s_old_phase(s_old_phase), .s_old_inc(s_old_inc),
    .old_mode_r(old_mode_r), .old_alt_r(old_alt_r), .old_q0(old_q0),
    .z_eval(z_eval), .dq17(dq17), .q16(q16),
    .prun(prun), .fold_busy(fold_busy),
    .dry16(dry16), .dry_valid(dry_valid));

  // The walk's own wires: its state_m owner bundle, its multiply request,
  // the wave-layer context, and the two terms it contributes to the freeze.
  wire        state_sample_read, state_sample_we;
  wire [PSG_VADR-1:0] wlk_ra, wlk_wa;
  wire [15:0] wlk_wd;
  wire        wmul_start;
  wire signed [24:0] wmul_a;
  wire [11:0] wmul_b;
  wire [1:0]  wmul_mode;
  wire        iss_sec, iss_om, iss_os, dq_old_ctx;
  wire [2:0]  s_snd_wave, s_old_wave;
  wire        s_snd_wt, s_ch_buzz;
  wire [1:0]  s_ch_det, old_mode_r;
  wire        old_alt_r;
  wire [23:0] s_phase, s_phase2, s_old_phase;
  wire [20:0] s_eff_inc, s_old_inc;
  wire [16:0] old_q0;
  wire [PSG_NV-1:0] clr_ack;
  wire signed [15:0] dry16;
  wire        dry_valid;

  // ---- the computed wave layer (adoption 2.2) ------------------------
  // One evaluation pipe serves the three per-visit reads: main (issued at
  // PWORK, captured +1), secondary q view (issued +1, captured +2), old
  // continuation (issued +2, captured +3). Phase/wave/flags register at
  // issue; the cone evaluates during the following cycle. Every constant
  // multiply is a proven reciprocal form (psg_hw_forms) - yosys lowers
  // them to the priced CSD adder networks; the fabric has no DSP.
  //
  // u_walk supplies the evaluation context and the live/old voice fields;
  // u_wave returns the three values the walk consumes.
  psg_wave #(.REALTIME_PREVIEW(REALTIME_PREVIEW)) u_wave(
    .clk(clk),
    .iss_sec(iss_sec), .iss_om(iss_om), .iss_os(iss_os),
    .dq_old_ctx(dq_old_ctx),
    .s_snd_wave(s_snd_wave), .s_snd_wt(s_snd_wt), .s_ch_det(s_ch_det),
    .s_ch_buzz(s_ch_buzz), .s_phase_hi(s_phase[23:8]), .s_phase2(s_phase2),
    .s_eff_inc_hi(s_eff_inc[20:8]),
    .s_old_wave(s_old_wave), .s_old_phase_hi(s_old_phase[23:8]),
    .s_old_inc_hi(s_old_inc[20:8]), .old_mode_r(old_mode_r),
    .old_alt_r(old_alt_r), .old_q0_lo(old_q0[15:0]),
    .z_eval(z_eval), .dq17(dq17), .q16(q16));

  wire signed [17:0] z_eval;
  wire [16:0] dq17;
  wire [15:0] q16;



  // The sequencer's bundle. Its guard is the walk-freeze contract, so it is
  // silent for every cycle the walk's bundle can speak.
  logic        smul_start;
  logic signed [24:0] smul_a;
  logic [11:0] smul_b;
  logic [1:0]  smul_mode;
  always_comb begin
    smul_start = 1'b0;
    smul_a     = 25'sd0;
    smul_b     = 12'd0;
    smul_mode  = 2'd0;
    if (!walk_frozen) begin
      case (sst)
        // mul_go names the steps that actually have operands; the rest
        // are register writes, divide launches or the publish handshake.
        K_FX: if (!m_busy && mul_go
                  && !((xs == 4'd7 || xs == 4'd10) && d_busy)
                  && !(xs == 4'd2 && e_fx == 3'd1)) begin
          smul_start   = 1'b1;
          smul_a = mul_a;
          smul_b = mul_b;
          smul_mode = mul_md;
        end
        // The affine multiply, one 12-bit pass each side of the split.
        K_SL3: if (!m_busy) begin
          smul_start   = 1'b1;
          smul_a = {9'b0, sl_frac};
          smul_b = crom_q[11:0];
          smul_mode = 2'd2;
        end
        K_SL6: if (!m_busy) begin
          smul_start   = 1'b1;
          smul_a = {9'b0, sl_frac};
          smul_b = {3'b0, sl_bhi};
          smul_mode = 2'd2;
        end
        // The music pattern's tick length, launched fire-and-forget; the
        // ungated capture in the sequencer picks m_res up when it lands.
        // m cannot be busy here - the nearest preceding launch site is the
        // previous slot's xs 6 product, a full record store earlier - and
        // the simulation-only check below guards that schedule fact.
        T_NL: if (tnl_len_launch) begin
          smul_start   = 1'b1;
          smul_a = {17'b0, wrd[7:0]};       // speed, staged at T_LS
          smul_b = {6'b0, pat_rows};
        end
        default: ;
      endcase
    end
  end

  // The service's single request port. The two bundles are DISJOINT, not
  // merely prioritised - the walk arm needs `prun`, the sequencer arm needs
  // `!walk_frozen`, and walk_frozen subsumes prun - and every arm in both
  // blocks writes its operands and its start bit together, so the silent
  // bundle is all-zero. A bitwise OR is therefore the exact merge, and the
  // one that costs nothing: a 40-bit selecting mux here measured +34 cells
  // against the anchor where the OR measures -8.
  //
  // The assertion is the guard on that argument: it is what makes a future
  // arm that sets an operand without its start bit, or an arm that escapes
  // the freeze contract, fail loudly in simulation instead of quietly
  // OR-ing two live requests together.
  wire        mul_start = wmul_start | smul_start;
  wire signed [24:0] mul_start_a = wmul_a | smul_a;
  wire [11:0] mul_start_b        = wmul_b | smul_b;
  wire [1:0]  mul_start_mode     = wmul_mode | smul_mode;
`ifndef SYNTHESIS
  always @(posedge clk) if (!reset && wmul_start && smul_start)
    $fatal(1, "psg: both multiply requesters asserted in the same cycle");
`endif

  psg_mulsvc u_mul(
    .clk(clk), .reset(reset),
    .mul_start(mul_start), .mul_start_a(mul_start_a),
    .mul_start_b(mul_start_b), .mul_start_mode(mul_start_mode),
    .m_res(m_res), .m_res_wide(m_res_wide), .m_res12(m_res12),
    .m_busy(m_busy));


  // Output stage: the mixed sum is the PCM - the adopted reverb is
  // per-voice, pre-mix (the rings above); the old shared post-mix
  // delay is gone.
  always_ff @(posedge clk) begin
    if (reset) pcm <= 16'sd0;
    else if (dry_valid) pcm <= dry16;
  end

  // ------------------------------------------------------------------
  // CPU interface: music mask and status reads
  // ------------------------------------------------------------------
  // The upload port ($00/$01/$02) is u_aram's: it writes the array, so it
  // owns the address register that walks it.
  always_ff @(posedge clk) begin
    if (reset) begin
      mus_mask <= 4'h0;
      dout <= 0;
    end else if (cs && rw) begin
      case (addr)
        8'h21: mus_mask <= di[3:0];
        default: ;
      endcase
    end else if (cs && !rw) begin
      case (addr)
        // Bits 0-3 are the FOREGROUND slots, which is exactly what software
        // auto-pick wants: a channel is available for a sound effect whenever
        // its foreground slot is idle, regardless of the song. A pending
        // trigger (written this cycle, not yet serviced) already reads as busy,
        // so back-to-back sfx() calls never collide on the same channel.
        8'h03: dout <= {mus_playing, 3'b0,
                        play_bits[3:0] | trig_req[3:0]};
        8'h20: dout <= {2'b0, mus_pat};
        // Low nibble: the channels the cart reserved, as written. High nibble
        // now reads 0 and is retained only so the register keeps its shape.
        //
        // It used to report the channels the song occupied, because software
        // auto-pick had to steer around them. With a music slot per channel
        // there is nothing to steer around: every foreground slot is always
        // available to a sound effect, whatever the song is doing. Reporting
        // occupancy here would make unmodified software refuse channels that
        // are in fact free, so it deliberately reports none.
        8'h21: dout <= {4'b0, mus_mask};
        8'h22: dout <= fade_len;
        default:
          if (addr[7:4] == 4'h1)
            // $10-$13 report the row, $14-$17 the SFX. Both answer for the
            // AUDIBLE slot of the channel - the foreground effect if one is
            // playing, otherwise the song underneath it - which is the
            // ownership state a cart can actually observe.
            dout <= (addr[3:2] == 2'd1)
                      ? {play_bits[aud_sl(addr[1:0], play_bits)], 1'b0,
                         sfx_id[aud_sl(addr[1:0], play_bits)]}
                      : {play_bits[aud_sl(addr[1:0], play_bits)], 2'b0,
                         aud_row[addr[1:0]]};
          else
            dout <= 8'h00;
      endcase
    end
  end
  // {music, pattern, foreground playing, music playing, per-channel sfx/row}.
  // The sfx/row fields report the audible slot, so --psg-trace keeps its
  // four-channel shape and tools/p8_music_trace.py comparisons still work;
  // dbg[15:12] now says which channels are hearing the song rather than which
  // are "owned" by it, which under the pairing is the same question.
  generate
  if (DBG_PORT) begin : g_dbg
    always_comb begin
      dbg = 64'b0;
      dbg[7:0]   = {mus_playing, 1'b0, mus_pat};
      dbg[11:8]  = play_bits[3:0];
      dbg[15:12] = play_bits[7:4];
      for (int ch = 0; ch < PSG_NCH; ch++) begin
        dbg[16 + ch*6 +: 6] = sfx_id[aud_sl(2'(ch), play_bits)];
        dbg[40 + ch*6 +: 6] = {1'b0, aud_row[ch]};
      end
    end
  end else begin : g_no_dbg
    always_comb dbg = 64'b0;
  end
  endgenerate

endmodule

// This file is `include'd by chip.sv and the synthesis targets; keep the
// record-layout macros psg_common.svh defines from leaking into whatever is
// compiled after it. Undefining them here rather than in the header is
// deliberate: they have to survive every submodule include above, and this
// is the one place that is past all of them.
`undef PSG_REC_W3
`undef PSG_REC_W4
`undef PSG_REC_W5
`undef PSG_REC_W9
`undef PSG_OSC_W14
`undef PSG_OSC_W17
`undef PSG_OSC_W22
