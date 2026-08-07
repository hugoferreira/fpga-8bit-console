`include "serialize.sv"

// Parameters come BEFORE the port list on purpose. They used to be declared in
// the module body while the ports referenced them, which yosys and Verilator
// accept but iverilog does not:
//
//   rtl/lcd.sv:7: error: Unable to bind wire/reg/memory `WIDTH' in `lcd'
//
// That is why this file had no bench for so long - it could not be elaborated
// by the simulator the rest of the benches use. rtl/lcd_tb.sv is that bench.
module lcd #(parameter WIDTH = 320,
             parameter HEIGHT = 240,
             parameter RGBSIZE = 16,
             // Byte-times spent in reset_lcd before initialisation begins. The
             // panel needs the real 65536; a bench does not, and simulating
             // them costs ~590k clocks before anything interesting happens.
             // Overriding this is the ONLY thing rtl/lcd_tb.sv changes about
             // the design under test.
             parameter RESET_WAIT = 16'hFFFF)
          (input bit clk, input bit reset,
           input logic [RGBSIZE-1:0] rgb,
           output bit sda, output bit scl, output bit cs, output bit rs,
           output bit vsync, output bit hsync,
           output logic [$clog2(HEIGHT)-1:0] vpos, output logic [$clog2(WIDTH)-1:0] hpos);

  localparam INIT_SIZE = 15;
  localparam WORD = 2;
  localparam RESOLUTION = WIDTH*HEIGHT*WORD;

  // Scanlines and Pixels
  logic [$clog2(WIDTH*HEIGHT):0] pos;

  assign hsync = hpos == WIDTH-1;

  // LCD Protocol
  bit irdy;
  logic [7:0] dataout;
  enum logic [1:0] { reset_lcd, initialize, start_frame, send_frame } state;

  // Declared after `state`, not before it: iverilog requires declaration
  // before use and rejected the original ordering.
  assign vsync = state == start_frame;


  serialize #(.SCL_MODE(0), .WIDTH(8)) ser(.cin(!clk), .reset, .data(dataout), .sda, .scl, .irdy, .ordy(cs));

  // LCD INITIALISATION
  logic  [3:0] counter;  
  logic [15:0] waittimer;
  logic  [8:0] rom [0:INIT_SIZE];
  wire   [8:0] command = rom[counter];
  
  initial $readmemh("setup_st7789_565.hex", rom);
  
  always_ff @(posedge cs)
    begin
      if (reset) begin
        dataout <= 0;
        counter <= 0;
        state <= reset_lcd;
        irdy <= 1'b1;
        waittimer <= RESET_WAIT;
      end
      else
        begin
          case (state)
            reset_lcd: begin
              rs <= 0;
              dataout <= 8'h11;              
              waittimer <= waittimer - 1;
              if (waittimer == 0) state <= initialize;
            end
            
            initialize: begin 
              if (counter == INIT_SIZE) state <= start_frame;
              counter <= counter + 1;
              rs <= command[8];
              dataout <= command[7:0];
            end

            start_frame: begin
              pos <= 0;
              hpos <= 0;
              vpos <= 0;
              rs <= 0;
              dataout <= 8'h2C;
              state <= send_frame;
            end

            send_frame: begin
              rs <= 1;
              dataout <= pos[0] ? rgb[7:0] : rgb[15:8];

              if (pos != RESOLUTION) begin
                pos <= pos + 1;
                if (pos[1]) begin
                  hpos <= hpos + 1;
                  if (hpos == (WIDTH-1)) begin
                    hpos <= 0;
                    vpos <= vpos + 1;
                  end             
                end 
              end else state <= start_frame;
            end
          endcase
        end
    end
endmodule