`include "textbuffer/textbuffer.v"
`include "sprites/sprite.v"
`include "lcd/palette.v"
`include "lcd/lcd.v"

/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        25.000 MHz
 * Requested output frequency:   60.000 MHz
 * Achieved output frequency:    60.156 MHz
 */

module master_clk (input cin, output cout, output locked);
  SB_PLL40_CORE #(
      .FEEDBACK_PATH("SIMPLE"),
      .DIVR(4'b0001),		// DIVR =  1
      .DIVF(7'b1001100),	// DIVF = 76
      .DIVQ(3'b100),		// DIVQ =  4
      .FILTER_RANGE(3'b001)	// FILTER_RANGE = 1
    ) uut (
      .LOCK(locked),
      .RESETB(1'b1),
      .BYPASS(1'b0),
      .REFERENCECLK(cin),
      .PLLOUTCORE(cout)
  );
endmodule

module slower_clk (input cin, input reset, output cout);
  reg [1:0] counter = 2'b00;
  wire cout = counter == counter[1];
  always @(posedge cin or posedge reset)
  begin
    if (reset) counter <= 2'b00;
    else counter <= counter + 1;
  end
endmodule

module control(input clk, input reset, input vsync, output reg [15:0] addr, output reg [7:0] data, output reg rw);
  reg [7:0] letter;
  reg [3:0] color;
  reg [7:0] pos;
  reg [1:0] delay;
  
  always @(posedge clk or posedge reset)
  begin
    if (reset) begin
      letter  <= 0;
      color   <= 0;
      pos     <= 80;
      delay   <= 2'b00;
    end
    else begin
      if (vsync) begin
        if (delay !== 2'b11) delay <= delay + 1;

        // Update Character RAM
        case (delay) 
          2'b00: begin
            addr <= 16'hF003 + 16'h200;
            color <= color + 1;
            data <= { 4'b0000, color };
            rw <= 1;
          end 
          2'b01: begin
            addr <= 16'hEFF8;
            pos <= pos - 1;
            data <= pos;
            rw <= 1;
          end
          2'b10: begin
            addr <= 16'hF005;
            letter <= letter + 1;
            data <= letter;
            rw <= 1;
          end
          default: rw <= 0;
        endcase
      end else delay <= 2'b00;
    end
  end  
endmodule

module chip(input cin, input reset, output sda, output scl, output cs, output rs);
  wire clk;
  wire videoclk;
  master_clk clk0(.cin, .cout(videoclk));
  slower_clk clk1(.cin(videoclk), .cout(clk), .reset(~reset));

  // Basic Video Signals 
  wire vsync;
  wire hsync;
  wire [6:0] vpos;
  wire [7:0] hpos;
  wire [4:0] red   = sr | txtr; 
  wire [5:0] green = sg | txtg; 
  wire [4:0] blue  = sb | txtb; 
  scalescreen lcd0(.clk, .reset(~reset), .red, .green, .blue, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos, .hpos); 

  // Bus(es) and  Memory Mapping
  wire [15:0] addr;

  wire        rw;
  wire [7:0]  cpu_do;
  // wire [7:0]  cpu_di = tb_oe ? tb_do : (sp_oe ? sp_do : 8'h0);

  wire        tb_cs = addr === 16'b1111_xxxx_xxxx_xxxx;
  wire        tb_oe = tb_cs & ~rw;
  wire [7:0]  tb_do;

  wire        sp_cs = addr === 16'b1110_1111_1111_xxxx;
  wire        sp_oe = sp_cs & ~rw;
  wire [7:0]  sp_do;
  
  // Text Video Buffer  
  wire [3:0] text_color;
  wire [4:0] txtr; 
  wire [5:0] txtg; 
  wire [4:0] txtb; 
  textbuffer tb(.clk(~videoclk), .reset(~reset), .addr(addr[9:0]), .cs(tb_cs), .rw, .di(cpu_do), .dout(tb_do), .hpos, .vpos, .vsync, .hsync, .color(text_color));
  palette pal_text(.clk(videoclk), .color(text_color), .r(txtr), .g(txtg), .b(txtb));

  // Video Sprites  
  wire [4:0] sr;
  wire [5:0] sg; 
  wire [4:0] sb; 
  wire pixel;
  sprite s0(.clk(~videoclk), .reset(~reset), .addr(addr[3:0]), .cs(sp_cs), .rw, .di(cpu_do), .dout(sp_do), .hpos, .vpos, .vsync, .pixel);  
  palette pal_sprite(.clk(videoclk), .color(pixel ? 4'h9 : 4'h0), .r(sr), .g(sg), .b(sb));

  // Others
  control c0(.clk, .reset(~reset), .vsync, .addr, .data(cpu_do), .rw);
endmodule
