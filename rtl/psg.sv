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
  logic        playing[0:3], music_owned[0:3];
  logic [5:0]  sfx_id[0:3];
  logic [4:0]  row[0:3];
  logic [7:0]  fcnt[0:3];            // ticks into the current row
  logic [7:0]  tcnt[0:3];            // ticks into the record (vibrato/arp)
  logic [7:0]  sp[0:3], lps[0:3], lpe[0:3];
  logic [5:0]  cur_pitch[0:3], prev_pitch[0:3];
  logic [2:0]  cur_wave[0:3], cur_vol[0:3], cur_fx[0:3], prev_vol[0:3];
  logic [23:0] eff_inc[0:3];
  logic [7:0]  eff_vol[0:3];
  logic [23:0] phase[0:3], phase2[0:3];
  logic signed [7:0] nz_hold[0:3];
  logic [3:0]  nz_ph[0:3];

  // Trigger parameters latched for the next trigger on a channel, and the
  // resulting play limits (sfx(n, ch, offset, length) / release from loop)
  logic [4:0]  trg_row[0:3];
  // Borrowed-music restore. PICO-8 lets an SFX take a channel the music is
  // using: the displaced music SFX is remembered and relaunched when the SFX
  // ends (zepto-8 / fake-08 Audio.cpp store it as `sfx_music`). Without this a
  // cart's own channel mask is not enough - see docs/hardware-gaps.md - and a
  // game has to reserve every channel its patterns touch.
  logic [5:0]  sav_sfx[0:3];
  logic [4:0]  sav_row[0:3];
  logic [3:0]  sav_valid;
  logic [5:0]  trg_len[0:3], play_len[0:3];
  logic        released[0:3];

  // Custom-instrument playhead: SFX 0-7 running underneath the note
  logic        ins_on[0:3], ins_wt[0:3], ins_bass[0:3], ins_done[0:3];
  logic [2:0]  ins_id[0:3];
  logic [4:0]  ins_row[0:3];
  logic [7:0]  ins_fcnt[0:3], ins_tcnt[0:3];
  logic [7:0]  ins_sp[0:3], ins_lps[0:3], ins_lpe[0:3];
  logic [5:0]  ins_pitch[0:3], ins_prev_pitch[0:3];
  logic [2:0]  ins_wave[0:3], ins_vol[0:3], ins_fx[0:3], ins_prev_vol[0:3];

  // What the synthesis datapath sounds: the note's waveform, or the
  // instrument's, or a wavetable at snd_wtb (audio RAM record base)
  logic [2:0]  snd_wave[0:3];
  logic        snd_wt[0:3];
  logic [12:0] snd_wtb[0:3];
  // The pitch the noise gain is looked up by, latched per channel alongside
  // the other synthesis-path values. It cannot be read from the sequencer's
  // ring: that ring only advances on ticks, so during synthesis it holds
  // channel 0's note whatever channel is being synthesised, and every channel
  // was getting channel 0's noise gain (test 20c).
  logic [5:0]  snd_pitch[0:3];

  // Per-channel filter state: bf_* comes from the played SFX's filter byte
  // at trigger, ch_* is that folded together with the instrument's
  logic        bf_noiz[0:3], bf_buzz[0:3];
  logic [1:0]  bf_det[0:3], bf_rev[0:3], bf_damp[0:3];
  logic        ch_noiz[0:3], ch_buzz[0:3];
  logic [1:0]  ch_det[0:3], ch_rev[0:3], ch_damp[0:3];
  logic signed [15:0] lp[0:3];     // dampen one-pole state, Q8
  logic signed [12:0] brown[0:3];  // brown-noise integrator

  logic [3:0]  trig_req;
  logic [3:0]  clr_tog;   // toggled to ask the synth walk to reset lp/brown

  // Music state
  logic        mus_playing, mus_launch;
  logic [5:0]  mus_pat;
  logic [3:0]  mus_mask;
  logic [7:0]  pb[0:2];
  logic [3:0]  launched;
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
    K_ROT,
    ML_STOP, ML_RD0, ML_RD1, ML_RD2, ML_RD3, ML_LD,
    MS_RD, MS_CK
  } sst_t;
  sst_t sst;

  logic [1:0]  c;                    // channel being processed
  logic        walk_tick;            // this pass was started by a tick
  logic        tickpend;
  logic [5:0]  scan_p;
  logic [7:0]  note_lo, ins_note_lo;
  logic [5:0]  arp_p;

  wire [12:0] ch_base  = 13'd256 + {1'b0, sfx_id[c], 6'b0} + {5'b0, sfx_id[c], 2'b0};
  wire [12:0] ins_base = 13'd256 + {4'b0, ins_id[c], 6'b0} + {8'b0, ins_id[c], 2'b0};

  // The note's instrument voice: a playhead (ins_use) or a wavetable
  wire ins_use = ins_on[c] & ~ins_wt[c];

  // Effect 3 on a custom-instrument note means "retrigger", not "drop"; the
  // instrument's own effect is used when the note carries none of its own.
  wire [2:0] nfx      = (ins_on[c] && cur_fx[c] == 3'd3) ? 3'd0 : cur_fx[c];
  wire       e_insfx  = ins_use && nfx == 3'd0 && ins_fx[c] != 3'd0;
  wire [2:0] e_fx     = e_insfx ? ins_fx[c]   : nfx;
  wire [7:0] e_fcnt   = e_insfx ? ins_fcnt[c] : fcnt[c];
  wire [7:0] e_sp     = e_insfx ? ins_sp[c]   : sp[c];
  wire [7:0] e_tcnt   = e_insfx ? ins_tcnt[c] : tcnt[c];

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
  logic [12:0] seq_addr, last_addr;
  logic [7:0]  seq_q;
  logic        syn_rd, replay;
  logic [12:0] syn_addr;
  wire         seq_frozen = syn_rd | replay;
  wire  [12:0] aram_addr  = syn_rd ? syn_addr : replay ? last_addr : seq_addr;

  always_comb begin
    seq_addr = 13'd0;
    case (sst)
      T_FL:   seq_addr = ch_base + 13'd64;
      T_SP:   seq_addr = ch_base + 13'd65;
      T_LS:   seq_addr = ch_base + 13'd66;
      T_LE:   seq_addr = ch_base + 13'd67;
      T_NL,
      K_NL:   seq_addr = ch_base + {7'b0, row[c], 1'b0};
      T_NH,
      K_NH:   seq_addr = ch_base + {7'b0, row[c], 1'b1};
      K_ARP:  seq_addr = e_insfx ? ins_base + {7'b0, ins_row[c][4:2], arp_idx, 1'b0}
                                 : ch_base  + {7'b0, row[c][4:2],     arp_idx, 1'b0};
      I_TR0:  seq_addr = ins_base + 13'd64;
      I_TR1:  seq_addr = ins_base + 13'd65;
      I_TR2:  seq_addr = ins_base + 13'd66;
      I_TR3:  seq_addr = ins_base + 13'd67;
      I_NL:   seq_addr = ins_base + {7'b0, ins_row[c], 1'b0};
      I_NH:   seq_addr = ins_base + {7'b0, ins_row[c], 1'b1};
      ML_RD0: seq_addr = {5'b0, mus_pat, 2'd0};
      ML_RD1: seq_addr = {5'b0, mus_pat, 2'd1};
      ML_RD2: seq_addr = {5'b0, mus_pat, 2'd2};
      ML_RD3: seq_addr = {5'b0, mus_pat, 2'd3};
      MS_RD:  seq_addr = {5'b0, scan_p, 2'd0};
      default: ;
    endcase
  end
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
  // Rows an SFX record plays before it ends, valid in T_NL where lps[c] holds
  // the loop start and seq_q the loop end. Mirrors the end-of-record rule the
  // per-tick walk applies, so a pattern's tick length matches the sound that
  // paces it.
  wire [5:0] pat_rows = (lps[c] != 0 && seq_q == 0)
                          ? ((lps[c] < 8'd32) ? lps[c][5:0] : 6'd32) : 6'd32;

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

  wire signed [8:0] pc_raw = $signed({3'b0, cur_pitch[c]})
                           + $signed({3'b0, ins_pitch[c]}) - 9'sd24;
  wire signed [8:0] pp_raw = $signed({3'b0, prev_pitch[c]})
                           + $signed({3'b0, ins_prev_pitch[c]}) - 9'sd24;
  wire [5:0] e_pitch = ins_use ? pclamp(pc_raw) : cur_pitch[c];
  wire [5:0] e_prevp = ins_use ? pclamp(pp_raw) : prev_pitch[c];

  wire [5:0] vmul  = 6'(cur_vol[c]  * ins_vol[c]);
  wire [5:0] pvmul = 6'(prev_vol[c] * ins_prev_vol[c]);

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
      e_insfx ? ($signed({3'b0, cur_pitch[c]}) + $signed({3'b0, arp_p}) - 9'sd24)
    : ins_use ? ($signed({3'b0, arp_p}) + $signed({3'b0, ins_pitch[c]}) - 9'sd24)
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
  wire [7:0]  vol_direct  = ins_done[c] ? 8'd0
                          : {cur_vol[c], 5'b0} + {3'b0, cur_vol[c], 2'b0};
  wire [7:0]  pvol_direct = {prev_vol[c], 5'b0} + {3'b0, prev_vol[c], 2'b0};

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
  wire  [25:0] m_sum = {1'b0, m_p[32:8]} + (m_p[0] ? {2'b0, m_a} : 26'd0);
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
      sav_valid <= 0;
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
      for (int i = 0; i < 4; i++) begin
        playing[i] <= 0;
        music_owned[i] <= 0;
        sfx_id[i] <= 0;
        row[i] <= 0;
        fcnt[i] <= 0;
        tcnt[i] <= 0;
        sp[i] <= 1;
        lps[i] <= 0;
        lpe[i] <= 0;
        cur_pitch[i] <= 0;
        prev_pitch[i] <= 0;
        cur_wave[i] <= 0;
        cur_vol[i] <= 0;
        cur_fx[i] <= 0;
        prev_vol[i] <= 0;
        eff_inc[i] <= 0;
        eff_vol[i] <= 0;
        trg_row[i] <= 0;
        sav_sfx[i] <= 0;
        sav_row[i] <= 0;
        trg_len[i] <= 0;
        play_len[i] <= 0;
        released[i] <= 0;
        ins_on[i] <= 0;
        ins_wt[i] <= 0;
        ins_bass[i] <= 0;
        ins_done[i] <= 0;
        ins_id[i] <= 0;
        ins_row[i] <= 0;
        ins_fcnt[i] <= 0;
        ins_tcnt[i] <= 0;
        ins_sp[i] <= 1;
        ins_lps[i] <= 0;
        ins_lpe[i] <= 0;
        ins_pitch[i] <= 6'd24;
        ins_prev_pitch[i] <= 6'd24;
        ins_wave[i] <= 0;
        ins_vol[i] <= 3'd7;
        ins_fx[i] <= 0;
        ins_prev_vol[i] <= 3'd7;
        snd_wave[i] <= 0;
        snd_wt[i] <= 0;
        snd_wtb[i] <= 0;
        snd_pitch[i] <= 0;
        bf_noiz[i] <= 0;
        bf_buzz[i] <= 0;
        bf_det[i] <= 0;
        bf_rev[i] <= 0;
        bf_damp[i] <= 0;
        ch_noiz[i] <= 0;
        ch_buzz[i] <= 0;
        ch_det[i] <= 0;
        ch_rev[i] <= 0;
        ch_damp[i] <= 0;
      end
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
        // Channel state lives in a ring whose head is the channel being
        // processed, so every visit has to go through the walk in order:
        // one pass over channels 0..3, servicing any pending trigger and,
        // when the pass was started by a tick, advancing the row.
        S_IDLE: begin
          if (mus_launch) begin
            mus_launch <= 0;
            sst <= ML_STOP;
          end else if (trig_req != 0 || tickpend) begin
            walk_tick <= tickpend;
            tickpend <= 0;
            c <= 0;
            sst <= K_ADV;
          end
        end

        // ---- trigger: filter byte, metadata, then the first note ------
        T_FL: begin
          trig_req[c] <= 0;
          row[c] <= trg_row[c];             // sfx(n, ch, offset, length)
          play_len[c] <= trg_len[c];
          trg_row[c] <= 0;                  // parameters are one-shot
          trg_len[c] <= 0;
          released[c] <= 0;
          fcnt[c] <= 0;
          tcnt[c] <= 0;
          prev_pitch[c] <= 6'd24;
          prev_vol[c] <= 0;
          playing[c] <= 1;
          ins_on[c] <= 0;
          ins_done[c] <= 0;
          clr_tog[c] <= ~clr_tog[c];        // synth walk clears lp/brown
          sst <= T_SP;
        end
        T_SP: begin
          bf_noiz[c] <= seq_q[1];
          bf_buzz[c] <= seq_q[2];
          bf_det[c]  <= f_det;
          bf_rev[c]  <= f_rev;
          bf_damp[c] <= f_damp;
          ch_noiz[c] <= seq_q[1];
          ch_buzz[c] <= seq_q[2];
          ch_det[c]  <= f_det;
          ch_rev[c]  <= f_rev;
          ch_damp[c] <= f_damp;
          sst <= T_LS;
        end
        T_LS: begin
          sp[c] <= (seq_q == 0) ? 8'd1 : seq_q;
          // vibrato/arpeggio phase follows the row's place in the record,
          // so a slice started at an offset sounds like the whole record
          tcnt[c] <= 8'({3'b0, row[c]} * ((seq_q == 0) ? 8'd1 : seq_q));
          sst <= T_LE;
        end
        T_LE: begin
          lps[c] <= seq_q;
          sst <= T_NL;
        end
        T_NL: begin
          lpe[c] <= seq_q;
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
              ptick_tgt <= {sp[c], 5'b0};
            end
            if (!tch_seen && !(lps[c] < seq_q)) begin
              tch_seen <= 1;
              ptick_tgt <= 13'(sp[c] * pat_rows);
            end
          end
          sst <= T_NH;
        end
        T_NH: begin
          note_lo <= seq_q;
          sst <= T_LD;
        end
        T_LD: begin
          cur_pitch[c] <= note_lo[5:0];
          cur_wave[c]  <= {seq_q[0], note_lo[7:6]};
          cur_vol[c]   <= seq_q[3:1];
          cur_fx[c]    <= seq_q[6:4];
          if (seq_q[7]) begin               // custom instrument: always new
            ins_on[c] <= 1;
            ins_id[c] <= {seq_q[0], note_lo[7:6]};
            sst <= I_TR0;
          end else
            sst <= K_ARP;
        end

        // ---- per-tick walk -------------------------------------------
        K_ADV: begin
          if (trig_req[c]) begin
            sst <= T_FL;                    // this channel wants a new SFX
          end else if (!walk_tick || !playing[c]) begin
            if (!playing[c]) eff_vol[c] <= 0;
            sst <= K_ROT;
          end else begin
            tcnt[c] <= tcnt[c] + 1;
            if ({1'b0, fcnt[c]} + 9'd1 >= {1'b0, sp[c]}) begin
              // row finished: loop, stop, or advance, then refetch
              prev_pitch[c] <= cur_pitch[c];
              prev_vol[c] <= cur_vol[c];
              fcnt[c] <= 0;
              if (play_len[c] != 0) begin
                // an explicit length overrides the record's loop points
                if (play_len[c] == 6'd1 || row[c] == 5'd31) begin
                  if (sav_valid[c]) begin
                    sfx_id[c] <= sav_sfx[c];
                    trg_row[c] <= sav_row[c];
                    trig_req[c] <= 1;
                    music_owned[c] <= 1;
                    launched[c] <= 1;
                    sav_valid[c] <= 0;
                  end else begin
                    playing[c] <= 0;
                    eff_vol[c] <= 0;
                  end
                  sst <= K_ROT;
                end else begin
                  play_len[c] <= play_len[c] - 1;
                  row[c] <= row[c] + 1;
                  sst <= K_NL;
                end
              end else if (lps[c] < lpe[c] && !released[c] &&
                           {3'b0, row[c]} + 8'd1 >= lpe[c]) begin
                row[c] <= lps[c][4:0];
                sst <= K_NL;
              end else if ({3'b0, row[c]} + 8'd1 >=
                           ((lps[c] != 0 && lpe[c] == 0)
                              ? ((lps[c] < 8'd32) ? lps[c] : 8'd32)
                              : 8'd32)) begin
                if (sav_valid[c]) begin
                  sfx_id[c] <= sav_sfx[c];
                  trg_row[c] <= sav_row[c];
                  trig_req[c] <= 1;
                  music_owned[c] <= 1;
                  launched[c] <= 1;
                  sav_valid[c] <= 0;
                end else begin
                  playing[c] <= 0;
                  eff_vol[c] <= 0;
                end
                sst <= K_ROT;
              end else begin
                row[c] <= row[c] + 1;
                sst <= K_NL;
              end
            end else begin
              fcnt[c] <= fcnt[c] + 1;
              // the row holds, but the instrument playhead still advances
              sst <= sst_t'((ins_on[c] && !ins_wt[c]) ? I_ADV : K_ARP);
            end
          end
        end
        K_NL: sst <= K_NH;                  // note lo lands next cycle
        K_NH: begin
          note_lo <= seq_q;
          sst <= K_LD;
        end
        K_LD: begin
          cur_pitch[c] <= note_lo[5:0];
          cur_wave[c]  <= {seq_q[0], note_lo[7:6]};
          cur_vol[c]   <= seq_q[3:1];
          cur_fx[c]    <= seq_q[6:4];
          if (seq_q[7]) begin
            ins_on[c] <= 1;
            ins_id[c] <= {seq_q[0], note_lo[7:6]};
            // retrigger on a pitch change, after a silent note, on a new
            // instrument, or when the note asks for it with effect 3
            if (!ins_on[c] || ins_id[c] != {seq_q[0], note_lo[7:6]} ||
                note_lo[5:0] != prev_pitch[c] || prev_vol[c] == 0 ||
                seq_q[6:4] == 3'd3)
              sst <= I_TR0;
            else
              sst <= sst_t'(ins_wt[c] ? K_ARP : I_ADV);
          end else begin
            ins_on[c] <= 0;                 // back to the note's own filters
            ch_noiz[c] <= bf_noiz[c];
            ch_buzz[c] <= bf_buzz[c];
            ch_det[c]  <= bf_det[c];
            ch_rev[c]  <= bf_rev[c];
            ch_damp[c] <= bf_damp[c];
            sst <= K_ARP;
          end
        end

        // ---- custom instrument: retrigger, then per-tick advance -------
        I_TR0: begin
          ins_row[c] <= 0;
          ins_fcnt[c] <= 0;
          ins_tcnt[c] <= 0;
          ins_done[c] <= 0;
          ins_prev_pitch[c] <= 6'd24;
          ins_prev_vol[c] <= 0;
          sst <= I_TR1;
        end
        I_TR1: begin                        // the instrument's filters join
          ch_noiz[c] <= bf_noiz[c] | seq_q[1];
          ch_buzz[c] <= bf_buzz[c] | seq_q[2];
          ch_det[c]  <= (f_det  > bf_det[c])  ? f_det  : bf_det[c];
          ch_rev[c]  <= (f_rev  > bf_rev[c])  ? f_rev  : bf_rev[c];
          ch_damp[c] <= (f_damp > bf_damp[c]) ? f_damp : bf_damp[c];
          sst <= I_TR2;
        end
        I_TR2: begin
          ins_sp[c]   <= (seq_q == 0) ? 8'd1 : seq_q;
          ins_bass[c] <= seq_q[0];          // wavetable: down an octave
          sst <= I_TR3;
        end
        I_TR3: begin
          ins_lps[c] <= seq_q;
          ins_wt[c]  <= seq_q[7];           // loop start bit 7 = wavetable
          sst <= I_TR4;
        end
        I_TR4: begin
          ins_lpe[c] <= seq_q;
          if (ins_wt[c]) begin              // no playhead: the record is PCM
            ins_pitch[c] <= 6'd24;
            ins_prev_pitch[c] <= 6'd24;
            ins_vol[c] <= 3'd7;
            ins_prev_vol[c] <= 3'd7;
            ins_fx[c] <= 0;
            ins_wave[c] <= 0;
            sst <= K_ARP;
          end else
            sst <= I_NL;
        end
        I_ADV: begin
          ins_tcnt[c] <= ins_tcnt[c] + 1;
          if ({1'b0, ins_fcnt[c]} + 9'd1 >= {1'b0, ins_sp[c]}) begin
            ins_prev_pitch[c] <= ins_pitch[c];
            ins_prev_vol[c] <= ins_vol[c];
            ins_fcnt[c] <= 0;
            if (ins_lps[c] < ins_lpe[c] &&
                {3'b0, ins_row[c]} + 8'd1 >= ins_lpe[c])
              ins_row[c] <= ins_lps[c][4:0];
            else if ({3'b0, ins_row[c]} + 8'd1 >=
                     ((ins_lps[c] != 0 && ins_lpe[c] == 0)
                        ? ((ins_lps[c] < 8'd32) ? ins_lps[c] : 8'd32)
                        : 8'd32))
              ins_done[c] <= 1;             // instrument over: note silent
            else
              ins_row[c] <= ins_row[c] + 1;
          end else
            ins_fcnt[c] <= ins_fcnt[c] + 1;
          sst <= I_NL;
        end
        I_NL: sst <= I_NH;
        I_NH: begin
          ins_note_lo <= seq_q;
          sst <= I_LD;
        end
        I_LD: begin
          ins_pitch[c] <= ins_note_lo[5:0];
          ins_wave[c]  <= {seq_q[0], ins_note_lo[7:6]};
          ins_vol[c]   <= seq_q[3:1];
          ins_fx[c]    <= seq_q[6:4];
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
            3'd2: vol_r  <= ins_use ? (ins_done[c] ? 8'd0 : p8) : vol_direct;
            3'd3: pvol_r <= ins_use ? p8 : pvol_direct;
            3'd4: fxi_r  <= fxi_next;
            3'd5: fxv_r  <= fxv_next;
            default: ;
          endcase
          if (xs == 3'd6) begin
            xs <= 0;
            // a wavetable instrument's bass flag drops it an octave
            eff_inc[c] <= (ins_on[c] && ins_wt[c] && ins_bass[c])
                            ? {1'b0, fxi_r[23:1]} : fxi_r;
            // music channels ride the fade gain
            eff_vol[c] <= music_owned[c] ? p8 : fxv_r;
            snd_wave[c] <= ins_use ? ins_wave[c]
                         : (ins_on[c] && ins_wt[c]) ? 3'd0 : cur_wave[c];
            snd_wt[c]   <= ins_on[c] & ins_wt[c];
            snd_wtb[c]  <= ins_base;
            snd_pitch[c] <= e_pitch;
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
          // Nothing rotates any more: every voice is named by its index. The
          // ring made a cross-walk read look innocent - the synthesis pipeline
          // reading the sequencer's index 0 got channel 0 whatever voice it
          // was on, which is how the noise gain bug (test 20c) hid.
          if (c == 2'd3) begin
            c <= 0;
            sst <= W_MUS;
          end else begin
            c <= c + 1;
            sst <= K_ADV;
          end
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
                for (int i = 0; i < 4; i++)
                  if (music_owned[i]) begin
                    playing[i] <= 0;
                    eff_vol[i] <= 0;
                    music_owned[i] <= 0;
                  end
              end else if (f_lb) begin
                scan_p <= mus_pat;
                sst <= MS_RD;
              end else if (mus_pat == 6'd63) begin
                mus_playing <= 0;
                for (int i = 0; i < 4; i++)
                  if (music_owned[i]) begin
                    playing[i] <= 0;
                    eff_vol[i] <= 0;
                    music_owned[i] <= 0;
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
          for (int i = 0; i < 4; i++) begin
            if (music_owned[i]) begin
              playing[i] <= 0;
              eff_vol[i] <= 0;
              music_owned[i] <= 0;
            end
            sav_valid[i] <= 0;      // a new pattern makes any saved SFX stale
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
          // every enabled pattern channel launches; $21 only records which
          // channels are reserved for music, for the CPU to consult
          for (int i = 0; i < 3; i++)
            if (!pb[i][6]) begin
              trig_req[i] <= 1;
              sfx_id[i] <= pb[i][5:0];
              music_owned[i] <= 1;
              launched[i] <= 1;
            end
          if (!seq_q[6]) begin
            trig_req[3] <= 1;
            sfx_id[3] <= seq_q[5:0];
            music_owned[3] <= 1;
            launched[3] <= 1;
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
              for (int i = 0; i < 4; i++)
                if (music_owned[i]) begin
                  playing[i] <= 0;
                  eff_vol[i] <= 0;
                  music_owned[i] <= 0;
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
          2'd0:                              // $10-$13: trigger / stop
            if (di == 8'h81)
              released[addr[1:0]] <= 1;      // sfx(-2): finish, don't loop
            else if (di[7]) begin
              playing[addr[1:0]] <= 0;
              eff_vol[addr[1:0]] <= 0;
              music_owned[addr[1:0]] <= 0;
              launched[addr[1:0]] <= 0;
              trig_req[addr[1:0]] <= 0;
              sav_valid[addr[1:0]] <= 0;    // an explicit stop forgets it
            end else begin
              // Taking a music channel: remember the SFX and the row it was on
              // so it can be put back when this sound finishes. A launch that
              // has not been serviced yet has not reached its start row, so
              // the row to come back to is the pending trigger's, not the one
              // left over from the pattern before.
              if (music_owned[addr[1:0]]) begin
                sav_sfx[addr[1:0]] <= sfx_id[addr[1:0]];
                sav_row[addr[1:0]] <= trig_req[addr[1:0]]
                                        ? trg_row[addr[1:0]] : row[addr[1:0]];
                sav_valid[addr[1:0]] <= 1;
              end
              trig_req[addr[1:0]] <= 1;
              sfx_id[addr[1:0]] <= di[5:0];
              music_owned[addr[1:0]] <= 0;
              launched[addr[1:0]] <= 0;     // a sound cannot pace the pattern
              eff_vol[addr[1:0]] <= 0;
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
            for (int i = 0; i < 4; i++)
              if (music_owned[i]) begin
                playing[i] <= 0;
                eff_vol[i] <= 0;
                music_owned[i] <= 0;
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
  logic [1:0]  pc_ch, pst;
  logic        prun;
  logic signed [7:0] wq, smp_a, smp_b;
  logic [10:0] wrom_addr;
  logic [3:0]  clr_ack;              // pairs with the sequencer's clr_tog

  wire [2:0] wbank = (snd_wave[pc_ch] == 3'd7) ? 3'd0 : snd_wave[pc_ch];
  always_comb begin
    if (pst == 2'd1)
      wrom_addr = {wbank, phase2[pc_ch][23:16]};        // second voice
    else
      wrom_addr = {wbank, phase[pc_ch][23:16]};         // main voice
  end
  always_ff @(posedge clk)
    wq <= wrom[wrom_addr];

  // Second voice: phaser preset (~109/110) on wave 7, else the detune ratio
  wire [23:0] einc = eff_inc[pc_ch];
  wire [23:0] v2inc =
      // Phaser: the second oscillator runs at 109/110 of the first, which is
      // what produces the beat. 109/110 = 0.9909091; the previous shift pair
      // gave 0.9902344, a 7.4% error in the BEAT rate (4.30 Hz instead of 4.00
      // at A440). Three shifts land on 0.9909668 - 0.6% - for one more adder.
      // Reference: zepto-8 synth.cpp INST_PHASER, via jtothebell/fake-08.
      (snd_wave[pc_ch] == 3'd7) ? (einc - {7'b0, einc[23:7]}
                                        - {10'b0, einc[23:10]}
                                        - {12'b0, einc[23:12]}) :
      (ch_det[pc_ch] == 2'd1)   ? (einc + {7'b0, einc[23:7]}) :   // ~+14 cents
      (ch_det[pc_ch] == 2'd2)   ? {einc[22:0], 1'b0} :            // +1 octave
                                  24'd0;
  wire v2_on = (snd_wave[pc_ch] == 3'd7) || (ch_det[pc_ch] != 0);

  // Wavetable instruments read their 64 samples out of audio RAM, one
  // borrowed read per voice per sample (the sequencer FSM freezes for it).
  always_comb begin
    syn_rd   = 1'b0;
    syn_addr = 13'd0;
    if (prun && snd_wt[pc_ch] && playing[pc_ch]) begin
      if (pst == 2'd0) begin
        syn_rd   = 1'b1;
        syn_addr = snd_wtb[pc_ch] + {7'b0, phase[pc_ch][23:18]};
      end else if (pst == 2'd1 && v2_on) begin
        syn_rd   = 1'b1;
        syn_addr = snd_wtb[pc_ch] + {7'b0, phase2[pc_ch][23:18]};
      end
    end
  end

  // ---- waveform selection (head of the ring = this channel) ----------
  // BUZZ square/pulse: shifted duty straight from the phase counter
  wire [7:0] mph = phase[pc_ch][23:16];
  wire signed [7:0] buzzsq =
      (snd_wave[pc_ch] == 3'd3) ? (mph < 8'd102 ? 8'sd63 : -8'sd63)   // ~40%
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
  wire signed [15:0] nz_mul = $signed(nz_hold[pc_ch])
                            * $signed({1'b0, nz_gain[snd_pitch[pc_ch]]});
  wire signed [7:0] nz_scaled =
      (nz_mul >>> 8) > 16'sd127  ?  8'sd127 :
      (nz_mul >>> 8) < -16'sd127 ? -8'sd127 : 8'(nz_mul >>> 8);

  logic signed [7:0] samp;
  always_comb begin
    case (snd_wave[pc_ch])
      3'd6: samp = (ch_buzz[pc_ch] && !ch_noiz[pc_ch])
                     ? brown[pc_ch][12:5]                               // brown
                     : nz_scaled;
      // Phaser. The multiply MUST be done at full width: ph_sum is 11 bits and
      // so was the constant, so the product was evaluated modulo 2^11 and
      // 381*85 = 32385 wrapped to -383, leaving the phaser at 3% of its proper
      // amplitude - inaudible. It is two triangles summed 2:1 and scaled by
      // 85/256, which peaks at 126, i.e. the same full scale as any other wave.
      3'd7: samp = 8'((ph_wide * 19'sd85) >>> 8);                   // phaser
      3'd3, 3'd4:
            samp = ch_buzz[pc_ch] ? buzzsq
                 : (ch_det[pc_ch] != 0) ? det_clip : smp_a;
      default:
            samp = (ch_det[pc_ch] != 0) ? det_clip : smp_a;
    endcase
  end

  // DAMPEN: per-channel one-pole low-pass (Q8), shift by damp level
  wire signed [15:0] samp_q8 = signed'({samp, 8'b0});
  wire signed [15:0] lp_next =
      lp[pc_ch] + ((samp_q8 - lp[pc_ch]) >>> ch_damp[pc_ch]);
  wire signed [7:0] samp_d = (ch_damp[pc_ch] == 0) ? samp : lp_next[15:8];

  // Sample x volume. This used to be an 8-iteration shift-add unit, to avoid
  // an array multiplier. It cost 8 of the ~12 clocks a voice takes per sample,
  // which is affordable at four voices and not at sixteen: a single-cycle 8x8
  // multiply is about 60 LCs and hands back 7 clocks per voice per sample.
  //
  // The magnitude is multiplied and the sign reapplied, exactly as the serial
  // unit did, so this is bit-for-bit the same product.
  logic        mx_neg, mx_play;
  logic signed [15:0] mx_lp;
  logic [1:0]  mx_rev, mx_damp;
  wire  [7:0]  n_mag = samp_d[7] ? ((samp_d == -8'sd128) ? 8'd127 : 8'(-samp_d))
                                 : 8'(samp_d);
  // The full 16-bit product, not its top byte. Truncating here cost the most
  // resolution anywhere in the chip: a note at PICO-8 volume 1 has eff_vol 36,
  // so (127*36)>>8 = 17 levels - 4.2 bits. Two thirds of NEMO's title music is
  // volume 1 or 2. Keeping the low half makes those 12.2 and 13.2 bits.
  logic [15:0] n_res;
  wire signed [18:0] n_contrib = mx_neg ? -$signed({3'b0, n_res})
                                        :  $signed({3'b0, n_res});

  logic signed [18:0] mixacc;   // 4 channels x 32512 needs 19 bits
  logic [1:0]  rev_max;
  // The echo has to outlive the note that asked for it, so the level any
  // playing channel requests is held for a full delay line after the last
  // request rather than dropping with the channel.
  logic [1:0]  rev_lvl;
  logic [9:0]  rev_ttl;
  logic        dry_pend;
  logic signed [15:0] dry16;
  logic        dry_valid;

  always_ff @(posedge clk) begin
    if (reset) begin
      lfsr <= 15'h2A5F;
      prun <= 0;
      pc_ch <= 0;
      pst <= 0;
      smp_a <= 0;
      smp_b <= 0;
      clr_ack <= 0;
      n_res <= 0;
      mx_neg <= 0;
      mx_play <= 0;
      mx_lp <= 0;
      mx_rev <= 0;
      mx_damp <= 0;
      mixacc <= 0;
      rev_max <= 0;
      rev_lvl <= 0;
      rev_ttl <= 0;
      dry_pend <= 0;
      dry16 <= 0;
      dry_valid <= 0;
      for (int i = 0; i < 4; i++) begin
        phase[i] <= 0;
        phase2[i] <= 0;
        nz_hold[i] <= 0;
        nz_ph[i] <= 0;
        brown[i] <= 0;
        lp[i] <= 0;
      end
    end else begin
      dry_valid <= 0;

      if (dry_pend) begin
        dry_pend <= 0;
        // PICO-8 mixes four quarter-scale channels and clips only at the sum
        // (zepto-8 synth: chan = waveform * vol * 0.5, mix = clamp(sum, +-1)).
        // One channel at full volume peaks at 32512, so >>> 2 puts it at a
        // quarter of full scale and four sum to full scale without clipping.
        dry16 <= 16'((mixacc > 19'sd131068 ?  19'sd131068 :
                      mixacc < -19'sd131068 ? -19'sd131068 : mixacc) >>> 2);
        dry_valid <= 1;
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

      if (sample_en) begin
        prun <= 1;
        pc_ch <= 0;
        pst <= 0;
        mixacc <= 0;
        rev_max <= 0;
      end else if (prun) begin
        case (pst)
          2'd0: begin                    // advance phase(s), issue main read
            // One step per voice per sample. This used to free-run on the
            // system clock, which tied the noise sequence to how many clocks
            // the per-voice pipeline happened to take - so shortening the
            // sample x volume multiply, or changing the number of voices,
            // silently changed what the noise sounded like. Stepping it here
            // gives every voice a fresh value every sample and makes the
            // noise independent of the pipeline's timing.
            lfsr <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};
            if (playing[pc_ch]) begin
              phase[pc_ch] <= phase[pc_ch] + einc;
              if (v2_on)
                phase2[pc_ch] <= phase2[pc_ch] + v2inc;
              // noise: white every sample when NOIZ, else pitched S&H
              if (ch_noiz[pc_ch] || phase[pc_ch][23:20] != nz_ph[pc_ch]) begin
                nz_ph[pc_ch] <= phase[pc_ch][23:20];
                nz_hold[pc_ch] <= $signed(lfsr[7:0]);
              end
              // brown integrator (leaky low-pass of white) for BUZZ noise
              brown[pc_ch] <= brown[pc_ch]
                            - {{5{brown[pc_ch][12]}}, brown[pc_ch][12:5]}
                            + $signed({{5{lfsr[7]}}, lfsr[7:0]});
            end
            // a trigger asked for this channel's filter state to be reset
            if (clr_tog[pc_ch] != clr_ack[pc_ch]) begin
              clr_ack[pc_ch] <= clr_tog[pc_ch];
              lp[pc_ch] <= 0;
              brown[pc_ch] <= 0;
            end
            pst <= 2'd1;
          end
          2'd1: begin                    // main-voice sample
            smp_a <= snd_wt[pc_ch] ? $signed(seq_q) : wq;
            pst <= 2'd2;
          end
          2'd2: begin                    // second voice, then start x volume
            smp_b <= snd_wt[pc_ch] ? $signed(seq_q) : wq;
            n_res <= n_mag * eff_vol[pc_ch];
            mx_neg  <= samp_d[7];
            mx_play <= playing[pc_ch];
            mx_lp   <= lp_next;
            mx_rev  <= ch_rev[pc_ch];
            mx_damp <= ch_damp[pc_ch];
            pst <= 2'd3;
          end
          2'd3: begin                    // accumulate, then next voice
            if (mx_play) begin
              mixacc <= mixacc + n_contrib;
              if (mx_rev > rev_max) rev_max <= mx_rev;
            end
            // the dampen state is the only thing this stage writes back
            if (mx_play && mx_damp != 0) lp[pc_ch] <= mx_lp;
            pst <= 2'd0;
            if (pc_ch == 2'd3) begin
              prun <= 0;
              dry_pend <= 1;
            end
            pc_ch <= pc_ch + 1;
          end
          default: pst <= 2'd0;
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
        // A pending trigger (written this cycle, not yet processed by the
        // sequencer) already reads as busy, so back-to-back sfx() calls
        // that auto-pick a channel never collide on the same one.
        8'h03: dout <= {mus_playing, 3'b0,
                        playing[3] | trig_req[3], playing[2] | trig_req[2],
                        playing[1] | trig_req[1], playing[0] | trig_req[0]};
        8'h20: dout <= {2'b0, mus_pat};
        // Low nibble: the channels the cart reserved. High nibble: the
        // channels the song actually occupies right now. PICO-8 does not need
        // the second one - sfx(n, -1) takes a voice from a pool of sixteen and
        // so can never displace music - but with four physical channels the
        // software auto-pick has to be told what the music is using, or it
        // will take a music channel the reservation mask does not name.
        8'h21: dout <= {music_owned[3], music_owned[2], music_owned[1],
                        music_owned[0], mus_mask};
        8'h22: dout <= fade_len;
        default:
          if (addr[7:4] == 4'h1)
            // $10-$13 report the row, $14-$17 the SFX the channel plays
            dout <= (addr[3:2] == 2'd1)
                      ? {playing[addr[1:0]], 1'b0, sfx_id[addr[1:0]]}
                      : {playing[addr[1:0]], 2'b0, row[addr[1:0]]};
          else
            dout <= 8'h00;
      endcase
    end
  end
  // {music, pattern, per-channel owned/playing/sfx/vol}
  always_comb begin
    dbg = 64'b0;
    dbg[7:0]   = {mus_playing, 1'b0, mus_pat};
    dbg[11:8]  = {playing[3], playing[2], playing[1], playing[0]};
    dbg[15:12] = {music_owned[3], music_owned[2], music_owned[1], music_owned[0]};
    dbg[21:16] = sfx_id[0];
    dbg[27:22] = sfx_id[1];
    dbg[33:28] = sfx_id[2];
    dbg[39:34] = sfx_id[3];
    dbg[45:40] = {1'b0, row[0]};
    dbg[51:46] = {1'b0, row[1]};
    dbg[57:52] = {1'b0, row[2]};
    dbg[63:58] = {1'b0, row[3]};
  end

endmodule
