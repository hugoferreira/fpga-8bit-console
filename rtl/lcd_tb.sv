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
// there. Writes lcd_frame.ppm - one decoded frame, so the geometry can be
// looked at rather than trusted.
module lcd_tb;
  localparam int W = 320, H = 240;
  localparam int INIT_N = 16;          // entries in setup_st7789_565.hex
  localparam int RESET_WAIT = 3;       // byte-times; the panel wants 65535
  // `dataout` is registered, so the serialiser shifts out its reset value once
  // before the first real byte: the panel sees a leading rs=0 0x00. That is a
  // NOP to an ST7789 and harmless, but it is on the wire and the bench has to
  // account for it rather than pretend the stream starts at the reset run.
  localparam int LEAD = 1;

  logic clk = 0, reset = 1;
  logic [15:0] rgb;
  wire sda, scl, cs, rs, vsync, hsync;
  wire [$clog2(H)-1:0] vpos;
  wire [$clog2(W)-1:0] hpos;

  lcd #(.WIDTH(W), .HEIGHT(H), .RGBSIZE(16), .RESET_WAIT(RESET_WAIT)) dut(
    .clk, .reset, .rgb, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos, .hpos);

  always #5 clk = ~clk;

  // The test pattern the panel should receive: a horizontal red ramp, a
  // vertical green ramp, and a blue square in one corner, so a wrong stride, a
  // swapped byte order or a transposed axis all look obviously wrong.
  function automatic logic [15:0] pattern(input int x, input int y);
    logic [4:0] r; logic [5:0] g; logic [4:0] b;
    begin
      r = 5'((x * 31) / (W - 1));
      g = 6'((y * 63) / (H - 1));
      b = (x < W/4 && y < H/4) ? 5'd31 : 5'd0;
      pattern = {r, g, b};
    end
  endfunction

  assign rgb = pattern(int'(hpos), int'(vpos));

  // ---- SPI receiver ---------------------------------------------------
  // SCL_MODE=0, so scl idles high between bytes and follows ~cin while a byte
  // is shifting. The panel samples on the rising edge; so does this.
  logic [7:0] shreg;
  int         nbits = 0;
  logic [8:0] stream [0:400000];       // {rs, byte}, in wire order
  int         nbytes = 0;

  always @(posedge scl) begin
    if (!reset && !cs) begin
      shreg = {shreg[6:0], sda};
      nbits = nbits + 1;
      if (nbits == 8) begin
        if (nbytes < 400000) stream[nbytes] = {rs, shreg};
        nbytes = nbytes + 1;
        nbits  = 0;
      end
    end
  end

  // ---- expected initialisation ----------------------------------------
  logic [8:0] rom [0:INIT_N-1];
  initial $readmemh("setup_st7789_565.hex", rom);

  int i, base, px, x, y, fd, errors;
  logic [15:0] pix;
  logic [8:0] distinct [0:INIT_N-1];
  int ndistinct;

  initial begin
    #100 reset = 0;

    // Wait for one full frame to have been streamed: the reset run, the 16
    // init bytes, RAMWR, and W*H*2 pixel bytes.
    wait (nbytes >= LEAD + (RESET_WAIT + 1) + INIT_N + 1 + (W * H * 2));
    #1;

    errors = 0;

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
    base = LEAD + RESET_WAIT + 1 + INIT_N;
    if (stream[base] !== 9'h02C) begin
      $display("FAIL: expected RAMWR (rs=0 2C), got rs=%b %02x",
               stream[base][8], stream[base][7:0]);
      errors = errors + 1;
    end

    // --- 4. decode one frame to a PPM ---
    base = base + 1;
    fd = $fopen("lcd_frame.ppm", "wb");
    $fwrite(fd, "P6\n%0d %0d\n255\n", W, H);
    for (y = 0; y < H; y = y + 1)
      for (x = 0; x < W; x = x + 1) begin
        px  = base + (y * W + x) * 2;
        pix = {stream[px][7:0], stream[px + 1][7:0]};   // MSB first on the wire
        $fwrite(fd, "%c%c%c", {pix[15:11], 3'b0}, {pix[10:5], 2'b0},
                              {pix[4:0], 3'b0});
      end
    $fclose(fd);

    // every pixel byte must be data, not command
    for (i = 0; i < W * H * 2; i = i + 1)
      if (stream[base + i][8] !== 1'b1) begin
        $display("FAIL: pixel byte %0d has rs=0", i);
        errors = errors + 1;
        i = W * H * 2;                                  // report once
      end

    if (errors) begin
      $display("FAIL: %0d error(s)", errors);
      $fatal;
    end
    $display("PASS: reset run, %0d distinct init bytes in ROM order, RAMWR, %0dx%0d frame -> build/lcd_frame.ppm", ndistinct, W, H);
    $finish;
  end

  initial begin
    #200000000;
    $display("FAIL: timed out after %0d bytes", nbytes);
    $fatal;
  end
endmodule
