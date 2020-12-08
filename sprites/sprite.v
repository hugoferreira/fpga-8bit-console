module sprite(input clk, input reset, input we, input [3:0] address, input [7:0] data, input [7:0] hpos, input [6:0] vpos, input vsync, output pixel);
  reg [7:0] spriteram[0:9];

  wire [7:0] sprite_hpos = spriteram[8];  // X
  wire [7:0] sprite_vpos = spriteram[9];  // Y

  initial $readmemh("spriteram.hex", spriteram); 

  wire sprite_on = ((hpos - sprite_hpos)) < 8 & ((vpos - sprite_vpos) < 8);
  assign pixel = sprite_on & spriteram[vpos - sprite_vpos][hpos - sprite_hpos];

  always @(posedge clk)
  begin
    if (we) begin
      spriteram[address] <= data;
    end
  end
endmodule