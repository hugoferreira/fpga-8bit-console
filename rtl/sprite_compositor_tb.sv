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
  logic [5:0] addr = 0;
  logic [7:0] di = 0;
  logic [7:0] dout;
  logic [3:0] color;
  bit map_cs = 0;
  logic [9:0] map_addr = 0;
  bit ovl_cs = 0;
  logic [11:0] ovl_addr = 0;

  sprite_compositor dut(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di), .dout(dout),
    .map_cs(map_cs), .map_addr(map_addr),
    .ovl_cs(ovl_cs), .ovl_addr(ovl_addr),
    .hpos(hp), .vpos(vp),
    .vsync(vsync), .hsync(hsync),
    .color(color),
    .dma_active(1'b0), .dma_write(1'b0), .dma_addr(4'h0), .dma_data(8'h00));

  task cpuwrite(input [5:0] a, input [7:0] d);
    @(negedge clk);
    cs = 1; rw = 1; addr = a; di = d;
    @(negedge clk);
    cs = 0; rw = 0;
  endtask

  task mapwrite(input [9:0] a, input [7:0] d);
    @(negedge clk);
    map_cs = 1; rw = 1; map_addr = a; di = d;
    @(negedge clk);
    map_cs = 0; rw = 0;
  endtask

  task ovlwrite(input [11:0] a, input [7:0] d);
    @(negedge clk);
    ovl_cs = 1; rw = 1; ovl_addr = a; di = d;
    @(negedge clk);
    ovl_cs = 0; rw = 0;
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

  // Same sheet data as rtl/sprite_pattern.bin, uploaded via the CPU port
  // to exercise the auto-increment path (first 8 plane slots are used)
  logic [7:0] SHEET_INIT[0:2047];
  initial $readmemb("./rtl/sprite_pattern.bin", SHEET_INIT);

  // Camera motion
  int camx = 0, camy = 0, cdx = 1, cdy = 1;

  // Overlay static content (border + main diagonal), CPU-shadow style
  logic [7:0] ovlbase[0:2399];
  int barlane = 0;
  function automatic [7:0] ovl_static(input int y, input int lane);
    logic [7:0] b;
    b = 0;
    if (y == 0 || y == H - 1) b = 8'hFF;
    else begin
      if (lane == 0) b[0] = 1;
      if (lane == W/8 - 1) b[7] = 1;
    end
    if ((y >> 3) == lane && y < W) b[y & 7] = b[y & 7] | 1'b1;
    return b;
  endfunction
  logic [7:0] TEXTROW [0:16];
  initial begin
    TEXTROW[0]="S"; TEXTROW[1]="C"; TEXTROW[2]="R"; TEXTROW[3]="O"; TEXTROW[4]="L";
    TEXTROW[5]="L"; TEXTROW[6]="I"; TEXTROW[7]="N"; TEXTROW[8]="G"; TEXTROW[9]=" ";
    TEXTROW[10]="T"; TEXTROW[11]="I"; TEXTROW[12]="L"; TEXTROW[13]="E"; TEXTROW[14]="M";
    TEXTROW[15]="A"; TEXTROW[16]="P";
  end

  // Sprite motion and appearance
  int px[NSPR], py[NSPR], vx[NSPR], vy[NSPR];
  logic [7:0] fbase[NSPR];  // static flag bits: {pal[3:0], bppm1[1:0], 2'b00}
  logic [7:0] sbase[NSPR];  // pattern base (plane-slot address)
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
      cpuwrite(4'hE, sbase[i]);
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
      // Pattern by kind: 4bpp arrow @0, 1bpp disc @4, 2bpp diamond @5,
      // 1bpp cross @7 - mixed footprints packed back to back in the sheet
      case (i[1:0])
        2'd0: begin sbase[i] = 8'd0; bppm1 = 2'd3; end
        2'd1: begin sbase[i] = 8'd4; bppm1 = 2'd0; end
        2'd2: begin sbase[i] = 8'd5; bppm1 = 2'd1; end
        2'd3: begin sbase[i] = 8'd7; bppm1 = 2'd0; end
      endcase
      pal = (bppm1 == 2'd3) ? 4'd8 : PALTBL[(i >> 2) & 7];
      fbase[i] = {pal, bppm1, 2'b00};
    end

    repeat (4) @(negedge clk);
    reset = 0;

    // Upload the first 8 plane slots of the sheet via the auto-increment port
    cpuwrite(4'h0, 8'd0);
    cpuwrite(4'h1, 8'd0);
    for (int b = 0; b < 64; b++)
      cpuwrite(4'h2, SHEET_INIT[b]);

    // Build the tile world: diagonal stripes of 2bpp diamonds plus a text
    // banner living in the world at row 2
    for (int ty = 0; ty < 16; ty++)
      for (int tx = 0; tx < 32; tx++) begin
        logic [7:0] lo, hi;
        lo = 0;
        hi = 0;
        if (((tx + ty) & 7) == 0) begin
          lo = 8'd5;
          hi = {PALTBL[ty & 7], 2'd1, 2'b00};
        end
        if (ty == 2 && tx >= 2 && tx < 19) begin
          lo = 8'd128 + TEXTROW[tx - 2];
          hi = 8'h60;
        end
        mapwrite({1'b0, ty[3:0], tx[4:0]}, lo);
        mapwrite({1'b1, ty[3:0], tx[4:0]}, hi);
      end
    // Overlay: border + diagonal as static content, plus a sweeping bar
    for (int y = 0; y < H; y++)
      for (int l = 0; l < W/8; l++) begin
        ovlbase[y*20 + l] = ovl_static(y, l);
        ovlwrite(12'(y*20 + l), ovl_static(y, l));
      end
    for (int y = 40; y < 80; y++)
      ovlwrite(12'(y*20 + barlane), 8'hFF);
    cpuwrite(4'h6, 8'd10);  // overlay color: yellow

    // Draw state: inset clip window, value 3 also transparent, draw-palette
    // 9 -> 14 (orange -> pink), screen-palette 0 -> 1 (navy background)
    cpuwrite(6'h30, 8'd8);
    cpuwrite(6'h31, 8'd8);
    cpuwrite(6'h32, 8'd151);
    cpuwrite(6'h33, 8'd111);
    cpuwrite(6'h34, 8'h09);
    cpuwrite(6'h19, 8'd14);
    cpuwrite(6'h20, 8'd1);

    cpuwrite(4'h5, 8'h03);  // enable tilemap + overlay

    // Each iteration: move sprites, stream the list (tears into the frame
    // in progress), then let one full quiet frame render before dumping so
    // every dumped frame is bit-exact against the golden model
    for (int f = 0; f < NFRAMES; f++) begin
      if (f == 0)
        write_list();
      else begin
        step_motion();
        camx += cdx;
        if (camx <= 0 || camx >= 96) cdx = -cdx;
        camy += cdy;
        if (camy <= 0 || camy >= 8) cdy = -cdy;
        cpuwrite(4'h3, camx[7:0]);
        cpuwrite(4'h4, camy[7:0]);
        // Sweep the overlay bar one lane right (erase old, draw new)
        for (int y = 40; y < 80; y++)
          ovlwrite(12'(y*20 + barlane), ovlbase[y*20 + barlane]);
        barlane = (barlane + 1) % 20;
        for (int y = 40; y < 80; y++)
          ovlwrite(12'(y*20 + barlane), 8'hFF);
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
