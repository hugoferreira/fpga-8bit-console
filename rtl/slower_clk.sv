module slower_clk(input logic cin, input logic reset, 
    output logic clk_div2, output logic clk_div4,
    output logic clk_div8, output logic clk_div16,
    output logic clk_div32, output logic clk_div64,
    output logic clk_div128, output logic clk_div256
);

  always_ff @(posedge cin)
    clk_div2 <= ~clk_div2;

  always_ff @(posedge clk_div2)
    clk_div4 <= ~clk_div4;

  always_ff @(posedge clk_div4)
    clk_div8 <= ~clk_div8;

  always_ff @(posedge clk_div8)
    clk_div16 <= ~clk_div16;

  always_ff @(posedge clk_div16)
    clk_div32 <= ~clk_div32;

  always_ff @(posedge clk_div32)
    clk_div64 <= ~clk_div64;

  always_ff @(posedge clk_div64)
    clk_div128 <= ~clk_div128;

  always_ff @(posedge clk_div128)
    clk_div256 <= ~clk_div256;
endmodule