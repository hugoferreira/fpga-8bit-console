`include "chip.v"
`include "lcd/lcd.v"
`include "lcd/scalescreen.v"

/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        25.000 MHz
 * Requested output frequency:   60.000 MHz
 * Achieved output frequency:    60.156 MHz
 */
module master_clk(input cin, output cout, output locked);
  SB_PLL40_CORE #(
      .FEEDBACK_PATH("SIMPLE"),
      .DIVR(4'b0001),		// DIVR =  1
      .DIVF(7'b1001100),	// DIVF = 76
      .DIVQ(3'b100),		// DIVQ =  4
      .FILTER_RANGE(3'b001)	// FILTER_RANGE = 1
    ) uut (
      .LOCK(locked),
      .RESETB(1'b1),
      .BYPASS(1'b0),
      .REFERENCECLK(cin),
      .PLLOUTCORE(cout)
  );
endmodule

module slower_clk(input cin, input reset, output cout);
  reg [1:0] counter = 2'b00;
  assign cout = counter[1];
  always @(posedge cin or posedge reset)
  begin
    if (reset) counter <= 2'b00;
    else counter <= counter + 1;
  end
endmodule

module por(input clk, input reset, output reg user_reset);
  reg [20:0] counter = 21'h17D796;
  reg user_reset = 1;

  always @(posedge clk or posedge reset)
  begin
    if (reset) begin 
      counter <= 21'h17D796;    // 0.062s @ 25Mhz
      user_reset <= 1;
    end else if (user_reset) begin 
      if (counter == 0) user_reset <= 0;
      counter <= counter - 1;
    end
  end
endmodule

module top(input clk, output yellow_led, output sda, output scl, output cs, output rs, output lcd_rst, output tx);
  parameter SCALE = 2, WIDTH = 320, HEIGHT = 240;

  wire reset;
  wire clk_1;
  wire clk_2;

  assign lcd_rst = ~reset;
  assign yellow_led = ~reset;

  por u_por(.clk, .reset(1'b0), .user_reset(reset));
  master_clk clk0(.cin(clk), .cout(clk_1));
  slower_clk clk1(.cin(clk_1), .cout(clk_2), .reset);

  wire vsync;
  wire hsync;
  wire [4:0] red;
  wire [5:0] green;
  wire [4:0] blue;

  wire [7:0] vp;
  wire [8:0] hp;
  wire [6:0] vpos;
  wire [7:0] hpos;

  scalescreen #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) scaler0(.clk(clk_2), .reset, .vp, .hp, .vpos, .hpos);
  lcd #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) lcd0(.clk(clk_2), .reset, .red, .green, .blue, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos(vp), .hpos(hp));

  chip chip(.clk_0(clk), .clk_1, .clk_2, .reset, .vsync, .hsync, .vpos, .hpos, .red, .green, .blue);

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
