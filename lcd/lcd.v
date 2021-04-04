`include "serialize.v"

module scalescreen(input clk, input reset, 
                   input [4:0] red, input [5:0] green, input [4:0] blue, 
                   output sda, output scl, output cs, output reg rs, 
                   output vsync, output hsync, 
                   output [$clog2(HEIGHT)-SCALE:0] vpos, output [$clog2(WIDTH)-SCALE:0] hpos);
  parameter SCALE = 2, WIDTH = 320, HEIGHT = 240, SCANLINES = 0;

  wire [$clog2(WIDTH)-1:0] hp;
  wire [$clog2(HEIGHT)-1:0] vp;
  assign vpos = vp[$clog2(HEIGHT)-1:SCALE-1];
  assign hpos = hp[$clog2(WIDTH)-1:SCALE-1];
  
  generate 
    if (SCANLINES == 0) begin
      lcd #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) lcd0(.clk, .reset, .red, .green, .blue, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos(vp), .hpos(hp));
    end else begin
      wire [4:0] nr = vp[0] ? red : 0;
      wire [5:0] ng = vp[0] ? green : 0;
      wire [4:0] nb = vp[0] ? blue : 0;

      lcd #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) lcd0(.clk, .reset, .red(nr), .green(ng), .blue(nb), .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos(vp), .hpos(hp));
    end
  endgenerate

endmodule

module lcd(input clk, input reset, 
           input [4:0] red, input [5:0] green, input [4:0] blue, 
           output sda, output scl, output cs, output reg rs, 
           output vsync, output hsync, 
           output reg [$clog2(HEIGHT)-1:0] vpos, output reg [$clog2(WIDTH)-1:0] hpos);

  parameter WIDTH = 320;
  parameter HEIGHT = 240;

  localparam INIT_SIZE = 15;
  localparam WORD = 2;
  localparam RESOLUTION = WIDTH*HEIGHT*WORD;

  // Scanlines and Pixels
  reg [$clog2(WIDTH*HEIGHT):0] pos;

  assign hsync = hpos == WIDTH-1;
  assign vsync = state == 2;
  
  wire [15:0] color = { red, green, blue };

  // LCD Protocol
  reg irdy;
  reg [1:0] state = 0;
  reg [7:0] dataout;
    
  serialize #(.SCL_MODE(0), .WIDTH(8)) ser(.cin(!clk), .reset, .data(dataout), .sda, .scl, .irdy, .ordy(cs));

  // LCD INITIALISATION
  reg  [3:0]  counter;  
  reg  [15:0] waittimer;
  reg  [8:0]  rom [0:INIT_SIZE];
  wire [8:0]  command = rom[counter];
  
  initial $readmemh("setup.hex", rom);
  
  always @(posedge cs or posedge reset)
    begin
      if (reset) begin
        dataout <= 0;
        counter <= 0;
        state <= 0;
        irdy <= 1'b1;
        waittimer <= 16'hFFFF;
      end
      else
        begin
          case (state)
            0: begin
              rs <= 0;
              dataout <= 8'h11;              
              waittimer <= waittimer - 1;
              if (waittimer == 0) state <= 1;
            end
            1: begin 
              if (counter == INIT_SIZE) state <= 2;
              counter <= counter + 1;
              rs <= command[8];
              dataout <= command[7:0];
            end
            2: begin
              pos <= 0;
              hpos <= 0;
              vpos <= 0;
              rs <= 0;
              dataout <= 8'h2C;
              state <= 3;
            end
            3: begin
              rs <= 1;
              dataout <= pos[0] ? color[7:0] : color[15:8];

              if (pos != RESOLUTION) begin
                pos <= pos + 1;
                if (pos[1]) begin
                  hpos <= hpos + 1;
                  if (hpos == (WIDTH-1)) begin
                    hpos <= 0;
                    vpos <= vpos + 1;
                  end             
                end 
              end else state <= 2;
            end
          endcase
        end
    end
endmodule