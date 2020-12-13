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

module counter(input clk, input vsync, input reset, output reg [15:0] addr, output reg [7:0] data, output reg rw);
  reg [7:0] letter  = 0;
  reg [3:0] color   = 0;
  reg [7:0] pos     = 80;
  reg [2:0] delay   = 3'b111;
  
  always @(posedge clk)
  begin
    if (vsync) begin
      delay <= delay - 1;

      // Update Character RAM
      case (delay) 
        2'b00: begin
          addr <= 16'hFC03 + (20*15);
          color <= color + 1;
          data <= { 4'b0000, color };
          rw <= 1;
        end 
        2'b01: begin
          addr <= 16'hFBF8;
          pos <= pos - 2;
          data <= pos;
          rw <= 1;
        end 
        /* 2'b10: begin
          addr <= 16'hFC05;
          letter <= letter + 1;
          data <= letter;
          rw <= 1;
        end */
        default: rw <= 0;
      endcase
    end
  end  
endmodule

module chip(input cin, input reset, output sda, output scl, output cs, output rs);
  wire clk;
  master_clk clk0(.cin, .cout(clk));

  // Basic Video Signals 
  wire vsync;
  wire hsync;
  wire [6:0] vpos;
  wire [7:0] hpos;
  wire [4:0] red   = sr | txtr; 
  wire [5:0] green = sg | txtg; 
  wire [4:0] blue  = sb | txtb; 
  scalescreen lcd0(.cin(clk), .reset(~reset), .red, .green, .blue, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos, .hpos); 

  // Bus(es) and  Memory Mapping
  wire [15:0] addr;

  reg         rw;
  wire [7:0]  cpu_do;
  wire [7:0]  cpu_di = tb_oe ? tb_do : (sp_we ? sp_do : 8'b0);

  reg         tb_we;
  reg         tb_oe;
  wire [7:0]  tb_di = cpu_do;
  wire [7:0]  tb_do;

  reg         sp_we;
  reg         sp_oe;
  wire [7:0]  sp_di = cpu_do;
  wire [7:0]  sp_do;
  
  always @(*)
    casex (addr)
      16'b111111xxxxxxxxxx: begin
        tb_we  =  rw;
        tb_oe  = !rw;
        sp_we  = 0;
        sp_oe  = 0;
      end
      16'b111110111111xxxx: begin
        tb_we  = 0;
        tb_oe  = 0;
        sp_we  =  rw;
        sp_oe  = !rw;
      end
      default: begin
        tb_we = 0;
        tb_oe = 0;      
        sp_we = 0;
        sp_oe = 0;  
      end
    endcase

  // Text Video Buffer  
  wire [3:0] text_color;
  wire [4:0] txtr; 
  wire [5:0] txtg; 
  wire [4:0] txtb; 
  textbuffer tb(.clk, .reset, .addr(addr[9:0]), .we(tb_we), .oe(tb_oe), .di(tb_di), .dout(tb_do), .hpos, .vpos, .vsync, .hsync, .color(text_color));
  palette pal_text(.color(text_color), .r(txtr), .g(txtg), .b(txtb));

  // Video Sprites  
  wire [4:0] sr;
  wire [5:0] sg; 
  wire [4:0] sb; 
  sprite s0(.clk, .reset, .addr(addr[3:0]), .we(sp_we), .oe(sp_oe), .di(sp_di), .dout(sp_do), .hpos, .vpos, .vsync, .pixel(sprite_rgb));  
  palette pal_sprite(.color(sprite_rgb ? 4'h9 : 4'h0), .r(sr), .g(sg), .b(sb));

  // Others
  counter c0(.clk, .vsync, .reset, .addr, .data(cpu_do), .rw);
endmodule
