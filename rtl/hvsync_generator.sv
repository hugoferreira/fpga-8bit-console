module hvsync_generator(
    input logic clk, input logic reset, output logic hsync, output logic vsync, 
    output logic display_on, output logic [7:0] hpos, output logic [6:0] vpos);

  // horizontal constants
  parameter H_DISPLAY       = 160; // horizontal display width
  parameter H_BACK          =   0; // horizontal left border (back porch)
  parameter H_FRONT         =   0; // horizontal right border (front porch)
  parameter H_SYNC          =   1; // horizontal sync width
  // vertical constants
  parameter V_DISPLAY       = 120; // vertical display height
  parameter V_TOP           =   0; // vertical top border
  parameter V_BOTTOM        =   0; // vertical bottom border
  parameter V_SYNC          =   1; // vertical sync # lines
  // derived constants
  parameter H_SYNC_START    = H_DISPLAY + H_FRONT;
  parameter H_SYNC_END      = H_DISPLAY + H_FRONT + H_SYNC - 1;
  parameter H_MAX           = H_DISPLAY + H_BACK + H_FRONT + H_SYNC - 1;
  parameter V_SYNC_START    = V_DISPLAY + V_BOTTOM;
  parameter V_SYNC_END      = V_DISPLAY + V_BOTTOM + V_SYNC - 1;
  parameter V_MAX           = V_DISPLAY + V_TOP + V_BOTTOM + V_SYNC - 1;

  wire hmaxxed = (hpos === H_MAX) | reset;	// set when hpos is maximum
  wire vmaxxed = (vpos === V_MAX) | reset;	// set when vpos is maximum
  
  // horizontal position counter
  always_ff @(posedge clk)
  begin
    hsync <= (hpos >= H_SYNC_START && hpos <= H_SYNC_END);
    if (hmaxxed) hpos <= 0;
    else hpos <= hpos + 1;
  end

  // vertical position counter
  always_ff @(posedge clk)
  begin
    vsync <= (vpos >= V_SYNC_START && vpos <= V_SYNC_END);
    if (hmaxxed)
      if (vmaxxed) vpos <= 0;
      else vpos <= vpos + 1;
  end
  
  // display_on is set when beam is in "safe" visible frame
  assign display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);
endmodule