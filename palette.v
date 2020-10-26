module palette(input [3:0] color, output [4:0] r, output [5:0] g, output [4:0] b);
  reg [15:0] palette[0:15];
  initial $readmemb("palette.bin", palette);
  assign { r, g, b } = palette[color];
endmodule
