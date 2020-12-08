`include "textbuffer/textbuffer.v"
`include "sprites/sprite.v"
`include "lcd/palette.v"
`include "lcd/lcd.v"

/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        25.000 MHz
 * Requested output frequency:   60.000 MHz
 * Achieved output frequency:    60.156 MHz
 */

module master_clk (input cin, output cout, output locked);
  SB_PLL40_CORE #(
      .FEEDBACK_PATH("SIMPLE"),
      .DIVR(4'b0000),		// DIVR =  0
      .DIVF(7'b0011111),	// DIVF = 31
      .DIVQ(3'b100),		// DIVQ =  4
      .FILTER_RANGE(3'b010)	// FILTER_RANGE = 2
    ) uut (
      .LOCK(locked),
      .RESETB(1'b1),
      .BYPASS(1'b0),
      .REFERENCECLK(cin),
      .PLLOUTCORE(cout)
  );
endmodule

module counter(input vsync, input reset, output reg [11:0] addr, output reg [7:0] data, output rw);
  reg [7:0] counter = 0;
  reg [2:0] delay   = 8'hFF;
  
  assign data = counter;
  assign rw   = delay == 0;

  always @(posedge vsync)
  begin
    addr <= 16'h400;
    delay <= delay - 1;
    if (delay == 0) counter <= counter + 1;
  end  
endmodule

module chip(input cin, input reset, output sda, output scl, output cs, output rs);
  wire clk;
  master_clk clk0(.cin, .cout(clk));

  // Basic Video Signals 
  wire vsync;
  wire [6:0] vpos;
  wire [7:0] hpos;
  wire [4:0] red   = sr | txtr; 
  wire [5:0] green = sg | txtg; 
  wire [4:0] blue  = sb | txtb; 
  scalescreen lcd0(.cin(clk), .reset(~reset), .red, .green, .blue, .sda, .scl, .cs, .rs, .vsync, .vpos, .hpos); 

  // Bus(es) and  Memory Mapping
  wire [11:0] addr;
  wire [7:0]  cpu_do;
  wire [7:0]  cpu_di;
  wire [7:0]  tb_di;
  wire [7:0]  tb_do;
  reg         rw;
  reg         tb_we;
  reg         tb_oe;
  
  always @(*)
    casex (addr)
      12'h4xx: begin
        tb_we =  rw;
        tb_oe = !rw;
        tb_di = cpu_do;
        cpu_di = tb_do;
      end
      default: begin
        tb_we = 0;
        tb_oe = 0;        
      end
    endcase

  // Text Video Buffer  
  wire [3:0] text_color;
  wire [4:0] txtr; 
  wire [5:0] txtg; 
  wire [4:0] txtb; 
  textbuffer tb(.clk, .reset, .addr, .we(tb_we), .oe(tb_oe), .di(tb_di), .do(tb_do), .hpos, .vpos, .vsync, .color(text_color));
  palette pal_text(.color(text_color), .r(txtr), .g(txtg), .b(txtb));

  // Video Sprites  
  wire [4:0] sr;
  wire [5:0] sg; 
  wire [4:0] sb; 
  sprite s0(.clk, .reset, .hpos, .vpos, .vsync, .pixel(sprite_rgb));  
  palette pal_sprite(.color(sprite_rgb ? 4'h9 : 4'h0), .r(sr), .g(sg), .b(sb));

  // Others
  counter c0(.vsync, .reset, .addr, .data(cpu_do), .rw);
endmodule
