module clkdivider(input cin, input reset, output cout);
  parameter CLK_DIV = 0;
  
  reg [22:0] counter = 0;
  assign cout = counter[CLK_DIV];

  always @(posedge cin or posedge reset) 
  begin
    if (reset) counter <= 0;
    else counter <= counter + 1;
  end
endmodule