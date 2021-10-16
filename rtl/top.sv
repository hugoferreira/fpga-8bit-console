`include "chip.sv"
`include "por.sv"
`include "slower_clk.sv"
`include "lcd.sv"
`include "scalescreen.v"
`include "pll.v"
`include "clocks.sv"

module top(input  bit clk, output bit yellow_led, 
           output bit sda, output bit scl, output bit cs, output bit rs, output bit lcd_rst, 
           output bit tx);

  localparam SCALE = 2, WIDTH = 320, HEIGHT = 240;
  localparam RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";

  logic reset;
  logic masterclk;
  logic videoclk;
  logic cpuclk;
  clocks clocks0(.clk, .reset, .masterclk, .videoclk, .cpuclk);

  assign lcd_rst = ~reset;
  assign yellow_led = ~reset;

  logic vsync;
  logic hsync;
  logic [RGB-1:0] rgb;
  logic [7:0] vp;
  logic [8:0] hp;
  logic [6:0] vpos;
  logic [7:0] hpos;

  lcd #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) lcd0(.clk(videoclk), .reset, .rgb, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos(vp), .hpos(hp));
  scalescreen #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) scaler0(.clk(videoclk), .reset, .vp, .hp, .vpos, .hpos);
  chip #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE(FILE)) chip(.clk(masterclk), .cpuclk(cpuclk), .reset, .vsync, .hsync, .vpos, .hpos, .rgb);

  /* wire tx_ready;

  uart_tx u_uart_tx (
    .clk (clk),
    .reset (~user_reset),
    .tx_req (1'b1),
    .tx_ready (tx_ready),
    .tx_data (8'h55),
    .uart_tx (tx)
  ); */
endmodule
