module clocks(input bit clk, output bit reset, output bit masterclk, output bit videoclk, output bit cpuclk);
  assign reset = ~locked;
  logic locked;

  logic clk2;       
	/* SB_GB clk2_gbuf (
		.USER_SIGNAL_TO_GLOBAL_BUFFER(clk2),
		.GLOBAL_BUFFER_OUTPUT(videoclk)
	); */
  assign videoclk = clk2;

  logic clk8;       
	/* SB_GB clk8_gbuf (
		.USER_SIGNAL_TO_GLOBAL_BUFFER(clk8),
		.GLOBAL_BUFFER_OUTPUT(cpuclk)
	); */
  assign cpuclk = clk8;

  pll clk0(.clock_in(clk), .clock_out(masterclk), .locked);
  slower_clk clocks(.cin(masterclk), .clk_div2(clk2), .clk_div256(clk8), .reset);

endmodule 
