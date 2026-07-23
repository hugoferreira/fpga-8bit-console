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

    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("%0d TEST(S) FAILED", errors);
    $finish;
  end
endmodule
