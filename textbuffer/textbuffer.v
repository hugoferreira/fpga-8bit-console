`include "font_cp437_8x8.v"
`include "font_pico8.v"

module textbuffer(input clk, input reset, 
                  input we, input oe, input [$clog2(WIDTH*HEIGHT):0] addr, input [7:0] di, output reg [7:0] dout, 
                  input [7:0] hpos, input [6:0] vpos, input vsync, input hsync, 
                  output reg [3:0] color);
  
  parameter WIDTH = 20;
  parameter HEIGHT = 15;

  reg [7:0] videoram [WIDTH*HEIGHT*2:0];

  initial $readmemh("videoram.hex", videoram, 0);
  initial $readmemh("attrram.hex", videoram, WIDTH*HEIGHT);

  wire [$clog2(WIDTH*HEIGHT)-1:0] charpos = (vpos[6:3] * WIDTH) + { 4'b0000, hpos[7:3] };
  wire [$clog2(WIDTH*HEIGHT)  :0] attrpos = WIDTH*HEIGHT + charpos;

  wire [7:0] bits;
  reg  [7:0] char;

  always @(negedge clk)
  begin
    color <= bits[~hpos[2:0]] ? videoram[attrpos][3:0] : videoram[attrpos][7:4];
    char <= videoram[{1'b0, charpos }];
  end

  always @(negedge clk)
  begin
    if (we) videoram[addr] <= di;    
    if (oe) dout <= videoram[addr];
  end

  font_cp437_8x8 font(.clk, .addr({ char, vpos[2:0]}), .data(bits)); 
endmodule