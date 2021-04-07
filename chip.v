`include "raster/textbuffer/textbuffer.v"
`include "raster/sprites/sprite.v"
`include "raster/palette.v"
`include "ram.v"

module control(input clk, input reset, input vsync, output reg [15:0] addr, output reg [7:0] data, input [7:0] din, output reg rw);
  reg [7:0] letter;
  reg [3:0] color;
  reg [7:0] pos;
  reg [2:0] delay;
  
  always @(posedge clk)
  begin
    if (reset) begin
      letter  <= 0;
      color   <= 0;
      delay   <= 3'b000;
      rw      <= 0;
    end
    else begin
      if (vsync) begin
        if (delay != 3'b110) delay <= delay + 1;

        // Update Character RAM
        case (delay) 
          3'b000: begin
            addr <= 16'h0000;
            rw <= 0;
          end
          3'b001: begin
            pos <= din;
          end
          3'b010: begin
            addr <= 16'hEFF8;
            pos <= pos - 1;
            data <= pos;
            rw <= 1;
          end
          3'b011: begin
            addr <= 16'hF003 + 16'h200;
            color <= color + 1;
            data <= { 4'b0000, color };
            rw <= 1;
          end 
          3'b100: begin
            addr <= 16'h0000;
            data <= pos;
            rw <= 1;
          end
          3'b101: begin
            addr <= 16'hF005;
            letter <= letter + 1;
            data <= letter;
            rw <= 1;
          end
          default: rw <= 0;
        endcase
      end else delay <= 3'b000;
    end
  end  
endmodule

module addressdecoder(input [15:0] addr, input rw, 
                      input [7:0] tb_do, input [7:0] sp_do, input [7:0] ram_do,  
                      output [7:0] cpu_di,
                      output tb_cs, output sp_cs, output ram_cs);

  wire [2:0] peripheral = { tb_oe, sp_oe, ram_oe };

  function [7:0] p(input [2:0] code);
    case (code)
        3'b001  : p = ram_do;
        3'b100  : p = tb_do;
        default : p = 8'b0;
    endcase
  endfunction

  assign cpu_di = p(peripheral);

  assign tb_cs  = addr[15:12] == 04'b1111;
  assign sp_cs  = addr[15:04] == 12'b1110_1111_1111;
  assign ram_cs = addr[15:12] == 04'b0000;

  wire tb_oe  = tb_cs & ~rw;
  wire sp_oe  = sp_cs & ~rw;
  wire ram_oe = ram_cs & ~rw;
endmodule

module chip(input clk_1, input clk_2, input reset, 
            input vsync, input hsync, input [6:0] vpos, input [7:0] hpos, 
            output [RGB-1:0] rgb);

  parameter RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";

  // Addressing and Peripherals
  wire        rw;
  wire [15:0] addr;
  wire [7:0]  cpu_do;
  wire [7:0]  cpu_di;
  wire [7:0]  tb_do;
  wire        tb_cs;    
  wire [7:0]  sp_do;
  wire        sp_cs;    
  wire [7:0]  ram_do;
  wire        ram_cs;    

  addressdecoder decoder(.addr, .rw, .cpu_di, .tb_do, .sp_do, .ram_do, .tb_cs, .sp_cs, .ram_cs);

  // 8x64kbit Async RAM
  RAM_async #(.A(12), .D(8)) ram (.clk(~clk_1), .cs(ram_cs), .rw, .addr(addr[11:0]), .di(cpu_do), .dout(ram_do));

  // Control Unit
  control c0(.clk(clk_1), .reset, .vsync, .addr, .data(cpu_do), .din(cpu_di), .rw);

  // Text Video Buffer  
  wire [3:0] text_color;
  wire [RGB-1:0] trgb; 
  textbuffer tb(.clk(~clk_1), .reset, .addr(addr[9:0]), .cs(tb_cs), .rw, .di(cpu_do), .dout(tb_do), .hpos, .vpos, .vsync, .hsync, .color(text_color));
  palette #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE(FILE)) pal_text(.clk(clk_1), .color(text_color), .rgb(trgb));

  // Video Sprites  
  wire pixel;
  wire [RGB-1:0] srgb;
  sprite s0(.clk(~clk_1), .reset, .addr(addr[3:0]), .cs(sp_cs), .rw, .di(cpu_do), .dout(sp_do), .hpos, .vpos, .hsync, .vsync, .pixel);  
  palette #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE(FILE)) pal_sprite(.clk(clk_1), .color(pixel ? 4'h9 : 4'h0), .rgb(srgb));

  // Basic Video Signals 
  assign rgb = srgb | trgb; 
endmodule
