module slower_clk(input logic cin, input logic reset, output logic clk_div2, output logic clk_div4);
  always_ff @(posedge cin)
    clk_div2 <= ~clk_div2;

  always_ff @(posedge clk_div2)
    clk_div4 <= ~clk_div4;
endmodule