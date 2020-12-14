`include "font_cp437_8x8.v"

module textbuffer(input clk, input reset, 
                  input cs, input rw, input [$clog2(WIDTH*HEIGHT):0] addr, input [7:0] di, output reg [7:0] dout, 
                  input [7:0] hpos, input [6:0] vpos, input vsync, input hsync, 
                  output reg [3:0] color);
  
  parameter WIDTH = 20;
  parameter HEIGHT = 15;

  reg [7:0] videoram [0:1023];

  initial $readmemh("videoram.hex", videoram, 0);
  initial $readmemh("attrram.hex",  videoram, 512);

  wire [$clog2(WIDTH*HEIGHT)-1:0] charpos = (vpos[6:3] * WIDTH) + { 4'b0000, hpos[7:3] };

  wire [7:0] bits;
  reg  [7:0] char;
  reg  [7:0] attr;

  always @(negedge clk)
  begin
    char  = videoram[{1'b0, charpos }];
    attr  = videoram[{1'b1, charpos }];
    color = bits[~hpos[2:0]] ? attr[3:0] : attr[7:4];
  end

  always @(negedge clk)
    if (cs & rw) videoram[addr] <= di;    

  always @(negedge clk)
    if (cs & ~rw) dout <= videoram[addr];

  font_cp437_8x8 font(.clk(~clk), .addr({ char, vpos[2:0]}), .data(bits)); 
endmodule