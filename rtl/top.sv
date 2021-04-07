`include "chip.sv"
`include "por.sv"
`include "slower_clk.sv"
`include "lcd.sv"
`include "scalescreen.v"

/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        25.000 MHz
 * Requested output frequency:   80.000 MHz
 * Achieved output frequency:    79.688 MHz
 */
module master_clk(input bit cin, output bit cout, output bit locked);
  SB_PLL40_CORE #(
      .FEEDBACK_PATH("SIMPLE"),
      .DIVR(4'b0001),		    // DIVR =  1
      .DIVF(7'b0110010),	  // DIVF = 50
      .DIVQ(3'b011),		    // DIVQ =  3
      .FILTER_RANGE(3'b001)	// FILTER_RANGE = 1
    ) uut (
      .LOCK(locked),
      .RESETB(1'b1),
      .BYPASS(1'b0),
      .REFERENCECLK(cin),
      .PLLOUTCORE(cout)
  );
endmodule

module top(input  bit clk, output bit yellow_led, 
           output bit sda, output bit scl, output bit cs, output bit rs, output bit lcd_rst, 
           output bit tx);

  localparam SCALE = 2, WIDTH = 320, HEIGHT = 240;
  localparam RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";

  logic reset;
  logic clk_locked;  // PLL generator is locked
  logic clk_1;       // 80MHz
  logic clk_2;       // 40MHz

  assign lcd_rst = ~reset;
  assign yellow_led = ~reset;

  por u_por(.clk, .reset(~clk_locked), .user_reset(reset));
  master_clk clk0(.cin(clk), .cout(clk_1), .locked(clk_locked));
  slower_clk clk1(.cin(clk_1), .clk_div4(clk_2), .reset);

  logic vsync;
  logic hsync;
  logic [RGB-1:0] rgb;
  logic [7:0] vp;
  logic [8:0] hp;
  logic [6:0] vpos;
  logic [7:0] hpos;

  lcd #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) lcd0(.clk(clk_2), .reset, .rgb, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos(vp), .hpos(hp));
  scalescreen #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) scaler0(.clk(clk_2), .reset, .vp, .hp, .vpos, .hpos);
  chip #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE(FILE)) chip(.clk(clk_1), .reset, .vsync, .hsync, .vpos, .hpos, .rgb);

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
