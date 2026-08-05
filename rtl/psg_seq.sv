// Tick-rate PSG sequencer.
//
// A pre_tick request runs a serialized visit over all eight playback slots.
// Each visit loads its record, advances row/instrument state, evaluates effects,
// writes the inactive sounding bank, and stores the record. The bank flips only
// after all visits complete. CPU triggers and music flow share the same FSM.
//
// Reading guide: c is the slot, sst is the serialized program state, vcnt is
// the record-word index, and xs is the effect-arithmetic substep. w_* is the
// current slot's register-resident record; publication writes its completed
// sounding tuple to the bank opposite spar_bank.

`ifndef PSG_SEQ_SV
`define PSG_SEQ_SV

module psg_seq (input  bit   clk,
                input  bit   reset,

                // CPU control-write pulse and status exported to psg.sv.
                input  bit   cs,
                input  bit   rw,
                input  logic [7:0] addr,
                input  logic [7:0] di,
                output logic [PSG_NV-1:0] play_bits,
                output logic [PSG_NV-1:0] trig_req,

                output logic [5:0] rb_sfx,

                // CPU wait-state lane. sfx_id lives in state-memory word
                // PSG_V_SFX; a CPU access commits only while the engine idles
                // and the walk is off the needed port. cpu_stall holds the
                // CPU's RDY low until then, so `cs` pulses exactly at commit.
                input  logic wr_pend,
                input  logic rd_lvl,
                input  logic wlk_we_i,
                input  logic wlk_rd_i,
                output logic cpu_stall,
                output logic mus_playing,
                output logic [5:0] mus_pat,
                output logic [3:0] mus_mask,
                output logic [7:0] fade_len,

                // Timing grid and synthesis-walk exclusion.
                input  logic sample_en,
                input  logic tick_en_d,
                input  logic pre_tick,
                input  logic [7:0] scnt,

                input  logic walk_frozen,
                output logic spar_bank,
                output logic [PSG_NV-1:0] clr_tog,
                output logic bank_ready,

                // Shared audio-RAM read port.
                output logic [12:0] seq_addr,
                input  logic [7:0]  seq_q,

                // Sequencer side of the shared per-slot state memory.
                input  logic [15:0] state_q,
                input  logic        state_replay,
                output logic [PSG_VADR-1:0] etk_ra,
                output logic        etk_we,
                output logic [PSG_VADR-1:0] etk_wa,
                output logic [15:0] etk_wd,

                // Sequencer side of the shared magnitude multiplier.
                input  logic [33:0] m_res,
                input  logic        m_busy,
                output logic        smul_start,
                output logic signed [24:0] smul_a,
                output logic [11:0] smul_b,
                output logic [1:0]  smul_mode,
                output logic        smul_short,

                // Dedicated exact divider used by slide and volume effects.
                output logic        div_start,
                output logic [23:0] div_n,
                output logic [7:0]  div_d,
                input  logic [23:0] d_res,
                input  logic [7:0]  d_rem,
                input  logic        d_busy,

                // The sample walk reads control words during idle crom cycles.
                input  logic        ctrl_read,
                input  logic [7:0]  ctrl_addr,
                output logic [15:0] ctrl_q,
                output logic        ctrl_stall);
  // ---- Tables, persistent slot state, and CPU-visible status ----
  // Pitch increments, slide/fade constants, and synthesis control words.
  logic [15:0] crom[0:255];
  initial begin
    $readmemh("./rtl/psg_const.hex", crom);
  end

  // Slots 0..3 are foreground effects and 4..7 are music. Both members of a
  // channel pair advance; the foreground slot masks music only at the mixer.
  logic        playing[0:PSG_NV-1];

  assign play_bits = {playing[7], playing[6], playing[5], playing[4],
                      playing[3], playing[2], playing[1], playing[0]};
  logic [4:0]  w_row;
  logic        w_clr_tog;

  // Working copy of the in-service slot's sfx_id (state word PSG_V_SFX).
  logic [5:0]  w_sfx;

  // CPU SFX registers address foreground slots only.
  wire [PSG_VW-1:0] fg_sl = {1'b0, addr[1:0]};

  // Start row/length live in state words PSG_V_TROW/PSG_V_TLEN of the
  // foreground voice (CPU-written through the wait-state lane, consumed and
  // cleared by the next trigger). The audible row is served straight from
  // word PSG_V_SEQ on readback: word 32 and the old aud_row register were
  // provably equal whenever the CPU could observe them, because reads only
  // commit while the engine idles.
  logic [4:0]  w_trg_row;
  logic [5:0]  w_trg_len;
  logic        released[0:PSG_NV-1];

  // ---- Current-slot record working set ----
  // w_* mirrors the current slot record; vcnt selects each load/store word.
  // acc/wrd hold counter, loop, and speed fields modified by the engine below.
  logic        join_stage;
  logic [15:0] vwdata;
  logic [3:0]  vcnt;

  logic [5:0]  w_cur_pitch, w_prev_pitch;
  logic [2:0]  w_cur_wave, w_cur_vol, w_cur_fx, w_prev_vol;
  logic        w_bf_noiz, w_bf_buzz;
  logic [1:0]  w_bf_det, w_bf_rev, w_bf_damp;
  logic        w_ins_on, w_ins_wt, w_ins_done;
  logic [2:0]  w_ins_id;
  logic [4:0]  w_ins_row;
  logic [5:0]  w_ins_pitch, w_ins_prev_pitch;
  logic [2:0]  w_ins_wave, w_ins_vol, w_ins_fx, w_ins_prev_vol;

  logic [15:0] acc;
  logic [13:0] wrd;
  logic        abank;
  logic        froll;
  logic        ge_lpe;

  logic [7:0]  eff_sp, eff_fcnt;

  logic [3:0]  eff_tcnt;

  // Pack the working fields for the V_ST record-store sequence.
  always_comb begin
    case (vcnt)
      4'd0: vwdata = `PSG_REC_W3;
      4'd1: vwdata = `PSG_REC_W4;
      4'd2: vwdata = `PSG_REC_W5;
      4'd4: vwdata = {10'b0, w_clr_tog, w_row};
      default: vwdata = {2'b0, `PSG_REC_W9};
    endcase
  end

  logic        w_ch_noiz, w_ch_buzz;
  logic [1:0]  w_ch_det, w_ch_rev, w_ch_damp;
  // ---- Bank publication, stop timing, music flow, and fades ----
  // Stops are delayed to the sample where the corresponding parameter bank is
  // visible. pend_stop2 is the one-sample-later music-flow class.
  logic [PSG_NV-1:0] pend_stop, pend_stop2;
  logic          ml_cpu;

  logic        mus_launch;
  logic [PSG_NV-1:0] launched;
  logic        ptick_seen, f_lb, f_stop;
  // ptick_* is the music-pattern pacing accumulator and pending product.
  logic [12:0] pticks, ptick_tgt;
  logic        ptick_pend;

  logic [7:0]  mus_gain;
  logic [1:0]  fade_dir;
  logic [15:0] fade_acc;
  logic [12:0] fade_step;

  // One sum, four consumers: [16] is the wrap test, [15:0] the next
  // accumulator, [15:8] the published gain byte. Spelling it once keeps a
  // single 17-bit chain instead of a 17-bit test plus a separately inferred
  // 16-bit accumulate. Exact by construction - the low sixteen bits of the
  // 17-bit sum are the 16-bit truncating add the three consumers used.
  wire [16:0] fade_sum = {1'b0, fade_acc} + {4'b0, fade_step};

  logic [12:0] fstep_q;

  // ---- Serialized tick program and current-slot control ----
  // State families: T loads a trigger; EA advances row/instrument counters;
  // ES loads effect counters; K evaluates note/effect work; I handles custom
  // instruments; P publishes a new bank; PC copies an unchanged bank; V moves
  // the register-resident record; ML launches music and MS scans loop-back.
  typedef enum logic [5:0] {
    S_IDLE,
    T_FL, T_SP, T_LS, T_LE, T_NL, T_NH, T_LD,
    K_ADV, K_NL, K_NH, K_LD, K_ARP, K_ARPC,
    K_PF0, K_FX,
    K_SL0, K_SL1, K_SL2, K_SL3, K_SL4, K_SL5, K_SL6, K_SL7, K_SL8,

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

  logic [PSG_VW-1:0] c;

  // One compare implements counter rollover, loop end, and record end.
  wire [4:0] arow = abank ? w_ins_row : w_row;

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

  // Evaluated slots write the inactive sounding bank directly. Skipped slots
  // copy their active bank; cpz zeroes the copied amplitude after a stop.
  logic        cpz;
  logic        walk_tick;
  logic        tickpend;

  logic        flip_pend;
  logic [5:0]  scan_p;
  logic [7:0]  note_lo;
  logic [5:0]  arp_p;

  wire [12:0] ch_base  = rec_base(w_sfx);
  wire [12:0] ins_base = rec_base({3'b0, w_ins_id});

  // ---- Effective instrument and effect selection ----
  // A custom instrument is an SFX playhead unless marked as a wavetable.
  wire ins_use = w_ins_on & ~w_ins_wt;

  wire fx_dfl = (w_cur_fx == 3'd0) || (w_cur_fx == 3'd3);

  wire [2:0] nfx      = (w_ins_on && w_cur_fx == 3'd3) ? 3'd0 : w_cur_fx;
  wire       e_insfx  = ins_use && nfx == 3'd0 && w_ins_fx != 3'd0;
  wire [2:0] e_fx     = e_insfx ? w_ins_fx   : nfx;

  logic [1:0] arp_idx;
  always_comb begin
    if (e_fx == 3'd6)
      arp_idx = (eff_sp <= 8) ? eff_tcnt[1:0] : eff_tcnt[2:1];
    else
      arp_idx = (eff_sp <= 8) ? eff_tcnt[2:1] : eff_tcnt[3:2];
  end
  // ---- Audio-RAM and control-ROM synchronous read schedules ----
  // Audio-RAM address generation is a synchronous schedule keyed by FSM state.
  // seq_hold preserves the state/address while another shared owner is active.
  logic [12:0] sa_base;
  logic [7:0]  sa_off;
  logic        sa_pat;
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

  wire [5:0] pat_rows = (acc[7:0] != 0 && seq_q == 0)
                          ? ((acc[7:0] < 8'd32) ? acc[5:0] : 6'd32) : 6'd32;

  function automatic logic [5:0] fdec(input logic [4:0] n);
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

  wire [5:0] fdv    = fdec(seq_q[7:3]);
  wire [1:0] f_det  = fdv[1:0];
  wire [1:0] f_rev  = fdv[3:2];
  wire [1:0] f_damp = fdv[5:4];

  function automatic logic [5:0] pclamp(input logic signed [7:0] v);
    pclamp = v[7] ? 6'd0 : v[6] ? 6'd63 : v[5:0];
  endfunction

  wire signed [7:0] pp_raw = $signed({2'b0, w_prev_pitch})
                           + $signed({2'b0, w_ins_prev_pitch}) - 8'sd24;
  wire [5:0] e_prevp = ins_use ? pclamp(pp_raw) : w_prev_pitch;

  logic [7:0]  pinc_addr;
  logic [15:0] crom_q;

  assign ctrl_q = crom_q;
  wire         fade_issue = cs && rw && addr == 8'h22;
  wire         trg_len_over = (|di[7:6]) || (di[5] && (|di[4:0]));
  logic        crom_replay;
  logic        ctrl_displaced;

  wire         seq_hold = walk_frozen | fade_issue | crom_replay;
  assign ctrl_stall = ctrl_displaced;

  // ---- Pitch, effect, slide, volume, and shared-service arithmetic ----
  // Effect intermediates persist across shared multiply/divide requests.
  wire [12:0] pinc_q = crom_q[12:0];
  // Slide setup and pitch-ROM address generation never consume the ordinary
  // and arpeggiated pitches together. Select their operands before the shared
  // add-and-clamp cone; K_SL0/K_SL1 naturally select the ordinary pitch.
  wire use_arp_pitch = (sst == K_PF0)
      || ((sst == K_FX || sst == P_W0 || sst == P_W1)
          && e_fx[2] && e_fx[1]);
  wire [5:0] pitch_a = use_arp_pitch ? arp_p : w_cur_pitch;
  wire [5:0] pitch_b = (use_arp_pitch && e_insfx)
                         ? w_cur_pitch : w_ins_pitch;
  wire signed [7:0] pitch_raw = $signed({2'b0, pitch_a})
                              + $signed({2'b0, pitch_b}) - 8'sd24;
  wire [5:0] e_pitch = ins_use ? pclamp(pitch_raw) : pitch_a;

  always_comb begin
    case (sst)

      K_PF0:   pinc_addr = {2'b0, e_pitch};

      // Effects 6/7 publish the arpeggiated pitch-table result. Keep that
      // synchronous lookup selected until the two inactive-bank increment
      // words have been written; every other ordinary effect uses e_pitch.
      K_FX:    pinc_addr = {2'b0, e_pitch};

      K_SL2:   pinc_addr = 8'd64 + {2'b0, sl_chr[3:0], 2'd0};
      K_SL3:   pinc_addr = 8'd64 + {2'b0, sl_chr[3:0], 2'd1};
      K_SL4:   pinc_addr = 8'd64 + {2'b0, sl_chr[3:0], 2'd2};
      K_SL5,
      K_SL6:   pinc_addr = 8'd64 + {2'b0, sl_chr[3:0], 2'd3};
      K_SL7,
      K_SL8:   pinc_addr = 8'd36 + {2'b0, sl_chr};
      P_W0,
      P_W1:    pinc_addr = (e_fx == 3'd1)
                              ? 8'd36 + {2'b0, sl_chr}
                              : {2'b0, e_pitch};
      default: pinc_addr = {2'b0, e_pitch};
    endcase
    if (fade_issue)
      pinc_addr = 8'd112 + {3'b0, di[7:3]};
  end
  always_ff @(posedge clk) begin
    // A fade-table read may land while the sample walk streams control words.
    // Give the CPU lookup this cycle, then hold the walker for one phase while
    // its displaced word is reissued. Adjacent $22/$20 writes still consume
    // crom_q directly on the replay cycle.
    crom_q <= crom[(ctrl_read && !fade_issue) ? ctrl_addr : pinc_addr];
    if (reset) begin
      crom_replay    <= 1'b0;
      ctrl_displaced <= 1'b0;
    end else begin
      crom_replay    <= fade_issue;
      ctrl_displaced <= fade_issue && ctrl_read;
      if (crom_replay)
        fstep_q <= crom_q[12:0];
    end
  end

  wire [12:0] base_inc = pinc_q;

  wire [11:0] vol_direct  = w_ins_done ? 12'd0 : {1'b0, w_cur_vol, 8'b0};
  wire [11:0] pvol_direct = {1'b0, w_prev_vol, 8'b0};

  logic [3:0]  xs;

  logic [11:0] vol_r;

  logic signed [2:0] lfo;
  always_comb begin
    case (eff_tcnt[2:0])
      3'd1, 3'd3: lfo =  3'sd1;
      3'd2:       lfo =  3'sd2;
      3'd5, 3'd7: lfo = -3'sd1;
      3'd6:       lfo = -3'sd2;
      default:    lfo =  3'sd0;
    endcase
  end
  wire       lfo_neg = lfo[2];
  wire [1:0] lfo_mag = lfo_neg ? 2'(-lfo) : 2'(lfo);

  wire [11:0] pvol_now = e_insfx ? {1'b0, w_ins_prev_vol, 8'b0}
                                 : pvol_direct;
  wire signed [12:0] vl_d   = $signed({1'b0, vol_r})
                             - $signed({1'b0, pvol_now});
  wire               vl_neg = vl_d[12];
  wire signed [6:0]  slp_d = $signed({1'b0, e_pitch})
                            - $signed({1'b0, e_prevp});
  wire               slp_neg = slp_d[6];

  logic [5:0]  sl_q1;
  logic [5:0]  sl_int;
  logic [15:0] sl_frac;
  wire  [15:0] sl_fmag = d_res[15:0];
  wire  [5:0]  sl_int_n = slp_neg
                            ? e_prevp - sl_q1 - 6'((|sl_fmag))
                            : e_prevp + sl_q1;

  wire sl_ge12 = sl_int[5] || sl_int[4] || (sl_int[3] && sl_int[2]);
  wire sl_ge24 = sl_int[5] || (sl_int[4] && sl_int[3]);
  wire sl_ge36 = sl_int[5] && (sl_int[4] || sl_int[3] || sl_int[2]);
  wire sl_ge48 = sl_int[5] && sl_int[4];
  wire sl_ge60 = &sl_int[5:2];
  wire [2:0] sl_oct = sl_ge60 ? 3'd5 : sl_ge48 ? 3'd4 : sl_ge36 ? 3'd3
                    : sl_ge24 ? 3'd2 : sl_ge12 ? 3'd1 : 3'd0;
  wire [5:0] sl_chr = sl_int - {sl_oct, 3'b0} - {1'b0, sl_oct, 2'b0};

  logic [8:0]  sl_bhi;
  logic [15:0] sl_rlo;
  logic [17:0] sl_uhi;
  wire  [29:0] sl_u = {crom_q[12:0], sl_rlo} + {2'b0, m_res[27:0]};
  wire  [25:0] sl_w = {8'b0, sl_uhi} + m_res[25:0];
  wire  [12:0] sl_dp_pre = crom_q[12:0] + {4'b0, sl_w[25:17]};

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

  // Vibrato scales the phase increment only by |lfo| = 0, 1, or 2. Spell that
  // product as wiring so it does not occupy a wide shared-service request arm.
  // vib_cb records whether the discarded /128 remainder is non-zero and
  // therefore supplies the signed rounding correction in fxp_res.
  wire [13:0] vib_full = lfo_mag[1] ? {base_inc, 1'b0}
                         : lfo_mag[0] ? {1'b0, base_inc} : 14'd0;
  wire        vib_cb  = |vib_full[6:0];
  wire [12:0] fxp_op  = {6'b0, vib_full[13:7]};
  wire [12:0] fxp_res = base_inc + (lfo_neg ? ~fxp_op : fxp_op)
                      + {12'b0, (lfo_neg & ~vib_cb)};
  logic [11:0] fxv_next;

  logic signed [24:0] mul_a;
  logic [11:0] mul_b;
  logic [1:0]  mul_md;
  logic        mul_go;
  always_comb begin
    mul_a = 25'sd0;
    mul_b = 12'd0;
    mul_md = 2'd0;
    mul_go = 1'b0;
    case (xs)

      4'd1: if (e_fx == 3'd1) begin

              mul_a = 25'(slp_d);
              mul_b = {4'b0, eff_fcnt};
              mul_go = 1'b1;
            end

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

      4'd8: if (ins_use) begin
              mul_a = e_insfx ? {14'b0, w_cur_vol, 8'b0} : {13'b0, vol_r};
              mul_b = e_insfx ? {8'b0, vol_r[11:8]} : {9'b0, w_ins_vol};
              mul_go = 1'b1;
            end
      4'd10: begin mul_a = {13'b0, a_post};
                   mul_b = {4'b0, mus_gain} + 12'd1; mul_md = 2'd1;
                   mul_go = 1'b1; end
      4'd4: case (e_fx)
              3'd3: begin mul_a = {12'b0, base_inc};
                          mul_b = eff_rem;
                          mul_go = 1'b1; end
              default: ;
            endcase
      default: ;
    endcase
  end

  // Slide uses two exact divisions; volume effects and instrument scaling use
  // the same divider with their own numerator and rounding rule.
  wire [11:0] a_post = ins_use ? d_res[11:0] : vol_r;

  wire vol_div = (e_fx == 3'd1) || (e_fx == 3'd4) || (e_fx == 3'd5);

  wire [11:0] eff_rem = {4'b0, eff_sp} - {4'b0, eff_fcnt};
  assign div_start = !seq_hold
                     && ((sst == K_FX && !m_busy
                          && ((xs == 4'd5 && e_fx == 3'd3)
                              || (xs == 4'd6 && vol_div)
                              || (xs == 4'd9 && ins_use)
                              || (xs == 4'd2 && e_fx == 3'd1)))
                         || (sst == K_SL0 && !d_busy));

  wire div_ceil = (sst == K_SL0) ? slp_neg
                                 : (xs == 4'd6 && e_fx == 3'd1 && vl_neg);
  wire [23:0] div_base = (sst == K_SL0) ? {d_rem, 16'b0} : m_res[27:4];
  always_comb begin
    div_d = (sst == K_FX && xs == 4'd9) ? 8'd7 : eff_sp;
    div_n = div_base + (div_ceil ? ({16'b0, eff_sp} - 24'd1) : 24'd0);
  end

  always_comb begin
    fxv_next = vol_r;
    case (e_fx)
      3'd1: fxv_next = pvol_now + (vl_neg ? ~d_res[11:0] : d_res[11:0])
                     + {11'b0, vl_neg};
      3'd4: fxv_next = d_res[11:0];
      3'd5: fxv_next = d_res[11:0];
      default: ;
    endcase
  end

  // The final increment is available before volume/instrument post-processing
  // finishes. Publish its two words immediately, then resume K_FX. The value
  // stays in address-selected storage, and both writes finish before the
  // inactive sounding bank flips atomically.
  logic [12:0] fxi_pub;
  always_comb begin
    fxi_pub = base_inc;
    case (e_fx)
      3'd1: fxi_pub = sl_dp;
      3'd2: fxi_pub = fxp_res;
      3'd3: fxi_pub = d_res[12:0];
      default: ;
    endcase
  end
  // ---- Inactive sounding-bank publication ----
  // Four words form the inactive sounding-parameter bank consumed by psg_walk.
  // Published increments use units of 2^7. Ordinary pitches append one zero;
  // the custom-instrument bass flag divides by two without losing its residue.
  wire [13:0] pub_inc = (w_ins_on && w_ins_wt && w_ins_fx[0])
                          ? {1'b0, fxi_pub} : {fxi_pub, 1'b0};

  wire [11:0] a_pub = vol_r;
  logic [15:0] pub_wd;
  always_comb begin
    case (sst)
      P_W0:    pub_wd = {pub_inc[8:0], 7'b0};
      P_W1:    pub_wd = {1'b0, w_ins_id, (w_ins_on & w_ins_wt),
                         (ins_use ? w_ins_wave
                          : (w_ins_on && w_ins_wt) ? 3'd0 : w_cur_wave),
                         3'b0, pub_inc[13:9]};
      P_W2:    pub_wd = {1'b0,
                         (w_cur_fx == 3'd1
                          || (ins_use && fx_dfl && w_ins_fx == 3'd1)),
                         w_ch_damp, w_ch_rev, w_ch_det, w_ch_buzz,
                         w_ch_noiz,

                         6'b0};
      default: pub_wd = {(ins_use && fx_dfl
                          && (w_ins_fx == 3'd0
                              || w_ins_fx == 3'd4
                              || w_ins_fx == 3'd5)),
                         ((!w_ins_on && w_cur_fx == 3'd3)
                          || (ins_use && fx_dfl && w_ins_fx == 3'd3)),
                         w_clr_tog,
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

  wire [2:0] note_wave = {seq_q[0], note_lo[7:6]};

  wire tnl_len_launch = launched[c] && !(acc[7:0] < seq_q);

  task cur_note_load();
    w_cur_pitch <= note_lo[5:0];
    w_cur_wave  <= note_wave;
    w_cur_vol   <= seq_q[3:1];
    w_cur_fx    <= seq_q[6:4];
  endtask

  // The sfx_id store itself goes through the state-memory write lane in the
  // ML_L* arms of the eng_we mux below.
  task ml_launch(input logic [1:0] ch);
    if (!seq_q[6]) begin
      trig_req[{1'b1, ch}] <= 1;
      launched[{1'b1, ch}] <= 1;
    end
  endtask

  task mus_stop(input logic [1:0] how);
    for (int i = PSG_NCH; i < PSG_NV; i++)
      case (how)
        2'd0:    playing[i] <= 0;
        2'd1:    pend_stop[i] <= 1;
        default: pend_stop2[i] <= 1;
      endcase
  endtask
  // ---- Sequential controller, boundary handshakes, and CPU commands ----
  // Main controller. FSM advancement and sequencer-owned stores pause under
  // seq_hold; boundary stop/flip handshakes remain active outside that guard.
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
      mus_mask <= 4'h0;
      // sfx_id is state-memory-resident (word PSG_V_SFX): power-on zeros come
      // from the memory initial; a mid-run reset leaves old ids in place,
      // which is unobservable while playing/trig_req are cleared.
      for (int i = 0; i < PSG_NV; i++) begin
        playing[i] <= 0;
        released[i] <= 0;
      end
      for (int i = 0; i < PSG_NCH; i++) begin
      end

      vcnt <= 0;
      spar_bank <= 0;
      join_stage <= 0;
      xs <= 0;
    end else begin

      if (ptick_pend && !m_busy) begin

        ptick_tgt <= m_res[18:6];
        ptick_pend <= 0;
      end
`ifndef SYNTHESIS
      if (!seq_hold && sst == T_NL && tnl_len_launch && m_busy)
        $error("T_NL pattern-length product blocked by a busy m service");
`endif

      if (tick_en_d) begin

        if (bank_ready && !(join_stage && sst != S_IDLE)) begin
          spar_bank <= ~spar_bank;
          bank_ready <= 0;
        end else if (tickpend || ((walk_tick || join_stage) && sst != S_IDLE))
          flip_pend <= 1;

        for (int i = 0; i < PSG_NV; i++)
          if (pend_stop[i]) playing[i] <= 0;
        pend_stop <= 0;
      end

      if (sample_en && scnt == 8'd3) begin
        for (int i = 0; i < PSG_NV; i++)
          if (pend_stop2[i]) playing[i] <= 0;
        pend_stop2 <= 0;
      end
      if (!seq_hold)
      case (sst)

        S_IDLE: begin

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

        V_LD: begin
          case (vcnt)
            4'd1: `PSG_REC_W3 <= state_q;
            4'd2: `PSG_REC_W4 <= state_q;
            4'd3: `PSG_REC_W5 <= state_q;
            4'd4: w_ins_pitch <= state_q[13:8];
            4'd5: `PSG_REC_W9 <= state_q[13:0];

            4'd6: {w_ch_damp, w_ch_rev, w_ch_det, w_ch_buzz, w_ch_noiz}
                    <= state_q[13:6];
            4'd7: {w_clr_tog, w_row} <= state_q[5:0];
            4'd8: w_sfx <= state_q[5:0];
            4'd9: w_trg_row <= state_q[4:0];
            4'd10: w_trg_len <= state_q[5:0];
            default: ;
          endcase
          if (vcnt == 4'd10) begin
            vcnt <= 0;
            sst <= K_ADV;
          end else
            vcnt <= vcnt + 1;
        end

        V_ST: begin

          if (vcnt == 4'd4) begin
            vcnt <= 0;
            if (c == PSG_VW'(PSG_NV-1)) begin
              c <= 0;

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

        // Trigger fetch and initial record setup.
        T_FL: begin
          trig_req[c] <= 0;
          pend_stop[c] <= 0;
          pend_stop2[c] <= 0;

          w_row <= is_mus(c) ? 5'd0 : w_trg_row;

          wrd[13:8] <= is_mus(c) ? 6'd0 : w_trg_len;
          // The consumed trigger words clear through the state-memory write
          // lane: T_FL zeroes PSG_V_TROW, T_SP zeroes PSG_V_TLEN.
          released[c] <= 0;
          w_prev_pitch <= 6'd24;
          w_prev_vol <= 0;
          playing[c] <= 1;
          w_ins_on <= 0;
          w_ins_done <= 0;
          clr_tog[c] <= ~clr_tog[c];
          w_clr_tog <= ~w_clr_tog;
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

          wrd[7:0] <= (seq_q == 0) ? 8'd1 : seq_q;
          sst <= T_LE;
        end
        T_LE: begin
          acc[7:0] <= seq_q;
          sst <= T_NL;
        end
        T_NL: begin

          if (launched[c]) begin
            if (!ptick_seen) begin
              ptick_seen <= 1;
              ptick_tgt <= {wrd[7:0], 5'b0};
            end
            if (tnl_len_launch) begin
              // The left-most launched non-looping channel owns pacing.  Its
              // acceptance consumes the launch worklist: ptick_seen already
              // captured the fallback speed, and no later mark remains live.
              launched <= 0;
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
          if (seq_q[7]) begin
            w_ins_on <= 1;
            w_ins_id <= note_wave;
            sst <= I_TR0;
          end else
            sst <= ES0;
        end

        // Row/instrument counter advance and loop/length decisions.
        K_ADV: begin
          if (trig_req[c]) begin
            sst <= T_FL;
          end else if (!walk_tick || !playing[c]) begin

            cpz <= !playing[c];
            sst <= K_ROT;
          end else begin
            abank <= 0;
            sst <= EA0;
          end
        end
        EA0: sst <= EA1;
        EA1: begin
          acc <= state_q;
          sst <= EA2;
        end
        EA2: begin

          wrd <= state_q[13:0];
          froll <= ta_ge;

          sst <= EA3;
        end
        EA3: begin
          acc <= state_q;
          if (!froll) begin

            if (!abank) begin
              if (ins_use) begin
                abank <= 1;
                sst <= EA0;
              end else
                sst <= ES0;
            end else
              sst <= I_NL;
          end else begin

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
          ge_lpe <= ta_ge;
          sst <= EA5;
        end
        EA5: begin

          if (!abank && wrd[13:8] != 0) begin

            if (wrd[13:8] == 6'd1 || w_row == 5'd31) begin
              pend_stop[c] <= 1;
              cpz <= 1;
              sst <= K_ROT;
            end else begin

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
              pend_stop[c] <= 1;
              cpz <= 1;
              sst <= K_ROT;
            end else begin
              w_ins_done <= 1;
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
        K_NL: sst <= K_NH;
        K_NH: begin
          note_lo <= seq_q;
          sst <= K_LD;
        end
        K_LD: begin
          cur_note_load();
          if (seq_q[7]) begin
            w_ins_on <= 1;
            w_ins_id <= note_wave;

            if (!w_ins_on || w_ins_id != note_wave ||
                note_lo[5:0] != w_prev_pitch || w_prev_vol == 0 ||
                seq_q[6:4] == 3'd3)
              sst <= I_TR0;
            else if (w_ins_wt)
              sst <= ES0;
            else begin
              abank <= 1;
              sst <= EA0;
            end
          end else begin
            w_ins_on <= 0;
            w_ch_noiz <= w_bf_noiz;
            w_ch_buzz <= w_bf_buzz;
            w_ch_det  <= w_bf_det;
            w_ch_rev  <= w_bf_rev;
            w_ch_damp <= w_bf_damp;
            sst <= ES0;
          end
        end

        // Custom-instrument trigger and note fetch.
        I_TR0: begin

          w_ins_row <= 0;
          w_ins_done <= 0;
          w_ins_prev_pitch <= 6'd24;
          w_ins_prev_vol <= 0;
          sst <= I_TR1;
        end
        I_TR1: begin
          w_ch_noiz <= w_bf_noiz | seq_q[1];
          w_ch_buzz <= w_bf_buzz | seq_q[2];
          w_ch_det  <= (f_det  > w_bf_det)  ? f_det  : w_bf_det;
          w_ch_rev  <= (f_rev  > w_bf_rev)  ? f_rev  : w_bf_rev;
          w_ch_damp <= (f_damp > w_bf_damp) ? f_damp : w_bf_damp;
          sst <= I_TR2;
        end
        I_TR2: begin

          wrd[7:0]   <= (seq_q == 0) ? 8'd1 : seq_q;
          w_ins_fx[0] <= seq_q[0];
          sst <= I_TR3;
        end
        I_TR3: begin
          acc[7:0]  <= seq_q;
          w_ins_wt  <= seq_q[7];
          sst <= I_TR4;
        end
        I_TR4: begin

          if (w_ins_wt) begin
            w_ins_pitch <= 6'd24;
            w_ins_prev_pitch <= 6'd24;
            w_ins_vol <= 3'd7;
            w_ins_prev_vol <= 3'd7;
            w_ins_fx <= {2'b0, w_ins_fx[0]};
            w_ins_wave <= 0;
            sst <= I_TW;
          end else
            sst <= I_NL;
        end
        I_TW: begin

          sst <= ES0;
        end

        I_NL: sst <= I_NH;
        I_NH: begin
          note_lo <= seq_q;
          sst <= I_LD;
        end
        I_LD: begin

          w_ins_pitch <= note_lo[5:0];
          w_ins_wave  <= note_wave;
          w_ins_vol   <= seq_q[3:1];
          w_ins_fx    <= seq_q[6:4];
          sst <= ES0;
        end

        ES0: sst <= ES1;
        ES1: begin
          eff_tcnt <= state_q[12:9];
          eff_fcnt <= state_q[7:0];
          sst <= ES2;
        end
        ES2: begin
          eff_sp <= state_q[7:0];
          sst <= K_ARP;
        end

        // Effect evaluation and exact slide interpolation.
        K_ARP:
          if (e_fx == 3'd6 || e_fx == 3'd7)
            sst <= K_ARPC;
          else
            sst <= K_PF0;
        K_ARPC: begin
          arp_p <= seq_q[5:0];
          sst <= K_PF0;
        end

        K_PF0: sst <= K_FX;

        K_FX: if (!m_busy && !((xs == 4'd7 || xs == 4'd10) && d_busy)) begin
          case (xs)

            4'd3: vol_r  <= (w_ins_done && ins_use) ? 12'd0
                          : e_insfx ? {1'b0, w_ins_vol, 8'b0}
                                    : vol_direct;
            4'd7: begin
              vol_r <= fxv_next;
            end
            4'd10: vol_r <= a_post;
            4'd11: if (is_mus(c)) vol_r <= m_res[21:10];
            default: ;
          endcase
          if (xs == 4'd2 && e_fx == 3'd1) begin

            sst <= K_SL0;
          end else if (xs == 4'd7 && e_fx != 3'd1) begin

            // The phase result is final. Publish it through P_W0/P_W1, then
            // resume volume and instrument processing at substep xs=8.
            xs <= 4'd8;
            sst <= P_W0;
          end else if (xs == 4'd11) begin

              xs <= 0;
              sst <= P_W2;
          end else begin
            xs    <= xs + 1;
          end
        end

        K_SL0: if (!d_busy) begin
          sl_q1 <= d_res[5:0];
          sst   <= K_SL1;
        end
        K_SL1: if (!d_busy) begin

          sl_frac <= slp_neg ? (16'd0 - sl_fmag) : sl_fmag;
          sl_int  <= sl_int_n;
          sst     <= K_SL2;
        end
        K_SL2: sst <= K_SL3;
        K_SL3: sst <= K_SL4;
        K_SL4: begin sl_bhi <= crom_q[8:0]; sst <= K_SL5; end
        K_SL5: begin sl_rlo <= crom_q;     sst <= K_SL6; end
        K_SL6: if (!m_busy) begin
          sl_uhi <= sl_u[29:12];
          sst    <= K_SL7;
        end
        K_SL7: sst <= K_SL8;
        K_SL8: if (!m_busy) begin
          // sl_dp depends on the final synchronous slide-table word. Publish
          // it before returning to K_FX, while that word and m_res are held.
          xs    <= 4'd3;
          sst   <= P_W0;
        end

        // Direct publication, or active-bank copy for a skipped slot.
        P_W0: sst <= P_W1;
        P_W1: sst <= K_FX;
        P_W2: sst <= P_W3;
        P_W3: begin
          vcnt <= 0;
          sst <= V_ST;
        end

        K_ROT: sst <= PC0;
        PC0: sst <= PC1;
        PC1: sst <= PC2;
        PC2: sst <= PC3;
        PC3: begin
          vcnt <= 0;
          sst <= V_ST;
        end

        // Pattern completion, loop-back scan, and next-pattern launch.
        W_MUS: begin
          sst <= S_IDLE;

          if (walk_tick && mus_playing && !mus_launch) begin
            pticks <= pticks + 1;

            if (trig_req == 0 && pticks + 13'd1 >= ptick_tgt) begin
              if (f_stop) begin
                mus_playing <= 0;
                mus_stop(2'd2);
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
        MS_RD: sst <= MS_CK;
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

        ML_STOP: begin

          mus_stop(ml_cpu ? 2'd0 : 2'd2);
          launched <= 0;
          sst <= ML_RD0;
        end

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
          ptick_seen <= 0;
          pticks <= 0;
          sst <= S_IDLE;
        end
        default: sst <= S_IDLE;
      endcase

      // Queue the tick pass and advance any active fade once per pre_tick.
      if (pre_tick) begin
        tickpend <= 1;
        if (fade_dir != 2'd0) begin
          if (fade_sum[16]) begin
            fade_acc <= 0;
            fade_dir <= 0;
            mus_gain <= 8'd255;
            if (fade_dir == 2'd2) begin
              mus_playing <= 0;
              mus_launch <= 0;
              mus_stop(2'd1);
            end
          end else begin
            fade_acc <= fade_sum[15:0];
            mus_gain <= (fade_dir == 2'd1)
                          ? fade_sum[15:8]
                          : 8'd255 - fade_sum[15:8];
          end
        end
      end

      // Foreground SFX control registers.
      if (cs && rw && addr[7:4] == 4'h1) begin
        case (addr[3:2])

          2'd0:
            if (di == 8'h81)
              released[fg_sl] <= 1;
            else if (di[7]) begin

              playing[fg_sl] <= 0;
              trig_req[fg_sl] <= 0;
            end else begin
              // sfx_id store rides the CPU state-memory lane this same
              // committed cycle; see cpu_sfx_commit below.
              trig_req[fg_sl] <= 1;

              playing[fg_sl] <= 0;
            end
          // 2'd1/2'd2 (trg_row/trg_len) land in state memory through the
          // CPU lane; see cpu_trg_commit below.
          default: ;
        endcase
      end
      // Music start/stop and fade control.
      if (cs && rw && addr == 8'h20) begin
        if (di[7]) begin
          if (fade_len >= 8'd8) begin
            fade_dir <= 2'd2;
            fade_acc <= 0;
            fade_step <= crom_replay ? crom_q[12:0] : fstep_q;
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
          if (fade_len >= 8'd8) begin
            fade_dir <= 2'd1;
            fade_acc <= 0;
            fade_step <= crom_replay ? crom_q[12:0] : fstep_q;
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

      // Reservation state is CPU-visible but does not gate playback.
      if (cs && rw && addr == 8'h21)
        mus_mask <= di[3:0];
    end
  end

  // ---- State-memory load/store and replay adapter ----
  // Register-resident record words visited by V_LD and V_ST.
  function automatic logic [5:0] tick_load_word(
      input logic [3:0] n, input logic bank);
    case (n)
      4'd0: tick_load_word = 6'd3;
      4'd1: tick_load_word = 6'd4;
      4'd2: tick_load_word = 6'd5;
      4'd3: tick_load_word = 6'd8;
      4'd4: tick_load_word = 6'd9;
      4'd6: tick_load_word = PSG_V_SEQ;
      4'd7: tick_load_word = PSG_V_SFX;
      4'd8: tick_load_word = PSG_V_TROW;
      4'd9: tick_load_word = PSG_V_TLEN;

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

  // State-memory read schedule. A displaced synchronous read reissues the
  // address selected for the preceding consume state.
  wire [5:0] par_act = spar_bank ? PSG_V_PAR1 : PSG_V_PAR0;
  wire [5:0] par_ina = spar_bank ? PSG_V_PAR0 : PSG_V_PAR1;

  wire [5:0] par_cpy = join_stage ? par_ina : par_act;
  logic       eng_rd;
  logic [5:0] eng_word;
  always_comb begin
    eng_rd = 1'b1;
    eng_word = 6'd0;
    case (sst)
      EA0:  eng_word = abank ? 6'd6 : 6'd0;
      EA1:  eng_word = seq_hold ? (abank ? 6'd6 : 6'd0)
                                : (abank ? 6'd8 : 6'd2);
      EA2:  eng_word = seq_hold ? (abank ? 6'd8 : 6'd2)
                                : (abank ? 6'd7 : 6'd1);
      EA3:  begin
              eng_word = abank ? 6'd7 : 6'd1;
              eng_rd = seq_hold;
            end
      ES0:  eng_word = e_insfx ? 6'd6 : 6'd0;
      ES1:  eng_word = seq_hold ? (e_insfx ? 6'd6 : 6'd0)
                                : (e_insfx ? 6'd8 : 6'd2);
      ES2:  begin
              eng_word = e_insfx ? 6'd8 : 6'd2;
              eng_rd = seq_hold;
            end

      K_ROT: eng_word = par_cpy;
      PC0:   eng_word = seq_hold ? par_cpy : par_cpy + 6'd1;
      PC1:   eng_word = seq_hold ? par_cpy + 6'd1 : par_cpy + 6'd2;
      PC2:   eng_word = seq_hold ? par_cpy + 6'd2 : par_cpy + 6'd3;
      PC3:   begin
               eng_word = par_cpy + 6'd3;
               eng_rd = seq_hold;
             end
      default: eng_rd = 1'b0;
    endcase
  end

  logic        eng_we;
  logic [PSG_VW-1:0] eng_va;
  logic [5:0]  eng_wa;
  logic [15:0] eng_wd;
  wire [7:0] sp_in = (seq_q == 0) ? 8'd1 : seq_q;

  // Trigger counter phase, modulo 32.
  wire [4:0] seed5 = 5'(w_row * sp_in[4:0]);
  always_comb begin
    eng_we = 1'b1;
    eng_wa = 6'd0;
    eng_wd = 16'd0;
    eng_va = c;
    case (sst)
      // Consumed foreground trigger words clear on the trigger path.
      T_FL: begin eng_wa = PSG_V_TROW; eng_wd = 16'd0;
                  eng_we = !is_mus(c); end
      T_SP: begin eng_wa = PSG_V_TLEN; eng_wd = 16'd0;
                  eng_we = !is_mus(c); end
      // Music launch: sfx_id of music slot {1,ch} into its PSG_V_SFX word.
      ML_L0: begin eng_va = 3'b100; eng_wa = PSG_V_SFX;
                   eng_wd = {10'b0, seq_q[5:0]}; eng_we = !seq_q[6]; end
      ML_L1: begin eng_va = 3'b101; eng_wa = PSG_V_SFX;
                   eng_wd = {10'b0, seq_q[5:0]}; eng_we = !seq_q[6]; end
      ML_L2: begin eng_va = 3'b110; eng_wa = PSG_V_SFX;
                   eng_wd = {10'b0, seq_q[5:0]}; eng_we = !seq_q[6]; end
      ML_L3: begin eng_va = 3'b111; eng_wa = PSG_V_SFX;
                   eng_wd = {10'b0, seq_q[5:0]}; eng_we = !seq_q[6]; end
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

               eng_wa = 6'd2;
               eng_wd = {2'b0, wrd[13:8] - 6'd1, wrd[7:0]};
               eng_we = !abank && wrd[13:8] != 0
                        && !(wrd[13:8] == 6'd1 || w_row == 5'd31);
             end

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
    if (seq_hold)
      eng_we = 1'b0;
  end

  wire state_tick_we = (sst == V_ST) && !seq_hold;
  logic [3:0] tick_issue;

  // Ledger: H165 established this lane (sfx_id, stage 1); H167 widened it
  // to the trigger words and retired aud_row into word PSG_V_SEQ readback.
  // ---- CPU wait-state lane ----
  // The sequencer lends its state-memory port halves to the CPU while idle.
  // Writes: the $10-$13 trigger form carries sfx_id; it commits on the first
  // cycle where the engine idles and the walk is not writing (the walk wins
  // the shared write mux). Reads: $14-$17 readback issues a one-cycle
  // address, captures state_q the next cycle, then releases the stall.
  wire cpu_sfx_wr_lvl = wr_pend && addr[7:4] == 4'h1 && addr[3:2] == 2'd0
                        && !di[7] && di != 8'h81;
  wire cpu_trg_wr_lvl = wr_pend && addr[7:4] == 4'h1
                        && (addr[3:2] == 2'd1 || addr[3:2] == 2'd2);
  // Every $1x readback is served from state memory: $14-$17 read the audible
  // slot's sfx id (word PSG_V_SFX), the rest its row (word PSG_V_SEQ).
  wire cpu_sfx_rd_lvl = rd_lvl && addr[7:4] == 4'h1;

  wire cpu_wr_lane_ok = (sst == S_IDLE) && !wlk_we_i;
  wire cpu_rd_lane_ok = (sst == S_IDLE) && !wlk_rd_i;

  // rb_done trails rb_valid by one cycle: the top-level dout register needs
  // one edge to capture rb_sfx before the stall releases.
  logic rb_issued, rb_valid, rb_done;
  wire  rb_take = cpu_sfx_rd_lvl && !rb_issued && cpu_rd_lane_ok;
  always_ff @(posedge clk) begin
    if (reset || !cpu_sfx_rd_lvl) begin
      rb_issued <= 0;
      rb_valid  <= 0;
      rb_done   <= 0;
    end else begin
      if (rb_take)
        rb_issued <= 1;
      if (rb_issued && !rb_valid) begin
        rb_sfx   <= state_q[5:0];
        rb_valid <= 1;
      end
      rb_done <= rb_valid;
    end
  end

  assign cpu_stall = ((cpu_sfx_wr_lvl || cpu_trg_wr_lvl) && !cpu_wr_lane_ok)
                   | (cpu_sfx_rd_lvl && !rb_done);

  // `cs` is the commit pulse: it only fires while cpu_stall is low, so the
  // lane conditions hold on the committing cycle by construction.
  wire cpu_sfx_commit = cs && rw && addr[7:4] == 4'h1 && addr[3:2] == 2'd0
                        && !di[7] && di != 8'h81;
  wire cpu_trg_commit = cs && rw && addr[7:4] == 4'h1
                        && (addr[3:2] == 2'd1 || addr[3:2] == 2'd2);

  assign etk_we = eng_we | state_tick_we | cpu_sfx_commit | cpu_trg_commit;
  always_comb begin

    tick_issue = vcnt;
    if (seq_hold && sst == V_LD && vcnt != 0)
      tick_issue = vcnt - 1'b1;

    etk_ra = eng_rd ? {c, eng_word}
                    : {c, tick_load_word(tick_issue, spar_bank)};
    if (rb_take)
      etk_ra = {aud_sl(addr[1:0], play_bits),
                (addr[3:2] == 2'd1) ? PSG_V_SFX : PSG_V_SEQ};
    if (cpu_sfx_commit) begin
      etk_wa = {fg_sl, PSG_V_SFX};
      etk_wd = {10'b0, di[5:0]};
    end else if (cpu_trg_commit) begin
      etk_wa = {fg_sl, (addr[3:2] == 2'd1) ? PSG_V_TROW : PSG_V_TLEN};
      etk_wd = (addr[3:2] == 2'd1)
                 ? {11'b0, di[4:0]}
                 : {10'b0, trg_len_over ? 6'd32 : di[5:0]};
    end else if (eng_we) begin
      etk_wa = {eng_va, eng_wa};
      etk_wd = eng_wd;
    end else begin
      etk_wa = {c, tick_store_word(vcnt, spar_bank)};
      etk_wd = vwdata;
    end
  end

  // ---- Zero-idle multiplier request adapter ----
  // Multiply request bundle. It is zero while held, allowing the top-level OR
  // merge with the mutually exclusive synthesis-walk request.
  always_comb begin
    smul_start = 1'b0;
    smul_a     = 25'sd0;
    smul_b     = 12'd0;
    smul_mode  = 2'd0;
    smul_short = 1'b0;
    if (!seq_hold) begin
      case (sst)

        K_FX: if (!m_busy && mul_go
                  && !((xs == 4'd7 || xs == 4'd10) && d_busy)
                  && !(xs == 4'd2 && e_fx == 3'd1)) begin
          smul_start   = 1'b1;
          smul_a = mul_a;
          smul_b = mul_b;
          smul_mode = mul_md;
        end

        // The slide's two affine passes share their A operand and their
        // mode; only the half of b they scale differs. Select the operand,
        // not the result - one 12-bit select instead of a second 25-bit arm.
        K_SL3, K_SL6: if (!m_busy) begin
          smul_start   = 1'b1;
          smul_a = {9'b0, sl_frac};
          smul_b = (sst == K_SL3) ? crom_q[11:0] : {3'b0, sl_bhi};
          smul_mode = 2'd2;
        end

        T_NL: if (tnl_len_launch) begin
          smul_start   = 1'b1;
          smul_a = {17'b0, wrd[7:0]};
          smul_b = {6'b0, pat_rows};
          smul_mode = 2'd1;
          smul_short = 1'b1;
        end
        default: ;
      endcase
    end
  end

endmodule

`endif
