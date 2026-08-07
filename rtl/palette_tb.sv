`timescale 1ns/1ps

// Bench for the colour ROM, and specifically for the join between a palette
// FILE and the RGB width it is read into.
//
// WHY IT EXISTS. `palette` reads its file with $readmemb into RGB-bit words.
// Given a file whose words are WIDER than RGB, $readmemb keeps the LOW bits and
// reports it as a warning at most - iverilog says "Excess binary digits", yosys
// and GowinSynthesis say nothing that survives a build log. The result is a
// palette that is fully populated, passes every utilisation and timing gate,
// and is wrong in a way that looks like a colour-space fault.
//
// That is what shipped. chip.sv hardcoded the 24-bit palette888.bin into the
// palette instance while both Tang tops parameterised the design for RGB565, so
// the FILE parameter they passed was dead and every colour on the panel was the
// low 16 bits of a 24-bit word, re-read as 5:6:5:
//
//   PICO-8  1 dark blue (29,43,83)    -> (40,104,152)  blue
//   PICO-8 14 pink      (255,119,168) -> (112,244,64)  green
//   PICO-8  7 white     (255,241,232) -> (240,60,64)   red
//
// On hardware that reads as inverted channels or a byte-order bug, and it is
// neither. `make shot` could not see it: top_simulator.sv builds the chip at
// RED=GREEN=BLUE=8, the one width at which the hardcoded file was correct.
//
// So this bench does NOT test `palette` in isolation - that would have passed
// throughout. It elaborates `chip` at the width the BOARDS build it and reads
// the ROM the build actually loaded, then checks it renders the same colours as
// the 24-bit reference the simulator is judged against.
//
//   make test-palette
//
// Run with the repo root as the working directory; the $readmemb paths are
// "./rtl/..." as everywhere else in chip.sv.
module palette_tb;
  localparam int RED = 5, GREEN = 6, BLUE = 5;

  // The 8-bit reference. `make shot` renders through exactly these values, so
  // build/shot.ppm is the picture the panel is being held to.
  logic [23:0] ref888 [0:15];
  initial $readmemb("./rtl/palette888.bin", ref888);

  // The console, built as rtl/top_tangprimer20k.sv and rtl/top_tangnano20k.sv
  // build it. Nothing is clocked: the palette ROM is populated by $readmemb at
  // time zero, and the property under test is its contents.
  bit clk = 0, reset = 1;
  logic [RED+GREEN+BLUE-1:0] rgb;
  logic signed [15:0] audio;
  logic [63:0] psg_dbg;

  /* verilator lint_off PINCONNECTEMPTY */
  chip #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .RAM_ADDR_BITS(16),
         .PSG_DBG(0), .REVERB(0)) dut(
    .clk, .cpuclk(clk), .psgclk(clk), .psgfastclk(clk), .reset,
    .vsync(1'b0), .hsync(1'b0), .vpos(7'd0), .hpos(8'd0), .buttons(8'd0),
    .rgb, .audio, .psg_dbg());
  /* verilator lint_on PINCONNECTEMPTY */

  // Expand an n-bit channel to 8 bits by bit replication, the same way the LCD
  // bench and every RGB565 display do it, so the comparison is in the space the
  // eye sees rather than in raw codes.
  function automatic int exp5(input logic [4:0] v);
    exp5 = int'({v, v[4:2]});
  endfunction
  function automatic int exp6(input logic [5:0] v);
    exp6 = int'({v, v[5:4]});
  endfunction

  int i, errors, dr, dg, db;
  logic [RED+GREEN+BLUE-1:0] w;

  // One RGB565 step is 8 in R and B and 4 in G. palette565.bin is rounded, not
  // truncated, from the 888 reference, so allow one step in either direction
  // and no more: two steps is no longer quantisation, it is a different colour.
  localparam int TOL_R = 8, TOL_G = 4, TOL_B = 8;

  initial begin
    errors = 0;
    #1;

    for (i = 0; i < 16; i = i + 1) begin
      w  = dut.g_ppu.pal_sprite.palette[i];
      dr = exp5(w[15:11]) - int'(ref888[i][23:16]);
      dg = exp6(w[10:5])  - int'(ref888[i][15:8]);
      db = exp5(w[4:0])   - int'(ref888[i][7:0]);
      if (dr < 0) dr = -dr;
      if (dg < 0) dg = -dg;
      if (db < 0) db = -db;
      if (dr > TOL_R || dg > TOL_G || db > TOL_B) begin
        $display("FAIL: colour %0d is (%0d,%0d,%0d), reference is (%0d,%0d,%0d)",
                 i, exp5(w[15:11]), exp6(w[10:5]), exp5(w[4:0]),
                 ref888[i][23:16], ref888[i][15:8], ref888[i][7:0]);
        errors = errors + 1;
      end
    end

    // Two colours are called out by name because they are the ones a human
    // reads off a panel first, and because both are symmetric under the faults
    // that a wrong palette gets mistaken for. White stays white under channel
    // inversion, under an R<->B swap and under a byte swap; if white is not
    // white, none of those is the explanation.
    if (dut.g_ppu.pal_sprite.palette[7] !== {5'd31, 6'd60, 5'd28}) begin
      $display("FAIL: colour 7 must be white (31,60,28), got (%0d,%0d,%0d)",
               dut.g_ppu.pal_sprite.palette[7][15:11],
               dut.g_ppu.pal_sprite.palette[7][10:5],
               dut.g_ppu.pal_sprite.palette[7][4:0]);
      errors = errors + 1;
    end
    if (dut.g_ppu.pal_sprite.palette[0] !== '0) begin
      $display("FAIL: colour 0 must be black, got %04x",
               dut.g_ppu.pal_sprite.palette[0]);
      errors = errors + 1;
    end

    if (errors) begin
      $display("FAIL: %0d colour(s) wrong - the palette FILE does not match RGB=%0d",
               errors, RED + GREEN + BLUE);
      $fatal;
    end
    $display("PASS: chip at RGB%0d%0d%0d loads a palette matching palette888.bin within one quantisation step, white is white",
             RED, GREEN, BLUE);
    $finish;
  end
endmodule
