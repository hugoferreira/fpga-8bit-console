`include "chip.v"

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
  assign lcd_rst = user_reset;
  assign yellow_led = user_reset;

  por u_por(.clk, .reset(1'b0), .user_reset(user_reset));
  chip chip(.cin(clk), .reset(~user_reset), .sda, .scl, .cs, .rs);

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
