`include "sprite_compositor.sv"
`include "palette.sv"
`include "ram_async.sv"
`include "control.sv"
`include "memory_arbiter.sv"
`include "dma_controller.sv"
`include "cpu6502_wrapper.sv"

module chip(input logic clk, input logic cpuclk, input logic reset,
            input logic vsync, input logic hsync,
            input logic [6:0] vpos, input logic [7:0] hpos, output logic [RGB-1:0] rgb);

  parameter RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";

  // CPU signals
  wire  [15:0] cpu_addr;
  logic [7:0]  cpu_di, cpu_do;
  logic        cpu_write;
  logic        cpu_rdy;
  
  // Memory signals
  logic [15:0] mem_addr;
  logic        mem_write;
  logic [7:0]  mem_data_out;
  logic        tb_cs, sp_cs, ram_cs, ovl_cs;
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
    .mem_addr(mem_addr),
    .mem_write(mem_write),
    .mem_data_out(mem_data_out),
    .ram_data_in(ram_do),
    .tb_data_in(tb_do),
    .sp_data_in(sp_do),
    
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

  // 8x64kbit Async RAM - use the same clock as the CPU
  ram_async #(.A(16), .D(8), .FILE("./rtl/ram.hex")) ram(
    .clk(clk), 
    .cs(ram_cs), 
    .rw(mem_write), 
    .addr(mem_addr), 
    .di(mem_data_out), 
    .dout(ram_do)
  );
  
  // CPU - now with RDY control from arbiter
  cpu6502 cpu0(
    .clk(clk), 
    .reset(reset), 
    .address(cpu_addr), 
    .data_in(cpu_di), 
    .data_out(cpu_do), 
    .write(cpu_write),
    .rdy(cpu_rdy)
  );

  // The PPU's tilemap absorbed the old textbuffer; its $F000 window is the
  // map's CPU write port (write-only, reads return 0)
  assign tb_do = 8'h00;

  // PPU: tilemap + sprite compositor
  logic [3:0] sprite_color;
  logic [RGB-1:0] srgb;
  sprite_compositor s0(
    .clk(clk), 
    .reset(reset), 
    .addr(sp_cs ? mem_addr[3:0] : 4'h0), 
    .cs(sp_cs), 
    .rw(mem_write), 
    .di(mem_data_out), 
    .dout(sp_do), 
    .map_cs(tb_cs),
    .map_addr(tb_cs ? mem_addr[9:0] : 10'h0),
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

  // Basic Video Signals 
  assign rgb = srgb;
endmodule
