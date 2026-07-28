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

  // Audio RAM: PICO-8 $3100-$42FF (music 0..255, SFX records 256..4607)
  logic [7:0] aram[0:4607];
  logic [15:0] wraddr;

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
  logic        tick_en, tick_en_d;
  logic [1:0]  tick_hold;
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
      tick_en_d <= 0;
      tick_hold <= 2'd0;
      pre_tick <= 0;
    end else begin
      tick_en <= 0;
      tick_en_d <= 0;
      pre_tick <= 0;
      if (!divd[27]) begin             // divacc >= CLK_HZ - 22050
        divd <= divd - $signed({1'b0, DIV_DOWN});
        sample_en <= 1;
        // The grid effects (bank flip, deferred stops) land two SAMPLES
        // after tick_en, which is where the capture pipeline puts stream
        // tick boundaries (adjudicated by the transition cases).
        tick_en_d <= (tick_hold == 2'd1);
        if (tick_hold != 2'd0)
          tick_hold <= tick_hold - 2'd1;
        if (scnt == 8'd182) begin
          scnt <= 0;
          tick_en <= 1;
          tick_hold <= 2'd2;
        end else begin
          scnt <= scnt + 1;
          // Six intervals of pre-run window. The engine's advance and
          // staging sequences grew the tick program past one interval's
          // slack, and section 3's exact divides (two for a slide, one
          // for the volume, one for an instrument's seventh) grew it
          // past four: psg_tb's all-eight-slots case measures 5,044
          // clocks, which four intervals clear by only 56. The pre_tick
          // constant is exactly the knob the 3.0 handshake left for that
          // (design 3, staging constraints). The cost is that a CPU
          // write landing inside the window is observed one tick
          // evaluation later, over a wider window than before.
          if (scnt == 8'd176)
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
  logic [4:0]  w_row;        // this visit's note position
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
  // The audible-slot report behind $10-$17 and the trace port. PICO-8
  // specifies stat(46..53) as "a history of mixer state at each tick to
  // give a higher resolution estimate of the currently audible state" -
  // a sampled view, not a live probe - so refreshing it as each slot's
  // visit ends is faithful, and it is what lets row leave the flops.
  logic [4:0]  aud_row[0:NCH-1];
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
  // 64 words per slot, not 32: the tick/oscillator/parameter families
  // filled the first 32 exactly, and the per-slot arrays below need a
  // home. REVERB=0 leaves the blocks for it - this costs one.
  localparam int VSTR = 64;                    // all records for one slot
  localparam int VADR = VW + 6;
  localparam logic [5:0] V_TICK = 6'd0;
  localparam logic [5:0] V_OSC  = 6'd10;
  localparam logic [5:0] V_PAR0 = 6'd24;
  localparam logic [5:0] V_PAR1 = 6'd28;
  // The sequencer's per-slot note position. An array of these is eight
  // flops sharing one D behind per-slot enables, so every one of them
  // is unpackable AND the decode rides along; as a record word it is a
  // working register loaded at V_LD and stored at V_ST, like every
  // other family section 3 moved.
  localparam logic [5:0] V_SEQ  = 6'd32;
  localparam int PLOSC = REALTIME_PREVIEW ? 7  : SOSC;
  localparam int PWORK = REALTIME_PREVIEW ? 12 : 19;
  localparam int PFOLD = REALTIME_PREVIEW ? 23 : 108;
  localparam int PSTOR = REALTIME_PREVIEW ? 16 : 52;
  localparam int PLAST = REALTIME_PREVIEW ? 23 : 108;

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
  // this trigger pass writes the bank a tick pass already staged
  logic        join_stage;
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
      4'd4: vwdata = {11'b0, w_row};
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
  logic        s_ch_noiz, s_ch_buzz;
  logic [1:0]  s_ch_det, s_ch_rev, s_ch_damp;
  logic [11:0] s_eff_a;
  logic [23:0] s_phase, s_phase2;
  logic signed [7:0] s_nz_hold;
  logic [3:0]  s_nz_ph;
  logic signed [12:0] s_brown;
  logic signed [16:0] s_lp;
  logic signed [15:0] s_noise_lp;
  // PICO-8 keeps a copy of the preceding oscillator state at every synthesis
  // tick and blends its continuation into the first 64 new samples. These
  // fields live in the oscillator portion of state_m.
  logic [23:0] s_old_phase, s_old_inc, s_last_inc;
  logic [12:0] s_old_G, s_last_G;
  logic [2:0]  s_old_wave, s_last_wave;
  // The old state's own 17-bit secondary and the detune modes each side
  // of the tick boundary: the old continuation renders with the dq its
  // parameters had, not the new bank's.
  logic [16:0] old_q0;
  logic [1:0]  old_mode_r, last_mode_r;
  logic        old_alt_r, last_alt_r;
  // The reverb digit is oscillator state too (`hmode = state[0x5c]`), so
  // the copied old continuation combs at the level the PREVIOUS tick
  // asked for while the new block combs at the current one.
  logic [1:0]  old_rev_r, last_rev_r;
  logic [6:0]  bl_cnt;               // samples since this voice's copy
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

  logic [VW-1:0] c;                  // voice being processed

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
  // Exactly the oscillator record: PLAST may extend past the last store
  // (the product chain's tail phases), so the window is bounded by SOSC,
  // not by the visit's end.
  // The dampen state is produced at +86, far past its word's store
  // slot, so it writes back through two dedicated late cycles.
  wire         state_lp_we = prun && !REALTIME_PREVIEW
                               && (pph == 7'(PWORK + 87)
                                   || pph == 7'(PWORK + 88));
  wire         state_sample_we = (prun
                               && pph >= 7'(PSTOR)
                               && pph < 7'(PSTOR + PLOSC))
                               || state_lp_we;
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
  logic [23:0] arp_r;
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
      K_SL2:   pinc_addr = 8'd64 + {sl_chr[3:0], 2'd0};
      K_SL3:   pinc_addr = 8'd64 + {sl_chr[3:0], 2'd1};
      K_SL4:   pinc_addr = 8'd64 + {sl_chr[3:0], 2'd2};
      K_SL5,
      K_SL6:   pinc_addr = 8'd64 + {sl_chr[3:0], 2'd3};
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
  wire [23:0] base_inc = pinc_q;
  // The binary's amplitude is vol<<8 exactly (a0 in _calculate_osc_state).
  wire [11:0] vol_direct  = w_ins_done ? 12'd0 : {1'b0, w_cur_vol, 8'b0};
  wire [11:0] pvol_direct = {1'b0, w_prev_vol, 8'b0};

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
  logic [36:0] m_p;                  // accumulator plus 8/10/12-bit multiplier
  logic [3:0]  m_cnt;
  logic [1:0]  m_mode;               // 0: 8-bit B, 1: 10-bit, 2: 12-bit
  // Reset contract: m_cnt and the micro-PC are validity/control state and
  // reset to idle.  m_a/m_p and the working results below are datapath:
  // every one is overwritten by the six-op program before it is observed.
  wire  [24:0] m_acc = (m_mode == 2'd2) ? m_p[36:12]
                     : (m_mode == 2'd1) ? m_p[34:10] : m_p[32:8];
  wire  [25:0] m_sum = {1'b0, m_acc} + (m_p[0] ? {2'b0, m_a} : 26'd0);
  wire  [31:0] m_res = m_p[31:0];
  wire  [33:0] m_res_wide = m_p[33:0];
  wire  [27:0] m_res12 = m_p[27:0];
  wire         m_busy = (m_cnt != 0);

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

  wire         div_start;
  // ------------------------------------------------------------------
  // Exact truncated division (3.2a). The effect recurrences divide by
  // the SFX speed, and recip[s] = round(65536/s) is not exact truncated
  // division. One restoring divider serves them: a 24-bit dividend
  // field over an 8-bit divisor, 24 shift-subtract steps, the partial
  // remainder held in the top byte. It is its own unit rather than a
  // mode on the multiply service so a divide can overlap the next
  // product - the 9-bit compare-subtract is cheaper than muxing the
  // 26-bit accumulator's shift direction either way.
  // ------------------------------------------------------------------
  logic [31:0] d_p;                  // {remainder[7:0], dividend/quotient}
  logic [7:0]  d_d;
  logic [4:0]  d_cnt;
  // rem < d holds from rem = 0, so the shifted partial is 9 bits and the
  // restored remainder is always back under a byte.
  wire  [8:0]  d_rsh = {d_p[31:24], d_p[23]};
  wire  [9:0]  d_sub = {1'b0, d_rsh} - {2'b0, d_d};
  wire         d_fit = !d_sub[9];
  wire  [23:0] d_res = d_p[23:0];
  wire  [7:0]  d_rem = d_p[31:24];
  wire         d_busy = (d_cnt != 0);
  logic [23:0] div_n;
  logic [7:0]  div_d;

  always_ff @(posedge clk) begin
    if (reset)
      d_cnt <= 0;
    else if (d_cnt != 0) begin
      d_p   <= {(d_fit ? d_sub[7:0] : d_rsh[7:0]), d_p[22:0], d_fit};
      d_cnt <= d_cnt - 5'd1;
    end else if (div_start) begin
      d_p   <= {8'b0, div_n};
      d_d   <= div_d;
      d_cnt <= 5'd24;
    end
  end

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
  wire  [12:0] sl_dp_pre = crom_q[12:0] + {5'b0, sl_w[25:17]};
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
  wire [23:0] fxp_op  = m_res[30:7];
  wire [23:0] fxp_res = base_inc + (lfo_neg ? ~fxp_op : fxp_op)
                      + {23'b0, (lfo_neg & ~vib_cb)};
  logic [23:0] fxi_next;
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
              3'd2: begin mul_a = {1'b0, base_inc}; mul_b = {10'b0, lfo_mag};
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
      3'd2: fxi_next = {fxp_res[23:8], 8'b0};
      3'd3: fxi_next = {3'b0, d_res[12:0], 8'b0};
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
  wire [23:0] pub_inc = (w_ins_on && w_ins_wt && w_ins_bass)
                          ? {1'b0, arp_r[23:1]} : arp_r;
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
                         pub_inc[23:16]};
      P_W2:    pub_wd = {1'b0,
                         (w_cur_fx == 3'd1
                          || (w_ins_on && !w_ins_wt
                              && (w_cur_fx == 3'd0
                                  || w_cur_fx == 3'd3)
                              && w_ins_fx == 3'd1)),
                         w_ch_damp, w_ch_rev, w_ch_det, w_ch_buzz,
                         w_ch_noiz, e_pitch};
      default: pub_wd = {(w_ins_on && !w_ins_wt
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
                         a_pub};
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
        for (int i = 0; i < NV; i++)
          if (pend_stop[i]) playing[i] <= 0;
        pend_stop <= 0;
      end
      // Class-2 deferred stops (music flow) become audible one sample
      // later, where the frozen walk used to land them.
      if (sample_en && scnt == 8'd3) begin
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
          if (vcnt == 4'd4 && aud_sl(c[1:0]) == c)
            aud_row[c[1:0]] <= w_row;
          if (vcnt == 4'd4) begin
            vcnt <= 0;
            if (c == VW'(NV-1)) begin
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
        K_FX: if (!m_busy && !((xs == 4'd7 || xs == 4'd10) && d_busy)) begin
          if (xs == 0) arp_r <= pinc_q;
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
          arp_r <= {3'b0, sl_dp, 8'b0};
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
  // smp_a/smp_b/old_smp carry composed 16-bit z components (18-bit signed
  // working width); in the wavetable path smp_a/smp_b hold the raw signed
  // table bytes until the lerp lands the 16-bit z over them.
  logic signed [17:0] smp_a, smp_b, old_smp, old_smpb;
  logic signed [7:0] wt_p1, wt_q1;
  logic [9:0] wt_pf, wt_qf;
  logic wi_neg;
  logic [2:0] wsel, wsel_r;
  logic [15:0] wx, wx_r;
  logic        wsec, wsec_r, walt_r;
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
        4'd0:    sosc_wd = s_phase[23:8];
        4'd1:    sosc_wd = {s_nz_hold, old_q0[7:0]};
        4'd2:    sosc_wd = s_phase2[15:0];
        // The binary's secondary phase is a true 17-bit q0; its bit 16
        // shares this word with the noise phase and the old/last G high
        // slices (the low bytes ride words 9 and 12).
        4'd3:    sosc_wd = {1'b0, s_old_G[12:8], s_last_G[12:8],
                            s_nz_ph, s_phase2[16]};
        4'd4:    sosc_wd = {s_lp[16], old_mode_r, s_brown};
        4'd5:    sosc_wd = s_lp[15:0];
        4'd6:    sosc_wd = s_old_phase[23:8];
        4'd7:    sosc_wd = {bl_cnt, old_q0[16:8]};
        4'd8:    sosc_wd = s_old_inc[15:0];
        4'd9:    sosc_wd = {s_old_G[7:0], s_old_inc[23:16]};
        4'd10:   sosc_wd = {1'b0, old_rev_r, last_rev_r,
                            s_last_wave, s_last_inc[23:16]};
        4'd11:   sosc_wd = s_last_inc[15:0];
        4'd12:   sosc_wd = {1'b0, old_alt_r, last_alt_r,
                            last_mode_r, s_old_wave, s_last_G[7:0]};
        default: sosc_wd = s_noise_lp;
      endcase
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
      4'd0: tick_load_word = 5'd3;
      4'd1: tick_load_word = 5'd4;
      4'd2: tick_load_word = 5'd5;
      4'd3: tick_load_word = 6'd8;         // ins_pitch read-copy refresh
      4'd4: tick_load_word = 6'd9;
      4'd6: tick_load_word = V_SEQ;        // the note position
      // Active filter word for the carried w_ch_* refresh.
      default: tick_load_word = (bank ? V_PAR1 : V_PAR0) + 6'd2;
    endcase
  endfunction
  function automatic logic [5:0] tick_store_word(
      input logic [3:0] n, input logic bank);
    case (n)
      4'd0: tick_store_word = 5'd3;
      4'd1: tick_store_word = 5'd4;
      4'd2: tick_store_word = 6'd5;
      4'd4: tick_store_word = V_SEQ;
      default: tick_store_word = 6'd9;
    endcase
  endfunction

  // Engine read requests: addresses are pure functions of the held state,
  // so a read displaced by a sample walk re-issues itself, and a consume
  // state re-issues the displaced word during the replay cycle (the V_LD
  // pattern, generalized).
  wire [5:0] par_act = spar_bank ? V_PAR1 : V_PAR0;   // active bank base
  wire [5:0] par_ina = spar_bank ? V_PAR0 : V_PAR1;   // inactive (publish)
  // A skipped slot re-publishes its ACTIVE words - except in a joined
  // trigger pass, where the staged (inactive) bank already holds the tick
  // results for that slot and copying the active bank would revert them.
  wire [5:0] par_cpy = join_stage ? par_ina : par_act;
  logic       eng_rd;
  logic [5:0] eng_word;
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
      // The skipped-slot copy reads the ACTIVE sounding words (the
      // STAGED ones in a joined trigger pass - see par_cpy).
      K_ROT: eng_word = par_cpy;
      PC0:   eng_word = state_replay ? par_cpy : par_cpy + 5'd1;
      PC1:   eng_word = state_replay ? par_cpy + 5'd1 : par_cpy + 5'd2;
      PC2:   eng_word = state_replay ? par_cpy + 5'd2 : par_cpy + 5'd3;
      PC3:   begin
               eng_word = par_cpy + 5'd3;
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
                        && !(wrd[13:8] == 6'd1 || w_row == 5'd31);
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
    if (state_lp_we) begin
      state_wa = {pc_ch, (pph == 7'(PWORK + 87)) ? V_OSC + 5'd5
                                                 : V_OSC + 5'd4};
      state_wd = (pph == 7'(PWORK + 87))
                   ? s_lp[15:0]
                   : {s_lp[16], old_mode_r, s_brown};
    end else if (state_sample_we) begin
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

  // ---- the sample walk's control store -------------------------------
  // The hardware schedule is a pure function of pph, so its step decode
  // is a ROM, not an equality fabric: 128 x 32 one-hot control words
  // (two spare EBRs), read at pph+1 so ctrl_q is registered exactly
  // when its step executes. tools/gen_psg_ctrl.py writes the image and
  // documents the bit layout; the CTRL_* names here must match it.
  // At most one capture bit and one MUL_SEL value are set per word -
  // the generator asserts it - which is what lets the former case tree
  // run as parallel ifs. The preview flavour keeps its own case tree
  // and comparisons untouched; ctrl_q reads as zero there.
  localparam int CTRL_W0 = 0,  CTRL_W1 = 1,  CTRL_W2 = 2,  CTRL_W3 = 3;
  localparam int CTRL_W4 = 4,  CTRL_W5 = 5,  CTRL_W6 = 6,  CTRL_W15 = 7;
  localparam int CTRL_W17 = 8, CTRL_W26 = 9, CTRL_W27 = 10, CTRL_W28 = 11;
  localparam int CTRL_W39 = 12, CTRL_W40 = 13, CTRL_W51 = 14;
  localparam int CTRL_W52 = 15, CTRL_W62 = 16, CTRL_W63 = 17;
  localparam int CTRL_W74 = 18, CTRL_W84 = 19, CTRL_W86 = 20;
  localparam int CTRL_FOLD = 21, CTRL_ISEC = 22, CTRL_IOM = 23;
  localparam int CTRL_IOS = 24, CTRL_DQO = 25;
  localparam int CTRL_SYNA = 30, CTRL_SYNB = 31;
  logic [31:0] ctrl_q;
  generate
  if (!REALTIME_PREVIEW) begin : g_ctrl
    (* ram_style = "block" *) logic [31:0] ctrl_rom[0:127];
    initial $readmemh("./rtl/psg_ctrl.hex", ctrl_rom);
    wire [6:0] pph_nxt = (!prun || pph == 7'(PLAST)) ? 7'd0 : pph + 7'd1;
    always_ff @(posedge clk) ctrl_q <= ctrl_rom[pph_nxt];
  end else begin : g_no_ctrl
    always_comb ctrl_q = 32'b0;
  end
  endgenerate
  wire [3:0] ctrl_mul = ctrl_q[29:26];

  // ---- the computed wave layer (adoption 2.2) ------------------------
  // One evaluation pipe serves the three per-visit reads: main (issued at
  // PWORK, captured +1), secondary q view (issued +1, captured +2), old
  // continuation (issued +2, captured +3). Phase/wave/flags register at
  // issue; the cone evaluates during the following cycle. Every constant
  // multiply is a proven reciprocal form (psg_hw_forms) - yosys lowers
  // them to the priced CSD adder networks; the fabric has no DSP.
  wire iss_sec = REALTIME_PREVIEW ? (pph == 7'(PWORK + 1))
                                  : ctrl_q[CTRL_ISEC];
  wire iss_om  = REALTIME_PREVIEW ? (pph == 7'(PWORK + 2))
                                  : ctrl_q[CTRL_IOM];
  wire iss_os  = REALTIME_PREVIEW ? (pph == 7'(PWORK + 3))
                                  : ctrl_q[CTRL_IOS];
  always_comb begin
    wsel = s_snd_wave;
    wx = s_phase[23:8];
    wsec = 1'b0;
    if (iss_sec) begin
      wx = q16;                     // second voice (q0 view)
      wsec = 1'b1;
    end else if (iss_om) begin
      wsel = s_old_wave;
      wx = s_old_phase[23:8];       // old-state continuation, primary
    end else if (iss_os) begin
      wsel = s_old_wave;
      wx = q16;                     // old-state secondary (old q view)
      wsec = 1'b1;
    end
  end
  wire w_old_ctx = iss_om || iss_os;
  always_ff @(posedge clk) begin
    wx_r <= wx;
    wsel_r <= wsel;
    wsec_r <= wsec;
    walt_r <= w_old_ctx ? old_alt_r : s_ch_buzz;
  end

  // tz(v / 2^k): the proven biased arithmetic shift (psg_hw_forms tzpow).
  function automatic logic signed [17:0] tzs(
      input logic signed [17:0] v, input logic [1:0] k);
    tzs = (v + (v[17] ? $signed((18'sd1 <<< k) - 18'sd1) : 18'sd0)) >>> k;
  endfunction

  // The split remainders, forced to blocks: as LUTs these ROMs cost more
  // than the networks they replace, and REVERB=0 leaves the blocks idle.
  (* ram_style = "block" *) logic [7:0] org3[0:511];
  (* ram_style = "block" *) logic [6:0] tab7[0:1023];
  (* ram_style = "block" *) logic [6:0] tab15[0:2047];
  initial begin
    for (int i = 0; i < 512;  i++) org3[i]  = 8'(i / 3);
    for (int i = 0; i < 1024; i++) tab7[i]  = 7'(i / 7);
    for (int i = 0; i < 2048; i++) tab15[i] = 7'(i / 15);
  end
  logic [7:0] org3_q;
  logic [6:0] t7_q, t15_q;
  always_ff @(posedge clk) begin
    org3_q <= org3[org_ix];
    t7_q   <= tab7[t_ix7];
    t15_q  <= tab15[t_ix15];
  end

  // The cone is two REGISTERED stages so the reciprocal CSD networks do
  // not sit on the same path as the ramp arithmetic (routed Fmax fell
  // to 25 MHz single-cycle): stage 1 forms every linear piece and the
  // reciprocal operands; stage 2 runs the reciprocals and composes.
  // Captures shift one phase later (main +2, secondary +3, old +4).
  // tri_raw: 3x - 49152, mirrored above 0x8000; +/-49152. 3x reaches
  // 196,605, so the intermediate carries 19 unsigned bits.
  // Triangle folds BEFORE the x3: 3x - 49152 and 147456 - 3x are both
  // 3*(x - 16384) with the fold's sign pushed inside the multiply
  // (exhaustively proven, scratchpad prove_wave.py), and the fold is an
  // XOR with the sign plus a carry-in - one subtract where the fold
  // used to need two 20-bit mux arms after the x3.
  wire signed [16:0] tri_u =
      $signed({1'b0, wx_r ^ {16{wx_r[15]}}}) - 17'sd16384
      + $signed({16'b0, wx_r[15]});
  wire signed [17:0] tri_v = {tri_u[16], tri_u} + {tri_u, 1'b0};
  // The wave-1 buzz break is 61440 (>>12 + recip15), else 57344 (>>13 +
  // recip7); the tails are the pure shifts. tri_alt's skew is the 57344
  // form, selected because tilt_hi needs wave 1. (The x3 here cannot
  // merge with the triangle's: the buzz triangle consumes BOTH chains
  // in the same evaluation.)
  wire tilt_hi = (wsel_r == 3'd1) && walt_r;
  wire tilt_tail = tilt_hi ? (wx_r >= 16'd61440) : (wx_r >= 16'd57344);
  wire [15:0] tramp = tilt_tail ? (16'd65535 - wx_r) : wx_r;
  // The 24572 chain retires: 24572 = 3*8192 - 4 gives, exactly over the
  // whole ramp (prove_wave.py),
  //   floor(24572 r / 2^13) = 3r - ceil(r/2048)
  //   floor(24572 r / 2^12) = 6r - ceil(r/1024)
  // so t_pre is 3r (or its double) minus a small ceiling term - an
  // 18-bit add and a 19-bit subtract instead of two 31-bit adds.
  wire [17:0] t_m3 = {2'b0, tramp} + {1'b0, tramp, 1'b0};
  wire [6:0] t_ceil = tilt_hi ? 7'(({1'b0, tramp} + 17'd1023) >> 10)
                              : 7'(({1'b0, tramp} + 17'd2047) >> 11);
  wire [18:0] t_pre = (tilt_hi ? {t_m3, 1'b0} : {1'b0, t_m3})
                    - {12'b0, t_ceil};
  // The tilt reciprocals take the organ's shape. 512h = 7*73h + h and
  // 256h = 15*17h + h, so
  //   t/7  = 73h + (h + l)/7    with h = t>>9, l = t[8:0]
  //   t/15 = 17h + (h + l)/15   with h = t>>8, l = t[7:0]
  // exactly, and both indices stay inside a table the spare blocks can
  // carry. Eleven CSD adds become three, and the reads are the stage
  // register the cone already had.
  wire [9:0]  t_h7  = t_pre[18:9];
  wire [10:0] t_ix7 = {1'b0, t_h7} + {2'b0, t_pre[8:0]};
  wire [10:0] t_h15 = t_pre[18:8];
  wire [11:0] t_ix15 = {1'b0, t_h15} + {4'b0, t_pre[7:0]};
  // saw: tz((x - 32768)/4); saw_alt folds in the half-rate copy.
  wire signed [15:0] saw_sx = $signed({~wx_r[15], wx_r[14:0]});
  wire signed [17:0] saw_v = tzs({{2{saw_sx[15]}}, saw_sx}, 2'd2);
  wire signed [17:0] sa_h = $signed({3'b0, wx_r[15:1]}) - 18'sd32768;
  wire signed [17:0] saw_alt_v = tzs(saw_v + tzs(sa_h, 2'd2), 2'd1);
  // square/pulse: exact thresholds, buzz alternates.
  wire [15:0] sq_th = (wsel_r == 3'd3) ? (walt_r ? 16'h9800 : 16'h8000)
                                       : (walt_r ? 16'hC800 : 16'hB000);
  wire signed [17:0] sq_v = (wx_r < sq_th) ? -18'sd6143 : 18'sd6143;
  // organ linear pieces; the half-slope ramp waits for stage 2's recip3.
  wire [14:0] org_ramp = wx_r[14] ? 15'(16'd0 - wx_r) : wx_r[14:0];
  // The organ's tz(2x/3) as address-selected storage instead of a
  // nine-add CSD network. With v = 2x = 256h + l, 256h is 3*85h + h, so
  //   v/3 = 85h + (h + l)/3
  // exactly - and h+l stays under 512, which is one EBR of eighths. The
  // shifts feeding 85h are free; the table read IS the pipeline
  // register the cone already had, so no stage is added.
  wire [7:0] org_h = org_ramp[14:7];
  wire [8:0] org_ix = {1'b0, org_h} + {1'b0, org_ramp[6:0], 1'b0};
  wire signed [17:0] org_lin =
      !wx_r[14] ? ($signed({2'b0, wx_r}) - 18'sd8192)
                : (18'sd24576 - $signed({2'b0, wx_r}));
  wire signed [17:0] tri4 = tzs(tri_v, 2'd2);
  wire signed [17:0] org_alt_sec = wx_r[15] ? 18'sd3071 : -18'sd3071;

  // The stage-1 value for every non-reciprocal shape, selected here so
  // stage 2 keeps only the divide cones and the final compose.
  logic signed [17:0] z_lin;
  always_comb begin
    case (wsel_r)
      3'd0:    z_lin = tri_v;              // alt adds the skew in stage 2
      3'd7:    z_lin = tri_v;
      3'd2:    z_lin = walt_r ? saw_alt_v : saw_v;
      3'd3, 3'd4: z_lin = sq_v;
      3'd5:    z_lin = (walt_r && wsec_r) ? org_alt_sec : org_lin;
      default: z_lin = 18'sd0;             // wave 6: its own path
    endcase
  end

  logic signed [17:0] z_lin_r;
  logic [14:0] t_pre_r;      // only the tail path reads it
  logic [9:0]  t_h7_r;
  logic [10:0] t_h15_r;
  logic        tilt_hi_r, tilt_tail_r, org_hi_r;
  logic [7:0]  org_h_r;
  logic signed [17:0] tri4_r;
  logic [2:0]  wsel_r2;
  logic        wsec_r2, walt_r2;
  always_ff @(posedge clk) begin
    z_lin_r <= z_lin;
    t_pre_r <= t_pre[14:0];
    t_h7_r  <= t_h7;
    t_h15_r <= t_h15;
    tilt_hi_r <= tilt_hi;
    tilt_tail_r <= tilt_tail;
    org_hi_r <= wx_r[15];
    org_h_r <= org_h;
    tri4_r <= tri4;
    wsel_r2 <= wsel_r;
    wsec_r2 <= wsec_r;
    walt_r2 <= walt_r;
  end

  // Stage 2: ONE masked-shift recombine serves all three split
  // identities - the consuming shapes are wsel-exclusive per
  // evaluation: 73h = h<<6 + h<<3 + h (tilt lo), 17h = h<<4 + h
  // (tilt hi), 85h = h<<6 + h<<4 + h<<2 + h (organ), plus the table
  // remainder; one shared subtract then closes tz with the shape's
  // offset. Three add trees and two subtractors become one of each.
  wire org_ctx = (wsel_r2 == 3'd5);
  wire [10:0] rc_h = org_ctx ? {3'b0, org_h_r}
                   : tilt_hi_r ? t_h15_r : {1'b0, t_h7_r};
  wire [7:0] rc_q = org_ctx ? org3_q
                  : tilt_hi_r ? {1'b0, t15_q} : {1'b0, t7_q};
  wire rc_e6 = !tilt_hi_r || org_ctx;
  wire rc_e4 = tilt_hi_r || org_ctx;
  wire rc_e3 = !tilt_hi_r && !org_ctx;
  wire rc_e2 = org_ctx;
  wire [16:0] rc = (rc_e6 ? {rc_h, 6'b0} : 17'd0)
                 + (rc_e4 ? {2'b0, rc_h, 4'b0} : 17'd0)
                 + (rc_e3 ? {3'b0, rc_h, 3'b0} : 17'd0)
                 + (rc_e2 ? {4'b0, rc_h, 2'b0} : 17'd0)
                 + {6'b0, rc_h}
                 + {9'b0, rc_q};
  wire [14:0] t_div = (tilt_tail_r && !org_ctx) ? t_pre_r : rc[14:0];
  wire signed [17:0] div_out = $signed({3'b0, t_div})
                             - (org_ctx ? 18'sd8192 : 18'sd12286);
  wire signed [17:0] tri_alt_v = div_out + tri4_r + (tri4_r <<< 1);

  logic signed [17:0] z_prim;
  always_comb begin
    case (wsel_r2)
      3'd0:    z_prim = walt_r2 ? tri_alt_v : z_lin_r;
      3'd1:    z_prim = div_out;
      3'd5:    z_prim = (org_hi_r && !(walt_r2 && wsec_r2))
                          ? div_out : z_lin_r;
      default: z_prim = z_lin_r;
    endcase
  end
  // wave_pair's composition scaling: the triangle core (waves 0 and 7)
  // carries /4 main and /8 secondary; every other shape adds tz(sec/2).
  wire tri_core = (wsel_r2 == 3'd0) || (wsel_r2 == 3'd7);
  wire signed [17:0] z_eval =
      tri_core ? (wsec_r2 ? tzs(z_prim, 2'd3) : tzs(z_prim, 2'd2))
               : (wsec_r2 ? tzs(z_prim, 2'd1) : z_prim);

  // Second voice: the binary's universal 17-bit q0. Every rendering voice
  // advances q0 by dq = tz(dp*K/256), K selected per wave and detune mode.
  // Each K is at most two adds and one shift (psg_hw_forms dq.k*, all
  // exhaustively proven over the clamped dp range): the subtractive Ks are
  // dp minus a ceil term, triangle mode-1 is three shift-adds, and the
  // phaser's 254/256 default replaces the retired ~109/110 serial chain.
  wire [23:0] einc = s_eff_inc;
  // The one dq network serves both phase contexts: the live voice at
  // PWORK+6 and the old continuation at PWORK+5 (its wave/mode/dp are
  // the previous tick's, carried in the old fields).
  wire dq_old_ctx = REALTIME_PREVIEW ? (pph == 7'(PWORK + 5))
                                     : ctrl_q[CTRL_DQO];
  wire [2:0] dq_wave = dq_old_ctx ? s_old_wave : s_snd_wave;
  wire [1:0] dq_mode = dq_old_ctx ? old_mode_r : s_ch_det;
  wire [23:0] dp24 = {8'b0, dq_old_ctx ? s_old_inc[23:8] : einc[23:8]};
  logic [16:0] dq17;
  always_comb begin
    if (s_snd_wt)
      dq17 = dp24[16:0];                                        // dq = dp
    else if (dq_wave == 3'd0) begin
      case (dq_mode)
        2'd1:    dq17 = 17'(((dp24 << 7) + (dp24 << 6) + dp24) >> 8);
        2'd2:    dq17 = 17'(dp24 + (dp24 >> 1));                // K=384
        default: dq17 = dp24[16:0];                             // K=256
      endcase
    end else if (dq_wave == 3'd7) begin
      case (dq_mode)
        2'd1:    dq17 = 17'(dp24 - (((dp24 << 2) + (dp24 << 1)
                                     + 24'd255) >> 8));         // K=250
        2'd2:    dq17 = 17'((dp24 << 1) - ((dp24 + 24'd63) >> 6));  // 508
        default: dq17 = 17'(dp24 - ((dp24 + 24'd127) >> 7));    // K=254
      endcase
    end else if (dq_mode != 2'd0)
      dq17 = 17'(dp24 - ((dp24 + 24'd255) >> 8));               // K=255
    else
      dq17 = dp24[16:0];                                        // K=256
  end
  // The 16-bit q the wave functions read: u16(q0 << (mode==2)), except
  // triangle and phaser whose secondary reads u16(q0) unshifted (the
  // model's wave_pair). The preview schedule keeps its original 24-bit
  // second phase, so its view is the old [23:8] window.
  wire q_old_ctx = iss_os && !s_snd_wt;
  wire [2:0] qv_wave = q_old_ctx ? s_old_wave : s_snd_wave;
  wire [1:0] qv_mode = q_old_ctx ? old_mode_r : s_ch_det;
  wire [15:0] qv_lo = q_old_ctx ? old_q0[15:0] : s_phase2[15:0];
  wire [15:0] q16 =
      REALTIME_PREVIEW ? s_phase2[23:8]
    : (!s_snd_wt && (qv_wave == 3'd0 || qv_wave == 3'd7))
        ? qv_lo
    : (qv_mode == 2'd2) ? {qv_lo[14:0], 1'b0}
                        : qv_lo;
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
  wire v2_on = s_snd_wt || (s_snd_wave == 3'd7) || (s_ch_det != 0);

  // The transition machinery is GONE (adoption 2.4): the binary detects
  // nothing - _mix_sfx_tick copies the whole oscillator state at every
  // tick and crossfades the first 64 samples of every tick against that
  // copy, identical states blending to identity. The five phase
  // corrections, the pitch/trigger/slide comparison network and the
  // per-voice ramp all retire; the blend index is the global
  // sample-in-tick position.

  // The walk's phase updates run on their own small adder (the q0
  // precedent): the shared ALU below is the fold engine's alone, so a
  // fold chain crossing into the next visit can no longer collide with
  // a phase op - the old mutual-exclusion assertion retires with the
  // hazard.
  logic [23:0] pha_a, pha_b;
  always_comb begin
    pha_a = s_phase;
    pha_b = einc;
    if (dq_old_ctx) begin
      pha_a = s_old_phase;
      pha_b = s_old_inc;
    end
  end
  wire [23:0] pha_y = pha_a + pha_b;

  logic [23:0] fold_a, fold_b;
  logic        fold_sub, fold_cin;
  // One physical carry chain for the fold: a - b is a + ~b + 1, and the
  // single "+1" micro-op rides the same carry-in.
  wire [23:0] phase_alu_y =
      fold_a + (fold_sub ? ~fold_b : fold_b)
             + {23'b0, fold_sub | fold_cin};

  // Wavetable instruments read their 64 samples out of audio RAM, one
  // borrowed read per voice per sample (the sequencer FSM freezes for it).
  always_comb begin
    syn_rd   = 1'b0;
    syn_addr = 13'd0;
    if (prun && s_snd_wt && playing[pc_ch]) begin
      if (REALTIME_PREVIEW ? (pph == 7'(PWORK)) : ctrl_q[CTRL_SYNA]) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb + {7'b0, s_phase[23:18]};
      end else if (!REALTIME_PREVIEW && ctrl_q[CTRL_SYNB]) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb
                 + {7'b0, s_phase[23:18] + 6'd1};
      end else if ((REALTIME_PREVIEW ? (pph == 7'(PWORK + 1)) : iss_om)
                   && v2_on) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb + {7'b0, q16[15:10]};
      end else if (!REALTIME_PREVIEW && iss_os
                   && v2_on) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb
                 + {7'b0, q16[15:10] + 6'd1};
      end
    end
  end

  // ---- voice composition at the binary's z scale (2.2/2.3) -----------
  // The composed z: main lands in smp_a at PWORK+1, the secondary in
  // smp_b at +2, both already carrying wave_pair's per-read scaling, so
  // z is their plain sum. Noise bypasses the wave layer with its own
  // process value; the wavetable lerp lands its 16-bit z over smp_a and
  // smp_b at +15/+26 before the same sum.
  wire signed [17:0] z_noise =
      (s_ch_buzz && !s_ch_noiz)
        ? $signed({{2{s_brown[12]}}, s_brown, 3'b0})   // brown, x8 to z
        : {{2{s_noise_lp[15]}}, s_noise_lp};
  wire signed [17:0] z_new_c =
      (!s_snd_wt && s_snd_wave == 3'd6) ? z_noise
    : s_snd_wt ? (smp_a + tzs(smp_b, 2'd1))
               : (smp_a + smp_b);
  wire signed [17:0] z_old_c = old_smp + old_smpb;

  // Wavetable lerp, exact: z = (t0*1024 + (t1-t0)*f) >> 3 - the model's
  // (t << 7) load scale folded through the shift identity
  // ((v<<7)>>10 == v>>3). The service supplies |delta*f|; the sign
  // rebuilds the exact signed product and the floor shift runs on the
  // whole sum, matching custom_wave's arithmetic >>10.
  wire signed [8:0] wt_pd =
      $signed({wt_p1[7], wt_p1}) - $signed(smp_a[8:0]);
  wire signed [8:0] wt_qd =
      $signed({wt_q1[7], wt_q1}) - $signed(smp_b[8:0]);
  wire signed [19:0] wt_prod =
      wi_neg ? -$signed({1'b0, m_res_wide[18:0]})
             :  $signed({1'b0, m_res_wide[18:0]});
  // The p-side consume (+15) bases on smp_a's table byte; the q-side
  // (+26) must base on smp_b's - by then smp_a already holds the p
  // RESULT, which is what a shared base compounded into garbage.
  wire signed [17:0] wt_base =
      (pph == 7'(PWORK + 26)) ? smp_b : smp_a;
  wire signed [19:0] wt_sum = $signed({wt_base[9:0], 10'b0}) + wt_prod;
  wire signed [17:0] wt_z = 18'(wt_sum >>> 3);

  // Built-in noise is a stateful one-pole process, not a flat
  // sample-and-hold. Q8 coefficient 15/16 gives the exported reference's
  // short-lag decay. Statistical territory: the shared-RNG boundary.
  wire signed [15:0] noise_target = $signed({lfsr[7:0], 8'b0});
  wire signed [16:0] noise_delta =
      $signed({noise_target[15], noise_target})
      - $signed({s_noise_lp[15], s_noise_lp});
  wire signed [16:0] noise_step =
      $signed({s_noise_lp[15], s_noise_lp}) + (noise_delta >>> 4);
  wire signed [15:0] noise_next = noise_step[15:0];

  // The amplitude ladder (2.3): the bank publishes the binary's 12-bit
  // `a`; detuned voices of waves 0..5 take the tz(5a/4) boost, and
  // G = tz(3a/2) - both proven shift-adds. G rides the serial service
  // in two limb passes (svc.two_pass_G), the >>10 and the /3
  // reciprocal close tz(G*z/3072), and noise takes /2048 (>>11).
  wire g_boost = (s_ch_det != 2'd0) && !s_snd_wt
                 && !(s_snd_wave[2] & s_snd_wave[1]);
  wire [12:0] g_a = g_boost ? ({1'b0, s_eff_a} + {3'b0, s_eff_a[11:2]})
                            : {1'b0, s_eff_a};
  wire [12:0] g_live = g_a + {1'b0, g_a[12:1]};

  logic        mx_play;
  logic signed [16:0] mx_filt;        // post-comb, post-dampen sample
  logic [9:0]  ring_rp;               // global ring position, per sample
  // Whether this slot is HEARD, as opposed to merely running. A music
  // slot is silenced while its channel's foreground effect plays, but it
  // still renders; only the mixer leaf is zeroed. mx_play (does it run)
  // and mx_aud (is it audible) must stay separate.
  logic        mx_aud;
  logic        mxs_new, mxs_old;      // saved z signs for the G products
  logic [24:0] g_part;                // the recip3-hi partial
  logic [16:0] gz_s1_r;               // captured G*z >> 10 for /3
  // the noise bypass (>>11) is gz_s1_r >> 1: floor of floor.
  logic signed [16:0] mx_new, mx_old, mx_prod;
  // tz(G*z/3072): ONE 12-bit-B service pass forms the whole product
  // magnitude (m_res12), then the /3 runs serially as two limb passes
  // of the reciprocal (174763 = 341*2^9 + 171), replacing the
  // combinational recip3 network the fabric could not afford. The q3
  // accumulator closes the >>19.
  wire [33:0] gz_q3acc = {g_part, 9'b0} + {9'b0, m_res_wide[24:0]};
  wire [16:0] gz_scaled = (!s_snd_wt && s_snd_wave == 3'd6)
                            ? {1'b0, gz_s1_r[16:1]}       // noise /2048
                            : {2'b0, gz_q3acc[33:19]};
  wire [16:0] gz_old_scaled = (s_old_wave == 3'd6)
                            ? {1'b0, gz_s1_r[16:1]}
                            : {2'b0, gz_q3acc[33:19]};
  wire signed [16:0] mx_old_eff =
      s_snd_wt ? ((s_old_G == 13'd0) ? 17'sd0 : mx_new) : mx_old;
  // COMB: tz((2x + h)/2) (the study's narrowed accumulator). It sits
  // INSIDE each block's render, not after the crossfade, and each block
  // combs at its OWN state's level - the reverb digit is oscillator
  // state, so the copied old continuation carries the level the previous
  // tick asked for. filter-reverb-onset/-level convict the
  // after-the-blend order: it diverges on exactly the 64 crossfade
  // samples of every switching tick, by the half tap the old
  // continuation must not receive. With h=0 (no ring, or an empty one)
  // the comb is the identity, so the datapath is uniform.
  logic signed [15:0] ring_q;         // new-level tap (0 without a ring)
  logic signed [15:0] ring_q_old;     // old-level tap
  wire signed [18:0] cmbn_acc = {mx_new[16], mx_new, 1'b0}
                              + {{3{ring_q[15]}}, ring_q};
  wire signed [18:0] cmbn_tz = cmbn_acc + (cmbn_acc[18] ? 19'sd1 : 19'sd0);
  wire signed [16:0] cmb_new = (s_ch_rev != 2'd0) ? cmbn_tz[17:1]
                                                  : mx_new;
  wire signed [18:0] cmbo_acc = {mx_old_eff[16], mx_old_eff, 1'b0}
                              + {{3{ring_q_old[15]}}, ring_q_old};
  wire signed [18:0] cmbo_tz = cmbo_acc + (cmbo_acc[18] ? 19'sd1 : 19'sd0);
  wire signed [16:0] cmb_old = (old_rev_r != 2'd0) ? cmbo_tz[17:1]
                                                   : mx_old_eff;
  wire signed [17:0] blend_diff =
      {cmb_new[16], cmb_new} - {cmb_old[16], cmb_old};
  wire signed [23:0] bl_p = blend_diff[17]
                              ? -$signed({1'b0, bl_res})
                              :  $signed({1'b0, bl_res});
  wire signed [23:0] bl_acc = {{1{cmb_old[16]}}, cmb_old, 6'b0}
                            + bl_p;
  wire signed [23:0] bl_acc_tz =
      bl_acc + (bl_acc[23] ? 24'sd63 : 24'sd0);
  // DAMPEN runs once, on the blended stream, with the current digit:
  // the blend-form one-pole y = tz((x + (2^d - 1)y)/2^d). The ring
  // stores the final post-comb, post-dampen sample through a WRAPPING
  // int16 cell (captured; a saturating or wider cell is a different
  // answer).
  wire signed [18:0] dmp_mul = (s_ch_damp == 2'd1)
                                 ? {{2{s_lp[16]}}, s_lp}
                                 : ({s_lp, 2'b0} - {{2{s_lp[16]}}, s_lp});
  wire signed [18:0] dmp_acc = {{2{mx_prod[16]}}, mx_prod} + dmp_mul;
  wire signed [18:0] dmp_tz =
      dmp_acc + (dmp_acc[18] ? ((s_ch_damp == 2'd1) ? 19'sd1 : 19'sd3)
                             : 19'sd0);
  wire signed [16:0] dmp_y = (s_ch_damp == 2'd1) ? dmp_tz[17:1]
                                                 : dmp_tz[18:2];
  wire signed [16:0] filt_y = (s_ch_damp != 2'd0) ? dmp_y : mx_prod;
  // The shared service forms |new-old| * blend_pos; dividing by 64 is a
  // wiring shift and the saved sign reproduces truncation toward zero.
  wire [22:0] bl_res = m_res[22:0];

  // One physical request mux and one sequential write site make the effect
  // multiplier a PSG-wide service. A sample walk freezes the tick sequencer;
  // any product launched on the sample boundary finishes well before the
  // first sample request at PWORK+2/PWORK+4.
  logic        mul_start;
  logic signed [24:0] mul_start_a;
  logic [11:0] mul_start_b;
  logic [1:0]  mul_start_mode;
  always_comb begin
    mul_start      = 1'b0;
    mul_start_a    = 25'sd0;
    mul_start_b    = 12'd0;
    mul_start_mode = 2'd0;
    if (prun && !m_busy) begin
      if (REALTIME_PREVIEW) begin
        if (pph == 7'(PWORK + 2)) begin
          mul_start   = 1'b1;
          mul_start_a = 25'(z_new_c);
          mul_start_b = {2'b0, s_eff_a[11:4]};
        end
      end else begin
        // The G*z product runs as two limb passes per voice
        // (svc.two_pass_G): |z| x G[12:7] then |z| x G[6:0], the partial
        // captured between them and recombined by gz_mag at the consume
        // step. New voice at +4/+13 (consumed +22), old continuation at
        // +22/+31 (consumed +40), blend at +40 (consumed +49); the
        // wavetable path lerps first and takes its G passes at +27/+36.
        // The step association lives in the control store's MUL_SEL
        // field (tools/gen_psg_ctrl.py) - the arm ids below match it.
        case (ctrl_mul)
          4'd1: begin
            mul_start = 1'b1;
            if (s_snd_wt) begin
              mul_start_a = 25'(wt_pd);
              mul_start_b = {2'b0, wt_pf};
              mul_start_mode = 2'd1;
            end else begin
              // ONE 12-bit G pass: |z| x G on the widened B port.
              mul_start_a = 25'(z_new_c);
              mul_start_b = 12'(g_live);
              mul_start_mode = 2'd2;
            end
          end
          // /3 limb passes: m_res12 is the whole G*z magnitude.
          4'd3: if (!s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = {8'b0, m_res12[26:10]};
            mul_start_b = 12'd341;
            mul_start_mode = 2'd1;
          end
          4'd5: if (!s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = {8'b0, gz_s1_r};
            mul_start_b = 12'd171;
            mul_start_mode = 2'd1;
          end
          4'd6: if (!s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = 25'(z_old_c);
            mul_start_b = 12'(s_old_G);
            mul_start_mode = 2'd2;
          end
          4'd9: if (!s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = {8'b0, m_res12[26:10]};
            mul_start_b = 12'd341;
            mul_start_mode = 2'd1;
          end
          4'd10: if (!s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = {8'b0, gz_s1_r};
            mul_start_b = 12'd171;
            mul_start_mode = 2'd1;
          end
          4'd11: if (bl_cnt != 7'd64) begin
            mul_start   = 1'b1;
            mul_start_a = 25'(blend_diff);
            mul_start_b = {6'b0, bl_cnt[5:0]};
          end
          4'd2: if (s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = 25'(wt_qd);
            mul_start_b = {2'b0, wt_qf};
            mul_start_mode = 2'd1;
          end
          4'd4: if (s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = 25'(z_new_c);
            mul_start_b = 12'(g_live);
            mul_start_mode = 2'd2;
          end
          4'd7: if (s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = {8'b0, m_res12[26:10]};
            mul_start_b = 12'd341;
            mul_start_mode = 2'd1;
          end
          4'd8: if (s_snd_wt) begin
            mul_start   = 1'b1;
            mul_start_a = {8'b0, gz_s1_r};
            mul_start_b = 12'd171;
            mul_start_mode = 2'd1;
          end
          default: ;
        endcase
      end
    end else if (!walk_frozen) begin
      case (sst)
        // mul_go names the steps that actually have operands; the rest
        // are register writes, divide launches or the publish handshake.
        K_FX: if (!m_busy && mul_go
                  && !((xs == 4'd7 || xs == 4'd10) && d_busy)
                  && !(xs == 4'd2 && e_fx == 3'd1)) begin
          mul_start   = 1'b1;
          mul_start_a = mul_a;
          mul_start_b = mul_b;
          mul_start_mode = mul_md;
        end
        // The affine multiply, one 12-bit pass each side of the split.
        K_SL3: if (!m_busy) begin
          mul_start   = 1'b1;
          mul_start_a = {9'b0, sl_frac};
          mul_start_b = crom_q[11:0];
          mul_start_mode = 2'd2;
        end
        K_SL6: if (!m_busy) begin
          mul_start   = 1'b1;
          mul_start_a = {9'b0, sl_frac};
          mul_start_b = {3'b0, sl_bhi};
          mul_start_mode = 2'd2;
        end
        // The music pattern's tick length, launched fire-and-forget; the
        // ungated capture in the sequencer picks m_res up when it lands.
        // m cannot be busy here - the nearest preceding launch site is the
        // previous slot's xs 6 product, a full record store earlier - and
        // the simulation-only check below guards that schedule fact.
        T_NL: if (launched[c] && !tch_seen && !(acc[7:0] < seq_q)) begin
          mul_start   = 1'b1;
          mul_start_a = {17'b0, wrd[7:0]};       // speed, staged at T_LS
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
      m_p   <= (m_mode == 2'd2) ? {m_sum, m_p[11:1]}
             : (m_mode == 2'd1) ? {2'b0, m_sum, m_p[9:1]}
                                : {4'b0, m_sum, m_p[7:1]};
      m_cnt <= m_cnt - 1;
    end else if (mul_start) begin
      // The one place signs are stripped: requesters pass raw signed
      // values and keep their own saved sign for the consume step, so
      // the per-source magnitude networks retire. Truncation points are
      // unchanged - the product is formed and scaled in the magnitude
      // domain exactly as before.
      m_a    <= mul_start_a[24] ? (24'd0 - mul_start_a[23:0])
                                : mul_start_a[23:0];
      m_p    <= {25'b0, mul_start_b};
      m_mode <= mul_start_mode;
      m_cnt  <= (mul_start_mode == 2'd2) ? 4'd12
              : (mul_start_mode == 2'd1) ? 4'd10 : 4'd8;
    end
  end

  // The mixer consumes the STORED cell value: the binary keeps one
  // int16 block per voice, so the wrap the ring applies is what the
  // tree reads too (the fixpoint ladder convicts unbounded feed).
  wire signed [16:0] mix_prod =
      REALTIME_PREVIEW
        ? (mxs_new ? -$signed({1'b0, m_res[22:7]})
                   :  $signed({1'b0, m_res[22:7]}))
        : {mx_filt[15], mx_filt[15:0]};
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
  localparam signed [22:0] SA_TH = 23'sd24576;    // the binary's, at 1x
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

  logic signed [15:0] dry16;
  logic        dry_valid;

  // The per-voice history rings (design 8 / the buffer study): flat
  // 732 x int16 per slot, written UNCONDITIONALLY every rendered
  // sample (captured: a slot with no reverb digit still fills its
  // ring), read at 366 (level 1) or 732 (level 2, read-before-write by
  // schedule) samples of lookback. Absent rings read zero and the comb
  // degenerates to the identity.
  generate
  if (REVERB) begin : g_ring
    logic [15:0] ringm[0:NV * 732 - 1];
    logic [15:0] ring_rd;
    initial for (int i = 0; i < NV * 732; i++) ringm[i] = 16'd0;
    // Both blocks tap the same ring at their own lookback, so the two
    // reads are sequenced onto ONE port: the new level at +70, the old
    // at +71, both landing before the blend product launches at +75.
    // Level 2's tap is the write cell itself; the write stays at +87,
    // so it is still read-before-write.
    wire [1:0] ring_lvl = (pph == 7'(PWORK + 70)) ? s_ch_rev : old_rev_r;
    wire [9:0] ring_tap =
        (ring_lvl == 2'd1)
          ? ((ring_rp >= 10'd366) ? ring_rp - 10'd366
                                  : ring_rp + 10'd366)
          : ring_rp;
    always_ff @(posedge clk) begin
      if (prun && (pph == 7'(PWORK + 70) || pph == 7'(PWORK + 71)))
        ring_rd <= ringm[{4'b0, pc_ch} * 732 + {3'b0, ring_tap}];
      if (prun && pph == 7'(PWORK + 71))
        ring_q <= $signed(ring_rd);
      if (prun && pph == 7'(PWORK + 72))
        ring_q_old <= $signed(ring_rd);
      if (prun && pph == 7'(PWORK + 87) && playing[pc_ch])
        ringm[{4'b0, pc_ch} * 732 + {3'b0, ring_rp}] <= mx_filt[15:0];
    end
  end else begin : g_noring
    always_comb ring_q = 16'sd0;
    always_comb ring_q_old = 16'sd0;
  end
  endgenerate

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
                dry16 <= 16'($signed(fstk[0]));
                dry_valid <= 1;
              end
            end
          end
        endcase
      end

      if (sample_en) begin
        prun <= 1;
        pc_ch <= 0;
        pph <= 0;
        ring_rp <= (ring_rp == 10'd731) ? 10'd0 : ring_rp + 10'd1;
      end else if (prun) begin
        // ---- record load: word pph-1 has landed ----------------------
        case (pph)
          7'd1: s_phase <= {state_q, 8'b0};
          7'd2: {s_nz_hold, old_q0[7:0]} <= state_q;
          7'd3: s_phase2[15:0] <= state_q;
          7'd4: if (REALTIME_PREVIEW)
                  {s_nz_ph, s_phase2[23:16]} <= state_q[11:0];
                else begin
                  s_old_G[12:8]  <= state_q[14:10];
                  s_last_G[12:8] <= state_q[9:5];
                  s_nz_ph        <= state_q[4:1];
                  s_phase2[23:16] <= {7'b0, state_q[0]};
                end
          7'd5: if (REALTIME_PREVIEW)
                  s_brown <= state_q[12:0];
                else
                  {s_lp[16], old_mode_r, s_brown} <= state_q;
          7'd6: if (!REALTIME_PREVIEW) s_lp[15:0] <= state_q;
          7'd7: if (REALTIME_PREVIEW)
                   s_noise_lp <= state_q;
                else
                   s_old_phase <= {state_q, 8'b0};
          7'd8: if (!REALTIME_PREVIEW)
                   {bl_cnt, old_q0[16:8]} <= state_q;
          7'd9: if (!REALTIME_PREVIEW) s_old_inc[15:0] <= state_q;
          7'd10: if (!REALTIME_PREVIEW)
                    {s_old_G[7:0], s_old_inc[23:16]} <= state_q;
          7'd11: if (!REALTIME_PREVIEW)
                    {old_rev_r, last_rev_r, s_last_wave,
                     s_last_inc[23:16]} <= state_q[14:0];
          7'd12: if (!REALTIME_PREVIEW) s_last_inc[15:0] <= state_q;
          7'd13: if (!REALTIME_PREVIEW)
                    {old_alt_r, last_alt_r, last_mode_r, s_old_wave,
                     s_last_G[7:0]} <= state_q[14:0];
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
            {s_ch_damp, s_ch_rev, s_ch_det, s_ch_buzz,
             s_ch_noiz, s_snd_pitch} <= state_q[13:0];
          7'(PLOSC + 4):
            s_eff_a <= state_q[11:0];
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
              if (playing[pc_ch] && s_eff_a != 0) begin
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
              if (playing[pc_ch] && s_eff_a != 0 && v2_on)
                s_phase2 <= s_phase2 + preview_v2inc;
              smp_a <= s_snd_wt ? 18'($signed(seq_q)) : z_eval;
            end
            7'(PWORK + 2): begin
              smp_b <= s_snd_wt ? 18'($signed(seq_q)) : z_eval;
              mxs_new <= z_new_c[17];
              mx_play <= playing[pc_ch];
              mx_aud  <= playing[pc_ch]
                         & ~(is_mus(pc_ch)
                             & playing[{1'b0, pc_ch[1:0]}]);
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
            end
            default: ;
          endcase
        end else begin
        // Step decode rides the control store; the case is over the
        // one-hot bits themselves, declared parallel so the arms map
        // as a flat pmux. The generator asserts one capture bit per
        // word - that invariant is what the attribute states, and a
        // hand-edited hex that broke it would diverge sim vs synth.
        (* parallel_case *)
        case (1'b1)
          ctrl_q[CTRL_W0]: begin               // advance phase(s), issue main read
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
            if (playing[pc_ch] && s_eff_a != 0) begin
              if (!s_snd_wt) begin
                s_phase <= pha_y;
              end else begin
                wt_pf <= s_phase[17:8];
                wt_qf <= q16[9:0];
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
            // The binary copies the WHOLE oscillator state at every
            // tick and blends the first 64 samples of every tick against
            // that copy. An unchanged tick's blend is the identity, so
            // copying only when a sounding parameter changes is
            // byte-equivalent - and it starts the window at the voice's
            // own parameter arrival, absorbing trigger-service latency.
            // The reverb digit counts as a sounding parameter: the two
            // blocks comb at their own levels, so a level change alone
            // makes the blend audible (filter-reverb-onset/-level).
            if (playing[pc_ch]
                && (s_eff_inc != s_last_inc || g_live != s_last_G
                    || s_snd_wave != s_last_wave
                    || s_ch_det != last_mode_r
                    || s_ch_rev != last_rev_r
                    || s_ch_buzz != last_alt_r)) begin
              bl_cnt <= 7'd0;
              s_old_phase <= s_phase;
              old_q0 <= s_phase2[16:0];
              s_old_inc <= s_last_inc;
              s_old_G <= s_last_G;
              s_old_wave <= s_last_wave;
              old_mode_r <= last_mode_r;
              old_alt_r <= last_alt_r;
              old_rev_r <= last_rev_r;
              // A zero-amplitude tick is not an inaudible running
              // oscillator: the next nonzero tick starts from the
              // canonical phase (speed-2 fade-in rows prove it).
              if (s_eff_a == 0) begin
                s_phase <= 0;
                s_phase2 <= 0;
              end
            end else if (bl_cnt != 7'd64)
              bl_cnt <= bl_cnt + 7'd1;
            // a trigger asked for this channel's filter state to be reset
            if (clr_tog[pc_ch] != clr_ack[pc_ch]) begin
              clr_ack[pc_ch] <= clr_tog[pc_ch];
              s_lp <= 0;
              s_brown <= 0;
              s_noise_lp <= 0;
            end
          end
          ctrl_q[CTRL_W1]: begin           // main-voice sample
            // Keep q's synchronous ROM address on the pre-advance phase,
            // matching PICO-8's render-then-advance oscillator ordering.
            if (playing[pc_ch] && s_eff_a != 0 && s_snd_wt)
              s_phase <= pha_y;
            if (s_snd_wt)
              smp_a <= 18'($signed(seq_q));
          end
          ctrl_q[CTRL_W2]: begin           // second voice
            if (s_snd_wt)
              wt_p1 <= $signed(seq_q);
            else
              smp_a <= z_eval;           // main z, one stage later
            s_last_inc <= s_eff_inc;
            // A pattern handoff publishes zero volume while music itself
            // is still active. Preserve only that last audible field
            // across the gap.
            if (playing[pc_ch] || !(is_mus(pc_ch) && mus_playing))
              s_last_G <= g_live;
            s_last_wave <= s_snd_wave;
            last_mode_r <= s_ch_det;
            last_alt_r <= s_ch_buzz;
            last_rev_r <= s_ch_rev;
          end
          ctrl_q[CTRL_W3]: begin           // preceding-state waveform sample
            if (s_snd_wt)
              smp_b <= 18'($signed(seq_q));
            else
              smp_b <= z_eval;           // secondary z
          end
          ctrl_q[CTRL_W4]: begin
            if (!s_snd_wt)
              old_smp <= z_eval;         // old main z
            if (s_snd_wt) begin
              // PICO-8 interpolates its 64 signed wavetable samples with ten
              // fractional phase bits. The PSG-wide product service evaluates
              // p and then q; wi_neg reapplies floor rounding via the sign.
              wt_q1 <= $signed(seq_q);
              wi_neg <= wt_pd[8];
            end else begin
              // First G*z limb pass launches this cycle; stage the sign
              // and the mixer-leaf gating.
              mxs_new <= z_new_c[17];
              mx_play <= playing[pc_ch];
              // Audible unless this music slot has a foreground effect.
              mx_aud  <= playing[pc_ch]
                         & ~(is_mus(pc_ch) & playing[{1'b0, pc_ch[1:0]}]);
            end
          end
          ctrl_q[CTRL_W15]: begin
            if (s_snd_wt) begin
              smp_a <= wt_z;
              wi_neg <= wt_qd[8];
            end
          end
          ctrl_q[CTRL_W5]: begin
            // The old waveform read has captured the pre-advance phase.
            // The dq network serves the OLD context this cycle.
            if (!s_snd_wt) begin
              old_smpb <= z_eval;        // old secondary z
              if (s_old_G != 0) begin
                s_old_phase <= pha_y;
                old_q0 <= 17'(old_q0 + dq17);
              end
            end
          end
          ctrl_q[CTRL_W6]: begin
            // All secondary waveform reads have captured the pre-advance
            // phase. The universal q0 advances for EVERY rendering voice -
            // the binary's `q0 = (q0 + dq) & 0x1ffff` - on a dedicated
            // 17-bit add. The old v2_on gating and the DETUNE-1/phaser
            // multi-step ALU sequence (PWORK+7..9) are retired; dq17 holds
            // the proven per-wave adder forms, including the phaser's
            // 254/256 that replaces the ~109/110 approximation.
            if (playing[pc_ch] && s_eff_a != 0)
              s_phase2 <= {7'b0, 17'(s_phase2[16:0] + dq17)};
          end
          ctrl_q[CTRL_W17]: begin
            // The G pass is done: capture the >>10 for the second /3
            // limb and the >>11 for the noise bypass while the first
            // limb launches.
            if (!s_snd_wt) begin
              gz_s1_r <= m_res12[26:10];
              mxs_old <= z_old_c[17];
            end
          end
          ctrl_q[CTRL_W26]: begin
            if (s_snd_wt)
              smp_b <= wt_z;
          end
          ctrl_q[CTRL_W27]: begin
            if (s_snd_wt) begin
              mxs_new <= z_new_c[17];
              mx_play <= playing[pc_ch];
              mx_aud  <= playing[pc_ch]
                         & ~(is_mus(pc_ch) & playing[{1'b0, pc_ch[1:0]}]);
            end
          end
          ctrl_q[CTRL_W28]: begin
            if (!s_snd_wt)
              g_part <= m_res_wide[24:0];       // recip3-hi
          end
          ctrl_q[CTRL_W39]: begin
            // The /3-lo result is live: consume mx_new while the old
            // voice's G pass launches.
            if (!s_snd_wt)
              mx_new <= mxs_new ? -$signed(gz_scaled) : $signed(gz_scaled);
          end
          ctrl_q[CTRL_W40]: begin
            if (s_snd_wt)
              gz_s1_r <= m_res12[26:10];
          end
          ctrl_q[CTRL_W51]: begin
            if (s_snd_wt)
              g_part <= m_res_wide[24:0];
          end
          ctrl_q[CTRL_W52]: begin
            if (!s_snd_wt)
              gz_s1_r <= m_res12[26:10];        // old G*z
          end
          ctrl_q[CTRL_W62]: begin
            if (s_snd_wt)
              mx_new <= mxs_new ? -$signed(gz_scaled) : $signed(gz_scaled);
          end
          ctrl_q[CTRL_W63]: begin
            if (!s_snd_wt)
              g_part <= m_res_wide[24:0];       // old recip3-hi
          end
          ctrl_q[CTRL_W74]: begin
            if (!s_snd_wt)
              mx_old <= mxs_old ? -$signed(gz_old_scaled)
                                : $signed(gz_old_scaled);
          end
          ctrl_q[CTRL_W86]: begin
            // The dampen stage, on the already-combed and blended
            // sample; the dampen state advances only when its digit is
            // set, like the model's damp_y.
            mx_filt <= filt_y;
            if (s_ch_damp != 2'd0)
              s_lp <= dmp_y;
          end
          ctrl_q[CTRL_W84]: begin
            // Blend consume: tz((64*old + i*(new - old)) / 64) over the
            // COMBED blocks - the truncation is over the WHOLE
            // accumulator (blend.one_multiply + tzpow), not split across
            // the terms.
            if (bl_cnt == 7'd64)
              mx_prod <= cmb_new;
            else
              mx_prod <= 17'(bl_acc_tz >>> 6);
          end
          ctrl_q[CTRL_FOLD]: begin               // fold into the tree
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
          end
          default: ;
        endcase
        end
      end
    end
  end

  // Output stage: the mixed sum is the PCM - the adopted reverb is
  // per-voice, pre-mix (the rings above); the old shared post-mix
  // delay is gone.
  always_ff @(posedge clk) begin
    if (reset) pcm <= 16'sd0;
    else if (dry_valid) pcm <= dry16;
  end

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
      dbg[11:8]  = {playing[3], playing[2], playing[1], playing[0]};
      dbg[15:12] = {playing[7], playing[6], playing[5], playing[4]};
      dbg[21:16] = sfx_id[aud_sl(2'd0)];
      dbg[27:22] = sfx_id[aud_sl(2'd1)];
      dbg[33:28] = sfx_id[aud_sl(2'd2)];
      dbg[39:34] = sfx_id[aud_sl(2'd3)];
      dbg[45:40] = {1'b0, aud_row[2'd0]};
      dbg[51:46] = {1'b0, aud_row[2'd1]};
      dbg[57:52] = {1'b0, aud_row[2'd2]};
      dbg[63:58] = {1'b0, aud_row[2'd3]};
    end
  end else begin : g_no_dbg
    always_comb dbg = 64'b0;
  end
  endgenerate

endmodule
