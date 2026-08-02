`timescale 1ns/1ps
`include "psg_execwave.sv"

// Direct proof of H-D's explicit W0--W3 substitution boundary.  The older
// production-image test intentionally exercises the H-C compatibility wrapper;
// this test supplies the post-update contexts that the semantic adapter owns.
module psg_execwave_core_tb;
  bit clk;
  logic active, hold, owner, play;
  logic [6:0] action;
  logic [15:0] state_q;
  logic [16:0] phase_w1_raw;
  logic [15:0] phase_w2_raw;
  logic [16:0] phase_w3_raw;

  logic wave_ce, wave_issue, wave_take;
  logic [15:0] wave_phase;
  logic [2:0] wave_sel;
  logic wave_alt, wave_secondary;
  logic aram_req, aram_adjacent, aram_take;
  logic [2:0] aram_id;
  logic [5:0] aram_index;

  localparam logic [6:0]
    LOAD_OSC_14 = 7'h05,
    LOAD_OSC_22 = 7'h0d,
    LOAD_PAR_1  = 7'h11,
    LOAD_PAR_2  = 7'h12,
    CAP_W0      = 7'h22,
    CAP_W1      = 7'h23,
    CAP_W2      = 7'h24,
    CAP_W3      = 7'h25,
    CAP_W4      = 7'h26,
    CAP_W5      = 7'h27;

  psg_execwave_core dut(
    .clk(clk), .active(active), .hold(hold), .owner(owner), .action(action),
    .state_q(state_q), .phase_w1_raw(phase_w1_raw),
    .phase_w2_raw(phase_w2_raw), .phase_w3_raw(phase_w3_raw), .play(play),
    .wave_ce(wave_ce), .wave_issue(wave_issue), .wave_take(wave_take),
    .wave_phase(wave_phase), .wave_sel(wave_sel), .wave_alt(wave_alt),
    .wave_secondary(wave_secondary), .aram_req(aram_req),
    .aram_id(aram_id), .aram_index(aram_index),
    .aram_adjacent(aram_adjacent), .aram_take(aram_take));

  always #5 clk = ~clk;

  function automatic logic [15:0] phase_view(
      input logic [15:0] raw,
      input logic [2:0] wave,
      input logic [1:0] mode,
      input logic wt);
    begin
      if (!wt && (wave == 3'd0 || wave == 3'd7))
        phase_view = raw;
      else if (mode == 2'd2)
        phase_view = {raw[14:0], 1'b0};
      else
        phase_view = raw;
    end
  endfunction

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic load_controls(
      input logic [2:0] live_wave,
      input logic [1:0] live_mode,
      input logic live_alt,
      input logic live_wt,
      input logic [2:0] old_wave,
      input logic [1:0] old_mode,
      input logic old_alt,
      input logic [2:0] snd_id);
    begin
      action = LOAD_OSC_14;
      state_q = {1'b0, old_mode, 13'h1555};
      tick();
      action = LOAD_OSC_22;
      state_q = {1'b0, old_alt, 3'b101, old_wave, 8'h6d};
      tick();
      action = LOAD_PAR_1;
      state_q = {1'b0, snd_id, live_wt, live_wave, 8'h3c};
      tick();
      action = LOAD_PAR_2;
      state_q = {6'h2a, live_mode, live_alt, 7'h35};
      tick();
    end
  endtask

  task automatic expect_wave(
      input logic [6:0] expected_action,
      input logic [15:0] expected_phase,
      input logic [2:0] expected_wave,
      input logic expected_alt,
      input logic expected_secondary,
      input logic expected_ce,
      input logic expected_issue,
      input logic expected_take);
    begin
      action = expected_action;
      #1;
      if (wave_ce !== expected_ce || wave_issue !== expected_issue
          || wave_take !== expected_take || wave_phase !== expected_phase
          || wave_sel !== expected_wave || wave_alt !== expected_alt
          || wave_secondary !== expected_secondary)
        $fatal(1,
               "wave action=%h got ce/issue/take=%b/%b/%b ctx=%h/%0d/%b/%b expected=%b/%b/%b %h/%0d/%b/%b",
               action, wave_ce, wave_issue, wave_take, wave_phase, wave_sel,
               wave_alt, wave_secondary, expected_ce, expected_issue,
               expected_take, expected_phase, expected_wave, expected_alt,
               expected_secondary);
    end
  endtask

  task automatic prove_builtin_contexts;
    integer w, m;
    logic [2:0] old_wave;
    logic [1:0] old_mode;
    logic [15:0] w0_raw, w1_raw, w2_raw, w3_raw;
    begin
      for (w = 0; w < 8; w++) begin
        for (m = 0; m < 3; m++) begin
          old_wave = 3'((w + 3) & 7);
          old_mode = 2'((m + 1) % 3);
          load_controls(3'(w), 2'(m), w[0], 1'b0, old_wave, old_mode,
                        ~w[0], 3'((w + 5) & 7));
          w0_raw = 16'h8135 ^ {w[2:0], 13'd0}
                               ^ {10'd0, m[1:0], 4'd0};
          w1_raw = 16'hc2a7 ^ {6'd0, w[2:0], 7'd0}
                               ^ {11'd0, m[1:0], 3'd0};
          w2_raw = 16'h3749 ^ {5'd0, w[2:0], 8'd0}
                               ^ {9'd0, m[1:0], 5'd0};
          w3_raw = 16'hf18b ^ {7'd0, w[2:0], 6'd0}
                               ^ {12'd0, m[1:0], 2'd0};
          state_q = w0_raw;
          phase_w1_raw = {1'b1, w1_raw};
          phase_w2_raw = w2_raw;
          phase_w3_raw = {1'b1, w3_raw};

          expect_wave(CAP_W0, w0_raw, 3'(w), w[0], 1'b0,
                      1'b1, 1'b1, 1'b0);
          tick();
          expect_wave(CAP_W1, phase_view(w1_raw, 3'(w), 2'(m), 1'b0),
                      3'(w), w[0], 1'b1, 1'b1, 1'b1, 1'b0);
          tick();
          expect_wave(CAP_W2, w2_raw, old_wave, ~w[0], 1'b0,
                      1'b1, 1'b1, 1'b1);
          tick();
          expect_wave(CAP_W3, phase_view(w3_raw, old_wave, old_mode, 1'b0),
                      old_wave, ~w[0], 1'b1, 1'b1, 1'b1, 1'b1);
          tick();
          expect_wave(CAP_W4, state_q, 3'(w), w[0], 1'b0,
                      1'b1, 1'b0, 1'b1);
          tick();
          expect_wave(CAP_W5, state_q, 3'(w), w[0], 1'b0,
                      1'b0, 1'b0, 1'b1);
          tick();
          if (aram_req || aram_take)
            $fatal(1, "built-in context emitted ARAM traffic");
        end
      end
    end
  endtask

  task automatic prove_wavetable_contexts;
    logic [5:0] w0_index, w2_index;
    logic [15:0] w2_phase;
    begin
      load_controls(3'd0, 2'd2, 1'b1, 1'b1,
                    3'd5, 2'd2, 1'b0, 3'd6);
      state_q = 16'hfc35;
      phase_w1_raw = 17'h157a4;
      phase_w2_raw = 16'h92bc;
      phase_w3_raw = 17'h1d319;
      w0_index = state_q[15:10];
      w2_phase = phase_view(phase_w1_raw[15:0], 3'd0, 2'd2, 1'b1);
      w2_index = w2_phase[15:10];

      action = CAP_W0;
      #1;
      if (wave_ce || wave_issue || wave_take || !aram_req || aram_take
          || aram_id != 3'd6 || aram_index != w0_index || aram_adjacent)
        $fatal(1, "wavetable W0 context mismatch");
      tick();
      action = CAP_W1;
      #1;
      if (wave_ce || !aram_req || !aram_take || aram_index != w0_index
          || !aram_adjacent)
        $fatal(1, "wavetable W1 adjacent context mismatch");
      tick();
      action = CAP_W2;
      #1;
      if (wave_ce || !aram_req || !aram_take || aram_index != w2_index
          || aram_adjacent)
        $fatal(1, "wavetable W2 substituted index mismatch");
      tick();
      action = CAP_W3;
      #1;
      if (wave_ce || !aram_req || !aram_take || aram_index != w2_index
          || !aram_adjacent)
        $fatal(1, "wavetable W3 adjacent context mismatch");
      tick();
      action = CAP_W4;
      #1;
      if (wave_ce || aram_req || !aram_take)
        $fatal(1, "wavetable W4 drain mismatch");
      tick();

      play = 1'b0;
      action = CAP_W0;
      #1;
      if (aram_req || aram_take)
        $fatal(1, "inactive wavetable emitted ARAM traffic");
      play = 1'b1;
    end
  endtask

  task automatic prove_external_hold;
    logic [21:0] saved_context;
    begin
      load_controls(3'd2, 2'd2, 1'b1, 1'b0,
                    3'd6, 2'd1, 1'b0, 3'd3);
      state_q = 16'h8c21;
      phase_w1_raw = 17'h13375;
      phase_w2_raw = 16'h4752;
      phase_w3_raw = 17'h1a963;
      action = CAP_W0;
      tick();
      saved_context = {dut.phase_index_hold, dut.snd_id, dut.snd_wt,
                       dut.snd_wave, dut.snd_mode, dut.snd_alt,
                       dut.old_wave, dut.old_mode, dut.old_alt};
      hold = 1'b1;
      action = CAP_W1;
      state_q = 16'hffff;
      phase_w1_raw = 17'h1ffff;
      repeat (3) begin
        #1;
        if (wave_ce || wave_issue || wave_take || aram_req || aram_take)
          $fatal(1, "external hold emitted a service event");
        tick();
        if ({dut.phase_index_hold, dut.snd_id, dut.snd_wt,
             dut.snd_wave, dut.snd_mode, dut.snd_alt,
             dut.old_wave, dut.old_mode, dut.old_alt} !== saved_context)
          $fatal(1, "external hold changed core context");
      end
      hold = 1'b0;
      #1;
      if (!wave_issue || wave_phase !== 16'hfffe)
        $fatal(1, "held W1 did not resume from explicit context");
      tick();

      owner = 1'b1;
      action = CAP_W2;
      #1;
      if (wave_ce || wave_issue || wave_take || aram_req || aram_take)
        $fatal(1, "owner-one action reached owner-zero service");
      owner = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    active = 1'b1;
    hold = 1'b0;
    owner = 1'b0;
    play = 1'b1;
    action = 7'd0;
    state_q = 16'd0;
    phase_w1_raw = 17'd0;
    phase_w2_raw = 16'd0;
    phase_w3_raw = 17'd0;
    prove_builtin_contexts();
    prove_wavetable_contexts();
    prove_external_hold();
    $display("psg_execwave_core_tb: PASS (24 built-in contexts, explicit W0-W3, ARAM, hold)");
    $finish;
  end
endmodule
