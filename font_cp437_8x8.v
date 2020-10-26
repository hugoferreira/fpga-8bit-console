// PC font (code page 437)
module font_cp437_8x8(input clk, input [10:0] addr, output [7:0] data);
  reg [7:0] bitarray[0:2047];
  initial $readmemh("font_cp437_8x8.hex", bitarray);

  always @(posedge clk)
    data <= bitarray[addr];
endmodule