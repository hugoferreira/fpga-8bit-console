`include "textbuffer/textbuffer.v"
`include "sprites/sprite.v"
`include "lcd/palette.v"
`include "lcd/lcd.v"
`include "ram.v"



module control(input clk, input reset, input vsync, output reg [15:0] addr, output reg [7:0] data, input [7:0] din, output reg rw);
  reg [7:0] letter;
  reg [3:0] color;
  reg [7:0] pos;
  reg [2:0] delay;
  
  always @(posedge clk or posedge reset)
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

  wire tb_cs  = addr === 16'b1111_xxxx_xxxx_xxxx;
  wire sp_cs  = addr === 16'b1110_1111_1111_xxxx;
  wire ram_cs = addr === 16'b0000_xxxx_xxxx_xxxx;

  wire tb_oe  = tb_cs & ~rw;
  wire sp_oe  = sp_cs & ~rw;
  wire ram_oe = ram_cs & ~rw;
endmodule

module chip(input clk_0, input clk_1, input clk_2, input reset, output sda, output scl, output cs, output rs);
  // Basic Video Signals 
  wire vsync;
  wire hsync;
  wire [6:0] vpos;
  wire [7:0] hpos;
  wire [4:0] red   = sr | txtr; 
  wire [5:0] green = sg | txtg; 
  wire [4:0] blue  = sb | txtb; 
  scalescreen lcd0(.clk(clk_2), .reset, .red, .green, .blue, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos, .hpos); 

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

  // Text Video Buffer  
  wire [3:0] text_color;
  wire [4:0] txtr; 
  wire [5:0] txtg; 
  wire [4:0] txtb; 
  textbuffer tb(.clk(~clk_1), .reset, .addr(addr[9:0]), .cs(tb_cs), .rw, .di(cpu_do), .dout(tb_do), .hpos, .vpos, .vsync, .hsync, .color(text_color));
  palette pal_text(.clk(clk_1), .color(text_color), .r(txtr), .g(txtg), .b(txtb));

  // Video Sprites  
  wire [4:0] sr;
  wire [5:0] sg; 
  wire [4:0] sb; 
  wire pixel;
  sprite s0(.clk(~clk_1), .reset, .addr(addr[3:0]), .cs(sp_cs), .rw, .di(cpu_do), .dout(sp_do), .hpos, .vpos, .vsync, .pixel);  
  palette pal_sprite(.clk(clk_1), .color(pixel ? 4'h9 : 4'h0), .r(sr), .g(sg), .b(sb));

  // 8x64kbit Async RAM, 
  RAM_async #(.A(12), .D(8)) ram (.clk(~clk_1), .cs(ram_cs), .rw, .addr(addr[11:0]), .di(cpu_do), .dout(ram_do));

  // Others
  control c0(.clk(clk_2), .reset, .vsync, .addr, .data(cpu_do), .din(cpu_di), .rw);
endmodule
