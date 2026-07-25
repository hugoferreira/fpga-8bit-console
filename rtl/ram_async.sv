// Parameters precede the port list because the ports use them: declaring them
// after (as this did) is legal to Verilator and yosys but leaves iverilog
// unable to bind A and D, which is why `make test` never elaborated.
module ram_async #(parameter A = 16, D = 8, FILE = "ram.hex")
                (input bit clk, input bit cs, input bit rw,
                 input logic [A-1:0] addr, input logic [D-1:0] di,
                 output logic [D-1:0] dout);
    
  logic [D-1:0] mem [0:(1<<A)-1]; // synthesis nomem2reg
  initial begin
    $display("RAM: Loading memory from %s", FILE);
    $readmemh(FILE, mem);

    // The startup dumps below are guarded because they are the reason this
    // memory was never block RAM. A `$display` that reads `mem[...]` is an
    // ASYNCHRONOUS read port as far as yosys is concerned, and a memory with
    // an async read port cannot be a block RAM - so the whole array went to
    // fabric, which is how a 64 KB RAM became 1.7 M AND gates on a part with
    // 7680 logic cells. Verilator defines VERILATOR itself, so the simulator
    // keeps the dumps and synthesis does not pay for them.
`ifdef VERILATOR
    // Print reset vector and surrounding memory
    $display("RAM: Memory dump around reset vector:");
    $display("RAM: $FFF8: %02X %02X %02X %02X %02X %02X %02X %02X",
              mem[16'hFFF8], mem[16'hFFF9], mem[16'hFFFA], mem[16'hFFFB],
              mem[16'hFFFC], mem[16'hFFFD], mem[16'hFFFE], mem[16'hFFFF]);

    // Print program start area
    $display("RAM: Memory dump around program start ($0300):");
    $display("RAM: $0300: %02X %02X %02X %02X %02X %02X %02X %02X",
              mem[16'h0300], mem[16'h0301], mem[16'h0302], mem[16'h0303],
              mem[16'h0304], mem[16'h0305], mem[16'h0306], mem[16'h0307]);

    // Print the first few bytes of memory (zero page)
    $display("RAM: Memory dump of zero page ($0000-$000F):");
    $display("RAM: $0000: %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X",
              mem[16'h0000], mem[16'h0001], mem[16'h0002], mem[16'h0003],
              mem[16'h0004], mem[16'h0005], mem[16'h0006], mem[16'h0007],
              mem[16'h0008], mem[16'h0009], mem[16'h000A], mem[16'h000B],
              mem[16'h000C], mem[16'h000D], mem[16'h000E], mem[16'h000F]);
`endif

    // Force certain memory locations to known values for safety. This is
    // functional, not debug: a memory init port, which block RAM does support.
    mem[16'h0000] = 8'hEA; // NOP at $0000 instead of BRK
    mem[16'h0001] = 8'hEA; // NOP at $0001 instead of BRK
    mem[16'h0002] = 8'hEA; // NOP at $0002 instead of BRK
  end

  // Implement RAM with registered output
  logic [D-1:0] data_out_reg;
  
  // Register the read data on clock edge
  always_ff @(posedge clk) begin
    if (cs & ~rw)
      data_out_reg <= mem[addr];
  end

  // Handle writes
  always_ff @(posedge clk) begin
    if (cs & rw)
      mem[addr] <= di;
  end
  
  // Expose the registered data
  assign dout = data_out_reg;
  
endmodule