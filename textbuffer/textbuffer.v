module textbuffer(input clk, input reset, 
                  input cs, input rw, input [$clog2(WIDTH*HEIGHT):0] addr, input [7:0] di, output reg [7:0] dout, 
                  input [7:0] hpos, input [6:0] vpos, input vsync, input hsync, 
                  output reg [3:0] color);
  
  parameter WIDTH = 20;
  parameter HEIGHT = 15;

  reg [7:0] charram [0:(1<<9)-1];
  reg [7:0] attrram [0:(1<<9)-1];
  reg [7:0] fontrom [0:(1<<11)-1];

  initial $readmemh("videoram.hex", charram);
  initial $readmemh("attrram.hex",  attrram);
  initial $readmemh("font_cp437_8x8.hex", fontrom);

  wire [8:0]  address = addr[8:0];
  reg  [$clog2(WIDTH*HEIGHT)-1:0] pos;
  reg  [10:0] char;
  reg  [7:0]  attr;
  reg  [1:0]  state;
  reg  [7:0]  bits;

  always @(posedge clk or posedge reset)
  begin
    if (reset) begin
      state <= 0;
    end else begin
      state <= state + 1;
      case (state)
        2'b00: // Calculate position
          pos <= vpos[6:3] * WIDTH + { 4'b0000, hpos[7:3] };

        2'b01: // Fetch from both display RAMs
        begin
          char <= { charram[pos], vpos[2:0] };
          attr <= attrram[pos];
        end

        2'b10: // Fetch from font ROM
          bits <= fontrom[char];
        
        2'b11: // Output pixel
          color <= bits[~hpos[2:0]] ? attr[3:0] : attr[7:4];
      endcase
    end
  end
  
  always @(posedge clk)
  begin
    if (cs) casez (addr)
      10'b0?????????: begin
        if (~rw) dout <= charram[address];
        else charram[address] <= di;
      end 

      10'b1?????????: begin
        if (~rw) dout <= attrram[address];
        else attrram[address] <= di;
      end        
    endcase
  end
endmodule