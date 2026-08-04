`include "sprite_compositor.sv"
`include "psg.sv"
`include "palette.sv"
`include "ram_async.sv"
`include "control.sv"
`include "memory_arbiter.sv"
`include "dma_controller.sv"
`include "cpu6502_wrapper.sv"

module chip(input logic clk, input logic cpuclk, input logic psgclk,
            input logic psgfastclk,
            input logic reset,
            input logic vsync, input logic hsync,
            input logic [6:0] vpos, input logic [7:0] hpos,
            input logic [7:0] buttons,
            output logic [RGB-1:0] rgb,
            output logic signed [15:0] audio,
            output logic [63:0] psg_dbg);

  parameter RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";
  // Master-clock frequency, threaded to the PSG so its 22050 Hz virtual
  // sample rate is derived correctly on any board (default: the simulator's
  // 161*121*3*60 Hz pixel clock). REVERB=0 drops the reverb delay BRAM.
  parameter CLK_HZ = 32'd3_506_580, REVERB = 1, PSG_PREVIEW = 0;
  // Enable only when psgfastclk is the 112.5 MHz PLL clock and psgclk is its
  // accepted /6 derivative. Other boards and simulator models leave this off.
  parameter PSG_MULTIPUMP = 0;
  // The PSG's --psg-trace bus. Only top_simulator.sv reads it; every
  // synthesised top leaves psg_dbg unconnected, so they set this to 0
  // and the cone that drives it is never built.
  parameter PSG_DBG = 1;

  // Which subsystems are present. Both default to 1, so `top.sv` and
  // `top_simulator.sv` build exactly the console they always did without being
  // touched. Setting one to 0 removes that subsystem and ties its bus inputs
  // to zero; the memory arbiter's decode branch for it is then trimmed.
  //
  // This is what makes the per-subsystem synthesis targets measure the SHIPPING
  // design rather than a harness that imitates it - see rtl/target_*.sv and
  // openspec/changes/refactor-build-targets/design.md decision D1. There is one
  // description of how the console is wired, and the subsystem targets are that
  // description with parts switched off.
  parameter HAS_PPU = 1, HAS_PSG = 1;

  // Size of the internal RAM, in address bits. 16 (64 KB) is the real machine
  // and what the simulator uses. The FPGA top overrides it, because 64 KB is
  // 512 kbit against the hx8k's 128 kbit of block RAM and the design cannot
  // be synthesised at all with it - see rtl/top.sv. TEMPORARY: this parameter
  // exists only until the external-memory abstraction lands, at which point
  // both tops should pass the same thing and this can go.
  parameter RAM_ADDR_BITS = 16;

  // CPU signals
  wire  [15:0] cpu_addr;
  logic [7:0]  cpu_di, cpu_do;
  logic        cpu_write;
  logic        cpu_rdy;
  wire         psg_rdy;
  
  // Memory signals
  logic [15:0] mem_addr;
  logic        mem_write;
  logic [7:0]  mem_data_out;
  logic        tb_cs, sp_cs, ram_cs, ovl_cs, psg_cs;
  logic [7:0]  psg_do;
  logic [7:0]  ram_do, tb_do, sp_do;
  
  // DMA signals
  logic dma_active;
  logic dma_request;
  logic [15:0] dma_addr;
  logic dma_write;
  logic [7:0] dma_data_out;
  logic vblank_start;
  
  // Text buffer DMA signals
  logic tb_dma_active;
  logic tb_dma_write;
  logic [9:0] tb_dma_addr;
  logic [7:0] tb_dma_data;
  
  // Sprite DMA signals
  logic sp_dma_active;
  logic sp_dma_write;
  logic [3:0] sp_dma_addr;
  logic [7:0] sp_dma_data;
  
  // VBLANK detection
  logic vblank;
  logic vsync_prev;
  
  always_ff @(posedge clk) begin
    vsync_prev <= vsync;
    // Detect falling edge of vsync (start of VBLANK)
    vblank_start <= vsync_prev && !vsync;
  end
  
  // Memory arbiter
  memory_arbiter arbiter(
    .clk(clk),
    .reset(reset),
    .vsync(vsync),
    
    // CPU interface
    .cpu_addr(cpu_addr),
    .cpu_write(cpu_write),
    .cpu_data_out(cpu_do),
    .cpu_data_in(cpu_di),
    .cpu_rdy(cpu_rdy),
    
    // Memory interfaces
    .ram_cs(ram_cs),
    .tb_cs(tb_cs),
    .sp_cs(sp_cs),
    .ovl_cs(ovl_cs),
    .psg_cs(psg_cs),
    .mem_addr(mem_addr),
    .mem_write(mem_write),
    .mem_data_out(mem_data_out),
    .ram_data_in(ram_do),
    .tb_data_in(tb_do),
    .sp_data_in(sp_do),
    .psg_data_in(psg_do),
    
    // DMA interface
    .dma_active(dma_active),
    .dma_request(dma_request),
    .dma_addr(dma_addr),
    .dma_write(dma_write),
    .dma_data_out(dma_data_out)
  );
  
  // DMA controller
  dma_controller dma(
    .clk(clk),
    .reset(reset),
    .vblank_start(vblank_start),
    
    // Memory arbiter interface
    .dma_request(dma_request),
    .dma_addr(dma_addr),
    .dma_write(dma_write),
    .dma_data_out(dma_data_out),
    .dma_data_in(cpu_di),  // Use the same data bus as CPU
    .dma_active(dma_active),
    
    // Text buffer interface
    .tb_dma_active(tb_dma_active),
    .tb_dma_write(tb_dma_write),
    .tb_dma_addr(tb_dma_addr),
    .tb_dma_data(tb_dma_data),
    
    // Sprite interface
    .sp_dma_active(sp_dma_active),
    .sp_dma_write(sp_dma_write),
    .sp_dma_addr(sp_dma_addr),
    .sp_dma_data(sp_dma_data)
  );

  // Async RAM - use the same clock as the CPU. The address is truncated
  // explicitly rather than by port width, so a shrunken RAM aliases visibly
  // instead of silently.
  ram_async #(.A(RAM_ADDR_BITS), .D(8), .FILE("./rtl/ram.hex")) ram(
    .clk(clk),
    .cs(ram_cs),
    .rw(mem_write),
    .addr(mem_addr[RAM_ADDR_BITS-1:0]),
    .di(mem_data_out), 
    .dout(ram_do)
  );
  
  // CPU - now with RDY control from arbiter
  // The CPU is NOT behind a parameter, and the attempt is worth recording:
  // removing it ties cpu_addr to a constant, so psg_cs/sp_cs never assert and
  // yosys constant-folds the subsystem behind them. Measured - the PSG went
  // from 6772 logic cells to 1467, a "result" that is 78% trimming. A
  // bus master that cannot be removed without folding the design is a bus
  // master that stays. rtl/target_psg.sv explains what it does instead.
  cpu6502 cpu0(
    .clk(clk),
    .reset(reset),
    .address(cpu_addr),
    .data_in(cpu_di),
    .data_out(cpu_do),
    .write(cpu_write),
    // The PSG adds wait-states for state-memory-resident register accesses;
    // both ready sources freeze the core identically.
    .rdy(cpu_rdy && psg_rdy)
  );

  // The PPU's tilemap absorbed the old textbuffer; its $F000 window is the
  // map's CPU write port (write-only, reads return 0)
  assign tb_do = 8'h00;

  // PPU: tilemap + sprite compositor
  logic [RGB-1:0] srgb;
  generate
    if (HAS_PPU) begin : g_ppu
      logic [3:0] sprite_color;
      sprite_compositor s0(
        .clk(clk),
        .reset(reset),
        .addr(sp_cs ? mem_addr[5:0] : 6'h0),
        .cs(sp_cs),
        .rw(mem_write),
        .di(mem_data_out),
        .dout(sp_do),
        .map_cs(tb_cs),
        .map_addr(tb_cs ? mem_addr[9:0] : 10'h0),
        .btn(buttons),
        .ovl_cs(ovl_cs),
        .ovl_addr(ovl_cs ? mem_addr[11:0] : 12'h0),
        .hpos(hpos),
        .vpos(vpos),
        .hsync(hsync),
        .vsync(vsync),
        .color(sprite_color),
        // DMA interface
        .dma_active(sp_dma_active),
        .dma_write(sp_dma_write),
        .dma_addr(sp_dma_addr),
        .dma_data(sp_dma_data)
      );
      palette #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE("./rtl/palette888.bin")) pal_sprite(
        .clk(clk),
        .color(sprite_color),
        .rgb(srgb)
      );
    end else begin : g_no_ppu
      // Reads of the PPU's windows return 0. The arbiter needs no change:
      // sp_cs/tb_cs/ovl_cs still decode, they just select a constant, and
      // yosys trims the branch.
      assign sp_do = 8'h00;

      // The video output carries a reduction of the CPU bus rather than zero.
      // This is an OBSERVABILITY tie-off, not a rendering behaviour - it only
      // exists in a build with no PPU, which is a measurement configuration
      // and never a console. Without it, a build with neither PPU nor PSG has
      // no non-constant output at all, and synthesis quite correctly trims the
      // CPU, the arbiter and the RAM to nothing: `make synth-cpu` first
      // reported 193 MHz with its critical path inside the video timing
      // generator, which is what a design that folded away looks like.
      //
      // Done here rather than through a new chip port because adding one
      // breaks every existing top - Verilator escalates PINMISSING to an
      // error, so top_simulator.sv fails to build the moment a port is added
      // that it does not connect.
      // NB: one bit, not {RGB{bus_obs}}. RGB is 16, and a consumer that
      // XOR-reduces the bus - which is exactly what a probe pin does - sees
      // the XOR of 16 identical bits, which is constant 0. Replicating it
      // folded the design harder than leaving it zero: 103 logic cells, with
      // the CPU gone entirely.
      logic bus_obs;
      always_ff @(posedge clk) bus_obs <= ^{cpu_addr, cpu_do, cpu_write};
      assign srgb = {{(RGB-1){1'b0}}, bus_obs};
    end
  endgenerate

  // PSG: PICO-8-equivalent audio chip; all timing derived internally
  // from CLK_HZ (22050 Hz virtual sample rate, 120.49 Hz sequencer tick)
  // The PSG is architected for the undivided PLL clock, giving thousands of
  // hardware clocks per 22050 Hz sample for serialized, BRAM-backed work.
  // Simulator lowering and host throughput are not an RTL scheduling budget.
  // Both clocks are phase-locked derivatives of one PLL; clocks.sv keeps
  // non-power-of-two PSG rising edges on the opposite PLL phase from the
  // CPU/master rising edges.
  generate
    if (HAS_PSG) begin : g_psg
      psg #(.CLK_HZ(CLK_HZ), .REVERB(REVERB),
            .REALTIME_PREVIEW(PSG_PREVIEW), .DBG_PORT(PSG_DBG),
            .MULTIPUMP(PSG_MULTIPUMP)) psg0(
        .clk(psgclk),
        .fastclk(psgfastclk),
        .reset(reset),
        .cs(psg_cs),
        .rw(mem_write),
        .addr(psg_cs ? mem_addr[7:0] : 8'h0),
        .di(mem_data_out),
        .dout(psg_do),
        .rdy(psg_rdy),
        .pcm(audio),
        .dbg(psg_dbg)
      );
    end else begin : g_no_psg
      assign psg_do  = 8'h00;
      assign psg_rdy = 1'b1;
      assign audio   = '0;
      assign psg_dbg = '0;
    end
  endgenerate

  // Basic Video Signals
  assign rgb = srgb;

endmodule
