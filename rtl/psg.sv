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
// The music sequencer is hardware: writing a pattern number fetches the
// 4 pattern bytes, launches the enabled channels' SFX, ends the pattern
// by the left-most non-looping channel rule, and follows the loop-start /
// loop-back / stop flag bits with zero CPU work. The filter byte and
// custom-instrument flag are accepted but not yet interpreted.
//
// Registers (byte window at $4100):
//   $00/$01 upload address lo/hi (PICO-8 address), $02 data (auto-inc)
//   $03 (read) playing bits [3:0], music playing bit 7
//   $10+c write: play SFX n (0-63) on channel c; $80 stops the channel
//         read: {playing, 2'b0, row}
//   $20 write: start music at pattern m (0-63); $80 stops music
//       read: current pattern
//   $21 music channel mask (bit c: music may use channel c; reset $0F)
module psg #(parameter CLK_HZ = 32'd3_506_580)
          (input bit clk, input bit reset,
           input bit cs, input bit rw, input logic [7:0] addr, input logic [7:0] di,
           output logic [7:0] dout,
           output logic [7:0] pcm);

  // Audio RAM: PICO-8 $3100-$42FF (music 0..255, SFX records 256..4607)
  logic [7:0] aram[0:4607];
  logic [15:0] wraddr;

  logic signed [7:0] wrom[0:2047];   // 8 waves x 256, exact PICO-8 shapes
  logic [23:0] pinc[0:63];           // 2^24 * f(pitch) / 22050
  logic [15:0] recip[0:255];         // 65536 / speed
  initial begin
    $readmemh("./rtl/psg_waves.hex", wrom);
    $readmemh("./rtl/psg_pitch.hex", pinc);
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
  logic [7:0]  tcnt[0:3];            // ticks since trigger (vibrato/arp)
  logic [7:0]  sp[0:3], lps[0:3], lpe[0:3];
  logic [5:0]  cur_pitch[0:3], prev_pitch[0:3];
  logic [2:0]  cur_wave[0:3], cur_vol[0:3], cur_fx[0:3], prev_vol[0:3];
  logic [23:0] eff_inc[0:3];
  logic [7:0]  eff_vol[0:3];
  logic [23:0] phase[0:3], phase2[0:3];
  logic signed [7:0] nz_hold[0:3];
  logic [3:0]  nz_ph[0:3];

  logic [3:0]  trig_req;

  // Music state
  logic        mus_playing, mus_launch, mus_tch_pend;
  logic [5:0]  mus_pat;
  logic [3:0]  mus_mask;
  logic [7:0]  pb[0:2];
  logic [3:0]  launched;
  logic [1:0]  tch;
  logic        tch_valid, f_lb, f_stop;
  logic [12:0] pticks, ptick_tgt;    // all-looping-pattern fallback

  // ------------------------------------------------------------------
  // Sequencer FSM (note fetch, per-tick effects, music flow control)
  // ------------------------------------------------------------------
  typedef enum logic [4:0] {
    S_IDLE,
    T_SP, T_LS, T_LE, T_NL, T_NH, T_LD,
    K_ADV, K_NL, K_NH, K_LD, K_ARP, K_ARPC, K_FX,
    W_MUS,
    ML_STOP, ML_RD0, ML_RD1, ML_RD2, ML_RD3, ML_LD, M_TCH,
    MS_RD, MS_CK
  } sst_t;
  sst_t sst;

  logic [1:0]  c;                    // channel being processed
  logic        walk;                 // 1 = tick walk, 0 = trigger service
  logic        tickpend;
  logic [5:0]  scan_p;
  logic [7:0]  note_lo;
  logic [5:0]  arp_p;

  wire [12:0] ch_base = 13'd256 + {1'b0, sfx_id[c], 6'b0} + {5'b0, sfx_id[c], 2'b0};

  // Arpeggio source row: (tick / period) & 3, period from fx and speed
  logic [1:0] arp_idx;
  always_comb begin
    if (cur_fx[c] == 3'd6)
      arp_idx = (sp[c] <= 8) ? tcnt[c][2:1] : tcnt[c][3:2];
    else
      arp_idx = (sp[c] <= 8) ? tcnt[c][3:2] : tcnt[c][4:3];
  end

  // Registered RAM read: seq_q holds the data for the address issued in
  // the previous state.
  logic [12:0] seq_addr;
  logic [7:0]  seq_q;
  always_comb begin
    seq_addr = 13'd0;
    case (sst)
      T_SP:   seq_addr = ch_base + 13'd65;
      T_LS:   seq_addr = ch_base + 13'd66;
      T_LE:   seq_addr = ch_base + 13'd67;
      T_NL,
      K_NL:   seq_addr = ch_base + {7'b0, row[c], 1'b0};
      T_NH,
      K_NH:   seq_addr = ch_base + {7'b0, row[c], 1'b1};
      K_ARP:  seq_addr = ch_base + {7'b0, row[c][4:2], arp_idx, 1'b0};
      ML_RD0: seq_addr = {5'b0, mus_pat, 2'd0};
      ML_RD1: seq_addr = {5'b0, mus_pat, 2'd1};
      ML_RD2: seq_addr = {5'b0, mus_pat, 2'd2};
      ML_RD3: seq_addr = {5'b0, mus_pat, 2'd3};
      MS_RD:  seq_addr = {5'b0, scan_p, 2'd0};
      default: ;
    endcase
  end
  always_ff @(posedge clk)
    seq_q <= aram[seq_addr];

  // Per-tick effect evaluation (feeds eff_inc/eff_vol in K_FX)
  wire [23:0] fx_u24 = ({16'b0, fcnt[c]} * {8'b0, recip[sp[c]]}) >> 8;
  wire [7:0]  u = fx_u24[7:0];               // row progress, Q8
  wire [23:0] base_inc = pinc[cur_pitch[c]];
  wire [23:0] prev_inc = pinc[prev_pitch[c]];
  wire [7:0]  vol36  = {2'b0, cur_vol[c], 3'b0} + {3'b0, cur_vol[c], 2'b0};
  wire [7:0]  pvol36 = {2'b0, prev_vol[c], 3'b0} + {3'b0, prev_vol[c], 2'b0};

  logic signed [25:0] sl_diff;
  logic signed [34:0] sl_prod;
  logic signed [9:0]  vl_diff;
  logic signed [18:0] vl_prod;
  logic signed [4:0]  lfo;
  logic [31:0] drop_prod;
  logic [15:0] fade_prod;
  logic [23:0] fx_inc;
  logic [7:0]  fx_vol;
  always_comb begin
    sl_diff = $signed({2'b0, base_inc}) - $signed({2'b0, prev_inc});
    sl_prod = sl_diff * $signed({1'b0, u});
    vl_diff = $signed({2'b0, vol36}) - $signed({2'b0, pvol36});
    vl_prod = vl_diff * $signed({1'b0, u});
    if (tcnt[c][3:0] < 4'd5)       lfo = $signed({1'b0, tcnt[c][3:0]});
    else if (tcnt[c][3:0] < 4'd13) lfo = 5'sd8 - $signed({1'b0, tcnt[c][3:0]});
    else                           lfo = $signed({1'b0, tcnt[c][3:0]}) - 5'sd16;
    drop_prod = {8'b0, base_inc} * {24'b0, 8'd255 - u};
    fade_prod = {8'b0, vol36} *
                ((cur_fx[c] == 3'd4) ? {8'b0, u} : {8'b0, 8'd255 - u});

    fx_inc = base_inc;
    fx_vol = vol36;
    case (cur_fx[c])
      3'd1: begin  // slide from the previous row's pitch and volume
        fx_inc = prev_inc + 24'($signed(sl_prod >>> 8));
        fx_vol = pvol36 + 8'($signed(vl_prod >>> 8));
      end
      3'd2:        // vibrato: ~7.5 Hz triangle LFO, ~+/-1.5% frequency
        fx_inc = base_inc + 24'($signed({9'b0, base_inc[23:8]}) * lfo);
      3'd3:        // drop: frequency falls to zero across the row
        fx_inc = drop_prod[31:8];
      3'd4, 3'd5:  // fade in / fade out
        fx_vol = fade_prod[15:8];
      3'd6, 3'd7:  // arpeggio: pitch from the fetched group row
        fx_inc = pinc[arp_p];
      default: ;
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      sst <= S_IDLE;
      c <= 0;
      walk <= 0;
      tickpend <= 0;
      trig_req <= 0;
      mus_playing <= 0;
      mus_launch <= 0;
      mus_tch_pend <= 0;
      mus_pat <= 0;
      launched <= 0;
      tch <= 0;
      tch_valid <= 0;
      f_lb <= 0;
      f_stop <= 0;
      pticks <= 0;
      ptick_tgt <= 0;
      scan_p <= 0;
      note_lo <= 0;
      arp_p <= 0;
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
      end
      for (int i = 0; i < 3; i++)
        pb[i] <= 0;
    end else begin
      if (tick_en)
        tickpend <= 1;

      case (sst)
        S_IDLE: begin
          if (trig_req != 0) begin
            walk <= 0;
            c <= trig_req[0] ? 2'd0 : trig_req[1] ? 2'd1 :
                 trig_req[2] ? 2'd2 : 2'd3;
            sst <= T_SP;
          end else if (mus_launch) begin
            mus_launch <= 0;
            sst <= ML_STOP;
          end else if (mus_tch_pend) begin
            mus_tch_pend <= 0;
            sst <= M_TCH;
          end else if (tickpend) begin
            tickpend <= 0;
            walk <= 1;
            c <= 0;
            sst <= K_ADV;
          end
        end

        // ---- trigger: load record metadata, then note 0 --------------
        T_SP: begin
          trig_req[c] <= 0;
          row[c] <= 0;
          fcnt[c] <= 0;
          tcnt[c] <= 0;
          prev_pitch[c] <= 6'd24;
          prev_vol[c] <= 0;
          playing[c] <= 1;
          sst <= T_LS;
        end
        T_LS: begin
          sp[c] <= (seq_q == 0) ? 8'd1 : seq_q;
          sst <= T_LE;
        end
        T_LE: begin
          lps[c] <= seq_q;
          sst <= T_NL;
        end
        T_NL: begin
          lpe[c] <= seq_q;
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
          sst <= K_ARP;
        end

        // ---- per-tick walk -------------------------------------------
        K_ADV: begin
          if (!playing[c]) begin
            eff_vol[c] <= 0;
            if (c == 2'd3) sst <= W_MUS;
            else begin c <= c + 1; sst <= K_ADV; end
          end else begin
            tcnt[c] <= tcnt[c] + 1;
            if ({1'b0, fcnt[c]} + 9'd1 >= {1'b0, sp[c]}) begin
              // row finished: loop, stop, or advance, then refetch
              prev_pitch[c] <= cur_pitch[c];
              prev_vol[c] <= cur_vol[c];
              fcnt[c] <= 0;
              if (lps[c] < lpe[c] && {3'b0, row[c]} + 8'd1 >= lpe[c]) begin
                row[c] <= lps[c][4:0];
                sst <= K_NL;
              end else if ({3'b0, row[c]} + 8'd1 >=
                           ((lps[c] != 0 && lpe[c] == 0)
                              ? ((lps[c] < 8'd32) ? lps[c] : 8'd32)
                              : 8'd32)) begin
                playing[c] <= 0;
                eff_vol[c] <= 0;
                if (c == 2'd3) sst <= W_MUS;
                else begin c <= c + 1; sst <= K_ADV; end
              end else begin
                row[c] <= row[c] + 1;
                sst <= K_NL;
              end
            end else begin
              fcnt[c] <= fcnt[c] + 1;
              sst <= K_ARP;
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
          sst <= K_ARP;
        end
        K_ARP:
          if (cur_fx[c] == 3'd6 || cur_fx[c] == 3'd7)
            sst <= K_ARPC;                  // arp row's note lo lands next
          else
            sst <= K_FX;
        K_ARPC: begin
          arp_p <= seq_q[5:0];
          sst <= K_FX;
        end
        K_FX: begin
          eff_inc[c] <= fx_inc;
          eff_vol[c] <= fx_vol;
          if (!walk)
            sst <= S_IDLE;
          else if (c == 2'd3)
            sst <= W_MUS;
          else begin
            c <= c + 1;
            sst <= K_ADV;
          end
        end

        // ---- music: pattern-end check and flow control ---------------
        W_MUS: begin
          sst <= S_IDLE;
          if (mus_playing && !mus_launch && trig_req == 0 && !mus_tch_pend) begin
            pticks <= pticks + 1;
            if (tch_valid ? !playing[tch] : (pticks >= ptick_tgt)) begin
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
          for (int i = 0; i < 4; i++)
            if (music_owned[i]) begin
              playing[i] <= 0;
              eff_vol[i] <= 0;
              music_owned[i] <= 0;
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
          for (int i = 0; i < 3; i++)
            if (!pb[i][6] && mus_mask[i]) begin
              trig_req[i] <= 1;
              sfx_id[i] <= pb[i][5:0];
              music_owned[i] <= 1;
              launched[i] <= 1;
            end
          if (!seq_q[6] && mus_mask[3]) begin
            trig_req[3] <= 1;
            sfx_id[3] <= seq_q[5:0];
            music_owned[3] <= 1;
            launched[3] <= 1;
          end
          mus_playing <= 1;
          mus_tch_pend <= 1;
          sst <= S_IDLE;
        end
        M_TCH: begin
          // left-most launched non-looping channel paces the pattern
          tch_valid <= 0;
          for (int i = 3; i >= 0; i--)
            if (launched[i] && !(lps[i] < lpe[i])) begin
              tch <= i[1:0];
              tch_valid <= 1;
            end
          pticks <= 0;
          ptick_tgt <= {launched[0] ? sp[0] :
                        launched[1] ? sp[1] :
                        launched[2] ? sp[2] : sp[3], 5'b0};
          sst <= S_IDLE;
        end

        default: sst <= S_IDLE;
      endcase

      // ---- CPU control writes (override sequencer state) -------------
      if (cs && rw && addr[7:4] == 4'h1) begin
        if (di[7]) begin
          playing[addr[1:0]] <= 0;
          eff_vol[addr[1:0]] <= 0;
          music_owned[addr[1:0]] <= 0;
          trig_req[addr[1:0]] <= 0;
        end else begin
          trig_req[addr[1:0]] <= 1;
          sfx_id[addr[1:0]] <= di[5:0];
          music_owned[addr[1:0]] <= 0;
          eff_vol[addr[1:0]] <= 0;
        end
      end
      if (cs && rw && addr == 8'h20) begin
        if (di[7]) begin
          mus_playing <= 0;
          mus_launch <= 0;
          for (int i = 0; i < 4; i++)
            if (music_owned[i]) begin
              playing[i] <= 0;
              eff_vol[i] <= 0;
              music_owned[i] <= 0;
            end
        end else begin
          mus_pat <= di[5:0];
          mus_launch <= 1;
        end
      end
    end
  end

  // ------------------------------------------------------------------
  // Synthesis: channels serialized through one datapath per sample.
  // Per channel: pst0 advance phase + issue main wave read, pst1 issue
  // detuned read + capture main, pst2 capture detuned + hand to mixer.
  // ------------------------------------------------------------------
  logic [14:0] lfsr;
  logic [1:0]  pc_ch, pst;
  logic        prun;
  logic signed [7:0] wq, smp_a, smp_b;
  logic [10:0] wrom_addr;

  always_comb begin
    if (pst == 2'd1)
      wrom_addr = {3'd0, phase2[pc_ch][23:16]};   // phaser's detuned voice
    else
      wrom_addr = {(cur_wave[pc_ch] == 3'd7) ? 3'd0 : cur_wave[pc_ch],
                   phase[pc_ch][23:16]};
  end
  always_ff @(posedge clk)
    wq <= wrom[wrom_addr];

  // Detuned increment for the phaser: ~0.99 of the main frequency
  wire [23:0] einc  = eff_inc[pc_ch];
  wire [23:0] einc2 = einc - {7'b0, einc[23:7]} - {9'b0, einc[23:9]};

  always_ff @(posedge clk) begin
    if (reset) begin
      lfsr <= 15'h2A5F;
      prun <= 0;
      pc_ch <= 0;
      pst <= 0;
      smp_a <= 0;
      smp_b <= 0;
      for (int i = 0; i < 4; i++) begin
        phase[i] <= 0;
        phase2[i] <= 0;
        nz_hold[i] <= 0;
        nz_ph[i] <= 0;
      end
    end else begin
      lfsr <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};

      if (sample_en) begin
        prun <= 1;
        pc_ch <= 0;
        pst <= 0;
      end else if (prun) begin
        case (pst)
          2'd0: begin                    // advance phase, issue main read
            if (playing[pc_ch]) begin
              phase[pc_ch] <= phase[pc_ch] + eff_inc[pc_ch];
              phase2[pc_ch] <= phase2[pc_ch] + einc2;
              if (phase[pc_ch][23:20] != nz_ph[pc_ch]) begin
                nz_ph[pc_ch] <= phase[pc_ch][23:20];
                nz_hold[pc_ch] <= $signed(lfsr[7:0]);
              end
            end
            pst <= 2'd1;
          end
          2'd1: begin
            smp_a <= wq;                 // main-voice sample
            pst <= 2'd2;
          end
          2'd2: begin
            smp_b <= wq;                 // detuned sample (phaser only)
            pst <= 2'd0;
            if (pc_ch == 2'd3) prun <= 0;
            pc_ch <= pc_ch + 1;
          end
          default: pst <= 2'd0;
        endcase
      end
    end
  end

  // Mixer: runs one cycle behind the datapath, one channel at a time
  logic [1:0]  mix_ch;
  logic        mix_go, mix_fin;
  logic signed [10:0] mixacc;

  logic signed [7:0] samp;
  logic signed [10:0] ph_sum;
  always_comb begin
    ph_sum = $signed({smp_a[7], smp_a, 1'b0}) + $signed({{3{smp_b[7]}}, smp_b});
    case (cur_wave[mix_ch])
      3'd6:    samp = (nz_hold[mix_ch] + (nz_hold[mix_ch] >>> 1)) >>> 1;
      3'd7:    samp = 8'((ph_sum * 11'sd85) >>> 8);
      default: samp = smp_a;
    endcase
  end
  wire signed [16:0] contrib = samp * $signed({1'b0, eff_vol[mix_ch]});

  always_ff @(posedge clk) begin
    if (reset) begin
      mix_ch <= 0;
      mix_go <= 0;
      mix_fin <= 0;
      mixacc <= 0;
      pcm <= 8'h80;
    end else begin
      mix_go <= prun && pst == 2'd2;
      mix_ch <= pc_ch;
      mix_fin <= 0;
      if (sample_en)
        mixacc <= 0;
      if (mix_go) begin
        if (playing[mix_ch])
          mixacc <= mixacc + 11'($signed(contrib[16:8]));
        if (mix_ch == 2'd3) mix_fin <= 1;
      end
      if (mix_fin)
        pcm <= 8'd128 + 8'((mixacc > 11'sd255 ?  11'sd255 :
                            mixacc < -11'sd255 ? -11'sd255 : mixacc) >>> 1);
    end
  end

  // ------------------------------------------------------------------
  // CPU interface: upload port, music mask, status reads
  // ------------------------------------------------------------------
  wire [15:0] up_idx = wraddr - 16'h3100;

  always_ff @(posedge clk) begin
    if (reset) begin
      wraddr <= 16'h3100;
      mus_mask <= 4'hF;
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
        8'h03: dout <= {mus_playing, 3'b0,
                        playing[3], playing[2], playing[1], playing[0]};
        8'h20: dout <= {2'b0, mus_pat};
        8'h21: dout <= {4'b0, mus_mask};
        default:
          if (addr[7:4] == 4'h1)
            dout <= {playing[addr[1:0]], 2'b0, row[addr[1:0]]};
          else
            dout <= 8'h00;
      endcase
    end
  end
endmodule
