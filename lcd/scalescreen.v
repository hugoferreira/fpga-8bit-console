module scalescreen(input clk, input reset, 
                   input [$clog2(HEIGHT)-1:0] vp, input [$clog2(WIDTH)-1:0] hp,
                   output [$clog2(HEIGHT)-SCALE:0] vpos, output [$clog2(WIDTH)-SCALE:0] hpos);
  parameter SCALE = 2, WIDTH = 320, HEIGHT = 240;

  assign vpos = vp[$clog2(HEIGHT)-1:SCALE-1];
  assign hpos = hp[$clog2(WIDTH)-1:SCALE-1];  
endmodule