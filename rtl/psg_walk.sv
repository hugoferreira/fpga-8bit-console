// PSG per-sample synthesis walk: one pass over the eight playback slots for
// every 22050 Hz sample.
//
// This is the module that RUNS every sample, and everything about it is
// scheduled rather than parallel: the slots' oscillator state lives in the
// scheduled record store, one voice is loaded, rendered, mixed and written
// back at a time, and one control-store ROM word per micro-phase says what
// each step does. The walk owns `prun` and `pph` - the two signals the whole
// chip's freeze contract is written against - and every s_*/old_*/last_*
// streaming register.
//
// What it does NOT own: the wave cone (u_wave, a sibling - this module hands
// it the evaluation context and reads back z_eval/dq17/q16), the record store
// (u_state), the audio RAM (u_aram) and the two arithmetic services. It
// reaches all of them through the request/response ports below.
`ifndef PSG_WALK_SV
`define PSG_WALK_SV

module psg_walk #(parameter REVERB = 1, parameter REALTIME_PREVIEW = 0)
                 (input  bit   clk,
                  input  bit   reset,
                  input  logic sample_en,
                  // The sequencer's view: which slots sound, which bank is
                  // live, and the filter-clear handshake.
                  input  logic [PSG_NV-1:0] play_bits,
                  input  logic mus_playing,
                  input  logic spar_bank,
                  input  logic [PSG_NV-1:0] clr_tog,
                  output logic [PSG_NV-1:0] clr_ack,
                  // Audio RAM: the borrowed read for wavetable instruments
                  input  logic [7:0]  seq_q,
                  output logic        syn_rd,
                  output logic [12:0] syn_addr,
                  // The scheduled record store: this module's owner bundle
                  input  logic [15:0] state_q,
                  output logic        state_sample_read,
                  output logic [PSG_VADR-1:0] wlk_ra,
                  output logic        state_sample_we,
                  output logic [PSG_VADR-1:0] wlk_wa,
                  output logic [15:0] wlk_wd,
                  // The multiply service: this module's request bundle
                  input  logic [31:0] m_res,
                  input  logic [33:0] m_res_wide,
                  input  logic [27:0] m_res12,
                  input  logic        m_busy,
                  output logic        wmul_start,
                  output logic signed [24:0] wmul_a,
                  output logic [11:0] wmul_b,
                  output logic [1:0]  wmul_mode,
                  // The wave layer: context out, values back
                  output logic iss_sec,
                  output logic iss_om,
                  output logic iss_os,
                  output logic dq_old_ctx,
                  output logic [2:0]  s_snd_wave,
                  output logic        s_snd_wt,
                  output logic [1:0]  s_ch_det,
                  output logic        s_ch_buzz,
                  output logic [23:0] s_phase,
                  output logic [23:0] s_phase2,
                  output logic [20:0] s_eff_inc,
                  output logic [2:0]  s_old_wave,
                  output logic [23:0] s_old_phase,
                  output logic [20:0] s_old_inc,
                  output logic [1:0]  old_mode_r,
                  output logic        old_alt_r,
                  output logic [16:0] old_q0,
                  input  logic signed [17:0] z_eval,
                  input  logic [16:0] dq17,
                  input  logic [15:0] q16,
                  // The freeze contract's two walk-side terms
                  output logic        prun,
                  output logic        fold_busy,
                  // The mixed sample
                  output logic signed [15:0] dry16,
                  output logic        dry_valid);

  logic [6:0]  pph;                            // sample micro-phase
  logic [15:0] sosc_wd;                        // the oscillator write-back word

  // The walk's schedule. The interactive simulator can select the compact
  // schedule that preceded the old-state crossfade renderer; hardware and
  // oracle builds use the full one. REALTIME_PREVIEW is a parameter, so the
  // unused schedule is removed during lowering rather than becoming runtime
  // selection logic.
  localparam int PLOSC = REALTIME_PREVIEW ? 7  : PSG_SOSC;
  localparam int PWORK = REALTIME_PREVIEW ? 12 : 19;
  localparam int PFOLD = REALTIME_PREVIEW ? 23 : 108;
  localparam int PSTOR = REALTIME_PREVIEW ? 16 : 52;
  localparam int PLAST = REALTIME_PREVIEW ? 23 : 108;


  // The synthesis walk's working copy: parameters and oscillator state loaded
  // serially from state_m, with the oscillator words written back in place.
  // Increment carriers are 21 bits: the pitch table's 13-bit entries
  // put every increment (vibrato included) under 2^21, but the adds
  // between them launder that bound out of synthesis's sight.
  logic [2:0]  s_snd_id;
  logic [5:0]  s_snd_pitch;
  logic        s_ch_noiz;
  logic [1:0]  s_ch_rev, s_ch_damp;
  logic [11:0] s_eff_a;
  logic signed [7:0] s_nz_hold;
  logic [3:0]  s_nz_ph;
  logic signed [12:0] s_brown;
  logic signed [16:0] s_lp;
  logic signed [15:0] s_noise_lp;
  // PICO-8 keeps a copy of the preceding oscillator state at every synthesis
  // tick and blends its continuation into the first 64 new samples. These
  // fields live in the oscillator portion of state_m.
  logic [20:0] s_last_inc;
  logic [12:0] s_old_G, s_last_G;
  logic [2:0]  s_last_wave;
  // The old state's own 17-bit secondary and the detune modes each side
  // of the tick boundary: the old continuation renders with the dq its
  // parameters had, not the new bank's.
  logic [1:0]  last_mode_r;
  logic        last_alt_r;
  // The reverb digit is oscillator state too (`hmode = state[0x5c]`), so
  // the copied old continuation combs at the level the PREVIOUS tick
  // asked for while the new block combs at the current one.
  logic [1:0]  old_rev_r, last_rev_r;
  logic [6:0]  bl_cnt;               // samples since this voice's copy

  wire [12:0] s_snd_wtb = rec_base({3'b0, s_snd_id});


  // The serial soft_add fold engine (datapath in the mixer section below).
  // Declared here because walk_frozen must hold the tick sequencer while the
  // post-walk fold chain still owns the phase ALU and the m service idle slot.
  logic [3:0]  fmc;                  // fold micro-cycle, 0 = idle
  assign fold_busy = (fmc != 4'd0);
  assign state_sample_read = prun && pph < 7'(PLOSC + PSG_SPAR);
  // Exactly the oscillator record: PLAST may extend past the last store
  // (the product chain's tail phases), so the window is bounded by PSG_SOSC,
  // not by the visit's end.
  // The dampen state is produced at +86, far past its word's store
  // slot, so it writes back through two dedicated late cycles.
  wire         state_lp_we = prun && !REALTIME_PREVIEW
                               && (pph == 7'(PWORK + 87)
                                   || pph == 7'(PWORK + 88));
  assign state_sample_we = (prun
                               && pph >= 7'(PSTOR)
                               && pph < 7'(PSTOR + PLOSC))
                               || state_lp_we;

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
  logic [PSG_VW-1:0] pc_ch;
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

  // Record streaming for the synthesis walk. Reads are issued on the load
  // cycles and land one cycle later; the oscillator write-back runs on the
  // store cycles, addressing word pph-PSTOR.
  // The PSG_OSC_W* field lists (oscillator words 14/17/22) are in
  // psg_common.svh: the pack (sosc_wd), the unpack (the pph load case) and -
  // for word 14 - the late dampen write-back all expand the same macro, so
  // the layouts cannot drift apart.
  wire [3:0] s_stw = 4'(pph - 7'(PSTOR));
  always_comb begin
    if (REALTIME_PREVIEW) begin
      case (s_stw)
        4'd0:    sosc_wd = s_phase[15:0];
        4'd1:    sosc_wd = {s_nz_hold, s_phase[23:16]};
        4'd2:    sosc_wd = s_phase2[15:0];
        4'd3:    sosc_wd = {4'b0, s_nz_ph, s_phase2[23:16]};
        4'd4:    sosc_wd = {3'b0, s_brown};
        4'd5:    sosc_wd = s_lp[15:0];
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
        4'd4:    sosc_wd = `PSG_OSC_W14;
        4'd5:    sosc_wd = s_lp[15:0];
        4'd6:    sosc_wd = s_old_phase[23:8];
        4'd7:    sosc_wd = `PSG_OSC_W17;
        4'd8:    sosc_wd = s_old_inc[15:0];
        4'd9:    sosc_wd = {s_old_G[7:0], 3'b0, s_old_inc[20:16]};
        4'd10:   sosc_wd = {1'b0, old_rev_r, last_rev_r,
                            s_last_wave, 3'b0, s_last_inc[20:16]};
        4'd11:   sosc_wd = s_last_inc[15:0];
        4'd12:   sosc_wd = {1'b0, `PSG_OSC_W22};
        default: sosc_wd = s_noise_lp;
      endcase
    end
  end

  // ---- the two owner bundles ------------------------------------------
  // The store has exactly two owners, and each presents one read request and
  // one write request. Spelling them as bundles rather than as arms of a
  // single chain is what lets the store become its own module: the priority
  // below is then the module's port contract instead of a comment.
  //
  // Owner 1, the sample walk. Its write covers the oscillator write-back
  // window AND the two late dampen cycles (state_sample_we includes
  // state_lp_we), which is why the address choice inside is lp-first.
  always_comb begin
    if (pph < 7'(PLOSC))
      wlk_ra = {pc_ch, PSG_V_OSC + 5'(pph)};
    else if (pph < 7'(PLOSC + PSG_SPAR))
      wlk_ra = {pc_ch, (spar_bank ? PSG_V_PAR1 : PSG_V_PAR0)
                       + 5'(pph - 7'(PLOSC))};
    else
      wlk_ra = {pc_ch, PSG_V_OSC};

    if (state_lp_we) begin
      wlk_wa = {pc_ch, (pph == 7'(PWORK + 87)) ? PSG_V_OSC + 5'd5
                                               : PSG_V_OSC + 5'd4};
      wlk_wd = (pph == 7'(PWORK + 87)) ? s_lp[15:0] : `PSG_OSC_W14;
    end else begin
      wlk_wa = {pc_ch, PSG_V_OSC + 5'(s_stw)};
      wlk_wd = sosc_wd;
    end
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


  assign iss_sec = REALTIME_PREVIEW ? (pph == 7'(PWORK + 1))
                                  : ctrl_q[CTRL_ISEC];
  assign iss_om  = REALTIME_PREVIEW ? (pph == 7'(PWORK + 2))
                                  : ctrl_q[CTRL_IOM];
  assign iss_os  = REALTIME_PREVIEW ? (pph == 7'(PWORK + 3))
                                  : ctrl_q[CTRL_IOS];

  // The one dq network serves both phase contexts: the live voice at
  // PWORK+6 and the old continuation at PWORK+5 (its wave/mode/dp are the
  // previous tick's, carried in the old fields).
  assign dq_old_ctx = REALTIME_PREVIEW ? (pph == 7'(PWORK + 5))
                                     : ctrl_q[CTRL_DQO];

  // The preview's own secondary-increment network below still reads the
  // live increment directly; u_wave carries its own copy of the same wire.
  wire [20:0] einc = s_eff_inc;

  // The deliberately compact simulator preview still uses its original
  // single-cycle secondary increment. REALTIME_PREVIEW is a parameter, so
  // this complete network is removed from hardware and oracle builds.
  wire [16:0] preview_det_round = {4'b0, einc[20:8]} + 17'd255;
  wire [16:0] preview_det_wide =
      {4'b0, einc[20:8]} - {8'b0, preview_det_round[16:8]};
  wire [23:0] preview_v2inc =
      s_snd_wt ? {3'b0, einc} :
      (s_snd_wave == 3'd7) ? ({3'b0, einc} - {10'b0, einc[20:7]}
                                        - {13'b0, einc[20:10]}
                                        - {15'b0, einc[20:12]}) :
      (s_ch_det == 2'd1)   ? {preview_det_wide[15:0], 8'b0} :
      (s_ch_det == 2'd2)   ? {2'b0, einc, 1'b0} :
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
    pha_b = {3'b0, einc};
    if (dq_old_ctx) begin
      pha_a = s_old_phase;
      pha_b = {3'b0, s_old_inc};
    end
  end
  wire [23:0] pha_y = pha_a + pha_b;

  // 18 bits, not 24: operands are 18-bit stack/series values, and the
  // widest result is a compare spanning +-(65,536 + 24,576) = 90,112,
  // inside signed 18. The compare sign moves from bit 23 to bit 17.
  logic [17:0] fold_a, fold_b;
  logic        fold_sub, fold_cin;
  // One physical carry chain for the fold: a - b is a + ~b + 1, and the
  // single "+1" micro-op rides the same carry-in.
  wire [17:0] phase_alu_y =
      fold_a + (fold_sub ? ~fold_b : fold_b)
             + {17'b0, fold_sub | fold_cin};

  // Wavetable instruments read their 64 samples out of audio RAM, one
  // borrowed read per voice per sample (the sequencer FSM freezes for it).
  always_comb begin
    syn_rd   = 1'b0;
    syn_addr = 13'd0;
    if (prun && s_snd_wt && play_bits[pc_ch]) begin
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
  //
  // The two requesters present separate bundles, merged below under the
  // priority the single mux used to spell as an if/else-if chain. They are
  // DISJOINT, not merely prioritised: the walk arm needs `prun`, the
  // sequencer arm needs `!walk_frozen`, and walk_frozen subsumes prun - so
  // at most one bundle ever asserts and the merge is a wiring choice, not an
  // arbiter. That is what lets the service move to its own module while the
  // request selection stays with the requesters.
  always_comb begin
    wmul_start = 1'b0;
    wmul_a     = 25'sd0;
    wmul_b     = 12'd0;
    wmul_mode  = 2'd0;
    if (prun && !m_busy) begin
      if (REALTIME_PREVIEW) begin
        if (pph == 7'(PWORK + 2)) begin
          wmul_start   = 1'b1;
          wmul_a = 25'(z_new_c);
          wmul_b = {4'b0, s_eff_a[11:4]};
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
            wmul_start = 1'b1;
            if (s_snd_wt) begin
              wmul_a = 25'(wt_pd);
              wmul_b = {2'b0, wt_pf};
              wmul_mode = 2'd1;
            end else begin
              // ONE 12-bit G pass: |z| x G on the widened B port.
              wmul_a = 25'(z_new_c);
              wmul_b = 12'(g_live);
              wmul_mode = 2'd2;
            end
          end
          // /3 limb passes: m_res12 is the whole G*z magnitude. Arms 3/9
          // are the new and old voices' hi limbs and 5/10 their lo limbs
          // - identical launches, distinguished only by where the consume
          // steps put the result.
          4'd3, 4'd9: if (!s_snd_wt) begin
            wmul_start   = 1'b1;
            wmul_a = {8'b0, m_res12[26:10]};
            wmul_b = 12'd341;
            wmul_mode = 2'd1;
          end
          4'd5, 4'd10: if (!s_snd_wt) begin
            wmul_start   = 1'b1;
            wmul_a = {8'b0, gz_s1_r};
            wmul_b = 12'd171;
            wmul_mode = 2'd1;
          end
          4'd6: if (!s_snd_wt) begin
            wmul_start   = 1'b1;
            wmul_a = 25'(z_old_c);
            wmul_b = 12'(s_old_G);
            wmul_mode = 2'd2;
          end
          4'd11: if (bl_cnt != 7'd64) begin
            wmul_start   = 1'b1;
            wmul_a = 25'(blend_diff);
            wmul_b = {6'b0, bl_cnt[5:0]};
          end
          4'd2: if (s_snd_wt) begin
            wmul_start   = 1'b1;
            wmul_a = 25'(wt_qd);
            wmul_b = {2'b0, wt_qf};
            wmul_mode = 2'd1;
          end
          4'd4: if (s_snd_wt) begin
            wmul_start   = 1'b1;
            wmul_a = 25'(z_new_c);
            wmul_b = 12'(g_live);
            wmul_mode = 2'd2;
          end
          4'd7: if (s_snd_wt) begin
            wmul_start   = 1'b1;
            wmul_a = {8'b0, m_res12[26:10]};
            wmul_b = 12'd341;
            wmul_mode = 2'd1;
          end
          4'd8: if (s_snd_wt) begin
            wmul_start   = 1'b1;
            wmul_a = {8'b0, gz_s1_r};
            wmul_b = 12'd171;
            wmul_mode = 2'd1;
          end
          default: ;
        endcase
      end
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
  wire signed [17:0] n_contrib = {mix_prod[16], mix_prod};
  // This slot's leaf in the reduction tree: its sample, or an explicit zero
  // when it is running but not audible.
  wire signed [17:0] mix_leaf = mx_aud ? n_contrib : 18'sd0;

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
  // 18 bits, not 22: a leaf is an int16-wrapped sample (the ring's
  // wrap defines the domain), soft_add is contractive toward 32768
  // (TH + (2*32768 - TH)/5 = 32768 exactly), so every stack value is
  // <= |32768| and every raw pair sum <= |65536| - 18-bit signed
  // carries both with a bit to spare.
  logic signed [17:0] fstk[0:2];      // S0, S1, S2
  logic [2:0]  fsel;                  // active fold: see fda/fdb below
  logic [1:0]  fpend;                 // folds still queued in this chain
  logic        ffin;                  // this chain ends in dry16
  logic        f_over, f_under;
  logic [17:0] fx_r;                  // |excess|, then the partial remainder
  logic [17:0] ft2;                   // series accumulator (q << 2)
  logic [3:0]  fr_r;                  // final remainder, 0..9

  // Fold operand selection: 0/1/2 combine a stack entry with the slot leaf,
  // 3 folds S1 into S0, 4 folds S2 into S1. fda is always the destination.
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

  // One ALU micro-op per fmc step. fmc 1 forms the plain sum, 2/3 the two
  // threshold compares (capturing the excess), 4-6 the divide series, 7/8
  // the remainder, 9 rebuilds TH + q (+1 rides the carry-in), 10 negates for
  // the underflow side. Steps 4-10 run regardless and commit nothing unless
  // a compare fired; the schedule is fixed so nothing downstream cares.
  always_comb begin
    fold_a = 18'd0; fold_b = 18'd0; fold_sub = 1'b0; fold_cin = 1'b0;
    case (fmc)
      4'd1:  begin fold_a = fda;
                   fold_b = fdb; end
      4'd2:  begin fold_a = fda;
                   fold_b = 18'(SA_TH); fold_sub = 1'b1; end
      4'd3:  begin fold_a = 18'(-SA_TH);
                   fold_b = fda; fold_sub = 1'b1; end
      4'd4:  begin fold_a = {1'b0, fx_r[17:1]};
                   fold_b = {2'b0, fx_r[17:2]}; end
      4'd5:  begin fold_a = ft2;
                   fold_b = {4'b0, ft2[17:4]}; end
      4'd6:  begin fold_a = ft2;
                   fold_b = {8'b0, ft2[17:8]}; end
      4'd7:  begin fold_a = fx_r;
                   fold_b = {ft2[17:2], 2'b00}; fold_sub = 1'b1; end
      4'd8:  begin fold_a = fx_r;
                   fold_b = {2'b0, ft2[17:2]}; fold_sub = 1'b1; end
      4'd9:  begin fold_a = 18'(SA_TH);
                   fold_b = {2'b0, ft2[17:2]};
                   fold_cin = (fr_r >= 4'd5); end
      4'd10: begin fold_a = 18'd0;
                   fold_b = fda; fold_sub = 1'b1; end
      default: ;
    endcase
  end


  // The per-voice history rings (design 8 / the buffer study): flat
  // 732 x int16 per slot, written UNCONDITIONALLY every rendered
  // sample (captured: a slot with no reverb digit still fills its
  // ring), read at 366 (level 1) or 732 (level 2, read-before-write by
  // schedule) samples of lookback. Absent rings read zero and the comb
  // degenerates to the identity.
  generate
  if (REVERB) begin : g_ring
    logic [15:0] ringm[0:PSG_NV * 732 - 1];
    logic [15:0] ring_rd;
    initial for (int i = 0; i < PSG_NV * 732; i++) ringm[i] = 16'd0;
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
      if (prun && pph == 7'(PWORK + 87) && play_bits[pc_ch])
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

  // Steps the preview and hardware schedules share, spelled once each.

  // Per-sample noise state when `run` (playing, nonzero amplitude) -
  // white into the pitched S&H window (every sample when NOIZ), the
  // brown integrator (leaky low-pass of white, for BUZZ), the built-in
  // noise one-pole - and the filter-state reset a trigger asked for.
  // The reset overrides the step, spelled as one clr-priority write per
  // register: that is the enable/data cone synthesis derives from a
  // step-then-clear block anyway, and Verilator's always_ff lint only
  // attributes a task's writes to the caller when each register has a
  // single write site in the task.
  task noise_filt_step(input logic run);
    logic clr;
    clr = (clr_tog[pc_ch] != clr_ack[pc_ch]);
    if (run) begin
      if (s_ch_noiz || s_phase[23:20] != s_nz_ph) begin
        s_nz_ph <= s_phase[23:20];
        s_nz_hold <= $signed(lfsr[7:0]);
      end
    end
    if (clr) begin
      clr_ack[pc_ch] <= clr_tog[pc_ch];
      s_lp <= 0;
    end
    if (run || clr)
      s_brown <= clr ? 13'sd0
                     : s_brown - {{5{s_brown[12]}}, s_brown[12:5]}
                               + $signed({{5{lfsr[7]}}, lfsr[7:0]});
    if ((run && s_snd_wave == 3'd6) || clr)
      s_noise_lp <= clr ? 16'sd0 : noise_next;
  endtask

  // Stage the mixer leaf: the z sign for the G product's consume step,
  // and the run/audible split - a music slot renders while its channel's
  // foreground effect plays, but only the mixer leaf is zeroed.
  task stage_leaf();
    mxs_new <= z_new_c[17];
    mx_play <= play_bits[pc_ch];
    mx_aud  <= play_bits[pc_ch]
               & ~(is_mus(pc_ch) & play_bits[{1'b0, pc_ch[1:0]}]);
  endtask

  // Fold this slot into the soft_add tree: an even slot's leaf waits on
  // the stack; an odd slot's launches the fold chain (one fold, or the
  // queued multi-fold steps after slots 3 and 7). mix_leaf is zero for a
  // slot that is running but suppressed, which is deliberate - the
  // tree's zero leaves are part of the function.
  task fold_launch();
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
  endtask


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
          4'd1:  begin fstk[fdsti] <= phase_alu_y[17:0]; fmc <= 4'd2; end
          4'd2:  begin
            f_over <= ~phase_alu_y[17];
            if (!phase_alu_y[17]) fx_r <= phase_alu_y[17:0];
            fmc <= 4'd3;
          end
          4'd3:  begin
            f_under <= ~phase_alu_y[17];
            if (!phase_alu_y[17]) fx_r <= phase_alu_y[17:0];
            fmc <= 4'd4;
          end
          4'd4, 4'd5, 4'd6: begin ft2 <= phase_alu_y[17:0]; fmc <= fmc + 1; end
          4'd7:  begin fx_r <= phase_alu_y[17:0]; fmc <= 4'd8; end
          4'd8:  begin fr_r <= phase_alu_y[3:0]; fmc <= 4'd9; end
          4'd9:  begin
            if (f_over | f_under) fstk[fdsti] <= phase_alu_y[17:0];
            fmc <= f_under ? 4'd10 : 4'd11;
          end
          4'd10: begin fstk[fdsti] <= phase_alu_y[17:0]; fmc <= 4'd11; end
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
                  `PSG_OSC_W14 <= state_q;
          7'd6: if (!REALTIME_PREVIEW) s_lp[15:0] <= state_q;
          7'd7: if (REALTIME_PREVIEW)
                   s_noise_lp <= state_q;
                else
                   s_old_phase <= {state_q, 8'b0};
          7'd8: if (!REALTIME_PREVIEW)
                   `PSG_OSC_W17 <= state_q;
          7'd9: if (!REALTIME_PREVIEW) s_old_inc[15:0] <= state_q;
          7'd10: if (!REALTIME_PREVIEW)
                    {s_old_G[7:0], s_old_inc[20:16]}
                      <= {state_q[15:8], state_q[4:0]};
          7'd11: if (!REALTIME_PREVIEW)
                    {old_rev_r, last_rev_r, s_last_wave,
                     s_last_inc[20:16]} <= {state_q[14:8], state_q[4:0]};
          7'd12: if (!REALTIME_PREVIEW) s_last_inc[15:0] <= state_q;
          7'd13: if (!REALTIME_PREVIEW)
                    `PSG_OSC_W22 <= state_q[14:0];
          7'd14: if (!REALTIME_PREVIEW) s_noise_lp <= state_q;
          default: ;
        endcase
        case (pph)
          7'(PLOSC + 1):
            s_eff_inc[15:0] <= state_q;
          7'(PLOSC + 2):
            {s_snd_id, s_snd_wt, s_snd_wave, s_eff_inc[20:16]}
              <= {state_q[14:8], state_q[4:0]};
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
          if (pc_ch == PSG_VW'(PSG_NV-1))
            prun <= 0;
          pc_ch <= pc_ch + 1;
        end else
          pph <= pph + 1;

        if (REALTIME_PREVIEW) begin
          case (pph)
            7'(PWORK): begin
              lfsr <= {lfsr[13:0], lfsr[14] ^ lfsr[13]};
              if (play_bits[pc_ch] && s_eff_a != 0)
                s_phase <= s_phase + {3'b0, einc};
              else if (play_bits[pc_ch]) begin
                s_phase <= 0;
                s_phase2 <= 0;
              end
              noise_filt_step(play_bits[pc_ch] && s_eff_a != 0);
            end
            7'(PWORK + 1): begin
              // The secondary synchronous read observes q during this cycle.
              // Advance it at the edge only after that address has captured
              // the same pre-advance sample state as p captured at PWORK.
              if (play_bits[pc_ch] && s_eff_a != 0 && v2_on)
                s_phase2 <= s_phase2 + preview_v2inc;
              smp_a <= s_snd_wt ? 18'($signed(seq_q)) : z_eval;
            end
            7'(PWORK + 2): begin
              smp_b <= s_snd_wt ? 18'($signed(seq_q)) : z_eval;
              stage_leaf();
            end
            7'(PFOLD): fold_launch();
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
            if (play_bits[pc_ch] && s_eff_a != 0) begin
              if (!s_snd_wt) begin
                s_phase <= pha_y;
              end else begin
                wt_pf <= s_phase[17:8];
                wt_qf <= q16[9:0];
              end
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
            if (play_bits[pc_ch]
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
            noise_filt_step(play_bits[pc_ch] && s_eff_a != 0);
          end
          ctrl_q[CTRL_W1]: begin           // main-voice sample
            // Keep q's synchronous ROM address on the pre-advance phase,
            // matching PICO-8's render-then-advance oscillator ordering.
            if (play_bits[pc_ch] && s_eff_a != 0 && s_snd_wt)
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
            if (play_bits[pc_ch] || !(is_mus(pc_ch) && mus_playing))
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
            end else
              // The first G*z limb pass launches this cycle.
              stage_leaf();
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
            if (play_bits[pc_ch] && s_eff_a != 0)
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
            if (s_snd_wt)
              stage_leaf();
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
          ctrl_q[CTRL_FOLD]: fold_launch();      // fold into the tree
          default: ;
        endcase
        end
      end
    end
  end


endmodule

`endif
