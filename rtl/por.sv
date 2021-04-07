module por(input bit clk, input bit reset, output bit user_reset);
  logic [20:0] counter = 21'h17D796;
  initial user_reset = 1;

  always_ff @(posedge clk)
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