module textbuffer(input logic clk, input logic reset, 
                  input logic cs, input logic rw, input logic [$clog2(WIDTH*HEIGHT):0] addr, input logic [7:0] di, output logic [7:0] dout, 
                  input logic [7:0] hpos, input logic [6:0] vpos, input logic vsync, input logic hsync, 
                  output logic [3:0] color);
  
  localparam WIDTH = 20, HEIGHT = 15;
  
  logic [7:0] charram [0:(1<<9)-1];   // nomem2reg
  logic [7:0] attrram [0:(1<<9)-1];   // nomem2reg
  logic [7:0] fontrom [0:(1<<11)-1];  // nomem2reg

  initial $readmemh("videoram.hex", charram);
  initial $readmemh("attrram.hex",  attrram);
  initial $readmemh("font_cp437_8x8.hex", fontrom);

  enum logic [1:0] { ram_addr, fetch_ram, fetch_rom, display } state;

  logic [$clog2(WIDTH*HEIGHT)-1:0] pos;
  logic [10:0] char;
  logic [7:0]  attr;
  logic [7:0]  bits;
  logic        sel;
  logic [8:0]  address;

  assign { sel, address } = addr;
  
  always_ff @(posedge clk)
  begin
    if (reset) begin
      state <= ram_addr;
    end else begin
      state <= state + 1;
      case (state)  
        ram_addr:  
          pos <= vpos[6:3] * 20 + { 4'b0000, hpos[7:3] };

        fetch_ram: 
        begin
          char <= { charram[pos], vpos[2:0] };
          attr <= attrram[pos];
        end

        fetch_rom: 
          bits <= fontrom[char];
        
        display: 
          color <= bits[~hpos[2:0]] ? attr[3:0] : attr[7:4];
      endcase
    end
  end

  logic [7:0] read_attr, read_char;
  assign dout = sel ? read_char : read_attr;
  
  always_ff @(posedge clk)
    if (sel & cs & ~rw) read_attr <= attrram[address];
      
  always_ff @(posedge clk)
    if (sel & cs & rw) attrram[address] <= di;

  always_ff @(posedge clk)
    if (~sel & cs & ~rw) read_char <= charram[address];
  
  always_ff @(posedge clk)
    if (~sel & cs & rw) charram[address] <= di; 
endmodule