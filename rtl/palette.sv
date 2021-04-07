module palette(input logic clk, input logic [3:0] color, output logic [RGB-1:0] rgb);
  parameter RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";

  logic [RED+GREEN+BLUE-1:0] palette[0:15];
  initial $readmemb(FILE, palette);
  
  always_ff @(posedge clk)
    rgb <= palette[color];
endmodule
