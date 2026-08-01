// Functional PSG regression.
//
// Builds synthetic PICO-8 audio images and checks timing, loops, effects,
// music flow, filters, noise, reverb, trigger parameters, custom instruments,
// wavetables, foreground/music coexistence, and worst-case scheduling.
//
// Build command:
//   command: verilator --binary --timing -j 4 -Irtl rtl/psg_tb.sv rtl/psg.sv \
//     rtl/dsigma.sv --top-module psg_tb

`timescale 1ns/1ps

module psg_tb;

  localparam CLKHZ = 32'd18_750_000;
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

  // Functional DUT and independently driven delta-sigma smoke-test DUT.
  psg #(.CLK_HZ(CLKHZ), .MULTIPUMP(1)) dut(
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

  // Deadline checks count PSG clocks, independent of host simulation speed.
  always @(negedge clk) begin
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
          else begin
            $display("  FAIL: tick pre-run missed its boundary from an idle walk");
            errors++;
          end
          tick_job_active = 0;
        end
      end
    end
  end

  // Bus helpers. Writes are separated by an idle cycle, matching the top-level
  // write-edge detector's interface contract.
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

  // Native $3100-$42ff audio-image construction helpers.
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

  // Check messages below are the authoritative test inventory.
  initial begin
    for (int i = 0; i < 4608; i++) img[i] = 0;

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

    // Extend the image with API, instrument, wavetable, and slot-pair cases.
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

    $display("  synthesis deadline: worst %0d / %0d clocks (smoke test - the",
             max_sample_job_clocks, CLKHZ / 22050);
    $display("    fixed schedule also reserves 272 sequencer clocks/sample;");
    $display("    /6 supplies 850 clocks: 530 walk + 272 sequencer credits,");
    $display("    leaving 48 clocks of interval margin)");
    check(max_sample_job_clocks > 0 && max_sample_job_clocks < CLKHZ / 22050,
          "all slot and mix work completes before the next sample");
    $display("  tick pre-run: worst %0d / %0d clocks after pre_tick, %0d spare, %0d late flips",
             max_tick_job_clocks, tick_window,
             tick_window - max_tick_job_clocks, late_flips);
    check(max_tick_job_clocks > 0,
          "each tick evaluation stages its bank before the boundary");
    check(late_flips == 0,
          "no boundary flip was delayed by a colliding trigger pass");

    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("%0d TEST(S) FAILED", errors);
    $finish;
  end
endmodule
