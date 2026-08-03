// Waveform core and walk-facing adapter regression.
//
// Exhaustively compares fixed-context waveform results with the full and
// PREVIEW adapters, checks preceding-arm context selection, and proves that
// disabling the core holds every pipeline boundary.

`timescale 1ns/1ps
`include "psg_common.svh"
`include "psg_wave.sv"

module psg_wave_ctx_tb;
  bit clk = 1'b0;
  always #5 clk = ~clk;

  logic        ctx_ce = 1'b1;
  logic [15:0] ctx_phase = 16'd0;
  logic [2:0]  ctx_wave = 3'd0;
  logic        ctx_alt = 1'b0;
  logic        ctx_secondary = 1'b0;
  logic signed [17:0] ctx_z;

  logic iss_sec = 1'b0;
  logic iss_om = 1'b0;
  logic iss_os = 1'b0;
  logic dq_old_ctx = 1'b0;
  logic [2:0]  s_snd_wave = 3'd0;
  logic        s_snd_wt = 1'b0;
  logic [1:0]  s_ch_det = 2'd0;
  logic        s_ch_buzz = 1'b0;
  logic [15:0] s_phase_hi = 16'd0;
  logic [23:0] full_phase2 = 24'd0;
  logic [23:0] preview_phase2 = 24'd0;
  logic [12:0] s_eff_inc_hi = 13'd0;
  logic [2:0]  s_old_wave = 3'd0;
  logic [15:0] s_old_phase_hi = 16'd0;
  logic [12:0] s_old_inc_hi = 13'd0;
  logic [1:0]  old_mode_r = 2'd0;
  logic        old_alt_r = 1'b0;
  logic [15:0] old_q0_lo = 16'd0;

  logic signed [17:0] full_z, preview_z;
  logic [16:0] full_dq17, preview_dq17;
  logic [15:0] full_q16, preview_q16;

  psg_wave_ctx dut(
    .clk(clk), .ce(ctx_ce),
    .ctx_phase(ctx_phase), .ctx_wave(ctx_wave), .ctx_alt(ctx_alt),
    .ctx_secondary(ctx_secondary), .z_eval(ctx_z));

  psg_wave #(.REALTIME_PREVIEW(0)) full_adapter_dut(
    .clk(clk),
    .iss_sec(iss_sec), .iss_om(iss_om), .iss_os(iss_os),
    .dq_old_ctx(dq_old_ctx),
    .s_snd_wave(s_snd_wave), .s_snd_wt(s_snd_wt),
    .s_ch_det(s_ch_det), .s_ch_buzz(s_ch_buzz),
    .s_phase_hi(s_phase_hi), .s_phase2(full_phase2),
    .s_eff_inc_hi(s_eff_inc_hi),
    .s_old_wave(s_old_wave), .s_old_phase_hi(s_old_phase_hi),
    .s_old_inc_hi(s_old_inc_hi), .old_mode_r(old_mode_r),
    .old_alt_r(old_alt_r), .old_q0_lo(old_q0_lo),
    .z_eval(full_z), .dq17(full_dq17), .q16(full_q16));

  psg_wave #(.REALTIME_PREVIEW(1)) preview_adapter_dut(
    .clk(clk),
    .iss_sec(iss_sec), .iss_om(iss_om), .iss_os(iss_os),
    .dq_old_ctx(dq_old_ctx),
    .s_snd_wave(s_snd_wave), .s_snd_wt(s_snd_wt),
    .s_ch_det(s_ch_det), .s_ch_buzz(s_ch_buzz),
    .s_phase_hi(s_phase_hi), .s_phase2(preview_phase2),
    .s_eff_inc_hi(s_eff_inc_hi),
    .s_old_wave(s_old_wave), .s_old_phase_hi(s_old_phase_hi),
    .s_old_inc_hi(s_old_inc_hi), .old_mode_r(old_mode_r),
    .old_alt_r(old_alt_r), .old_q0_lo(old_q0_lo),
    .z_eval(preview_z), .dq17(preview_dq17), .q16(preview_q16));

  logic        hold_ce = 1'b1;
  logic [15:0] hold_phase = 16'd0;
  logic signed [17:0] hold_z;
  psg_wave_ctx hold_dut(
    .clk(clk), .ce(hold_ce),
    .ctx_phase(hold_phase), .ctx_wave(3'd3), .ctx_alt(1'b0),
    .ctx_secondary(1'b0), .z_eval(hold_z));

  task automatic step;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic check_outputs(input logic [15:0] phase,
                               input logic [2:0] wave,
                               input logic alt,
                               input logic secondary,
                               input string label);
    begin
      if (ctx_z !== full_z || ctx_z !== preview_z)
        $fatal(1,
               "%s mismatch phase=%h wave=%0d alt=%0b secondary=%0b direct=%0d full=%0d preview=%0d",
               label, phase, wave, alt, secondary,
               ctx_z, full_z, preview_z);
    end
  endtask

  task automatic drive_live(input logic [15:0] phase,
                            input logic [2:0] wave,
                            input logic alt,
                            input logic secondary);
    begin
      ctx_phase = phase;
      ctx_wave = wave;
      ctx_alt = alt;
      ctx_secondary = secondary;

      iss_sec = secondary;
      iss_om = 1'b0;
      iss_os = 1'b0;
      s_snd_wave = wave;
      s_snd_wt = 1'b0;
      s_ch_det = 2'd0;
      s_ch_buzz = alt;
      s_phase_hi = phase;
      full_phase2 = {8'd0, phase};
      preview_phase2 = {phase, 8'd0};
    end
  endtask

  int phase_i;
  int wave_i;
  int alt_i;
  int secondary_i;
  int unsigned context_checks;
  logic [15:0] prior_phase;
  logic [2:0] prior_wave;
  logic prior_alt, prior_secondary;
  logic have_prior;

  initial begin
    // A disabled core must freeze every pipeline boundary, not merely suppress
    // a request strobe.  The first resumed edge captures the new request and
    // the second makes it visible at the result.
    repeat (3) step();
    if (hold_z !== -18'sd6143)
      $fatal(1, "square-wave prime failed: got %0d", hold_z);
    hold_ce = 1'b0;
    hold_phase = 16'hffff;
    repeat (3) begin
      step();
      if (hold_z !== -18'sd6143)
        $fatal(1, "disabled core did not hold result: got %0d", hold_z);
    end
    hold_ce = 1'b1;
    step();
    if (hold_z !== -18'sd6143)
      $fatal(1, "new context escaped on first resumed edge: got %0d", hold_z);
    step();
    if (hold_z !== 18'sd6143)
      $fatal(1, "new context missing on second resumed edge: got %0d", hold_z);

    // The walk-facing adapter selects the preceding primary context,
    // including its independent wave and alternate controls.
    @(negedge clk);
    ctx_phase = 16'h8123;
    ctx_wave = 3'd2;
    ctx_alt = 1'b1;
    ctx_secondary = 1'b0;
    iss_sec = 1'b0;
    iss_om = 1'b1;
    iss_os = 1'b0;
    s_snd_wave = 3'd4;
    s_ch_buzz = 1'b0;
    s_phase_hi = 16'h1234;
    s_old_wave = 3'd2;
    s_old_phase_hi = 16'h8123;
    old_alt_r = 1'b1;
    step();
    step();
    check_outputs(16'h8123, 3'd2, 1'b1, 1'b0, "preceding primary");

    // The preceding secondary uses old_q0_lo in full mode and the compact
    // phase2 view in PREVIEW. Drive both representations to the same context.
    @(negedge clk);
    ctx_phase = 16'h9234;
    ctx_wave = 3'd5;
    ctx_alt = 1'b1;
    ctx_secondary = 1'b1;
    iss_om = 1'b0;
    iss_os = 1'b1;
    s_old_wave = 3'd5;
    old_mode_r = 2'd0;
    old_alt_r = 1'b1;
    old_q0_lo = 16'h9234;
    full_phase2 = 24'h001111;
    preview_phase2 = {16'h9234, 8'd0};
    step();
    step();
    check_outputs(16'h9234, 3'd5, 1'b1, 1'b1, "preceding secondary");

    // Stream every direct first-stage tuple.  Full mode presents phase2 in
    // bits 15:0; PREVIEW presents it in bits 23:8.  One final edge drains the
    // last tuple, giving exactly 8*2*2*65536 checked results.
    ctx_ce = 1'b1;
    iss_om = 1'b0;
    iss_os = 1'b0;
    context_checks = 0;
    have_prior = 1'b0;
    for (wave_i = 0; wave_i < 8; wave_i++) begin
      for (alt_i = 0; alt_i < 2; alt_i++) begin
        for (secondary_i = 0; secondary_i < 2; secondary_i++) begin
          for (phase_i = 0; phase_i < 65536; phase_i++) begin
            @(negedge clk);
            drive_live(16'(phase_i), 3'(wave_i), 1'(alt_i),
                       1'(secondary_i));
            step();
            if (full_q16 !== 16'(phase_i) ||
                preview_q16 !== 16'(phase_i))
              $fatal(1,
                     "phase presentation mismatch phase=%h wave=%0d full=%h preview=%h",
                     16'(phase_i), wave_i, full_q16, preview_q16);
            if (have_prior) begin
              check_outputs(prior_phase, prior_wave, prior_alt,
                            prior_secondary, "exhaustive live");
              context_checks++;
            end
            prior_phase = 16'(phase_i);
            prior_wave = 3'(wave_i);
            prior_alt = 1'(alt_i);
            prior_secondary = 1'(secondary_i);
            have_prior = 1'b1;
          end
        end
      end
    end
    step();
    check_outputs(prior_phase, prior_wave, prior_alt, prior_secondary,
                  "exhaustive live drain");
    context_checks++;
    if (context_checks != 32'd2097152)
      $fatal(1, "wrong exhaustive count: %0d", context_checks);

    $display("psg_wave_ctx_tb: PASS (%0d exhaustive contexts + preceding contexts + hold)",
             context_checks);
    $finish;
  end
endmodule
