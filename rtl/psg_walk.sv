// Sample-rate synthesis walk.
//
// Each sample serializes eight slot visits. A visit streams oscillator and
// active sounding state from psg_state_mem, evaluates built-in or wavetable
// oscillators, advances noise/filter/crossfade state, forms a mixer leaf, and
// writes oscillator state back. The eight leaves are reduced with PICO-8's
// soft-add function. REALTIME_PREVIEW selects a shorter approximate schedule.
//
// Reading guide: pph is the per-slot microphase and pc_ch is the slot. s_*
// names the live tuple, old_* the preceding crossfade arm, and last_* the tuple
// remembered for transition detection. wt_*, nz_*, mx_*, bl_*, and f* group
// wavetable, noise, mixer-arm, blend, and final fold state respectively.

`ifndef PSG_WALK_SV
`define PSG_WALK_SV

module psg_walk #(parameter REVERB = 1, parameter REALTIME_PREVIEW = 0,
                  parameter MULTIPUMP = 0,
                  // Live width of the secondary-oscillator phase: PREVIEW
                  // accumulates a full 24-bit phase; the hardware schedule
                  // stores, restores and consumes exactly [16:0]. Sized here
                  // because the s_phase2 port needs it (sizing audit).
                  localparam int PH2_W = REALTIME_PREVIEW ? 24 : 17)
                 (input  bit   clk,
                  input  bit   reset,
                  input  logic sample_en,

                  // Tick-published playback and sounding-bank state.
                  input  logic [PSG_NV-1:0] play_bits,
                  input  logic mus_playing,
                  input  logic spar_bank,
                  input  logic [PSG_NV-1:0] clr_tog,

                  // Shared audio-RAM borrow for wavetable samples.
                  input  logic [7:0]  seq_q,
                  output logic        syn_rd,
                  output logic [12:0] syn_addr,

                  // Walk side of the shared per-slot state memory.
                  input  logic [15:0] state_q,
                  output logic        state_sample_read,
                  output logic [PSG_VADR-1:0] wlk_ra,
                  output logic        state_sample_we,
                  output logic [PSG_VADR-1:0] wlk_wa,
                  output logic [15:0] wlk_wd,

                  // Shared multiplier result and zero-when-idle request bundle.
                  input  logic [33:0] m_res,
                  input  logic        m_busy,
                  output logic        wmul_start,
                  output logic signed [24:0] wmul_a,
                  output logic [11:0] wmul_b,
                  output logic [1:0]  wmul_mode,
                  output logic        wmul_short,

                  // Context request to psg_wave and its pipelined response.
                  output logic iss_sec,
                  output logic iss_om,
                  output logic iss_os,
                  output logic dq_old_ctx,
                  output logic [2:0]  s_snd_wave,
                  output logic        s_snd_wt,
                  output logic [1:0]  s_ch_det,
                  output logic        s_ch_buzz,
                  output logic [15:0] s_phase,
                  output logic [PH2_W-1:0] s_phase2,
                  output logic [13:0] s_eff_inc,
                  output logic [2:0]  s_old_wave,
                  output logic [15:0] s_old_phase,
                  output logic [13:0] s_old_inc,
                  output logic [1:0]  old_mode_r,
                  output logic        old_alt_r,
                  output logic [16:0] old_q0,
                  input  logic signed [17:0] z_eval,
                  input  logic [16:0] dq17,
                  input  logic [15:0] q16,

                  // Prefetched capture-action word from the shared control ROM.
                  input  logic [15:0] ctrl_q,
                  output logic [7:0]  ctrl_addr,
                  input  logic        ctrl_stall,

                  // Ownership/status and completed eight-slot mix.
                  output logic        prun,
                  output logic        fold_busy,

                  output wire signed [15:0] dry16,
                  output logic        dry_valid);
  // ---- Visit schedule and phase control ----
  // pph is the phase within one slot visit; pc_ch is the current slot index.
  logic [PPH_W-1:0] pph;
  logic [15:0] sosc_wd;

  // Schedule landmarks. Full mode streams 14 oscillator words and closes at
  // phase 61 with multi-pumping or 67 with the single-clock multiplier.
  // Preview streams seven words and closes at phase 23.
  localparam int PLOSC = REALTIME_PREVIEW ? 7  : PSG_SOSC;

  localparam int PWORK = REALTIME_PREVIEW ? 12 : 29;
  localparam int PFOLD = REALTIME_PREVIEW ? 23 : (MULTIPUMP ? 61 : 67);
  localparam int PSTOR = REALTIME_PREVIEW ? 16 : (MULTIPUMP ? 46 : 51);
  localparam int PLAST = REALTIME_PREVIEW ? 23 : (MULTIPUMP ? 61 : 67);

  // Full-schedule shared-multiplier phases for previous/live noise steps.
  localparam int PNZ_OLD  = 19;
  localparam int PNZ_LIVE = 24;

  // Sized by what the values need, not by convenience (sizing audit):
  // - pph never exceeds PLAST (PFOLD == PLAST by construction), so the phase
  //   counter is 6 bits under MULTIPUMP (PLAST = 61) and 7 otherwise.
  // - s_phase2's live width PH2_W is declared with the module parameters
  //   (the port needs it); ph2_pad below keeps the PREVIEW-only slices
  //   width-stable in both elaborations.
  localparam int PPH_W = $clog2(PLAST + 1);

  // Zero-extended view of s_phase2 for the PREVIEW-only wide slices.
  wire [23:0] ph2_pad = 24'(s_phase2);

  // ---- Current-slot sounding and oscillator working set ----
  // s_* is current-slot state; old_*/last_* retain transition-arm context.
  logic [2:0]  s_snd_id;
  logic        s_ch_noiz;
  logic [1:0]  s_ch_rev, s_ch_damp;
  logic [10:0] s_eff_a;
  logic signed [7:0] s_nz_hold;
  logic [3:0]  s_nz_ph;
  logic signed [12:0] s_brown;
  logic signed [16:0] s_lp;
  logic signed [15:0] s_noise_lp;

  logic [13:0] s_last_inc;
  logic [11:0] s_old_G, s_last_G;
  logic [2:0]  s_last_wave;

  logic [1:0]  last_mode_r;
  logic        last_alt_r;

  logic [1:0]  old_rev_r, last_rev_r;
  logic [6:0]  bl_cnt;

  // Full mode streams the per-slot clear acknowledgement through a spare
  // oscillator-record bit. Preview keeps random access for its phase-0 skip.
  logic        s_clr_tog, s_clr_ack;
  logic [PSG_NV-1:0] clr_ack_pv;

  wire [12:0] s_snd_wtb = rec_base({3'b0, s_snd_id});

  // Full schedule uses a serial soft-add microcycle; preview uses mxs below.
  logic [3:0]  fmc;

  assign fold_busy = REALTIME_PREVIEW ? (mxs != 2'd0) : (fmc != 4'd0);
  assign state_sample_read = prun && !ctrl_stall
                               && pph < PPH_W'(PLOSC + PSG_SPAR);

  wire         state_lp_we = prun && !ctrl_stall && !REALTIME_PREVIEW
                               && (pph == PPH_W'(PLAST - 1)
                                   || pph == PPH_W'(PLAST));
  assign state_sample_we = (prun && !ctrl_stall
                               && pph >= PPH_W'(PSTOR)
                               && pph < PPH_W'(PSTOR + PLOSC))
                               || state_lp_we;

  logic [14:0] lfsr;

  logic [14:0] lfsr2;

  logic        spar_last, nz_tick_r;

  logic signed [17:0] nz_out_r, nz_old_out_r;
  logic        old_nz_r_on;

  logic        nz_tog;
  logic [PSG_VW-1:0] pc_ch;

  logic signed [17:0] smp_a, smp_b;
  logic signed [7:0] wt_x1;
  logic [9:0] wt_pf, wt_qf;

  // Pack the oscillator working set for its scheduled writeback window.
  wire [3:0] s_stw = 4'(pph - PPH_W'(PSTOR));
  always_comb begin
    if (REALTIME_PREVIEW) begin
      case (s_stw)

        4'd0:    sosc_wd = s_phase;
        4'd1:    sosc_wd = {s_nz_hold, old_q0[7:0]};
        4'd2:    sosc_wd = s_phase2[15:0];
        4'd3:    sosc_wd = {s_old_G[3:0], s_nz_ph, ph2_pad[23:16]};
        4'd4:    sosc_wd = {s_old_G[6:4], s_brown};
        4'd5:    sosc_wd = s_lp[15:0];
        4'd6:    sosc_wd = s_noise_lp;
        default: sosc_wd = 16'd0;
      endcase
    end else begin
      case (s_stw)
        4'd0:    sosc_wd = s_phase;
        4'd1:    sosc_wd = {s_nz_hold, old_q0[7:0]};
        4'd2:    sosc_wd = s_phase2[15:0];

        4'd3:    sosc_wd = {s_clr_ack, 1'b0, s_old_G[11:8],
                            1'b0, s_last_G[11:8],
                            s_nz_ph, s_phase2[16]};
        4'd4:    sosc_wd = `PSG_OSC_W14;
        4'd5:    sosc_wd = s_lp[15:0];
        4'd6:    sosc_wd = s_old_phase;
        4'd7:    sosc_wd = `PSG_OSC_W17;
        4'd8:    sosc_wd = {s_old_inc[8:0], 7'b0};
        4'd9:    sosc_wd = {s_old_G[7:0], 3'b0, s_old_inc[13:9]};
        4'd10:   sosc_wd = {1'b0, old_rev_r, last_rev_r,
                            s_last_wave, 3'b0, s_last_inc[13:9]};
        4'd11:   sosc_wd = {s_last_inc[8:0], 7'b0};
        4'd12:   sosc_wd = {1'b0, `PSG_OSC_W22};
        default: sosc_wd = s_noise_lp;
      endcase
    end
  end

  // ---- State-memory stream and writeback schedule ----
  // State-memory addresses stream oscillator words followed by the selected
  // sounding bank. Late full-schedule writes commit dampen state.
  logic [4:0] wlk_roff;
  always_comb begin
    if (pph < PPH_W'(PLOSC))
      wlk_roff = PSG_V_OSC + 5'(pph);
    else if (pph < PPH_W'(PLOSC + PSG_SPAR))
      wlk_roff = (spar_bank ? PSG_V_PAR1 : PSG_V_PAR0)
                 + 5'(pph - PPH_W'(PLOSC));
    else
      wlk_roff = PSG_V_OSC;
    wlk_ra = {pc_ch, 1'b0, wlk_roff};

    if (state_lp_we) begin
      wlk_wa = {pc_ch, (pph == PPH_W'(PLAST - 1)) ? PSG_V_OSC + 5'd5
                                              : PSG_V_OSC + 5'd4};
      wlk_wd = (pph == PPH_W'(PLAST - 1)) ? s_lp[15:0] : `PSG_OSC_W14;
    end else begin
      wlk_wa = {pc_ch, PSG_V_OSC + 5'(s_stw)};
      wlk_wd = sosc_wd;
    end
  end

  // ---- Capture-action schedule ----
  // Control-ROM bits name actions, not absolute phases. pph_nxt prefetches the
  // synchronous word consumed on the next cycle.
  localparam int
      CAP_W0 = 0, CAP_W1 = 1, CAP_W2 = 2, CAP_W3 = 3,
      CAP_W4 = 4, CAP_W5 = 5, CAP_W6 = 6, CAP_W15 = 7,
      CAP_W26 = 8, CAP_W27 = 9, CAP_W40 = 10, CAP_W51 = 11,
      CAP_W75 = 12, CAP_W84 = 13;
  wire [PPH_W-1:0] pph_nxt = ctrl_stall ? pph
                         : (!prun || pph == PPH_W'(PLAST)) ? PPH_W'(0) : pph + PPH_W'(1);
  always_comb ctrl_addr = 8'd144 + 8'(pph_nxt);

  // Single-clock multiplication needs wider action spacing than the compact
  // multi-pumped schedule. This elaboration-only decoder supplies that
  // spacing when MULTIPUMP=0. Its return value is the capture-action mask for
  // the current phase. The iCE40 MULTIPUMP=1 netlist uses the shared control
  // ROM directly and contains none of this decode.
  function automatic logic [15:0] single_clock_cap(input logic [6:0] phase);
    begin
      single_clock_cap = 16'd0;
      case (phase)
        7'd29: single_clock_cap[CAP_W0]  = 1'b1;
        7'd30: single_clock_cap[CAP_W1]  = 1'b1;
        7'd31: single_clock_cap[CAP_W2]  = 1'b1;
        7'd32: single_clock_cap[CAP_W3]  = 1'b1;
        7'd33: single_clock_cap[CAP_W4]  = 1'b1;
        7'd34: single_clock_cap[CAP_W5]  = 1'b1;
        7'd35: single_clock_cap[CAP_W6]  = 1'b1;
        7'd40: single_clock_cap[CAP_W15] = 1'b1;
        7'd46: single_clock_cap[CAP_W26] = 1'b1;
        7'd47: single_clock_cap[CAP_W27] = 1'b1;
        7'd54: single_clock_cap[CAP_W40] = 1'b1;
        7'd60: single_clock_cap[CAP_W51] = 1'b1;
        7'd61: single_clock_cap[CAP_W75] = 1'b1;
        7'd65: single_clock_cap[CAP_W84] = 1'b1;
        default: ;
      endcase
    end
  endfunction

  wire [15:0] scheduled_cap = MULTIPUMP ? ctrl_q : single_clock_cap(7'(pph));
  wire [15:0] cap = (pph == PPH_W'(0) || ctrl_stall) ? 16'd0 : scheduled_cap;

  wire nz_req_old  = !REALTIME_PREVIEW && !ctrl_stall
                       && (pph == PPH_W'(PNZ_OLD));
  wire nz_req_live = !REALTIME_PREVIEW && !ctrl_stall
                       && (pph == PPH_W'(PNZ_LIVE));
  // ---- Built-in waveform context and shared phase ALU ----
  // Context requests into psg_wave.
  assign iss_sec = REALTIME_PREVIEW ? (pph == PPH_W'(PWORK))
                                  : prun && cap[CAP_W1];
  assign iss_om  = REALTIME_PREVIEW ? 1'b0
                                  : prun && cap[CAP_W2];
  assign iss_os  = REALTIME_PREVIEW ? 1'b0
                                  : prun && cap[CAP_W3];

  assign dq_old_ctx = REALTIME_PREVIEW ? (pph == PPH_W'(PWORK + 5))
                                     : prun && cap[CAP_W5];

  wire [13:0] einc = s_eff_inc;

  // Compact secondary-phase approximation used only by preview.
  wire [16:0] preview_det_round = {4'b0, einc[13:1]} + 17'd255;
  wire [16:0] preview_det_wide =
      {4'b0, einc[13:1]} - {8'b0, preview_det_round[16:8]};
  wire [23:0] preview_v2inc =
      s_snd_wt ? {3'b0, einc, 7'b0} :
      (s_snd_wave == 3'd7) ? ({3'b0, einc, 7'b0} - {10'b0, einc}
                                        - {13'b0, einc[13:3]}
                                        - {15'b0, einc[13:5]}) :
      (s_ch_det == 2'd1)   ? {preview_det_wide[15:0], 8'b0} :
      (s_ch_det == 2'd2)   ? {2'b0, einc, 8'b0} :
                                  24'd0;
  wire v2_on = s_snd_wt || (s_snd_wave == 3'd7) || (s_ch_det != 0);

  // The phase ALU is shared with the full-schedule serial soft-add engine.
  logic [15:0] pha_a, pha_b;
  always_comb begin
    pha_a = s_phase;
    pha_b = {3'b0, einc[13:1]};
    if (dq_old_ctx) begin
      pha_a = s_old_phase;
      pha_b = {3'b0, s_old_inc[13:1]};
    end
  end
  wire [15:0] pha_y = pha_a + pha_b;

  logic [17:0] fold_a, fold_b;
  logic        fold_sub, fold_cin;

  wire [17:0] phase_alu_y =
      fold_a + (fold_sub ? ~fold_b : fold_b)
             + {17'b0, fold_sub | fold_cin};
  // ---- Wavetable fetch and interpolation ----
  // Wavetable samples are signed bytes in the selected SFX record. Full mode
  // reads adjacent points for interpolation; preview reads one point per arm.
  // All four fetch sites add the same 13-bit record base to a six-bit index,
  // so select the index and add once instead of building four adders under a
  // result mux. The +1 arms keep their six-bit wrap: incrementing before the
  // widen is exactly what the four separate spellings did, so this is exact by
  // construction and needs no bound on s_phase or q16. syn_use_q/syn_plus1
  // reproduce the original chain's a0 > a1 > a2 > a3 priority - that ordering
  // is the only place this transform could silently go wrong.
  wire syn_a0 = REALTIME_PREVIEW ? (pph == PPH_W'(PWORK)) : cap[CAP_W0];
  wire syn_a1 = !REALTIME_PREVIEW && cap[CAP_W1];
  wire syn_a2 = (REALTIME_PREVIEW ? (pph == PPH_W'(PWORK + 1)) : iss_om) && v2_on;
  wire syn_a3 = !REALTIME_PREVIEW && iss_os && v2_on;
  wire syn_use_q = !syn_a0 && !syn_a1 && (syn_a2 || syn_a3);
  wire syn_plus1 = (!syn_a0 && syn_a1)
                || (!syn_a0 && !syn_a1 && !syn_a2 && syn_a3);
  wire [5:0] syn_ix = (syn_use_q ? q16[15:10] : s_phase[15:10])
                    + (syn_plus1 ? 6'd1 : 6'd0);

  always_comb begin
    syn_rd   = 1'b0;
    syn_addr = 13'd0;
    if (prun && !ctrl_stall && s_snd_wt && play_bits[pc_ch]
        && (syn_a0 || syn_a1 || syn_a2 || syn_a3)) begin
      syn_rd   = 1'b1;
      syn_addr = s_snd_wtb + {7'b0, syn_ix};
    end
  end

  wire signed [17:0] z_noise =
      (s_ch_buzz && !s_ch_noiz)
        ? $signed({{2{s_brown[12]}}, s_brown, 3'b0})
        : nz_z;
  wire signed [17:0] z_new_c =
      (!s_snd_wt && s_snd_wave == 3'd6) ? z_noise
    : s_snd_wt ? (smp_a + tzs(smp_b, 2'd1))
               : (smp_a + smp_b);
  wire signed [17:0] z_old_c = smp_b;

  // Linear interpolation deltas and ten-bit phase fractions for the two
  // oscillator arms.
  wire signed [8:0] wt_delta_base = cap[CAP_W4]
                                  ? $signed(smp_a[8:0])
                                  : $signed(smp_b[8:0]);
  wire signed [8:0] wt_d =
      $signed({wt_x1[7], wt_x1}) - wt_delta_base;
  wire signed [19:0] wt_mag = $signed({1'b0, m_res[20:2]});
  wire signed [19:0] wt_op = wt_mag ^ $signed({20{mxs_new}});
  wire signed [17:0] wt_base = cap[CAP_W26] ? smp_b : smp_a;
  wire signed [19:0] wt_sum = $signed({wt_base[9:0], 10'b0})
                            + wt_op + $signed({19'b0, mxs_new});
  wire signed [17:0] wt_z = 18'(wt_sum >>> 3);
  // ---- Live and preceding-arm pitched noise ----
  // Pitched-noise recurrence. lfsr supplies the held sample and random step;
  // lfsr2 supplies the independent kick and previous-arm step.
  wire  [12:0] nz_dp   = einc[13:1];

  wire  [7:0] nz_adv = {lfsr[7] ^ lfsr[6], lfsr[8] ^ lfsr[7],
                        lfsr[9] ^ lfsr[8], lfsr[10] ^ lfsr[9],
                        lfsr[11] ^ lfsr[10], lfsr[12] ^ lfsr[11],
                        lfsr[13] ^ lfsr[12], lfsr[14] ^ lfsr[13]};
  wire  signed [8:0] nz_rand = $signed({nz_adv[7], nz_adv});

  wire  [16:0] nz_j = {1'b0, nz_dp, 3'b0} + 17'd1120;

  wire  [12:0] nz_g       = {lfsr[14:7], lfsr[4:0]};
  // g[12] alone rejects: 3*4096 exceeds the largest dp+497.  In the remaining
  // half-domain dp+497-3*g is [-11788,8688], so its sign is exact in 15 bits.
  wire signed [14:0] nz_kick_delta =
      $signed({2'b0, nz_dp}) + 15'sd497
      - $signed({1'b0, nz_g[11:0], 1'b0})
      - $signed({2'b0, nz_g[11:0]});
  wire         nz_kick_en = !nz_g[12] && !nz_kick_delta[14];

  wire signed [11:0] nz_t11  = $signed({{2{~lfsr2[12]}}, lfsr2[11:2]});
  wire signed [11:0] nz_draw = nz_t11 - (nz_t11 >>> 3) - (nz_t11 >>> 6);
  wire        [2:0]  nz_q    = s_eff_a[10:8];
  wire signed [14:0] nz_kick_m =
      (nz_q[2] ? (15'(nz_draw) <<< 2) : 15'sd0)
    + (nz_q[1] ? (15'(nz_draw) <<< 1) : 15'sd0)
    + (nz_q[0] ?  15'(nz_draw)        : 15'sd0);
  wire signed [17:0] nz_kick = nz_kick_en ? 18'(nz_kick_m) : 18'sd0;

  wire  signed [17:0] nz_pre =
      $signed({{2{s_noise_lp[15]}}, s_noise_lp})
      + (nz_tog ? 18'(nz_step) : 18'sd0)
      + nz_kick;
  function automatic logic signed [15:0] noise_clamp(
      input logic signed [17:0] value);
    logic over, under;
    begin
      // The exact out-of-range boundaries are +6144 and -6144 (18'h3e800).
      // Decode their prefixes directly instead of building signed comparators.
      over = !value[17] && ((|value[16:13]) || (&value[12:11]));
      under = value[17]
              && (!(&value[16:13])
                  || (!value[12] && (!value[11] || !(|value[10:0]))));
      noise_clamp = over ? 16'sd6143
                  : under ? -16'sd6143 : value[15:0];
    end
  endfunction
  wire signed [15:0] noise_next = noise_clamp(nz_pre);

  // The full-mode live and old noise scales are consumed on disjoint phases:
  // live at W4, old at W15/W27. Select their registered payload before one
  // exact x68/x80 shift-add tree. PREVIEW and wavetable W27 remain live.
  wire nz_scale_old = !REALTIME_PREVIEW && !s_snd_wt
      && (cap[CAP_W15] || cap[CAP_W27]);
  wire signed [17:0] nz_scale_value = nz_scale_old
      ? nz_old_out_r : nz_out_r;
  wire nz_scale_hi = nz_scale_old ? s_old_inc[13] : einc[13];
  wire signed [17:0] nz_scale_r6 = nz_scale_value >>> 6;
  wire signed [17:0] nz_scale_z = nz_scale_hi
      ? ((nz_scale_r6 <<< 6) + (nz_scale_r6 <<< 2))
      : ((nz_scale_r6 <<< 6) + (nz_scale_r6 <<< 4));
  wire signed [17:0] nz_z = nz_scale_z;
  // ---- Transition detection and secondary-increment service ----
  // A changed sounding tuple starts a 64-sample previous-to-current blend.
  wire blend_restart =
      play_bits[pc_ch]
      && (s_eff_inc != s_last_inc || g_live != s_last_G
          || s_snd_wave != s_last_wave
          || s_ch_det != last_mode_r
          || s_ch_rev != last_rev_r
          || s_ch_buzz != last_alt_r

          || (s_eff_a != 0 && s_snd_wave == 3'd6 && !s_snd_wt
              && !s_ch_buzz && nz_tick_r));
  wire  [13:0] nz2_inc = blend_restart ? s_last_inc : s_old_inc;
  wire  [12:0] nz2_dp  = nz2_inc[13:1];

  // Every full-schedule secondary increment is floor(K*dp/256). Evaluate the
  // live and just-audible old tuples in the two five-phase windows already
  // occupied by the independent multi-pumped noise products. On a transition
  // restart the old context must use the tuple W0 is about to snapshot, just
  // as the preceding-noise request above does.
  function automatic logic [8:0] dq_coeff(
      input logic wt, input logic [2:0] wave, input logic [1:0] mode);
    begin
      if (wt)
        dq_coeff = 9'd256;
      else if (wave == 3'd0)
        dq_coeff = (mode == 2'd1) ? 9'd193
                 : (mode == 2'd2) ? 9'd384 : 9'd256;
      else if (wave == 3'd7)
        dq_coeff = (mode == 2'd1) ? 9'd250
                 : (mode == 2'd2) ? 9'd508 : 9'd254;
      else
        dq_coeff = (mode == 2'd0) ? 9'd256 : 9'd255;
    end
  endfunction

  wire dq_start = !REALTIME_PREVIEW && prun && !ctrl_stall
                  && (pph == PPH_W'(PNZ_OLD) || pph == PPH_W'(PNZ_LIVE));
  wire dq_start_old = pph == PPH_W'(PNZ_LIVE);
  wire [13:0] dq_old_inc_now = blend_restart ? s_last_inc : s_old_inc;
  wire [2:0] dq_old_wave_now = blend_restart ? s_last_wave : s_old_wave;
  wire [1:0] dq_old_mode_now = blend_restart ? last_mode_r : old_mode_r;
  wire [2:0] dq_start_wave = dq_start_old ? dq_old_wave_now : s_snd_wave;
  wire [1:0] dq_start_mode = dq_start_old ? dq_old_mode_now : s_ch_det;
  wire [8:0] dq_start_k = dq_coeff(s_snd_wt, dq_start_wave, dq_start_mode);
  wire [13:0] dq_result;
  wire dq_done, dq_busy, dq_start_ready;
  logic [13:0] dq_live_r;

  psg_dqsvc u_dq(
    .clk(clk), .reset(reset),
    .start(dq_start),
    .live_a(s_eff_inc[13:1]), .old_a(dq_old_inc_now[13:1]),
    .start_k(dq_start_k), .start_old(dq_start_old),
    .result(dq_result), .done(dq_done),
    .busy(dq_busy), .start_ready(dq_start_ready));

  // The first terminal edge is also the fixed phase-24 old-context request.
  // Capture that live result because the chained request overwrites the
  // recurrence.  The final old result remains in the idle recurrence through
  // its only consumer at W5, so it needs no duplicate walker register.
  always_ff @(posedge clk)
    if (dq_start && dq_start_old)
      dq_live_r <= dq_result;

  wire [16:0] dq_visit = REALTIME_PREVIEW ? dq17
                       : {3'b0, dq_old_ctx ? dq_result : dq_live_r};

`ifndef SYNTHESIS
  logic dq_live_valid, dq_old_valid;
  always_ff @(posedge clk) begin
    if (reset || (prun && !ctrl_stall && pph == 0)) begin
      dq_live_valid <= 1'b0;
      dq_old_valid <= 1'b0;
    end else if (dq_done) begin
      if (dq_start && dq_start_old) dq_live_valid <= 1'b1;
      else                          dq_old_valid <= 1'b1;
    end
    if (!reset && dq_start && !dq_start_ready)
      $fatal(1, "psg_walk: dq request dropped at pph %0d", pph);
    if (!reset && !REALTIME_PREVIEW && prun && cap[CAP_W5]
        && !dq_old_valid)
      $fatal(1, "psg_walk: old dq result not ready at W5");
    if (!reset && !REALTIME_PREVIEW && prun && cap[CAP_W6]
        && !dq_live_valid)
      $fatal(1, "psg_walk: live dq result not ready at W6");
  end
`endif

  wire  [7:0]  nz2_adv = {lfsr2[7] ^ lfsr2[6], lfsr2[8] ^ lfsr2[7],
                          lfsr2[9] ^ lfsr2[8], lfsr2[10] ^ lfsr2[9],
                          lfsr2[11] ^ lfsr2[10], lfsr2[12] ^ lfsr2[11],
                          lfsr2[13] ^ lfsr2[12], lfsr2[14] ^ lfsr2[13]};
  wire  signed [8:0]  nz2_rand = $signed({nz2_adv[7], nz2_adv});

  wire [23:0]        nz_m   = m_res[27:4];
  wire signed [17:0] nz_mag = $signed({2'b0, nz_m[23:8]});
  wire signed [17:0] nz_pos = nz_mag;
  // Round toward zero on the negative branch: -(m + |frac|) == ~m + !|frac|
  // for the zero-extended magnitude, so one complemented limb replaces the
  // negate-after-increment carry chain.
  wire signed [17:0] nz_neg = ~nz_mag + 18'(!(|nz_m[7:0]));

  // Previous and live noise steps have the same multiply shape and occur on
  // disjoint phases, so select their operands before the shared request arm.
  wire  [12:0]       nz_dp_req  = nz_req_old ? nz2_dp : nz_dp;
  wire  [16:0]       nz_j_req   = {1'b0, nz_dp_req, 3'b0} + 17'd1120;
  wire signed [8:0]  nz_rand_req = nz_req_old ? nz2_rand : nz_rand;
  wire [8:0]         nz_mag_req = nz_rand_req[8] ? 9'(-nz_rand_req)
                                                 : 9'(nz_rand_req);

  wire signed [25:0]   nz_mul_pv =
      ($signed({1'b0, nz_j}) * nz_rand) >>> 8;

  wire signed [17:0]   nz_step = REALTIME_PREVIEW ? nz_mul_pv[17:0]
                               : (nz_rand[8] ? nz_neg : nz_pos);

  // On a restart the old arm becomes the just-audible tuple. Select its noise
  // context from that tuple immediately; using s_old_wave for this W0 edge
  // lets the pre-restart noise continuation overwrite a newly snapped phaser
  // phase and creates a one-tick-late discontinuity.
  wire old_nz_on = REALTIME_PREVIEW ? 1'b0
                 : blend_restart ? (s_last_wave == 3'd6 && !last_alt_r)
                                 : (s_old_wave == 3'd6 && !old_alt_r);
  wire [15:0] old_nz_seed_base =
      (blend_restart || nz_tick_r) ? 16'(s_noise_lp) : s_old_phase;
  wire signed [17:0] nz_old_seed =
      $signed({{2{old_nz_seed_base[15]}}, old_nz_seed_base}) + nz_kick;
  wire signed [17:0] nz_old_pre =
      $signed({{2{s_old_phase[15]}}, s_old_phase})
      + (nz_tog ? {mx_old[16], mx_old} : 18'sd0);
  wire signed [15:0] nz_old_next = noise_clamp(nz_old_pre);
  wire signed [17:0] nz_old_z = nz_scale_z;
  wire signed [17:0] z_old_sel = old_nz_r_on ? nz_old_z : z_old_c;
  // ---- Gain, reverb, crossfade, and dampen datapath ----
  // g* builds note gain; mx* holds signed arms; cmb* applies the reverb comb.
  wire g_boost = (s_ch_det != 2'd0) && !s_snd_wt
                 && !(s_snd_wave[2] & s_snd_wave[1]);
  wire [11:0] g_a = g_boost ? ({1'b0, s_eff_a} + {3'b0, s_eff_a[10:2]})
                            : {1'b0, s_eff_a};
  wire [11:0] g_live = g_a + {1'b0, g_a[11:1]};

  // The gain-series limb is dead after W51; W84 reuses the same 17-bit
  // register for the final filtered sample consumed by the store/fold tail.
  logic signed [16:0] gz_filt_r;
  logic [9:0]  ring_rp;

  logic        mx_aud;
  logic        mxs_new, mxs_old;

  logic signed [16:0] mx_new, mx_old;
  wire [25:0] gz_171_twice =
      m_res[28:3] + {9'b0, gz_filt_r};
  wire [24:0] gz_171 = gz_171_twice[25:1];
  wire [33:0] gz_q3acc =
      {m_res[27:3], 9'b0} + {9'b0, gz_171};

  wire [16:0] gz_scaled = (!s_snd_wt && s_snd_wave == 3'd6)
                            ? {1'b0, gz_filt_r[16:1]}
                            : {2'b0, gz_q3acc[33:19]};
  wire [16:0] gz_old_scaled = (s_old_wave == 3'd6)
                            ? {1'b0, gz_filt_r[16:1]}
                            : {2'b0, gz_q3acc[33:19]};
  wire signed [16:0] mx_new_w51 =
      mxs_new ? -$signed(gz_scaled) : $signed(gz_scaled);
  wire signed [16:0] mx_old_w51 =
      mxs_old ? -$signed(gz_old_scaled) : $signed(gz_old_scaled);

  wire signed [16:0] mx_old_eff =
      s_snd_wt ? ((s_old_G == 12'd0) ? 17'sd0 : mx_new) : mx_old;

  // Reverb combs current and previous arms independently before crossfade;
  // dampen then filters the blended sample.
  logic signed [15:0] ring_q;
  logic signed [15:0] ring_q_old;
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

  wire signed [16:0] blend_y =
      (bl_cnt == 7'd64) ? cmb_new : 17'(bl_acc_tz >>> 6);

  wire signed [18:0] dmp_mul = (s_ch_damp == 2'd1)
                                 ? {{2{s_lp[16]}}, s_lp}
                                 : ({s_lp, 2'b0} - {{2{s_lp[16]}}, s_lp});
  wire signed [18:0] dmp_acc = {{2{blend_y[16]}}, blend_y} + dmp_mul;
  wire signed [18:0] dmp_tz =
      dmp_acc + (dmp_acc[18] ? ((s_ch_damp == 2'd1) ? 19'sd1 : 19'sd3)
                             : 19'sd0);
  wire signed [16:0] dmp_y = (s_ch_damp == 2'd1) ? dmp_tz[17:1]
                                                 : dmp_tz[18:2];
  wire signed [16:0] filt_y = (s_ch_damp != 2'd0) ? dmp_y : blend_y;

  wire [22:0] bl_res = m_res[28:6];

`ifndef SYNTHESIS
  wire [17:0] blend_mag_check = blend_diff[17]
                                    ? 18'(-blend_diff) : 18'(blend_diff);
  wire [23:0] blend_prod_check = blend_mag_check * bl_cnt[5:0];
`endif
  // ---- Shared multiplier request schedule ----
  // Full-schedule multiplier requests are grouped by operand shape:
  // noise step, wavetable lerp, gain pass, reciprocal /3 limb, and crossfade.
  always_comb begin
    wmul_start = 1'b0;
    wmul_a     = 25'sd0;
    wmul_b     = 12'd0;
    wmul_mode  = 2'd0;
    wmul_short = 1'b0;
    if (prun && !m_busy) begin
      // Preview uses the local product below and never requests this service.
      if (REALTIME_PREVIEW) begin

      end else begin

        (* parallel_case *) case (1'b1)
          (nz_req_old || nz_req_live): begin
            wmul_start = 1'b1;
            wmul_a = {8'b0, nz_j_req};
            wmul_b = {3'b0, nz_mag_req};
            wmul_mode = 2'd0;
          end

          ((cap[CAP_W4] || cap[CAP_W15]) && s_snd_wt): begin
            wmul_start = 1'b1;
            wmul_a = 25'(wt_d);
            wmul_b = cap[CAP_W4] ? {2'b0, wt_pf} : {2'b0, wt_qf};
            wmul_mode = 2'd1;
          end

          ((cap[CAP_W4] && !s_snd_wt) || cap[CAP_W27]): begin
            wmul_start = 1'b1;
            wmul_a = (cap[CAP_W27] && !s_snd_wt) ? 25'(z_old_sel)
                                                 : 25'(z_new_c);
            wmul_b = (cap[CAP_W27] && !s_snd_wt) ? 12'(s_old_G)
                                                 : 12'(g_live);
            wmul_mode = 2'd2;
          end

          ((cap[CAP_W15] && !s_snd_wt) || cap[CAP_W40]): begin
            wmul_start = 1'b1;
            wmul_a = {8'b0, m_res[26:10]};
            wmul_b = 12'd341;
            wmul_mode = 2'd3;
          end
          cap[CAP_W75]: if (bl_cnt != 7'd64) begin
            wmul_start   = 1'b1;
            wmul_a = 25'(blend_diff);
            wmul_b = {6'b0, bl_cnt[5:0]};
            wmul_mode = 2'd1;
            wmul_short = 1'b1;
          end
          default: ;
        endcase
      end
    end
  end
  // ---- Compact PREVIEW-only sample and transition path ----
  // Preview keeps its local sample-by-volume multiply; the full schedule uses
  // only the shared multiplier above.
  wire [20:0]  pv_mag   = z_new_c[17] ? (21'd0 - 21'(z_new_c)) : 21'(z_new_c);
  wire [28:0]  pv_full  = pv_mag * {14'b0, s_eff_a[10:4]};
  wire [15:0]  pv_slice = pv_full[22:7];
  logic [15:0] pv_prod_r;

  wire signed [16:0] mix_prod =
      REALTIME_PREVIEW
        ? (mxs_new ? -$signed({1'b0, pv_prod_r})
                   :  $signed({1'b0, pv_prod_r}))
        : {gz_filt_r[15], gz_filt_r[15:0]};
  wire signed [17:0] n_contrib = {mix_prod[16], mix_prod};

  wire signed [17:0] mix_leaf = mx_aud ? n_contrib : 18'sd0;

  // PREVIEW keeps a compact transition signature in otherwise dead oscillator
  // record bits and crossfades from the last emitted leaf for 32 samples. The
  // full renderer's multiplier-backed two-oscillator blend is too long for the
  // console-clock preview budget; this bounded form is elaborated out of full
  // mode and preserves natural waveform motion on the new arm.
  wire preview_trigger = REALTIME_PREVIEW
      && clr_tog[pc_ch] != clr_ack_pv[pc_ch];
  wire preview_zero_edge = s_eff_a == 0 && old_q0[4:0] == 0 && s_lp != 0;
  // PREVIEW's gain multiply consumes s_eff_a[10:4] (bit 11 is unreachable
  // for the published 0..7 note-volume range). All seven bits are audible:
  // dropping either low bit aliases adjacent effect-volume steps and creates
  // tick-edge snaps.
  wire preview_restart = REALTIME_PREVIEW && play_bits[pc_ch]
      && (({s_eff_a[10:4], s_snd_wave}
           != {s_old_G[6:0], old_q0[7:5]})
          || preview_zero_edge || preview_trigger);
  wire [4:0] preview_alpha = preview_restart ? 5'd0 : old_q0[4:0];
  wire signed [17:0] preview_old_leaf = {s_lp[16], s_lp};
  wire signed [18:0] preview_diff =
      $signed({mix_leaf[17], mix_leaf})
      - $signed({preview_old_leaf[17], preview_old_leaf});
  wire signed [24:0] preview_blend_prod =
      preview_diff * $signed({1'b0, preview_alpha});
  wire signed [18:0] preview_blend_wide =
      $signed({preview_old_leaf[17], preview_old_leaf})
      + 19'($signed(preview_blend_prod) >>> 5);
  wire signed [17:0] preview_blend_leaf = preview_blend_wide[17:0];
  wire signed [17:0] fold_leaf = REALTIME_PREVIEW
      ? (mx_aud ? {gz_filt_r[16], gz_filt_r} : 18'sd0) : mix_leaf;

  localparam signed [22:0] SA_TH = 23'sd24576;
  // ---- Eight-leaf PICO-8 soft-add reduction ----
  // PICO-8 soft addition: linear inside +/-24576, then 5:1 compression with
  // nearest rounding. Preview evaluates it combinationally.
  function automatic signed [17:0] soft_add(input signed [17:0] a,
                                            input signed [17:0] b);
    logic signed [18:0] s;
    logic over, under;
    logic [17:0] ex, t0, t1, t2, q4, rem5;
    logic [3:0]  rem;
    begin
      s     = $signed({a[17], a}) + $signed({b[17], b});
      over  = (s >=  19'sd24576);
      under = (s <= -19'sd24576);
      ex    = over  ? 18'(s - 19'sd24576)
            : under ? 18'(-19'sd24576 - s)
                    : 18'd0;
      t0    = {1'b0, ex[17:1]} + {2'b0, ex[17:2]};
      t1    = t0 + {4'b0, t0[17:4]};
      t2    = t1 + {8'b0, t1[17:8]};
      q4    = {2'b0, t2[17:2]};
      rem5  = ex - {t2[17:2], 2'b00} - q4;
      rem   = rem5[3:0];

      q4    = q4 + 18'((rem >= 4'd5) ? 1 : 0);
      soft_add = over  ?  18'(18'(SA_TH) + q4)
               : under ? -18'(18'(SA_TH) + q4)
                       :  18'(s);
    end
  endfunction

  logic signed [17:0] sa_hold;
  logic signed [17:0] l1[0:3];
  logic signed [17:0] l2a, l2b;
  logic [1:0]  mxs;

  // Full mode evaluates the same function with one shared 18-bit ALU. fstk is
  // the three-level reduction stack; fmc is the current arithmetic microstep.
  logic signed [17:0] fstk[0:2];
  logic signed [15:0] dry16_pv;
  assign dry16 = REALTIME_PREVIEW ? dry16_pv : fstk[0][15:0];
  logic [2:0]  fsel;
  logic [1:0]  fpend;
  logic        ffin;
  logic        f_under;

  // Exact fold quotient after a base-256 split:
  //   x/5 = 51*(x>>8) + ((x>>8) + x[7:0])/5.
  // The second term has a 0..414 domain, so one EBR evaluates it directly
  // without carrying quotient-correction state through the fold pipeline.
  (* ram_style = "block" *) logic [6:0] fdiv5[0:511];
  logic [6:0] fdiv5_q;
  wire [8:0] fdiv5_addr = {1'b0, phase_alu_y[15:8]}
                           + {1'b0, phase_alu_y[7:0]};
  initial for (int i = 0; i < 512; i++) fdiv5[i] = 7'(i / 5);

  always_ff @(posedge clk)
    if (!REALTIME_PREVIEW
        && ((fmc == 4'd2 && !phase_alu_y[17])
            || (fmc == 4'd3 && !phase_alu_y[17])))
      fdiv5_q <= fdiv5[fdiv5_addr];

  logic signed [17:0] fda, fdb;
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

  always_comb begin
    fold_a = 18'd0; fold_b = 18'd0; fold_sub = 1'b0; fold_cin = 1'b0;
    case (fmc)
      4'd1:  begin fold_a = fda;
                   fold_b = fdb; end
      4'd2:  begin fold_a = fda;
                   fold_b = 18'(SA_TH); fold_sub = 1'b1; end
      4'd3:  begin fold_a = 18'(-SA_TH);
                   fold_b = fda; fold_sub = 1'b1; end
      4'd4:  begin fold_a = {10'b0, fda[15:8]};
                   fold_b = {9'b0, fda[15:8], 1'b0}; end
      4'd5:  begin fold_a = fda;
                   fold_b = {fda[13:0], 4'b0}; end
      4'd6:  begin fold_a = fda;
                   fold_b = {11'b0, fdiv5_q}; end
      4'd7:  begin fold_a = 18'(SA_TH);
                   fold_b = fda; end
      4'd8:  begin fold_a = 18'd0;
                   fold_b = fda; fold_sub = 1'b1; end
      default: ;
    endcase
  end
  // ---- Optional reverb history memory ----
  // Per-slot 732-sample history. Level 1 taps 366 samples back; level 2 uses
  // the write position, which is read before it is overwritten.
  generate
  if (REVERB) begin : g_ring
    logic [15:0] ringm[0:PSG_NV * 732 - 1];
    logic [15:0] ring_rd;
    initial for (int i = 0; i < PSG_NV * 732; i++) ringm[i] = 16'd0;

    // The two reads must complete before W75 snapshots blend_diff. Anchor them
    // to the store window so the dependency is explicit in both schedules:
    // phases 57/58/59 in single-clock mode and 52/53/54 in compact
    // multi-pumped mode.
    wire [1:0] ring_lvl = (pph == PPH_W'(PSTOR + 6)) ? s_ch_rev : old_rev_r;
    wire [9:0] ring_tap =
        (ring_lvl == 2'd1)
          ? ((ring_rp >= 10'd366) ? ring_rp - 10'd366
                                  : ring_rp + 10'd366)
          : ring_rp;
    always_ff @(posedge clk) begin
      if (prun && !ctrl_stall
          && (pph == PPH_W'(PSTOR + 6) || pph == PPH_W'(PSTOR + 7)))
        ring_rd <= ringm[{4'b0, pc_ch} * 732 + {3'b0, ring_tap}];
      if (prun && !ctrl_stall && pph == PPH_W'(PSTOR + 7))
        ring_q <= $signed(ring_rd);
      if (prun && !ctrl_stall && pph == PPH_W'(PSTOR + 8))
        ring_q_old <= $signed(ring_rd);
      if (prun && !ctrl_stall && pph == PPH_W'(PLAST - 1)
          && play_bits[pc_ch])
        ringm[{4'b0, pc_ch} * 732 + {3'b0, ring_rp}] <= gz_filt_r[15:0];
    end
  end else begin : g_noring
    always_comb ring_q = 16'sd0;
    always_comb ring_q_old = 16'sd0;
  end
  endgenerate

  // ---- Visit actions shared by PREVIEW and full mode ----
  // Advance noise and filter state once for the current slot, with trigger
  // clear requests taking priority over accumulated filter state.
  task noise_filt_step(input logic run);
    logic clr;
    logic clr_token;
    clr_token = REALTIME_PREVIEW ? clr_tog[pc_ch] : s_clr_tog;
    clr = (clr_token
           != (REALTIME_PREVIEW ? clr_ack_pv[pc_ch] : s_clr_ack));
    if (run) begin
      if (s_ch_noiz || s_phase[15:12] != s_nz_ph) begin
        s_nz_ph <= s_phase[15:12];
        s_nz_hold <= $signed(lfsr[7:0]);
      end
    end
    if (clr) begin
      if (!REALTIME_PREVIEW)
        s_clr_ack <= clr_token;
      s_lp <= 0;
    end
    if (run || clr)
      s_brown <= clr ? 13'sd0
                     : s_brown - {{5{s_brown[12]}}, s_brown[12:5]}
                               + $signed({{5{lfsr[7]}}, lfsr[7:0]});
    if ((run && s_snd_wave == 3'd6) || clr) begin
      s_noise_lp <= clr ? 16'sd0 : noise_next;

      nz_out_r   <= clr ? 18'sd0 : nz_pre;
    end
    if (!REALTIME_PREVIEW) begin

      old_nz_r_on <= run && old_nz_on;
      if (run && old_nz_on) begin

        s_old_phase <= nz_old_seed[15:0];
      end
    end
  endtask

  // A hidden music slot still renders and advances, but contributes zero while
  // its foreground partner is playing.
  task stage_leaf();
    mxs_new <= z_new_c[17];
    mx_aud  <= play_bits[pc_ch]
               & ~(is_mus(pc_ch) & play_bits[{1'b0, pc_ch[1:0]}]);
  endtask

  // Even slots stage a leaf; odd slots launch the next reduction node.
  task fold_launch();
    if (REALTIME_PREVIEW) begin

      if (pc_ch[0] == 1'b0) sa_hold        <= fold_leaf;
      else                  l1[pc_ch[2:1]] <= soft_add(sa_hold, fold_leaf);
    end else if (pc_ch[0] == 1'b0)
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
  endtask
  // ---- Sequential walk, writeback, and fold controller ----
  // Walk controller, streamed state load/store, synthesis actions, and fold
  // completion. Datapath registers are overwritten before use; reset initializes
  // only control/validity and persistent oscillator state.
  always_ff @(posedge clk) begin
    if (reset) begin
      lfsr <= 15'h2A5F;
      lfsr2 <= 15'h5117;
      spar_last <= 0;
      nz_tick_r <= 0;
      nz_out_r <= '0;
      nz_old_out_r <= '0;
      old_nz_r_on <= 0;
      nz_tog <= 0;
      prun <= 0;
      pc_ch <= 0;
      pph <= 0;
      if (REALTIME_PREVIEW)
        clr_ack_pv <= 0;
      fmc <= 0;
      mxs <= 0;
      fpend <= 0;
      ffin <= 0;
      dry_valid <= 0;

    end else begin
      dry_valid <= 0;

      // Preview finishes the three remaining reduction nodes after slot 7.
      if (REALTIME_PREVIEW) begin
        case (mxs)
          2'd1: begin l2a <= soft_add(l1[0], l1[1]); mxs <= 2'd2; end
          2'd2: begin l2b <= soft_add(l1[2], l1[3]); mxs <= 2'd3; end
          2'd3: begin
            dry16_pv  <= 16'($signed(soft_add(l2a, l2b)));
            dry_valid <= 1;
            mxs       <= 2'd0;
          end
          default: ;
        endcase
      end

      // Full mode serializes each soft-add node through phase_alu_y.
      if (!REALTIME_PREVIEW && fmc != 4'd0) begin
        case (fmc)
          4'd1:  begin fstk[fdsti] <= phase_alu_y[17:0]; fmc <= 4'd2; end
          4'd2:  begin
            if (!phase_alu_y[17]) begin
              fstk[fdsti] <= phase_alu_y[17:0];
              f_under <= 1'b0;
              fmc <= 4'd4;
            end else
              fmc <= 4'd3;
          end
          4'd3:  begin
            if (!phase_alu_y[17]) begin
              fstk[fdsti] <= phase_alu_y[17:0];
              f_under <= 1'b1;
              fmc <= 4'd4;
            end else
              fmc <= 4'd9;
          end
          4'd4, 4'd5, 4'd6: begin
            fstk[fdsti] <= phase_alu_y[17:0];
            fmc <= fmc + 1;
          end
          4'd7: begin
            fstk[fdsti] <= phase_alu_y[17:0];
            fmc <= f_under ? 4'd8 : 4'd9;
          end
          4'd8: begin fstk[fdsti] <= phase_alu_y[17:0]; fmc <= 4'd9; end
          default: begin
            if (fpend != 2'd0) begin
              fpend <= fpend - 1;
              fsel <= (fsel == 3'd2) ? 3'd4 : 3'd3;
              fmc <= 4'd1;
            end else begin
              fmc <= 4'd0;
              if (ffin) begin
                ffin <= 0;
                dry_valid <= 1;
              end
            end
          end
        endcase
      end

      // Noise alternation and parameter-bank edge detection are sample based.
      if (sample_en) begin
        nz_tog    <= ~nz_tog;
        nz_tick_r <= spar_bank != spar_last;
        spar_last <= spar_bank;
      end

      // Full mode relies on the hardware clock budget and starts every sample.
      // Preview drops a start if its compact walk or reduction is still active.
      if (sample_en && !(REALTIME_PREVIEW && (prun || fold_busy))) begin
        prun <= 1;
        pc_ch <= 0;
        pph <= 0;
        ring_rp <= (ring_rp == 10'd731) ? 10'd0 : ring_rp + 10'd1;
      end else if (prun && !ctrl_stall) begin

        // Consume synchronous oscillator-record reads.
        case (pph)
          PPH_W'(1): s_phase <= state_q;
          PPH_W'(2): {s_nz_hold, old_q0[7:0]} <= state_q;
          PPH_W'(3): s_phase2[15:0] <= state_q;
          PPH_W'(4): if (REALTIME_PREVIEW) begin
                  s_old_G[3:0] <= state_q[15:12];
                  s_nz_ph <= state_q[11:8];
                  s_phase2[PH2_W-1:16] <= state_q[PH2_W-17:0];
                end
                else begin
                  s_clr_ack       <= state_q[15];
                  s_old_G[11:8]  <= state_q[13:10];
                  s_last_G[11:8] <= state_q[8:5];
                  s_nz_ph        <= state_q[4:1];
                  s_phase2[16] <= state_q[0];
                end
          PPH_W'(5): if (REALTIME_PREVIEW) begin
                  s_old_G[6:4] <= state_q[15:13];
                  s_brown <= state_q[12:0];
                end
                else
                  `PSG_OSC_W14 <= state_q;
          PPH_W'(6): if (REALTIME_PREVIEW)
                  s_lp <= {state_q[15], state_q};
                else
                  s_lp[15:0] <= state_q;
          PPH_W'(7): if (REALTIME_PREVIEW)
                   s_noise_lp <= state_q;
                else
                   s_old_phase <= state_q;
          PPH_W'(8): if (!REALTIME_PREVIEW)
                   `PSG_OSC_W17 <= state_q;
          PPH_W'(9): if (!REALTIME_PREVIEW) s_old_inc[8:0] <= state_q[15:7];
          PPH_W'(10): if (!REALTIME_PREVIEW)
                    {s_old_G[7:0], s_old_inc[13:9]}
                      <= {state_q[15:8], state_q[4:0]};
          PPH_W'(11): if (!REALTIME_PREVIEW)
                    {old_rev_r, last_rev_r, s_last_wave,
                     s_last_inc[13:9]} <= {state_q[14:8], state_q[4:0]};
          PPH_W'(12): if (!REALTIME_PREVIEW) s_last_inc[8:0] <= state_q[15:7];
          PPH_W'(13): if (!REALTIME_PREVIEW)
                    `PSG_OSC_W22 <= state_q[14:0];
          PPH_W'(14): if (!REALTIME_PREVIEW) s_noise_lp <= state_q;
          default: ;
        endcase
        // Consume the four active sounding-parameter words.
        case (pph)
          PPH_W'(PLOSC + 1):
            s_eff_inc[8:0] <= state_q[15:7];
          PPH_W'(PLOSC + 2):
            {s_snd_id, s_snd_wt, s_snd_wave, s_eff_inc[13:9]}
              <= {state_q[14:8], state_q[4:0]};
          PPH_W'(PLOSC + 3):
            {s_ch_damp, s_ch_rev, s_ch_det, s_ch_buzz,
             s_ch_noiz} <= state_q[13:6];
          PPH_W'(PLOSC + 4): begin
            s_eff_a <= state_q[10:0];
            if (!REALTIME_PREVIEW)
              s_clr_tog <= state_q[13];
          end
          default: ;
        endcase

        // Close this slot and advance to the next; slot 7 ends the walk.
        if (pph == PPH_W'(PLAST)) begin
          pph <= 0;

          if (pc_ch == PSG_VW'(PSG_NV-1)) begin
            prun <= 0;

            if (REALTIME_PREVIEW) mxs <= 2'd1;
          end
          pc_ch <= pc_ch + 1;
        end else
          pph <= pph + 1;

        // Compact preview actions are addressed directly by pph.
        if (REALTIME_PREVIEW) begin
          case (pph)

            PPH_W'(0): if (!play_bits[pc_ch]
                      && clr_tog[pc_ch] == clr_ack_pv[pc_ch]) begin
                    stage_leaf();

                    lfsr  <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};
                    lfsr2 <= {lfsr2[13:0], lfsr2[14] ^ lfsr2[10]};
                    pph <= PPH_W'(PFOLD);
                  end
            PPH_W'(PWORK): begin
              lfsr  <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};
              lfsr2 <= {lfsr2[13:0], lfsr2[14] ^ lfsr2[10]};
              if (play_bits[pc_ch] && s_eff_a != 0) begin
                s_phase <= s_phase + {3'b0, einc[13:1]};
                if (v2_on)
                  s_phase2 <= s_phase2 + PH2_W'(preview_v2inc);
              end else if (play_bits[pc_ch]) begin
                s_phase <= 0;
                s_phase2 <= 0;
              end
              noise_filt_step(play_bits[pc_ch] && s_eff_a != 0);
            end
            PPH_W'(PWORK + 1): begin
              smp_a <= s_snd_wt ? 18'($signed(seq_q)) : z_eval;
            end
            PPH_W'(PWORK + 2): begin
              smp_b <= s_snd_wt ? 18'($signed(seq_q)) : z_eval;
            end

            PPH_W'(PWORK + 3): begin
              pv_prod_r <= pv_slice;
              stage_leaf();
            end
            PPH_W'(PSTOR): begin
              if (preview_trigger)
                clr_ack_pv[pc_ch] <= clr_tog[pc_ch];
              gz_filt_r <= (preview_restart || old_q0[4:0] != 0)
                           ? preview_blend_leaf[16:0] : mix_leaf[16:0];
              if (preview_restart) begin
                old_q0[4:0] <= 5'd1;
                old_q0[7:5] <= s_snd_wave;
                s_old_G[6:0] <= s_eff_a[10:4];
              end else if (old_q0[4:0] != 0) begin
                if (old_q0[4:0] == 5'd31) begin
                  old_q0[4:0] <= 5'd0;
                  s_lp <= mix_leaf[16:0];
                end else
                  old_q0[4:0] <= old_q0[4:0] + 5'd1;
              end else
                s_lp <= mix_leaf[16:0];
            end
            PPH_W'(PFOLD): fold_launch();
            default: ;
          endcase
        end else begin

        // Full-schedule action decode comes from the prefetched control word.
        (* parallel_case *) case (1'b1)
          // Start the live arm and snapshot the preceding sounding tuple when
          // a 64-sample crossfade must restart.
          cap[CAP_W0]: begin

            lfsr  <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};
            lfsr2 <= {lfsr2[13:0], lfsr2[14] ^ lfsr2[10]};

            if (play_bits[pc_ch] && s_eff_a != 0) begin
              if (!s_snd_wt) begin
                s_phase <= pha_y;
              end else begin
                wt_pf <= s_phase[9:0];
                wt_qf <= q16[9:0];
              end
            end

            if (blend_restart) begin
              bl_cnt <= 7'd0;
              s_old_phase <= s_phase;
              old_q0 <= s_phase2[16:0];
              s_old_inc <= s_last_inc;
              s_old_G <= s_last_G;
              s_old_wave <= s_last_wave;
              old_mode_r <= last_mode_r;
              old_alt_r <= last_alt_r;
              old_rev_r <= last_rev_r;

              if (s_eff_a == 0) begin
                s_phase <= 0;
                s_phase2 <= 0;
              end
            end else if (bl_cnt != 7'd64)
              bl_cnt <= bl_cnt + 7'd1;
            noise_filt_step(play_bits[pc_ch] && s_eff_a != 0);
          end
          cap[CAP_W1]: begin

            if (old_nz_r_on) begin
              s_old_phase  <= nz_old_next;
              nz_old_out_r <= nz_old_pre;
            end

            if (play_bits[pc_ch] && s_eff_a != 0 && s_snd_wt)
              s_phase <= pha_y;
            if (s_snd_wt)
              smp_a <= 18'($signed(seq_q));
          end
          // Capture the live primary result and remember this sounding tuple
          // for the next sample's restart comparison.
          cap[CAP_W2]: begin
            if (s_snd_wt)
              wt_x1 <= $signed(seq_q);
            else
              smp_a <= z_eval;
            s_last_inc <= s_eff_inc;

            if (play_bits[pc_ch] || !(is_mus(pc_ch) && mus_playing))
              s_last_G <= g_live;
            s_last_wave <= s_snd_wave;
            last_mode_r <= s_ch_det;
            last_alt_r <= s_ch_buzz;
            last_rev_r <= s_ch_rev;
          end
          cap[CAP_W3]: begin
            if (s_snd_wt)
              smp_b <= 18'($signed(seq_q));
            else
              smp_b <= z_eval;
          end
          cap[CAP_W4]: begin
            if (!s_snd_wt)

              smp_b <= z_eval;
            if (s_snd_wt) begin

              wt_x1 <= $signed(seq_q);
              mxs_new <= wt_d[8];
            end else

              stage_leaf();
          end
          cap[CAP_W15]: begin
            if (s_snd_wt) begin
              smp_a <= wt_z;
              mxs_new <= wt_d[8];
            end else begin

              gz_filt_r <= m_res[26:10];
              mxs_old <= z_old_sel[17];
            end
          end
          cap[CAP_W5]: begin

            if (!s_snd_wt) begin

              smp_b <= smp_b + z_eval;

              if (s_old_G != 0 && !old_nz_r_on) begin
                s_old_phase <= pha_y;
                old_q0 <= 17'(old_q0 + dq_visit);
              end
            end
          end
          cap[CAP_W6]: begin

            if (play_bits[pc_ch] && s_eff_a != 0)
              s_phase2 <= PH2_W'(17'(s_phase2[16:0] + dq_visit));
          end
          cap[CAP_W26]: begin
            if (s_snd_wt)
              smp_b <= wt_z;
          end
          // Consume the live gain path; the old arm follows on later actions.
          cap[CAP_W27]: begin
            if (s_snd_wt) begin
              stage_leaf();
            end else begin

              mx_new <= mxs_new ? -$signed(gz_scaled) : $signed(gz_scaled);
            end
          end
          cap[CAP_W40]: begin

            gz_filt_r <= m_res[26:10];
          end
          cap[CAP_W51]: begin
            if (s_snd_wt)
              mx_new <= mx_new_w51;
            else
              mx_old <= mx_old_w51;
          end
          // Consume the blend on its first readable phase; the same
          // combinational result feeds the dampen filter directly.
          cap[CAP_W84]: begin
`ifndef SYNTHESIS
            if (bl_cnt != 7'd64 && bl_res != blend_prod_check[22:0])
              $fatal(1, "psg_walk: early blend consume got %0d, expected %0d, busy=%0b",
                     bl_res, blend_prod_check[22:0], m_busy);
`endif
            gz_filt_r <= filt_y;
            if (s_ch_damp != 2'd0)
              s_lp <= dmp_y;
          end
          default: ;
        endcase

        // The old noise step has no register of its own: mx_old is dead
        // from the visit's start until CAP_W51 writes it, and this value is
        // read at CAP_W1, thirty phases before that. |step| <= 33,324, so
        // mx_old's seventeen signed bits hold it exactly.
        if (pph == PPH_W'(PNZ_LIVE))
          mx_old <= 17'(nz2_rand[8] ? nz_neg : nz_pos);
`ifndef SYNTHESIS

        if ((nz_req_old || nz_req_live) && m_busy)
          $error("psg_walk: noise product dropped, m service busy at pph %0d",
                 pph);
        if (cap[CAP_W75] && bl_cnt != 7'd64 && m_busy)
          $fatal(1, "psg_walk: blend product dropped, m service busy at pph %0d",
                 pph);
`endif

        if (pph == PPH_W'(PLAST)) fold_launch();
        end
      end
    end
  end

endmodule

`endif
