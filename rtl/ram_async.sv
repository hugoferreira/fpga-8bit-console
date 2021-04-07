module ram_async(input bit clk, input bit cs, input bit rw, 
                 input logic [A-1:0] addr, input logic [D-1:0] di, 
                 output logic [D-1:0] dout);
  parameter A = 10, D = 8; 
    
  logic [D-1:0] mem [0:(1<<A)-1]; // synthesis nomem2reg
  initial $readmemh("ram.hex", mem); 

  always_ff @(posedge clk)
    if (cs & ~rw) dout <= mem[addr];

  always_ff @(posedge clk)
    if (cs & rw) mem[addr] <= di;
endmodule