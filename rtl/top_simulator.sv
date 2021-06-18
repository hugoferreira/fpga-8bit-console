`include "chip.sv"
`include "por.sv"
`include "slower_clk.sv"

module top(input logic clk_i, input logic rst_i, 
           output logic hsync, output logic vsync, output logic [23:0] rgb);
  localparam WIDTH = 320, HEIGHT = 240;

  logic       clk_4;
  logic       clk_64;
  logic [7:0] hpos;
  logic [6:0] vpos;
    
  /* verilator lint_off PINMISSING */
  slower_clk clk1(.cin(clk_i), .clk_div4(clk_4), .reset(rst_i));
  slower_clk clk2(.cin(clk_4), .clk_div256(clk_64), .reset(rst_i));

  hvsync_generator hvsync_gen(.clk(clk_4), .reset(rst_i), .hsync, .vsync, .hpos, .vpos);
  chip #(.RED(8), .GREEN(8), .BLUE(8), .FILE("palette888.bin")) chip(.clk(clk_i), .cpuclk(clk_64), .reset(rst_i), .vsync, .hsync, .vpos, .hpos, .rgb);
endmodule
