// PICO-8-compatible PSG top level.
//
// The CPU uploads the native $3100-$42ff music/SFX image through $00-$02.
// Four foreground SFX slots and four music slots are sequenced at one tick
// per 183 samples; psg_walk serializes all eight voices at 22.05 kHz.
//
// Control/status registers:
//   $03     foreground busy bits and music-active bit
//   $10-$13 play, stop, or release foreground SFX; read audible row
//   $14-$17 next-trigger start row; read audible SFX number
//   $18-$1b next-trigger length
//   $20     start/stop music; read current pattern
//   $21     advisory channel-reservation mask
//   $22     fade length for the next music start/stop
//
// This module owns only composition, bus write edge detection, shared-service
// arbitration, the PCM output register, and readback/debug muxes.

`include "psg_common.svh"

// Submodules are textually included because chip and synthesis targets include
// psg.sv as their single PSG source. Include guards keep explicit file lists safe.
`include "psg_timing.sv"
`include "psg_aram.sv"
`include "psg_mulsvc.sv"
`include "psg_divsvc.sv"
`include "psg_state_mem.sv"
`include "psg_wave.sv"
`include "psg_walk.sv"
`include "psg_seq.sv"

module psg #(parameter CLK_HZ = 32'd3_506_580, parameter REVERB = 1,
             parameter REALTIME_PREVIEW = 0, parameter DBG_PORT = 1)
          (input bit clk, input bit reset,
           input bit cs, input bit rw, input logic [7:0] addr, input logic [7:0] di,
           output logic [7:0] dout,
           output logic signed [15:0] pcm,

           // Optional simulator trace: pattern, slot activity, SFX ids, rows.
           output logic [63:0] dbg);

  // Timing grid. pre_tick precedes tick_en by six sample intervals;
  // tick_en_d marks the sample two intervals after tick_en.
  logic        sample_en;
  logic [7:0]  scnt;
  logic        tick_en, tick_en_d;
  logic        pre_tick;

  psg_timing #(.CLK_HZ(CLK_HZ)) u_timing(
    .clk(clk), .reset(reset),
    .sample_en(sample_en), .tick_en(tick_en), .tick_en_d(tick_en_d),
    .pre_tick(pre_tick), .scnt(scnt));

  wire  [12:0] seq_addr;
  wire  [7:0]  seq_q;
  wire         syn_rd;
  wire  [12:0] syn_addr;
  wire         seq_frozen;

  wire         state_replay;

  // The sequencer advances only while neither shared memory nor the synthesis
  // pipeline is owned by the sample walk.
  wire         prun, fold_busy;
  wire         walk_frozen = seq_frozen | prun | state_replay | fold_busy;

  // Convert a level-style bus write into one pulse in the PSG clock domain.
  // Reads retain level semantics.
  logic cs_wr_q;
  always_ff @(posedge clk) cs_wr_q <= cs && rw;
  wire  cs_wr = (cs && rw) && !cs_wr_q;

  psg_aram u_aram(
    .clk(clk), .reset(reset),
    .cs(cs_wr), .rw(rw), .addr(addr), .di(di),
    .seq_addr(seq_addr), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .seq_q(seq_q), .seq_frozen(seq_frozen));

  // Shared arithmetic services.
  wire  [33:0] m_res;
  wire         m_busy;

  wire         div_start;
  logic [23:0] div_n;
  logic [7:0]  div_d;
  wire  [23:0] d_res;
  wire  [7:0]  d_rem;
  wire         d_busy;

  psg_divsvc u_div(
    .clk(clk), .reset(reset),
    .div_start(div_start), .div_n(div_n), .div_d(div_d),
    .d_res(d_res), .d_rem(d_rem), .d_busy(d_busy));

  psg_state_mem u_state(
    .clk(clk), .reset(reset),
    .wlk_rd(state_sample_read), .wlk_ra(wlk_ra),
    .wlk_we(state_sample_we), .wlk_wa(wlk_wa), .wlk_wd(wlk_wd),
    .etk_ra(etk_ra), .etk_we(etk_we), .etk_wa(etk_wa), .etk_wd(etk_wd),
    .prun(prun), .state_replay(state_replay), .state_q(state_q));

  // The full schedule renders crossfades and reverb. Preview uses the compact
  // schedule and disables unreachable reverb phases at elaboration time.
  psg_walk #(.REVERB(REVERB && !REALTIME_PREVIEW),
             .REALTIME_PREVIEW(REALTIME_PREVIEW)) u_walk(
    .clk(clk), .reset(reset), .sample_en(sample_en),
    .play_bits(play_bits), .mus_playing(mus_playing),
    .spar_bank(spar_bank), .clr_tog(clr_tog), .clr_ack(clr_ack),
    .seq_q(seq_q), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .state_q(state_q),
    .state_sample_read(state_sample_read), .wlk_ra(wlk_ra),
    .state_sample_we(state_sample_we), .wlk_wa(wlk_wa), .wlk_wd(wlk_wd),
    .m_res(m_res), .m_busy(m_busy),
    .wmul_start(wmul_start), .wmul_a(wmul_a), .wmul_b(wmul_b),
    .wmul_mode(wmul_mode), .wmul_short(wmul_short),
    .iss_sec(iss_sec), .iss_om(iss_om), .iss_os(iss_os),
    .dq_old_ctx(dq_old_ctx),
    .s_snd_wave(s_snd_wave), .s_snd_wt(s_snd_wt), .s_ch_det(s_ch_det),
    .s_ch_buzz(s_ch_buzz), .s_phase(s_phase), .s_phase2(s_phase2),
    .s_eff_inc(s_eff_inc), .s_old_wave(s_old_wave),
    .s_old_phase(s_old_phase), .s_old_inc(s_old_inc),
    .old_mode_r(old_mode_r), .old_alt_r(old_alt_r), .old_q0(old_q0),
    .z_eval(z_eval), .dq17(dq17), .q16(q16),
    .ctrl_q(ctrl_q), .ctrl_addr(ctrl_addr),
    .prun(prun), .fold_busy(fold_busy),
    .dry16(dry16), .dry_valid(dry_valid));

  wire        state_sample_read, state_sample_we;
  wire [PSG_VADR-1:0] wlk_ra, wlk_wa;
  wire [15:0] wlk_wd;
  wire        wmul_start;
  wire signed [24:0] wmul_a;
  wire [11:0] wmul_b;
  wire [1:0]  wmul_mode;
  wire        wmul_short;
  wire        iss_sec, iss_om, iss_os, dq_old_ctx;
  wire [2:0]  s_snd_wave, s_old_wave;
  wire        s_snd_wt, s_ch_buzz;
  wire [1:0]  s_ch_det, old_mode_r;
  wire        old_alt_r;
  wire [23:0] s_phase, s_phase2, s_old_phase;
  wire [20:0] s_eff_inc, s_old_inc;
  wire [16:0] old_q0;
  wire [15:0] ctrl_q;
  wire [7:0]  ctrl_addr;
  wire [PSG_NV-1:0] clr_ack;
  wire signed [15:0] dry16;
  wire        dry_valid;

  // Combinational waveform evaluation shared by the walk's live, secondary,
  // and previous-voice contexts.
  psg_wave #(.REALTIME_PREVIEW(REALTIME_PREVIEW)) u_wave(
    .clk(clk),
    .iss_sec(iss_sec), .iss_om(iss_om), .iss_os(iss_os),
    .dq_old_ctx(dq_old_ctx),
    .s_snd_wave(s_snd_wave), .s_snd_wt(s_snd_wt), .s_ch_det(s_ch_det),
    .s_ch_buzz(s_ch_buzz), .s_phase_hi(s_phase[23:8]), .s_phase2(s_phase2),
    .s_eff_inc_hi(s_eff_inc[20:8]),
    .s_old_wave(s_old_wave), .s_old_phase_hi(s_old_phase[23:8]),
    .s_old_inc_hi(s_old_inc[20:8]), .old_mode_r(old_mode_r),
    .old_alt_r(old_alt_r), .old_q0_lo(old_q0[15:0]),
    .z_eval(z_eval), .dq17(dq17), .q16(q16));

  wire signed [17:0] z_eval;
  wire [16:0] dq17;
  wire [15:0] q16;

  // Walk and sequencer requests are mutually exclusive under walk_frozen, so
  // their zero-when-idle bundles merge with OR gates. The assertion protects
  // that interface invariant in simulation.
  wire        mul_start = wmul_start | smul_start;
  wire signed [24:0] mul_start_a = wmul_a | smul_a;
  wire [11:0] mul_start_b        = wmul_b | smul_b;
  wire [1:0]  mul_start_mode     = wmul_mode | smul_mode;
  wire        mul_start_short    = wmul_short | smul_short;
`ifndef SYNTHESIS
  always @(posedge clk) if (!reset && wmul_start && smul_start)
    $fatal(1, "psg: both multiply requesters asserted in the same cycle");
