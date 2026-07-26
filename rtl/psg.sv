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
// Synthesis: 8 waveforms (six exact shapes from a generated wave ROM,
// pitched sample-and-hold LFSR noise, dual-oscillator phaser) and all 8
// note effects evaluated per tick (slide, vibrato, drop, fade in/out,
// fast/slow arpeggio). Channels are serialized through one datapath
// between samples; the mix clips PICO-8-style (one full-volume triangle
// = half scale).
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
module psg #(parameter CLK_HZ = 32'd3_506_580, parameter REVERB = 1)
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

  logic signed [7:0] wrom[0:2047];   // 8 waves x 256, exact PICO-8 shapes
  // Noise gain per key: PICO-8's noise amplitude rises with pitch and this
  // chip's sample-and-hold is flat, so the slope is restored from a table.
  // 1.0 = 256. See tools/gen_psg_tables.py.
  logic [7:0]  nz_gain[0:63];
  logic [23:0] pinc[0:63];           // 2^24 * f(pitch) / 22050
  logic [15:0] recip[0:255];         // 65536 / speed
  initial begin
    $readmemh("./rtl/psg_waves.hex", wrom);
    $readmemh("./rtl/psg_pitch.hex", pinc);
    $readmemh("./rtl/psg_noise.hex", nz_gain);
    $readmemh("./rtl/psg_recip.hex", recip);
  end

  // ------------------------------------------------------------------
  // Timing: 22050 Hz virtual sample rate, sequencer tick every 183
  // ------------------------------------------------------------------
  logic [31:0] divacc;
  logic        sample_en;
  logic [7:0]  scnt;
  logic        tick_en;

  always_ff @(posedge clk) begin
    if (reset) begin
      divacc <= 0;
      sample_en <= 0;
      scnt <= 0;
      tick_en <= 0;
    end else begin
      tick_en <= 0;
      if (divacc >= CLK_HZ - 32'd22050) begin
        divacc <= divacc - (CLK_HZ - 32'd22050);
        sample_en <= 1;
        if (scnt == 8'd182) begin
          scnt <= 0;
          tick_en <= 1;
        end else
          scnt <= scnt + 1;
      end else begin
        divacc <= divacc + 32'd22050;
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
  localparam int VREC = 10;                    // 16-bit words actually used
  localparam int VSTR = 16;                    // stride, padded to a power of 2
  localparam int VADR = VW + 4;
  logic [15:0] vmem[0:NV*VSTR-1];
  logic [VADR-1:0] vraddr, vwaddr;
  logic [15:0] vwdata, vq;
  logic        vwe;
  logic [3:0]  vcnt;                           // word within the record
  // Simulation determinism, and a free BRAM init on iCE40. Without it iverilog
  // starts the record at X and the X leaks through the packing.
  initial for (int i = 0; i < NV * VSTR; i++) vmem[i] = 16'h0000;
  // The note record's memory is instantiated below, next to seq_frozen.

  // The working copy: the record of the slot the walk is visiting.
  logic [7:0]  w_fcnt, w_tcnt;
  logic [7:0]  w_sp, w_lps, w_lpe;
  logic [5:0]  w_cur_pitch, w_prev_pitch;
  logic [2:0]  w_cur_wave, w_cur_vol, w_cur_fx, w_prev_vol;
  logic [5:0]  w_play_len;
  logic        w_bf_noiz, w_bf_buzz;
  logic [1:0]  w_bf_det, w_bf_rev, w_bf_damp;
  logic        w_ins_on, w_ins_wt, w_ins_bass, w_ins_done;
  logic [2:0]  w_ins_id;
  logic [4:0]  w_ins_row;
  logic [7:0]  w_ins_fcnt, w_ins_tcnt;
  logic [7:0]  w_ins_sp, w_ins_lps, w_ins_lpe;
  logic [5:0]  w_ins_pitch, w_ins_prev_pitch;
  logic [2:0]  w_ins_wave, w_ins_vol, w_ins_fx, w_ins_prev_vol;

  // Record layout, 154 bits in 10 words. This MUST stay an always_comb reading
  // the working registers directly, not a function called from a continuous
  // assign: iverilog does not infer sensitivity to signals a function reads
  // internally, so `assign vwdata = vpack(vcnt)` held 0 forever and every store
  // wrote zeros - the slot reloaded blank state each tick and no row ever
  // advanced. Verilator was happy with it, which is why this needs saying.
  // The unpack in V_LD is the mirror of this and the two must move together.
  always_comb begin
    case (vcnt)
      4'd0: vwdata = {w_tcnt, w_fcnt};
      4'd1: vwdata = {w_lps, w_sp};
      4'd2: vwdata = {w_ins_wt, w_ins_on, w_play_len, w_lpe};
      4'd3: vwdata = {w_ins_bass, w_cur_wave, w_prev_pitch, w_cur_pitch};
      4'd4: vwdata = {w_ins_done, w_bf_rev, w_bf_det, w_bf_buzz, w_bf_noiz,
                      w_prev_vol, w_cur_fx, w_cur_vol};
      4'd5: vwdata = {w_ins_vol, w_ins_wave, w_ins_row, w_ins_id, w_bf_damp};
      4'd6: vwdata = {w_ins_tcnt, w_ins_fcnt};
      4'd7: vwdata = {w_ins_lps, w_ins_sp};
      4'd8: vwdata = {2'b0, w_ins_pitch, w_ins_lpe};
      default: vwdata = {4'b0, w_ins_prev_vol, w_ins_fx, w_ins_prev_pitch};
    endcase
  end

  // ------------------------------------------------------------------
  // Per-slot synthesis state: two more BRAM register files
  // ------------------------------------------------------------------
  // The remaining per-slot state splits by who writes it, and that split is
  // what decides the port structure:
  //
  //   spar  45 bits - what the note sounds LIKE. The sequencer produces it
  //                   once per tick; the synthesis walk only reads it. That is
  //                   a plain producer/consumer, so it maps onto an
  //                   SB_RAM40_4K's independent write and read ports with no
  //                   arbitration at all.
  //   sosc  89 bits - the oscillator state. The synthesis walk reads AND
  //                   writes it, and nothing else touches it, so it is a
  //                   single-owner memory.
  //
  // Both are padded to a 16-word stride. That is not laziness about packing:
  // yosys will not spend a 4096-bit block RAM on a few hundred bits, so a
  // tightly packed 48-word memory stays in LUTs and the whole exercise buys
  // nothing. Padding to 128 x 16 = 2048 bits is what makes it infer, and block
  // RAM is the resource this design has spare (17 of 32 before this).
  localparam int SPAR = 4;                     // words of parameters
  localparam int SOSC = 6;                     // words of oscillator state
  logic [15:0] spar_m[0:NV*16-1];
  logic [15:0] sosc_m[0:NV*16-1];
  logic [VADR-1:0] spar_wa, spar_ra, sosc_wa, sosc_ra;
  logic [15:0] spar_wd, spar_q, sosc_wd, sosc_q;
  logic        spar_we, sosc_we;
  initial for (int i = 0; i < NV*16; i++) begin
    spar_m[i] = 16'h0000;
    sosc_m[i] = 16'h0000;
  end
  always_ff @(posedge clk) begin
    if (spar_we) spar_m[spar_wa] <= spar_wd;
    spar_q <= spar_m[spar_ra];
    if (sosc_we) sosc_m[sosc_wa] <= sosc_wd;
    sosc_q <= sosc_m[sosc_ra];
  end

  // The sequencer's working copy of the parameters: what it is building for the
  // slot it is visiting, published to spar_m when the visit ends.
  logic [23:0] w_eff_inc;
  logic [2:0]  w_snd_wave;
  logic        w_snd_wt;
  logic [2:0]  w_snd_id;              // was a 13-bit base address; see s_snd_wtb
  logic [5:0]  w_snd_pitch;
  logic        w_ch_noiz, w_ch_buzz;
  logic [1:0]  w_ch_det, w_ch_rev, w_ch_damp;
  logic [7:0]  w_eff_vol;

  // The synthesis walk's working copy: parameters loaded from spar_m,
  // oscillator state loaded from sosc_m and written back.
  logic [23:0] s_eff_inc;
  logic [2:0]  s_snd_wave;
  logic        s_snd_wt;
  logic [2:0]  s_snd_id;
  logic [5:0]  s_snd_pitch;
  logic        s_ch_noiz, s_ch_buzz;
  logic [1:0]  s_ch_det, s_ch_rev, s_ch_damp;
  logic [7:0]  s_eff_vol;
  logic [23:0] s_phase, s_phase2;
  logic signed [7:0] s_nz_hold;
  logic [3:0]  s_nz_ph;
  logic signed [12:0] s_brown;
  logic signed [15:0] s_lp;
  // The wavetable's base address in audio RAM, recomputed rather than stored:
  // 256 + id * 68 is two shifts and an add, against 13 bits per slot of state
  // and the mux to read them.
  wire [12:0] s_snd_wtb = 13'd256 + {4'b0, s_snd_id, 6'b0} + {8'b0, s_snd_id, 2'b0};

  // Per-slot filter state: bf_* comes from the played SFX's filter byte at
  // trigger and lives in the sequencer's record; ch_* is that folded together
  // with the instrument's and lives in spar_m.

  logic [NV-1:0] trig_req;
  logic [NV-1:0] clr_tog;   // toggled to ask the synth walk to reset lp/brown

  // Music state
  logic        mus_playing, mus_launch;
  logic [5:0]  mus_pat;
  logic [3:0]  mus_mask;
  logic [7:0]  pb[0:2];
  logic [NV-1:0] launched;
  logic        tch_seen, ptick_seen, f_lb, f_stop;
  // A pattern's length in ticks, fixed when the pattern launches, and the
  // tick position within it. PICO-8 paces a song the same way - the song
  // scheduler records the pattern length and a global pattern-tick position -
  // rather than asking any one voice whether it is still playing.
  logic [12:0] pticks, ptick_tgt;

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
    K_PF0, K_PF1, K_PF2, K_FX,
    I_TR0, I_TR1, I_TR2, I_TR3, I_TR4, I_ADV, I_NL, I_NH, I_LD,
    W_MUS,
    K_ROT, V_LD, V_ST,
    ML_STOP, ML_RD0, ML_RD1, ML_RD2, ML_RD3, ML_LD,
    MS_RD, MS_CK
  } sst_t;
  sst_t sst;

  logic [VW-1:0] c;                  // voice being processed

  // Record addressing. The stride is padded to 16 so the address is a plain
  // concatenation {slot, word} rather than a multiply by 10 in the address
  // path; the six unused words per slot cost nothing, since one SB_RAM40_4K
  // holds 256 words and eight slots need 128 of them either way.
  assign vraddr = {c, vcnt};
  assign vwaddr = {c, vcnt};

  // The parameter record is published on the same cycles as the note record,
  // through a different memory's write port, so it costs no extra states. V_ST
  // is the sequencer's single exit point, which makes the publish atomic: the
  // synthesis walk never sees a note's new pitch against its old waveform.
  assign spar_wa = {c, vcnt};
  // spar_we is driven with vwe, below seq_frozen's declaration.
  always_comb begin
    case (vcnt)
      4'd0:    spar_wd = w_eff_inc[15:0];
      4'd1:    spar_wd = {1'b0, w_snd_id, w_snd_wt, w_snd_wave,
                          w_eff_inc[23:16]};
      4'd2:    spar_wd = {2'b0, w_ch_damp, w_ch_rev, w_ch_det, w_ch_buzz,
                          w_ch_noiz, w_snd_pitch};
      default: spar_wd = {8'b0, w_eff_vol};
    endcase
  end
  // vwe is driven below, once seq_frozen exists - iverilog rejects use before
  // declaration, which is what kept this testbench from building before.
  logic        walk_tick;            // this pass was started by a tick
  logic        tickpend;
  logic [5:0]  scan_p;
  logic [7:0]  note_lo, ins_note_lo;
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
  wire [7:0] e_fcnt   = e_insfx ? w_ins_fcnt : w_fcnt;
  wire [7:0] e_sp     = e_insfx ? w_ins_sp   : w_sp;
  wire [7:0] e_tcnt   = e_insfx ? w_ins_tcnt : w_tcnt;

  // Arpeggio source row: (tick / period) & 3, period from fx and speed
  logic [1:0] arp_idx;
  always_comb begin
    if (e_fx == 3'd6)
      arp_idx = (e_sp <= 8) ? e_tcnt[2:1] : e_tcnt[3:2];
    else
      arp_idx = (e_sp <= 8) ? e_tcnt[3:2] : e_tcnt[4:3];
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
  wire         seq_frozen = syn_rd | replay;
  // A store only advances when the walk does, so a borrowed audio-RAM cycle
  // cannot leave a half-written record behind.
  assign vwe    = (sst == V_ST) && !seq_frozen;
  assign spar_we = (sst == V_ST) && (vcnt < 4'(SPAR)) && !seq_frozen;

  always_ff @(posedge clk) begin
    if (vwe) vmem[vwaddr] <= vwdata;
    // The read must stall with the FSM. V_LD unpacks word vcnt-1 out of vq, so
    // vq has to hold the value addressed on the previous ADVANCING cycle - but
    // the walk freezes whenever the synthesiser borrows the audio-RAM port, and
    // an unconditional read would keep fetching word vcnt during the stall and
    // then unpack it as if it were word vcnt-1. That corrupted one word of the
    // record every time a wavetable voice was sounding, which showed up as an
    // instrument id of 0 - every wavetable playing SFX 0's bytes.
    if (!seq_frozen) vq <= vmem[vraddr];
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
      ML_RD1: sa_pataddr = {5'b0, mus_pat, 2'd1};
      ML_RD2: sa_pataddr = {5'b0, mus_pat, 2'd2};
      ML_RD3: sa_pataddr = {5'b0, mus_pat, 2'd3};
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
  wire [5:0] pat_rows = (w_lps != 0 && seq_q == 0)
                          ? ((w_lps < 8'd32) ? w_lps[5:0] : 6'd32) : 6'd32;

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
  logic [23:0] pinc_q;
  logic [15:0] recip_q;
  logic [23:0] base_r, prev_r, arp_r;
  // Declared here rather than below its first use: iverilog rejects
  // declaration-after-use, which kept rtl/psg_tb.sv from building.
  wire signed [8:0] arp_raw =
      e_insfx ? ($signed({3'b0, w_cur_pitch}) + $signed({3'b0, arp_p}) - 9'sd24)
    : ins_use ? ($signed({3'b0, arp_p}) + $signed({3'b0, w_ins_pitch}) - 9'sd24)
              :  $signed({3'b0, arp_p});
  wire [5:0] e_arp = pclamp(arp_raw);

  always_comb begin
    case (sst)
      K_PF1:   pinc_addr = e_prevp;
      K_PF2:   pinc_addr = e_arp;
      default: pinc_addr = e_pitch;
    endcase
  end
  always_ff @(posedge clk) begin
    pinc_q  <= pinc[pinc_addr];
    recip_q <= recip[e_sp];
  end

  wire [23:0] base_inc = base_r;
  wire [23:0] prev_inc = prev_r;
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
  // 120 times a second - about 240 of the ~29 000 clocks in a tick.
  // ------------------------------------------------------------------
  logic [23:0] m_a;
  logic [32:0] m_p;                  // {accumulator[24:0], multiplier[7:0]}
  logic [3:0]  m_cnt;
  wire  [25:0] m_sum = {1'b0, m_p[32:8]};
  wire  [31:0] m_res = m_p[31:0];
  wire         m_busy = (m_cnt != 0);

  // Effect evaluation micro-sequence: step k captures the product started
  // at k-1 and starts its own (see K_FX).
  logic [2:0]  xs;
  logic [7:0]  u_r, vol_r, pvol_r, fxv_r;
  logic [23:0] fxi_r;

  logic signed [4:0] lfo;
  always_comb begin
    if (e_tcnt[3:0] < 4'd5)       lfo = $signed({1'b0, e_tcnt[3:0]});
    else if (e_tcnt[3:0] < 4'd13) lfo = 5'sd8 - $signed({1'b0, e_tcnt[3:0]});
    else                          lfo = $signed({1'b0, e_tcnt[3:0]}) - 5'sd16;
  end
  wire       lfo_neg = lfo[4];
  wire [3:0] lfo_mag = lfo_neg ? 4'(-lfo) : 4'(lfo);

  // Signed differences are fed in as magnitude plus sign, so the shared
  // unit only ever has to do unsigned work.
  wire signed [24:0] sl_d   = $signed({1'b0, base_inc}) - $signed({1'b0, prev_inc});
  wire               sl_neg = sl_d[24];
  wire [23:0]        sl_mag = sl_neg ? 24'(-sl_d) : 24'(sl_d);
  wire signed [8:0]  vl_d   = $signed({1'b0, vol_r}) - $signed({1'b0, pvol_r});
  wire               vl_neg = vl_d[8];
  wire [7:0]         vl_mag = vl_neg ? 8'(-vl_d) : 8'(vl_d);

  // Step results (fxv_next also feeds the last product's operand)
  wire [23:0] p24 = m_res[31:8];
  wire [7:0]  p8  = m_res[15:8];
  logic [23:0] fxi_next;
  logic [7:0]  fxv_next;

  // Operands for the product started at step xs
  logic [23:0] mul_a;
  logic [7:0]  mul_b;
  always_comb begin
    mul_a = 24'd0;
    mul_b = 8'd0;
    case (xs)
      3'd0: begin mul_a = {8'b0, recip_q};     mul_b = e_fcnt;        end  // u
      3'd1: begin mul_a = 24'd1317;            mul_b = {2'b0, vmul};  end
      3'd2: begin mul_a = 24'd1317;            mul_b = {2'b0, pvmul}; end
      3'd3: case (e_fx)                                       // -> fx_inc
              3'd1: begin mul_a = sl_mag;                    mul_b = u_r; end
              3'd2: begin mul_a = {8'b0, base_inc[23:8]};    mul_b = {4'b0, lfo_mag}; end
              3'd3: begin mul_a = base_inc;                  mul_b = 8'd255 - u_r; end
              default: ;
            endcase
      3'd4: case (e_fx)                                       // -> fx_vol
              3'd1: begin mul_a = {16'b0, vl_mag}; mul_b = u_r; end
              3'd4: begin mul_a = {16'b0, vol_r};  mul_b = u_r; end
              3'd5: begin mul_a = {16'b0, vol_r};  mul_b = 8'd255 - u_r; end
              default: ;
            endcase
      3'd5: begin mul_a = {15'b0, mus_gain} + 24'd1; mul_b = fxv_next; end
      default: ;
    endcase
  end

  always_comb begin
    fxi_next = base_inc;
    case (e_fx)
      3'd1: fxi_next = prev_inc + (sl_neg ? (24'd0 - p24) : p24);
      3'd2: fxi_next = base_inc + (lfo_neg ? (24'd0 - m_res[23:0]) : m_res[23:0]);
      3'd3: fxi_next = p24;
      3'd6, 3'd7: fxi_next = arp_r;
      default: ;
    endcase
    fxv_next = vol_r;
    case (e_fx)
      3'd1: fxv_next = pvol_r + (vl_neg ? (8'd0 - p8) : p8);
      3'd4, 3'd5: fxv_next = p8;
      default: ;
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      sst <= S_IDLE;
      c <= 0;
      walk_tick <= 0;
      tickpend <= 0;
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
      scan_p <= 0;
      note_lo <= 0;
      ins_note_lo <= 0;
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
      // The record itself lives in block RAM and cannot be reset per slot; see
      // the register-file comment for why that is safe. Only the working copy
      // resets, and only so the first visit starts from something defined.
      vcnt <= 0;
      w_fcnt <= 0;
      w_tcnt <= 0;
      w_sp <= 1;
      w_lps <= 0;
      w_lpe <= 0;
      w_cur_pitch <= 0;
      w_prev_pitch <= 0;
      w_cur_wave <= 0;
      w_cur_vol <= 0;
      w_cur_fx <= 0;
      w_prev_vol <= 0;
      w_play_len <= 0;
      w_bf_noiz <= 0;
      w_bf_buzz <= 0;
      w_bf_det <= 0;
      w_bf_rev <= 0;
      w_bf_damp <= 0;
      w_ins_on <= 0;
      w_ins_wt <= 0;
      w_ins_bass <= 0;
      w_ins_done <= 0;
      w_ins_id <= 0;
      w_ins_row <= 0;
      w_ins_fcnt <= 0;
      w_ins_tcnt <= 0;
      w_ins_sp <= 1;
      w_ins_lps <= 0;
      w_ins_lpe <= 0;
      w_ins_pitch <= 6'd24;
      w_ins_prev_pitch <= 6'd24;
      w_ins_wave <= 0;
      w_ins_vol <= 3'd7;
      w_ins_fx <= 0;
      w_ins_prev_vol <= 3'd7;
      w_eff_inc <= 0;
      w_snd_wave <= 0;
      w_snd_wt <= 0;
      w_snd_id <= 0;
      w_snd_pitch <= 0;
      w_ch_noiz <= 0;
      w_ch_buzz <= 0;
      w_ch_det <= 0;
      w_ch_rev <= 0;
      w_ch_damp <= 0;
      w_eff_vol <= 0;
      for (int i = 0; i < 3; i++)
        pb[i] <= 0;
      base_r <= 0;
      prev_r <= 0;
      arp_r <= 0;
      m_a <= 0;
      m_p <= 0;
      m_cnt <= 0;
      xs <= 0;
      u_r <= 0;
      vol_r <= 0;
      pvol_r <= 0;
      fxi_r <= 0;
      fxv_r <= 0;
    end else begin
      // Shared multiplier: shift-add, one iteration per clock. Runs even
      // while the FSM is frozen for a borrowed audio-RAM cycle; K_FX below
      // starts it and only advances when it is idle.
      if (m_cnt != 0) begin
        m_p   <= {m_sum, m_p[7:1]};
        m_cnt <= m_cnt - 1;
      end

      if (!seq_frozen)
      case (sst)
        // One pass over the slots in order, servicing any pending trigger and,
        // when the pass was started by a tick, advancing the row. Each visit is
        // now load / work / store: V_LD streams the slot's record out of the
        // register file into the working copy, the K_/T_/I_ states work on that
        // copy exactly as they did on `name[c]`, and V_ST writes it back.
        S_IDLE: begin
          if (mus_launch) begin
            mus_launch <= 0;
            sst <= ML_STOP;
          end else if (trig_req != 0 || tickpend) begin
            walk_tick <= tickpend;
            tickpend <= 0;
            c <= 0;
            vcnt <= 0;
            sst <= V_LD;
          end
        end

        // ---- record load: word vcnt-1 has landed in vq ----------------
        // The read is synchronous, so the data for the address issued at vcnt
        // arrives at vcnt+1. That one cycle of skew is the whole reason this
        // infers as block RAM instead of the LUT muxes it replaces.
        V_LD: begin
          case (vcnt)
            4'd1: {w_tcnt, w_fcnt} <= vq;
            4'd2: {w_lps, w_sp} <= vq;
            4'd3: {w_ins_wt, w_ins_on, w_play_len, w_lpe} <= vq;
            4'd4: {w_ins_bass, w_cur_wave, w_prev_pitch, w_cur_pitch} <= vq;
            4'd5: {w_ins_done, w_bf_rev, w_bf_det, w_bf_buzz, w_bf_noiz,
                   w_prev_vol, w_cur_fx, w_cur_vol} <= vq;
            4'd6: {w_ins_vol, w_ins_wave, w_ins_row, w_ins_id, w_bf_damp} <= vq;
            4'd7: {w_ins_tcnt, w_ins_fcnt} <= vq;
            4'd8: {w_ins_lps, w_ins_sp} <= vq;
            4'd9: {w_ins_pitch, w_ins_lpe} <= vq[13:0];
            4'd10: {w_ins_prev_vol, w_ins_fx, w_ins_prev_pitch} <= vq[11:0];
            default: ;
          endcase
          if (vcnt == 4'(VREC)) begin
            vcnt <= 0;
            sst <= K_ADV;
          end else
            vcnt <= vcnt + 1;
        end

        // ---- record store: one word per cycle, then on to the next slot ---
        V_ST: begin
          if (vcnt == 4'(VREC - 1)) begin
            vcnt <= 0;
            if (c == VW'(NV-1)) begin
              c <= 0;
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
          // A music slot has no pending parameters, so it starts at row 0 with
          // no length override; only a foreground slot consults the set.
          row[c] <= is_mus(c) ? 5'd0 : trg_row[c[1:0]];
          w_play_len <= is_mus(c) ? 6'd0 : trg_len[c[1:0]];
          w_eff_vol <= 0;                   // do not carry the old note's level
          if (!is_mus(c)) begin
            trg_row[c[1:0]] <= 0;           // parameters are one-shot
            trg_len[c[1:0]] <= 0;
          end
          released[c] <= 0;
          w_fcnt <= 0;
          w_tcnt <= 0;
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
          w_sp <= (seq_q == 0) ? 8'd1 : seq_q;
          // vibrato/arpeggio phase follows the row's place in the record,
          // so a slice started at an offset sounds like the whole record
          w_tcnt <= 8'({3'b0, row[c]} * ((seq_q == 0) ? 8'd1 : seq_q));
          sst <= T_LE;
        end
        T_LE: begin
          w_lps <= seq_q;
          sst <= T_NL;
        end
        T_NL: begin
          w_lpe <= seq_q;
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
              ptick_tgt <= {w_sp, 5'b0};
            end
            if (!tch_seen && !(w_lps < seq_q)) begin
              tch_seen <= 1;
              ptick_tgt <= 13'(w_sp * pat_rows);
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
            sst <= K_ARP;
        end

        // ---- per-tick walk -------------------------------------------
        K_ADV: begin
          if (trig_req[c]) begin
            sst <= T_FL;                    // this channel wants a new SFX
          end else if (!walk_tick || !playing[c]) begin
            if (!playing[c]) w_eff_vol <= 0;
            sst <= K_ROT;
          end else begin
            w_tcnt <= w_tcnt + 1;
            if ({1'b0, w_fcnt} + 9'd1 >= {1'b0, w_sp}) begin
              // row finished: loop, stop, or advance, then refetch
              w_prev_pitch <= w_cur_pitch;
              w_prev_vol <= w_cur_vol;
              w_fcnt <= 0;
              if (w_play_len != 0) begin
                // an explicit length overrides the record's loop points
                if (w_play_len == 6'd1 || row[c] == 5'd31) begin
                  playing[c] <= 0;
                  w_eff_vol <= 0;
                  sst <= K_ROT;
                end else begin
                  w_play_len <= w_play_len - 1;
                  row[c] <= row[c] + 1;
                  sst <= K_NL;
                end
              end else if (w_lps < w_lpe && !released[c] &&
                           {3'b0, row[c]} + 8'd1 >= w_lpe) begin
                row[c] <= w_lps[4:0];
                sst <= K_NL;
              end else if ({3'b0, row[c]} + 8'd1 >=
                           ((w_lps != 0 && w_lpe == 0)
                              ? ((w_lps < 8'd32) ? w_lps : 8'd32)
                              : 8'd32)) begin
                playing[c] <= 0;
                w_eff_vol <= 0;
                sst <= K_ROT;
              end else begin
                row[c] <= row[c] + 1;
                sst <= K_NL;
              end
            end else begin
              w_fcnt <= w_fcnt + 1;
              // the row holds, but the instrument playhead still advances
              sst <= sst_t'((w_ins_on && !w_ins_wt) ? I_ADV : K_ARP);
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
            else
              sst <= sst_t'(w_ins_wt ? K_ARP : I_ADV);
          end else begin
            w_ins_on <= 0;                 // back to the note's own filters
            w_ch_noiz <= w_bf_noiz;
            w_ch_buzz <= w_bf_buzz;
            w_ch_det  <= w_bf_det;
            w_ch_rev  <= w_bf_rev;
            w_ch_damp <= w_bf_damp;
            sst <= K_ARP;
          end
        end

        // ---- custom instrument: retrigger, then per-tick advance -------
        I_TR0: begin
          w_ins_row <= 0;
          w_ins_fcnt <= 0;
          w_ins_tcnt <= 0;
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
          w_ins_sp   <= (seq_q == 0) ? 8'd1 : seq_q;
          w_ins_bass <= seq_q[0];          // wavetable: down an octave
          sst <= I_TR3;
        end
        I_TR3: begin
          w_ins_lps <= seq_q;
          w_ins_wt  <= seq_q[7];           // loop start bit 7 = wavetable
          sst <= I_TR4;
        end
        I_TR4: begin
          w_ins_lpe <= seq_q;
          if (w_ins_wt) begin              // no playhead: the record is PCM
            w_ins_pitch <= 6'd24;
            w_ins_prev_pitch <= 6'd24;
            w_ins_vol <= 3'd7;
            w_ins_prev_vol <= 3'd7;
            w_ins_fx <= 0;
            w_ins_wave <= 0;
            sst <= K_ARP;
          end else
            sst <= I_NL;
        end
        I_ADV: begin
          w_ins_tcnt <= w_ins_tcnt + 1;
          if ({1'b0, w_ins_fcnt} + 9'd1 >= {1'b0, w_ins_sp}) begin
            w_ins_prev_pitch <= w_ins_pitch;
            w_ins_prev_vol <= w_ins_vol;
            w_ins_fcnt <= 0;
            if (w_ins_lps < w_ins_lpe &&
                {3'b0, w_ins_row} + 8'd1 >= w_ins_lpe)
              w_ins_row <= w_ins_lps[4:0];
            else if ({3'b0, w_ins_row} + 8'd1 >=
                     ((w_ins_lps != 0 && w_ins_lpe == 0)
                        ? ((w_ins_lps < 8'd32) ? w_ins_lps : 8'd32)
                        : 8'd32))
              w_ins_done <= 1;             // instrument over: note silent
            else
              w_ins_row <= w_ins_row + 1;
          end else
            w_ins_fcnt <= w_ins_fcnt + 1;
          sst <= I_NL;
        end
        I_NL: sst <= I_NH;
        I_NH: begin
          ins_note_lo <= seq_q;
          sst <= I_LD;
        end
        I_LD: begin
          w_ins_pitch <= ins_note_lo[5:0];
          w_ins_wave  <= {seq_q[0], ins_note_lo[7:6]};
          w_ins_vol   <= seq_q[3:1];
          w_ins_fx    <= seq_q[6:4];
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
        // prefetch the three pitch increments: each state banks what the
        // previous one addressed and issues the next
        K_PF0: sst <= K_PF1;
        K_PF1: begin base_r <= pinc_q; sst <= K_PF2; end
        K_PF2: begin prev_r <= pinc_q; sst <= K_FX;  end
        // Effect evaluation, one product per step on the shared multiplier:
        //   0 row progress u      1 note x instrument volume
        //   2 the same, previous  3 the effect's frequency term
        //   4 the effect's volume term    5 the music fade gain
        // Each step banks the product started by the previous one.
        K_FX: if (!m_busy) begin
          if (xs == 0) arp_r <= pinc_q;
          case (xs)
            3'd1: u_r    <= p8;
            3'd2: vol_r  <= ins_use ? (w_ins_done ? 8'd0 : p8) : vol_direct;
            3'd3: pvol_r <= ins_use ? p8 : pvol_direct;
            3'd4: fxi_r  <= fxi_next;
            3'd5: fxv_r  <= fxv_next;
            default: ;
          endcase
          if (xs == 3'd6) begin
            xs <= 0;
            // a wavetable instrument's bass flag drops it an octave
            w_eff_inc <= (w_ins_on && w_ins_wt && w_ins_bass)
                            ? {1'b0, fxi_r[23:1]} : fxi_r;
            // music slots ride the fade gain
            w_eff_vol <= is_mus(c) ? p8 : fxv_r;
            w_snd_wave <= ins_use ? w_ins_wave
                         : (w_ins_on && w_ins_wt) ? 3'd0 : w_cur_wave;
            w_snd_wt   <= w_ins_on & w_ins_wt;
            // The instrument id, not the record address it expands to: the
            // synthesis side rebuilds 256 + id*68 from three bits.
            w_snd_id    <= w_ins_id;
            w_snd_pitch <= e_pitch;
            sst <= K_ROT;
          end else begin
            m_a   <= mul_a;
            m_p   <= {25'b0, mul_b};
            m_cnt <= 4'd8;
            xs    <= xs + 1;
          end
        end

        // Rotate the ring so the next channel's state is at the head.
        // Four rotations per pass leave it where it started, so channel k
        // is always at index k while the sequencer is idle.
        K_ROT: begin
          // Nothing rotates any more: every slot is named by its index, and the
          // working copy IS the slot being visited. The old ring made a
          // cross-walk read look innocent - the synthesis pipeline reading the
          // sequencer's index 0 got channel 0 whatever voice it was on, which
          // is how the noise gain bug (test 20c) hid.
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
            if (trig_req == 0 && pticks >= ptick_tgt) begin
              if (f_stop) begin
                mus_playing <= 0;
                for (int i = NCH; i < NV; i++) begin
                  playing[i] <= 0;
                          end
              end else if (f_lb) begin
                scan_p <= mus_pat;
                sst <= MS_RD;
              end else if (mus_pat == 6'd63) begin
                mus_playing <= 0;
                for (int i = NCH; i < NV; i++) begin
                  playing[i] <= 0;
                          end
              end else begin
                mus_pat <= mus_pat + 1;
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
          for (int i = NCH; i < NV; i++) begin
            playing[i] <= 0;
              end
          launched <= 0;
          sst <= ML_RD0;
        end
        ML_RD0: sst <= ML_RD1;
        ML_RD1: begin pb[0] <= seq_q; sst <= ML_RD2; end
        ML_RD2: begin pb[1] <= seq_q; sst <= ML_RD3; end
        ML_RD3: begin pb[2] <= seq_q; sst <= ML_LD; end
        ML_LD: begin
          f_lb   <= pb[1][7];
          f_stop <= pb[2][7];
          // Every enabled pattern channel launches, on its MUSIC slot (NCH+c),
          // never on the foreground slot. A sound effect playing on channel c
          // therefore cannot be disturbed by the song, and vice versa: the two
          // states are independent and only the audible selection is shared.
          // $21 stays readable but is now advisory only - with a music slot per
          // channel there is nothing left for software to reserve.
          for (int i = 0; i < 3; i++)
            if (!pb[i][6]) begin
              trig_req[NCH+i] <= 1;
              sfx_id[NCH+i] <= pb[i][5:0];
              launched[NCH+i] <= 1;
            end
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
      if (tick_en) begin
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
                playing[i] <= 0;
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
  // A slot's visit is now 17 cycles: 7 loading its record (six oscillator words
  // plus the read's one cycle of latency, with the three parameter words
  // arriving in parallel out of the other memory), 4 doing the work the old
  // pst 0..3 did, and 6 writing the oscillator state back.
  //
  //   0..6   load        7..10  work (was pst 0..3)      11..16  store
  //
  // Eight slots is 136 clocks against the 159 a sample gives at the simulator's
  // clock, so this fits where a 16-bit-per-cycle stream of the FULL record
  // would not - which is why only the oscillator half is written back and the
  // parameters are read-only here.
  // 0..6 load, 7..9 work, 10..17 the sample x volume iterations (overlapping
  // the 11..16 store, which does not depend on them), 18 fold into the tree.
  localparam int PWORK = 7;
  localparam int PSTOR = 11;
  localparam int PFOLD = 18;
  localparam int PLAST = 18;
  logic [4:0]  pph;
  logic        prun;
  logic signed [7:0] wq, smp_a, smp_b;
  logic [10:0] wrom_addr;
  logic [NV-1:0] clr_ack;              // pairs with the sequencer's clr_tog

  // Record streaming for the synthesis walk. Reads are issued on the load
  // cycles and land one cycle later; the oscillator write-back runs on the
  // store cycles, addressing word pph-PSTOR.
  wire [3:0] s_stw = 4'(pph - 5'(PSTOR));
  assign sosc_ra = {pc_ch, (pph < 5'(SOSC)) ? pph[3:0] : 4'd0};
  assign spar_ra = {pc_ch, (pph < 5'(SPAR)) ? pph[3:0] : 4'd0};
  assign sosc_wa = {pc_ch, s_stw};
  assign sosc_we = prun && (pph >= 5'(PSTOR));
  always_comb begin
    case (s_stw)
      4'd0:    sosc_wd = s_phase[15:0];
      4'd1:    sosc_wd = {s_nz_hold, s_phase[23:16]};
      4'd2:    sosc_wd = s_phase2[15:0];
      4'd3:    sosc_wd = {4'b0, s_nz_ph, s_phase2[23:16]};
      4'd4:    sosc_wd = {3'b0, s_brown};
      default: sosc_wd = s_lp;
    endcase
  end

  wire [2:0] wbank = (s_snd_wave == 3'd7) ? 3'd0 : s_snd_wave;
  always_comb begin
    if (pph == 5'(PWORK + 1))
      wrom_addr = {wbank, s_phase2[23:16]};        // second voice
    else
      wrom_addr = {wbank, s_phase[23:16]};         // main voice
  end
  always_ff @(posedge clk)
    wq <= wrom[wrom_addr];

  // Second voice: phaser preset (~109/110) on wave 7, else the detune ratio
  wire [23:0] einc = s_eff_inc;
  wire [23:0] v2inc =
      // Phaser: the second oscillator runs at 109/110 of the first, which is
      // what produces the beat. 109/110 = 0.9909091; the previous shift pair
      // gave 0.9902344, a 7.4% error in the BEAT rate (4.30 Hz instead of 4.00
      // at A440). Three shifts land on 0.9909668 - 0.6% - for one more adder.
      // Reference: zepto-8 synth.cpp INST_PHASER, via jtothebell/fake-08.
      (s_snd_wave == 3'd7) ? (einc - {7'b0, einc[23:7]}
                                        - {10'b0, einc[23:10]}
                                        - {12'b0, einc[23:12]}) :
      (s_ch_det == 2'd1)   ? (einc + {7'b0, einc[23:7]}) :   // ~+14 cents
      (s_ch_det == 2'd2)   ? {einc[22:0], 1'b0} :            // +1 octave
                                  24'd0;
  wire v2_on = (s_snd_wave == 3'd7) || (s_ch_det != 0);

  // Wavetable instruments read their 64 samples out of audio RAM, one
  // borrowed read per voice per sample (the sequencer FSM freezes for it).
  always_comb begin
    syn_rd   = 1'b0;
    syn_addr = 13'd0;
    if (prun && s_snd_wt && playing[pc_ch]) begin
      if (pph == 5'(PWORK)) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb + {7'b0, s_phase[23:18]};
      end else if (pph == 5'(PWORK + 1) && v2_on) begin
        syn_rd   = 1'b1;
        syn_addr = s_snd_wtb + {7'b0, s_phase2[23:18]};
      end
    end
  end

  // ---- waveform selection (head of the ring = this channel) ----------
  // BUZZ square/pulse: shifted duty straight from the phase counter
  wire [7:0] mph = s_phase[23:16];
  wire signed [7:0] buzzsq =
      (s_snd_wave == 3'd3) ? (mph < 8'd102 ? 8'sd63 : -8'sd63)   // ~40%
                                : (mph < 8'd65  ? 8'sd63 : -8'sd63);  // ~25%
  wire signed [10:0] ph_sum =
      $signed({smp_a[7], smp_a, 1'b0}) + $signed({{3{smp_b[7]}}, smp_b});
  wire signed [18:0] ph_wide = {{8{ph_sum[10]}}, ph_sum};
  wire signed [8:0] det_sum =
      $signed({smp_a[7], smp_a}) + $signed({{2{smp_b[7]}}, smp_b[7:1]});
  wire signed [7:0] det_clip =
      det_sum > 9'sd127 ? 8'sd127 : det_sum < -9'sd127 ? -8'sd127 : det_sum[7:0];

  // nz_hold * nz_gain[key] / 256, saturated. The gain runs 87/256 at the
  // bottom of the range to 222/256 at the top; it used to be a flat 192/256
  // (0.75), which made low-pitched noise about twice as loud as PICO-8's.
  //
  // The gain table is read SYNCHRONOUSLY. As an asynchronous lookup it was a
  // 64-to-1 mux of eight bits built out of logic - measured at 170 LC, on a
  // table small enough that yosys will not spend a block RAM on it either way.
  // A register costs eight flops instead, and it is free of timing risk here:
  // s_snd_pitch is unpacked at pph 3 and held for the rest of the slot's visit,
  // so the value latched here is settled long before pph 9 consumes it.
  logic [7:0] nz_g;
  always_ff @(posedge clk) nz_g <= nz_gain[s_snd_pitch];
  wire signed [15:0] nz_mul = $signed(s_nz_hold) * $signed({1'b0, nz_g});
  wire signed [7:0] nz_scaled =
      (nz_mul >>> 8) > 16'sd127  ?  8'sd127 :
      (nz_mul >>> 8) < -16'sd127 ? -8'sd127 : 8'(nz_mul >>> 8);

  // x * 85 as two adds instead of a multiplier: 85 = 5 * 17, so x*5 = x + 4x
  // and (x*5)*17 = 5x + 80x. Exactly the same product, so the phaser is
  // bit-identical - it just stops asking yosys for an array multiplier.
  wire signed [26:0] ph_w5  = 27'(ph_wide) + 27'(ph_wide <<< 2);
  wire signed [26:0] ph_x85 = ph_w5 + (ph_w5 <<< 4);

  logic signed [7:0] samp;
  always_comb begin
    case (s_snd_wave)
      3'd6: samp = (s_ch_buzz && !s_ch_noiz)
                     ? s_brown[12:5]                               // brown
                     : nz_scaled;
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
  wire signed [15:0] lp_next =
      s_lp + ((samp_q8 - s_lp) >>> s_ch_damp);
  wire signed [7:0] samp_d = (s_ch_damp == 0) ? samp : lp_next[15:8];

  // Sample x volume, back to an 8-iteration shift-add - and this is the third
  // position this multiply has been in, so the reasoning is worth recording.
  //
  // It was serial; task 1.1 made it a single-cycle array multiply to hand back
  // 7 clocks per voice per sample, because the budget then was believed to be
  // the console simulator's 159 clocks. Measured, that multiplier costs 346 LC
  // and nextpnr names it as the critical path (prun -> n_res).
  //
  // The budget was never 159. That is the CONSOLE SIMULATOR's number, not the
  // board's: rtl/clocks.sv gives the PSG 1275 clocks per sample at 28.125 MHz,
  // eight times as many, and the simulator only has fewer because stepping the
  // whole Verilated model faster would cost `make run` its frame rate. Sizing
  // the hardware to the simulator's convenience is backwards.
  //
  // So it is serial again, and the iterations are hidden under the record
  // write-back rather than added to the visit: the store phase does not depend
  // on the product, so the 8 steps run concurrently with it. A visit costs 19
  // clocks instead of 17, which still fits even the simulator's 159 (8 x 19 + 3
  // = 155). The magnitude is multiplied and the sign reapplied, so the product
  // is bit-for-bit what the array multiplier produced.
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
  wire  [7:0]  n_mag = samp_d[7] ? ((samp_d == -8'sd128) ? 8'd127 : 8'(-samp_d))
                                 : 8'(samp_d);
  // The full 16-bit product, not its top byte. Truncating here cost the most
  // resolution anywhere in the chip: a note at PICO-8 volume 1 has eff_vol 36,
  // so (127*36)>>8 = 17 levels - 4.2 bits. Two thirds of NEMO's title music is
  // volume 1 or 2. Keeping the low half makes those 12.2 and 13.2 bits.
  logic [15:0] n_res;
  // {accumulator, multiplier}: one add-and-shift per clock, 8 of them.
  logic [7:0]  nm_a;
  logic [3:0]  nm_cnt;
  wire  [8:0]  nm_sum = {1'b0, n_res[15:8]} + (n_res[0] ? {1'b0, nm_a} : 9'd0);
  wire signed [21:0] n_contrib = mx_neg ? -$signed({6'b0, n_res})
                                        :  $signed({6'b0, n_res});
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
  // Scale: PICO-8's threshold is 24576 against a signed 16-bit sample, and one
  // of our slots at full volume peaks at 32512 - four times the output scale,
  // because the old mixer summed four of them and then shifted right by 2. So
  // the threshold is scaled up by the same 4 and the shift stays at the end.
  // That is not cosmetic: it keeps any mix that never reaches the threshold
  // bit-identical to the old flat sum, so only genuinely loud material - the
  // material that used to hard-clip - changes at all.
  // Every comparison and subtraction here must be SIGNED. A concatenation is
  // unsigned in Verilog however signed its operands are, so writing the
  // threshold as {SA_TH[21], SA_TH} silently makes `sa_s <= -threshold` an
  // unsigned compare - which is true for almost every input, including 0 + 0.
  // That produced a large negative constant out of an idle chip: a steady
  // -9175 in the output with no slot playing at all.
  localparam signed [22:0] SA_TH = 23'sd98304;    // 24576 << 2
  logic signed [21:0] sa_a, sa_b;
  wire  signed [22:0] sa_s = $signed({sa_a[21], sa_a}) + $signed({sa_b[21], sa_b});
  wire         sa_over  = (sa_s >=  SA_TH);
  wire         sa_under = (sa_s <= -SA_TH);
  wire  signed [22:0] sa_exs = sa_over  ? (sa_s - SA_TH)
                             : sa_under ? (-SA_TH - sa_s)
                                        : 23'sd0;
  // The binary's division by five: (excess * 52429) >> 18. The excess is
  // non-negative by construction, so this stays unsigned.
  //
  // Not as a multiply. 52429 factors exactly:
  //
  //     52429 = 4 * 3 * 17 * 257 + 1 = (((3x * 17) * 257) << 2) + x
  //
  // and 17 = 1 + (1<<4), 257 = 1 + (1<<8), 3 = 1 + (1<<1), so the whole product
  // is four adds of shifted copies. The array multiplier yosys built for the
  // literal form measured 529 LC - the largest single item in the chip - and
  // this is the identical product, so the mix stays bit-for-bit the same.
  //
  // 18 bits is enough for the excess, and provably so rather than by margin:
  // a leaf is at most 32512, so level 1 tops out at 65024 - below the 98304
  // threshold, i.e. level 1 never compresses at all. Level 2 reaches 130048 and
  // level 3 reaches 209304, giving a largest-ever excess of 111000, which is 17
  // bits. It was declared 22.
  wire  [17:0] sa_ex   = 18'(sa_exs);
  wire  [19:0] sa_x3   = {sa_ex, 1'b0} + {2'b0, sa_ex};          // 3x
  wire  [23:0] sa_x51  = {sa_x3, 4'b0} + {4'b0, sa_x3};          // 3x * 17
  wire  [31:0] sa_x13k = {sa_x51, 8'b0} + {8'b0, sa_x51};        // 3x * 17 * 257
  // 34 bits, not 32: at the largest reachable excess the product is 5.82e9.
  wire  [33:0] sa_div  = {sa_x13k, 2'b0} + {16'b0, sa_ex};       // *4 + x
  wire  [21:0] sa_q    = 22'(sa_div >> 18);
  wire  signed [21:0] sa_r =
      sa_over  ? ( 22'sd98304 + $signed({1'b0, sa_q[20:0]}))
    : sa_under ? (-22'sd98304 - $signed({1'b0, sa_q[20:0]}))
               : 22'(sa_s);

  logic signed [21:0] sa_hold;        // the even leaf, waiting for its partner
  logic signed [21:0] l1[0:3];        // level-1 results
  logic signed [21:0] l2a, l2b;       // level-2 results
  logic [1:0]  mxs;                   // post-walk reduction step

  logic [1:0]  rev_max;
  // The echo has to outlive the note that asked for it, so the level any
  // playing channel requests is held for a full delay line after the last
  // request rather than dropping with the channel.
  logic [1:0]  rev_lvl;
  logic [9:0]  rev_ttl;
  logic signed [15:0] dry16;
  logic        dry_valid;

  // Level 1 happens inside the walk, levels 2 and 3 after it, all on this one
  // unit - the tree is seven soft_adds spread over time, not seven instances.
  always_comb begin
    case (mxs)
      2'd1:    begin sa_a = l1[0];   sa_b = l1[1];      end
      2'd2:    begin sa_a = l1[2];   sa_b = l1[3];      end
      2'd3:    begin sa_a = l2a;     sa_b = l2b;        end
      default: begin sa_a = sa_hold; sa_b = mix_leaf;   end
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      lfsr <= 15'h2A5F;
      prun <= 0;
      pc_ch <= 0;
      pph <= 0;
      smp_a <= 0;
      smp_b <= 0;
      clr_ack <= 0;
      n_res <= 0;
      nm_a <= 0;
      nm_cnt <= 0;
      mx_neg <= 0;
      mx_play <= 0;
      mx_aud <= 0;
      mx_lp <= 0;
      mx_rev <= 0;
      mx_damp <= 0;
      sa_hold <= 0;
      for (int i = 0; i < 4; i++) l1[i] <= 0;
      l2a <= 0;
      l2b <= 0;
      mxs <= 0;
      rev_max <= 0;
      rev_lvl <= 0;
      rev_ttl <= 0;
      dry16 <= 0;
      dry_valid <= 0;
      // The oscillator state lives in sosc_m and cannot be reset per slot. It
      // does not need to be: a slot's phase only advances while `playing`, and
      // a trigger clears lp/brown through clr_tog, so nothing stale is audible.
      s_phase <= 0;
      s_phase2 <= 0;
      s_nz_hold <= 0;
      s_nz_ph <= 0;
      s_brown <= 0;
      s_lp <= 0;
      s_eff_inc <= 0;
      s_snd_wave <= 0;
      s_snd_wt <= 0;
      s_snd_id <= 0;
      s_snd_pitch <= 0;
      s_ch_noiz <= 0;
      s_ch_buzz <= 0;
      s_ch_det <= 0;
      s_ch_rev <= 0;
      s_ch_damp <= 0;
      s_eff_vol <= 0;
    end else begin
      dry_valid <= 0;

      // Levels 2 and 3 of the tree, one soft_add per cycle on the shared unit.
      // The walk has already left the four level-1 results in l1[].
      case (mxs)
        2'd1: begin l2a <= sa_r; mxs <= 2'd2; end
        2'd2: begin l2b <= sa_r; mxs <= 2'd3; end
        2'd3: begin
          // The >>> 2 the old flat sum applied to the total, kept here so a mix
          // that never reaches the threshold comes out exactly as it used to.
          dry16 <= 16'(sa_r >>> 2);
          dry_valid <= 1;
          mxs <= 2'd0;
          // hold the requested echo level for one delay line past the last
          // request, so a note that ends still gets its own echo back
          if (rev_max != 2'd0) begin
            rev_lvl <= rev_max;
            rev_ttl <= 10'd732;
          end else if (rev_ttl != 0)
            rev_ttl <= rev_ttl - 1;
          else
            rev_lvl <= 0;
        end
        default: ;
      endcase

      if (sample_en) begin
        prun <= 1;
        pc_ch <= 0;
        pph <= 0;
        rev_max <= 0;
      end else if (prun) begin
        // ---- record load: word pph-1 has landed ----------------------
        case (pph)
          5'd1: s_phase[15:0] <= sosc_q;
          5'd2: {s_nz_hold, s_phase[23:16]} <= sosc_q;
          5'd3: s_phase2[15:0] <= sosc_q;
          5'd4: {s_nz_ph, s_phase2[23:16]} <= sosc_q[11:0];
          5'd5: s_brown <= sosc_q[12:0];
          5'd6: s_lp <= sosc_q;
          default: ;
        endcase
        case (pph)
          5'd1: s_eff_inc[15:0] <= spar_q;
          5'd2: {s_snd_id, s_snd_wt, s_snd_wave, s_eff_inc[23:16]} <= spar_q[14:0];
          5'd3: {s_ch_damp, s_ch_rev, s_ch_det, s_ch_buzz, s_ch_noiz,
                 s_snd_pitch} <= spar_q[13:0];
          5'd4: s_eff_vol <= spar_q[7:0];
          default: ;
        endcase

        // Sample x volume, one add-and-shift per clock. Runs underneath the
        // record write-back, so it costs the visit nothing but the two clocks
        // that PLAST was extended by.
        if (nm_cnt != 0) begin
          n_res  <= {nm_sum, n_res[7:1]};
          nm_cnt <= nm_cnt - 1;
        end

        if (pph == 5'(PLAST)) begin
          pph <= 0;
          if (pc_ch == VW'(NV-1)) begin
            prun <= 0;
            mxs <= 2'd1;                 // start the tree's levels 2 and 3
          end
          pc_ch <= pc_ch + 1;
        end else
          pph <= pph + 1;

        case (pph)
          5'(PWORK): begin               // advance phase(s), issue main read
            // One step per voice per sample. This used to free-run on the
            // system clock, which tied the noise sequence to how many clocks
            // the per-voice pipeline happened to take - so shortening the
            // sample x volume multiply, or changing the number of voices,
            // silently changed what the noise sounded like. Stepping it here
            // gives every voice a fresh value every sample and makes the
            // noise independent of the pipeline's timing.
            lfsr <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};
            if (playing[pc_ch]) begin
              s_phase <= s_phase + einc;
              if (v2_on)
                s_phase2 <= s_phase2 + v2inc;
              // noise: white every sample when NOIZ, else pitched S&H
              if (s_ch_noiz || s_phase[23:20] != s_nz_ph) begin
                s_nz_ph <= s_phase[23:20];
                s_nz_hold <= $signed(lfsr[7:0]);
              end
              // brown integrator (leaky low-pass of white) for BUZZ noise
              s_brown <= s_brown
                            - {{5{s_brown[12]}}, s_brown[12:5]}
                            + $signed({{5{lfsr[7]}}, lfsr[7:0]});
            end
            // a trigger asked for this channel's filter state to be reset
            if (clr_tog[pc_ch] != clr_ack[pc_ch]) begin
              clr_ack[pc_ch] <= clr_tog[pc_ch];
              s_lp <= 0;
              s_brown <= 0;
            end
          end
          5'(PWORK + 1): begin           // main-voice sample
            smp_a <= s_snd_wt ? $signed(seq_q) : wq;
          end
          5'(PWORK + 2): begin           // second voice, then start x volume
            smp_b <= s_snd_wt ? $signed(seq_q) : wq;
            // Load the shift-add unit: accumulator clear, multiplier in the low
            // half. The 8 iterations below run while the record is written back.
            nm_a   <= n_mag;
            n_res  <= {8'b0, s_eff_vol};
            nm_cnt <= 4'd8;
            mx_neg  <= samp_d[7];
            mx_play <= playing[pc_ch];
            // Audible unless this is a music slot whose channel currently has a
            // foreground effect running.
            mx_aud  <= playing[pc_ch]
                       & ~(is_mus(pc_ch) & playing[{1'b0, pc_ch[1:0]}]);
            mx_lp   <= lp_next;
            mx_rev  <= s_ch_rev;
            mx_damp <= s_ch_damp;
          end
          5'(PFOLD): begin               // fold into the tree
            // Level 1: hold the even slot's leaf, combine it with the odd one.
            // mix_leaf is zero for a slot that is running but suppressed, which
            // is deliberate - the tree's zero leaves are part of the function.
            if (pc_ch[0] == 1'b0)
              sa_hold <= mix_leaf;
            else
              l1[pc_ch[2:1]] <= sa_r;
            if (mx_aud && mx_rev > rev_max) rev_max <= mx_rev;
            // the dampen state is the only thing this stage writes back, and it
            // is written for every RUNNING slot, audible or not
            if (mx_play && mx_damp != 0) s_lp <= mx_lp;
          end
          default: ;
        endcase
      end
    end
  end

  // Output stage: direct, or a shared feed-forward reverb echo (2/4-tick
  // delay at the strongest level any active channel requested)
  generate
  if (REVERB) begin : g_reverb
    logic signed [7:0] revbuf[0:731];
    logic [9:0] widx, ridx;
    logic signed [7:0] rev_q, dry_l;
    logic [1:0] rst, rlvl_l;
    logic signed [9:0] rev_outv;
    wire [9:0] dlen = (rev_lvl == 2'd1) ? 10'd366 :
                      (rev_lvl == 2'd2) ? 10'd732 : 10'd0;
    always_ff @(posedge clk)
      rev_q <= revbuf[ridx];
    always_ff @(posedge clk) begin
      if (reset) begin
        widx <= 0; ridx <= 0; rst <= 0; pcm <= 16'sd0;
        dry_l <= 0; rlvl_l <= 0;
      end else begin
        case (rst)
          2'd0: if (dry_valid) begin
            dry_l <= 8'(dry16 >>> 8);   // the echo tap stays 8-bit
            rlvl_l <= rev_lvl;
            ridx <= (dlen == 0) ? widx :
                    (widx >= dlen) ? widx - dlen : widx + 10'd732 - dlen;
            rst <= 2'd1;
          end
          2'd1: rst <= 2'd2;                     // revbuf read settles
          2'd2: begin
            rev_outv = (rlvl_l == 2'd0) ? 10'sd0
                         : $signed({{3{rev_q[7]}}, rev_q[7:1]});
            pcm <= 16'(dry16 + $signed({rev_outv, 8'b0}));
            revbuf[widx] <= dry_l;
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
