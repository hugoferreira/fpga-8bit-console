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
module psg #(parameter CLK_HZ = 32'd3_506_580, parameter REVERB = 1,
             parameter REALTIME_PREVIEW = 0)
          (input bit clk, input bit reset,
           input bit cs, input bit rw, input logic [7:0] addr, input logic [7:0] di,
           output logic [7:0] dout,
           output logic signed [15:0] pcm,
           // Verification only: per-channel state for the simulator's
           // --psg-trace. Left unconnected in the synthesised top level, so it
           // costs nothing on the FPGA. Exists because there was no way to tell
           // whether an audio fidelity complaint was allocation, sequencing or
           // synthesis without seeing inside.
           output logic [63:0] dbg);

  // Audio RAM: PICO-8 $3100-$42FF (music 0..255, SFX records 256..4607)
  logic [7:0] aram[0:4607];
  logic [15:0] wraddr;

  // The two non-trivial 256-sample shapes that remain table-shaped. Tilted saw
  // and saw use bounded integer phase formulae below; square and pulse are
  // exact thresholds; noise and phaser have their own synthesis paths.
  logic signed [7:0] wrom[0:511];
  // The constants block, homed in the EBR the computed waveforms freed:
  // words 0..63 are the pitch increment's effective 13 bits (every pinc is
  // dp << 8), words 64..255 are reserved for microcode and scheduled tables
  // (design section 6). Padded to 256x16 so yosys spends the block RAM.
  logic [15:0] crom[0:255];
  logic [15:0] recip[0:255];         // 65536 / speed
  initial begin
    $readmemh("./rtl/psg_waves_compact.hex", wrom);
    $readmemh("./rtl/psg_const.hex", crom);
    $readmemh("./rtl/psg_recip.hex", recip);
  end

  // ------------------------------------------------------------------
  // Timing: 22050 Hz virtual sample rate, sequencer tick every 183
  // ------------------------------------------------------------------
  // The accumulator is stored OFFSET by the wrap threshold: divd is the
  // classical divacc minus (CLK_HZ - 22050), so "time to emit a sample" is
  // simply divd's sign bit. The unsigned form spent a 27-bit comparator AND
  // separate 27-bit add and subtract networks on the same decision; this is
  // one adder whose second operand is a mux of two constants. The clock-for-
  // clock sample_en/tick_en sequence is unchanged - same Bresenham, same
  // phase - and sim/psg_wav.cpp mirrors the recurrence, not the register.
  // 28 bits: the fastest clock this design can be given is the 112.5 MHz PLL
  // output, and the offset form needs its magnitude plus a sign.
  localparam logic [26:0] DIV_DOWN = 27'(CLK_HZ - 32'd22050);
  logic signed [27:0] divd;
  logic        sample_en;
  logic [7:0]  scnt;
  logic        tick_en;
  // pre_tick fires one sample before tick_en (task 3.0): the tick program
  // EVALUATES during the preceding sample interval into the inactive bank,
  // and the boundary edge itself only flips spar_bank. That hands the tick
  // microprogram a full sample interval instead of sharing the boundary
  // sample's 1,275 clocks with synthesis. A CPU write landing inside the
  // pre-run window is observed one tick evaluation later than before -
  // accepted deliberately, see design section 3.
  logic        pre_tick;

  always_ff @(posedge clk) begin
    if (reset) begin
      divd <= -$signed({1'b0, DIV_DOWN});
      sample_en <= 0;
      scnt <= 0;
      tick_en <= 0;
      pre_tick <= 0;
    end else begin
      tick_en <= 0;
      pre_tick <= 0;
      if (!divd[27]) begin             // divacc >= CLK_HZ - 22050
        divd <= divd - $signed({1'b0, DIV_DOWN});
        sample_en <= 1;
        if (scnt == 8'd182) begin
          scnt <= 0;
          tick_en <= 1;
        end else begin
          scnt <= scnt + 1;
          // Two intervals of pre-run window: the engine's advance and
          // staging sequences grew the tick program past one interval's
          // slack, and the pre_tick constant is exactly the knob the 3.0
          // handshake left for that (design 3, staging constraints).
          if (scnt == 8'd180)
            pre_tick <= 1;
        end
      end else begin
        divd <= divd + 28'sd22050;
        sample_en <= 0;
      end
    end
  end

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
  localparam int NV  = 8;              // playback slots
  localparam int VW  = 3;              // bits to index one
  localparam int NCH = 4;              // public channels
  logic        playing[0:NV-1];
  // Slot v carries music iff v >= NCH. Was a register (`music_owned`) back when
  // any slot could be either; the fixed pairing makes it a wire.
  function automatic bit is_mus(input logic [VW-1:0] v);
    is_mus = v[2];
  endfunction
  // The slot a channel is actually heard on: its foreground effect when that is
  // playing, otherwise the song underneath. This is the audible selection the
  // mixer applies and the one status reads answer for.
  function automatic logic [VW-1:0] aud_sl(input logic [1:0] ch);
    aud_sl = playing[{1'b0, ch}] ? {1'b0, ch} : {1'b1, ch};
  endfunction
  logic [5:0]  sfx_id[0:NV-1];
  logic [4:0]  row[0:NV-1];
  // eff_vol used to be an addressable array because the music-stop, fade-out
  // and channel-stop paths zeroed it for slots other than the one being walked.
  // Those writes were redundant: every one of them also clears `playing`, and
  // the mixer leaf is gated on playing (mx_play/mx_aud), so a stale level on a
  // stopped slot is never heard. Dropping them lets the level ride the spar
  // record the synthesis walk already loads, at no extra cycles - measured 141
  // LC of flops and read mux.
  // The slot a CPU channel register acts on: the channel's foreground slot,
  // which is slot c. Spelled out because the arrays are NV deep and addr is a
  // 2-bit channel - an implicit widening here is the kind of thing that only
  // shows up as a warning in one of the three builds.
  wire [VW-1:0] fg_sl = {1'b0, addr[1:0]};

  // Trigger parameters latched for the next trigger on a channel, and the
  // resulting play limits (sfx(n, ch, offset, length) / release from loop)
  // Pending trigger parameters. These are addressed by CHANNEL, not by slot:
  // sfx(n, ch, offset, length) names a channel, and only a foreground slot can
  // ever carry a pending request - a music slot is scheduled by the pattern and
  // never has an offset or a length. So four sets suffice however many slots
  // exist, and holding eight was holding four of them permanently at zero.
  logic [4:0]  trg_row[0:NCH-1];
  // Borrow-and-restore (`sav_sfx`/`sav_row`/`sav_valid`) is gone. It saved the
  // displaced music SFX and relaunched it at the row it was interrupted on,
  // which is the one thing PICO-8 does not do: the hidden music slot keeps
  // advancing while inaudible, so the song comes back where it *now* is. The
  // foreground/music pairing gives that for free and cannot desynchronise the
  // song, so there is nothing left to save.
  logic [5:0]  trg_len[0:NCH-1];
  logic        released[0:NV-1];

  // ------------------------------------------------------------------
  // Per-slot note and instrument state: a BRAM register file
  // ------------------------------------------------------------------
  // These 154 bits per slot are touched by exactly one thing - the per-tick
  // sequencer walk - and only ever for the slot it is currently visiting. Held
  // as `name[NV]` arrays they cost a flop per bit AND an NV:1 mux per read, and
  // the muxes are the larger half: measured across NV=2/4/8/16 the marginal
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
  localparam int TREC = 10;                    // tick/note words per slot
  localparam int SPAR = 4;                     // sounding parameter words
  localparam int SOSC = 14;                    // oscillator-state words
  localparam int VREC = TREC + SPAR;           // tick load/store visit
  localparam int VSTR = 32;                    // all records for one slot
  localparam int VADR = VW + 5;
  localparam logic [4:0] V_TICK = 5'd0;
  localparam logic [4:0] V_OSC  = 5'd10;
  localparam logic [4:0] V_PAR0 = 5'd24;
  localparam logic [4:0] V_PAR1 = 5'd28;
  localparam int PLOSC = REALTIME_PREVIEW ? 7  : SOSC;
  localparam int PWORK = REALTIME_PREVIEW ? 12 : 19;
  localparam int PFOLD = REALTIME_PREVIEW ? 23 : 61;
  localparam int PSTOR = REALTIME_PREVIEW ? 16 : 52;
  localparam int PLAST = REALTIME_PREVIEW ? 23 : 65;

  // One 256x16 scheduled store holds every per-slot record:
  //
  //   word  0.. 9  tick/note state
  //   word 10..23  oscillator state
  //   word 24..27  sounding parameter bank 0
  //   word 28..31  sounding parameter bank 1
  //
  // Eight slots x 32 words is exactly one iCE40 EBR. The sequencer writes the
  // inactive parameter bank and flips spar_bank only after the complete
  // eight-slot walk, so synthesis never observes a partly published tick.
  logic [15:0] state_m[0:NV*VSTR-1];
  logic [VADR-1:0] state_ra, state_wa;
  logic [15:0] state_wd, state_q;
  logic        state_we, spar_bank;
  logic [15:0] vwdata;
  logic [3:0]  vcnt;                           // word within the record
  logic [6:0]  pph;                            // sample micro-phase
  // Simulation determinism, and a free BRAM init on iCE40. Without it iverilog
  // starts the record at X and the X leaks through the packing.
  initial for (int i = 0; i < NV * VSTR; i++) state_m[i] = 16'h0000;

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

  // Register-resident record layout, four words. This MUST stay an
  // always_comb reading the working registers directly, not a function
  // called from a continuous assign: iverilog does not infer sensitivity to
  // signals a function reads internally, so `assign vwdata = vpack(vcnt)`
  // held 0 forever and every store wrote zeros. The unpack in V_LD is the
  // mirror of this and the two must move together. Flow-owned words never
  // appear here: V_ST does not store them and V_LD does not unpack them
  // (word 8's ins_pitch read-copy is the one exception, refreshed on load).
  always_comb begin
    case (vcnt)
      4'd0: vwdata = {w_ins_bass, w_cur_wave, w_prev_pitch, w_cur_pitch};
      4'd1: vwdata = {w_ins_done, w_bf_rev, w_bf_det, w_bf_buzz, w_bf_noiz,
                      w_prev_vol, w_cur_fx, w_cur_vol};
      4'd2: vwdata = {w_ins_vol, w_ins_wave, w_ins_row, w_ins_id, w_bf_damp};
      default: vwdata = {2'b0, w_ins_wt, w_ins_on,
                         w_ins_prev_vol, w_ins_fx, w_ins_prev_pitch};
    endcase
  end

  // ------------------------------------------------------------------
  // Per-slot synthesis state: working copies of the scheduled store
  // ------------------------------------------------------------------
  logic [15:0] sosc_wd;

  // The sequencer's working copy of the parameters: what it is building for the
  // slot it is visiting, published to the inactive bank when the visit ends.
  // The former w_eff_inc/w_snd_*/w_eff_vol publication staging is gone:
  // arp_r, vol_r and the final product hold the results until the P_W
  // steps write the bank words directly.
  logic        w_ch_noiz, w_ch_buzz;
  logic [1:0]  w_ch_det, w_ch_rev, w_ch_damp;

  // The synthesis walk's working copy: parameters and oscillator state loaded
  // serially from state_m, with the oscillator words written back in place.
  logic [23:0] s_eff_inc;
  logic [2:0]  s_snd_wave;
  logic        s_snd_wt;
  logic [2:0]  s_snd_id;
  logic [5:0]  s_snd_pitch;
  logic        s_pitch_direct;
  logic        s_slide_effect;
  logic        s_compound_direct;
  logic        s_drop_effect;
  logic        s_trigger_tag;
  logic        s_ch_noiz, s_ch_buzz;
  logic [1:0]  s_ch_det, s_ch_rev, s_ch_damp;
  logic [7:0]  s_eff_vol;
  logic [23:0] s_phase, s_phase2;
  logic signed [7:0] s_nz_hold;
  logic [3:0]  s_nz_ph;
  logic signed [12:0] s_brown;
  logic signed [15:0] s_lp;
  logic signed [15:0] s_noise_lp;
  // PICO-8 keeps a copy of the preceding oscillator state at every synthesis
  // tick and blends its continuation into the first 64 new samples. These
  // fields live in the oscillator portion of state_m.
  logic [23:0] s_old_phase, s_old_inc, s_last_inc;
  logic [7:0]  s_old_vol, s_last_vol;
  logic [2:0]  s_old_wave, s_last_wave;
  logic [5:0]  s_last_pitch;
  logic        s_last_trigger;
  logic        s_last_slide;
  logic        s_fx_phase_entry;
  logic [6:0]  s_ramp;              // 0 idle; 1..64 means blend position 0..63
  // The wavetable's base address in audio RAM, recomputed rather than stored:
  // 256 + id * 68 is two shifts and an add, against 13 bits per slot of state
  // and the mux to read them.
  wire [12:0] s_snd_wtb = 13'd256 + {4'b0, s_snd_id, 6'b0} + {8'b0, s_snd_id, 2'b0};

  // Per-slot filter state: bf_* comes from the played SFX's filter byte at
  // trigger and lives in the sequencer's record; ch_* is that folded together
  // with the instrument's and lives in the active parameter bank.

  logic [NV-1:0] trig_req;
  logic [NV-1:0] clr_tog;   // toggled to ask the synth walk to reset lp/brown
  // Deferred stops (task 3.0 completed for arbitrary pre-run depth): the
  // tick program mutates playing[] while it evaluates, but the render must
  // observe those clears exactly when it did before the pre-run. Note-end,
  // length-stop and fade-out stops were visible from the BOUNDARY sample
  // (class 1, applied at tick_en); the music-flow stops ran after V_ST
  // behind the frozen boundary render and were visible one sample later
  // (class 2, applied at the scnt==1 sample). A trigger overrides both.
  logic [NV-1:0] pend_stop, pend_stop2;
  logic          ml_cpu;    // ML_STOP reached from a CPU launch, not the song

  // Music state
  logic        mus_playing, mus_launch;
  logic [5:0]  mus_pat;
  logic [3:0]  mus_mask;
  logic [NV-1:0] launched;
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
    K_SLP0, K_SLP1, K_SLP2, K_SLPM,
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

  logic [VW-1:0] c;                  // voice being processed

  // The engine's one 9-bit compare unit: A+1 >= B, operands keyed by the
  // advance step. EA2 compares fcnt+1 against the speed landing in state_q;
  // EA4 compares row+1 against the loop end; EA5 against the end-of-record
  // bound. arow is the bank's row.
  wire [4:0] arow = abank ? w_ins_row : row[c];
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

  wire [12:0] ch_base  = 13'd256 + {1'b0, sfx_id[c], 6'b0} + {5'b0, sfx_id[c], 2'b0};
  wire [12:0] ins_base = 13'd256 + {4'b0, w_ins_id, 6'b0} + {8'b0, w_ins_id, 2'b0};

  // The note's instrument voice: a playhead (ins_use) or a wavetable
  wire ins_use = w_ins_on & ~w_ins_wt;

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

  // Audio RAM read port, shared: the sequencer owns it except on the one
  // cycle per sample per wavetable voice that the synthesiser borrows it.
  // A borrow overwrites the byte the sequencer was waiting on, so the FSM
  // freezes for that cycle and for one more while the address it issued
  // last is replayed. There is exactly one unconditional read of aram, so
  // it still infers as a block RAM.
  logic [12:0] last_addr;
  wire  [12:0] seq_addr;
  logic [7:0]  seq_q;
  logic        syn_rd, replay;
  logic [12:0] syn_addr;
  logic        prun;
  wire         seq_frozen = syn_rd | replay;
  // A sample owns the scheduled state store for its complete bounded walk.
  // Tick-first ordering gives the 120 Hz microprogram an uncontested port on
  // the boundary where its result matters; ordinary trigger work can wait one
  // sample without changing any sample-visible state. One replay cycle restores
  // a synchronous V_LD word displaced when a sample began mid-trigger.
  logic        state_replay;
  // The serial soft_add fold engine (datapath in the mixer section below).
  // Declared here because walk_frozen must hold the tick sequencer while the
  // post-walk fold chain still owns the phase ALU and the m service idle slot.
  logic [3:0]  fmc;                  // fold micro-cycle, 0 = idle
  wire         fold_busy = (fmc != 4'd0);
  wire         state_sample_read = prun && pph < 7'(PLOSC + SPAR);
  wire         state_sample_we = prun
                               && pph >= 7'(PSTOR)
                               && pph <= 7'(PLAST);
  wire         walk_frozen = seq_frozen | prun | state_replay | fold_busy;
  always_ff @(posedge clk) begin
    if (reset)
      state_replay <= 0;
    else
      state_replay <= prun;
  end
  wire  [12:0] aram_addr  = syn_rd ? syn_addr : replay ? last_addr : seq_addr;

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
      K_NL:   sa_off = {2'b0, row[c], 1'b0};
      T_NH,
      K_NH:   sa_off = {2'b0, row[c], 1'b1};
      K_ARP:  begin
                sa_base = e_insfx ? ins_base : ch_base;
                sa_off  = e_insfx ? {2'b0, w_ins_row[4:2], arp_idx, 1'b0}
                                  : {2'b0, row[c][4:2],    arp_idx, 1'b0};
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
  always_ff @(posedge clk) begin
    seq_q <= aram[aram_addr];
    if (reset) begin
      replay <= 0;
      last_addr <= 0;
    end else begin
      replay <= syn_rd;              // a borrow costs a replay cycle
      if (!seq_frozen) last_addr <= seq_addr;
    end
  end

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

  wire [5:0] vmul  = 6'(w_cur_vol  * w_ins_vol);
  wire [5:0] pvmul = 6'(w_prev_vol * w_ins_prev_vol);

  // Pitch and reciprocal tables are read through one synchronous port
  // each, so both infer as block RAM instead of ~750 LUTs of address mux.
  // The three pitch lookups an evaluation needs (this note, the previous
  // one for slide, the arpeggio row) are prefetched into registers by the
  // K_PF states before K_FX runs.
  logic [5:0]  pinc_addr;
  logic [15:0] crom_q;
  // Every pitch increment is dp << 8 with dp in 13 bits, so the 24-bit
  // value is a wiring reconstruction of the constants word.
  wire [23:0] pinc_q = {3'b000, crom_q[12:0], 8'h00};
  logic [15:0] recip_q;
  logic [23:0] arp_r;
  logic [5:0] slide_addr;
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
      K_PF0:   pinc_addr = e_arp;
      K_SLP0:  pinc_addr = slide_addr;
      K_SLP1:  pinc_addr = (slide_addr == 6'd63)
                              ? 6'd63 : slide_addr + 1'b1;
      default: pinc_addr = e_pitch;
    endcase
  end
  always_ff @(posedge clk) begin
    crom_q  <= crom[{2'b00, pinc_addr}];
    recip_q <= recip[eff_sp];
  end

  // The base pitch increment is the LIVE table port: pinc_addr idles at
  // e_pitch through every K_FX step, and the earliest consumer (the xs4
  // product) runs tens of cycles after the port settles - including after
  // the slide detour, whose K_SLP2/K_SLPM states already restore the
  // default address. The base_r/prev_r prefetch registers this replaces
  // were a leftover of the phase-increment slide: prev_r had no consumer
  // at all.
  wire [23:0] base_inc = pinc_q;
  wire [7:0]  vol_direct  = w_ins_done ? 8'd0
                          : {w_cur_vol, 5'b0} + {3'b0, w_cur_vol, 2'b0};
  wire [7:0]  pvol_direct = {w_prev_vol, 5'b0} + {3'b0, w_prev_vol, 2'b0};

  // The arpeggiating voice contributes arp_p; the other voice still adds
  // its pitch relative to 24, so an arpeggio inside an instrument
  // transposes with the note and vice versa.

  // ------------------------------------------------------------------
  // Shared multiplier. Every product the effect unit needs is (24-bit
  // magnitude x 8-bit unsigned), so one shift-add unit serves them all:
  // 8 iterations of a 26-bit add, versus the ~1500 LUTs the parallel
  // array multipliers cost. An evaluation runs six of them, 4 channels
  // 120 times a second - about 240 clocks in a tick.
  // ------------------------------------------------------------------
  logic [23:0] m_a;
  logic [34:0] m_p;                  // accumulator plus 8/10-bit multiplier
  logic [3:0]  m_cnt;
  logic        m_wide;
  // Reset contract: m_cnt and the micro-PC are validity/control state and
  // reset to idle.  m_a/m_p and the working results below are datapath:
  // every one is overwritten by the six-op program before it is observed.
  wire  [24:0] m_acc = m_wide ? m_p[34:10] : m_p[32:8];
  wire  [25:0] m_sum = {1'b0, m_acc} + (m_p[0] ? {2'b0, m_a} : 26'd0);
  wire  [31:0] m_res = m_p[31:0];
  wire  [33:0] m_res_wide = m_p[33:0];
  wire         m_busy = (m_cnt != 0);

  // Effect microinstruction contract (xs is the micro-PC):
  //   0 row fraction, 1 current volume, 2 previous volume,
  //   3 pitch effect, 4 volume effect, 5 music fade, 6 atomic publish.
  // A step consumes the preceding m_res, updates only the documented
  // working register, and starts at most one new eight-cycle product.
  // Products retain the original truncation points: 24-bit effects use
  // m_res[31:8], and volumes use m_res[15:8].
  logic [3:0]  xs;
  logic [7:0]  u_r, vol_r, pvol_r;

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
  wire signed [8:0]  vl_d   = $signed({1'b0, vol_r}) - $signed({1'b0, pvol_r});
  wire               vl_neg = vl_d[8];
  wire [7:0]         vl_mag = vl_neg ? 8'(-vl_d) : 8'(vl_d);
  wire signed [6:0]  slp_d = $signed({1'b0, e_pitch})
                            - $signed({1'b0, e_prevp});
  wire               slp_neg = slp_d[6];
  wire [5:0]         slp_mag = slp_neg ? 6'(-slp_d) : 6'(slp_d);
  // One chain here too: +/- m_res[15:0] as xor-and-carry, not two adders.
  wire signed [15:0] slp_q8 = $signed(
      {2'b0, e_prevp, 8'b0}
      + (slp_neg ? ~m_res[15:0] : m_res[15:0])
      + {15'b0, slp_neg});
  wire signed [8:0] slp_whole = {slp_q8[15], slp_q8[15:8]};
  wire [5:0] slp_int = pclamp(slp_whole);
  wire [7:0] slp_frac = (slp_whole < 0 || slp_whole > 9'sd62)
                          ? 8'd0 : slp_q8[7:0];

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
  wire        fxp_neg = (e_fx == 3'd3) | lfo_neg;
  wire [23:0] fxp_op  = (e_fx == 3'd3) ? p24 : m_res[30:7];
  wire [23:0] fxp_res = base_inc + (fxp_neg ? ~fxp_op : fxp_op)
                      + {23'b0, (e_fx == 3'd3) | (lfo_neg & ~vib_cb)};
  logic [23:0] fxi_next;
  logic [7:0]  fxv_next;

  // Operands for the product started at step xs
  logic [23:0] mul_a;
  logic [7:0]  mul_b;
  always_comb begin
    mul_a = 24'd0;
    mul_b = 8'd0;
    case (xs)
      4'd0: begin mul_a = {8'b0, recip_q};     mul_b = eff_fcnt; end
      4'd1: begin
              if (e_fx == 3'd1) begin
                mul_a = {18'b0, slp_mag};
                // Step 1 is entered on the cycle that publishes the row
                // fraction.  Feed the just-completed product directly:
                // u_r still contains the preceding tick until this edge.
                mul_b = p8;
              end
            end
      4'd2: begin mul_a = 24'd1317;            mul_b = {2'b0, vmul}; end
      4'd3: begin mul_a = 24'd1317;            mul_b = {2'b0, pvmul}; end
      4'd4: case (e_fx)
              3'd2: begin mul_a = base_inc;                  mul_b = {6'b0, lfo_mag}; end
              3'd3: begin mul_a = base_inc;                  mul_b = u_r; end
              default: ;
            endcase
      4'd5: case (e_fx)
              3'd1: begin mul_a = {16'b0, vl_mag}; mul_b = u_r; end
              3'd4: begin mul_a = {16'b0, vol_r};  mul_b = u_r; end
              3'd5: begin mul_a = {16'b0, vol_r};  mul_b = u_r; end
              default: ;
            endcase
      4'd6: begin mul_a = {15'b0, mus_gain} + 24'd1; mul_b = fxv_next; end
      default: ;
    endcase
  end

  always_comb begin
    fxi_next = base_inc;
    case (e_fx)
      3'd1: fxi_next = arp_r;
      // PICO-8 multiplies its integer `dp`, then the FPGA phase convention
      // expands that result by eight bits.  Multiplying base_inc directly is
      // otherwise subtly more precise and accumulates audible phase drift.
      3'd2, 3'd3: fxi_next = {fxp_res[23:8], 8'b0};
      3'd6, 3'd7: fxi_next = arp_r;
      default: ;
    endcase
    fxv_next = vol_r;
    case (e_fx)
      3'd1: fxv_next = pvol_r + (vl_neg ? ~p8 : p8) + {7'b0, vl_neg};
      3'd4: fxv_next = p8;
      3'd5: fxv_next = vol_r - p8;
      default: ;
    endcase
  end

  // The publication pack, one inactive sounding word per P_W step. The
  // operands hold across all four cycles: arp_r and vol_r are the effect
  // program's result slots, p8 is the xs 6 product (the m service is idle
  // until the next slot's first launch), and everything else is a
  // register or a cone over registers.
  wire [23:0] pub_inc = (w_ins_on && w_ins_wt && w_ins_bass)
                          ? {1'b0, arp_r[23:1]} : arp_r;
  logic [15:0] pub_wd;
  always_comb begin
    case (sst)
      P_W0:    pub_wd = pub_inc[15:0];
      P_W1:    pub_wd = {1'b0, w_ins_id, (w_ins_on & w_ins_wt),
                         (ins_use ? w_ins_wave
                          : (w_ins_on && w_ins_wt) ? 3'd0 : w_cur_wave),
                         pub_inc[23:16]};
      P_W2:    pub_wd = {2'b0, w_ch_damp, w_ch_rev, w_ch_det, w_ch_buzz,
                         w_ch_noiz, e_pitch};
      default: pub_wd = {3'b0,
                         (w_cur_fx == 3'd1
                          || (w_ins_on && !w_ins_wt
                              && (w_cur_fx == 3'd0
                                  || w_cur_fx == 3'd3)
                              && w_ins_fx == 3'd1)),
                         (w_ins_on && !w_ins_wt
                          && (w_cur_fx == 3'd0 || w_cur_fx == 3'd3)
                          && (w_ins_fx == 3'd0
                              || w_ins_fx == 3'd4
                              || w_ins_fx == 3'd5)),
                         ((!w_ins_on && w_cur_fx == 3'd3)
                          || (w_ins_on && !w_ins_wt
                              && (w_cur_fx == 3'd0
                                  || w_cur_fx == 3'd3)
                              && w_ins_fx == 3'd3)),
                         clr_tog[c],
                         ((!w_ins_on
                           && (w_cur_fx == 3'd0
                               || w_cur_fx == 3'd4
                               || w_cur_fx == 3'd5))
                          || (w_ins_on && !w_ins_wt
                              && (w_cur_fx == 3'd0
                                  || w_cur_fx == 3'd3)
                              && (w_ins_fx == 3'd0
                                  || w_ins_fx == 3'd4
                                  || w_ins_fx == 3'd5))
                          || (w_ins_on && !w_ins_wt
                              && (w_cur_fx == 3'd4
                                  || w_cur_fx == 3'd5))),
                         is_mus(c) ? p8 : vol_r};
    endcase
  end

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
      for (int i = 0; i < NV; i++) begin
        playing[i] <= 0;
        sfx_id[i] <= 0;
        row[i] <= 0;
        released[i] <= 0;
      end
      for (int i = 0; i < NCH; i++) begin
        trg_row[i] <= 0;
        trg_len[i] <= 0;
      end
      // The record and parameter memories cannot reset per slot.  The working
      // copies do not need reset hardware either: V_LD replaces every record
      // field before K_ADV, and playing/trig_req validity gates the parameter
      // fields until T_/K_FX has produced them.
      vcnt <= 0;
      spar_bank <= 0;
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
      if (!walk_frozen && sst == T_NL && launched[c] && !tch_seen
          && !(acc[7:0] < seq_q) && m_busy)
        $error("T_NL pattern-length product blocked by a busy m service");
`endif
      // Boundary publication for the pre-run tick pass: the evaluation ran
      // during the preceding sample interval, so the tick edge itself only
      // flips the staged bank. No bank_ready means a trigger pass collided
      // with pre_tick and the tick pass has not finished; V_ST then flips
      // late via flip_pend. Placed before the state case deliberately: when
      // the pass completes on the boundary edge itself, V_ST's textually
      // later assignments win and the flip happens once, immediately.
      if (tick_en) begin
        if (bank_ready) begin
          spar_bank <= ~spar_bank;
          bank_ready <= 0;
        end else if (tickpend || (walk_tick && sst != S_IDLE))
          flip_pend <= 1;
        // Class-1 deferred stops become audible from the boundary sample.
        for (int i = 0; i < NV; i++)
          if (pend_stop[i]) playing[i] <= 0;
        pend_stop <= 0;
      end
      // Class-2 deferred stops (music flow) become audible one sample
      // later, where the frozen walk used to land them.
      if (sample_en && scnt == 8'd1) begin
        for (int i = 0; i < NV; i++)
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
          // While a staged publication awaits its boundary, hold new work: a
          // pass dispatched now would rewrite the staged bank and publish it
          // immediately, leaking the tick results before the boundary. The
          // hold is at most one sample, the same wait trigger work already
          // tolerated under the old coincident deferral.
          if (bank_ready) begin
          end else if (mus_launch) begin
            mus_launch <= 0;
            ml_cpu <= 1;
            sst <= ML_STOP;
          end else if (trig_req != 0 || tickpend) begin
            walk_tick <= tickpend;
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
            4'd1: {w_ins_bass, w_cur_wave, w_prev_pitch, w_cur_pitch} <= state_q;
            4'd2: {w_ins_done, w_bf_rev, w_bf_det, w_bf_buzz, w_bf_noiz,
                   w_prev_vol, w_cur_fx, w_cur_vol} <= state_q;
            4'd3: {w_ins_vol, w_ins_wave, w_ins_row, w_ins_id, w_bf_damp}
                    <= state_q;
            4'd4: w_ins_pitch <= state_q[13:8];   // word 8 read-copy refresh
            4'd5: {w_ins_wt, w_ins_on, w_ins_prev_vol, w_ins_fx,
                   w_ins_prev_pitch} <= state_q[13:0];
            // The carried channel filters: an instrument that continues
            // without a retrigger passes no filter-writing state, so the
            // active bank's word refreshes the w_ch_* registers the P_W2
            // publication reads.
            4'd6: {w_ch_damp, w_ch_rev, w_ch_det, w_ch_buzz, w_ch_noiz}
                    <= state_q[13:6];
            default: ;
          endcase
          if (vcnt == 4'd6) begin
            vcnt <= 0;
            sst <= K_ADV;
          end else
            vcnt <= vcnt + 1;
        end

        // ---- record store: one word per cycle, then on to the next slot ---
        V_ST: begin
          if (vcnt == 4'd3) begin
            vcnt <= 0;
            if (c == VW'(NV-1)) begin
              c <= 0;
              // A trigger pass publishes at once, as before. The tick pass
              // stages its bank for the boundary flip - unless the boundary
              // already passed (trigger collision at pre_tick), where it
              // flips immediately rather than holding the tick a period.
              if (!walk_tick)
                spar_bank <= ~spar_bank;
              else if (tick_en | flip_pend) begin
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
          row[c] <= is_mus(c) ? 5'd0 : trg_row[c[1:0]];
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
            if (!tch_seen && !(acc[7:0] < seq_q)) begin
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
          w_cur_pitch <= note_lo[5:0];
          w_cur_wave  <= {seq_q[0], note_lo[7:6]};
          w_cur_vol   <= seq_q[3:1];
          w_cur_fx    <= seq_q[6:4];
          if (seq_q[7]) begin               // custom instrument: always new
            w_ins_on <= 1;
            w_ins_id <= {seq_q[0], note_lo[7:6]};
            sst <= I_TR0;
          end else
            sst <= ES0;
        end

        // ---- per-tick walk: the engine's advance sequence -------------
        // One sequence for both banks. The note pass runs it on words 0..2
        // with row[c], playing and play_len; the instrument pass on words
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
              if (w_ins_on && !w_ins_wt) begin
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
            if (wrd[13:8] == 6'd1 || row[c] == 5'd31) begin
              pend_stop[c] <= 1;             // visible from the boundary
              cpz <= 1;                      // publish a zero volume
              sst <= K_ROT;
            end else begin
              // the engine write this cycle decrements the length in place
              row[c] <= row[c] + 1;
              sst <= K_NL;
            end
          end else if (acc[7:0] < acc[15:8] && (abank || !released[c])
                       && ge_lpe) begin
            if (!abank) begin
              row[c] <= acc[4:0];
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
              row[c] <= row[c] + 1;
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
          w_cur_pitch <= note_lo[5:0];
          w_cur_wave  <= {seq_q[0], note_lo[7:6]};
          w_cur_vol   <= seq_q[3:1];
          w_cur_fx    <= seq_q[6:4];
          if (seq_q[7]) begin
            w_ins_on <= 1;
            w_ins_id <= {seq_q[0], note_lo[7:6]};
            // retrigger on a pitch change, after a silent note, on a new
            // instrument, or when the note asks for it with effect 3
            if (!w_ins_on || w_ins_id != {seq_q[0], note_lo[7:6]} ||
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
          w_ins_wave  <= {seq_q[0], note_lo[7:6]};
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
        K_FX: if (!m_busy) begin
          if (xs == 0) arp_r <= pinc_q;
          case (xs)
            4'd1: u_r    <= p8;
            4'd3: vol_r  <= ins_use ? (w_ins_done ? 8'd0 : p8) : vol_direct;
            4'd4: pvol_r <= ins_use ? p8 : pvol_direct;
            // arp_r and vol_r are dead after their respective effect
            // calculations, so they become the publication result slots.
            4'd5: arp_r  <= fxi_next;
            4'd6: vol_r  <= fxv_next;
            default: ;
          endcase
          if (xs == 4'd2 && e_fx == 3'd1) begin
            // Product 1 is |pitch delta| × Q8 row fraction. Convert the
            // interpolated raw pitch to a table address before continuing the
            // ordinary effect program; this is pitch-domain slide, not the
            // former (incorrect) phase-increment interpolation.
            slide_addr <= slp_int;
            sst <= K_SLP0;
          end else if (xs == 4'd7) begin
              // Publication runs P_W0..P_W3, writing the four inactive
              // sounding words directly; arp_r, vol_r, the final product
              // and the identity registers hold every operand.
              xs <= 0;
              sst <= P_W0;
          end else begin
            xs    <= xs + 1;
          end
        end
        K_SLP0: sst <= K_SLP1;       // issue/read the lower semitone
        K_SLP1: begin
          // _get_dx_for_note_fine linearly interpolates the two adjacent
          // integer-note increments using the fractional 16.16 pitch. Our row
          // fraction is Q8, so retain those eight useful fractional bits and
          // borrow a second synchronous table read.
          arp_r <= pinc_q;
          sst <= K_SLP2;
        end
        K_SLP2: begin
          // pinc_q is the upper semitone. Reuse the iterative multiplier for
          // (upper-lower)*fraction; this trades 8 clocks for the combinational
          // fine-pitch network PICO-8's software implementation can afford.
          sst   <= K_SLPM;
        end
        K_SLPM: if (!m_busy) begin
          arp_r <= arp_r + p24;
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
                for (int i = NCH; i < NV; i++) begin
                  pend_stop2[i] <= 1;      // visible one sample past the boundary
                          end
              end else if (f_lb) begin
                scan_p <= mus_pat;
                ml_cpu <= 0;
                sst <= MS_RD;
              end else if (mus_pat == 6'd63) begin
                mus_playing <= 0;
                for (int i = NCH; i < NV; i++) begin
                  pend_stop2[i] <= 1;
                          end
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
          for (int i = NCH; i < NV; i++) begin
            if (ml_cpu)
              playing[i] <= 0;
            else
              pend_stop2[i] <= 1;
              end
          launched <= 0;
          sst <= ML_RD0;
        end
        // Each channel launches from its byte as it lands - the pattern
        // staging registers are gone. Every enabled channel launches on its
        // MUSIC slot (NCH+c), never the foreground slot: a sound effect on
        // channel c cannot be disturbed by the song, and vice versa. The
        // four trig_req bits now set over four cycles, which nothing
        // observes: the walk cannot dispatch mid-chain and $03 reads only
        // the foreground bits. $21 stays readable but advisory.
        ML_RD0: sst <= ML_L0;
        ML_L0: begin
          if (!seq_q[6]) begin
            trig_req[NCH+0] <= 1;
            sfx_id[NCH+0] <= seq_q[5:0];
            launched[NCH+0] <= 1;
          end
          sst <= ML_L1;
        end
        ML_L1: begin
          f_lb <= seq_q[7];
          if (!seq_q[6]) begin
            trig_req[NCH+1] <= 1;
            sfx_id[NCH+1] <= seq_q[5:0];
            launched[NCH+1] <= 1;
          end
          sst <= ML_L2;
        end
        ML_L2: begin
          f_stop <= seq_q[7];
          if (!seq_q[6]) begin
            trig_req[NCH+2] <= 1;
            sfx_id[NCH+2] <= seq_q[5:0];
            launched[NCH+2] <= 1;
          end
          sst <= ML_L3;
        end
        ML_L3: begin
          if (!seq_q[6]) begin
            trig_req[NCH+3] <= 1;
            sfx_id[NCH+3] <= seq_q[5:0];
            launched[NCH+3] <= 1;
          end
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
              for (int i = NCH; i < NV; i++) begin
                pend_stop[i] <= 1;            // visible from the boundary
                      end
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
            for (int i = NCH; i < NV; i++) begin
              playing[i] <= 0;
                  end
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

  // ------------------------------------------------------------------
  // Synthesis and mixing: one walk over the four channels per sample, with
  // the channels' oscillator state in a ring whose head is the channel
  // being processed (same trick as the sequencer's). Per channel:
  //   pst0 advance phase(s), issue the main wave read, honour a filter
  //        clear the sequencer asked for
  //   pst1 bank the main sample, issue the second voice's read
  //   pst2 bank the second sample, pick the waveform, run the dampen
  //        one-pole and start sample x volume on the small multiplier
  //   pst3 wait for it, accumulate, write the dampen state back into the
  //        slot the ring is about to rotate it into, and step on
  // ------------------------------------------------------------------
  logic [14:0] lfsr;
  logic [VW-1:0] pc_ch;
  // A slot's visit is deliberately long and serial. It loads the oscillator
  // words followed by the active four-word parameter bank, renders the new and
  // old continuations through one wave port, runs both sample×volume products
  // through one multiplier, then runs the 6-bit blend weight through one more
  // shift-add sequence. The derived PSG clock is 28.125 MHz, giving at least
  // 1275 clocks per sample. The complete eight-slot walk remains below 550.
  // The interactive simulator can select the compact schedule that preceded
  // the old-state crossfade renderer. It keeps live audio at the simulator's
  // intentionally lowered chip clock; hardware and oracle builds use the full
  // schedule below. REALTIME_PREVIEW is a constant, so the unused schedule is
  // removed during lowering rather than becoming runtime selection logic.
  logic signed [7:0] wq, wrom_q, smp_a, smp_b, old_smp;
  logic signed [7:0] wt_p1, wt_q1;
  logic [9:0] wt_pf, wt_qf;
  logic wi_neg;
  logic [2:0] wsel;
  logic [2:0] wsel_q;
  logic [7:0] wph;
  logic [7:0] wph_q;
  logic       wbank;
  logic [8:0] wrom_addr;
  logic [NV-1:0] clr_ack;              // pairs with the sequencer's clr_tog

  // Record streaming for the synthesis walk. Reads are issued on the load
  // cycles and land one cycle later; the oscillator write-back runs on the
  // store cycles, addressing word pph-PSTOR.
  wire [3:0] s_stw = 4'(pph - 7'(PSTOR));
  always_comb begin
    if (REALTIME_PREVIEW) begin
      case (s_stw)
        4'd0:    sosc_wd = s_phase[15:0];
        4'd1:    sosc_wd = {s_nz_hold, s_phase[23:16]};
        4'd2:    sosc_wd = s_phase2[15:0];
        4'd3:    sosc_wd = {4'b0, s_nz_ph, s_phase2[23:16]};
        4'd4:    sosc_wd = {3'b0, s_brown};
        4'd5:    sosc_wd = s_lp;
        4'd6:    sosc_wd = s_noise_lp;
        default: sosc_wd = 16'd0;
      endcase
    end else begin
      case (s_stw)
        4'd0:    sosc_wd = s_phase[15:0];
        4'd1:    sosc_wd = {s_nz_hold, s_phase[23:16]};
        4'd2:    sosc_wd = s_phase2[15:0];
        4'd3:    sosc_wd = {4'b0, s_nz_ph, s_phase2[23:16]};
        4'd4:    sosc_wd = {3'b0, s_brown};
        4'd5:    sosc_wd = s_lp;
        4'd6:    sosc_wd = s_old_phase[15:0];
        4'd7:    sosc_wd = {s_ramp, 1'b0, s_old_phase[23:16]};
        4'd8:    sosc_wd = s_old_inc[15:0];
        4'd9:    sosc_wd = {s_old_vol, s_old_inc[23:16]};
        4'd10:   sosc_wd = {s_last_pitch[4:0], s_last_wave,
                            s_last_inc[23:16]};
        4'd11:   sosc_wd = s_last_inc[15:0];
        4'd12:   sosc_wd = {1'b0, s_last_slide, s_fx_phase_entry,
                            s_last_trigger,
                            s_last_pitch[5],
                            s_old_wave, s_last_vol};
        default: sosc_wd = s_noise_lp;
      endcase
    end
  end

  // Load and store sequences over the register-resident words. The
  // flow-owned family words (0..2 and 6..8) never appear here: the engine
  // reads, modifies and writes them in place through the same two port
  // sites. The bank is an explicit argument so simulators include it in
  // combinational sensitivity.
  function automatic logic [4:0] tick_load_word(
      input logic [3:0] n, input logic bank);
    case (n)
      4'd0: tick_load_word = 5'd3;
      4'd1: tick_load_word = 5'd4;
      4'd2: tick_load_word = 5'd5;
      4'd3: tick_load_word = 5'd8;         // ins_pitch read-copy refresh
      4'd4: tick_load_word = 5'd9;
      // Active filter word for the carried w_ch_* refresh.
      default: tick_load_word = (bank ? V_PAR1 : V_PAR0) + 5'd2;
    endcase
  endfunction
  function automatic logic [4:0] tick_store_word(
      input logic [3:0] n, input logic bank);
    case (n)
      4'd0: tick_store_word = 5'd3;
      4'd1: tick_store_word = 5'd4;
      4'd2: tick_store_word = 5'd5;
      default: tick_store_word = 5'd9;
    endcase
  endfunction

  // Engine read requests: addresses are pure functions of the held state,
  // so a read displaced by a sample walk re-issues itself, and a consume
  // state re-issues the displaced word during the replay cycle (the V_LD
  // pattern, generalized).
  wire [4:0] par_act = spar_bank ? V_PAR1 : V_PAR0;   // active bank base
  wire [4:0] par_ina = spar_bank ? V_PAR0 : V_PAR1;   // inactive (publish)
  logic       eng_rd;
  logic [4:0] eng_word;
  always_comb begin
    eng_rd = 1'b1;
    eng_word = 5'd0;
    case (sst)
      EA0:  eng_word = abank ? 5'd6 : 5'd0;
      EA1:  eng_word = state_replay ? (abank ? 5'd6 : 5'd0)
                                    : (abank ? 5'd8 : 5'd2);
      EA2:  eng_word = state_replay ? (abank ? 5'd8 : 5'd2)
                                    : (abank ? 5'd7 : 5'd1);
      EA3:  begin
              eng_word = abank ? 5'd7 : 5'd1;
              eng_rd = state_replay;
            end
      ES0:  eng_word = e_insfx ? 5'd6 : 5'd0;
      ES1:  eng_word = state_replay ? (e_insfx ? 5'd6 : 5'd0)
                                    : (e_insfx ? 5'd8 : 5'd2);
      ES2:  begin
              eng_word = e_insfx ? 5'd8 : 5'd2;
              eng_rd = state_replay;
            end
      // The skipped-slot copy reads the ACTIVE sounding words.
      K_ROT: eng_word = par_act;
      PC0:   eng_word = state_replay ? par_act : par_act + 5'd1;
      PC1:   eng_word = state_replay ? par_act + 5'd1 : par_act + 5'd2;
      PC2:   eng_word = state_replay ? par_act + 5'd2 : par_act + 5'd3;
      PC3:   begin
               eng_word = par_act + 5'd3;
               eng_rd = state_replay;
             end
      default: eng_rd = 1'b0;
    endcase
  end

  // Engine store requests, one per state, selected before the single
  // physical write site below.
  logic        eng_we;
  logic [4:0]  eng_wa;
  logic [15:0] eng_wd;
  wire [7:0] sp_in = (seq_q == 0) ? 8'd1 : seq_q;
  // The mod-32 trigger seed: row * speed's low bits (design 5b, stage 4).
  wire [4:0] seed5 = 5'(row[c] * sp_in[4:0]);
  always_comb begin
    eng_we = 1'b1;
    eng_wa = 5'd0;
    eng_wd = 16'd0;
    case (sst)
      T_LS:  begin eng_wa = 5'd0; eng_wd = {3'b0, seed5, 8'b0}; end
      T_NL:  begin eng_wa = 5'd1; eng_wd = {seq_q, acc[7:0]}; end
      T_NH:  begin eng_wa = 5'd2; eng_wd = {2'b0, wrd[13:8], wrd[7:0]}; end
      I_TR0: begin eng_wa = 5'd6; eng_wd = 16'd0; end
      I_TR2: begin eng_wa = 5'd8; eng_wd = {2'b0, w_ins_pitch, sp_in}; end
      I_TR4: begin eng_wa = 5'd7; eng_wd = {seq_q, acc[7:0]}; end
      I_TW:  begin eng_wa = 5'd8; eng_wd = {2'b0, 6'd24, wrd[7:0]}; end
      I_LD:  begin eng_wa = 5'd8; eng_wd = {2'b0, note_lo[5:0], wrd[7:0]}; end
      EA2:   begin
               eng_wa = abank ? 5'd6 : 5'd0;
               eng_wd = {acc[15:8] + 8'd1,
                         ta_ge ? 8'd0 : acc[7:0] + 8'd1};
             end
      EA5:   begin
               // The explicit-length decrement, note bank only; the other
               // EA5 outcomes write no word.
               eng_wa = 5'd2;
               eng_wd = {2'b0, wrd[13:8] - 6'd1, wrd[7:0]};
               eng_we = !abank && wrd[13:8] != 0
                        && !(wrd[13:8] == 6'd1 || row[c] == 5'd31);
             end
      // Direct publication and the skipped-slot copy.
      P_W0:  begin eng_wa = par_ina;         eng_wd = pub_wd; end
      P_W1:  begin eng_wa = par_ina + 5'd1;  eng_wd = pub_wd; end
      P_W2:  begin eng_wa = par_ina + 5'd2;  eng_wd = pub_wd; end
      P_W3:  begin eng_wa = par_ina + 5'd3;  eng_wd = pub_wd; end
      PC0:   begin eng_wa = par_ina;         eng_wd = state_q; end
      PC1:   begin eng_wa = par_ina + 5'd1;  eng_wd = state_q; end
      PC2:   begin eng_wa = par_ina + 5'd2;  eng_wd = state_q; end
      PC3:   begin eng_wa = par_ina + 5'd3;
               eng_wd = cpz ? {state_q[15:8], 8'd0} : state_q;
             end
      default: eng_we = 1'b0;
    endcase
    if (walk_frozen)
      eng_we = 1'b0;
  end

  wire state_tick_we = (sst == V_ST) && !walk_frozen;
  logic [3:0] tick_issue;
  always_comb begin
    // Normal V_LD issues word n while consuming word n-1. If a sample stole
    // the port, replay n-1 once, then normal addressing resumes on the cycle
    // that consumes it.
    tick_issue = vcnt;
    if (state_replay && sst == V_LD && vcnt != 0)
      tick_issue = vcnt - 1'b1;

    state_ra = eng_rd ? {c, eng_word}
                      : {c, tick_load_word(tick_issue, spar_bank)};
    if (state_sample_read) begin
      if (pph < 7'(PLOSC))
        state_ra = {pc_ch, V_OSC + 5'(pph)};
      else if (pph < 7'(PLOSC + SPAR))
        state_ra = {pc_ch, (spar_bank ? V_PAR1 : V_PAR0)
                           + 5'(pph - 7'(PLOSC))};
      else
        state_ra = {pc_ch, V_OSC};
    end

    // Sample write-back has absolute priority. The tick engine is frozen for
    // the complete sample walk, so these owners never contend in practice;
    // retaining explicit priority makes that port contract structural.
    state_we = state_sample_we | state_tick_we | eng_we;
    if (state_sample_we) begin
      state_wa = {pc_ch, V_OSC + 5'(s_stw)};
      state_wd = sosc_wd;
    end else if (eng_we) begin
      state_wa = {c, eng_wa};
      state_wd = eng_wd;
    end else begin
      state_wa = {c, tick_store_word(vcnt, spar_bank)};
      state_wd = vwdata;
    end
  end

  // Exactly one synchronous read site and one write site: this is the shape
  // expected to lower to a single SB_RAM40_4K simple-dual-port instance.
  always_ff @(posedge clk) begin
    if (state_we)
      state_m[state_wa] <= state_wd;
    state_q <= state_m[state_ra];
  end

  always_comb begin
    wsel = s_snd_wave;
    wph = s_phase[23:16];
    if (pph == 7'(PWORK + 1))
      wph = s_phase2[23:16];        // second voice
    else if (pph == 7'(PWORK + 2)) begin
      wsel = s_old_wave;
      wph = s_old_phase[23:16];     // old-state continuation
    end

    wbank = (wsel == 3'd5);
    wrom_addr = {wbank, wph};
  end
  always_ff @(posedge clk) begin
    wrom_q <= wrom[wrom_addr];
    wsel_q <= wsel;
    wph_q <= wph;
  end
  // The recovered tilted-saw slopes are 127/112 and -127/16. Their nearest
  // one-add shift forms stay within three sample units.
  wire signed [9:0] tsaw_rise =
      $signed({2'b0, wph_q}) + $signed({5'b0, wph_q[7:3]}) - 10'sd127;
  wire [4:0] tsaw_tail = wph_q[4:0];
  wire signed [9:0] tsaw_fall =
      10'sd127 - $signed({2'b0, tsaw_tail, 3'b0});
  wire signed [7:0] tsaw_formula =
      wph_q < 8'd224 ? tsaw_rise[7:0] : tsaw_fall[7:0];
  // A two-chain 5/8 ramp retains the recovered saw's shape to within four
  // sample units. Its level is adjudicated by the oracle's fitted-gain gate.
  wire signed [8:0] saw_phase =
      $signed({1'b0, wph_q}) - 9'sd128;
  wire signed [9:0] saw_phase_wide = {saw_phase[8], saw_phase};
  wire signed [9:0] saw_formula_wide =
      saw_phase_wide - (saw_phase_wide >>> 2) - (saw_phase_wide >>> 3);
  wire signed [7:0] saw_formula = saw_formula_wide[7:0];
  always_comb begin
    case (wsel_q)
      3'd1:   wq = tsaw_formula;
      3'd2:   wq = saw_formula;
      3'd3:   wq = (wph_q < 8'h80) ? -8'sd64 : 8'sd64;
      3'd4:   wq = (wph_q < 8'hb0) ? -8'sd64 : 8'sd64;
      3'd6:   wq = 8'sd0;
      default: wq = wrom_q;
    endcase
  end

  // Second voice: phaser preset (~109/110) on wave 7, else the detune ratio
  wire [23:0] einc = s_eff_inc;
  // PICO-8 keeps a 17-bit secondary phase and computes DETUNE-1's increment
  // as trunc(dp * 255 / 256).  The FPGA phase has eight additional fractional
  // bits. ceil(dp/256) is subtracted on a second phase-ALU clock, retaining
  // the exact truncated 16-bit result followed by eight zeroes.
  wire [8:0] det_ceil =
      {1'b0, einc[23:16]} + 9'(|einc[15:8]);
  // The deliberately compact simulator preview still uses its original
  // single-cycle secondary increment. REALTIME_PREVIEW is a parameter, so
  // this complete network is removed from hardware and oracle builds.
  wire [16:0] preview_det_round = {1'b0, einc[23:8]} + 17'd255;
  wire [16:0] preview_det_wide =
      {1'b0, einc[23:8]} - {8'b0, preview_det_round[16:8]};
  wire [23:0] preview_v2inc =
      s_snd_wt ? einc :
      (s_snd_wave == 3'd7) ? (einc - {7'b0, einc[23:7]}
                                        - {10'b0, einc[23:10]}
                                        - {12'b0, einc[23:12]}) :
      (s_ch_det == 2'd1)   ? {preview_det_wide[15:0], 8'b0} :
      (s_ch_det == 2'd2)   ? {einc[22:0], 1'b0} :
                                  24'd0;
  wire pitch_transition = playing[pc_ch] && !s_snd_wt
                        && s_pitch_direct
                        && s_eff_inc != s_last_inc
                        && s_last_vol != 0
                        && (s_snd_wave == s_last_wave
                            || s_compound_direct)
                        && s_snd_pitch != s_last_pitch;
  wire trigger_transition = playing[pc_ch]
                          && s_trigger_tag != s_last_trigger;
  wire transition_change = playing[pc_ch] && !s_snd_wt
                         && (trigger_transition
                             || s_eff_inc != s_last_inc
                             || s_eff_vol != s_last_vol
                             || s_snd_wave != s_last_wave);
  wire v2_on = s_snd_wt || (s_snd_wave == 3'd7) || (s_ch_det != 0);

  // Transition phase corrections used to be five independent 24-bit
  // expressions feeding s_phase, alongside separate current, secondary and
  // old-phase adders. The sample schedule has idle clocks, so select one phase
  // operation before a single add/sub datapath and execute the two-term
  // corrections over two clocks.
  localparam logic [2:0] PH_ADV       = 3'd0;
  localparam logic [2:0] PH_OLD_SUB   = 3'd1;
  localparam logic [2:0] PH_OLD_ADD   = 3'd2;
  localparam logic [2:0] PH_HOLD      = 3'd3;
  localparam logic [2:0] PH_NEW2      = 3'd4;
  logic [2:0] phase_op;
  always_comb begin
    phase_op = PH_ADV;
    if (transition_change) begin
      if (s_slide_effect && s_eff_inc != s_last_inc
          && s_last_vol != 0 && s_snd_wave == s_last_wave
          && !trigger_transition)
        phase_op = PH_OLD_SUB;
      else if (pitch_transition && s_compound_direct
               && s_snd_wave != s_last_wave && !trigger_transition)
        phase_op = PH_OLD_SUB;
      else if (pitch_transition && s_last_slide && !trigger_transition)
        phase_op = PH_OLD_ADD;
      else if (pitch_transition && !trigger_transition && !s_last_slide)
        phase_op = PH_HOLD;
      else if (s_drop_effect && s_eff_inc != s_last_inc
               && s_last_vol != 0 && s_snd_wave == s_last_wave
               && !trigger_transition)
        phase_op = s_fx_phase_entry ? PH_OLD_SUB : PH_NEW2;
    end
  end

  // The soft_add fold engine borrows this ALU whenever fmc is nonzero; its
  // operands are prepared in the mixer section, where the stack lives.
  logic [23:0] fold_a, fold_b;
  logic        fold_sub, fold_cin;
  logic [23:0] phase_alu_a, phase_alu_b;
  logic phase_alu_sub, phase_alu_cin;
  always_comb begin
    phase_alu_a = s_phase;
    phase_alu_b = einc;
    phase_alu_sub = 1'b0;
    phase_alu_cin = 1'b0;
    if (fold_busy) begin
      phase_alu_a = fold_a;
      phase_alu_b = fold_b;
      phase_alu_sub = fold_sub;
      phase_alu_cin = fold_cin;
    end else
    case (pph)
      7'(PWORK): begin
        case (phase_op)
          PH_OLD_SUB: phase_alu_b = {s_last_inc[22:0], 1'b0};
          PH_OLD_ADD: phase_alu_b = s_eff_inc;
          PH_NEW2:    phase_alu_b = {s_eff_inc[22:0], 1'b0};
          default: ;
        endcase
      end
      7'(PWORK + 1): begin
        if (!s_snd_wt && phase_op == PH_OLD_SUB) begin
          phase_alu_b = s_eff_inc;
          phase_alu_sub = 1'b1;
        end else if (!s_snd_wt && phase_op == PH_OLD_ADD)
          phase_alu_b = s_last_inc;
      end
      7'(PWORK + 5): begin
        phase_alu_a = s_old_phase;
        phase_alu_b = s_old_inc;
      end
      7'(PWORK + 6): begin
        phase_alu_a = s_phase2;
        if (s_snd_wt)
          phase_alu_b = einc;
        else if (s_snd_wave == 3'd7)
          phase_alu_b = einc;
        else if (s_ch_det == 2'd1)
          phase_alu_b = {einc[23:8], 8'b0};
        else
          phase_alu_b = {einc[22:0], 1'b0};
      end
      7'(PWORK + 7): begin
        phase_alu_a = s_phase2;
        phase_alu_sub = 1'b1;
        phase_alu_b = (s_snd_wave == 3'd7)
                        ? {7'b0, einc[23:7]}
                        : {7'b0, det_ceil, 8'b0};
      end
      7'(PWORK + 8): begin
        phase_alu_a = s_phase2;
        phase_alu_b = {10'b0, einc[23:10]};
        phase_alu_sub = 1'b1;
      end
      7'(PWORK + 9): begin
        phase_alu_a = s_phase2;
        phase_alu_b = {12'b0, einc[23:12]};
        phase_alu_sub = 1'b1;
      end
      default: ;
    endcase
  end
  // One physical carry chain: a - b is a + ~b + 1, and the fold's single
  // "+1" micro-op rides the same carry-in, so subtract and add no longer
  // build two 24-bit adders behind a result mux.
  wire [23:0] phase_alu_y =
      phase_alu_a + (phase_alu_sub ? ~phase_alu_b : phase_alu_b)
                  + {23'b0, phase_alu_sub | phase_alu_cin};

  // Wavetable instruments read their 64 samples out of audio RAM, one
  // borrowed read per voice per sample (the sequencer FSM freezes for it).
  always_comb begin
    syn_rd   = 1'b0;
    syn_addr = 13'd0;
    if (prun && s_snd_wt && playing[pc_ch]) begin
      if (pph == 7'(PWORK)) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb + {7'b0, s_phase[23:18]};
      end else if (!REALTIME_PREVIEW && pph == 7'(PWORK + 1)) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb
                 + {7'b0, s_phase[23:18] + 6'd1};
      end else if (pph == 7'(PWORK + (REALTIME_PREVIEW ? 1 : 2))
                   && v2_on) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb + {7'b0, s_phase2[23:18]};
      end else if (!REALTIME_PREVIEW && pph == 7'(PWORK + 3)
                   && v2_on) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb
                 + {7'b0, s_phase2[23:18] + 6'd1};
      end
    end
  end

  // ---- waveform selection (head of the ring = this channel) ----------
  // BUZZ square/pulse: shifted duty straight from the phase counter
  wire [7:0] mph = s_phase[23:16];
  wire signed [7:0] buzzsq =
      // PICO-8's alternate square/pulse thresholds are 0x9800 and 0xc800.
      // The old approximation used the complementary duty and polarity.
      (s_snd_wave == 3'd3) ? (mph < 8'd152 ? -8'sd63 : 8'sd63)
                           : (mph < 8'd200 ? -8'sd63 : 8'sd63);
  wire signed [10:0] ph_sum =
      $signed({smp_a[7], smp_a, 1'b0}) + $signed({{3{smp_b[7]}}, smp_b});
  wire signed [18:0] ph_wide = {{8{ph_sum[10]}}, ph_sum};
  wire signed [8:0] det_sum =
      $signed({smp_a[7], smp_a}) + $signed({{2{smp_b[7]}}, smp_b[7:1]});
  // The built-in waveform tables are already calibrated to PICO-8's combined
  // oscillator level. A DETUNE secondary needs 5/6 pre-mix normalisation, not
  // an unnormalised +1/2 voice. 53/64 is the nearest cheap shift-only form and
  // keeps the three pitch guards within one percent of the exported level.
  wire signed [10:0] det_norm =
      $signed({{2{det_sum[8]}}, det_sum})
      - ($signed({{2{det_sum[8]}}, det_sum}) >>> 3)
      - ($signed({{2{det_sum[8]}}, det_sum}) >>> 5)
      - ($signed({{2{det_sum[8]}}, det_sum}) >>> 6);
  wire signed [7:0] det_clip =
      det_norm > 11'sd127 ? 8'sd127
    : det_norm < -11'sd127 ? -8'sd127 : det_norm[7:0];
  wire signed [7:0] det_raw_clip =
      det_sum > 9'sd127 ? 8'sd127
    : det_sum < -9'sd127 ? -8'sd127 : det_sum[7:0];
  wire signed [8:0] wt_pd =
      $signed({wt_p1[7], wt_p1}) - $signed({smp_a[7], smp_a});
  wire signed [8:0] wt_qd =
      $signed({wt_q1[7], wt_q1}) - $signed({smp_b[7], smp_b});
  // Signed arithmetic right shift rounds a negative fractional delta down.
  // The shared multiplier works on magnitudes, so add one when any discarded
  // fractional bit is set before reapplying a negative sign.
  wire [8:0] wi_mag_floor = m_res_wide[18:10];
  wire [8:0] wi_mag_ceil = wi_mag_floor + 9'(|m_res_wide[9:0]);
  wire signed [9:0] wi_delta =
      wi_neg ? -$signed({1'b0, wi_mag_ceil})
             :  $signed({1'b0, wi_mag_floor});

  // The nz_gain sample-and-hold gain path died in the fidelity rework: the
  // built-in noise became the one-pole s_noise_lp process below, nothing
  // consumed nz_scaled, and synthesis had already trimmed the whole cone.
  // The table, its hex load and the 8x8 multiply are gone with it.
  // Built-in noise is a stateful one-pole process, not a flat sample-and-hold.
  // Q8 coefficient 15/16 gives the exported reference's short-lag decay;
  // x3 restores the oscillator's higher noise gain before its separate 3/2
  // product scaling below.
  wire signed [15:0] noise_target = $signed({lfsr[7:0], 8'b0});
  // The subtraction needs its carry bit: opposite-sign endpoints can differ
  // by almost 65535, and a 16-bit subtraction wraps into positive feedback.
  wire signed [16:0] noise_delta =
      $signed({noise_target[15], noise_target})
      - $signed({s_noise_lp[15], s_noise_lp});
  wire signed [16:0] noise_step =
      $signed({s_noise_lp[15], s_noise_lp}) + (noise_delta >>> 4);
  wire signed [15:0] noise_next = noise_step[15:0];
  wire signed [9:0] noise_x3 =
      $signed({{2{s_noise_lp[15]}}, s_noise_lp[15:8]})
      + ($signed({{2{s_noise_lp[15]}}, s_noise_lp[15:8]}) <<< 1);
  wire signed [7:0] noise_shaped =
      noise_x3 > 10'sd127 ? 8'sd127
    : noise_x3 < -10'sd127 ? -8'sd127 : 8'(noise_x3);

  // x * 85 as two adds instead of a multiplier: 85 = 5 * 17, so x*5 = x + 4x
  // and (x*5)*17 = 5x + 80x. Exactly the same product, so the phaser is
  // bit-identical - it just stops asking yosys for an array multiplier.
  wire signed [26:0] ph_w5  = 27'(ph_wide) + 27'(ph_wide <<< 2);
  wire signed [26:0] ph_x85 = ph_w5 + (ph_w5 <<< 4);

  logic signed [7:0] samp;
  always_comb begin
    if (s_snd_wt)
      samp = det_raw_clip;              // custom(p) + custom(q)/2
    else case (s_snd_wave)
      3'd6: samp = (s_ch_buzz && !s_ch_noiz)
                     ? s_brown[12:5]                               // brown
                     : noise_shaped;
      // Phaser. The multiply MUST be done at full width: ph_sum is 11 bits and
      // so was the constant, so the product was evaluated modulo 2^11 and
      // 381*85 = 32385 wrapped to -383, leaving the phaser at 3% of its proper
      // amplitude - inaudible. It is two triangles summed 2:1 and scaled by
      // 85/256, which peaks at 126, i.e. the same full scale as any other wave.
      3'd7: samp = 8'(ph_x85 >>> 8);                                // phaser
      3'd3, 3'd4:
            samp = s_ch_buzz ? buzzsq
                 : (s_ch_det != 0) ? det_clip : smp_a;
      default:
            samp = (s_ch_det != 0) ? det_clip : smp_a;
    endcase
  end

  // DAMPEN: per-channel one-pole low-pass (Q8), shift by damp level
  wire signed [15:0] samp_q8 = signed'({samp, 8'b0});
  // Keep the subtraction's carry bit. Opposite-sign endpoints can span almost
  // the full 16-bit unsigned range; evaluating it at 16 bits wraps the first
  // square-wave edge and produces an alternating full-scale transient instead
  // of PICO-8's 0, 1/2, 3/4, 7/8... response.
  wire signed [16:0] lp_delta =
      $signed({samp_q8[15], samp_q8})
      - $signed({s_lp[15], s_lp});
  wire signed [16:0] lp_step =
      $signed({s_lp[15], s_lp}) + (lp_delta >>> s_ch_damp);
  wire signed [15:0] lp_next = lp_step[15:0];
  wire signed [7:0] samp_d = (s_ch_damp == 0) ? samp : lp_next[15:8];

  // Sample x volume, back to an 8-iteration shift-add - and this is the third
  // position this multiply has been in, so the reasoning is worth recording.
  //
  // A single-cycle array version cost 346 LC and nextpnr named it as the
  // critical path (prun -> product accumulator). The hardware-derived sample deadline has
  // ample slack, so the multiplier is serial and its iterations are hidden
  // under the record
  // write-back rather than added to the visit: the store phase does not depend
  // on the product, so the 8 steps run concurrently with it. The architectural
  // PSG clock is derived from the >=100 MHz master clock; Verilator lowering
  // and host throughput are not cycle-budget requirements. The magnitude is
  // multiplied and the sign reapplied, so the product is bit-for-bit what the
  // array multiplier produced.
  logic        mx_neg, mx_play;
  // Whether this slot is HEARD, as opposed to merely running. A music slot is
  // silenced while its channel's foreground effect plays, but it still renders:
  // its phase, effects, row position and filter state all keep advancing, and
  // it still steps the shared noise LFSR. Only the mixer leaf is zeroed. That
  // is what makes the song reappear at its current position rather than where
  // it was interrupted, so mx_play (does it run) and mx_aud (is it audible)
  // must stay separate.
  logic        mx_aud;
  logic signed [15:0] mx_lp;
  logic [1:0]  mx_rev, mx_damp;
  wire [7:0] n_mag =
      samp_d[7] ? ((samp_d == -8'sd128) ? 8'd127 : 8'(-samp_d))
                : 8'(samp_d);
  // Custom waveforms add two signed table results before oscillator scaling,
  // so their exact range is wider than one sample byte. Keep that ninth bit
  // through the same eight-cycle sample-by-volume multiply. Their expanded
  // table values use PICO-8's approximately 8/9 oscillator scale before
  // volume. 57/64 is the nearest one-add shift-only form.
  wire signed [8:0] wt_mix = det_sum;
  wire signed [8:0] wt_scaled =
      wt_mix - (wt_mix >>> 3) + (wt_mix >>> 6);
  wire [8:0] n_mag9 =
      s_snd_wt
        ? (wt_scaled[8] ? 9'(-wt_scaled) : 9'(wt_scaled))
        : {1'b0, n_mag};
  // The full 16-bit product, not its top byte. Truncating here cost the most
  // resolution anywhere in the chip: a note at PICO-8 volume 1 has eff_vol 36,
  // so (127*36)>>8 = 17 levels - 4.2 bits. Two thirds of NEMO's title music is
  // volume 1 or 2. Keeping the low half makes those 12.2 and 13.2 bits.
  // The tick and sample schedules cannot overlap, so sample x volume and the
  // transition blend also use the effect engine's 24x8 shift-add service.
  // Padding the 6-bit blend weight to eight bits costs two otherwise idle
  // cycles and leaves one accumulator, counter, adder and result write site
  // for all three product families.
  wire signed [16:0] nm_signed = $signed(
      (m_res[16:0] ^ {17{mx_neg}}) + {16'b0, mx_neg});
  wire signed [16:0] nm_noise_scaled = nm_signed + (nm_signed >>> 1);
  logic signed [16:0] mx_new, mx_old, mx_prod;
  wire signed [16:0] blend_diff = mx_new - mx_old;
  wire [15:0] blend_mag = blend_diff[16] ? 16'(-blend_diff) : 16'(blend_diff);
  wire [5:0] blend_pos = s_ramp[5:0] - 6'd1;
  // The shared service forms |new-old| * blend_pos. Division by 64 is then a
  // wiring shift; applying the saved sign reproduces signed truncation toward
  // zero without a divider.
  wire [21:0] bl_res = m_res[21:0];

  // One physical request mux and one sequential write site make the effect
  // multiplier a PSG-wide service. A sample walk freezes the tick sequencer;
  // any product launched on the sample boundary finishes well before the
  // first sample request at PWORK+2/PWORK+4.
  logic        mul_start;
  logic [23:0] mul_start_a;
  logic [9:0]  mul_start_b;
  logic        mul_start_wide;
  always_comb begin
    mul_start      = 1'b0;
    mul_start_a    = 24'd0;
    mul_start_b    = 10'd0;
    mul_start_wide = 1'b0;
    if (prun && !m_busy) begin
      if (REALTIME_PREVIEW) begin
        if (pph == 7'(PWORK + 2)) begin
          mul_start   = 1'b1;
          mul_start_a = {15'b0, n_mag9};
          mul_start_b = s_eff_vol;
        end
      end else begin
        case (pph)
          7'(PWORK + 4): begin
            mul_start = 1'b1;
            if (s_snd_wt) begin
              mul_start_a = {15'b0,
                             wt_pd[8] ? 9'(-wt_pd) : 9'(wt_pd)};
              mul_start_b = wt_pf;
              mul_start_wide = 1'b1;
            end else begin
              mul_start_a = {15'b0, n_mag9};
              mul_start_b = {2'b0, s_eff_vol};
            end
          end
          7'(PWORK + 13): if (!s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = {15'b0,
                           old_smp[7]
                             ? ((old_smp == -8'sd128) ? 9'd127
                                                     : 9'(-old_smp))
                             : {1'b0, old_smp}};
            mul_start_b = s_old_vol;
          end
          7'(PWORK + 23): if (!s_snd_wt && s_ramp != 0) begin
            mul_start   = 1'b1;
            mul_start_a = {8'b0, blend_mag};
            mul_start_b = {2'b0, blend_pos};
          end
          7'(PWORK + 15): if (s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = {15'b0,
                           wt_qd[8] ? 9'(-wt_qd) : 9'(wt_qd)};
            mul_start_b = wt_qf;
            mul_start_wide = 1'b1;
          end
          7'(PWORK + 27): if (s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = {15'b0, n_mag9};
            mul_start_b = {2'b0, s_eff_vol};
          end
          default: ;
        endcase
      end
    end else if (!walk_frozen) begin
      case (sst)
        K_FX: if (!m_busy && xs != 4'd7
                  && !(xs == 4'd2 && e_fx == 3'd1)) begin
          mul_start   = 1'b1;
          mul_start_a = mul_a;
          mul_start_b = {2'b0, mul_b};
        end
        K_SLP2: if (!m_busy) begin
          mul_start   = 1'b1;
          mul_start_a = pinc_q - arp_r;
          mul_start_b = {2'b0, slp_frac};
        end
        K_SLPM: if (!m_busy) begin
          mul_start   = 1'b1;
          mul_start_a = 24'd1317;
          mul_start_b = {4'b0, vmul};
        end
        // The music pattern's tick length, launched fire-and-forget; the
        // ungated capture in the sequencer picks m_res up when it lands.
        // m cannot be busy here - the nearest preceding launch site is the
        // previous slot's xs 6 product, a full record store earlier - and
        // the simulation-only check below guards that schedule fact.
        T_NL: if (launched[c] && !tch_seen && !(acc[7:0] < seq_q)) begin
          mul_start   = 1'b1;
          mul_start_a = {16'b0, wrd[7:0]};       // speed, staged at T_LS
          mul_start_b = {4'b0, pat_rows};
        end
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (reset)
      m_cnt <= 0;
    else if (m_cnt != 0) begin
      m_p   <= m_wide ? {m_sum, m_p[9:1]}
                      : {2'b0, m_sum, m_p[7:1]};
      m_cnt <= m_cnt - 1;
    end else if (mul_start) begin
      m_a    <= mul_start_a;
      m_p    <= {25'b0, mul_start_b};
      m_wide <= mul_start_wide;
      m_cnt  <= mul_start_wide ? 4'd10 : 4'd8;
    end
  end

  wire signed [16:0] mix_prod =
      REALTIME_PREVIEW
        ? ((s_snd_wave == 3'd6) ? nm_noise_scaled : nm_signed)
        : mx_prod;
  wire signed [21:0] n_contrib = {{5{mix_prod[16]}}, mix_prod};
  // This slot's leaf in the reduction tree: its sample, or an explicit zero
  // when it is running but not audible.
  wire signed [21:0] mix_leaf = mx_aud ? n_contrib : 22'sd0;

  // ---- PICO-8's pairwise soft_add reduction --------------------------
  // The flat sum with a hard clamp at +-131068 is gone. PICO-8 reduces the
  // eight slots through a fixed binary tree, combining every pair with
  // `soft_add`, which compresses 5:1 above a threshold instead of clipping:
  //
  //   L1  (0+1) (2+3) (4+5) (6+7)      L2  (0+2) (4+6)      L3  (0+4)
  //
  // The order is part of the behaviour, because soft_add is not associative -
  // a flat sum is a different function, not an optimisation of this one. A
  // suppressed music slot is an explicit ZERO leaf rather than a removed one,
  // and soft_add(x, 0) != x above the threshold, so the zeros must be fed in.
  //
  // Scale: PICO-8's threshold is 24576 against a signed 16-bit sample. The
  // oscillator product peaks near 32512 internally, while PICO-8's exported
  // single full-volume triangle peaks near 16118, so the internal tree is at
  // twice output scale. The previous quarter-scale assumption made every
  // exported waveform almost exactly 6 dB too quiet. Keep the tree and
  // threshold at 2x, then shift once at the end.
  //
  // The tree used to be a parallel soft_add node - a 23-bit sum, two signed
  // compares, the excess mux and a four-stage shift-add network for the
  // binary's (excess * 52429) >> 18 division - plus l1[0:3]/l2a/l2b/sa_hold
  // holding registers. The register file was the expensive half: every one of
  // those flops was fed by shared logic, so nextpnr gave each its own logic
  // cell with a feed-through LUT - cost that mapped LUT4 counts never showed.
  //
  // It is now ONE serial fold engine on the shared phase ALU. The stack S0
  // carries the running left spine, S1/S2 the pending right subtrees, and the
  // (dest, src) schedule below reproduces PICO-8's exact pairing order:
  //
  //   slot 0  push S0        slot 1  S0 += leaf1            (L1 0+1)
  //   slot 2  push S1        slot 3  S1 += leaf3, S0 += S1  (L1 2+3, L2 0+2)
  //   slot 4  push S1        slot 5  S1 += leaf5            (L1 4+5)
  //   slot 6  push S2        slot 7  S2 += leaf7, S1 += S2, S0 += S1
  //
  // soft_add is not associative and the zero leaves are part of the function,
  // so the order above IS the old tree, fold for fold - bit-identical.
  //
  // The division by five: floor(x/5) via a truncating shift-add series with a
  // single bounded fixup,
  //
  //   q = (x>>1) + (x>>2);  q += q>>4;  q += q>>8;  q >>= 2;
  //   r = x - 5q;  q += (r >= 5);
  //
  // verified exhaustively equal to the binary's (x * 52429) >> 18 for every
  // x below 80k (the largest reachable excess is under 72k: a leaf is at most
  // 32512, level 1 receives at most 65024, and repeating the compressed bound
  // through levels 2 and 3 stays under 72k - 17 bits). Every step is one
  // A +/- (B >> k) pass through the 24-bit phase ALU, which is idle from
  // PWORK+10 to the end of the visit, so the network of 20/24/32/34-bit
  // adders is gone and no service got wider.
  //
  // Comparisons are done by subtracting on the ALU and testing bit 23, with
  // both operands sign-extended to 24 bits first - the old parallel node's
  // unsigned-concatenation trap does not exist here, but the sign extension
  // below is still load-bearing for exactly that reason.
  localparam signed [22:0] SA_TH = 23'sd49152;    // 24576 << 1
  logic signed [21:0] fstk[0:2];      // S0, S1, S2
  logic [2:0]  fsel;                  // active fold: see fda/fdb below
  logic [1:0]  fpend;                 // folds still queued in this chain
  logic        ffin;                  // this chain ends in dry16
  logic        f_over, f_under;
  logic [17:0] fx_r;                  // |excess|, then the partial remainder
  logic [17:0] ft2;                   // series accumulator (q << 2)
  logic [3:0]  fr_r;                  // final remainder, 0..9

  // Fold operand selection: 0/1/2 combine a stack entry with the slot leaf,
  // 3 folds S1 into S0, 4 folds S2 into S1. fda is always the destination.
  logic signed [21:0] fda, fdb;
  always_comb begin
    case (fsel)
      3'd0:    begin fda = fstk[0]; fdb = mix_leaf; end
      3'd1:    begin fda = fstk[1]; fdb = mix_leaf; end
      3'd2:    begin fda = fstk[2]; fdb = mix_leaf; end
      3'd4:    begin fda = fstk[1]; fdb = fstk[2];  end
      default: begin fda = fstk[0]; fdb = fstk[1];  end
    endcase
  end
  wire [1:0] fdsti = (fsel == 3'd2) ? 2'd2
                   : (fsel == 3'd1 || fsel == 3'd4) ? 2'd1 : 2'd0;

  // One ALU micro-op per fmc step. fmc 1 forms the plain sum, 2/3 the two
  // threshold compares (capturing the excess), 4-6 the divide series, 7/8
  // the remainder, 9 rebuilds TH + q (+1 rides the carry-in), 10 negates for
  // the underflow side. Steps 4-10 run regardless and commit nothing unless
  // a compare fired; the schedule is fixed so nothing downstream cares.
  always_comb begin
    fold_a = 24'd0; fold_b = 24'd0; fold_sub = 1'b0; fold_cin = 1'b0;
    case (fmc)
      4'd1:  begin fold_a = {{2{fda[21]}}, fda};
                   fold_b = {{2{fdb[21]}}, fdb}; end
      4'd2:  begin fold_a = {{2{fda[21]}}, fda};
                   fold_b = 24'(SA_TH); fold_sub = 1'b1; end
      4'd3:  begin fold_a = 24'(-SA_TH);
                   fold_b = {{2{fda[21]}}, fda}; fold_sub = 1'b1; end
      4'd4:  begin fold_a = {7'b0, fx_r[17:1]};
                   fold_b = {8'b0, fx_r[17:2]}; end
      4'd5:  begin fold_a = {6'b0, ft2};
                   fold_b = {10'b0, ft2[17:4]}; end
      4'd6:  begin fold_a = {6'b0, ft2};
                   fold_b = {14'b0, ft2[17:8]}; end
      4'd7:  begin fold_a = {6'b0, fx_r};
                   fold_b = {6'b0, ft2[17:2], 2'b00}; fold_sub = 1'b1; end
      4'd8:  begin fold_a = {6'b0, fx_r};
                   fold_b = {8'b0, ft2[17:2]}; fold_sub = 1'b1; end
      4'd9:  begin fold_a = 24'(SA_TH);
                   fold_b = {8'b0, ft2[17:2]};
                   fold_cin = (fr_r >= 4'd5); end
      4'd10: begin fold_a = 24'd0;
                   fold_b = {{2{fda[21]}}, fda}; fold_sub = 1'b1; end
      default: ;
    endcase
  end

  logic [1:0]  rev_max;
  // The echo has to outlive the note that asked for it, so the level any
  // playing channel requests is held for a full delay line after the last
  // request rather than dropping with the channel.
  logic [1:0]  rev_lvl;
  logic [9:0]  rev_ttl;
  logic signed [15:0] dry16;
  logic        dry_valid;

  // A sequencer tick and a sample boundary coincide every 183 samples. Under
  // the pre-run (task 3.0) the tick program evaluated during the PRECEDING
  // sample interval and the boundary edge flipped the staged bank, so the
  // boundary sample starts immediately like any other and reads the
  // just-flipped parameters. The old tick-first deferral (sample_pending /
  // tick_publish) is gone: the tick program no longer shares the boundary
  // sample's 1,275-clock budget with synthesis.


  always_ff @(posedge clk) begin
    if (reset) begin
      lfsr <= 15'h2A5F;
      prun <= 0;
      pc_ch <= 0;
      pph <= 0;
      clr_ack <= 0;
      fmc <= 0;
      fpend <= 0;
      ffin <= 0;
      rev_max <= 0;
      rev_lvl <= 0;
      rev_ttl <= 0;
      dry_valid <= 0;
      // Datapath and streamed voice fields deliberately have no reset mux.
      // state_m supplies every s_* field before PWORK; each product/blend
      // register is committed before its count or phase consumes it; and the
      // mix leaves are overwritten in voice order before the fold consumes
      // them. Only the
      // validity/count controls above require a defined reset value.
    end else begin
      dry_valid <= 0;

      // The serial soft_add fold: one phase-ALU micro-op per cycle. A chain
      // launched at an odd slot's PFOLD runs into the following visit's
      // record-load phases - the ALU is idle there - and the slot-7 chain
      // runs on past the walk, with walk_frozen holding the tick sequencer
      // until the final fold lands in dry16.
      if (fmc != 4'd0) begin
`ifndef SYNTHESIS
        if (prun && !REALTIME_PREVIEW
            && ((pph >= 7'(PWORK) && pph <= 7'(PWORK + 1))
                || (pph >= 7'(PWORK + 5) && pph <= 7'(PWORK + 9))))
          $error("fold engine and sample walk both claim the phase ALU");
`endif
        case (fmc)
          4'd1:  begin fstk[fdsti] <= phase_alu_y[21:0]; fmc <= 4'd2; end
          4'd2:  begin
            f_over <= ~phase_alu_y[23];
            if (!phase_alu_y[23]) fx_r <= phase_alu_y[17:0];
            fmc <= 4'd3;
          end
          4'd3:  begin
            f_under <= ~phase_alu_y[23];
            if (!phase_alu_y[23]) fx_r <= phase_alu_y[17:0];
            fmc <= 4'd4;
          end
          4'd4, 4'd5, 4'd6: begin ft2 <= phase_alu_y[17:0]; fmc <= fmc + 1; end
          4'd7:  begin fx_r <= phase_alu_y[17:0]; fmc <= 4'd8; end
          4'd8:  begin fr_r <= phase_alu_y[3:0]; fmc <= 4'd9; end
          4'd9:  begin
            if (f_over | f_under) fstk[fdsti] <= phase_alu_y[21:0];
            fmc <= f_under ? 4'd10 : 4'd11;
          end
          4'd10: begin fstk[fdsti] <= phase_alu_y[21:0]; fmc <= 4'd11; end
          default: begin                       // chain step complete
            if (fpend != 2'd0) begin
              fpend <= fpend - 1;
              fsel <= (fsel == 3'd2) ? 3'd4 : 3'd3;
              fmc <= 4'd1;
            end else begin
              fmc <= 4'd0;
              if (ffin) begin
                ffin <= 0;
                dry16 <= 16'($signed(fstk[0]) >>> 1);
                dry_valid <= 1;
                // hold the requested echo level for one delay line past the
                // last request, so a note that ends still gets its echo back
                if (rev_max != 2'd0) begin
                  rev_lvl <= rev_max;
                  rev_ttl <= 10'd732;
                end else if (rev_ttl != 0)
                  rev_ttl <= rev_ttl - 1;
                else
                  rev_lvl <= 0;
              end
            end
          end
        endcase
      end

      if (sample_en) begin
        prun <= 1;
        pc_ch <= 0;
        pph <= 0;
        rev_max <= 0;
      end else if (prun) begin
        // ---- record load: word pph-1 has landed ----------------------
        case (pph)
          7'd1: s_phase[15:0] <= state_q;
          7'd2: {s_nz_hold, s_phase[23:16]} <= state_q;
          7'd3: s_phase2[15:0] <= state_q;
          7'd4: {s_nz_ph, s_phase2[23:16]} <= state_q[11:0];
          7'd5: s_brown <= state_q[12:0];
          7'd6: s_lp <= state_q;
          7'd7: if (REALTIME_PREVIEW)
                   s_noise_lp <= state_q;
                else
                   s_old_phase[15:0] <= state_q;
          7'd8: if (!REALTIME_PREVIEW)
                   {s_ramp, s_old_phase[23:16]} <= {state_q[15:9],
                                                    state_q[7:0]};
          7'd9: if (!REALTIME_PREVIEW) s_old_inc[15:0] <= state_q;
          7'd10: if (!REALTIME_PREVIEW)
                    {s_old_vol, s_old_inc[23:16]} <= state_q;
          7'd11: if (!REALTIME_PREVIEW)
                    {s_last_pitch[4:0], s_last_wave,
                     s_last_inc[23:16]} <= state_q;
          7'd12: if (!REALTIME_PREVIEW) s_last_inc[15:0] <= state_q;
          7'd13: if (!REALTIME_PREVIEW) begin
                    s_last_slide <= state_q[14];
                    s_fx_phase_entry <= state_q[13];
                    s_last_trigger <= state_q[12];
                    {s_last_pitch[5], s_old_wave,
                     s_last_vol} <= state_q[11:0];
                  end
          7'd14: if (!REALTIME_PREVIEW) s_noise_lp <= state_q;
          default: ;
        endcase
        case (pph)
          7'(PLOSC + 1):
            s_eff_inc[15:0] <= state_q;
          7'(PLOSC + 2):
            {s_snd_id, s_snd_wt, s_snd_wave, s_eff_inc[23:16]}
              <= state_q[14:0];
          7'(PLOSC + 3):
            {s_ch_damp, s_ch_rev, s_ch_det, s_ch_buzz, s_ch_noiz,
             s_snd_pitch} <= state_q[13:0];
          7'(PLOSC + 4):
            {s_slide_effect, s_compound_direct, s_drop_effect,
             s_trigger_tag, s_pitch_direct, s_eff_vol} <= state_q[12:0];
          default: ;
        endcase

        if (pph == 7'(PLAST)) begin
          pph <= 0;
          // Slot 7's fold chain was launched at its PFOLD and finishes after
          // the walk; fold_busy keeps the tick sequencer off the ALU until
          // the final fold has landed in dry16.
          if (pc_ch == VW'(NV-1))
            prun <= 0;
          pc_ch <= pc_ch + 1;
        end else
          pph <= pph + 1;

        if (REALTIME_PREVIEW) begin
          case (pph)
            7'(PWORK): begin
              lfsr <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};
              if (playing[pc_ch] && s_eff_vol != 0) begin
                s_phase <= s_phase + einc;
                if (s_ch_noiz || s_phase[23:20] != s_nz_ph) begin
                  s_nz_ph <= s_phase[23:20];
                  s_nz_hold <= $signed(lfsr[7:0]);
                end
                s_brown <= s_brown
                              - {{5{s_brown[12]}}, s_brown[12:5]}
                              + $signed({{5{lfsr[7]}}, lfsr[7:0]});
                if (s_snd_wave == 3'd6)
                  s_noise_lp <= noise_next;
              end else if (playing[pc_ch]) begin
                s_phase <= 0;
                s_phase2 <= 0;
              end
              if (clr_tog[pc_ch] != clr_ack[pc_ch]) begin
                clr_ack[pc_ch] <= clr_tog[pc_ch];
                s_lp <= 0;
                s_brown <= 0;
                s_noise_lp <= 0;
              end
            end
            7'(PWORK + 1): begin
              // The secondary synchronous read observes q during this cycle.
              // Advance it at the edge only after that address has captured
              // the same pre-advance sample state as p captured at PWORK.
              if (playing[pc_ch] && s_eff_vol != 0 && v2_on)
                s_phase2 <= s_phase2 + preview_v2inc;
              smp_a <= s_snd_wt ? $signed(seq_q) : wq;
            end
            7'(PWORK + 2): begin
              smp_b <= s_snd_wt ? $signed(seq_q) : wq;
              mx_neg  <= s_snd_wt ? wt_mix[8] : samp_d[7];
              mx_play <= playing[pc_ch];
              mx_aud  <= playing[pc_ch]
                         & ~(is_mus(pc_ch)
                             & playing[{1'b0, pc_ch[1:0]}]);
              mx_lp   <= lp_next;
              mx_rev  <= s_ch_rev;
              mx_damp <= s_ch_damp;
            end
            7'(PFOLD): begin
              if (pc_ch[0] == 1'b0)
                fstk[(pc_ch == 3'd0) ? 2'd0
                   : (pc_ch == 3'd6) ? 2'd2 : 2'd1] <= mix_leaf;
              else begin
                fsel  <= (pc_ch == 3'd1) ? 3'd0
                       : (pc_ch == 3'd7) ? 3'd2 : 3'd1;
                fpend <= (pc_ch == 3'd3) ? 2'd1
                       : (pc_ch == 3'd7) ? 2'd2 : 2'd0;
                ffin  <= (pc_ch == 3'd7);
                fmc   <= 4'd1;
              end
              if (mx_aud && mx_rev > rev_max) rev_max <= mx_rev;
              if (mx_play && mx_damp != 0) s_lp <= mx_lp;
            end
            default: ;
          endcase
        end else begin
        case (pph)
          7'(PWORK): begin               // advance phase(s), issue main read
            // One step per voice per sample. This used to free-run on the
            // system clock, which tied the noise sequence to how many clocks
            // the per-voice pipeline happened to take - so shortening the
            // sample x volume multiply, or changing the number of voices,
            // silently changed what the noise sounded like. Stepping it here
            // gives every voice a fresh value every sample and makes the
            // noise independent of the pipeline's timing.
            lfsr <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};
            // `_mix_osc_tick_new` returns before touching oscillator state
            // when its amplitude is zero.  This is observable with repeated
            // fade-in rows: their silent first ticks freeze phase rather than
            // free-running it.
            if (playing[pc_ch] && s_eff_vol != 0) begin
              if (!s_snd_wt) begin
                if (phase_op != PH_HOLD)
                  s_phase <= phase_alu_y;
              end else begin
                wt_pf <= s_phase[17:8];
                wt_qf <= s_phase2[17:8];
              end
              // noise: white every sample when NOIZ, else pitched S&H
              if (s_ch_noiz || s_phase[23:20] != s_nz_ph) begin
                s_nz_ph <= s_phase[23:20];
                s_nz_hold <= $signed(lfsr[7:0]);
              end
              // brown integrator (leaky low-pass of white) for BUZZ noise
              s_brown <= s_brown
                            - {{5{s_brown[12]}}, s_brown[12:5]}
                            + $signed({{5{lfsr[7]}}, lfsr[7:0]});
              if (s_snd_wave == 3'd6)
                s_noise_lp <= noise_next;
            end
            // Parameter publication happens atomically once per tick. On the
            // first sample that observes a new built-in oscillator state,
            // preserve the preceding state and start PICO-8's 64-sample
            // old-to-new render. The previous phase begins exactly where the
            // new phase did before either continuation advances.
            if (transition_change) begin
              // A trigger generation is published atomically with the new
              // parameters and retained in the oscillator record. This makes
              // a retrigger a transition even when its sounding parameters
              // happen to match the preceding state.
              s_old_phase <= s_phase;
              s_old_inc <= s_last_inc;
              s_old_vol <= s_last_vol;
              s_old_wave <= s_last_wave;
              s_ramp <= 7'd1;
              // A zero-amplitude state is not merely an inaudible running
              // oscillator in PICO-8: the next nonzero state starts from the
              // canonical phase again.  Repeated speed-2 fade-in rows export
              // byte-identical audible ticks, which exposes this reset.
              if (s_eff_vol == 0) begin
                s_phase <= 0;
                s_phase2 <= 0;
              end
            end
            // a trigger asked for this channel's filter state to be reset
            if (clr_tog[pc_ch] != clr_ack[pc_ch]) begin
              clr_ack[pc_ch] <= clr_tog[pc_ch];
              s_lp <= 0;
              s_brown <= 0;
              s_noise_lp <= 0;
            end
          end
          7'(PWORK + 1): begin           // main-voice sample
            // Keep q's synchronous ROM address on the pre-advance phase,
            // matching PICO-8's render-then-advance oscillator ordering.
            if (playing[pc_ch] && s_eff_vol != 0 && s_snd_wt)
              s_phase <= phase_alu_y;
            else if (playing[pc_ch] && s_eff_vol != 0
                     && (phase_op == PH_OLD_SUB || phase_op == PH_OLD_ADD))
              s_phase <= phase_alu_y;
            smp_a <= s_snd_wt ? $signed(seq_q) : wq;
          end
          7'(PWORK + 2): begin           // second voice
            if (s_snd_wt)
              wt_p1 <= $signed(seq_q);
            else
              smp_b <= wq;
            s_last_inc <= s_eff_inc;
            // A pattern handoff publishes zero volume while music itself is
            // still active. Preserve only that last audible field across the
            // gap; increment, waveform and pitch never change there and do not
            // need wide preservation muxes.
            if (playing[pc_ch] || !(is_mus(pc_ch) && mus_playing))
              s_last_vol <= s_eff_vol;
            s_last_wave <= s_snd_wave;
            s_last_pitch <= s_snd_pitch;
            s_last_trigger <= s_trigger_tag;
            s_last_slide <= s_slide_effect;
            if (transition_change && s_drop_effect
                && s_eff_inc != s_last_inc && s_last_vol != 0
                && s_snd_wave == s_last_wave && !trigger_transition)
              s_fx_phase_entry <= 1;
            if (trigger_transition || s_pitch_direct)
              s_fx_phase_entry <= 0;
          end
          7'(PWORK + 3): begin           // preceding-state waveform sample
            if (s_snd_wt) begin
              smp_b <= $signed(seq_q);
            end else
              old_smp <= wq;
          end
          7'(PWORK + 4): begin
            if (s_snd_wt) begin
              // PICO-8 interpolates its 64 signed wavetable samples with ten
              // fractional phase bits. The PSG-wide product service evaluates
              // p and then q; wi_neg reapplies arithmetic-shift rounding.
              wt_q1 <= $signed(seq_q);
              wi_neg <= wt_pd[8];
            end else begin
              // First serialized product: new oscillator sample × new volume.
              mx_neg  <= samp_d[7];
              mx_play <= playing[pc_ch];
              // Audible unless this music slot has a foreground effect.
              mx_aud  <= playing[pc_ch]
                         & ~(is_mus(pc_ch) & playing[{1'b0, pc_ch[1:0]}]);
              mx_lp   <= lp_next;
              mx_rev  <= s_ch_rev;
              mx_damp <= s_ch_damp;
            end
          end
          7'(PWORK + 15): begin
            if (s_snd_wt) begin
              smp_a <= 8'($signed({smp_a[7], smp_a}) + wi_delta);
              wi_neg <= wt_qd[8];
            end
          end
          7'(PWORK + 5): begin
            // The old waveform read has captured the pre-advance phase.
            if (!s_snd_wt && s_ramp != 0 && s_old_vol != 0)
              s_old_phase <= phase_alu_y;
            // Commit the built-in path's one-pole state before oscillator
            // word 5 is written back. Waiting until PFOLD stored the preceding
            // value four clocks earlier, so DAMPEN restarted at its first
            // half-step on every sample.
            if (!s_snd_wt && mx_play && mx_damp != 0)
              s_lp <= mx_lp;
          end
          7'(PWORK + 6): begin
            // All secondary waveform reads have captured the pre-advance
            // phase. Wavetable and DETUNE-2 finish here; DETUNE-1 and phaser
            // continue through the same ALU below.
            if (playing[pc_ch] && s_eff_vol != 0 && v2_on)
              s_phase2 <= phase_alu_y;
          end
          7'(PWORK + 7): begin
            if (playing[pc_ch] && s_eff_vol != 0
                && (s_snd_wave == 3'd7
                    || (!s_snd_wt && s_ch_det == 2'd1)))
              s_phase2 <= phase_alu_y;
          end
          7'(PWORK + 8), 7'(PWORK + 9): begin
            // Phaser's 109/110 approximation is
            // x - (x>>7) - (x>>10) - (x>>12), accumulated serially.
            if (playing[pc_ch] && s_eff_vol != 0
                && !s_snd_wt && s_snd_wave == 3'd7)
              s_phase2 <= phase_alu_y;
          end
          7'(PWORK + 13): begin
            if (!s_snd_wt) begin
              mx_new <= (s_snd_wave == 3'd6) ? nm_noise_scaled : nm_signed;
              // Second serialized product: old continuation × old volume.
              mx_neg <= old_smp[7];
            end
          end
          7'(PWORK + 26): begin
            if (s_snd_wt)
              smp_b <= 8'($signed({smp_b[7], smp_b}) + wi_delta);
          end
          7'(PWORK + 27): begin
            if (s_snd_wt) begin
              mx_neg  <= wt_mix[8];
              mx_play <= playing[pc_ch];
              mx_aud  <= playing[pc_ch]
                         & ~(is_mus(pc_ch) & playing[{1'b0, pc_ch[1:0]}]);
              mx_lp   <= lp_next;
              mx_rev  <= s_ch_rev;
              mx_damp <= s_ch_damp;
            end
          end
          7'(PWORK + 28): begin
            if (s_snd_wt && mx_play && mx_damp != 0)
              s_lp <= mx_lp;
          end
          7'(PWORK + 22): begin
            if (!s_snd_wt)
              mx_old <= nm_signed;
          end
          7'(PWORK + 23): begin
            // A zero ramp bypasses the blend entirely. Otherwise start the
            // 16×6 difference product on the same serialized principle.
            if (!s_snd_wt && s_ramp == 0) begin
              mx_prod <= mx_new;
            end
          end
          7'(PWORK + 36): begin
            if (s_snd_wt) begin
              mx_new <= nm_signed;
              mx_prod <= nm_signed;
            end
          end
          7'(PWORK + 32): begin
            if (!s_snd_wt && s_ramp != 0) begin
              mx_prod <= blend_diff[16]
                           ? (mx_old - $signed({1'b0, bl_res[21:6]}))
                           : (mx_old + $signed({1'b0, bl_res[21:6]}));
              s_ramp <= (s_ramp == 7'd64) ? 7'd0 : s_ramp + 7'd1;
            end
          end
          7'(PFOLD): begin               // fold into the tree
            // An even slot's leaf waits on the stack; an odd slot's launches
            // the fold chain (one fold, or the queued multi-fold steps after
            // slots 3 and 7). mix_leaf is zero for a slot that is running but
            // suppressed, which is deliberate - the tree's zero leaves are
            // part of the function.
            if (pc_ch[0] == 1'b0)
              fstk[(pc_ch == 3'd0) ? 2'd0
                 : (pc_ch == 3'd6) ? 2'd2 : 2'd1] <= mix_leaf;
            else begin
              fsel  <= (pc_ch == 3'd1) ? 3'd0
                     : (pc_ch == 3'd7) ? 3'd2 : 3'd1;
              fpend <= (pc_ch == 3'd3) ? 2'd1
                     : (pc_ch == 3'd7) ? 2'd2 : 2'd0;
              ffin  <= (pc_ch == 3'd7);
              fmc   <= 4'd1;
            end
            if (mx_aud && mx_rev > rev_max) rev_max <= mx_rev;
          end
          default: ;
        endcase
        end
      end
    end
  end

  // Output stage: direct, or a shared feed-forward reverb echo (2/4-tick
  // delay at the strongest level any active channel requested)
  generate
  if (REVERB) begin : g_reverb
    // Ten signed bits in units of 64 PCM counts preserve the exported tail
    // down to its last ~62-count repeat while keeping 732 samples in two EBRs.
    logic signed [9:0] revbuf[0:731];
    logic [9:0] widx, ridx;
    logic signed [9:0] rev_q, dry_l;
    logic [1:0] rst, rlvl_l;
    logic signed [10:0] rev_fbv;
    logic signed [9:0] rev_fb;
    logic signed [15:0] rev_echo;
    wire [9:0] dlen = (rev_lvl == 2'd1) ? 10'd366 :
                      (rev_lvl == 2'd2) ? 10'd732 : 10'd0;
    always_comb begin
      rev_fbv = $signed({dry_l[9], dry_l})
                + ((rlvl_l == 2'd0)
                     ? 11'sd0 : $signed({rev_q[9], rev_q}) >>> 1);
      rev_fb = rev_fbv > 11'sd511 ? 10'sd511
             : rev_fbv < -11'sd512 ? -10'sd512 : rev_fbv[9:0];
      rev_echo = (rlvl_l == 2'd0)
                   ? 16'sd0 : $signed({rev_q[9], rev_q, 5'b0});
    end
    always_ff @(posedge clk)
      rev_q <= revbuf[ridx];
    always_ff @(posedge clk) begin
      if (reset) begin
        widx <= 0; ridx <= 0; rst <= 0; pcm <= 16'sd0;
        dry_l <= 0; rlvl_l <= 0;
      end else begin
        case (rst)
          2'd0: if (dry_valid) begin
            dry_l <= 10'(dry16 >>> 6);
            rlvl_l <= rev_lvl;
            ridx <= (dlen == 0) ? widx :
                    (widx >= dlen) ? widx - dlen : widx + 10'd732 - dlen;
            rst <= 2'd1;
          end
          2'd1: rst <= 2'd2;                     // revbuf read settles
          2'd2: begin
            pcm <= 16'(dry16 + rev_echo);
            // PICO-8's reverb is a feedback comb: the delayed half-level
            // repeat is written back with the dry signal, producing the
            // measured 1/2, 1/4, 1/8... impulse train every delay period.
            revbuf[widx] <= rev_fb;
            widx <= (widx == 10'd731) ? 10'd0 : widx + 1;
            rst <= 2'd0;
          end
          default: rst <= 2'd0;
        endcase
      end
    end
  end else begin : g_direct
    always_ff @(posedge clk) begin
      if (reset) pcm <= 16'sd0;
      else if (dry_valid) pcm <= dry16;
    end
  end
  endgenerate

  // ------------------------------------------------------------------
  // CPU interface: upload port, music mask, status reads
  // ------------------------------------------------------------------
  wire [15:0] up_idx = wraddr - 16'h3100;

  always_ff @(posedge clk) begin
    if (reset) begin
      wraddr <= 16'h3100;
      mus_mask <= 4'h0;
      dout <= 0;
    end else if (cs && rw) begin
      case (addr)
        8'h00: wraddr[7:0] <= di;
        8'h01: wraddr[15:8] <= di;
        8'h02: begin
          if (up_idx < 16'd4608)
            aram[up_idx[12:0]] <= di;
          wraddr <= wraddr + 1;
        end
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
                        playing[3] | trig_req[3], playing[2] | trig_req[2],
                        playing[1] | trig_req[1], playing[0] | trig_req[0]};
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
                      ? {playing[aud_sl(addr[1:0])], 1'b0,
                         sfx_id[aud_sl(addr[1:0])]}
                      : {playing[aud_sl(addr[1:0])], 2'b0,
                         row[aud_sl(addr[1:0])]};
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
  always_comb begin
    dbg = 64'b0;
    dbg[7:0]   = {mus_playing, 1'b0, mus_pat};
    dbg[11:8]  = {playing[3], playing[2], playing[1], playing[0]};
    dbg[15:12] = {playing[7], playing[6], playing[5], playing[4]};
    dbg[21:16] = sfx_id[aud_sl(2'd0)];
    dbg[27:22] = sfx_id[aud_sl(2'd1)];
    dbg[33:28] = sfx_id[aud_sl(2'd2)];
    dbg[39:34] = sfx_id[aud_sl(2'd3)];
    dbg[45:40] = {1'b0, row[aud_sl(2'd0)]};
    dbg[51:46] = {1'b0, row[aud_sl(2'd1)]};
    dbg[57:52] = {1'b0, row[aud_sl(2'd2)]};
    dbg[63:58] = {1'b0, row[aud_sl(2'd3)]};
  end

endmodule
