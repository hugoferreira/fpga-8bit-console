module sprite(input bit clk, input bit reset, 
              input bit cs, input bit rw, input logic [3:0] addr, input logic [7:0] di, output logic [7:0] dout, 
              input logic [7:0] hpos, input logic [6:0] vpos, input bit vsync, input bit hsync, 
              output bit pixel);

  logic [7:0] spriteram[0:9];
  initial $readmemb("./rtl/spriteram.bin", spriteram); 

  enum logic [1:0] { scanv, scanh, fetch, display } state;
  logic [7:0] sprite;
  logic [7:0] scanhpos;
  logic [7:0] scanvpos;
  logic       sprite_on;
  
  // Map the 4-bit address to sprite register index
  // $4008 => X position (8)
  // $4009 => Y position (9)
  logic [3:0] sprite_reg_addr;
  
  // Properly decode the address to sprite register index
  always_comb begin
    case (addr)
      4'h8: sprite_reg_addr = 4'd8;  // X position
      4'h9: sprite_reg_addr = 4'd9;  // Y position
      default: sprite_reg_addr = addr;
    endcase
  end
  
  // Display logic - continues regardless of chip select
  always_ff @(posedge clk)
  begin
    if (reset) begin
      state <= scanv;
    end else begin
      case (state)
        scanv: state <= scanh;
        scanh: state <= fetch;
        fetch: state <= display;
        display: state <= scanv;
      endcase
      
      case (state)
        scanv: scanvpos <= vpos - spriteram[9];

        scanh: begin
          scanhpos <= hpos - spriteram[8];
        end

        fetch: begin
          sprite <= spriteram[{1'b0, scanvpos[2:0]}];
          sprite_on <= scanhpos < 8 & scanvpos < 8;
        end
        
        display: pixel <= sprite_on & sprite[scanhpos[2:0]];
      endcase
    end
  end

  // CPU read access - only when chip select is active
  always_ff @(posedge clk)
    if (cs & ~rw) begin
      dout <= spriteram[sprite_reg_addr];
      $display("Sprite: CPU reading register %d at $400%01X = %02X", 
               sprite_reg_addr, addr, spriteram[sprite_reg_addr]);
    end

  // CPU write access - only when chip select is active
  always_ff @(posedge clk)
    if (cs & rw) begin
      spriteram[sprite_reg_addr] <= di;
      $display("Sprite: CPU writing register %d at $400%01X = %02X", 
               sprite_reg_addr, addr, di);
    end
endmodule