module RAM_async(input clk, input cs, input rw, input [A-1:0] addr, input [D-1:0] di, output reg [D-1:0] dout);
  parameter A = 10;
  parameter D = 8; 
    
  reg [D-1:0] mem [0:(1<<A)-1]; // nomem2reg
  initial $readmemh("ram.hex", mem); 

  always @(posedge clk) begin
    if (cs & ~rw) dout <= mem[addr];
    else if (cs & rw) mem[addr] <= di;
  end
endmodule