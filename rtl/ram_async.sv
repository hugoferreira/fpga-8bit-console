module ram_async(input bit clk, input bit cs, input bit rw, 
                 input logic [A-1:0] addr, input logic [D-1:0] di, 
                 output logic [D-1:0] dout);
  parameter A = 16, D = 8, FILE = "ram.hex"; 
    
  logic [D-1:0] mem [0:(1<<A)-1]; // synthesis nomem2reg
  initial begin
    $readmemh(FILE, mem);
    
    // Print reset vector on initialization
    $display("RAM: Reset vector at $FFFC-$FFFD = %02X %02X (points to $%02X%02X)",
              mem[16'hFFFC], mem[16'hFFFD], mem[16'hFFFD], mem[16'hFFFC]);
    $display("RAM: Reset vector values as integers - FFFC=%0d, FFFD=%0d", 
              mem[16'hFFFC], mem[16'hFFFD]);
              
    // Add debugging for the program at 0x300
    $display("RAM: Program at $0300 starts with: %02X %02X %02X %02X",
              mem[16'h0300], mem[16'h0301], mem[16'h0302], mem[16'h0303]);
  end

  always_ff @(posedge clk)
    if (cs & ~rw) begin
      dout <= mem[addr];
      
      // Only print reset vector reads
      if (addr == 16'hFFFC || addr == 16'hFFFD)
        $display("Reset Vector Access: CPU reading from $%04X = %02X (decimal: %0d)", 
                  addr, mem[addr], mem[addr]);
      
      // Print when CPU reads from program start
      if (addr == 16'h0300 || addr == 16'h0301 || addr == 16'h0302)
        $display("Program Access: CPU reading from $%04X = %02X", addr, mem[addr]);
        
      // Also print when CPU reads from address 0x0002
      if (addr == 16'h0002)
        $display("CPU reading from $0002 = %02X", mem[addr]);
    end

  always_ff @(posedge clk)
    if (cs & rw) begin
      mem[addr] <= di;
      
      // Only print interesting writes
      if (addr >= 16'h4000 && addr <= 16'h4009)
        $display("Sprite Access: CPU wrote %02X to $%04X", di, addr);
    end
endmodule