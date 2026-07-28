// PSG computed wave layer (adopt-pico8-integer-audio 2.2): every waveform is
// evaluated, not read from a wave ROM.
//
// One evaluation pipe serves the three per-visit reads: main (issued at
// PWORK, captured +1), secondary q view (issued +1, captured +2), old
// continuation (issued +2, captured +3). Phase/wave/flags register at issue;
// the cone evaluates during the following cycle. Every constant multiply is a
// proven reciprocal form (tools/psg_hw_forms.py) - yosys lowers them to the
// priced CSD adder networks; the fabric has no DSP.
//
// The module takes the evaluation CONTEXT (which of the three reads is being
// issued, and the live/old voice state) and returns the three values the walk
// consumes: z_eval, dq17 and q16. It holds no walk state of its own - the
// only registers here are the two pipeline stages and the split-identity
// table reads.
`ifndef PSG_WAVE_SV
`define PSG_WAVE_SV

module psg_wave #(parameter REALTIME_PREVIEW = 0)
                 (input  bit   clk,
                  // Which of the three per-visit reads is being issued. The
                  // walk derives these from its control store (or, in the
                  // preview schedule, from pph) and hands them over.
                  input  logic iss_sec,
                  input  logic iss_om,
                  input  logic iss_os,
                  input  logic dq_old_ctx,
                  // The live voice
                  input  logic [2:0]  s_snd_wave,
                  input  logic        s_snd_wt,
                  input  logic [1:0]  s_ch_det,
                  input  logic        s_ch_buzz,
                  // Only the slices the cone actually reads cross the
                  // boundary: a port carries a public net per bit, and a bit
                  // the module never uses is a net the optimiser has to keep.
                  input  logic [15:0] s_phase_hi,    // s_phase[23:8]
                  input  logic [23:0] s_phase2,
                  input  logic [12:0] s_eff_inc_hi,  // s_eff_inc[20:8]
                  // The old continuation, carried in the old fields
                  input  logic [2:0]  s_old_wave,
                  input  logic [15:0] s_old_phase_hi,  // s_old_phase[23:8]
                  input  logic [12:0] s_old_inc_hi,    // s_old_inc[20:8]
                  input  logic [1:0]  old_mode_r,
                  input  logic        old_alt_r,
                  input  logic [15:0] old_q0_lo,      // old_q0[15:0]
                  output logic signed [17:0] z_eval,
                  output logic [16:0] dq17,
                  output logic [15:0] q16);

  logic [2:0]  wsel, wsel_r;
  logic [15:0] wx, wx_r;
  logic        wsec, wsec_r, walt_r;

  always_comb begin
    wsel = s_snd_wave;
    wx = s_phase_hi;
    wsec = 1'b0;
    if (iss_sec) begin
      wx = q16;                     // second voice (q0 view)
      wsec = 1'b1;
    end else if (iss_om) begin
      wsel = s_old_wave;
      wx = s_old_phase_hi;          // old-state continuation, primary
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
  // The indices carry exactly the tables' address widths: the split
  // identities bound h + l below each size (847 and 1695), so the sums
  // never wrap and the extra carry bit the general form would grow is
  // provably dead.
  wire [9:0]  t_h7  = t_pre[18:9];
  wire [9:0]  t_ix7 = t_h7 + {1'b0, t_pre[8:0]};
  wire [10:0] t_h15 = t_pre[18:8];
  wire [10:0] t_ix15 = t_h15 + {3'b0, t_pre[7:0]};
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
  assign z_eval =
      tri_core ? (wsec_r2 ? tzs(z_prim, 2'd3) : tzs(z_prim, 2'd2))
               : (wsec_r2 ? tzs(z_prim, 2'd1) : z_prim);

  // Second voice: the binary's universal 17-bit q0. Every rendering voice
  // advances q0 by dq = tz(dp*K/256), K selected per wave and detune mode.
  // Each K is at most two adds and one shift (psg_hw_forms dq.k*, all
  // exhaustively proven over the clamped dp range): the subtractive Ks are
  // dp minus a ceil term, triangle mode-1 is three shift-adds, and the
  // phaser's 254/256 default replaces the retired ~109/110 serial chain.
  // The one dq network serves both phase contexts: the live voice at
  // PWORK+6 and the old continuation at PWORK+5 (its wave/mode/dp are
  // the previous tick's, carried in the old fields).
  wire [2:0] dq_wave = dq_old_ctx ? s_old_wave : s_snd_wave;
  wire [1:0] dq_mode = dq_old_ctx ? old_mode_r : s_ch_det;
  wire [23:0] dp24 = {11'b0, dq_old_ctx ? s_old_inc_hi : s_eff_inc_hi};
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
  wire [15:0] qv_lo = q_old_ctx ? old_q0_lo : s_phase2[15:0];
  assign q16 =
      REALTIME_PREVIEW ? s_phase2[23:8]
    : (!s_snd_wt && (qv_wave == 3'd0 || qv_wave == 3'd7))
        ? qv_lo
    : (qv_mode == 2'd2) ? {qv_lo[14:0], 1'b0}
                        : qv_lo;
endmodule

`endif
