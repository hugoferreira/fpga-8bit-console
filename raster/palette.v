module palette(input clk, input [3:0] color, output reg [RGB-1:0] rgb);
  parameter RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";

  reg [RED+GREEN+BLUE-1:0] palette[0:15];
  initial $readmemb(FILE, palette);
  
  always @(posedge clk)
    rgb <= palette[color];
endmodule