`endif

  psg_mulsvc u_mul(
    .clk(clk), .reset(reset),
    .mul_start(mul_start), .mul_start_a(mul_start_a),
    .mul_start_b(mul_start_b), .mul_start_mode(mul_start_mode),
    .mul_start_short(mul_start_short),
    .m_res(m_res), .m_busy(m_busy));

  // Tick-rate note/effect/music control.
  psg_seq u_seq(
    .clk(clk), .reset(reset),
    .cs(cs_wr), .rw(rw), .addr(addr), .di(di),
    .play_bits(play_bits), .trig_req(trig_req),
    .aud_sfx_bits(aud_sfx_bits), .aud_row_bits(aud_row_bits),
    .mus_playing(mus_playing), .mus_pat(mus_pat), .mus_mask(mus_mask),
    .fade_len(fade_len),
    .sample_en(sample_en), .tick_en_d(tick_en_d), .pre_tick(pre_tick),
    .scnt(scnt),
    .walk_frozen(walk_frozen), .spar_bank(spar_bank),
    .clr_tog(clr_tog), .bank_ready(bank_ready),
    .seq_addr(seq_addr), .seq_q(seq_q),
    .state_q(state_q), .state_replay(state_replay),
    .etk_ra(etk_ra), .etk_we(etk_we), .etk_wa(etk_wa), .etk_wd(etk_wd),
    .m_res(m_res), .m_busy(m_busy),
    .smul_start(smul_start), .smul_a(smul_a), .smul_b(smul_b),
    .smul_mode(smul_mode), .smul_short(smul_short),
    .div_start(div_start), .div_n(div_n), .div_d(div_d),
    .d_res(d_res), .d_rem(d_rem), .d_busy(d_busy),
    .ctrl_read(prun), .ctrl_addr(ctrl_addr), .ctrl_q(ctrl_q));

  wire [PSG_NV-1:0] play_bits, trig_req, clr_tog;
  wire [PSG_NCH*6-1:0] aud_sfx_bits;
  wire [PSG_NCH*5-1:0] aud_row_bits;
  wire        mus_playing, spar_bank, bank_ready;
  wire [5:0]  mus_pat;
  wire [3:0]  mus_mask;
  wire [7:0]  fade_len;
  wire [15:0] state_q;
  wire [PSG_VADR-1:0] etk_ra, etk_wa;
  wire [15:0] etk_wd;
  wire        etk_we;
  wire        smul_start;
  wire signed [24:0] smul_a;
  wire [11:0] smul_b;
  wire [1:0]  smul_mode;
  wire        smul_short;

  // dry_valid commits one completed eight-slot reduction.
  always_ff @(posedge clk) begin
    if (reset) pcm <= 16'sd0;
    else if (dry_valid) pcm <= dry16;
  end

  // CPU readback. Channel row/SFX reads report the audible slot: foreground
  // while it plays, otherwise the continuously advancing music slot.
  always_ff @(posedge clk) begin
    if (reset) begin
      dout <= 0;
    end else if (cs && !rw) begin
      case (addr)

        8'h03: dout <= {mus_playing, 3'b0,
                        play_bits[3:0] | trig_req[3:0]};
        8'h20: dout <= {2'b0, mus_pat};

        8'h21: dout <= {4'b0, mus_mask};
        8'h22: dout <= fade_len;
        default:
          if (addr[7:4] == 4'h1)

            dout <= (addr[3:2] == 2'd1)
                      ? {play_bits[aud_sl(addr[1:0], play_bits)], 1'b0,
                         aud_sfx_bits[addr[1:0]*6 +: 6]}
                      : {play_bits[aud_sl(addr[1:0], play_bits)], 2'b0,
                         aud_row_bits[addr[1:0]*5 +: 5]};
          else
            dout <= 8'h00;
      endcase
    end
  end

  // Keep debug generation removable when no hardware consumer exists.
  generate
  if (DBG_PORT) begin : g_dbg
    always_comb begin
      dbg = 64'b0;
      dbg[7:0]   = {mus_playing, 1'b0, mus_pat};
      dbg[11:8]  = play_bits[3:0];
      dbg[15:12] = play_bits[7:4];
      for (int ch = 0; ch < PSG_NCH; ch++) begin
        dbg[16 + ch*6 +: 6] = aud_sfx_bits[ch*6 +: 6];
        dbg[40 + ch*6 +: 6] = {1'b0, aud_row_bits[ch*5 +: 5]};
      end
    end
  end else begin : g_no_dbg
    always_comb dbg = 64'b0;
  end
  endgenerate

endmodule

// Record macros must remain visible through every included submodule, then be
// removed before the including compilation unit continues.
`undef PSG_REC_W3
`undef PSG_REC_W4
`undef PSG_REC_W5
`undef PSG_REC_W9
`undef PSG_OSC_W14
`undef PSG_OSC_W17
`undef PSG_OSC_W22
