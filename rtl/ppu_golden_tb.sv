// PPU golden-frame regression net.
//
// The compositor's demo testbench (sprite_compositor_tb.sv) renders 96 frames
// and dumps PPMs that nobody compares, so every change to the engine has been
// justified by reading the diff. This harness is the opposite: a fixed set of
// scenes, each exercising a different path through the compositor, each
// rendered to a committed reference frame and compared bit-for-bit.
//
// Two things are asserted, and both have to hold:
//
//   1. Pixels. Every pixel of every scene matches rtl/golden/ppu_NN_name.txt.
//      A failure names the scene, the first differing coordinate and the two
//      colour values.
//   2. Clocks. A scanline is HTOT*PCLK = 483 system clocks. The engine has to
//      reach E_IDLE before the next line_start; an overrun is silent in
//      hardware (the engine restarts and the tail of the sprite list is simply
//      not composited), so it is a test failure here. The per-scene worst-case
//      engine occupancy is itself a committed number, because a refactor that
//      buys Fmax by spending line budget is not a win.
//
// Regenerate the references deliberately, in the same commit as the behaviour
// change that moved them:  vvp build/ppu_golden.vvp +regen
// Prove the net still bites:                        vvp build/ppu_golden.vvp +inject
//
// Timing mirrors rtl/top_simulator.sv: 3 system clocks per pixel, 161 pixels
// per line (the last is hsync), 121 lines per frame (the last is vsync).
`timescale 1ns/1ps

module ppu_golden_tb;
  localparam W     = 160;
  localparam H     = 120;
  localparam HTOT  = 161;
  localparam VTOT  = 121;
  localparam PCLK  = 3;
  localparam BUDGET = HTOT * PCLK;   // 483 engine clocks per line

  // E_IDLE is the first member of the engine's state enum. Compared as a
  // literal so the harness does not depend on the type being visible.
  localparam [3:0] E_IDLE = 4'd0;

  localparam NSCENE = 11;

  bit clk = 0;
  always #5 clk = ~clk;

  bit reset = 1;

  // ------------------------------------------------------------------
  // Video counters
  // ------------------------------------------------------------------
  // `freeze` stops the beam at the end of a line without stopping the clock,
  // which is how the overrun probe measures what a line's work actually costs:
  // the engine keeps running, sees no display slots (as in hblank) and no
  // line_start, so it can be timed to completion instead of being restarted.
  bit freeze = 0;
  int phase = 0;
  logic [7:0] hp = 0;
  logic [6:0] vp = 0;
  always_ff @(posedge clk) begin
    if (reset) begin
      hp <= 0;
      vp <= 0;
      phase <= 0;
    end else if (freeze) begin
      phase <= 0;
    end else if (phase == PCLK - 1) begin
      phase <= 0;
      if (hp == HTOT - 1) begin
        hp <= 0;
        vp <= (vp == VTOT - 1) ? 7'd0 : vp + 7'd1;
      end else
        hp <= hp + 1;
    end else
      phase <= phase + 1;
  end
  wire vsync = (vp == VTOT - 1);
  wire hsync = (hp == HTOT - 1);

  // ------------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------------
  bit         cs = 0, rw = 0;
  logic [5:0] addr = 0;
  logic [7:0] di = 0;
  logic [7:0] dout;
  logic [3:0] color;
  bit          map_cs = 0;
  logic [9:0]  map_addr = 0;
  bit          ovl_cs = 0;
  logic [11:0] ovl_addr = 0;
  bit          dma_active = 0, dma_write = 0;
  logic [3:0]  dma_addr = 0;
  logic [7:0]  dma_data = 0;

  sprite_compositor dut(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di), .dout(dout),
    .map_cs(map_cs), .map_addr(map_addr),
    .btn(8'h00),
    .ovl_cs(ovl_cs), .ovl_addr(ovl_addr),
    .hpos(hp), .vpos(vp),
    .vsync(vsync), .hsync(hsync),
    .color(color),
    .dma_active(dma_active), .dma_write(dma_write),
    .dma_addr(dma_addr), .dma_data(dma_data));

  task cpuwrite(input [5:0] a, input [7:0] d);
    @(negedge clk);
    cs = 1; rw = 1; addr = a; di = d;
    @(negedge clk);
    cs = 0; rw = 0;
  endtask

  task cpuread(input [5:0] a, output [7:0] d);
    @(negedge clk);
    cs = 1; rw = 0; addr = a;
    @(negedge clk);
    @(negedge clk);
    d = dout;
    cs = 0;
  endtask

  task mapwrite(input [9:0] a, input [7:0] d);
    @(negedge clk);
    map_cs = 1; rw = 1; map_addr = a; di = d;
    @(negedge clk);
    map_cs = 0; rw = 0;
  endtask

  // The DMA controller's port into $00-$0F. It wins over CPU access, which is
  // the one piece of arbitration in the register file.
  task dmawrite(input [3:0] a, input [7:0] d);
    @(negedge clk);
    dma_active = 1; dma_write = 1; dma_addr = a; dma_data = d;
    @(negedge clk);
    dma_active = 0; dma_write = 0;
  endtask

  task ovlwrite(input [11:0] a, input [7:0] d);
    @(negedge clk);
    ovl_cs = 1; rw = 1; ovl_addr = a; di = d;
    @(negedge clk);
    ovl_cs = 0; rw = 0;
  endtask

  // ------------------------------------------------------------------
  // Frame capture: the colour for pixel (vp,hp) is stable on the pixel's
  // last clock (read issued on clock 0, registered on 1, held on 2)
  // ------------------------------------------------------------------
  logic [3:0] frame_pix[0:H-1][0:W-1];
  always_ff @(posedge clk)
    if (!reset && !freeze && phase == PCLK - 1 && hp < W && vp < H)
      frame_pix[vp][hp] <= color;

  // ------------------------------------------------------------------
  // Per-line cycle accounting
  // ------------------------------------------------------------------
  int  busy;         // clocks the engine has been non-idle in this line
  int  max_busy;     // worst line since the counters were cleared
  int  overrun_n;    // lines the engine did not finish
  int  ov_line, ov_scan, ov_lim, ov_est, ov_tk;
  bit  acct = 0;

  always @(posedge clk) if (!reset && !freeze) begin
    if (dut.line_start) begin
      if (acct && dut.est != E_IDLE) begin
        if (overrun_n == 0) begin
          ov_line = dut.line_y;
          ov_scan = dut.scan.scan_i;
          ov_lim  = dut.scan.count_eff;
          ov_est  = dut.est;
          ov_tk   = dut.tmap.tk;
        end
        overrun_n = overrun_n + 1;
      end
      if (acct && busy > max_busy) max_busy = busy;
      busy = 0;
    end else if (dut.est != E_IDLE)
      busy = busy + 1;
  end

  task clear_acct();
    max_busy  = 0;
    overrun_n = 0;
    busy      = 0;
  endtask

  // ------------------------------------------------------------------
  // Golden files: one line per scanline, 160 hex digits, pixel 0 leftmost
  // ------------------------------------------------------------------
  bit regen  = 0;
  bit inject = 0;
  int failures = 0;
  int committed_busy[0:NSCENE-1];
  int scene_busy[0:NSCENE-1];

  function automatic string ref_name(input int idx, input string nm);
    return $sformatf("rtl/golden/ppu_%0d_%0s.txt", idx, nm);
  endfunction

  task write_ref(input int idx, input string nm);
    int fd;
    logic [W*4-1:0] rowvec;
    fd = $fopen(ref_name(idx, nm), "w");
    if (fd == 0) $fatal(1, "cannot write %0s", ref_name(idx, nm));
    for (int y = 0; y < H; y++) begin
      for (int x = 0; x < W; x++)
        rowvec[(W - 1 - x) * 4 +: 4] = frame_pix[y][x];
      $fwrite(fd, "%h\n", rowvec);
    end
    $fclose(fd);
  endtask

  // Compares and reports the FIRST difference: scene, coordinate, both colours.
  task check_ref(input int idx, input string nm);
    int fd, code, ndiff;
    logic [W*4-1:0] rowvec;
    logic [3:0] want, got, fwant, fgot;
    int fy, fx;
    fd = $fopen(ref_name(idx, nm), "r");
    if (fd == 0)
      $fatal(1, "[ppu-check] no reference %0s - run with +regen to create it",
             ref_name(idx, nm));
    ndiff = 0;
    fy = -1;
    fx = -1;
    fwant = 4'hx;
    fgot  = 4'hx;
    for (int y = 0; y < H; y++) begin
      code = $fscanf(fd, "%h", rowvec);
      if (code != 1)
        $fatal(1, "[ppu-check] %0s truncated at line %0d", ref_name(idx, nm), y);
      for (int x = 0; x < W; x++) begin
        want = rowvec[(W - 1 - x) * 4 +: 4];
        got  = frame_pix[y][x];
        if (want !== got) begin
          if (ndiff == 0) begin fy = y; fx = x; fwant = want; fgot = got; end
          ndiff = ndiff + 1;
        end
      end
    end
    $fclose(fd);
    if (ndiff != 0) begin
      failures = failures + 1;
      $display("[ppu-check] FAIL scene %0d (%0s): %0d pixels differ", idx, nm, ndiff);
      $display("            first at (x=%0d, y=%0d): reference colour %0h, rendered %0h",
               fx, fy, fwant, fgot);
    end
  endtask

  // ------------------------------------------------------------------
  // Scene plumbing
  // ------------------------------------------------------------------
  // Sampled on the negedge so the counters are settled: reading them straight
  // off a posedge races the nonblocking update that produced them.
  task wait_frame_end();
    @(negedge clk);
    while (!(vp == VTOT - 1 && hp == HTOT - 1 && phase == PCLK - 1)) @(negedge clk);
    @(negedge clk);
  endtask

  // Render one quiet frame after the scene's writes, capture it, then render a
  // second and check that one - so the captured frame contains no tearing from
  // the register writes that set the scene up.
  task settle_and_check(input int idx, input string nm);
    wait_frame_end();
    clear_acct();
    acct = 1;
    wait_frame_end();
    acct = 0;

    if (inject && idx == 3)
      frame_pix[57][93] = ~frame_pix[57][93];

    if (regen) begin
      write_ref(idx, nm);
      $display("[ppu-check] scene %0d (%0s) written, worst line %0d/%0d clocks",
               idx, nm, max_busy, BUDGET);
    end else begin
      check_ref(idx, nm);
      if (overrun_n != 0) begin
        failures = failures + 1;
        $display("[ppu-check] FAIL scene %0d (%0s): %0d lines overran the %0d-clock budget",
                 idx, nm, overrun_n, BUDGET);
        $display("            first at line %0d: engine still in state %0d, scan at %0d of %0d, tile column %0d",
                 ov_line, ov_est, ov_scan, ov_lim, ov_tk);
      end
      if (max_busy > committed_busy[idx]) begin
        failures = failures + 1;
        $display("[ppu-check] FAIL scene %0d (%0s): worst line is %0d clocks, recorded %0d",
                 idx, nm, max_busy, committed_busy[idx]);
      end else if (max_busy < committed_busy[idx])
        $display("[ppu-check] note: scene %0d (%0s) worst line improved %0d -> %0d clocks (regenerate to lock it in)",
                 idx, nm, committed_busy[idx], max_busy);
    end
    scene_busy[idx] = max_busy;
  endtask

  // One integer per scene: the worst-case engine occupancy of any scanline in
  // that scene, in system clocks, against the BUDGET of 483.
  task write_cycles();
    int fd;
    fd = $fopen("rtl/golden/ppu_cycles.txt", "w");
    for (int i = 0; i < NSCENE; i++)
      $fwrite(fd, "%0d\n", scene_busy[i]);
    $fclose(fd);
  endtask

  task read_cycles();
    int fd, code;
    fd = $fopen("rtl/golden/ppu_cycles.txt", "r");
    if (fd == 0)
      $fatal(1, "[ppu-check] no rtl/golden/ppu_cycles.txt - run with +regen");
    for (int i = 0; i < NSCENE; i++) begin
      code = $fscanf(fd, "%d", committed_busy[i]);
      if (code != 1) $fatal(1, "[ppu-check] ppu_cycles.txt has fewer than %0d scenes", NSCENE);
    end
    $fclose(fd);
  endtask

  // ------------------------------------------------------------------
  // Content
  // ------------------------------------------------------------------
  // Deterministic patterns, uploaded through the CPU port so the sheet write
  // and auto-increment path is exercised too. Four footprints, one per depth,
  // packed back to back:
  //   slot 16, 4 planes: value = (2*col + row) & 15   - all 16 values appear
  //   slot 20, 3 planes: value = (col + 3*row) & 7
  //   slot 23, 2 planes: value = (col ^ row) & 3
  //   slot 25, 1 plane : value = (col + row) & 1      - a checkerboard
  // The bases are consecutive because the upload is one auto-incrementing run.
  localparam [7:0] P4 = 8'd16, P3 = 8'd20, P2 = 8'd23, P1 = 8'd25;

  function automatic [3:0] pat_val(input int grp, input int col, input int row);
    case (grp)
      3: return (2 * col + row) & 15;
      2: return (col + 3 * row) & 7;
      1: return (col ^ row) & 3;
      default: return (col + row) & 1;
    endcase
  endfunction

  task upload_patterns();
    logic [7:0] b;
    cpuwrite(6'h00, 8'(P4 * 8));        // byte address = slot * 8
    cpuwrite(6'h01, 8'((P4 * 8) >> 8));
    for (int grp = 3; grp >= 0; grp--)
      for (int p = 0; p <= grp; p++)
        for (int row = 0; row < 8; row++) begin
          b = 0;
          for (int col = 0; col < 8; col++)
            b[col] = pat_val(grp, col, row) >> p;
          cpuwrite(6'h02, b);
        end
  endtask

  // Every register back to its reset value, so a scene inherits nothing.
  bit ovl_dirty = 0;
  task defaults();
    cpuwrite(6'h05, 8'h00);             // tiles off, overlay off
    cpuwrite(6'h03, 8'h00);             // camera
    cpuwrite(6'h04, 8'h00);
    cpuwrite(6'h06, 8'h00);             // overlay colour
    cpuwrite(6'h0C, 8'h00);             // sprite count
    cpuwrite(6'h08, 8'h00);             // list index
    cpuwrite(6'h36, 8'h00);             // behind-split
    cpuwrite(6'h3A, 8'h00);             // staged behind bit
    cpuwrite(6'h38, 8'h00);             // overlay row colours: all defaulted
    for (int k = 0; k < 128; k++)
      cpuwrite(6'h39, 8'h00);
    cpuwrite(6'h37, 8'h01);             // repeat = one cell
    cpuwrite(6'h34, 8'h01);             // only value 0 transparent
    cpuwrite(6'h35, 8'h00);
    cpuwrite(6'h30, 8'd0);              // full-screen clip
    cpuwrite(6'h31, 8'd0);
    cpuwrite(6'h32, 8'(W - 1));
    cpuwrite(6'h33, 8'(H - 1));
    for (int k = 0; k < 16; k++) begin  // identity palettes
      cpuwrite(6'(6'h10 + k), 8'(k));
      cpuwrite(6'(6'h20 + k), 8'(k));
    end
  endtask

  task clear_map();
    for (int i = 0; i < 512; i++) begin
      mapwrite(10'(i), 8'h00);
      mapwrite(10'(512 + i), 8'h00);
    end
  endtask

  task clear_ovl();
    if (ovl_dirty)
      for (int i = 0; i < 2400; i++)
        ovlwrite(12'(i), 8'h00);
    ovl_dirty = 0;
  endtask

  task spr(input int x, input int y, input [7:0] base, input [1:0] bppm1,
           input bit xf, input bit yf, input [3:0] pal, input int rep);
    cpuwrite(6'h37, 8'(rep));
    cpuwrite(6'h09, 8'(x));
    cpuwrite(6'h0A, 8'(y));
    cpuwrite(6'h0E, base);
    cpuwrite(6'h0B, {pal, bppm1, yf, xf});
  endtask

  // A tile world: one band of each depth, mixed palettes and flips, with the
  // empty cells left empty so the skip path is exercised too.
  task build_map();
    logic [7:0] lo, hi;
    for (int ty = 0; ty < 16; ty++)
      for (int tx = 0; tx < 32; tx++) begin
        lo = 0;
        hi = 0;
        case (ty[1:0])
          2'd0: begin lo = P4; hi = {4'(tx & 15), 2'd3, 1'b0, 1'b0}; end
          2'd1: begin lo = P3; hi = {4'(ty & 15), 2'd2, 1'((tx >> 1) & 1), 1'(tx & 1)}; end
          2'd2: begin lo = P2; hi = {4'((tx + ty) & 15), 2'd1, 1'(tx & 1), 1'((tx >> 1) & 1)}; end
          2'd3: begin lo = P1; hi = {4'((tx * 3) & 15), 2'd0, 1'b1, 1'b1}; end
        endcase
        if (((tx * 5 + ty * 3) & 7) == 0) begin   // scattered empty cells
          lo = 0;
          hi = 0;
        end
        mapwrite({1'b0, ty[3:0], tx[4:0]}, lo);
        mapwrite({1'b1, ty[3:0], tx[4:0]}, hi);
      end
  endtask

  task build_ovl();
    logic [7:0] b;
    for (int y = 0; y < H; y++)
      for (int l = 0; l < W / 8; l++) begin
        b = 8'h00;
        if (y == 0 || y == H - 1) b = 8'hFF;              // top/bottom border
        if (l == 0) b[0] = 1;                             // left edge
        if (l == W / 8 - 1) b[7] = 1;                     // right edge
        if ((y >> 3) == l) b = b | 8'hFF;                 // diagonal band
        if (y >= 30 && y < 50 && l >= 4 && l < 9) b = 8'hAA;  // dotted block
        ovlwrite(12'(y * 20 + l), b);
      end
    ovl_dirty = 1;
  endtask

  // ------------------------------------------------------------------
  // Register readback: the register file is the first module to be split out,
  // so its contract is asserted directly rather than only through pixels.
  // ------------------------------------------------------------------
  task check_reg(input [5:0] a, input [7:0] want, input string nm);
    logic [7:0] got;
    cpuread(a, got);
    if (got !== want) begin
      failures = failures + 1;
      $display("[ppu-check] FAIL readback %0s ($%02h): expected %02h, got %02h",
               nm, a, want, got);
    end
  endtask

  task readback_checks();
    cpuwrite(6'h00, 8'h5A); cpuwrite(6'h01, 8'h05);
    check_reg(6'h00, 8'h5A, "sheet addr lo");
    check_reg(6'h01, 8'h05, "sheet addr hi");
    cpuwrite(6'h03, 8'h37); check_reg(6'h03, 8'h37, "camera x");
    cpuwrite(6'h04, 8'hC5); check_reg(6'h04, 8'h45, "camera y (7 bits)");
    cpuwrite(6'h05, 8'h03); check_reg(6'h05, 8'h03, "control");
    cpuwrite(6'h06, 8'h0A); check_reg(6'h06, 8'h0A, "overlay colour");
    cpuwrite(6'h08, 8'h11); check_reg(6'h08, 8'h11, "list index");
    cpuwrite(6'h0C, 8'h40); check_reg(6'h0C, 8'h40, "sprite count");
    cpuwrite(6'h0E, 8'hBE); check_reg(6'h0E, 8'hBE, "staged base");
    cpuwrite(6'h30, 8'd7);  check_reg(6'h30, 8'd7,  "clip x0");
    cpuwrite(6'h31, 8'd9);  check_reg(6'h31, 8'd9,  "clip y0");
    cpuwrite(6'h32, 8'd140);check_reg(6'h32, 8'd140,"clip x1");
    cpuwrite(6'h33, 8'd110);check_reg(6'h33, 8'd110,"clip y1");
    cpuwrite(6'h34, 8'h09); check_reg(6'h34, 8'h09, "palt lo");
    cpuwrite(6'h35, 8'h80); check_reg(6'h35, 8'h80, "palt hi");
    cpuwrite(6'h36, 8'h04); check_reg(6'h36, 8'h04, "behind split");
    // The two palettes do NOT read back as written, and that is asserted here
    // as it is rather than fixed: refactor-ppu-core is behaviour-preserving.
    // The readback arm `6'b01????` matches $10-$1F only, and inside that range
    // addr[4] is always 1, so a DRAW palette read returns the SCREEN palette
    // entry; $20-$2F match no arm at all and read 0. Both palettes take their
    // writes correctly - scenes 7 and 8 render through them - so this is a
    // readback decode bug, not a lost write. Recorded in docs/hardware-gaps.md.
    cpuwrite(6'h13, 8'h0C);
    cpuwrite(6'h23, 8'h05);
    check_reg(6'h13, 8'h05, "draw palette 3 (reads the SCREEN palette)");
    check_reg(6'h23, 8'h00, "screen palette 3 (reads 0)");
    // $37 reads back in cells, and clamps: 0 -> 1, >=8 -> 8
    cpuwrite(6'h37, 8'd0);   check_reg(6'h37, 8'd1, "repeat (0 clamps to 1)");
    cpuwrite(6'h37, 8'd5);   check_reg(6'h37, 8'd5, "repeat");
    cpuwrite(6'h37, 8'd200); check_reg(6'h37, 8'd8, "repeat (clamps to 8)");
    // The list index auto-increments on a commit
    cpuwrite(6'h08, 8'd7);
    cpuwrite(6'h0B, 8'h00);
    check_reg(6'h08, 8'd8, "list index after commit");

    // The DMA port: same registers, same side effects, and it wins over the
    // CPU. This is how the games actually upload a sprite list.
    dmawrite(4'h3, 8'h5C); check_reg(6'h03, 8'h5C, "camera x via DMA");
    dmawrite(4'h4, 8'h23); check_reg(6'h04, 8'h23, "camera y via DMA");
    dmawrite(4'h8, 8'd3);
    dmawrite(4'h9, 8'd40);
    dmawrite(4'hA, 8'd50);
    dmawrite(4'hE, 8'd12);
    dmawrite(4'hB, 8'h30);
    check_reg(6'h08, 8'd4, "list index after a DMA commit");
    check_reg(6'h0E, 8'd12, "staged base via DMA");
  endtask

  // ------------------------------------------------------------------
  // The overrun probe. A line with more composited entries than fit has to be
  // a reported failure, not observed flicker - and the report has to say by
  // how much. `freeze` holds the beam in hblank so the engine can be timed to
  // completion instead of being restarted at the next line_start.
  // ------------------------------------------------------------------
  task overrun_probe();
    int cost, dropped;
    defaults();
    // 128 four-bpp entries stacked on the same scanline: 11 clocks of fetch
    // and blit each, against a 483-clock line.
    cpuwrite(6'h08, 8'd0);
    for (int i = 0; i < 128; i++)
      spr((i * 7) % 152, 56, P4, 2'd3, 1'b0, 1'b0, 4'd0, 1);
    cpuwrite(6'h0C, 8'd128);

    wait_frame_end();
    clear_acct();
    acct = 1;
    wait_frame_end();
    acct = 0;

    if (overrun_n == 0) begin
      failures = failures + 1;
      $display("[ppu-check] FAIL: 128 four-bpp sprites on one line did not overrun -");
      $display("            the cycle accounting is not measuring anything");
      return;
    end

    // Time the same line again with the beam held in hblank once the visible
    // part is over, so the engine runs to completion instead of being
    // restarted at line_start and the work it wanted can be counted. The
    // composited line is one ahead of the beam, so it is line_y = vp + 1.
    dropped = ov_lim - ov_scan;
    @(negedge clk);
    while (!(vp == ov_line - 1 && hp == 0 && phase == 0)) @(negedge clk);
    cost = 1;
    while (!(hp == HTOT - 1 && phase == PCLK - 1)) begin
      @(negedge clk);
      cost = cost + 1;
    end
    freeze = 1;
    while (dut.est != E_IDLE) begin
      @(negedge clk);
      cost = cost + 1;
    end
    freeze = 0;
    $display("[ppu-check] overrun probe: line %0d wanted %0d clocks of a %0d-clock line",
             ov_line, cost, BUDGET);
    $display("            over budget by %0d clocks; %0d of %0d list entries did not composite",
             cost - BUDGET, dropped, ov_lim);
  endtask

  // ------------------------------------------------------------------
  // Scenes
  // ------------------------------------------------------------------
  task scene_bpp();                 // 1/2/3/4 bpp and a non-zero palette base
    defaults();
    cpuwrite(6'h08, 8'd0);
    for (int i = 0; i < 16; i++) begin
      spr(8 + i * 9, 10,  P1, 2'd0, 1'b0, 1'b0, 4'(i), 1);
      spr(8 + i * 9, 34,  P2, 2'd1, 1'b0, 1'b0, 4'(i), 1);
      spr(8 + i * 9, 58,  P3, 2'd2, 1'b0, 1'b0, 4'(i), 1);
      spr(8 + i * 9, 82,  P4, 2'd3, 1'b0, 1'b0, 4'(i), 1);
    end
    cpuwrite(6'h0C, 8'd64);
  endtask

  task scene_flips();               // xflip, yflip, both, at every depth
    defaults();
    cpuwrite(6'h08, 8'd0);
    for (int f = 0; f < 4; f++)
      for (int d = 0; d < 4; d++) begin
        spr(12 + f * 36, 12 + d * 26, d == 3 ? P4 : d == 2 ? P3 : d == 1 ? P2 : P1,
            2'(d), 1'(f & 1), 1'((f >> 1) & 1), 4'd0, 1);
        spr(20 + f * 36, 12 + d * 26, d == 3 ? P4 : d == 2 ? P3 : d == 1 ? P2 : P1,
            2'(d), 1'(f & 1), 1'((f >> 1) & 1), 4'd3, 1);
      end
    cpuwrite(6'h0C, 8'd32);
  endtask

  task scene_tiles();               // the tile layer, camera at the origin
    defaults();
    cpuwrite(6'h0C, 8'd0);
    cpuwrite(6'h05, 8'h01);
  endtask

  task scene_camera();              // sub-cell scroll on both axes, plus wrap
    defaults();
    cpuwrite(6'h0C, 8'd0);
    cpuwrite(6'h03, 8'd211);        // 211 & 7 = 3, and past the 256-px world edge
    cpuwrite(6'h04, 8'd101);        // 101 & 7 = 5
    cpuwrite(6'h05, 8'h01);
  endtask

  task scene_bsplit();              // entries 0-5 behind the tiles, 6-11 in front
    defaults();
    cpuwrite(6'h08, 8'd0);
    for (int i = 0; i < 6; i++)
      spr(16 + i * 20, 20 + i * 6, P4, 2'd3, 1'b0, 1'b0, 4'd0, 3);
    for (int i = 0; i < 6; i++)
      spr(20 + i * 20, 24 + i * 6, P3, 2'd2, 1'b0, 1'b0, 4'd8, 3);
    cpuwrite(6'h0C, 8'd12);
    cpuwrite(6'h36, 8'd6);
    cpuwrite(6'h03, 8'd4);
    cpuwrite(6'h04, 8'd2);
    cpuwrite(6'h05, 8'h01);
  endtask

  task scene_repeat();              // runs of 2..8 cells, including off the edges
    defaults();
    cpuwrite(6'h08, 8'd0);
    for (int r = 2; r <= 8; r++)
      spr(4, 4 + (r - 2) * 12, P2, 2'd1, 1'b0, 1'b0, 4'(r), r);
    spr(140, 92, P4, 2'd3, 1'b0, 1'b0, 4'd0, 8);   // runs off the right edge
    spr(3,  104, P3, 2'd2, 1'b1, 1'b0, 4'd5, 6);   // unaligned start, xflipped
    cpuwrite(6'h0C, 8'd9);
  endtask

  task scene_clip();                // sprites straddling all four clip edges
    defaults();
    cpuwrite(6'h08, 8'd0);
    // Every one of these straddles its edge, so each side has both a clipped
    // and an unclipped half. A sprite entirely outside proves less.
    for (int i = 0; i < 10; i++) begin
      spr(4 + i * 16, 8,   P4, 2'd3, 1'b0, 1'b0, 4'd0, 1);   // over the top edge
      spr(4 + i * 16, 109, P4, 2'd3, 1'b0, 1'b0, 4'd8, 1);   // over the bottom
    end
    for (int i = 0; i < 8; i++) begin
      spr(5,   16 + i * 12, P3, 2'd2, 1'b0, 1'b0, 4'd3, 1);  // over the left edge
      spr(147, 16 + i * 12, P3, 2'd2, 1'b0, 1'b0, 4'd9, 1);  // over the right
    end
    // A repeat run that starts inside the window and runs out of the right
    // edge, so the clip is applied per cell of a run rather than per entry.
    spr(120, 60, P2, 2'd1, 1'b0, 1'b0, 4'd11, 6);
    cpuwrite(6'h0C, 8'd37);
    cpuwrite(6'h30, 8'd9);          // an inset window: every edge cuts something
    cpuwrite(6'h31, 8'd11);
    cpuwrite(6'h32, 8'd150);
    cpuwrite(6'h33, 8'd112);
  endtask

  task scene_palt();                // non-default transparency + draw palette
    defaults();
    cpuwrite(6'h08, 8'd0);
    for (int i = 0; i < 12; i++) begin
      spr(6 + i * 13, 18, P4, 2'd3, 1'b0, 1'b0, 4'd0, 1);
      spr(6 + i * 13, 42, P3, 2'd2, 1'b0, 1'b0, 4'd2, 1);
      spr(6 + i * 13, 66, P2, 2'd1, 1'b0, 1'b0, 4'd6, 1);
      spr(6 + i * 13, 90, P1, 2'd0, 1'b0, 1'b0, 4'd1, 1);
    end
    cpuwrite(6'h0C, 8'd48);
    // Values 0, 3 and 7 transparent; 12 and 13 opaque even though 0 is not
    cpuwrite(6'h34, 8'h89);         // bits 0,3,7
    cpuwrite(6'h35, 8'h00);
    cpuwrite(6'h19, 8'd14);         // draw palette: 9 -> 14
    cpuwrite(6'h1A, 8'd7);          //               10 -> 7
    cpuwrite(6'h11, 8'd11);         //                1 -> 11
    cpuwrite(6'h05, 8'h01);
  endtask

  task scene_overlay();             // overlay set and clear + screen palette
    defaults();
    build_ovl();
    cpuwrite(6'h08, 8'd0);
    for (int i = 0; i < 20; i++)
      spr(4 + i * 8, 20 + (i % 5) * 16, P4, 2'd3, 1'b0, 1'b0, 4'(i & 15), 1);
    cpuwrite(6'h0C, 8'd20);
    cpuwrite(6'h06, 8'd10);         // overlay colour: yellow
    cpuwrite(6'h20, 8'd1);          // screen palette: 0 -> 1 (navy background)
    cpuwrite(6'h2A, 8'd9);          //                 10 -> 9, so the overlay
    cpuwrite(6'h05, 8'h03);         //                 is remapped too
  endtask

  task scene_all();                 // every path at once, and the busiest lines
    defaults();
    build_ovl();
    cpuwrite(6'h08, 8'd0);
    for (int i = 0; i < 8; i++)                       // behind the tiles
      spr(6 + i * 19, 12 + (i % 3) * 30, P2, 2'd1, 1'(i & 1), 1'b0, 4'(i), 2);
    for (int i = 0; i < 24; i++)                      // in front
      spr((i * 23) % 152, 8 + (i * 11) % 100,
          i[0] ? P4 : P3, i[0] ? 2'd3 : 2'd2,
          1'(i & 1), 1'((i >> 1) & 1), 4'((i * 5) & 15), 1 + (i % 3));
    cpuwrite(6'h0C, 8'd32);
    cpuwrite(6'h36, 8'd8);
    cpuwrite(6'h03, 8'd45);         // 45 & 7 = 5
    cpuwrite(6'h04, 8'd19);         // 19 & 7 = 3
    cpuwrite(6'h30, 8'd5);
    cpuwrite(6'h31, 8'd4);
    cpuwrite(6'h32, 8'd154);
    cpuwrite(6'h33, 8'd116);
    cpuwrite(6'h34, 8'h05);         // values 0 and 2 transparent
    cpuwrite(6'h1C, 8'd15);
    cpuwrite(6'h06, 8'd7);
    cpuwrite(6'h23, 8'd4);
    cpuwrite(6'h05, 8'h03);
  endtask

  task scene_rowlut();              // per-entry behind bit + overlay row colours
    defaults();
    build_ovl();
    cpuwrite(6'h08, 8'd0);
    // Front entries FIRST in the list, behind-bit entries after them: with
    // the split at zero, only the bit decides the pass, and list position no
    // longer implies it. The last entry proves the staged bit cleared.
    for (int i = 0; i < 4; i++)
      spr(12 + i * 32, 30 + i * 8, P3, 2'd2, 1'b0, 1'b0, 4'd8, 2);
    cpuwrite(6'h3A, 8'h01);
    for (int i = 0; i < 4; i++)
      spr(4 + i * 36, 26 + i * 10, P4, 2'd3, 1'b0, 1'b0, 4'd0, 4);
    cpuwrite(6'h3A, 8'h00);
    spr(70, 90, P2, 2'd1, 1'b0, 1'b0, 4'd5, 3);
    cpuwrite(6'h0C, 8'd9);
    cpuwrite(6'h06, 8'd10);         // global overlay colour: yellow
    cpuwrite(6'h38, 8'd40);         // rows 40..59 override to red
    for (int r = 0; r < 20; r++)
      cpuwrite(6'h39, 8'h88);
    cpuwrite(6'h38, 8'd80);         // rows 80..89 override to green,
    for (int r = 0; r < 10; r++)    // then the tail rewritten with the
      cpuwrite(6'h39, 8'h8B);       // override bit clear: back to yellow,
    cpuwrite(6'h38, 8'd85);         // proving bit 7 gates and does not just
    for (int r = 0; r < 5; r++)     // recolour
      cpuwrite(6'h39, 8'h0B);
    cpuwrite(6'h05, 8'h03);
  endtask

  // ------------------------------------------------------------------
  initial begin
    regen  = $test$plusargs("regen");
    inject = $test$plusargs("inject");
    for (int i = 0; i < NSCENE; i++) begin
      committed_busy[i] = 0;
      scene_busy[i] = 0;
    end
    if (!regen) read_cycles();

    repeat (4) @(negedge clk);
    reset = 0;

    upload_patterns();
    build_map();

    scene_bpp();     settle_and_check(0, "bpp");
    scene_flips();   settle_and_check(1, "flips");
    scene_tiles();   settle_and_check(2, "tiles");
    scene_camera();  settle_and_check(3, "camera");
    scene_bsplit();  settle_and_check(4, "bsplit");
    scene_repeat();  settle_and_check(5, "repeat");
    scene_clip();    settle_and_check(6, "clip");
    scene_palt();    settle_and_check(7, "palt");
    scene_overlay(); settle_and_check(8, "overlay");
    scene_all();     settle_and_check(9, "all");
    scene_rowlut();  settle_and_check(10, "rowlut");

    clear_ovl();
    readback_checks();
    overrun_probe();

    if (regen) begin
      write_cycles();
      $display("[ppu-check] %0d reference frames and the cycle budget regenerated", NSCENE);
      $finish;
    end

    if (failures == 0) begin
      $display("[ppu-check] PASS: %0d scenes bit-identical, every line inside the %0d-clock budget",
               NSCENE, BUDGET);
      $finish;
    end else
      $fatal(1, "[ppu-check] FAIL: %0d checks failed", failures);
  end

endmodule
