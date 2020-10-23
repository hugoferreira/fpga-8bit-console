`include "serialize.v"
`include "clkdivider.v"
`include "lcd.v"
`include "sevensegment.v"
`include "chip.v"

module resetcircuit(input clk, input reset, output reg user_reset);
  reg [15:0] counter = 16'hFFFF;
  reg user_reset = 1;
  
  always @(posedge clk or posedge reset)
  begin
    if (reset) begin 
      counter <= 16'hFFFF;
      user_reset <= 1;
    end else if (user_reset) begin 
      counter <= counter - 1;
      if (counter == 0) user_reset <= 0;
    end
  end
endmodule

module top(input clk, input reset, output sda, output scl, output cs, output rs, output lcd_rst);
  reg user_reset = 1;

  resetcircuit rst(
    .clk,
    .reset,
    .user_reset
  );

  chip chip(
    .clk,
    .reset(user_reset),
    .sda,
    .scl,
    .cs,
    .rs,
  );

  assign lcd_rst = !user_reset;
endmodule
