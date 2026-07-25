// Standalone PSG v2 testbench. Uploads a constructed PICO-8 audio RAM
// image through the CPU port, then checks: row timing against speed,
// loop and length-only conventions, slide/drop/fade/arpeggio effect
// trajectories (via hierarchical peeks at eff_inc/eff_vol), and music
// pattern flow (chaining, loop-back to loop-start, stop flag, $80).
//
// Run: verilator --binary --timing -j 4 rtl/psg_tb.sv rtl/psg.sv \
//        --top-module psg_tb && ./obj_dir/Vpsg_tb
`timescale 1ns/1ps

module psg_tb;
  // 32 system clocks per virtual sample keeps the sim quick while giving
  // the serialized datapath headroom (needs ~13)
  localparam CLKHZ = 32'd705_600;
  localparam CLKS_PER_TICK = 32 * 183;

  bit clk = 0;
  always #5 clk = ~clk;

  bit reset = 1;
  bit cs = 0, rw = 0;
  logic [7:0] addr = 0, di = 0;
  logic [7:0] dout, pcm;

  psg #(.CLK_HZ(CLKHZ)) dut(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di),
    .dout(dout), .pcm(pcm));

  // Delta-sigma modulator under test (driven directly from a ramp below)
  logic [7:0] ds_pcm = 0;
  logic       ds_out;
  dsigma dsig(.clk(clk), .reset(reset), .pcm(ds_pcm), .out(ds_out));

  int errors = 0;

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

  // ---- test bank ------------------------------------------------------
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

  // measure pcm over nclk system clocks: peak |delta| and change count
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

  // peak |pcm-128| over nclk clocks (post-note echo detection)
  task peak_dev(input int nclk, output int pk);
    int d;
    pk = 0;
    repeat (nclk) begin
      @(posedge clk);
      d = int'(pcm) - 128; if (d < 0) d = -d;
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

  initial begin
    for (int i = 0; i < 4608; i++) img[i] = 0;

    // sfx0: loop test - speed 4, rows all audible, loop rows [2,6)
    for (int r = 0; r < 32; r++) set_note(0, r, 30 + r % 8, 0, 7, 0);
    set_meta(0, 4, 2, 6);
    // sfx1: length-only - speed 2, 8 rows
    for (int r = 0; r < 32; r++) set_note(1, r, 40, 3, 7, 0);
    set_meta(1, 2, 8, 0);
    // sfx2: slide from pitch 21 to 33 across row 1 (speed 8)
    set_note(2, 0, 21, 0, 7, 0);
    set_note(2, 1, 33, 0, 7, 1);
    set_meta(2, 8, 0, 0);
    // sfx3: drop on row 0 (speed 16)
    set_note(3, 0, 33, 0, 7, 3);
    set_meta(3, 16, 0, 0);
    // sfx4: fade in row 0, fade out row 1 (speed 8)
    set_note(4, 0, 33, 0, 7, 4);
    set_note(4, 1, 33, 0, 7, 5);
    set_meta(4, 8, 0, 0);
    // sfx5: arpeggio group 10/20/30/40 (speed 16, fx6 -> 4-tick steps)
    set_note(5, 0, 10, 0, 7, 6);
    set_note(5, 1, 20, 0, 7, 0);
    set_note(5, 2, 30, 0, 7, 0);
    set_note(5, 3, 40, 0, 7, 0);
    set_meta(5, 16, 0, 0);
    // sfx6: music pacer - one row per tick, full 32 rows
    for (int r = 0; r < 32; r++) set_note(6, r, 33, 0, 7, 0);
    set_meta(6, 1, 0, 0);

    // --- filter-test bank -------------------------------------------
    // sfx7/8: white noise, no filter vs dampen level 2 (the low-pass
    // removes the high-frequency content, shrinking sample-to-sample steps)
    for (int r = 0; r < 32; r++) set_note(7, r, 30, 6, 7, 0);
    set_meta(7, 16, 0, 0); set_filter(7, 2);            // noiz (white)
    for (int r = 0; r < 32; r++) set_note(8, r, 30, 6, 7, 0);
    set_meta(8, 16, 0, 0); set_filter(8, 146);          // noiz + damp 2
    // sfx9: triangle with detune level 1
    for (int r = 0; r < 32; r++) set_note(9, r, 40, 0, 7, 0);
    set_meta(9, 16, 0, 0); set_filter(9, 8);            // detune 1
    // sfx10/11/12: noise white / pitched / brown
    for (int r = 0; r < 32; r++) set_note(10, r, 30, 6, 7, 0);
    set_meta(10, 16, 0, 0); set_filter(10, 2);          // noiz (white)
    for (int r = 0; r < 32; r++) set_note(11, r, 30, 6, 7, 0);
    set_meta(11, 16, 0, 0); set_filter(11, 0);          // pitched
    for (int r = 0; r < 32; r++) set_note(12, r, 30, 6, 7, 0);
    set_meta(12, 16, 0, 0); set_filter(12, 4);          // buzz (brown)
    // sfx13/14: short square with reverb 2 vs none
    set_note(13, 0, 40, 3, 7, 0);
    set_meta(13, 4, 1, 0); set_filter(13, 48);          // reverb 2, 1 row
    set_note(14, 0, 40, 3, 7, 0);
    set_meta(14, 4, 1, 0); set_filter(14, 0);           // no reverb, 1 row

    // patterns: 0 (loop start) -> 1 (loop back) cycle; 2 = stop flag
    set_pat(0, 8'h06 | 8'h80, 8'h41, 8'h42, 8'h43);
    set_pat(1, 8'h06, 8'h41 | 8'h80, 8'h42, 8'h43);
    set_pat(2, 8'h06, 8'h41, 8'h42 | 8'h80, 8'h43);

    // ---- reset and upload ------------------------------------------
    repeat (8) @(posedge clk);
    reset = 0;
    repeat (8) @(posedge clk);

    wr(8'h00, 8'h00);
    wr(8'h01, 8'h31);
    for (int i = 0; i < 4608; i++) wr(8'h02, img[i]);

    // ---- 1. row timing and looping ---------------------------------
    $display("[1] speed and loop rows");
    wr(8'h10, 8'd0);
    ticks(1);
    rd(8'h03, q);
    check(q[0] == 1, "channel 0 playing after trigger");
    nrows = 0;
    for (int i = 0; i < 64; i++) seen_rows[i] = -1;
    repeat (30) begin
      ticks(4);                       // one row per 4 ticks at speed 4
      rd(8'h10, q);
      seen_rows[nrows] = int'(q[4:0]);
      nrows++;
    end
    // after the first pass 0,1,2,3,4,5 the row must cycle 2..5 forever
    check(seen_rows[0] == 1 || seen_rows[0] == 2, "rows advance at speed");
    for (int i = 10; i < 30; i++)
      check(seen_rows[i] >= 2 && seen_rows[i] <= 5, "looped row in [2,6)");
    wr(8'h10, 8'h80);
    rd(8'h03, q);
    check(q[0] == 0, "channel 0 stops on $80");

    // ---- 2. length-only convention ---------------------------------
    $display("[2] length-only: 8 rows at speed 2");
    wr(8'h11, 8'd1);
    ticks(8 * 2 - 4);
    rd(8'h03, q);
    check(q[1] == 1, "still playing before row 8");
    ticks(8);
    rd(8'h03, q);
    check(q[1] == 0, "stopped after 8 rows");

    // ---- 3. slide --------------------------------------------------
    $display("[3] slide interpolates the phase increment");
    wr(8'h12, 8'd2);
    ticks(9);                          // into row 1 (fx1), early
    inc0 = dut.eff_inc[2];
    ticks(6);                          // near the end of row 1
    inc1 = dut.eff_inc[2];
    check(inc0 > 24'd120000 && inc0 < 24'd220000, "slide starts near f(21)");
    check(inc1 > inc0, "slide rises across the row");
    check(inc1 > 24'd280000, "slide approaches f(33)");
    wr(8'h12, 8'h80);

    // ---- 4. drop ---------------------------------------------------
    $display("[4] drop falls toward zero");
    wr(8'h13, 8'd3);
    ticks(2);
    inc0 = dut.eff_inc[3];
    ticks(12);
    inc1 = dut.eff_inc[3];
    check(inc0 > inc1, "drop decreases");
    check(inc1 < 24'd60000, "drop nearly silent-frequency by row end");
    wr(8'h13, 8'h80);

    // ---- 5. fades --------------------------------------------------
    $display("[5] fade in / fade out volume ramps");
    wr(8'h10, 8'd4);
    ticks(2);
    inc0 = {16'b0, dut.eff_vol[0]};
    ticks(5);
    inc1 = {16'b0, dut.eff_vol[0]};
    check(inc1 > inc0, "fade-in volume rises");
    ticks(3);                          // into row 1 (fade out)
    inc0 = {16'b0, dut.eff_vol[0]};
    ticks(5);
    inc1 = {16'b0, dut.eff_vol[0]};
    check(inc1 < inc0, "fade-out volume falls");
    wr(8'h10, 8'h80);

    // ---- 6. arpeggio -----------------------------------------------
    $display("[6] arpeggio cycles the row group");
    wr(8'h11, 8'd5);
    begin
      int hits[0:3];
      for (int i = 0; i < 4; i++) hits[i] = 0;
      for (int i = 0; i < 15; i++) begin
        ticks(1);
        case (dut.eff_inc[1])
          dut.pinc[10]: hits[0]++;
          dut.pinc[20]: hits[1]++;
          dut.pinc[30]: hits[2]++;
          dut.pinc[40]: hits[3]++;
          default: ;
        endcase
      end
      check(hits[0] > 0 && hits[1] > 0 && hits[2] > 0 && hits[3] > 0,
            "all four group pitches sounded within 15 ticks");
    end
    wr(8'h11, 8'h80);

    // ---- 7. music flow ---------------------------------------------
    $display("[7] music: chain, loop-back, stop flag");
    wr(8'h20, 8'd0);
    ticks(2);
    rd(8'h03, q);
    check(q[7] == 1, "music playing");
    check(q[0] == 1, "music launched sfx on channel 0");
    ticks(34);                          // pattern 0 is 32 ticks long
    rd(8'h20, q);
    check(q[5:0] == 6'd1, "advanced to pattern 1");
    ticks(34);
    rd(8'h20, q);
    check(q[5:0] == 6'd0, "looped back to the loop-start pattern");
    wr(8'h20, 8'h80);
    rd(8'h03, q);
    check(q[7] == 0, "music stops on $80");
    check(q[0] == 0, "music channel silenced on stop");

    wr(8'h20, 8'd2);
    ticks(2);
    rd(8'h03, q);
    check(q[7] == 1, "stop-flag pattern starts");
    ticks(40);
    rd(8'h03, q);
    check(q[7] == 0, "music halts after stop-flag pattern");

    // ---- 8. mix output sanity --------------------------------------
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

    // ---- 9. DAMPEN --------------------------------------------------
    $display("[9] dampen low-passes white noise");
    begin
      int md0, md2, ch0, ch2;
      wr(8'h10, 8'd7);                    // clean white noise
      ticks(2);
      measure(8000, md0, ch0);
      wr(8'h10, 8'h80);
      wr(8'h10, 8'd8);                    // damp-2 white noise
      ticks(2);
      measure(8000, md2, ch2);
      wr(8'h10, 8'h80);
      check(md0 > 0, "clean noise has large steps");
      check(md2 * 2 < md0, "dampen shrinks the peak sample step");
    end

    // ---- 10. DETUNE -------------------------------------------------
    $display("[10] detune runs a second voice");
    wr(8'h11, 8'd9);
    ticks(2);
    check(dut.phase2[1] != 0, "detuned second accumulator advances");
    wr(8'h11, 8'h80);

    // ---- 11. NOISE MODES --------------------------------------------
    $display("[11] noise modes differ (white/pitched/brown)");
    begin
      int mdw, mdp, mdb, cw, cp, cb;
      wr(8'h10, 8'd10); ticks(2); measure(8000, mdw, cw); wr(8'h10, 8'h80);
      wr(8'h10, 8'd11); ticks(2); measure(8000, mdp, cp); wr(8'h10, 8'h80);
      wr(8'h10, 8'd12); ticks(2); measure(8000, mdb, cb); wr(8'h10, 8'h80);
      check(cw > cp, "white noise updates faster than pitched");
      check(mdb < mdw, "brown noise has smaller sample steps than white");
    end

    // ---- 12. REVERB -------------------------------------------------
    $display("[12] reverb leaves an echo tail after note-off");
    begin
      int tail_rev, tail_dry;
      wr(8'h12, 8'd14);                   // dry short square
      ticks(2);
      wr(8'h12, 8'h80);                   // stop; measure the silence after
      peak_dev(9000, tail_dry);
      wr(8'h12, 8'd13);                   // reverb-2 short square
      ticks(2);
      wr(8'h12, 8'h80);
      peak_dev(9000, tail_rev);
      check(tail_rev > tail_dry + 2, "reverb tail outlasts the dry note");
    end

    // ---- 13. DELTA-SIGMA OUTPUT -------------------------------------
    $display("[13] delta-sigma density tracks a PCM ramp");
    begin
      int lo_hi, hi_hi;
      lo_hi = 0; hi_hi = 0;
      ds_pcm = 8'd32;
      repeat (2000) begin @(posedge clk); if (ds_out) lo_hi++; end
      ds_pcm = 8'd224;
      repeat (2000) begin @(posedge clk); if (ds_out) hi_hi++; end
      check(hi_hi > lo_hi, "higher PCM -> denser 1s");
      check(lo_hi > 100 && hi_hi < 1900, "density is proportional, not saturated");
    end

    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("%0d TEST(S) FAILED", errors);
    $finish;
  end
endmodule
