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
//
// Data flows in two rates: psg_seq publishes one inactive sounding bank per
// tick, while psg_walk consumes the active bank and all eight oscillator
// records once per sample. psg_wave and the arithmetic services execute the
// walk/sequencer requests; dry_valid commits the completed eight-slot mix.

`include "psg_common.svh"

// Submodules are textually included because chip and synthesis targets include
// psg.sv as their single PSG source. Include guards keep explicit file lists
// safe.
`include "psg_timing.sv"
`include "psg_aram.sv"
`include "psg_mulsvc.sv"
`include "psg_mulmp.sv"
`include "psg_dqsvc.sv"
`include "psg_divsvc.sv"
`include "psg_state_mem.sv"
`include "psg_wave.sv"
`include "psg_walk.sv"
`include "psg_seq.sv"

module psg #(
    parameter CLK_HZ = 32'd3_506_580,
    parameter REVERB = 1,
    parameter REALTIME_PREVIEW = 0,
    parameter DBG_PORT = 1,
    parameter int SEQ_BUDGET = 272,
    parameter MULTIPUMP = 0
) (
    input  bit                 clk,
    input  bit                 fastclk,
    input  bit                 reset,

    input  bit                 cs,
    input  bit                 rw,
    input  logic [7:0]         addr,
    input  logic [7:0]         di,
    output logic [7:0]         dout,
    // Wait-state handshake: low while a migrated-register access is held;
    // AND into the CPU's RDY. Constant 1 when no access is stalled.
    output logic               rdy,
    output logic signed [15:0] pcm,

    // Optional simulator trace: pattern, slot activity, SFX ids, rows.
    output logic [63:0]        dbg
);
  // ---- Timing grid and per-sample sequencer budget ----
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
  wire         walk_busy = seq_frozen | prun | state_replay | fold_busy;

  // A fixed 272-credit sequencer window makes the program position at each
  // sample boundary a function of the sample index rather than the number of
  // clocks in that sample. The full walk and credits need 802 clocks/sample.
  // At the /6 clock ratio, 112.5/6 = 18.75 MHz provides at least 850 clocks,
  // leaving 48 clocks. Only cycles not owned by the sample walk consume this
  // window; its terminal state freezes the sequencer until the next sample.
  // There is no minimum-interval margin, so the simulation assertion below is
  // part of the clock contract rather than advisory.
  // Preview is exempt because it runs in the simulator's single 3.5 MHz
  // domain with its own compact schedule.
  logic seq_starved;
  generate
    if (!REALTIME_PREVIEW && SEQ_BUDGET == 272) begin : g_seq_budget_272
      // 239 -> 255 takes 16 advances. After that wrap, another 255 advances
      // reach {phase,count} = {1,255}: 16 + 256 = exactly 272 credits. This
      // shares one eight-bit terminal decode instead of a nine-bit zero test.
      logic [7:0] seq_count;
      logic       seq_phase;
      wire        seq_terminal = seq_phase && (&seq_count);

      always_ff @(posedge clk) begin
        if (reset || sample_en) begin
          seq_count <= 8'd239;
          seq_phase <= 1'b0;
        end else if (!walk_busy && !seq_terminal) begin
          seq_count <= seq_count + 1'b1;
          if (&seq_count)
            seq_phase <= 1'b1;
        end
      end
      always_comb seq_starved = seq_terminal;

`ifndef SYNTHESIS
      logic [2:0] budget_warm;
      always_ff @(posedge clk) begin
        if (reset)
          budget_warm <= 0;
        else if (sample_en) begin
          if (budget_warm != 3'd7)
            budget_warm <= budget_warm + 1'b1;
          else if (!seq_terminal)
            $error("psg: CLK_HZ leaves fewer than SEQ_BUDGET clocks after the sample walk");
        end
      end
`endif
    end else if (!REALTIME_PREVIEW && SEQ_BUDGET > 0) begin : g_seq_budget
      localparam int SEQ_CW = $clog2(SEQ_BUDGET + 1);
      logic [SEQ_CW-1:0] seq_credit;

      always_ff @(posedge clk) begin
        if (reset || sample_en)
          seq_credit <= SEQ_CW'(SEQ_BUDGET);
        else if (!walk_busy && seq_credit != 0)
          seq_credit <= seq_credit - 1'b1;
      end
      always_comb seq_starved = (seq_credit == 0);

`ifndef SYNTHESIS
      // The credit is a real bound only when every complete interval can pay
      // it after the sample walk.  Ignore the partial startup intervals.
      logic [2:0] budget_warm;
      always_ff @(posedge clk) begin
        if (reset)
          budget_warm <= 0;
        else if (sample_en) begin
          if (budget_warm != 3'd7)
            budget_warm <= budget_warm + 1'b1;
          else if (seq_credit != 0)
            $error("psg: CLK_HZ leaves fewer than SEQ_BUDGET clocks after the sample walk");
        end
      end
`endif
    end else begin : g_no_seq_budget
      always_comb seq_starved = 1'b0;
    end
  endgenerate

  wire         walk_frozen = walk_busy | seq_starved;

  // ---- CPU edge adapter and audio RAM ----
  // Convert a level-style bus write into one pulse in the PSG clock domain.
  // Reads retain level semantics.
  // A migrated-register access may stall: cpu_stall (from the sequencer's
  // CPU state-memory lane) holds RDY low and defers the commit pulse, so the
  // level-holding CPU is itself the staging register.
  logic cs_wr_q;
  wire  cpu_stall;
  always_ff @(posedge clk) cs_wr_q <= cs && rw && (cs_wr_q || !cpu_stall);
  wire  cs_wr = (cs && rw) && !cs_wr_q && !cpu_stall;
  assign rdy = !cpu_stall;
  wire  aram_cpu_rd = cs && !rw && addr == 8'h02;
  wire [7:0] aram_cpu_q;

  psg_aram u_aram(
    .clk(clk), .reset(reset),
    .cs(cs_wr), .rw(rw), .addr(addr), .di(di),
    .cpu_rd(aram_cpu_rd), .cpu_q(aram_cpu_q),
    .seq_addr(seq_addr), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .seq_hold(prun | state_replay | fold_busy | seq_starved),
    .seq_q(seq_q), .seq_frozen(seq_frozen));

  // ---- State memory and arithmetic services ----
  // The divider belongs to the tick sequencer. Multiplier requests from the
  // sequencer and sample walk are arbitrated after both clients are declared.
  wire  [33:0] m_res;
  wire         m_busy_walk;
  wire         m_busy_seq;

  wire         div_start;
  logic [23:0] div_n;
  logic [7:0]  div_d;
  wire  [23:0] d_res;
  wire  [7:0]  d_rem;
  wire         d_busy;

  // State-memory ports. The walk owns wlk_* while it runs; the tick
  // sequencer owns etk_* in the remaining clocks.
  wire         state_sample_read, state_sample_we;
  wire [PSG_VADR-1:0] wlk_ra, wlk_wa;
  wire [15:0]  wlk_wd;
  wire [PSG_VADR-1:0] etk_ra, etk_wa;
  wire [15:0]  etk_wd;
  wire         etk_we;
  wire [15:0]  state_q;

  psg_divsvc u_div(
    .clk(clk), .reset(reset),
    .div_start(div_start), .div_n(div_n), .div_d(div_d),
    .d_res(d_res), .d_rem(d_rem), .d_busy(d_busy));

  psg_state_mem u_state(
    .clk(clk), .reset(reset),
    .wlk_rd(state_sample_read), .wlk_ra(wlk_ra),
    .wlk_we(state_sample_we), .wlk_wa(wlk_wa), .wlk_wd(wlk_wd),
    .etk_ra(etk_ra), .etk_we(etk_we), .etk_wa(etk_wa), .etk_wd(etk_wd),
    .prun(prun), .state_replay(state_replay),
    .state_q(state_q));

  // ---- Sample-rate walk and waveform pipeline ----
  // Tick-sequencer publication and arithmetic requests consumed by the walk
  // or by the shared top-level services.
  wire [PSG_NV-1:0] play_bits, trig_req, clr_tog;
  wire [5:0]           rb_sfx;
  wire [PSG_NCH*5-1:0] aud_row_bits;
  wire         mus_playing, spar_bank, bank_ready;
  wire [5:0]   mus_pat;
  wire [3:0]   mus_mask;
  wire [7:0]   fade_len;
  wire         smul_start;
  wire signed [24:0] smul_a;
  wire [11:0]  smul_b;
  wire [1:0]   smul_mode;
  wire         smul_short;

  // Walk-owned service requests, waveform context, and completed sample.
  wire         wmul_start;
  wire signed [24:0] wmul_a;
  wire [11:0]  wmul_b;
  wire [1:0]   wmul_mode;
  wire         wmul_short;
  wire         iss_sec, iss_om, iss_os, dq_old_ctx;
  wire [2:0]   s_snd_wave, s_old_wave;
  wire         s_snd_wt, s_ch_buzz;
  wire [1:0]   s_ch_det, old_mode_r;
  wire         old_alt_r;
  wire [15:0]  s_phase, s_old_phase;
  wire [23:0]  s_phase2;
  wire [13:0]  s_eff_inc, s_old_inc;
  wire [16:0]  old_q0;
  wire [15:0]  ctrl_q;
  wire [7:0]   ctrl_addr;
  wire         ctrl_stall;
  wire signed [15:0] dry16;
  wire         dry_valid;

  // Streaming results from the waveform pipeline back into the walk.
  wire signed [17:0] z_eval;
  wire [16:0]  dq17;
  wire [15:0]  q16;

  // The full schedule renders crossfades and reverb. Preview uses the compact
  // schedule and disables unreachable reverb phases at elaboration time.
  psg_walk #(.REVERB(REVERB && !REALTIME_PREVIEW),
             .REALTIME_PREVIEW(REALTIME_PREVIEW),
             .MULTIPUMP(MULTIPUMP)) u_walk(
    .clk(clk), .reset(reset), .sample_en(sample_en),
    .play_bits(play_bits), .mus_playing(mus_playing),
    .spar_bank(spar_bank), .clr_tog(clr_tog),
    .seq_q(seq_q), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .state_q(state_q),
    .state_sample_read(state_sample_read), .wlk_ra(wlk_ra),
    .state_sample_we(state_sample_we), .wlk_wa(wlk_wa), .wlk_wd(wlk_wd),
    .m_res(m_res), .m_busy(m_busy_walk),
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
    .ctrl_q(ctrl_q), .ctrl_addr(ctrl_addr), .ctrl_stall(ctrl_stall),
    .prun(prun), .fold_busy(fold_busy),
    .dry16(dry16), .dry_valid(dry_valid));

  // The waveform pipeline evaluates the walk's live/preceding and
  // primary/secondary contexts. Its registered result returns on the fixed
  // capture phase selected by the walk schedule.
  psg_wave #(.REALTIME_PREVIEW(REALTIME_PREVIEW)) u_wave(
    .clk(clk),
    .iss_sec(iss_sec), .iss_om(iss_om), .iss_os(iss_os),
    .dq_old_ctx(dq_old_ctx),
    .s_snd_wave(s_snd_wave), .s_snd_wt(s_snd_wt), .s_ch_det(s_ch_det),
    .s_ch_buzz(s_ch_buzz), .s_phase_hi(s_phase), .s_phase2(s_phase2),
    .s_eff_inc_hi(s_eff_inc[13:1]),
    .s_old_wave(s_old_wave), .s_old_phase_hi(s_old_phase),
    .s_old_inc_hi(s_old_inc[13:1]), .old_mode_r(old_mode_r),
    .old_alt_r(old_alt_r), .old_q0_lo(old_q0[15:0]),
    .z_eval(z_eval), .dq17(dq17), .q16(q16));

  // ---- Mutually exclusive multiplier arbitration ----
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

  // Multi-pumping is an explicit board/clocking contract, not something inferred
  // from CLK_HZ. Only the iCE40 /6 configuration has the required 112.5 MHz
  // fast clock and six-fast-clocks-per-PSG-clock service bound. PREVIEW,
  // single-clock simulation, and boards whose PSG runs at the PLL rate use the
  // single-clock service. The walker sees true readiness; the sequencer sees a
  // fixed radix-4-equivalent duration so multiplier throughput cannot move
  // audible tick-program timing.
  generate
    if (!MULTIPUMP || REALTIME_PREVIEW) begin : g_mul_single
      wire single_busy;
      psg_mulsvc u_mul(
        .clk(clk), .reset(reset),
        .mul_start(mul_start), .mul_start_a(mul_start_a),
        .mul_start_b(mul_start_b), .mul_start_mode(mul_start_mode),
        .mul_start_short(mul_start_short),
        .m_res(m_res), .m_busy(single_busy));
      assign m_busy_walk = single_busy;
      assign m_busy_seq  = single_busy;
    end else begin : g_mul_multipump
      psg_mulmp #(.RADIX_BITS(1)) u_mul(
        .clk(clk), .fastclk(fastclk), .reset(reset),
        .mul_start(mul_start), .mul_start_a(mul_start_a),
        .mul_start_b(mul_start_b), .mul_start_mode(mul_start_mode),
        .mul_start_short(mul_start_short),
        .m_res(m_res), .m_busy(m_busy_walk), .m_seq_busy(m_busy_seq));
    end
  endgenerate

  // The sequencer consumes its products against the padded busy, which can
  // expire across a freeze in which the walk reuses the multiplier and
  // overwrites the live m_res recurrence. Latch each sequencer-owned product
  // while it sits completed in the service, so a consume that resumes after
  // a walk reads the sequencer's own product, never the walk's last one.
  // The live arm covers the single-clock services, where readiness and the
  // completion edge coincide.
  logic        m_owner_seq;
  logic [33:0] m_res_seq;
  always_ff @(posedge clk) begin
    if (reset)
      m_owner_seq <= 1'b0;
    else if (smul_start)
      m_owner_seq <= 1'b1;
    else if (wmul_start)
      m_owner_seq <= 1'b0;
    if (m_owner_seq && !m_busy_walk)
      m_res_seq <= m_res;
  end
  wire [33:0] m_res_seq_v = (m_owner_seq && !m_busy_walk) ? m_res : m_res_seq;

  // ---- Tick-rate note, effect, and music control ----
  // The sequencer owns CPU-visible playback state and publishes the inactive
  // sounding bank before atomically flipping it for the sample walk.
  psg_seq u_seq(
    .clk(clk), .reset(reset),
    .cs(cs_wr), .rw(rw), .addr(addr), .di(di),
    .play_bits(play_bits), .trig_req(trig_req),
    .rb_sfx(rb_sfx), .aud_row_bits(aud_row_bits),
    // wr_pend deliberately omits rw: the 65C02 gates WE with RDY, so a stall
    // predicate that reads rw is a combinational loop through the CPU. The
    // frozen core holds cs/addr/di stable, which is what the lane decodes.
    .wr_pend(cs && !cs_wr_q), .rd_lvl(cs && !rw),
    .wlk_we_i(state_sample_we), .wlk_rd_i(state_sample_read),
    .cpu_stall(cpu_stall),
    .mus_playing(mus_playing), .mus_pat(mus_pat), .mus_mask(mus_mask),
    .fade_len(fade_len),
    .sample_en(sample_en), .tick_en_d(tick_en_d), .pre_tick(pre_tick),
    .scnt(scnt),
    .walk_frozen(walk_frozen), .spar_bank(spar_bank),
    .clr_tog(clr_tog), .bank_ready(bank_ready),
    .seq_addr(seq_addr), .seq_q(seq_q),
    .state_q(state_q), .state_replay(state_replay),
    .etk_ra(etk_ra), .etk_we(etk_we), .etk_wa(etk_wa), .etk_wd(etk_wd),
    .m_res(m_res_seq_v), .m_busy(m_busy_seq),
    .smul_start(smul_start), .smul_a(smul_a), .smul_b(smul_b),
    .smul_mode(smul_mode), .smul_short(smul_short),
    .div_start(div_start), .div_n(div_n), .div_d(div_d),
    .d_res(d_res), .d_rem(d_rem), .d_busy(d_busy),
    .ctrl_read(prun), .ctrl_addr(ctrl_addr), .ctrl_q(ctrl_q),
    .ctrl_stall(ctrl_stall));

  // ---- PCM commit, CPU readback, and optional debug ----
  // dry_valid commits one completed eight-slot reduction.
  always_ff @(posedge clk) begin
    if (reset) pcm <= 16'sd0;
    else if (dry_valid) pcm <= dry16;
  end

  // CPU readback. Audio-RAM data is synchronous: a read of $02 borrows the
  // shared RAM port, then commits its byte here on the following clock.
  // Channel row/SFX reads report the audible slot: foreground while it plays,
  // otherwise the continuously advancing music slot.
  logic aram_rd_pending;
  always_ff @(posedge clk) begin
    if (reset) begin
      dout <= 0;
      aram_rd_pending <= 1'b0;
    end else if (aram_rd_pending) begin
      dout <= aram_cpu_q;
      aram_rd_pending <= aram_cpu_rd;
    end else if (cs && !rw) begin
      aram_rd_pending <= aram_cpu_rd;
      if (addr != 8'h02) case (addr)

        8'h03: dout <= {mus_playing, 3'b0,
                        play_bits[3:0] | trig_req[3:0]};
        8'h20: dout <= {2'b0, mus_pat};

        8'h21: dout <= {4'b0, mus_mask};
        8'h22: dout <= fade_len;
        default:
          if (addr[7:4] == 4'h1)

            dout <= (addr[3:2] == 2'd1)
                      ? {play_bits[aud_sl(addr[1:0], play_bits)], 1'b0,
                         rb_sfx}
                      : {play_bits[aud_sl(addr[1:0], play_bits)], 2'b0,
                         aud_row_bits[addr[1:0]*5 +: 5]};
          else
            dout <= 8'h00;
      endcase
    end else begin
      aram_rd_pending <= 1'b0;
    end
  end

  // Keep debug generation removable when no hardware consumer exists.
  generate
    if (DBG_PORT == 1) begin : g_dbg
      // Simulator-trace shadow of the state-memory-resident sfx ids, snooped
      // off the sequencer write lane. Debug-build cost only.
      logic [5:0] sfx_shadow[0:PSG_NV-1];
      always_ff @(posedge clk)
        if (etk_we && etk_wa[5:0] == PSG_V_SFX)
          sfx_shadow[etk_wa[PSG_VADR-1:6]] <= etk_wd[5:0];
      always_comb begin
        dbg = 64'b0;
        dbg[7:0]   = {mus_playing, 1'b0, mus_pat};
        dbg[11:8]  = play_bits[3:0];
        dbg[15:12] = play_bits[7:4];
        for (int ch = 0; ch < PSG_NCH; ch++) begin
          dbg[16 + ch*6 +: 6] = sfx_shadow[aud_sl(2'(ch), play_bits)];
          dbg[40 + ch*6 +: 6] = {1'b0, aud_row_bits[ch*5 +: 5]};
        end
      end
    end else if (DBG_PORT == 2) begin : g_pcm_dbg
      // The PCM output register commits dry16 on dry_valid. Delay that condition
      // one clock so a same-domain diagnostic consumer observes the new stable
      // pcm word, not the preceding word from the commit edge.
      logic pcm_commit;
      always_ff @(posedge clk) begin
        if (reset) pcm_commit <= 1'b0;
        else       pcm_commit <= dry_valid;
      end
      always_comb begin
        dbg = 64'b0;
        dbg[0] = pcm_commit;
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
