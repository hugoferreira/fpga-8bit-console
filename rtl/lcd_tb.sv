`timescale 1ns/1ps

// Bench for rtl/lcd.sv - the serial panel driver every board top instantiates
// and which, until 2026-08-07, nothing tested at all.
//
// WHY IT EXISTS. `top_simulator.sv` does NOT include lcd.sv - only the three
// board tops do - so `make shot`, `make ppu-check` and the PSG gates all run
// with this module absent. That blind spot hid a real defect: the ROM lookup
// that walks the ST7789 initialisation sequence was written
//
//     logic [8:0] command = rom[counter];
//
// which is a variable declaration INITIALISER (evaluated once, at time zero),
// not a continuous assignment. Measured on the whole Tang Primer 20K design,
// the two spellings synthesise differently - 8,673 LUT4 against 8,915 - a
// ~242-cell gap that is about the size of the 16x9 ROM mux that never got
// built. GowinSynthesis rejects the construct outright. This bench asserts the
// property that spelling breaks: that the sixteen bytes after the reset wait
// are the sixteen DISTINCT entries of setup_st7789_565.hex, in order.
//
// It decodes the actual pins - sda/scl/cs/rs - rather than peeking at internal
// state, so it is a protocol check and not a mirror of the implementation.
//
//   make test-lcd
//
// It must run with build/ as the working directory: lcd.sv loads its command
// ROM with a bare $readmemh("setup_st7789_565.hex", ...), and iverilog resolves
// that relative to cwd rather than through -I. The Makefile stages the hex
// there. Writes lcd_frame.ppm and lcd_frame2.ppm - two decoded frames, so the
// geometry can be looked at rather than trusted.
//
// WHY TWO FRAMES. The bench used to decode exactly one, which made per-frame
// drift structurally invisible: a driver that emits 153601 bytes for frame 1
// and 153602 for every frame after it passes a single-frame decode with every
// pixel exact, and scrolls upward one row per frame on hardware. The frame
// boundary, the byte-per-line count and the vsync pulse are now asserted
// explicitly rather than inferred from a contiguous decode.
// The SPI divider is a parameter, not a constant, because the bench ran at the
// module default (2) while the boards shipped 3. Blanking is timed in `clk`
// cycles and byte transmission in SCL phases, so the two interact and a bench
// that only ever exercises one divider is not testing the built design.
//   iverilog -Plcd_tb.SPI_HALF=3 ...
module lcd_tb #(parameter int SPI_HALF = 2, parameter int RGBSIZE = 16);
  localparam int W = 320, H = 240;
  localparam int INIT_N = 16;          // entries in the setup ROM
  localparam int RESET_WAIT = 3;       // byte-times; the panel wants 65535
  // The pixel group, as rtl/lcd.sv defines it: RGB565 is one pixel in two
  // bytes, RGB444 two pixels in three. Everything downstream - line length,
  // frame length, the pixel decode - is derived from it, so the bench cannot
  // silently keep checking the old geometry.
  localparam int GRP_BYTES = (RGBSIZE == 12) ? 3 : 2;
  localparam int GRP_PIX   = (RGBSIZE == 12) ? 2 : 1;
  localparam int LINEBYTES  = (W / GRP_PIX) * GRP_BYTES;
  localparam int FRAMEBYTES = LINEBYTES * H;
  // pllclk:masterclk, rtl/pll_gowin.v DYN_SDIV_SEL. vsync crosses into the
  // masterclk domain, so a pulse narrower than this can be missed entirely -
  // which is how a rendered but completely static picture happened.
  localparam int MASTER_DIV = 8;
  // `dataout` is registered, so the serialiser shifts out its reset value once
  // before the first real byte: the panel sees a leading rs=0 0x00. That is a
  // NOP to an ST7789 and harmless, but it is on the wire and the bench has to
  // account for it rather than pretend the stream starts at the reset run.
  localparam int LEAD = 1;

  logic clk = 0, reset = 1;
  logic [RGBSIZE-1:0] rgb;
  wire sda, scl, cs, rs, vsync, hsync;
  wire [$clog2(H)-1:0] vpos;
  wire [$clog2(W)-1:0] hpos;

  lcd #(.WIDTH(W), .HEIGHT(H), .RGBSIZE(RGBSIZE), .RESET_WAIT(RESET_WAIT),
        .INIT_FILE((RGBSIZE == 12) ? "setup_st7789_444.hex"
                                   : "setup_st7789_565.hex"),
        .SPI_HALF(SPI_HALF)) dut(
    .clk, .reset, .rgb, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos, .hpos);

  always #5 clk = ~clk;

  // The test pattern the panel should receive: a horizontal red ramp, a
  // vertical green ramp, and a blue square in one corner, so a wrong stride, a
  // swapped byte order or a transposed axis all look obviously wrong.
  function automatic logic [RGBSIZE-1:0] pattern(input int x, input int y);
    logic [4:0] r5; logic [5:0] g6; logic [4:0] b5;
    logic [3:0] r4, g4, b4;
    begin
      if (RGBSIZE == 12) begin
        r4 = 4'((x * 15) / (W - 1));
        g4 = 4'((y * 15) / (H - 1));
        b4 = (x < W/4 && y < H/4) ? 4'd15 : 4'd0;
        pattern = {r4, g4, b4};
      end else begin
        r5 = 5'((x * 31) / (W - 1));
        g6 = 6'((y * 63) / (H - 1));
        b5 = (x < W/4 && y < H/4) ? 5'd31 : 5'd0;
        pattern = {r5, g6, b5};
      end
    end
  endfunction

  assign rgb = pattern(int'(hpos), int'(vpos));

  // ---- SPI receiver ---------------------------------------------------
  // SCL_MODE=0, so scl idles high between bytes and follows ~cin while a byte
  // is shifting. The panel samples on the rising edge; so does this.
  logic [7:0] shreg;
  int         nbits = 0;
  logic [8:0] stream [0:400000];       // {rs, byte}, in wire order
  int         bcycle [0:400000];       // clk cycle each byte completed on
  int         nbytes = 0;

  // Free-running clock counter. Line boundaries carry no marker on the wire -
  // the driver simply stops shifting for the blanking interval - so the only
  // way to measure bytes-per-line from the pins is to time the gaps.
  int cycles = 0;
  always @(posedge clk) cycles <= cycles + 1;

  // Pull pixel (x,y) back out of the packed byte stream. RGB444 puts two
  // pixels in three bytes as [R1G1][B1R2][G2B2], so which nibbles a pixel
  // occupies depends on whether its index is even or odd - the reason the
  // driver needed a modulo-3 phase and the reason this cannot be a shift.
  function automatic logic [RGBSIZE-1:0] unpack(input int fbase, input int x,
                                                input int y);
    int idx, grp, b0;
    begin
      idx = y * W + x;
      if (RGBSIZE == 12) begin
        grp = idx / 2;
        b0  = fbase + grp * 3;
        if (idx % 2 == 0)
          unpack = {stream[b0][7:0], stream[b0+1][7:4]};
        else
          unpack = {stream[b0+1][3:0], stream[b0+2][7:0]};
      end else begin
        b0 = fbase + idx * 2;
        unpack = {stream[b0][7:0], stream[b0+1][7:0]};
      end
    end
  endfunction

  // Expand a decoded pixel to 8:8:8 for the PPM.
  function automatic logic [23:0] to888(input logic [RGBSIZE-1:0] p);
    begin
      if (RGBSIZE == 12)
        to888 = {p[11:8], p[11:8], p[7:4], p[7:4], p[3:0], p[3:0]};
      else
        to888 = {p[15:11], p[15:13], p[10:5], p[10:9], p[4:0], p[4:2]};
    end
  endfunction

  // CS MUST STAY LOW. This is the property whose violation produced a white
  // panel on hardware while every other subsystem worked: the old driver used
  // `cs` as its state-machine clock, so it deasserted once per byte, and both
  // candidate controllers reset their serial interface on a high CSX. The
  // decoder below reads `!cs`, so without this assertion a regression would
  // simply make the bench see no bytes and time out with a confusing message.
  int cs_high = 0;
  always @(posedge scl) if (!reset && cs) cs_high = cs_high + 1;

  always @(posedge scl) begin
    if (!reset && !cs) begin
      shreg = {shreg[6:0], sda};
      nbits = nbits + 1;
      if (nbits == 8) begin
        if (nbytes < 400000) begin
          stream[nbytes] = {rs, shreg};
          bcycle[nbytes] = cycles;
        end
        nbytes = nbytes + 1;
        nbits  = 0;
      end
    end
  end

  // ---- vsync monitor ---------------------------------------------------
  // vsync is what ticks the console's game loop. It is sampled in the masterclk
  // domain, so both properties matter: exactly one pulse per frame (a driver
  // that never asserts it renders a correct but frozen picture, which is what
  // happened when the frame stopped passing through start_frame), and a pulse
  // at least one masterclk wide or the sampling edge can fall outside it.
  localparam int VS_MAX = 64;
  int vs_byte  [0:VS_MAX-1];           // bytes received when the pulse began
  int vs_start [0:VS_MAX-1];
  int vs_width [0:VS_MAX-1];
  int nvs = 0;

  always @(posedge vsync) if (!reset) begin
    if (nvs < VS_MAX) begin
      vs_byte[nvs]  = nbytes;
      vs_start[nvs] = cycles;
      vs_width[nvs] = 0;               // still high; overwritten on the falling edge
    end
    nvs = nvs + 1;
  end
  always @(negedge vsync) if (!reset && nvs > 0 && nvs <= VS_MAX)
    vs_width[nvs-1] = cycles - vs_start[nvs-1];

  // ---- expected initialisation ----------------------------------------
  logic [8:0] rom [0:INIT_N-1];
  initial
    if (RGBSIZE == 12) $readmemh("setup_st7789_444.hex", rom);
    else               $readmemh("setup_st7789_565.hex", rom);

  int i, k, base, px, x, y, fd, errors;
  int fr [0:2];                        // stream index of each frame's RAMWR
  logic [RGBSIZE-1:0] pix;
  logic [8:0] distinct [0:INIT_N-1];
  int ndistinct;

  // Decode a frame to a PPM and assert every pixel against the pattern the DUT
  // was shown. A constant offset, a per-row drift and a straddled pixel all look
  // different in the reported coordinates, which is what makes this a diagnosis
  // rather than a pass/fail.
  task automatic verify_frame(input int fbase, input int fnum, input string ppm);
    int bad, firstx, firsty, ffd, xx, yy;
    logic [RGBSIZE-1:0] ppix;
    logic [23:0] rgb888;
    begin
      bad = 0; firstx = -1; firsty = -1;
      ffd = $fopen(ppm, "wb");
      $fwrite(ffd, "P6\n%0d %0d\n255\n", W, H);
      for (yy = 0; yy < H; yy = yy + 1)
        for (xx = 0; xx < W; xx = xx + 1) begin
          ppix   = unpack(fbase, xx, yy);
          rgb888 = to888(ppix);
          $fwrite(ffd, "%c%c%c", rgb888[23:16], rgb888[15:8], rgb888[7:0]);
          if (ppix !== pattern(xx, yy)) begin
            if (bad < 6)
              $display("  frame %0d pixel (%0d,%0d) is %04x, pattern says %04x",
                       fnum, xx, yy, ppix, pattern(xx, yy));
            if (bad == 0) begin firstx = xx; firsty = yy; end
            bad = bad + 1;
          end
        end
      $fclose(ffd);
      if (bad != 0) begin
        $display("FAIL: frame %0d: %0d of %0d pixels wrong; first at (%0d,%0d)",
                 fnum, bad, W * H, firstx, firsty);
        errors = errors + 1;
      end
    end
  endtask

  // Bytes-per-line, measured from the pins. Within a line the driver shifts
  // back-to-back; at a line boundary it stops for the blanking interval. Split
  // the stream on those gaps and count what lands between them, so a line that
  // carries 641 bytes is named by its row number instead of showing up as a
  // sheared image several hundred rows later.
  task automatic check_lines(input int fstart, input int fend, input int fnum);
    int i, gap, nominal, thresh, run_data, run_cmd, run_start, nlines, bad;
    begin
      // The byte period, taken from inside a line rather than assumed from
      // SPI_HALF, so the check does not encode the divider it is measuring.
      nominal = bcycle[fstart + 2] - bcycle[fstart + 1];
      thresh  = nominal + nominal / 2;
      nlines = 0; bad = 0;
      run_data = 0; run_cmd = 0; run_start = fstart;
      for (i = fstart; i < fend; i = i + 1) begin
        gap = (i > fstart) ? (bcycle[i] - bcycle[i-1]) : 0;
        if (gap > thresh) begin
          nlines = nlines + 1;
          if ((run_data != LINEBYTES || run_cmd > 1) && bad < 6) begin
            $display("  frame %0d line %0d: %0d data bytes + %0d command bytes, expected %0d + <=1",
                     fnum, nlines - 1, run_data, run_cmd, LINEBYTES);
            bad = bad + 1;
          end
          run_data = 0; run_cmd = 0; run_start = i;
        end
        if (stream[i][8]) run_data = run_data + 1;
        else begin
          run_cmd = run_cmd + 1;
          // A command byte anywhere but at a line start means the driver
          // dropped rs mid-line; the panel would take a pixel byte as an opcode.
          if (i != run_start && bad < 6) begin
            $display("  frame %0d: command byte %02x at stream index %0d, mid-line",
                     fnum, stream[i][7:0], i);
            bad = bad + 1;
          end
        end
      end
      nlines = nlines + 1;                        // the run that ends at fend
      if (run_data != LINEBYTES || run_cmd > 1) begin
        $display("  frame %0d line %0d: %0d data bytes + %0d command bytes, expected %0d + <=1",
                 fnum, nlines - 1, run_data, run_cmd, LINEBYTES);
        bad = bad + 1;
      end
      if (nlines != H) begin
        $display("FAIL: frame %0d has %0d lines, expected %0d", fnum, nlines, H);
        errors = errors + 1;
      end
      if (bad != 0) begin
        $display("FAIL: frame %0d: %0d malformed line(s)", fnum, bad);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    #100 reset = 0;

    // Wait for TWO full frames plus the byte that starts the third: the reset
    // run, the 16 init bytes, then RAMWR + W*H*2 pixel bytes, twice. The margin
    // absorbs a driver that emits a few bytes too many per frame - which is
    // exactly the defect this waits long enough to see.
    wait (nbytes >= LEAD + (RESET_WAIT + 1) + INIT_N + 2 * (1 + FRAMEBYTES) + 64);
    #1;

    errors = 0;

    // --- 0. CS was asserted for every clock of the whole stream ------------
    if (cs_high != 0) begin
      $display("FAIL: CS went high during %0d SCL edges - it must stay low for the whole session", cs_high);
      errors = errors + 1;
    end

    // --- 1. the reset run: 0x11 (SLPOUT) as a command, RESET_WAIT+1 times ---
    for (i = 0; i <= RESET_WAIT; i = i + 1)
      if (stream[LEAD + i] !== 9'h011) begin
        $display("FAIL: reset byte %0d is rs=%b %02x, expected rs=0 11",
                 i, stream[LEAD+i][8], stream[LEAD+i][7:0]);
        errors = errors + 1;
      end

    // --- 2. THE REGRESSION: 16 init entries, in order, matching the ROM ---
    base = LEAD + RESET_WAIT + 1;
    for (i = 0; i < INIT_N; i = i + 1)
      if (stream[base + i] !== rom[i]) begin
        $display("FAIL: init[%0d] is rs=%b %02x, expected rs=%b %02x",
                 i, stream[base+i][8], stream[base+i][7:0],
                 rom[i][8], rom[i][7:0]);
        errors = errors + 1;
      end

    // A constant `command` would send ONE value sixteen times and still pass a
    // sloppy check, so assert the sequence actually varies.
    ndistinct = 0;
    for (i = 0; i < INIT_N; i = i + 1) begin
      distinct[ndistinct] = stream[base + i];
      for (int j = 0; j < ndistinct; j = j + 1)
        if (distinct[j] === stream[base + i]) ndistinct = ndistinct - 1;
      ndistinct = ndistinct + 1;
    end
    if (ndistinct < 8) begin
      $display("FAIL: only %0d distinct init bytes - ROM lookup not a function of counter", ndistinct);
      errors = errors + 1;
    end

    // --- 3. RAMWR, then the pixels ---
    fr[0] = LEAD + RESET_WAIT + 1 + INIT_N;
    if (stream[fr[0]] !== 9'h02C) begin
      $display("FAIL: expected RAMWR (rs=0 2C), got rs=%b %02x",
               stream[fr[0]][8], stream[fr[0]][7:0]);
      errors = errors + 1;
    end

    // --- 4. FRAME BOUNDARIES ---------------------------------------------
    // Every byte after RAMWR is pixel data until the next RAMWR, so the next
    // command byte on the wire IS the frame boundary. Locating it by scanning
    // rather than by counting is what makes the count an assertion: a frame
    // that carries one byte too many puts the boundary one index late and the
    // panel's address pointer one byte on, which reads as the picture scrolling
    // up a row per frame. A single-frame decode cannot see this at all.
    for (k = 1; k <= 2; k = k + 1) begin
      fr[k] = -1;
      for (i = fr[k-1] + 1; i < nbytes && fr[k] < 0; i = i + 1)
        if (stream[i][8] === 1'b0) fr[k] = i;
      if (fr[k] < 0) begin
        $display("FAIL: no command byte after frame %0d - frame never restarted within %0d bytes",
                 k - 1, nbytes);
        errors = errors + 1;
      end else begin
        if (stream[fr[k]][7:0] !== 8'h2C) begin
          $display("FAIL: frame %0d boundary byte is rs=0 %02x, expected RAMWR 2C",
                   k, stream[fr[k]][7:0]);
          errors = errors + 1;
        end
        if (fr[k] - fr[k-1] != FRAMEBYTES + 1) begin
          $display("FAIL: frame %0d is %0d bytes (RAMWR + %0d data), expected %0d + %0d",
                   k - 1, fr[k] - fr[k-1], fr[k] - fr[k-1] - 1, 1, FRAMEBYTES);
          errors = errors + 1;
        end
      end
    end

    // --- 5. decode both frames and assert every pixel ---------------------
    verify_frame(fr[0] + 1, 0, "lcd_frame.ppm");
    if (fr[1] > 0) verify_frame(fr[1] + 1, 1, "lcd_frame2.ppm");

    // --- 6. bytes per line, measured from the gaps ------------------------
    if (fr[1] > 0) check_lines(fr[0], fr[1], 0);
    if (fr[2] > 0) check_lines(fr[1], fr[2], 1);

    // --- 7. vsync ---------------------------------------------------------
    // One pulse per frame, in the trailing blank, at least one masterclk wide.
    begin
      int nin0, nin1;
      nin0 = 0; nin1 = 0;
      for (i = 0; i < nvs && i < VS_MAX; i = i + 1) begin
        if (vs_byte[i] > fr[0] && fr[1] > 0 && vs_byte[i] <= fr[1]) nin0 = nin0 + 1;
        if (fr[1] > 0 && vs_byte[i] > fr[1] && fr[2] > 0 && vs_byte[i] <= fr[2]) nin1 = nin1 + 1;
        if (vs_width[i] != 0 && vs_width[i] < MASTER_DIV) begin
          $display("FAIL: vsync pulse %0d is %0d clk wide, masterclk samples every %0d",
                   i, vs_width[i], MASTER_DIV);
          errors = errors + 1;
        end
      end
      if (nvs == 0) begin
        $display("FAIL: vsync never asserted in %0d bytes - the console's game loop would never tick", nbytes);
        errors = errors + 1;
      end
      if (fr[1] > 0 && nin0 != 1) begin
        $display("FAIL: %0d vsync pulses in frame 0, expected 1", nin0);
        errors = errors + 1;
      end
      if (fr[2] > 0 && nin1 != 1) begin
        $display("FAIL: %0d vsync pulses in frame 1, expected 1", nin1);
        errors = errors + 1;
      end
    end

    if (errors) begin
      $display("FAIL: %0d error(s)", errors);
      $fatal;
    end
    $display("PASS: RGB%0d SPI_HALF=%0d, %0d distinct init bytes in ROM order, RAMWR, 2 x %0dx%0d frames of exactly %0d bytes, %0d lines of %0d, %0d vsync pulses %0d clk wide -> build/lcd_frame{,2}.ppm",
             RGBSIZE, SPI_HALF, ndistinct, W, H, FRAMEBYTES, H, LINEBYTES, nvs,
             vs_width[0]);
    $finish;
  end

  initial begin
    #500000000;
    $display("FAIL: timed out after %0d bytes", nbytes);
    $fatal;
  end
endmodule
