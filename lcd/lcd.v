`include "serialize.v"

module scalescreen(input cin, input reset, 
                   input [4:0] red, input [5:0] green, input [4:0] blue, 
                   output sda, output scl, output cs, output reg rs, 
                   output vsync, output hsync, 
                   output [$clog2(HEIGHT/SCALE)-1:0] vpos, output [$clog2(WIDTH/SCALE)-1:0] hpos);
  parameter SCALE = 2;
  parameter WIDTH = 320;
  parameter HEIGHT = 240;

  wire [$clog2(WIDTH)-1:0] hp;
  wire [$clog2(HEIGHT)-1:0] vp;
  assign vpos = vp >> (SCALE - 1);
  assign hpos = hp >> (SCALE - 1);

  lcd #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) lcd0(.cin, .reset, .red, .green, .blue, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos(vp), .hpos(hp));
endmodule

module lcd(input cin, input reset, 
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

  assign hsync = hpos == 0;
  assign vsync = state == 2;
  
  wire [15:0] color = { red, green, blue };

  // LCD Protocol
  reg irdy;
  reg [2:0] state = 0;
  reg [7:0] dataout;
    
  serialize #(.SCL_MODE(0), .WIDTH(8), .CLK_DIV(0)) ser(
    .cin(!cin),
    .reset,
    .data(dataout),
    .sda,
    .scl,
    .irdy,
    .ordy(cs)
  );

  // LCD INITIALISATION
  reg [7:0] data [0:INIT_SIZE];
  reg       cmd  [0:INIT_SIZE];
  reg [3:0] counter;  
  reg [15:0] waittimer;

  initial $readmemh("setup.hex", data);
  initial $readmemh("setup_type.hex", cmd);
  
  always @(posedge cs or posedge reset)
    begin
      if (reset) begin
        counter <= 0;
        state <= 0;
        rs <= 1;
        dataout <= 0;
        pos <= 0;
        hpos <= 0;
        vpos <= 0;
        irdy <= 1'b1;
      end
      else
        begin
          case (state)
            0: begin
              rs <= 0;
              dataout <= 8'h11;
              waittimer <= 16'hFFFF;
              state <= 4;
            end
            4: begin
              if (waittimer > 0) waittimer <= waittimer - 1;
              else state <= 1;
            end
            1: begin 
              if (counter < INIT_SIZE) counter <= counter + 1;
              else state <= 2;
              rs <= cmd[counter] & 1'b1;
              dataout <= data[counter];
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

              if (pos < RESOLUTION) begin
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