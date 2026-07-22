// Standalone testbench for sprite_compositor: drives 160x120 video timing
// (one pixel per clock, same as top_simulator), programs the pattern and a
// full 128-entry sprite list through the CPU register interface, animates
// the list every frame (bouncing, with flips following travel direction),
// and dumps each frame as a PPM image under build/frames/.
`timescale 1ns/1ps

module sprite_compositor_tb;
  localparam W = 160;
  localparam H = 120;
  localparam NSPR = 128;
  localparam NFRAMES = 96;

  bit clk = 0;
  always #5 clk = ~clk;

  bit reset = 1;

  // Video counters, mirroring top_simulator.sv
  logic [8:0] hr = 0;
  logic [7:0] vr = 0;
  always_ff @(posedge clk) begin
    if (reset) begin
      hr <= 0;
      vr <= 0;
    end else if (hr >= W - 1) begin
      hr <= 0;
      vr <= (vr >= H - 1) ? 8'd0 : vr + 8'd1;
    end else begin
      hr <= hr + 1;
    end
  end

  // CPU register interface
  bit cs = 0, rw = 0;
  logic [3:0] addr = 0;
  logic [7:0] di = 0;
  logic [7:0] dout;
  bit pixel;

  sprite_compositor dut(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di), .dout(dout),
    .hpos(hr[7:0]), .vpos(vr[6:0]),
    .vsync(vr == 0), .hsync(hr == 0),
    .pixel(pixel),
    .dma_active(1'b0), .dma_write(1'b0), .dma_addr(4'h0), .dma_data(8'h00));

  task cpuwrite(input [3:0] a, input [7:0] d);
    @(negedge clk);
    cs = 1; rw = 1; addr = a; di = d;
    @(negedge clk);
    cs = 0; rw = 0;
  endtask

  // Frame capture: pixel is registered, so it pairs with last cycle's h/v
  logic [7:0] h_d;
  logic [7:0] v_d;
  bit frame_pix[0:H-1][0:W-1];
  always_ff @(posedge clk) begin
    h_d <= hr[7:0];
    v_d <= vr;
    if (v_d < H && h_d < W)
      frame_pix[v_d][h_d] <= (pixel === 1'b1);
  end

  task dump_frame(input int f);
    int fd;
    string name;
    name = $sformatf("build/frames/frame_%03d.ppm", f);
    fd = $fopen(name, "w");
    $fwrite(fd, "P3\n%0d %0d\n255\n", W, H);
    for (int y = 0; y < H; y++)
      for (int x = 0; x < W; x++)
        if (frame_pix[y][x])
          $fwrite(fd, "255 176 64\n");
        else
          $fwrite(fd, "18 22 38\n");
    $fclose(fd);
  endtask

  // Sprite motion state
  int px[NSPR], py[NSPR], vx[NSPR], vy[NSPR];
  int seed;

  task write_list();
    logic [7:0] flags;
    cpuwrite(4'h8, 8'd0);  // rewind index
    for (int i = 0; i < NSPR; i++) begin
      flags = {6'b0, vy[i] > 0, vx[i] > 0};  // arrow points along travel
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

  initial begin
    // Scatter sprites with an LCG and hand out velocities in {-2,-1,1,2}
    seed = 32'd42;
    for (int i = 0; i < NSPR; i++) begin
      seed = (seed * 32'd1103515245 + 32'd12345) & 32'h7fffffff;
      px[i] = (seed >> 8) % (W - 8);
      seed = (seed * 32'd1103515245 + 32'd12345) & 32'h7fffffff;
      py[i] = (seed >> 8) % (H - 8);
      vx[i] = ((i % 4) < 2) ? ((i % 2) + 1) : -((i % 2) + 1);
      vy[i] = (((i / 4) % 4) < 2) ? (((i / 2) % 2) + 1) : -(((i / 2) % 2) + 1);
    end

    repeat (4) @(negedge clk);
    reset = 0;

    write_list();

    for (int f = 0; f < NFRAMES; f++) begin
      // Wait for the end of a full frame, then one extra clock so the
      // final pixel lands in frame_pix
      @(posedge clk);
      while (!(vr == H - 1 && hr == W - 1)) @(posedge clk);
      @(posedge clk);
      dump_frame(f);
      step_motion();
      write_list();
    end

    $display("Rendered %0d frames of %0d sprites", NFRAMES, NSPR);
    $finish;
  end
endmodule
