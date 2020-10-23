
module chip(input clk, input reset, output sda, output scl, output cs, output rs);
  wire vsync;
  wire hsync;
  wire [7:0] vpos;
  wire [6:0] hpos;
  reg  [6:0] linehpos = 0;
  wire [4:0] red   = (hpos == linehpos) ? 5'b11111 : 0; //(vpos[3] == 0) ? 5'b11111 : 0;
  wire [5:0] green = 0; //(hpos[3] == 0) ? 6'b111111 : 0;
  wire [4:0] blue  = 0; //0;

  /* wire [3:0] digit = hpos[6:3];
  wire [2:0] xofs = hpos[3:1];
  wire [2:0] yofs = vpos[3:1];
  wire [4:0] bits;
  wire [6:0] segments;
  
  seven_segment_decoder decoder(
    .digit(digit),
    .segments(segments)
  );
  
  segments_to_bitmap numbers(
    .segments(segments),
    .line(yofs),
    .bits(bits)
  );

  wire [4:0] red   = (bits[~xofs]) ? 5'b11111 : 0;
  wire [5:0] green = (bits[~xofs]) ? 6'b111111 : 0;
  wire [4:0] blue  = (bits[~xofs]) ? 5'b11111 : 0;
  */

  lcd lcd0(
    .cin(clk),
    .reset,
    .red,
    .green,
    .blue,
    .sda,
    .scl,
    .cs,
    .rs,
    .vsync,
    .hsync,
    .vpos,
    .hpos
  ); 

  always @(posedge vsync or posedge reset)
  begin
    if (reset) begin 
      linehpos <= 0;
    end else begin
      if (linehpos == 127) linehpos <= 0;
      else linehpos = linehpos + 1;    
    end
  end
endmodule
