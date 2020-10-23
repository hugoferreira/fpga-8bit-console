/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        25.000 MHz
 * Requested output frequency:   20.000 MHz
 * Achieved output frequency:    19.922 MHz
 */

module lcd_clk (input cin, output cout, output locked);
  SB_PLL40_CORE #(
      .FEEDBACK_PATH("SIMPLE"),
      .DIVR(4'b0001),		    // DIVR =  1
      .DIVF(7'b0110010),	  // DIVF = 50
      .DIVQ(3'b101),		    // DIVQ =  5
      .FILTER_RANGE(3'b001)	// FILTER_RANGE = 1
    ) uut (
      .LOCK(locked),
      .RESETB(1'b1),
      .BYPASS(1'b0),
      .REFERENCECLK(cin),
      .PLLOUTCORE(cout)
  );
endmodule

module lcd(input cin, input reset, input [4:0] red, input [5:0] green, input [4:0] blue, output sda, output scl, output cs, output reg rs, output vsync, output hsync, output [VMSB-VLSB:0] vpos, output [VLSB-WORD:0] hpos);
  localparam INIT_SIZE = 15;
  localparam WIDTH = 128;
  localparam HEIGHT = 160;
  localparam WORD = 2;
  localparam RESOLUTION = WIDTH*HEIGHT*WORD;
  localparam VLSB = $clog2(WIDTH*WORD);
  localparam VMSB = VLSB + $clog2(HEIGHT) - 1;

  // Scanlines and Pixels
  reg [VMSB:0] pos;
  assign vpos  = pos[VMSB:VLSB];
  assign hpos  = pos[VLSB:WORD-1];
  assign hsync = hpos == 0;
  assign vsync = state == 2;
  
  wire [15:0] color = { red, green, blue };

  // LCD Protocol
  reg irdy;
  reg [2:0] state = 0;
  reg [7:0] dataout;
  
  wire clk;
  wire locked;
  lcd_clk spiclk(.cin, .cout(clk), .locked);

  serialize #(.SCL_MODE(0), .WIDTH(8), .CLK_DIV(0)) ser(
    .cin(clk),
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
        irdy <= 1'b1;
      end
      else
        begin
          case (state)
            0: begin
              rs <= 0;
              dataout <= 8'h11;
              state <= 1;
            end
            1: begin 
              if (counter < INIT_SIZE) counter <= counter + 1;
              else state <= 2;
              rs <= cmd[counter] & 1'b1;
              dataout <= data[counter];
            end
            2: begin
              pos <= 0;
              rs <= 0;
              dataout <= 8'h2C;
              state <= 3;
            end
            3: begin
              rs <= 1;
              dataout <= pos[0] ? color[VLSB:0] : color[VMSB:VLSB];

              if (pos < RESOLUTION) pos <= pos + 1;
              else state <= 2;
            end
          endcase
        end
    end
endmodule