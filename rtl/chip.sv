`include "textbuffer.sv"
`include "sprite.sv"
`include "palette.sv"
`include "ram_async.sv"
`include "control.sv"
`include "addressdecoder.sv"
`include "cpu6502_wrapper.sv"

module chip(input logic clk, input logic cpuclk, input logic reset,
            input logic vsync, input logic hsync,
            input logic [6:0] vpos, input logic [7:0] hpos, output logic [RGB-1:0] rgb);

  parameter RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";

  // Addressing and Peripherals - Separate CPU address bus from peripheral buses
  wire  [15:0] cpu_addr;       // CPU's address bus
  wire  [9:0]  tb_addr;        // Text buffer address (10 bits)
  wire  [3:0]  sp_addr;        // Sprite address (4 bits)
  logic  [7:0] cpu_di, cpu_do, tb_do, sp_do, ram_do;
  logic        tb_cs, sp_cs, ram_cs;
  logic        write;  // Rename for clarity - this is the CPU's write signal

  /* verilator lint_off UNOPTFLAT */
  addressdecoder decoder(
    .clk(clk),           // Connect the clock to the address decoder
    .addr(cpu_addr),     // Connect to CPU address bus 
    .rw(write), 
    .cpu_di, 
    .tb_do, 
    .sp_do, 
    .ram_do, 
    .tb_cs, 
    .sp_cs, 
    .ram_cs
  );
  /* verilator lint_on UNOPTFLAT */

  // 8x64kbit Async RAM - use the same clock as the CPU (not inverted)
  ram_async #(.A(16), .D(8), .FILE("./rtl/ram.hex")) ram(.clk(clk), .cs(ram_cs), .rw(write), .addr(cpu_addr[15:0]), .di(cpu_do), .dout(ram_do));
  
  // Control Unit
  // control c0(.clk, .reset, .vsync, .addr, .data(cpu_do), .din(cpu_di), .rw);

  // CPU - use the main clock instead of cpuclk
  cpu6502 cpu0(.clk(clk), .reset, .address(cpu_addr), .data_in(cpu_di), .data_out(cpu_do), .write(write));
  // cpu6502 cpu0(.clk, .reset, .AB(addr), .DI(cpu_di), .DO(cpu_do), .WE(~rw), .IRQ(0), .NMI(0), .RDY(1));

  // Generate addresses for peripherals from CPU address when selected
  assign tb_addr = cpu_addr[9:0];  // Lower 10 bits for text buffer
  assign sp_addr = cpu_addr[3:0];  // Lower 4 bits for sprite registers

  // Text Video Buffer - use the same clock as the CPU (not inverted)
  logic [3:0] text_color;
  logic [RGB-1:0] trgb; 
  textbuffer tb(.clk(clk), .reset, .addr(tb_addr), .cs(tb_cs), .rw(write), .di(cpu_do), .dout(tb_do), .hpos, .vpos, .vsync, .hsync, .color(text_color));
  palette #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE("./rtl/palette888.bin")) pal_text(.clk, .color(text_color), .rgb(trgb));

  // Video Sprites - use the same clock as the CPU (not inverted)
  logic pixel;
  logic [RGB-1:0] srgb;
  sprite s0(.clk(clk), .reset, .addr(sp_addr), .cs(sp_cs), .rw(write), .di(cpu_do), .dout(sp_do), .hpos, .vpos, .hsync, .vsync, .pixel);
  palette #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE("./rtl/palette888.bin")) pal_sprite(.clk, .color(pixel ? 4'h9 : 4'h0), .rgb(srgb));

  // Basic Video Signals 
  assign rgb = srgb | trgb;
endmodule
