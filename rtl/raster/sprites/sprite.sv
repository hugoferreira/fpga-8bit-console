module sprite(input bit clk, input bit reset, 
              input bit cs, input bit rw, input logic [3:0] addr, input logic [7:0] di, output logic [7:0] dout, 
              input logic [7:0] hpos, input logic [6:0] vpos, input bit vsync, input bit hsync, 
              output bit pixel);

  logic [7:0] spriteram[0:9];
  initial $readmemh("spriteram.hex", spriteram); 

  enum logic [1:0] { scanv, scanh, fetch, display } state;
  logic [7:0] sprite;
  logic [7:0] scanhpos;
  logic [7:0] scanvpos;
  logic       sprite_on;
  
  always_ff @(posedge clk)
  begin
    if (reset) begin
      state <= scanv;
    end else begin
      state <= state + 1;
      case (state)
        scanv: scanvpos <= vpos - spriteram[9];

        scanh: begin
          scanhpos <= hpos - spriteram[8];
          sprite_on <= scanhpos < 8 & scanvpos < 8;
        end

        fetch: sprite <= spriteram[{1'b0, scanvpos[2:0]}];
        display: pixel <= sprite_on & sprite[scanhpos[2:0]];
      endcase
    end
  end

  always_ff @(posedge clk)
    if (cs & ~rw) dout <= spriteram[addr];

  always_ff @(posedge clk)
    if (cs & rw) spriteram[addr] <= di;
endmodule