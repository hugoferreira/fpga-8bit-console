module sprite(input clk, input reset, 
              input cs, input rw, input [3:0] addr, input [7:0] di, output reg [7:0] dout, 
              input [7:0] hpos, input [6:0] vpos, input vsync, input hsync, 
              output reg pixel);

  reg [7:0] spriteram[0:9];
  initial $readmemh("spriteram.hex", spriteram); 

  reg [1:0] state;
  reg [7:0] sprite;
  reg [7:0] scanhpos;
  reg [7:0] scanvpos;
  reg sprite_on;
  
  always @(posedge clk)
  begin
    if (reset) begin
      state <= 0;
    end else begin
      state <= state + 1;
      case (state)
        2'b00: // Calculate if we are going to display the sprite
          scanvpos <= vpos - spriteram[9];

        2'b01: 
        begin
          scanhpos <= hpos - spriteram[8];
          sprite_on <= scanhpos < 8 & scanvpos < 8;
        end

        2'b10: // Fetch the sprite scanline
          sprite <= spriteram[{1'b0, scanvpos[2:0]}];

        2'b11: // Output pixel
          pixel <= sprite_on & sprite[scanhpos[2:0]];
      endcase
    end
  end

  always @(posedge clk)
    if (cs & ~rw) dout <= spriteram[addr];

  always @(posedge clk)
    if (cs & rw) spriteram[addr] <= di;
endmodule