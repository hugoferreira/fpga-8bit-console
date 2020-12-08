`include "font_cp437_8x8.v"
`include "font_pico8.v"

module textbuffer(input clk, input reset, input [11:0] addr, input we, input oe, input [7:0] di, output reg [7:0] dout, input [7:0] hpos, input [6:0] vpos, input vsync, output reg [3:0] color);
  parameter WIDTH = 20;
  parameter HEIGHT = 15;
  parameter BASEADDR = 16'h400;

  reg [7:0] videoram [WIDTH*HEIGHT*2:0];

  initial $readmemh("videoram.hex", videoram, 0);
  initial $readmemh("attrram.hex", videoram, WIDTH*HEIGHT);

  wire [$clog2(WIDTH*HEIGHT)-1:0] charpos = vpos[6:3] * WIDTH + hpos[7:3];
  wire [$clog2(WIDTH*HEIGHT*2)-1:0] attrpos = WIDTH*HEIGHT + charpos;

  wire [7:0] bits;
  reg  [7:0] char;

  always @(negedge clk)
  begin
    color <= bits[~hpos[2:0]] ? videoram[attrpos][3:0] : videoram[attrpos][7:4];
    char <= videoram[charpos];
  end

  always @(negedge clk)
  begin
    // if (oe & !we) data <= videoram[(addr - 16'h400) % (WIDTH*HEIGHT*2)];
    if (we) videoram[(addr - 16'h400) % (WIDTH*HEIGHT*2)] <= di;    
    if (oe) dout <= videoram[(addr - 16'h400) % (WIDTH*HEIGHT*2)];
  end

  font_cp437_8x8 font(.clk, .addr(char * 8 + vpos[2:0]), .data(bits)); 
endmodule