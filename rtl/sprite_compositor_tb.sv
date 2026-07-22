// Standalone testbench for the sprite compositor / PPU. Drives the real
// timing contract - 4 system clocks per pixel, 161 pixels per line, 121
// lines per frame (mirroring hvsync_generator) - programs the four pattern
// planes and a full 128-entry sprite list with mixed depths (1-4 bpp) and
// palette bases through the CPU register interface, animates the list every
// frame, and dumps each frame as a PICO-8-colored PPM under build/frames/.
`timescale 1ns/1ps

module sprite_compositor_tb;
  localparam W = 160;
  localparam H = 120;
  localparam HTOT = 161;   // includes the hsync pixel
  localparam VTOT = 121;   // includes the vsync line
  localparam PCLK = 4;     // system clocks per pixel
  localparam NSPR = 128;
  localparam NFRAMES = 96;

  bit clk = 0;
  always #5 clk = ~clk;

  bit reset = 1;

  // Video counters at 1/PCLK the clock rate, mirroring hvsync_generator
  int phase = 0;
  logic [7:0] hp = 0;
  logic [6:0] vp = 0;
  always_ff @(posedge clk) begin
    if (reset) begin
      hp <= 0;
      vp <= 0;
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

  // CPU register interface
  bit cs = 0, rw = 0;
  logic [3:0] addr = 0;
  logic [7:0] di = 0;
  logic [7:0] dout;
  logic [3:0] color;

  sprite_compositor dut(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di), .dout(dout),
    .hpos(hp), .vpos(vp),
    .vsync(vsync), .hsync(hsync),
    .color(color),
    .dma_active(1'b0), .dma_write(1'b0), .dma_addr(4'h0), .dma_data(8'h00));

  task cpuwrite(input [3:0] a, input [7:0] d);
    @(negedge clk);
    cs = 1; rw = 1; addr = a; di = d;
    @(negedge clk);
    cs = 0; rw = 0;
  endtask

  // Frame capture: color for pixel (vp,hp) is valid on the pixel's last clock
  logic [3:0] frame_pix[0:H-1][0:W-1];
  always_ff @(posedge clk)
    if (!reset && phase == PCLK - 1 && hp < W && vp < H)
      frame_pix[vp][hp] <= color;

  // PICO-8 palette (matches rtl/palette888.bin) for the PPM dumps
  logic [23:0] PAL[0:15];
  initial begin
    PAL[0]=24'h000000; PAL[1]=24'h1D2B53; PAL[2]=24'h7E2553; PAL[3]=24'h008751;
    PAL[4]=24'hAB5236; PAL[5]=24'h5F574F; PAL[6]=24'hC2C3C7; PAL[7]=24'hFFF1E8;
    PAL[8]=24'hFF004D; PAL[9]=24'hFFA300; PAL[10]=24'hFFEC27; PAL[11]=24'h00E436;
    PAL[12]=24'h29ADFF; PAL[13]=24'h83769C; PAL[14]=24'hFF77A8; PAL[15]=24'hFFCCAA;
  end

  task dump_frame(input int f);
    int fd;
    string name;
    logic [23:0] rgb;
    name = $sformatf("build/frames/frame_%03d.ppm", f);
    fd = $fopen(name, "w");
    $fwrite(fd, "P3\n%0d %0d\n255\n", W, H);
    for (int y = 0; y < H; y++)
      for (int x = 0; x < W; x++) begin
        rgb = PAL[frame_pix[y][x]];
        $fwrite(fd, "%0d %0d %0d\n", rgb[23:16], rgb[15:8], rgb[7:0]);
      end
    $fclose(fd);
  endtask

  // Same pattern data as rtl/sprite_pattern.bin, written via the CPU port
  // to exercise the plane-select path
  logic [7:0] PLANES_INIT[0:31];
  initial $readmemb("./rtl/sprite_pattern.bin", PLANES_INIT);

  // Sprite motion and appearance
  int px[NSPR], py[NSPR], vx[NSPR], vy[NSPR];
  logic [7:0] fbase[NSPR];  // static flag bits: {pal[3:0], bppm1[1:0], 2'b00}
  int seed;
  logic [3:0] PALTBL[0:7];
  initial begin
    PALTBL[0]=4'd8; PALTBL[1]=4'd2; PALTBL[2]=4'd10; PALTBL[3]=4'd4;
    PALTBL[4]=4'd12; PALTBL[5]=4'd5; PALTBL[6]=4'd3; PALTBL[7]=4'd0;
  end

  task write_list();
    logic [7:0] flags;
    cpuwrite(4'h8, 8'd0);  // rewind index
    for (int i = 0; i < NSPR; i++) begin
      flags = fbase[i] | {6'b0, vy[i] > 0, vx[i] > 0};  // arrow points along travel
      cpuwrite(4'h9, px[i][7:0]);
      cpuwrite(4'hA, py[i][7:0]);
      cpuwrite(4'hB, flags);
    end
    cpuwrite(4'hC, NSPR[7:0]);
  endtask

  task step_motion();
    for (int i = 0; i < NSPR; i++) begin
      px[i] += vx[i];
      py[i] += vy[i];
      if (px[i] < 0)       begin px[i] = 0;      vx[i] = -vx[i]; end
      if (px[i] > W - 8)   begin px[i] = W - 8;  vx[i] = -vx[i]; end
      if (py[i] < 0)       begin py[i] = 0;      vy[i] = -vy[i]; end
      if (py[i] > H - 8)   begin py[i] = H - 8;  vy[i] = -vy[i]; end
    end
  endtask

  task wait_frame_end();
    @(posedge clk);
    while (!(vp == VTOT - 1 && hp == HTOT - 1 && phase == PCLK - 1)) @(posedge clk);
    @(posedge clk);
  endtask

  initial begin
    logic [1:0] bppm1;
    logic [3:0] pal;

    // Scatter sprites with an LCG; velocities in {-2,-1,1,2}; depth cycles
    // 1,2,3,4 bpp with a per-sprite palette base
    seed = 32'd42;
    for (int i = 0; i < NSPR; i++) begin
      seed = (seed * 32'd1103515245 + 32'd12345) & 32'h7fffffff;
      px[i] = (seed >> 8) % (W - 8);
      seed = (seed * 32'd1103515245 + 32'd12345) & 32'h7fffffff;
      py[i] = (seed >> 8) % (H - 8);
      vx[i] = ((i % 4) < 2) ? ((i % 2) + 1) : -((i % 2) + 1);
      vy[i] = (((i / 4) % 4) < 2) ? (((i / 2) % 2) + 1) : -(((i / 2) % 2) + 1);
      bppm1 = i[1:0];
      pal = (bppm1 == 2'd3) ? 4'd8 : PALTBL[(i >> 2) & 7];
      fbase[i] = {pal, bppm1, 2'b00};
    end

    repeat (4) @(negedge clk);
    reset = 0;

    // Program the four pattern planes through the plane-select register
    for (int p = 0; p < 4; p++) begin
      cpuwrite(4'hE, p[7:0]);
      for (int r = 0; r < 8; r++)
        cpuwrite(r[3:0], PLANES_INIT[p*8 + r]);
    end
    cpuwrite(4'hE, 8'd0);

    // Each iteration: move sprites, stream the list (tears into the frame
    // in progress), then let one full quiet frame render before dumping so
    // every dumped frame is bit-exact against the golden model
    for (int f = 0; f < NFRAMES; f++) begin
      if (f == 0)
        write_list();
      else begin
        step_motion();
        write_list();
      end
      wait_frame_end();
      wait_frame_end();
      dump_frame(f);
    end

    $display("Rendered %0d frames of %0d sprites at mixed 1-4 bpp", NFRAMES, NSPR);
    $finish;
  end

endmodule
