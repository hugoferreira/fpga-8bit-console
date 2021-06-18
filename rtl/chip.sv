`include "textbuffer.sv"
`include "sprite.sv"
`include "palette.sv"
`include "ram_async.sv"
`include "control.sv"
`include "addressdecoder.sv"
`include "cpu6502.sv"

module chip(input logic clk, input logic cpuclk, input logic reset,
            input logic vsync, input logic hsync,
            input logic [6:0] vpos, input logic [7:0] hpos, output logic [RGB-1:0] rgb);

  parameter RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";

  // Addressing and Peripherals
  wire  [15:0] addr;
  logic  [7:0] cpu_di, cpu_do, tb_do, sp_do, ram_do;
  logic        tb_cs, sp_cs, ram_cs;
  logic        rw;

  addressdecoder decoder(.addr, .rw, .cpu_di, .tb_do, .sp_do, .ram_do, .tb_cs, .sp_cs, .ram_cs);

  // 8x64kbit Async RAM
  ram_async #(.A(12), .D(8), .FILE("ram.hex")) ram(.clk(~clk), .cs(ram_cs), .rw, .addr(addr[11:0]), .di(cpu_do), .dout(ram_do));
  
  // Control Unit
  // control c0(.clk, .reset, .vsync, .addr, .data(cpu_do), .din(cpu_di), .rw);

  cpu6502 cpu0(.clk(cpuclk), .reset, .address(addr), .data_in(cpu_di), .data_out(cpu_do), .write(rw));
  // cpu6502 cpu0(.clk, .reset, .AB(addr), .DI(cpu_di), .DO(cpu_do), .WE(~rw), .IRQ(0), .NMI(0), .RDY(1));

  // Text Video Buffer  
  logic [3:0] text_color;
  logic [RGB-1:0] trgb; 
  textbuffer tb(.clk(~clk), .reset, .addr(addr[9:0]), .cs(tb_cs), .rw, .di(cpu_do), .dout(tb_do), .hpos, .vpos, .vsync, .hsync, .color(text_color));
  palette #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE(FILE)) pal_text(.clk, .color(text_color), .rgb(trgb));

  // Video Sprites  
  logic pixel;
  logic [RGB-1:0] srgb;
  sprite s0(.clk(~clk), .reset, .addr(addr[3:0]), .cs(sp_cs), .rw, .di(cpu_do), .dout(sp_do), .hpos, .vpos, .hsync, .vsync, .pixel);
  palette #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE(FILE)) pal_sprite(.clk, .color(pixel ? 4'h9 : 4'h0), .rgb(srgb));

  // Basic Video Signals 
  assign rgb = srgb | trgb;
endmodule
