`include "textbuffer.v"
`include "sprite.v"
`include "palette.v"

module counter(input vsync, input reset, output reg [11:0] addr, inout [7:0] data);
  reg [7:0] counter;
  assign data = counter;

  always @(posedge vsync)
  begin
    addr <= 16'h400;
    counter <= counter + 1;
  end  
endmodule

module chip(input clk, input reset, output sda, output scl, output cs, output rs);
  // Basic Video Signals 
  wire vsync;
  wire [6:0] vpos;
  wire [7:0] hpos;
  wire [4:0] red   = sr | txtr; 
  wire [5:0] green = sg | txtg; 
  wire [4:0] blue  = sb | txtb; 
  rotatescreen lcd0(.cin(clk), .reset(~reset), .red, .green, .blue, .sda, .scl, .cs, .rs, .vsync, .vpos, .hpos); 

  // Bus(es) 
  wire [11:0] addr;
  wire [7:0]  data;
  wire        rw = 1'b1;

  // Memory Mapping
  wire video_we = (addr === 12'h4xx) &  rw;
  wire video_oe = (addr === 12'h4xx) & !rw;
  
  // Text Video Buffer  
  wire [3:0] text_color;
  wire [4:0] txtr; 
  wire [5:0] txtg; 
  wire [4:0] txtb; 
  textbuffer tb(.clk, .reset, .addr, .we(video_we), .oe(video_oe), .data, .hpos, .vpos, .vsync, .color(text_color));
  palette pal_text(.color(text_color), .r(txtr), .g(txtg), .b(txtb));

  // Video Sprites  
  wire [4:0] sr;
  wire [5:0] sg; 
  wire [4:0] sb; 
  sprite s0(.clk, .reset, .hpos, .vpos, .vsync, .pixel(sprite_rgb));  
  palette pal_sprite(.color(sprite_rgb ? 4'h9 : 4'h0), .r(sr), .g(sg), .b(sb));

  // Others
  counter c0(.vsync, .reset, .addr, .data);
endmodule
