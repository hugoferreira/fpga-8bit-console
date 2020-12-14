module textbuffer(input clk, input reset, 
                  input cs, input rw, input [$clog2(WIDTH*HEIGHT):0] addr, input [7:0] di, output reg [7:0] dout, 
                  input [7:0] hpos, input [6:0] vpos, input vsync, input hsync, 
                  output reg [3:0] color);
  
  parameter WIDTH = 20;
  parameter HEIGHT = 15;

  reg [7:0] videoram [0:(1<<12)-1];

  initial $readmemh("videoram.hex", videoram, 0);
  initial $readmemh("attrram.hex",  videoram, 512);
  initial $readmemh("font_cp437_8x8.hex", videoram, 2048);

  reg [$clog2(WIDTH*HEIGHT)-1:0] pos = vpos[6:3] * WIDTH + { 4'b0000, hpos[7:3] };  
  reg [7:0] char;
  reg [7:0] attr;

  always @(posedge clk)
  begin  
    char   = videoram[{3'b000, pos }]; 
    attr   = videoram[{3'b001, pos }];
    color <= videoram[{1'b1, char, vpos[2:0]}][~hpos[2:0]] ? attr[3:0] : attr[7:4];

    if (cs & ~rw) dout <= videoram[{2'b00, addr}];
    if (cs &  rw) videoram[{2'b00, addr}] <= di;
  end
endmodule