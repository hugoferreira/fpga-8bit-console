// PSG functional regression with cycle-demand instrumentation.
//
// CLKHZ_P selects the declared PSG clock and PREVIEW_P selects the synthesis
// schedule. In addition to the functional checks from psg_tb, this bench counts
// sample-walk work, sequencer work/freeze time, state-port collisions, sample
// overruns, active-slot time, and completion margins. +audio profiles an
// external image; +pcm with +renderer_samples emits sample-domain PCM text;
// +schedule_trace=<path> emits JSONL records consumable by tools/psg_viz.py.
//
// Build command:
//   command: verilator --binary --timing -j 4 -Irtl rtl/psg_budget_tb.sv rtl/psg.sv \
//     rtl/dsigma.sv --top-module psg_budget_tb -GCLKHZ_P=<hz>

`timescale 1ns/1ps

module psg_budget_tb #(parameter int CLKHZ_P = 32'd28_125_000,
                       parameter int PREVIEW_P = 0,
                       parameter int MULTIPUMP_P = 0);

  localparam CLKHZ = CLKHZ_P;

  // Widen before multiplication so non-default clocks cannot overflow.
  localparam int CLKS_PER_TICK = int'(longint'(CLKHZ) * 183 / 22050);

  bit clk = 0;
  bit fastclk = 0;
  always #30 clk = ~clk;
  always #5 fastclk = ~fastclk;

  bit reset = 1;
  bit cs = 0, rw = 0;
  logic [7:0] addr = 0, di = 0;
  logic [7:0] dout;
  logic signed [15:0] pcm;

  psg #(.CLK_HZ(CLKHZ), .REALTIME_PREVIEW(PREVIEW_P),
        .MULTIPUMP(MULTIPUMP_P)) dut(
    .clk(clk), .fastclk(fastclk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di),
    .dout(dout), .pcm(pcm),
    .dbg());

  logic signed [15:0] ds_pcm = 0;
  logic       ds_out;
  dsigma dsig(.clk(clk), .reset(reset), .pcm(ds_pcm), .out(ds_out));

  int errors = 0;
  int sample_job_clocks = 0;
  int max_sample_job_clocks = 0;
  bit sample_job_active = 0;
  int tick_job_clocks = 0;
  int max_tick_job_clocks = 0;
  bit tick_job_active = 0;

  int tick_window_clocks = 0;
  int tick_window = 0;
  bit tick_window_active = 0;
  bit tick_busy_at_pretick = 0;
  int late_flips = 0;

  // Demand counters are clock-rate independent; deadline margins compare them
  // with the selected clock's cycles per sample and pre_tick window.
  longint fsm_own = 0, walk_own = 0, frozen_seq = 0, total_clk = 0, samples = 0;
  longint st_clk[0:63];
  int tick_own = 0, max_tick_own = 0;
  int walk_run = 0, max_walk_run = 0;

  // Collision/overrun counters catch dropped work that a simple busy-time sum
  // would miss.
  longint state_wr_lost = 0;

  longint samp_over_prun = 0, samp_over_fold = 0;

  longint slot_play[0:7];

  bit recovery_probe = 0;
  int recovery_preboundary = 0;
  int recovery_coalesced = 0;
  int recovery_delayed = 0;
  int recovery_dropped_samples = 0;

  string pcm_trace_path = "";
  string schedule_trace_path = "";
  string walk_trace_path = "";
  string binding_trace_path = "";
  string value_trace_path = "";
  integer schedule_trace_fd = 0;
  integer walk_trace_fd = 0;
  integer binding_trace_fd = 0;
  integer value_trace_fd = 0;
  integer binding_trace_rows = 0;
  integer value_trace_rows = 0;
  integer value_trace_edge = 0;
  bit binding_trace_active = 0;
  int schedule_trace_limit = 250000;
  int schedule_trace_records = 0;
  bit schedule_trace_was_active = 0;
  bit schedule_trace_truncated = 0;

  initial begin
    if ($value$plusargs("schedule_trace=%s", schedule_trace_path)) begin
      void'($value$plusargs("schedule_trace_limit=%d", schedule_trace_limit));
      schedule_trace_fd = $fopen(schedule_trace_path, "w");
      if (schedule_trace_fd == 0) begin
        $display("FAIL: cannot open schedule trace %s", schedule_trace_path);
        errors++;
      end
    end
    if ($value$plusargs("walk_trace=%s", walk_trace_path)) begin
      walk_trace_fd = $fopen(walk_trace_path, "w");
      if (walk_trace_fd == 0) begin
        $display("FAIL: cannot open walk trace %s", walk_trace_path);
        errors++;
      end else
        $fdisplay(walk_trace_fd,
                  "sample,slot,event,row,eff_a,g_live,last_g,old_g,blend_restart,bl_cnt,phase,old_phase,last_inc,old_inc,snd_wave,last_wave,old_wave,nz_tick,old_nz_on,old_nz_r_on,mx_new,mx_old,blend_y,mix_leaf,preview_restart,preview_alpha,preview_old_leaf,preview_blend_leaf,fold_leaf,playing,pcm");
    end
    if ($value$plusargs("binding_trace=%s", binding_trace_path)) begin
      binding_trace_fd = $fopen(binding_trace_path, "w");
      if (binding_trace_fd == 0) begin
        $display("FAIL: cannot open binding trace %s", binding_trace_path);
        errors++;
      end
    end
    if ($value$plusargs("value_trace=%s", value_trace_path)) begin
      value_trace_fd = $fopen(value_trace_path, "w");
      if (value_trace_fd == 0) begin
        $display("FAIL: cannot open value trace %s", value_trace_path);
        errors++;
      end
    end
  end

  final begin
    if (schedule_trace_fd != 0)
      $fclose(schedule_trace_fd);
    if (walk_trace_fd != 0)
      $fclose(walk_trace_fd);
    if (binding_trace_fd != 0)
      $fclose(binding_trace_fd);
    if (value_trace_fd != 0)
      $fclose(value_trace_fd);
  end

  // C2-C-C proof-only trace coordinates are captured before the DUT edge.
  // The post row uses the same coordinates after all nonblocking assignments
  // settle, so a checker can prove value movement without reconstructing any
  // waveform, multiplier, record or fold equation.
  integer value_sample;
  logic [2:0] value_slot;
  logic value_bank;
  logic [6:0] value_pph;
  logic [15:0] value_cap;
  logic value_hold;
  logic value_state_read;
  logic [8:0] value_state_ra;
  logic value_state_write;
  logic [8:0] value_state_wa;
  logic [15:0] value_state_wd;
  logic [12:0] value_syn_addr;
  logic value_wave_primary, value_wave_secondary;
  logic value_wave_old_primary, value_wave_old_secondary;
  logic value_aram_issue;
  logic value_dq_start, value_dq_start_old, value_dq_start_ready;
  logic value_dq_done;
  logic value_dq_old_take;
  logic value_mul_start;
  logic [1:0] value_mul_mode;
  logic value_mul_short;
  logic value_nz_req_old, value_nz_req_live;
  logic value_ring_read, value_ring_take_current, value_ring_take_old;
  logic [12:0] value_ring_addr;
  logic [9:0] value_ring_rp;
  logic [1:0] value_ring_current_level, value_ring_old_level;
  logic [12:0] value_ring_current_addr, value_ring_old_addr;
  logic signed [15:0] value_ring_rd;
  logic value_ring_write, value_leaf_commit, value_lfsr_commit;
  logic [3:0] value_fold_step;
  logic value_fold_write;
  logic [1:0] value_fold_write_dst;
  logic value_dry_valid;
  logic value_guard_wavetable, value_guard_reverb;
  logic value_guard_audible, value_guard_blend;
  logic value_guard_restart, value_guard_clear = 1'b0;
  logic value_guard_play, value_guard_amplitude;
  logic value_guard_noise, value_guard_brown, value_guard_hidden;

  generate
    if (!PREVIEW_P) begin : g_value_ring_rd
      always_comb value_ring_rd = dut.u_walk.g_ring.ring_rd;
    end else begin : g_value_no_ring_rd
      always_comb value_ring_rd = 16'sd0;
    end
  endgenerate

  function automatic bit select_value_edge();
    select_value_edge = value_trace_fd != 0 && binding_trace_active
      && !PREVIEW_P
      && (dut.u_walk.prun || dut.u_walk.fold_busy || dut.dry_valid)
      && (dut.ctrl_stall || dut.state_sample_read || dut.state_sample_we
          || dut.syn_rd || dut.wmul_start || dut.u_walk.dq_start
          || dut.m_busy_walk
          || dut.u_walk.dq_done || dut.u_walk.cap != 16'd0
          || dut.u_walk.fmc != 4'd0 || dut.dry_valid
          || (dut.u_walk.prun && !dut.ctrl_stall
              && (dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 6)
                  || dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 7)
                  || dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 8)
                  || dut.u_walk.pph == 7'(dut.u_walk.PLAST - 1)
                  || dut.u_walk.pph == 7'(dut.u_walk.PLAST))));
  endfunction

  function automatic logic signed [17:0] value_fold_leaf_sink();
    case (value_slot)
      3'd0:         value_fold_leaf_sink = dut.u_walk.fstk[0];
      3'd2, 3'd4:   value_fold_leaf_sink = dut.u_walk.fstk[1];
      3'd6:         value_fold_leaf_sink = dut.u_walk.fstk[2];
      default:      value_fold_leaf_sink = dut.u_walk.fdb;
    endcase
  endfunction

  function automatic logic [12:0] value_ring_address(
    input logic [1:0] ring_level
  );
    logic [9:0] ring_tap;
    ring_tap = (ring_level == 2'd1)
      ? ((dut.u_walk.ring_rp >= 10'd366)
          ? dut.u_walk.ring_rp - 10'd366
          : dut.u_walk.ring_rp + 10'd366)
      : dut.u_walk.ring_rp;
    value_ring_address = {10'd0, dut.u_walk.pc_ch} * 13'd732
      + {3'b0, ring_tap};
  endfunction

  task automatic emit_value_trace(input string phase_name);
    $fdisplay(value_trace_fd,
      "{\"schema\":\"psg_legacy_value_v1\",\"phase\":\"%s\",\"edge\":%0d,\"sample\":%0d,\"multipump\":%0d,\"bank\":%0b,\"slot\":%0d,\"pph\":%0d,\"cap\":\"%04x\",\"hold\":%0b,\"state_read\":%0b,\"state_ra\":%0d,\"state_q\":\"%04x\",\"state_mem_r\":\"%04x\",\"state_write\":%0b,\"state_wa\":%0d,\"state_wd\":\"%04x\",\"state_mem_w\":\"%04x\",\"wave_primary\":%0b,\"wave_secondary\":%0b,\"wave_old_primary\":%0b,\"wave_old_secondary\":%0b,\"aram_issue\":%0b,\"dq_start\":%0b,\"dq_start_old\":%0b,\"dq_done\":%0b,\"dq_old_take\":%0b,\"mul_start\":%0b,\"mul_mode\":%0d,\"mul_short\":%0b,\"ring_read\":%0b,\"ring_take_current\":%0b,\"ring_take_old\":%0b,\"ring_write\":%0b,\"leaf_commit\":%0b,\"lfsr_commit\":%0b,\"fold_step\":%0d,\"dry_valid\":%0b,\"guard_wavetable\":%0b,\"guard_reverb\":%0b,\"guard_audible\":%0b,\"guard_blend\":%0b,\"guard_restart\":%0b,\"guard_clear\":%0b,\"guard_play\":%0b,\"guard_amplitude\":%0b,\"guard_noise\":%0b,\"guard_brown\":%0b,\"guard_hidden\":%0b,\"seq_q\":\"%02x\",\"z_eval\":%0d,\"dq_result\":%0d,\"dq_live_r\":%0d,\"dq_visit\":%0d,\"m_res\":\"%09x\",\"mul_limb17\":%0d,\"wt_mag19\":%0d,\"nz_step\":%0d,\"nz_old_step\":%0d,\"smp_a\":%0d,\"smp_b\":%0d,\"smp_a_byte\":\"%02x\",\"smp_b_byte\":\"%02x\",\"wt_p1\":%0d,\"wt_q1\":%0d,\"wt_p1_byte\":\"%02x\",\"wt_q1_byte\":\"%02x\",\"wt_prod\":%0d,\"wt_z\":%0d,\"gz_s1_r\":%0d,\"mx_new\":%0d,\"mx_old\":%0d,\"arm_new_w51\":%0d,\"arm_old_w51\":%0d,\"bl_res\":%0d,\"ring_rd\":%0d,\"ring_q\":%0d,\"ring_q_old\":%0d,\"bl_cnt\":%0d,\"s_phase\":%0d,\"s_phase_low16\":\"%04x\",\"s_phase2\":%0d,\"s_old_phase\":%0d,\"old_q0\":%0d,\"s_noise_lp\":%0d,\"s_noise_lp_word\":\"%04x\",\"filt_y\":%0d,\"mx_filt\":%0d,\"mix_leaf\":%0d,\"leaf_lo\":\"%04x\",\"leaf_hi\":\"%04x\",\"fold_leaf_sink\":%0d,\"lfsr\":%0d,\"lfsr2\":%0d,\"phase_alu_y\":%0d,\"fstk0\":%0d,\"fstk0_low16\":%0d,\"fstk1\":%0d,\"fstk2\":%0d,\"fsel\":%0d,\"fpend\":%0d,\"ffin\":%0b,\"fmc\":%0d,\"dry16\":%0d,\"mul_busy\":%0b,\"nz2_sign\":%0b,\"nz_neg17\":%0d,\"nz_pos17\":%0d,\"fold_fdb\":%0d,\"fdsti\":%0d,\"fold_fda\":%0d,\"fold_a\":%0d,\"fold_b\":%0d,\"fold_sub\":%0b,\"fold_cin\":%0b,\"f_under\":%0b,\"fdiv5_q\":%0d,\"mxs_new\":%0b,\"mxs_old\":%0b,\"pcm\":%0d,\"syn_addr\":%0d,\"dq_start_ready\":%0b,\"dq_busy\":%0b,\"nz_req_old\":%0b,\"nz_req_live\":%0b,\"blend_mag23\":%0d,\"ring_addr\":%0d,\"ring_rp\":%0d,\"ring_current_level\":%0d,\"ring_old_level\":%0d,\"ring_current_addr\":%0d,\"ring_old_addr\":%0d,\"fold_write\":%0b,\"fold_write_dst\":%0d}",
      phase_name, value_trace_edge, value_sample, MULTIPUMP_P,
      value_bank, value_slot, value_pph, value_cap, value_hold,
      value_state_read, value_state_ra, dut.state_q,
      dut.u_state.state_m[value_state_ra],
      value_state_write, value_state_wa, value_state_wd,
      dut.u_state.state_m[value_state_wa], value_wave_primary,
      value_wave_secondary, value_wave_old_primary,
      value_wave_old_secondary, value_aram_issue, value_dq_start,
      value_dq_start_old, value_dq_done, value_dq_old_take,
      value_mul_start, value_mul_mode, value_mul_short, value_ring_read,
      value_ring_take_current, value_ring_take_old, value_ring_write,
      value_leaf_commit, value_lfsr_commit, value_fold_step,
      value_dry_valid, value_guard_wavetable, value_guard_reverb,
      value_guard_audible, value_guard_blend, value_guard_restart,
      value_guard_clear, value_guard_play, value_guard_amplitude,
      value_guard_noise, value_guard_brown, value_guard_hidden, dut.seq_q,
      $signed(dut.z_eval), dut.u_walk.dq_result, dut.u_walk.dq_live_r,
      dut.u_walk.dq_visit, dut.m_res, dut.m_res[26:10], dut.m_res[20:2],
      $signed(dut.u_walk.nz_step),
      $signed(17'(dut.u_walk.nz2_rand[8]
        ? dut.u_walk.nz_neg : dut.u_walk.nz_pos)),
      $signed(dut.u_walk.smp_a), $signed(dut.u_walk.smp_b),
      dut.u_walk.smp_a[7:0], dut.u_walk.smp_b[7:0],
      $signed(dut.u_walk.wt_p1), $signed(dut.u_walk.wt_q1),
      dut.u_walk.wt_p1, dut.u_walk.wt_q1,
      $signed(dut.u_walk.wt_op)
        + $signed({19'b0, dut.u_walk.mxs_new}),
      $signed(dut.u_walk.wt_z), dut.u_walk.gz_filt_r,
      $signed(dut.u_walk.mx_new),
      $signed(dut.u_walk.mx_old), $signed(dut.u_walk.mx_new_w51),
      $signed(dut.u_walk.mx_old_w51), dut.u_walk.bl_res,
      value_ring_rd, $signed(dut.u_walk.ring_q),
      $signed(dut.u_walk.ring_q_old), dut.u_walk.bl_cnt,
      dut.u_walk.s_phase, dut.u_walk.s_phase[15:0], dut.u_walk.s_phase2,
      dut.u_walk.s_old_phase,
      dut.u_walk.old_q0, $signed(dut.u_walk.s_noise_lp),
      dut.u_walk.s_noise_lp,
      $signed(dut.u_walk.filt_y), $signed(dut.u_walk.gz_filt_r),
      $signed(dut.u_walk.mix_leaf), dut.u_walk.mix_leaf[15:0],
      {{14{dut.u_walk.mix_leaf[17]}}, dut.u_walk.mix_leaf[17:16]},
      $signed(value_fold_leaf_sink()),
      dut.u_walk.lfsr, dut.u_walk.lfsr2,
      $signed(dut.u_walk.phase_alu_y), $signed(dut.u_walk.fstk[0]),
      $signed(dut.u_walk.fstk[0][15:0]),
      $signed(dut.u_walk.fstk[1]), $signed(dut.u_walk.fstk[2]),
      dut.u_walk.fsel, dut.u_walk.fpend, dut.u_walk.ffin,
      dut.u_walk.fmc, $signed(dut.u_walk.dry16), dut.m_busy_walk,
      dut.u_walk.nz2_rand[8], $signed(dut.u_walk.nz_neg[16:0]),
      $signed(dut.u_walk.nz_pos[16:0]), $signed(dut.u_walk.fdb),
      dut.u_walk.fdsti, $signed(dut.u_walk.fda),
      $signed(dut.u_walk.fold_a), $signed(dut.u_walk.fold_b),
      dut.u_walk.fold_sub, dut.u_walk.fold_cin, dut.u_walk.f_under,
      dut.u_walk.fdiv5_q, dut.u_walk.mxs_new, dut.u_walk.mxs_old,
      $signed(pcm), value_syn_addr, value_dq_start_ready,
      dut.u_walk.dq_busy, value_nz_req_old, value_nz_req_live,
      dut.u_walk.bl_res, value_ring_addr, value_ring_rp,
      value_ring_current_level, value_ring_old_level,
      value_ring_current_addr, value_ring_old_addr, value_fold_write,
      value_fold_write_dst);
  endtask

  always @(posedge clk) if (!reset && select_value_edge()) begin
    value_sample = samples;
    value_bank = dut.spar_bank;
    value_slot = dut.u_walk.pc_ch;
    value_pph = dut.u_walk.pph;
    value_cap = dut.u_walk.cap;
    value_hold = dut.ctrl_stall;
    value_state_read = dut.state_sample_read;
    value_state_ra = dut.wlk_ra;
    value_state_write = dut.state_sample_we;
    value_state_wa = dut.wlk_wa;
    value_state_wd = dut.wlk_wd;
    value_syn_addr = dut.syn_addr;
    value_wave_primary = dut.u_walk.cap[dut.u_walk.CAP_W0];
    value_wave_secondary = dut.iss_sec;
    value_wave_old_primary = dut.iss_om;
    value_wave_old_secondary = dut.iss_os;
    value_aram_issue = dut.syn_rd;
    value_dq_start = dut.u_walk.dq_start;
    value_dq_start_old = dut.u_walk.dq_start_old;
    value_dq_start_ready = dut.u_walk.dq_start_ready;
    value_dq_done = dut.u_walk.dq_done;
    value_dq_old_take = dut.dq_old_ctx;
    value_mul_start = dut.wmul_start;
    value_mul_mode = dut.wmul_mode;
    value_mul_short = dut.wmul_short;
    value_nz_req_old = dut.u_walk.nz_req_old;
    value_nz_req_live = dut.u_walk.nz_req_live;
    value_ring_read = dut.u_walk.prun && !dut.ctrl_stall
      && (dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 6)
          || dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 7));
    value_ring_take_current = dut.u_walk.prun && !dut.ctrl_stall
      && dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 7);
    value_ring_take_old = dut.u_walk.prun && !dut.ctrl_stall
      && dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 8);
    value_ring_rp = dut.u_walk.ring_rp;
    value_ring_current_level = dut.u_walk.s_ch_rev;
    value_ring_old_level = dut.u_walk.old_rev_r;
    value_ring_current_addr = value_ring_address(value_ring_current_level);
    value_ring_old_addr = value_ring_address(value_ring_old_level);
    value_ring_addr = (dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 6))
      ? value_ring_current_addr : value_ring_old_addr;
    value_ring_write = dut.u_walk.prun && !dut.ctrl_stall
      && dut.u_walk.pph == 7'(dut.u_walk.PLAST - 1)
      && dut.u_walk.play_bits[dut.u_walk.pc_ch];
    value_leaf_commit = dut.u_walk.prun && !dut.ctrl_stall
      && dut.u_walk.pph == 7'(dut.u_walk.PLAST);
    value_lfsr_commit = dut.u_walk.prun && !dut.ctrl_stall
      && dut.u_walk.cap[dut.u_walk.CAP_W0];
    value_fold_step = dut.u_walk.fmc;
    value_fold_write = dut.u_walk.fmc == 4'd1
      || ((dut.u_walk.fmc == 4'd2 || dut.u_walk.fmc == 4'd3)
          && !dut.u_walk.phase_alu_y[17])
      || (dut.u_walk.fmc >= 4'd4 && dut.u_walk.fmc <= 4'd8);
    value_fold_write_dst = dut.u_walk.fdsti;
    value_dry_valid = dut.dry_valid;
    value_guard_wavetable = dut.u_walk.s_snd_wt;
    value_guard_reverb = dut.u_walk.s_ch_rev != 2'd0
      || dut.u_walk.old_rev_r != 2'd0;
    value_guard_audible = dut.u_walk.mx_aud;
    value_guard_blend = dut.u_walk.bl_cnt != 7'd64;
    value_guard_restart = dut.u_walk.blend_restart;
    // Clear is consumed and acknowledged at W0.  Retain that exact live
    // pre-edge predicate through the rest of the visit so later persistent
    // writes carry their real clear/no-clear provenance instead of seeing
    // only the already-acknowledged zero class.
    if (dut.u_walk.cap[dut.u_walk.CAP_W0])
      value_guard_clear = dut.u_walk.s_clr_tog != dut.u_walk.s_clr_ack;
    value_guard_play = dut.u_walk.play_bits[dut.u_walk.pc_ch];
    value_guard_amplitude = dut.u_walk.s_eff_a != 0;
    value_guard_noise = !dut.u_walk.s_snd_wt
      && dut.u_walk.s_snd_wave == 3'd6
      && !(dut.u_walk.s_ch_buzz && !dut.u_walk.s_ch_noiz);
    value_guard_brown = !dut.u_walk.s_snd_wt
      && dut.u_walk.s_snd_wave == 3'd6
      && dut.u_walk.s_ch_buzz && !dut.u_walk.s_ch_noiz;
    value_guard_hidden = dut.u_walk.play_bits[dut.u_walk.pc_ch]
      && !dut.u_walk.mx_aud;
    emit_value_trace("pre");
    value_trace_rows++;
    #1;
    emit_value_trace("post");
    value_trace_rows++;
    value_trace_edge++;
  end

  // Sample on the falling edge after DUT nonblocking assignments settle.
  always @(negedge clk) begin
    if (!reset) begin
      total_clk++;
      if (schedule_trace_fd != 0 && (dut.prun || schedule_trace_was_active)
          && (schedule_trace_limit == 0
              || schedule_trace_records < schedule_trace_limit)) begin
        $fdisplay(schedule_trace_fd,
                  "{\"cycle\":%0d,\"pph\":%0d,\"prun\":%0d,\"schedule\":\"%s\",\"sst\":%0d}",
                  total_clk, dut.u_walk.pph, dut.prun,
                  PREVIEW_P ? "preview" : "hw", dut.u_seq.sst);
        schedule_trace_records++;
      end else if (schedule_trace_fd != 0 && !schedule_trace_truncated
                   && schedule_trace_limit != 0
                   && schedule_trace_records >= schedule_trace_limit) begin
        schedule_trace_truncated = 1;
        $display("schedule trace stopped at %0d records; override with +schedule_trace_limit=<n> (0 is unlimited)",
                 schedule_trace_limit);
      end
      schedule_trace_was_active = dut.prun;
      if (walk_trace_fd != 0 && dut.u_walk.prun
          && ((!PREVIEW_P && dut.u_walk.cap[dut.u_walk.CAP_W0])
              || (!PREVIEW_P && dut.u_walk.cap[dut.u_walk.CAP_W1])
              || (PREVIEW_P && dut.u_walk.pph == dut.u_walk.PWORK)
              || dut.u_walk.pph == dut.u_walk.PLAST)) begin
        $fdisplay(walk_trace_fd,
                  "%0d,%0d,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                  samples, dut.u_walk.pc_ch,
                  (dut.u_walk.pph == dut.u_walk.PLAST) ? "fold" :
                  ((!PREVIEW_P && dut.u_walk.cap[dut.u_walk.CAP_W1])
                    ? "post_start" : "start"),
                  row_of(dut.u_walk.pc_ch), dut.u_walk.s_eff_a,
                  dut.u_walk.g_live,
                  dut.u_walk.s_last_G, dut.u_walk.s_old_G,
                  dut.u_walk.blend_restart, dut.u_walk.bl_cnt,
                  dut.u_walk.s_phase, dut.u_walk.s_old_phase,
                  dut.u_walk.s_last_inc, dut.u_walk.s_old_inc,
                  dut.u_walk.s_snd_wave, dut.u_walk.s_last_wave,
                  dut.u_walk.s_old_wave, dut.u_walk.nz_tick_r,
                  dut.u_walk.old_nz_on, dut.u_walk.old_nz_r_on,
                  $signed(dut.u_walk.mx_new), $signed(dut.u_walk.mx_old),
                  $signed(dut.u_walk.blend_y), $signed(dut.u_walk.mix_leaf),
                  dut.u_walk.preview_restart, dut.u_walk.preview_alpha,
                  $signed(dut.u_walk.preview_old_leaf),
                  $signed(dut.u_walk.preview_blend_leaf),
                  $signed(dut.u_walk.fold_leaf),
                  dut.u_walk.play_bits[dut.u_walk.pc_ch],
                  $signed(pcm));
      end
      if (binding_trace_fd != 0 && binding_trace_active && !PREVIEW_P
          && (dut.u_walk.prun || dut.u_walk.fold_busy || dut.dry_valid)
          && (dut.state_sample_read || dut.state_sample_we || dut.syn_rd
              || dut.wmul_start || dut.u_walk.dq_start
              || dut.u_walk.dq_done || dut.u_walk.cap != 16'd0
              || dut.u_walk.fmc != 4'd0 || dut.dry_valid
              || (dut.u_walk.prun && !dut.ctrl_stall
                  && (dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 6)
                      || dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 7)
                      || dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 8)
                      || dut.u_walk.pph == 7'(dut.u_walk.PLAST - 1))))) begin
        $fdisplay(binding_trace_fd,
          "{\"schema\":\"psg_legacy_binding_v1\",\"cycle\":%0d,\"sample\":%0d,\"multipump\":%0d,\"slot\":%0d,\"pph\":%0d,\"prun\":%0b,\"hold\":%0b,\"cap\":\"%04x\",\"state_read\":%0b,\"state_ra\":%0d,\"state_write\":%0b,\"state_wa\":%0d,\"wave_primary\":%0b,\"wave_secondary\":%0b,\"wave_old_primary\":%0b,\"wave_old_secondary\":%0b,\"aram_issue\":%0b,\"dq_start\":%0b,\"dq_start_old\":%0b,\"dq_done\":%0b,\"dq_old_take\":%0b,\"mul_start\":%0b,\"mul_mode\":%0d,\"mul_short\":%0b,\"ring_read\":%0b,\"ring_take_current\":%0b,\"ring_take_old\":%0b,\"ring_write\":%0b,\"leaf_commit\":%0b,\"lfsr_commit\":%0b,\"fold_step\":%0d,\"dry_valid\":%0b,\"guard_wavetable\":%0b,\"guard_reverb\":%0b,\"guard_audible\":%0b,\"guard_blend\":%0b,\"guard_play\":%0b}",
          total_clk, samples, MULTIPUMP_P, dut.u_walk.pc_ch,
          dut.u_walk.pph, dut.u_walk.prun,
          dut.ctrl_stall, dut.u_walk.cap, dut.state_sample_read, dut.wlk_ra,
          dut.state_sample_we, dut.wlk_wa,
          dut.u_walk.cap[dut.u_walk.CAP_W0], dut.iss_sec, dut.iss_om,
          dut.iss_os, dut.syn_rd, dut.u_walk.dq_start,
          dut.u_walk.dq_start_old, dut.u_walk.dq_done, dut.dq_old_ctx,
          dut.wmul_start, dut.wmul_mode, dut.wmul_short,
          dut.u_walk.prun && !dut.ctrl_stall
            && (dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 6)
                || dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 7)),
          dut.u_walk.prun && !dut.ctrl_stall
            && dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 7),
          dut.u_walk.prun && !dut.ctrl_stall
            && dut.u_walk.pph == 7'(dut.u_walk.PSTOR + 8),
          dut.u_walk.prun && !dut.ctrl_stall
            && dut.u_walk.pph == 7'(dut.u_walk.PLAST - 1)
            && dut.u_walk.play_bits[dut.u_walk.pc_ch],
          dut.u_walk.prun && !dut.ctrl_stall
            && dut.u_walk.pph == 7'(dut.u_walk.PLAST),
          dut.u_walk.prun && !dut.ctrl_stall
            && dut.u_walk.cap[dut.u_walk.CAP_W0],
          dut.u_walk.fmc, dut.dry_valid, dut.u_walk.s_snd_wt,
          (dut.u_walk.s_ch_rev != 2'd0 || dut.u_walk.old_rev_r != 2'd0),
          dut.u_walk.mx_aud, dut.u_walk.bl_cnt != 7'd64,
          dut.u_walk.play_bits[dut.u_walk.pc_ch]);
        binding_trace_rows++;
      end
      if (dut.sample_en) samples++;
      st_clk[dut.u_seq.sst]++;
      if (dut.u_state.wlk_we && dut.u_state.etk_we) state_wr_lost++;
      if (dut.sample_en && dut.prun)      samp_over_prun++;
      if (dut.sample_en && dut.fold_busy) samp_over_fold++;
      if (recovery_probe) begin
        if (dut.pre_tick && dut.u_seq.tickpend)
          recovery_coalesced++;
        if (dut.tick_en_d && dut.u_seq.flip_pend)
          recovery_delayed++;
        if (dut.sample_en && (dut.prun || dut.fold_busy))
          recovery_dropped_samples++;
      end
      if (dut.sample_en)
        for (int sl = 0; sl < 8; sl++)
          if (dut.u_seq.play_bits[sl]) slot_play[sl]++;
      if (dut.prun) begin walk_own++; walk_run++; end
      else begin
        if (walk_run > max_walk_run) max_walk_run = walk_run;
        walk_run = 0;
      end
      if (dut.u_seq.sst != 0) begin
        if (dut.u_seq.walk_frozen) frozen_seq++;
        else begin fsm_own++; tick_own++; end
      end else begin
        if (tick_own > max_tick_own) max_tick_own = tick_own;
        tick_own = 0;
      end
    end
    if (reset) begin
      sample_job_clocks = 0;
      max_sample_job_clocks = 0;
      sample_job_active = 0;
      tick_job_clocks = 0;
      max_tick_job_clocks = 0;
      tick_job_active = 0;
      tick_busy_at_pretick = 0;
      late_flips = 0;
    end else if (dut.sample_en) begin
      if (sample_job_active) begin
        $display("  FAIL: synthesis job exceeded the sample deadline");
        errors++;
      end
      sample_job_clocks = 0;
      sample_job_active = 1;
    end else if (sample_job_active) begin
      sample_job_clocks++;
      if (!dut.prun && dut.u_walk.fmc == 0 && dut.dry_valid) begin
        if (sample_job_clocks > max_sample_job_clocks)
          max_sample_job_clocks = sample_job_clocks;
        sample_job_active = 0;
      end
    end

    if (!reset) begin

      if (dut.pre_tick) begin
        tick_job_clocks = 0;
        tick_window_clocks = 0;
        tick_job_active = 1;
        tick_window_active = 1;

        tick_busy_at_pretick = (dut.u_seq.sst != 0);
      end
      if (tick_window_active && !dut.pre_tick) begin
        tick_window_clocks++;
        if (dut.tick_en) begin
          if (tick_window_clocks > tick_window)
            tick_window = tick_window_clocks;
          tick_window_active = 0;
        end
      end
      if (tick_job_active && !dut.pre_tick) begin
        tick_job_clocks++;
        if (dut.bank_ready) begin
          if (tick_job_clocks > max_tick_job_clocks)
            max_tick_job_clocks = tick_job_clocks;
          tick_job_active = 0;
        end else if (dut.tick_en) begin
          if (tick_busy_at_pretick)
            late_flips++;
          else if (recovery_probe)
            recovery_preboundary++;
          else begin
            $display("  FAIL: tick pre-run missed its boundary from an idle walk");
            errors++;
          end
          tick_job_active = 0;
        end
      end
    end
  end

  // Bus and native audio-image construction helpers.
  task wr(input [7:0] a, input [7:0] d);
    @(negedge clk);
    cs = 1; rw = 1; addr = a; di = d;
    @(negedge clk);
    cs = 0; rw = 0;
  endtask

  task rd(input [7:0] a, output [7:0] d);
    @(negedge clk);
    cs = 1; rw = 0; addr = a;
    @(negedge clk);
    cs = 0;
    d = dout;
  endtask

  task ticks(input int n);
    repeat (n * CLKS_PER_TICK) @(posedge clk);
  endtask

  logic [7:0] img[0:4607];

  task set_note(input int sfx, input int r, input int pitch,
                input int wave, input int vol, input int fx);
    int base;
    base = 256 + sfx * 68 + r * 2;
    img[base]     = 8'(((pitch & 63)) | ((wave & 3) << 6));
    img[base + 1] = 8'(((wave >> 2) & 1) | ((vol & 7) << 1) | ((fx & 7) << 4));
  endtask

  task set_meta(input int sfx, input int speed, input int ls, input int le);
    img[256 + sfx * 68 + 65] = speed[7:0];
    img[256 + sfx * 68 + 66] = ls[7:0];
    img[256 + sfx * 68 + 67] = le[7:0];
  endtask

  task set_filter(input int sfx, input int fb);
    img[256 + sfx * 68 + 64] = fb[7:0];
  endtask

  task set_inote(input int sfx, input int r, input int pitch, input int inst,
                 input int vol, input int fx);
    set_note(sfx, r, pitch, inst, vol, fx);
    img[256 + sfx * 68 + r * 2 + 1] = img[256 + sfx * 68 + r * 2 + 1] | 8'h80;
  endtask

  task set_wavetable(input int sfx, input int amp, input bit bass);
    for (int i = 0; i < 64; i++)
      img[256 + sfx * 68 + i] = (i < 32) ? 8'(amp) : 8'(-amp);
    img[256 + sfx * 68 + 64] = 8'd0;
    img[256 + sfx * 68 + 65] = bass ? 8'd1 : 8'd0;
    img[256 + sfx * 68 + 66] = 8'h80;
    img[256 + sfx * 68 + 67] = 8'd0;
  endtask

  task upload;
    wr(8'h00, 8'h00);
    wr(8'h01, 8'h31);
    for (int i = 0; i < 4608; i++) wr(8'h02, img[i]);
  endtask

  task measure(input int nclk, output int maxd, output int changes);
    int prev, cur, d;
    maxd = 0; changes = 0;
    prev = int'(pcm);
    repeat (nclk) begin
      @(posedge clk);
      cur = int'(pcm);
      d = cur - prev; if (d < 0) d = -d;
      if (d > maxd) maxd = d;
      if (cur != prev) changes++;
      prev = cur;
    end
  endtask

  task peak_dev(input int nclk, output int pk);
    int d;
    pk = 0;
    repeat (nclk) begin
      @(posedge clk);
      d = int'(pcm); if (d < 0) d = -d;
      if (d > pk) pk = d;
    end
  endtask

  task set_pat(input int p, input [7:0] b0, input [7:0] b1,
               input [7:0] b2, input [7:0] b3);
    img[p * 4 + 0] = b0;
    img[p * 4 + 1] = b1;
    img[p * 4 + 2] = b2;
    img[p * 4 + 3] = b3;
  endtask

  // Hierarchical probes decode the shared state-memory layout.
  localparam int VSTR = 64;

  function automatic logic [4:0] row_of(input int v);
    row_of = dut.u_state.state_m[v * VSTR + 32][4:0];
  endfunction
  function automatic logic [4:0] ins_row_of(input int v);
    ins_row_of = dut.u_state.state_m[v * VSTR + 5][9:5];
  endfunction

  function automatic logic [23:0] eff_inc_of(input int v);
    int b;
    begin
      b = v * VSTR + (dut.spar_bank ? 28 : 24);
      eff_inc_of = {dut.u_state.state_m[b+1][7:0], dut.u_state.state_m[b+0]};
    end
  endfunction
  function automatic logic [23:0] phase2_of(input int v);
    phase2_of = {dut.u_state.state_m[v*VSTR+13][7:0], dut.u_state.state_m[v*VSTR+12]};
  endfunction
  function automatic logic snd_wt_of(input int v);
    int b;
    begin
      b = v * VSTR + (dut.spar_bank ? 28 : 24);
      snd_wt_of = dut.u_state.state_m[b+1][11];
    end
  endfunction
  function automatic logic [11:0] eff_vol_of(input int v);
    int b;
    begin
      b = v * VSTR + (dut.spar_bank ? 28 : 24);
      eff_vol_of = dut.u_state.state_m[b+3][11:0];
    end
  endfunction
  function automatic logic [1:0] ch_damp_of(input int v);
    int b;
    begin
      b = v * VSTR + (dut.spar_bank ? 28 : 24);
      ch_damp_of = dut.u_state.state_m[b+2][13:12];
    end
  endfunction

  task check(input bit cond, input string what);
    if (!cond) begin
      $display("FAIL: %s", what);
      errors++;
    end else
      $display("  ok: %s", what);
  endtask

  logic [7:0] q;
  logic [23:0] inc0, inc1;
  int seen_rows[0:63];
  int nrows;

  // P.2 foreground-SFX recovery probes.  The aggregate PCM can remain busy
  // when one loud leaf survives, so count each music slot at its own fold
  // phase.  These counters are used by the focused +recovery test below.
  int recovery_seen[0:3];
  int recovery_audible[0:3];
  int recovery_nonzero[0:3];
  longint recovery_abs[0:3];
  logic [15:0] recovery_phase_first[0:3];
  logic [15:0] recovery_phase_last[0:3];

  task measure_music_recovery(input int visits);
    int guard;
    int sl;
    int v;
    bit done;
    for (int i = 0; i < 4; i++) begin
      recovery_seen[i] = 0;
      recovery_audible[i] = 0;
      recovery_nonzero[i] = 0;
      recovery_abs[i] = 0;
      recovery_phase_first[i] = 0;
      recovery_phase_last[i] = 0;
    end
    guard = 0;
    done = 0;
    while (!done && guard < visits * 4000) begin
      @(negedge clk);
      guard++;
      if (dut.u_walk.prun && dut.u_walk.pph == 7'd23
          && dut.u_walk.pc_ch >= 3'd4) begin
        sl = int'(dut.u_walk.pc_ch) - 4;
        if (recovery_seen[sl] < visits) begin
          v = $signed(dut.u_walk.mix_leaf);
          if (recovery_seen[sl] == 0)
            recovery_phase_first[sl] = dut.u_walk.s_phase;
          recovery_phase_last[sl] = dut.u_walk.s_phase;
          recovery_seen[sl]++;
          if (dut.u_walk.mx_aud) recovery_audible[sl]++;
          if (v != 0) recovery_nonzero[sl]++;
          recovery_abs[sl] += (v < 0) ? -v : v;
        end
      end
      done = 1;
      for (int i = 0; i < 4; i++)
        if (recovery_seen[i] < visits) done = 0;
    end
    check(done, "observed every music slot at the preview fold phase");
    for (int i = 0; i < 4; i++)
      $display("  recovery slot %0d: seen=%0d audible=%0d nonzero=%0d abs=%0d phase=%04x..%04x",
               i, recovery_seen[i], recovery_audible[i],
               recovery_nonzero[i], recovery_abs[i],
               recovery_phase_first[i], recovery_phase_last[i]);
  endtask

  // Profiling helpers isolate one workload and optionally emit PCM at the
  // DUT's sample strobe rather than at the host/system clock.
  task zero_counters;
    for (int i = 0; i < 64; i++) st_clk[i] = 0;
    fsm_own = 0; walk_own = 0; frozen_seq = 0; total_clk = 0; samples = 0;
    tick_own = 0; max_tick_own = 0; walk_run = 0; max_walk_run = 0;
    sample_job_clocks = 0; max_sample_job_clocks = 0; sample_job_active = 0;
    tick_job_clocks = 0; max_tick_job_clocks = 0; tick_job_active = 0;
    tick_window_clocks = 0; tick_window = 0; tick_window_active = 0;
    tick_busy_at_pretick = 0; late_flips = 0;
  endtask

  task cart_profile(input string path, input int pat, input int nticks);
    $readmemh(path, img);
    upload();
    wr(8'h21, 8'h07);
    wr(8'h20, 8'(pat));
    ticks(2);
    zero_counters();
    state_wr_lost = 0; samp_over_prun = 0; samp_over_fold = 0;
    for (int sl = 0; sl < 8; sl++) slot_play[sl] = 0;
    ticks(nticks);
    $display("");
    $display("=== cart demand profile: %s, music %0d, %0d ticks, %s schedule",
             path, pat, nticks, (PREVIEW_P != 0) ? "PREVIEW" : "hardware");
    report_demand();
  endtask

  task renderer_trace(input string path, input int pat, input int sfx,
                      input int nsamples);
    int captured;
    integer trace_fd;
    bit primed;
    $readmemh(path, img);

    repeat (16) @(negedge clk);
    reset = 0;
    repeat (16) @(negedge clk);
    upload();

    reset = 1;
    repeat (16) @(negedge clk);
    reset = 0;
    repeat (16) @(negedge clk);
    do @(negedge clk); while (!dut.sample_en);
    @(negedge clk);

    wr(8'h21, 8'h07);
    if (sfx >= 0)
      wr(8'h10, 8'(sfx));
    else
      wr(8'h20, 8'(pat));

    trace_fd = $fopen(pcm_trace_path, "w");
    if (trace_fd == 0) begin
      $display("FAIL: cannot open PCM trace %s", pcm_trace_path);
      errors++;
      return;
    end
    captured = 0;
    primed = 0;
    while (captured < nsamples) begin
      @(negedge clk);
      if (dut.sample_en) begin
        if (!primed)
          primed = 1;
        else begin
          $fdisplay(trace_fd, "%0d", $signed(pcm));
          captured++;
        end
      end
    end
    $fclose(trace_fd);
    $display("PCM renderer trace samples %0d -> %s", captured, pcm_trace_path);
  endtask

  task report_demand;
    $display("");
    $display("  ---- demand-side budget (clock-rate independent) ----");
    $display("  clock %0d Hz, %0d clocks/sample", CLKHZ, CLKHZ / 22050);
    $display("  samples rendered      %0d", samples);
    $display("  walk clocks total     %0d  (%0d per sample avg, %0d worst run)",
             walk_own, (samples != 0) ? walk_own / samples : 64'd0, max_walk_run);
    $display("  seq FSM own clocks    %0d  (%0d worst uninterrupted tick job)",
             fsm_own, max_tick_own);
    $display("  seq frozen clocks     %0d", frozen_seq);
    $display("  TOTAL busy per sample %0d of %0d",
             (samples != 0) ? (walk_own + fsm_own) / samples : 64'd0, CLKHZ / 22050);
    $display("  state writes LOST     %0d  (walk/tick collision, silently dropped)",
             state_wr_lost);
    check(state_wr_lost == 0,
          "no tick-engine write was dropped by a colliding walk write");
    $display("  slot sounding samples  %0d %0d %0d %0d | %0d %0d %0d %0d  (fg 0-3 | music 4-7)",
             slot_play[0], slot_play[1], slot_play[2], slot_play[3],
             slot_play[4], slot_play[5], slot_play[6], slot_play[7]);
    $display("  sample_en during walk  %0d prun, %0d fold_busy  (of %0d samples)",
             samp_over_prun, samp_over_fold, samples);
    check(samp_over_prun == 0 && samp_over_fold == 0,
          "no sample boundary landed inside the walk or its fold");
    $display("  ---- sequencer clocks by state group ----");
    begin
      longint g_note, g_eff, g_slide, g_eng, g_pub, g_ins, g_ldst, g_mus;
      g_note = st_clk[1]+st_clk[2]+st_clk[3]+st_clk[4]+st_clk[5]+st_clk[6]+st_clk[7]
             + st_clk[8]+st_clk[9]+st_clk[10]+st_clk[11]+st_clk[12]+st_clk[13];
      g_eff  = st_clk[14]+st_clk[15];
      g_slide= st_clk[16]+st_clk[17]+st_clk[18]+st_clk[19]+st_clk[20]
             + st_clk[21]+st_clk[22]+st_clk[23]+st_clk[24];
      g_eng  = st_clk[25]+st_clk[26]+st_clk[27]+st_clk[28]+st_clk[29]+st_clk[30]
             + st_clk[31]+st_clk[32]+st_clk[33];
      g_pub  = st_clk[34]+st_clk[35]+st_clk[36]+st_clk[37]
             + st_clk[38]+st_clk[39]+st_clk[40]+st_clk[41];
      g_ins  = st_clk[42]+st_clk[43]+st_clk[44]+st_clk[45]+st_clk[46]
             + st_clk[47]+st_clk[48]+st_clk[49]+st_clk[50];
      g_ldst = st_clk[52]+st_clk[53]+st_clk[54];
      g_mus  = st_clk[51]+st_clk[55]+st_clk[56]+st_clk[57]+st_clk[58]
             + st_clk[59]+st_clk[60]+st_clk[61]+st_clk[62];
      $display("  note fetch T_*/K_*    %0d", g_note);
      $display("  EFFECT K_PF0/K_FX     %0d", g_eff);
      $display("  slide detour K_SL*    %0d", g_slide);
      $display("  tick engine EA*/ES*   %0d", g_eng);
      $display("  publication P_W*/PC*  %0d", g_pub);
      $display("  instrument I_*        %0d", g_ins);
      $display("  record V_LD/V_ST/ROT  %0d", g_ldst);
      $display("  music flow ML_*/MS_*  %0d", g_mus);
      $display("  idle S_IDLE           %0d", st_clk[0]);
    end
    $display("");

    $display("  synthesis deadline: worst %0d / %0d clocks",
             max_sample_job_clocks, CLKHZ / 22050);
    check(max_sample_job_clocks > 0 && max_sample_job_clocks < CLKHZ / 22050,
          "all slot and mix work completes before the next sample");
    $display("  tick pre-run: worst %0d / %0d clocks after pre_tick, %0d spare, %0d late flips",
             max_tick_job_clocks, tick_window,
             tick_window - max_tick_job_clocks, late_flips);
    check(max_tick_job_clocks > 0,
          "each tick evaluation stages its bank before the boundary");
    check(late_flips == 0,
          "no boundary flip was delayed by a colliding trigger pass");
  endtask

  // +audio selects profiling mode; without it the synthetic functional suite
  // runs and reports the same behavior checks as psg_tb.
  initial begin
    for (int i = 0; i < 4608; i++) img[i] = 0;

    begin
      automatic string cart_path = "";
      automatic int    cart_pat = 0, cart_sfx = -1, cart_ticks = 500;
      automatic int    renderer_samples = 0;
      if ($value$plusargs("audio=%s", cart_path)) begin
        void'($value$plusargs("music=%d", cart_pat));
        void'($value$plusargs("sfx=%d", cart_sfx));
        void'($value$plusargs("ticks=%d", cart_ticks));
        void'($value$plusargs("pcm=%s", pcm_trace_path));
        void'($value$plusargs("renderer_samples=%d", renderer_samples));
        if (renderer_samples > 0) begin
          if (pcm_trace_path == "") begin
            $display("FAIL: +renderer_samples requires +pcm=<path>");
            errors++;
          end else
            renderer_trace(cart_path, cart_pat, cart_sfx, renderer_samples);
        end else begin
          repeat (8) @(posedge clk);
          reset = 0;
          cart_profile(cart_path, cart_pat, cart_ticks);
        end
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
      end
    end

    if ($test$plusargs("binding_only")) begin
      automatic integer binding_commits = 0;
      automatic integer binding_total_commits = 0;
      automatic integer binding_guard = 0;
      for (int r = 0; r < 32; r++) begin
        set_note(0, r, 33, 0, 0, 0);
        set_note(1, r, 29, 6, 7, 0);
        set_note(3, r, 41, 6, 7, 0);
        set_inote(20, r, 35, 2, 7, 0);
      end
      set_meta(0, 255, 0, 0);
      set_meta(1, 255, 0, 0);
      set_meta(3, 255, 0, 0);
      set_meta(20, 255, 0, 0);
      set_filter(0, 8'd48);
      set_filter(1, 8'h12);
      set_filter(3, 8'h04);
      set_wavetable(2, 100, 1'b0);
      set_filter(2, 8'h0c);
      set_pat(0, 8'd0, 8'd1, 8'd3, 8'h40 | 8'd20);

      repeat (8) @(posedge clk);
      reset = 0;
      repeat (8) @(posedge clk);
      upload;
      wr(8'h10, 8'd0);
      wr(8'h11, 8'd1);
      wr(8'h12, 8'd20);
      wr(8'h13, 8'd3);
      wr(8'h20, 8'd0);
      while (dut.u_seq.play_bits != 8'h7f
             && binding_guard < 500000) begin
        @(negedge clk);
        binding_guard++;
      end
      check(dut.u_seq.play_bits == 8'h7f,
            "binding profile published foreground, hidden music and stopped slots");
      binding_guard = 0;
      while (!(dut.u_walk.prun && dut.u_walk.pc_ch == 3'd2
               && dut.u_walk.s_snd_wt) && binding_guard < 500000) begin
        @(negedge clk);
        binding_guard++;
      end
      check(dut.u_walk.s_snd_wt,
            "binding profile loaded the wavetable sounding parameters");
      do @(negedge clk); while (!dut.sample_en);
      binding_trace_active = 1'b1;
      // Re-trigger one already-playing voice after tracing starts so the
      // value stream observes both sides of the real clear/ack transition.
      wr(8'h10, 8'd0);
      // Exercise the legacy walk's complete carried-value hold boundary at a
      // service-idle phase.  This is a proof-only testbench override: the
      // production controller remains untouched, while the value stream sees
      // three real clock edges with pph, state ports and every carried walker
      // value frozen.  C1 separately covers in-flight DQ/multiplier freezes.
      fork
        begin : binding_value_hold_probe
          if (value_trace_fd != 0) begin
            do @(negedge clk); while (!(dut.u_walk.prun
                                        && dut.u_walk.pc_ch == 3'd0
                                        && dut.u_walk.pph == 7'd45));
            force dut.ctrl_stall = 1'b1;
            repeat (3) @(negedge clk);
            release dut.ctrl_stall;
          end
        end
      join_none
      binding_guard = 0;
      while (binding_commits < 200 && binding_guard < 500000) begin
        @(negedge clk);
        if (dut.dry_valid) begin
          binding_commits++;
          binding_total_commits++;
        end
        binding_guard++;
      end
      // The loop sees dry_valid after its committing NBA edge.  Keep the
      // value trace enabled through the following rising edge so that the
      // final segment sample includes its dry16 -> pcm publication pair.
      if (value_trace_fd != 0)
        @(posedge clk);
      #1;
      check(binding_commits == 200,
            "binding profile completed the built-in/wavetable base segment");

      // Complement every slot's waveform guard with a second live image:
      // foreground 0/1/3 and music 4..7 now use instrument-2 wavetable data,
      // while foreground slot 2 changes from instrument-2 to built-in SFX20.
      // Both segments run for longer than one 120-Hz publication interval, so
      // every active identity appears in both parameter banks without forcing
      // any internal state or fabricating a service result.
      binding_trace_active = 1'b0;
      for (int r = 0; r < 32; r++) begin
        set_inote(0, r, 33, 2, 7, 0);
        set_inote(1, r, 29, 2, 7, 0);
        set_inote(3, r, 41, 2, 7, 0);
        set_note(20, r, 35, 0, 7, 0);
      end
      set_wavetable(2, 100, 1'b0);
      set_filter(2, 8'h0c);
      // Reverb is decoded from the base SFX filter, not the wavetable
      // instrument filter.  Make every slot's second-segment base exercise
      // the ring transaction; the first segment retains the disabled class.
      set_filter(0, 8'd48);
      set_filter(1, 8'd48);
      set_filter(3, 8'd48);
      set_filter(20, 8'd48);
      set_meta(0, 255, 0, 0);
      set_meta(1, 255, 0, 0);
      set_meta(3, 255, 0, 0);
      set_meta(20, 255, 0, 0);
      set_pat(0, 8'd0, 8'd1, 8'd3, 8'd0);
      upload;
      wr(8'h10, 8'd0);
      wr(8'h11, 8'd1);
      wr(8'h12, 8'd20);
      wr(8'h13, 8'd3);
      wr(8'h20, 8'd0);
      binding_guard = 0;
      while (dut.u_seq.play_bits != 8'hff && binding_guard < 500000) begin
        @(negedge clk);
        binding_guard++;
      end
      check(dut.u_seq.play_bits == 8'hff,
            "complement profile published all eight active slots");
      do @(negedge clk); while (!dut.sample_en);
      binding_trace_active = 1'b1;
      binding_commits = 0;
      binding_guard = 0;
      while (binding_commits < 200 && binding_guard < 500000) begin
        @(negedge clk);
        if (dut.dry_valid) begin
          binding_commits++;
          binding_total_commits++;
        end
        binding_guard++;
      end
      if (value_trace_fd != 0)
        @(posedge clk);
      #1;
      check(binding_commits == 200 && binding_total_commits == 400,
            "binding profile completed four hundred complementary commits");
      check(binding_trace_fd != 0 && binding_trace_rows > 0,
            "binding profile emitted structural source rows");
      if (value_trace_fd != 0)
        check(value_trace_rows > 0 && value_trace_rows[0] == 1'b0,
              "binding profile emitted paired live-value rows");
      $display("PSG binding profile: %0d commits, %0d structural rows",
               binding_total_commits, binding_trace_rows);
      if (value_trace_fd != 0)
        $display("PSG live-value profile: %0d paired rows",
                 value_trace_rows);
      if (errors == 0) $display("ALL TESTS PASSED");
      else             $display("%0d TEST(S) FAILED", errors);
      $finish;
    end

    if (!$test$plusargs("recovery")) begin

    for (int r = 0; r < 32; r++) set_note(0, r, 30 + r % 8, 0, 7, 0);
    set_meta(0, 4, 2, 6);

    for (int r = 0; r < 32; r++) set_note(1, r, 40, 3, 7, 0);
    set_meta(1, 2, 8, 0);

    set_note(2, 0, 21, 0, 7, 0);
    set_note(2, 1, 33, 0, 7, 1);
    set_meta(2, 8, 0, 0);

    set_note(3, 0, 33, 0, 7, 3);
    set_meta(3, 16, 0, 0);

    set_note(4, 0, 33, 0, 7, 4);
    set_note(4, 1, 33, 0, 7, 5);
    set_meta(4, 8, 0, 0);

    set_note(5, 0, 10, 0, 7, 6);
    set_note(5, 1, 20, 0, 7, 0);
    set_note(5, 2, 30, 0, 7, 0);
    set_note(5, 3, 40, 0, 7, 0);
    set_meta(5, 16, 0, 0);

    for (int r = 0; r < 32; r++) set_note(6, r, 33, 0, 7, 0);
    set_meta(6, 1, 0, 0);

    for (int r = 0; r < 32; r++) set_note(7, r, 30, 6, 7, 0);
    set_meta(7, 16, 0, 0); set_filter(7, 2);
    for (int r = 0; r < 32; r++) set_note(8, r, 30, 6, 7, 0);
    set_meta(8, 16, 0, 0); set_filter(8, 146);

    for (int r = 0; r < 32; r++) set_note(9, r, 40, 0, 7, 0);
    set_meta(9, 16, 0, 0); set_filter(9, 8);

    for (int r = 0; r < 32; r++) set_note(10, r, 30, 6, 7, 0);
    set_meta(10, 16, 0, 0); set_filter(10, 2);
    for (int r = 0; r < 32; r++) set_note(11, r, 30, 6, 7, 0);
    set_meta(11, 16, 0, 0); set_filter(11, 0);
    for (int r = 0; r < 32; r++) set_note(12, r, 30, 6, 7, 0);
    set_meta(12, 16, 0, 0); set_filter(12, 4);

    set_note(13, 0, 40, 3, 7, 0);
    for (int r = 1; r < 16; r++) set_note(13, r, 40, 3, 0, 0);
    set_meta(13, 4, 16, 0); set_filter(13, 48);
    set_note(14, 0, 40, 3, 7, 0);
    for (int r = 1; r < 16; r++) set_note(14, r, 40, 3, 0, 0);
    set_meta(14, 4, 16, 0); set_filter(14, 0);

    set_pat(0, 8'h06 | 8'h80, 8'h41, 8'h42, 8'h43);
    set_pat(1, 8'h06, 8'h41 | 8'h80, 8'h42, 8'h43);
    set_pat(2, 8'h06, 8'h41, 8'h42 | 8'h80, 8'h43);

    repeat (8) @(posedge clk);
    reset = 0;
    repeat (8) @(posedge clk);

    upload;

    $display("[1] speed and loop rows");
    wr(8'h10, 8'd0);
    ticks(1);
    rd(8'h03, q);
    check(q[0] == 1, "channel 0 playing after trigger");
    nrows = 0;
    for (int i = 0; i < 64; i++) seen_rows[i] = -1;
    repeat (30) begin
      ticks(4);
      rd(8'h10, q);
      seen_rows[nrows] = int'(q[4:0]);
      nrows++;
    end

    check(seen_rows[0] == 1 || seen_rows[0] == 2, "rows advance at speed");
    for (int i = 10; i < 30; i++)
      check(seen_rows[i] >= 2 && seen_rows[i] <= 5, "looped row in [2,6)");
    wr(8'h10, 8'h80);
    rd(8'h03, q);
    check(q[0] == 0, "channel 0 stops on $80");

    $display("[2] length-only: 8 rows at speed 2");
    wr(8'h11, 8'd1);
    ticks(8 * 2 - 4);
    rd(8'h03, q);
    check(q[1] == 1, "still playing before row 8");
    ticks(8);
    rd(8'h03, q);
    check(q[1] == 0, "stopped after 8 rows");

    $display("[3] slide interpolates the phase increment");
    wr(8'h12, 8'd2);
    ticks(9);
    inc0 = eff_inc_of(2);
    ticks(6);
    inc1 = eff_inc_of(2);
    check(inc0 > 24'd120000 && inc0 < 24'd220000, "slide starts near f(21)");
    check(inc1 > inc0, "slide rises across the row");
    check(inc1 > 24'd280000, "slide approaches f(33)");
    wr(8'h12, 8'h80);

    $display("[4] drop falls toward zero");
    wr(8'h13, 8'd3);
    ticks(2);
    inc0 = eff_inc_of(3);
    ticks(12);
    inc1 = eff_inc_of(3);
    check(inc0 > inc1, "drop decreases");
    check(inc1 < 24'd60000, "drop nearly silent-frequency by row end");
    wr(8'h13, 8'h80);

    $display("[5] fade in / fade out volume ramps");
    wr(8'h10, 8'd4);
    ticks(2);
    inc0 = {12'b0, eff_vol_of(0)};
    ticks(5);
    inc1 = {12'b0, eff_vol_of(0)};
    check(inc1 > inc0, "fade-in volume rises");
    ticks(3);
    inc0 = {12'b0, eff_vol_of(0)};
    ticks(5);
    inc1 = {12'b0, eff_vol_of(0)};
    check(inc1 < inc0, "fade-out volume falls");
    wr(8'h10, 8'h80);

    $display("[6] arpeggio cycles the row group");
    wr(8'h11, 8'd5);
    begin
      int hits[0:3];
      for (int i = 0; i < 4; i++) hits[i] = 0;
      for (int i = 0; i < 15; i++) begin
        ticks(1);

        case (eff_inc_of(1))
          {3'b0, dut.u_seq.crom[10][12:0], 8'b0}: hits[0]++;
          {3'b0, dut.u_seq.crom[20][12:0], 8'b0}: hits[1]++;
          {3'b0, dut.u_seq.crom[30][12:0], 8'b0}: hits[2]++;
          {3'b0, dut.u_seq.crom[40][12:0], 8'b0}: hits[3]++;
          default: ;
        endcase
      end
      check(hits[0] > 0 && hits[1] > 0 && hits[2] > 0 && hits[3] > 0,
            "all four group pitches sounded within 15 ticks");
    end
    wr(8'h11, 8'h80);

    $display("[7] music: chain, loop-back, stop flag");
    wr(8'h20, 8'd0);
    ticks(2);
    rd(8'h03, q);
    check(q[7] == 1, "music playing");

    check(dut.u_seq.playing[4] == 1, "music launched sfx on channel 0's music slot");
    ticks(34);
    rd(8'h20, q);
    check(q[5:0] == 6'd1, "advanced to pattern 1");
    ticks(34);
    rd(8'h20, q);
    check(q[5:0] == 6'd0, "looped back to the loop-start pattern");
    wr(8'h20, 8'h80);
    rd(8'h03, q);
    check(q[7] == 0, "music stops on $80");
    check(dut.u_seq.playing[4] == 0, "music channel silenced on stop");

    wr(8'h20, 8'd2);
    ticks(2);
    rd(8'h03, q);
    check(q[7] == 1, "stop-flag pattern starts");
    ticks(40);
    rd(8'h03, q);
    check(q[7] == 0, "music halts after stop-flag pattern");

    $display("[8] pcm moves while a note plays");
    wr(8'h10, 8'd0);
    begin
      int lo, hi;
      lo = 255; hi = 0;
      repeat (4 * CLKS_PER_TICK) begin
        @(posedge clk);
        if (int'(pcm) < lo) lo = int'(pcm);
        if (int'(pcm) > hi) hi = int'(pcm);
      end
      check(hi - lo > 30, "pcm swings with a full-volume note");
    end
    wr(8'h10, 8'h80);

    $display("[9] dampen low-passes white noise");
    begin
      int md0, md2, ch0, ch2;
      wr(8'h10, 8'd7);
      ticks(2);
      measure(24000, md0, ch0);
      wr(8'h10, 8'h80);
      wr(8'h10, 8'd8);
      ticks(2);
      measure(24000, md2, ch2);
      wr(8'h10, 8'h80);
      check(md0 > 0, "clean noise has large steps");
      check(md2 * 2 < md0, "dampen shrinks the peak sample step");
    end

    $display("[10] detune runs a second voice");
    wr(8'h11, 8'd9);
    ticks(2);
    check(phase2_of(1) != 0, "detuned second accumulator advances");
    wr(8'h11, 8'h80);

    $display("[11] noise paths remain live; brown is smoother");
    begin
      int mdw, mdp, mdb, cw, cp, cb;
      wr(8'h10, 8'd10); ticks(2); measure(24000, mdw, cw); wr(8'h10, 8'h80);
      wr(8'h10, 8'd11); ticks(2); measure(24000, mdp, cp); wr(8'h10, 8'h80);
      wr(8'h10, 8'd12); ticks(2); measure(24000, mdb, cb); wr(8'h10, 8'h80);

      check(cw > 0 && cp > 0, "white and pitched noise paths both update");
      check(mdb < mdw, "brown noise has smaller sample steps than white");
    end

    $display("[12] reverb leaves an echo tail after note-off");
    begin
      int tail_rev, tail_dry;

      wr(8'h12, 8'd14);
      ticks(6);
      peak_dev(78000, tail_dry);
      wr(8'h12, 8'h80);
      ticks(2);
      wr(8'h12, 8'd13);
      ticks(6);
      peak_dev(78000, tail_rev);
      wr(8'h12, 8'h80);
      check(tail_dry < 4, "a dry note leaves nothing behind");
      check(tail_rev > tail_dry + 8, "reverb tail outlasts the dry note");
    end

    $display("[13] delta-sigma density tracks a PCM ramp");
    begin
      int lo_hi, hi_hi;
      lo_hi = 0; hi_hi = 0;
      ds_pcm = 16'sd32;
      repeat (2000) begin @(posedge clk); if (ds_out) lo_hi++; end
      ds_pcm = 16'sd224;
      repeat (2000) begin @(posedge clk); if (ds_out) hi_hi++; end
      check(hi_hi > lo_hi, "higher PCM -> denser 1s");
      check(lo_hi > 100 && hi_hi < 1900, "density is proportional, not saturated");
    end

    for (int r = 0; r < 32; r++) set_note(15, r, 20 + r, 0, 7, 0);
    set_meta(15, 4, 0, 0);

    for (int r = 0; r < 32; r++) set_note(16, r, 30, 0, 7, 0);
    set_meta(16, 2, 2, 6);

    for (int r = 0; r < 32; r++) set_note(17, r, 30, 0, 7, 0);
    set_meta(17, 16, 0, 0);

    for (int r = 0; r < 32; r++)
      set_note(0, r, 24, 0, (r % 2 != 0) ? 2 : 5, 0);
    set_meta(0, 1, 0, 0);
    for (int r = 0; r < 32; r++) set_note(1, r, 36, 0, 7, 0);
    set_meta(1, 8, 0, 0);
    set_wavetable(2, 100, 1'b0);
    set_wavetable(3, 0,   1'b0);
    set_wavetable(4, 100, 1'b1);

    set_inote(18, 0, 33, 0, 7, 0); set_inote(18, 1, 33, 0, 7, 0);
    set_meta(18, 16, 2, 0);
    set_inote(19, 0, 33, 1, 7, 0); set_meta(19, 16, 1, 0);
    set_inote(20, 0, 33, 2, 7, 0); set_meta(20, 16, 1, 0);
    set_inote(21, 0, 33, 3, 7, 0); set_meta(21, 16, 1, 0);
    set_inote(22, 0, 33, 4, 7, 0); set_meta(22, 16, 1, 0);

    set_inote(23, 0, 33, 0, 7, 0); set_inote(23, 1, 33, 0, 7, 0);
    set_meta(23, 4, 2, 0);
    set_inote(24, 0, 33, 0, 7, 0); set_inote(24, 1, 34, 0, 7, 0);
    set_meta(24, 4, 2, 0);

    set_inote(26, 0, 33, 0, 7, 0); set_inote(26, 1, 33, 0, 7, 3);
    set_meta(26, 4, 2, 0);

    for (int r = 0; r < 32; r++) set_note(25, r, 30, 0, 7, 0);
    set_meta(25, 16, 0, 0); set_filter(25, 224);

    set_pat(3, 8'h06, 8'h06, 8'h06, 8'h06);

    for (int r = 0; r < 32; r++) set_note(40, r, 60, 6, 7, 0);
    set_meta(40, 16, 0, 0); set_filter(40, 2);
    for (int r = 0; r < 32; r++) set_note(41, r, 0, 0, 0, 0);
    set_meta(41, 16, 0, 0);
    upload;
    end

    // P.2: Celeste reserves music channels 0..2 and auto-picks foreground
    // channel 3 for jump effects.  Repeatedly retrigger a short effect while
    // the three music slots continue underneath, then prove recovery from the
    // per-slot fold leaves rather than from aggregate PCM activity.
    if ($test$plusargs("recovery")) begin
      string recovery_audio;
      int stop_guard;
      int clear_guard;

      reset = 1;
      repeat (16) @(negedge clk);
      reset = 0;
      repeat (16) @(negedge clk);
      errors = 0;

      if ($value$plusargs("recovery_audio=%s", recovery_audio)) begin
        $readmemh(recovery_audio, img);
        // Use Celeste's real music SFX 10..12 in a stable self-looping
        // three-channel pattern; channel 3 remains disabled as in the cart.
        set_pat(3, 8'h8a, 8'h8b, 8'h0c, 8'h44);
      end else begin
        // Standalone form of Celeste's timing mix.  The 32-tick channel is
        // what exposed a held EA2 consume being overwritten with word 1.
        for (int r = 0; r < 32; r++) begin
          set_note(29, r, 36, 0, 7, 0);
          set_note(30, r, 42, 0, 7, 0);
          set_note(31, r, 48, 0, 7, 0);
        end
        set_meta(29, 16, 0, 0);
        set_meta(30, 32, 0, 0);
        set_meta(31, 16, 0, 32);
        set_pat(3, 8'h9f, 8'h1e, 8'h1d, 8'h5c);
      end
      upload;

      wr(8'h21, 8'h07);
      wr(8'h22, 8'd0);
      wr(8'h20, 8'd3);
      ticks(6);
      check(dut.u_seq.playing[4] && dut.u_seq.playing[5]
            && dut.u_seq.playing[6] && !dut.u_seq.playing[7],
            "Celeste-shaped pattern owns exactly music channels 0..2");

      measure_music_recovery(512);
      for (int i = 0; i < 3; i++) begin
        check(recovery_audible[i] == 512 && recovery_nonzero[i] > 32,
              "each baseline music slot reaches the preview fold");
      end

      recovery_preboundary = 0;
      recovery_coalesced = 0;
      recovery_delayed = 0;
      recovery_dropped_samples = 0;
      recovery_probe = 1;
      for (int n = 0; n < 64; n++) begin
        // Celeste's jump is SFX 1.  At one trigger per PSG tick this always
        // retriggers while active and sweeps the relative pre-tick phase.
        wr(8'h13, 8'd1);
        ticks(1);
      end
      stop_guard = 0;
      while (dut.u_seq.playing[3] && stop_guard < 128) begin
        ticks(1);
        stop_guard++;
      end
      clear_guard = 0;
      while (dut.u_walk.clr_ack_pv[3] != dut.clr_tog[3]
             && clear_guard < CLKS_PER_TICK) begin
        @(posedge clk);
        clear_guard++;
      end
      recovery_probe = 0;

      $display("  recovery scheduling: preboundary=%0d coalesced=%0d delayed=%0d dropped_samples=%0d",
               recovery_preboundary, recovery_coalesced, recovery_delayed,
               recovery_dropped_samples);
      check(stop_guard < 128, "foreground SFX reaches its natural stop");
      check(!dut.u_seq.playing[3], "foreground channel 3 stops after retriggers");
      check(clear_guard < CLKS_PER_TICK,
            "preview consumes the final foreground clear token promptly");
      check(dut.u_walk.clr_ack_pv[3] == dut.clr_tog[3],
            "preview consumes the final foreground clear token");
      check(recovery_coalesced == 0,
            "repeated foreground triggers do not coalesce a music tick");
      check(recovery_delayed == 0,
            "repeated foreground triggers do not delay music publication");

      measure_music_recovery(512);
      for (int i = 0; i < 3; i++) begin
        check(dut.u_seq.playing[4+i], "music owner survives repeated SFX");
        check(recovery_audible[i] == 512 && recovery_nonzero[i] > 32,
              "music slot is audible again after foreground release");
        check(recovery_phase_first[i] != recovery_phase_last[i],
              "recovered music oscillator keeps advancing");
        check(recovery_abs[i] > 0,
              "recovered music leaf retains material signal energy");
      end
      check(recovery_audible[3] == 0,
            "unused fourth music channel remains silent");

      if (errors == 0) $display("ALL TESTS PASSED");
      else             $display("%0d TEST(S) FAILED", errors);
      $finish;
    end

    $display("[14] start row and length");
    wr(8'h14, 8'd8);
    wr(8'h18, 8'd4);
    wr(8'h10, 8'd15);
    ticks(1);
    rd(8'h10, q);
    check(q[4:0] == 5'd8, "playback starts at the requested row");
    ticks(13);
    rd(8'h03, q);
    check(q[0] == 1, "still playing inside the 4-row slice");
    ticks(5);
    rd(8'h03, q);
    check(q[0] == 0, "stops after exactly 4 rows");
    wr(8'h10, 8'd15);
    ticks(1);
    rd(8'h10, q);
    check(q[4:0] == 5'd0, "start row and length do not persist");
    wr(8'h10, 8'h80);

    $display("[15] release from looping");
    wr(8'h11, 8'd16);
    ticks(16);
    rd(8'h11, q);
    check(q[4:0] >= 5'd2 && q[4:0] < 5'd6, "looping inside [2,6)");
    wr(8'h11, 8'h81);
    ticks(8);
    rd(8'h11, q);
    check(q[7] == 1 && q[4:0] >= 5'd6, "released playback leaves the loop");
    ticks(56);
    rd(8'h03, q);
    check(q[1] == 0, "released sfx stops at the end of the record");

    $display("[16] channel reports which sfx it plays");
    wr(8'h12, 8'd17);
    ticks(1);
    rd(8'h16, q);
    check(q == 8'h91, "channel 2 reads back {playing, sfx 17}");
    wr(8'h12, 8'h80);
    ticks(1);
    rd(8'h16, q);
    check(q[7] == 0, "playing bit clears when the channel is stopped");

    $display("[17] music fade");
    wr(8'h22, 8'd125);
    wr(8'h20, 8'd0);
    ticks(2);
    check(dut.u_seq.mus_gain < 8'd40, "fade-in starts near silence");
    ticks(60);
    check(dut.u_seq.mus_gain > 8'd60, "fade-in gain rises");
    wr(8'h22, 8'd16);
    wr(8'h20, 8'h80);
    ticks(4);
    rd(8'h03, q);
    check(q[7] == 1, "music keeps playing while it fades out");
    check(dut.u_seq.mus_gain < 8'd230, "fade-out gain falls");
    ticks(40);
    rd(8'h03, q);
    check(q[7] == 0, "music stops when the fade-out reaches silence");
    check(q[3:0] == 4'd0, "music channels are silenced");

    $display("[18] channel mask reserves, it does not gate");
    wr(8'h21, 8'h07);
    wr(8'h20, 8'd3);
    ticks(2);
    check(dut.u_seq.playing[4] && dut.u_seq.playing[5] && dut.u_seq.playing[6] && dut.u_seq.playing[7],
          "all four pattern channels launch on their music slots");
    rd(8'h03, q);
    check(q[7], "the song reads as playing");

    check(q[3:0] == 4'h0,
          "the song leaves all four foreground slots free for effects");
    rd(8'h21, q);
    check(q[3:0] == 4'h7, "the reservation mask reads back");
    check(q[7:4] == 4'h0, "and the occupancy nibble no longer blocks anything");
    wr(8'h20, 8'h80);
    wr(8'h21, 8'h00);

    $display("[18b] an SFX covers the music; the music runs on underneath");
    begin
      logic [5:0] mus_sfx;
      logic [7:0] t0;
      wr(8'h20, 8'h80);
      ticks(1);
      wr(8'h21, 8'h00);
      wr(8'h22, 8'd0);
      wr(8'h20, 8'd3);
      ticks(3);
      check(dut.u_seq.playing[4], "channel 0's music slot is running");
      mus_sfx = dut.u_seq.sfx_id[4];
      rd(8'h14, q);
      check(q[7] && q[5:0] == mus_sfx,
            "$14 reports the music while nothing covers it");

      wr(8'h18, 8'd1);
      wr(8'h10, 8'd15);
      ticks(2);
      check(dut.u_seq.playing[0], "channel 0's foreground slot is running");
      check(dut.u_seq.playing[4], "the music slot was NOT stopped");
      check(dut.u_seq.sfx_id[4] == mus_sfx, "and it still holds the music's SFX");
      rd(8'h14, q);
      check(q[5:0] == 6'd15, "$14 reports the covering effect");

      t0 = {3'b0, row_of(4)};
      ticks(6);
      check({3'b0, row_of(4)} != t0, "the covered music advanced while inaudible");
      check(!dut.u_seq.playing[0], "the effect finished");
      rd(8'h14, q);
      check(q[7] && q[5:0] == mus_sfx,
            "the music is audible again, at its own current position");
      wr(8'h20, 8'h80);
      ticks(1);
    end

    $display("[18c] an SFX taken before the pattern's own trigger is serviced");
    begin
      logic [5:0] pat0;
      int guard;
      wr(8'h20, 8'h80);
      ticks(1);
      wr(8'h21, 8'h00);
      wr(8'h22, 8'd0);
      wr(8'h20, 8'd3);

      guard = 0;
      while (!(dut.mus_playing && dut.trig_req[4]) && guard < 2000) begin
        @(posedge clk);
        guard++;
      end
      check(guard < 2000, "the pattern launch raised its trigger requests");
      wr(8'h18, 8'd1);
      wr(8'h10, 8'd15);

      check(dut.trig_req[4], "the music slot's pending trigger is untouched");
      check(dut.u_seq.launched[4], "and it still paces the pattern");

      pat0 = dut.mus_pat;
      ticks(20);
      check(dut.mus_playing, "the music is still playing after the sound ends");
      check(dut.mus_pat == pat0,
            "the sound effect ending did not end the pattern");
      wr(8'h20, 8'h80);
      ticks(1);
    end

    $display("[20c] noise gain follows the noise channel, not channel 0");
    begin
      int pk_alone, pk_with_ch0;
      wr(8'h20, 8'h80);
      for (int i = 0; i < 4; i++) wr(8'h10 + 8'(i), 8'h80);
      ticks(1);
      wr(8'h12, 8'd40);
      ticks(2);
      peak_dev(4000, pk_alone);

      wr(8'h10, 8'd41);
      ticks(2);
      peak_dev(4000, pk_with_ch0);
      check(pk_alone > 20, "the noise is audible on its own");

      check(eff_vol_of(0) == 0 && pk_with_ch0 > 20,
            "a silent low note contributes zero while noise stays audible");
      for (int i = 0; i < 4; i++) wr(8'h10 + 8'(i), 8'h80);
      ticks(1);
    end

    $display("[19] custom instruments");
    begin
      int loud, quiet;
      loud = 0; quiet = 0;
      wr(8'h10, 8'd18);
      ticks(1);
      check(eff_inc_of(0) == {3'b0, dut.u_seq.crom[33][12:0], 8'b0},
            "instrument pitch 24 leaves the note's pitch alone");
      for (int i = 0; i < 6; i++) begin

        if (eff_vol_of(0) == 12'd1280) loud++;
        if (eff_vol_of(0) == 12'd512)  quiet++;
        ticks(1);
      end
      check(loud > 0 && quiet > 0, "instrument volume multiplies the note's");
      wr(8'h10, 8'h80);
    end
    wr(8'h11, 8'd19);
    ticks(2);
    check(eff_inc_of(1) == {3'b0, dut.u_seq.crom[45][12:0], 8'b0},
          "instrument pitch adds relative to C-2 (33 + 36 - 24)");
    wr(8'h11, 8'h80);

    $display("[19b] instrument retrigger rule");
    wr(8'h12, 8'd23);
    ticks(6);
    check(ins_row_of(2) >= 5'd4, "held pitch keeps the instrument running");
    wr(8'h12, 8'h80);
    wr(8'h12, 8'd24);
    ticks(6);
    check(ins_row_of(2) <= 5'd3, "a pitch change retriggers the instrument");
    wr(8'h12, 8'h80);
    wr(8'h12, 8'd26);
    ticks(6);
    check(ins_row_of(2) <= 5'd3, "effect 3 retriggers instead of dropping");
    check(eff_inc_of(2) == {3'b0, dut.u_seq.crom[33][12:0], 8'b0},
          "effect 3 does not drop the pitch");
    wr(8'h12, 8'h80);

    $display("[20] waveform instruments");
    begin
      int pk_wave, pk_zero;
      logic [23:0] inc_plain, inc_bass;
      wr(8'h10, 8'd20);
      ticks(2);
      check(snd_wt_of(0) == 1, "channel switches to the wavetable");
      peak_dev(27000, pk_wave);
      inc_plain = eff_inc_of(0);
      wr(8'h10, 8'h80);
      wr(8'h10, 8'd21);
      ticks(2);
      peak_dev(27000, pk_zero);
      wr(8'h10, 8'h80);
      check(pk_wave > 20, "the wavetable's samples reach the output");
      check(pk_zero < 4, "a zero wavetable is silent (samples really read)");
      wr(8'h10, 8'd22);
      ticks(2);
      inc_bass = eff_inc_of(0);
      wr(8'h10, 8'h80);
      check(inc_bass == (inc_plain >> 1), "the bass flag drops an octave");
    end

    $display("[20d] pre-run budget with all eight slots on slide + instrument");
    begin

      for (int r = 0; r < 32; r++) set_note(26, r, 24 + (r % 12), 0, 5, 0);
      set_meta(26, 1, 0, 0);
      for (int r = 0; r < 32; r++)
        set_inote(27, r, 20 + (r % 24), 2, 7, 1);
      set_meta(27, 3, 0, 0);

      img[8] = 8'd27; img[9] = 8'd27; img[10] = 8'd27; img[11] = 8'd27;
      upload;
      wr(8'h20, 8'd2);
      for (int i = 0; i < 4; i++) wr(8'h10 + 8'(i), 8'd27);
      ticks(8);
      begin
        int live;
        live = 0;
        for (int i = 0; i < 8; i++) if (dut.u_seq.playing[i]) live++;
        check(live == 8, "all eight slots are running");
      end
      for (int i = 0; i < 4; i++) wr(8'h10 + 8'(i), 8'h80);
      wr(8'h21, 8'h00);
      ticks(2);
    end

    $display("[21] dampen field is taken mod 3");
    wr(8'h13, 8'd25);
    ticks(1);
    check(ch_damp_of(3) == 2'd0, "filter byte 224 decodes dampen 0");
    wr(8'h13, 8'h80);

    report_demand();

    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("%0d TEST(S) FAILED", errors);
    $finish;
  end
endmodule
