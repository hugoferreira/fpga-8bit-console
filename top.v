`include "chip.v"

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
module master_clk (input cin, output cout, output locked);
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

module slower_clk (input cin, input reset, output cout);
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
  reg user_reset = 0;

  always @(posedge clk or posedge reset)
  begin
    if (reset) begin 
      counter <= 21'h17D796;    // 0.062s @ 25Mhz
      user_reset <= 0;
    end else if (~user_reset) begin 
      if (counter == 0) user_reset <= 1;
      counter <= counter - 1;
    end
  end
endmodule

module top(input clk, output yellow_led, output sda, output scl, output cs, output rs, output lcd_rst, output tx);
  wire user_reset;
  wire videoclk;
  wire clk_2;

  assign lcd_rst = user_reset;
  assign yellow_led = user_reset;

  por u_por(.clk, .reset(1'b0), .user_reset(user_reset));
  master_clk clk0(.cin(clk), .cout(videoclk));
  slower_clk clk1(.cin(videoclk), .cout(clk_2), .reset(~user_reset));
  chip chip(.clk_0(clk), .clk_1(videoclk), .clk_2, .reset(~user_reset), .sda, .scl, .cs, .rs);

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
