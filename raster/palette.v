module palette(input clk, input [3:0] color, output reg [4:0] r, output reg [5:0] g, output reg [4:0] b);
  reg [15:0] palette[0:15];
  initial $readmemb("palette.bin", palette);
  
  always @(posedge clk)
  begin
    { r, g, b } <= palette[color];
  end
endmodule
