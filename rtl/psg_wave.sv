// Two-stage computed-wave pipeline.
//
// psg_walk selects a live primary, live secondary, previous primary, or
// previous secondary phase. This module evaluates the selected built-in wave
// and also returns the secondary-phase increment (dq17) and phase view (q16).
// Wavetables bypass the built-in wave result but still use dq17/q16.

`ifndef PSG_WAVE_SV
`define PSG_WAVE_SV

// Direct fixed-context waveform pipeline.  The executor presents one
// {phase, wave, alternate, primary/secondary} tuple on every enabled edge.
// All three sequential boundaries share `ce` so an external executor hold
// freezes the request, reciprocal lookup and result as one transaction.
module psg_wave_ctx(input  bit          clk,
                    input  logic        ce,
                    input  logic [15:0] ctx_phase,
                    input  logic [2:0]  ctx_wave,
                    input  logic        ctx_alt,
                    input  logic        ctx_secondary,
                    output logic signed [17:0] z_eval);

  logic [2:0]  wsel_r;
  logic [15:0] wx_r;
  logic        wsec_r, walt_r;

  always_ff @(posedge clk)
    if (ce) begin
      wx_r   <= ctx_phase;
      wsel_r <= ctx_wave;
      wsec_r <= ctx_secondary;
      walt_r <= ctx_alt;
    end
  // ---- Stage 1: direct shapes and reciprocal address reduction ----
  // One block-RAM word supplies remainders for division by 3, 7, and 15.
  // The address folds each operand until it fits in eight bits; the matching
  // quotient field is selected after the synchronous read.
  (* ram_style = "block" *) logic [14:0] recip[0:255];
  initial
    for (int i = 0; i < 256; i++)
      recip[i] = {6'(i / 3), 5'(i / 7), 4'(i / 15)};

  wire signed [16:0] tri_u =
      $signed({1'b0, wx_r ^ {16{wx_r[15]}}}) - 17'sd16384
      + $signed({16'b0, wx_r[15]});
  wire signed [17:0] tri_v = {tri_u[16], tri_u} + {tri_u, 1'b0};

  // Tilt shapes reduce to a linear ramp followed by exact /7 or /15. The
  // split identities are x/d = h*(2^k/d) + (h+l)/d for x=2^k*h+l.
  wire tilt_hi = (wsel_r == 3'd1) && walt_r;
  wire tilt_tail = &wx_r[15:13] && (!tilt_hi || wx_r[12]);
  wire [15:0] tramp = tilt_tail ? (16'd65535 - wx_r) : wx_r;

  wire [17:0] t_m3 = {2'b0, tramp} + {1'b0, tramp, 1'b0};
  // ceil(tramp / 2^N) is the high word plus one for a non-zero remainder.
  // Keep that narrow boundary explicit instead of adding across all 16 bits.
  wire [6:0] t_ceil = tilt_hi
      ? {1'b0, tramp[15:10]} + {6'b0, |tramp[9:0]}
      : {2'b0, tramp[15:11]} + {6'b0, |tramp[10:0]};
  wire [18:0] t_pre = (tilt_hi ? {t_m3, 1'b0} : {1'b0, t_m3})
                    - {12'b0, t_ceil};

  wire [9:0]  t_h7  = t_pre[18:9];
  wire [9:0]  t_ix7 = t_h7 + {1'b0, t_pre[8:0]};
  wire [10:0] t_h15 = t_pre[18:8];
  wire [10:0] t_ix15 = t_h15 + {3'b0, t_pre[7:0]};

  wire [6:0]  t_h2_7  = t_ix7[9:3];
  wire [3:0]  t_l2_7  = {1'b0, t_ix7[2:0]};
  wire [6:0]  t_h2_15 = t_ix15[10:4];
  wire [3:0]  t_l2_15 = t_ix15[3:0];

  wire signed [15:0] saw_sx = $signed({~wx_r[15], wx_r[14:0]});
  wire signed [17:0] saw_v = tzs({{2{saw_sx[15]}}, saw_sx}, 2'd2);
  wire signed [17:0] sa_h = $signed({3'b0, wx_r[15:1]}) - 18'sd32768;
  wire signed [17:0] saw_alt_v = tzs(saw_v + tzs(sa_h, 2'd2), 2'd1);

  wire [15:0] sq_th = (wsel_r == 3'd3) ? (walt_r ? 16'h9800 : 16'h8000)
                                       : (walt_r ? 16'hC800 : 16'hB000);
  wire signed [17:0] sq_v = (wx_r < sq_th) ? -18'sd6143 : 18'sd6143;

  wire [14:0] org_ramp = wx_r[14] ? 15'(16'd0 - wx_r) : wx_r[14:0];
  wire [7:0] org_h = org_ramp[14:7];
  wire [8:0] org_ix = {1'b0, org_h} + {1'b0, org_ramp[6:0], 1'b0};
  wire [6:0] org_h2 = org_ix[8:2];
  wire [3:0] org_l2 = {2'b0, org_ix[1:0]};
  wire [6:0] rc_h2 = (wsel_r == 3'd5)
                    ? org_h2 : (tilt_hi ? t_h2_15 : t_h2_7);
  wire [3:0] rc_l2 = (wsel_r == 3'd5)
                    ? org_l2 : (tilt_hi ? t_l2_15 : t_l2_7);
  wire [7:0] rc_addr = {1'b0, rc_h2} + {4'b0, rc_l2};
  logic [14:0] recip_q;
  logic [6:0]  rc_h2_r;
  always_ff @(posedge clk)
    if (ce) begin
      recip_q <= recip[rc_addr];
      rc_h2_r <= rc_h2;
    end

  wire signed [17:0] org_lin =
      !wx_r[14] ? ($signed({2'b0, wx_r}) - 18'sd8192)
                : (18'sd24576 - $signed({2'b0, wx_r}));
  wire signed [17:0] tri4 = tzs(tri_v, 2'd2);
  wire signed [17:0] org_alt_sec = wx_r[15] ? 18'sd3071 : -18'sd3071;

  logic signed [17:0] z_lin;
  always_comb begin
    case (wsel_r)
      3'd0:    z_lin = tri_v;
      3'd7:    z_lin = tri_v;
      3'd2:    z_lin = walt_r ? saw_alt_v : saw_v;
      3'd3, 3'd4: z_lin = sq_v;
      3'd5:    z_lin = (walt_r && wsec_r) ? org_alt_sec : org_lin;
      default: z_lin = 18'sd0;
    endcase
  end
  // ---- Stage 2: registered terms and reciprocal recombination ----
  // Pipeline boundary: linear shapes are complete; tilt/organ carry only the
  // terms needed to recombine the reciprocal lookup on the next stage.
  logic signed [17:0] z_lin_r;
  logic [14:0] t_pre_r;
  logic [9:0]  t_h7_r;
  logic [10:0] t_h15_r;
  logic        tilt_tail_r;
  logic [7:0]  org_h_r;
  logic signed [17:0] tri4_r;
  logic [2:0]  wsel_r2;
  logic        wsec_r2, walt_r2;
  always_ff @(posedge clk)
    if (ce) begin
      z_lin_r <= z_lin;
      t_pre_r <= t_pre[14:0];
      t_h7_r  <= t_h7;
      t_h15_r <= t_h15;
      tilt_tail_r <= tilt_tail;
      org_h_r <= org_h;
      tri4_r <= tri4;
      wsel_r2 <= wsel_r;
      wsec_r2 <= wsec_r;
      walt_r2 <= walt_r;
    end

  wire tilt_hi2 = (wsel_r2 == 3'd1) && walt_r2;
  wire org_ctx = (wsel_r2 == 3'd5);
  wire [10:0] rc_h = org_ctx ? {3'b0, org_h_r}
                   : tilt_hi2 ? t_h15_r : {1'b0, t_h7_r};

  wire [5:0] rc_q = org_ctx ? recip_q[14:9]
                  : tilt_hi2 ? {2'b0, recip_q[3:0]} : {1'b0, recip_q[8:4]};
  wire rc_e6 = !tilt_hi2 || org_ctx;
  wire rc_e4 = tilt_hi2 || org_ctx;
  wire rc_e3 = !tilt_hi2 && !org_ctx;
  wire rc_e2 = org_ctx;
  // Shared shift/add recombination for the /3, /7, and /15 identities.
  wire [16:0] rc = (rc_e6 ? {rc_h, 6'b0} : 17'd0)
                 + (rc_e4 ? {2'b0, rc_h, 4'b0} : 17'd0)
                 + (rc_e3 ? {3'b0, rc_h, 3'b0} : 17'd0)
                 + (rc_e2 ? {4'b0, rc_h, 2'b0} : 17'd0)
                 + {6'b0, rc_h}

                 + {10'b0, rc_h2_r}
                 + {11'b0, rc_q};
  wire [14:0] t_div = (tilt_tail_r && !org_ctx) ? t_pre_r : rc[14:0];
  wire signed [17:0] div_out = $signed({3'b0, t_div})
                             - (org_ctx ? 18'sd8192 : 18'sd12286);
  wire signed [17:0] tri_alt_v = div_out + tri4_r + (tri4_r <<< 1);

  logic signed [17:0] z_prim;
  always_comb begin
    case (wsel_r2)
      3'd0:    z_prim = walt_r2 ? tri_alt_v : z_lin_r;
      3'd1:    z_prim = div_out;
      3'd5:    z_prim = ((z_lin_r[15] ^ z_lin_r[14])
                         && !(walt_r2 && wsec_r2))
                          ? div_out : z_lin_r;
      default: z_prim = z_lin_r;
    endcase
  end

  wire tri_core = (wsel_r2 == 3'd0) || (wsel_r2 == 3'd7);
  wire [1:0] z_shift = tri_core ? (wsec_r2 ? 2'd3 : 2'd2)
                                : {1'b0, wsec_r2};
  assign z_eval = tzs(z_prim, z_shift);

endmodule
// Walk-facing context selector, detune increment, and phase-view adapter.
module psg_wave #(parameter REALTIME_PREVIEW = 0)
                 (input  bit   clk,

                  input  logic iss_sec,
                  input  logic iss_om,
                  input  logic iss_os,
                  input  logic dq_old_ctx,

                  input  logic [2:0]  s_snd_wave,
                  input  logic        s_snd_wt,
                  input  logic [1:0]  s_ch_det,
                  input  logic        s_ch_buzz,

                  input  logic [15:0] s_phase_hi,
                  input  logic [23:0] s_phase2,
                  input  logic [12:0] s_eff_inc_hi,

                  input  logic [2:0]  s_old_wave,
                  input  logic [15:0] s_old_phase_hi,
                  input  logic [12:0] s_old_inc_hi,
                  input  logic [1:0]  old_mode_r,
                  input  logic        old_alt_r,
                  input  logic [15:0] old_q0_lo,
                  output logic signed [17:0] z_eval,
                  output logic [16:0] dq17,
                  output logic [15:0] q16);

  logic [2:0]  wsel;
  logic [15:0] wx;
  logic        wsec;
  // ---- Live/preceding and primary/secondary context selection ----
  // Select the evaluation context before the first pipeline register.
  always_comb begin
    wsel = s_snd_wave;
    wx = s_phase_hi;
    wsec = 1'b0;
    if (iss_sec) begin
      wx = q16;
      wsec = 1'b1;
    end else if (iss_om) begin
      wsel = s_old_wave;
      wx = s_old_phase_hi;
    end else if (iss_os) begin
      wsel = s_old_wave;
      wx = q16;
      wsec = 1'b1;
    end
  end
  wire w_old_ctx = iss_om || iss_os;
  psg_wave_ctx u_ctx(
    .clk(clk), .ce(1'b1), .ctx_phase(wx), .ctx_wave(wsel),
    .ctx_alt(w_old_ctx ? old_alt_r : s_ch_buzz), .ctx_secondary(wsec),
    .z_eval(z_eval));
  // ---- Per-wave secondary-oscillator increment ----
  // Per-wave secondary-oscillator increments. All expressions implement the
  // integer forms directly, including their ceiling-biased corrections.
  wire [2:0] dq_wave = dq_old_ctx ? s_old_wave : s_snd_wave;
  wire [1:0] dq_mode = dq_old_ctx ? old_mode_r : s_ch_det;
  wire [12:0] dp13 = dq_old_ctx ? s_old_inc_hi : s_eff_inc_hi;

  // Triangle detune-1 is floor(193*dp/256). Split dp = 256*q+r:
  // the coefficient applies to only five quotient bits, while the residue is
  // floor(193*r/256) = r-ceil(63*r/256).  The latter is floor(3*r/4)
  // plus one exactly when the two-bit residue is non-zero and no greater
  // than r's high two bits.
  wire [4:0] dq_q256 = dp13[12:8];
  wire [7:0] dq_r256 = dp13[7:0];
  wire [1:0] dq_rmod4 = dq_r256[1:0];
  wire dq_rnz4 = dq_rmod4 != 0;
  wire dq_r193_carry = dq_rnz4 && dq_r256[7:6] >= dq_rmod4;
  wire [8:0] dq_low193 = {1'b0, dq_r256}
                          - {3'b0, dq_r256[7:2]}
                          - {8'b0, dq_rnz4}
                          + {8'b0, dq_r193_carry};
  wire [6:0] dq_q256_3 = {2'b0, dq_q256} + {1'b0, dq_q256, 1'b0};
  wire [12:0] dq_hi193 = {dq_q256_3, 6'b0} + {8'b0, dq_q256};
  wire [13:0] dq_193 = {1'b0, dq_hi193} + {6'b0, dq_low193[7:0]};

  // Phaser detune-1 uses ceil(6*dp/256). Split at 128 so the coefficient is
  // 3 on a six-bit quotient and seven-bit residue. For r in [0,127],
  // ceil(3*r/128) is 0, 1, 2, 3 across 0, 1..42, 43..85, 86..127.
  wire [5:0] dq_q128 = dp13[12:7];
  wire [6:0] dq_r128 = dp13[6:0];
  wire [7:0] dq_q128_3 = {2'b0, dq_q128} + {1'b0, dq_q128, 1'b0};
  wire dq_r128_ge43 = dq_r128[5]
      && (dq_r128[4] || (dq_r128[3]
          && (dq_r128[2] || (dq_r128[1] && dq_r128[0]))));
  wire dq_r128_ge22 = dq_r128[5]
      || (dq_r128[4] && (dq_r128[3]
          || (dq_r128[2] && dq_r128[1])));
  wire [1:0] dq_ceil3r128 = {
      dq_r128[6] || dq_r128_ge43,
      (!dq_r128[6] && |dq_r128[5:0] && !dq_r128_ge43)
          || (dq_r128[6] && dq_r128_ge22)
  };
  wire [8:0] dq_ceil6_256 = {1'b0, dq_q128_3}
                              + {7'b0, dq_ceil3r128};
  wire [7:0] dq_ceil64 = {1'b0, dp13[12:6]}
                           + {7'b0, |dp13[5:0]};
  wire [6:0] dq_ceil128 = {1'b0, dq_q128}
                            + {6'b0, |dq_r128};
  wire [5:0] dq_ceil256 = {1'b0, dq_q256}
                            + {5'b0, |dq_r256};

  logic [13:0] dq_base;
  logic [8:0]  dq_corr;
  logic        dq_sub;
  always_comb begin
    dq_base = {1'b0, dp13};
    dq_corr = 9'd0;
    dq_sub = 1'b0;
    if (!s_snd_wt && dq_wave == 3'd0) begin
      case (dq_mode)
        2'd1:    dq_base = dq_193;
        2'd2:    dq_base = {1'b0, dp13} + {2'b0, dp13[12:1]};
        default: ;
      endcase
    end else if (!s_snd_wt && dq_wave == 3'd7) begin
      dq_sub = 1'b1;
      case (dq_mode)
        2'd1:    dq_corr = dq_ceil6_256;
        2'd2: begin
          dq_base = {dp13, 1'b0};
          dq_corr = {1'b0, dq_ceil64};
        end
        default: dq_corr = {2'b0, dq_ceil128};
      endcase
    end else if (!s_snd_wt && dq_mode != 2'd0) begin
      dq_sub = 1'b1;
      dq_corr = {3'b0, dq_ceil256};
    end
  end
  wire [13:0] dq_calc = dq_sub ? (dq_base - {5'b0, dq_corr}) : dq_base;
  always_comb dq17 = {3'b0, dq_calc};
  // ---- Secondary phase presentation ----
  // Secondary phase presentation: triangle/phaser use the unshifted 17-bit
  // accumulator, detune mode 2 doubles the other built-in waves, and preview
  // retains its compact 24-bit phase representation.
  wire q_old_ctx = iss_os && !s_snd_wt;
  wire [2:0] qv_wave = q_old_ctx ? s_old_wave : s_snd_wave;
  wire [1:0] qv_mode = q_old_ctx ? old_mode_r : s_ch_det;
  wire [15:0] qv_lo = q_old_ctx ? old_q0_lo : s_phase2[15:0];
  assign q16 =
      REALTIME_PREVIEW ? s_phase2[23:8]
    : (!s_snd_wt && (qv_wave == 3'd0 || qv_wave == 3'd7))
        ? qv_lo
    : (qv_mode == 2'd2) ? {qv_lo[14:0], 1'b0}
                        : qv_lo;
endmodule

`endif
