/* verilator lint_off UNOPTFLAT */
`include "chip.sv"
`include "por.sv"
`include "slower_clk.sv"
// The VERILATOR macro is predefined by the Verilator tool itself; define it
// here only for other tools (redefining is fatal DEFOVERRIDE in Verilator 5)
`ifndef VERILATOR
`define VERILATOR
`endif

module top(input logic clk_i, input logic rst_i, input logic [7:0] buttons,
           output logic hsync, output logic vsync, output logic [23:0] rgb,
           output logic signed [15:0] audio, output logic [63:0] psg_dbg);
  localparam WIDTH = 320, HEIGHT = 240;

  logic [7:0] hpos;
  logic [6:0] vpos;

  // Pixel clock: divide by 3. The PPU display pipeline needs 3 clocks per
  // pixel (read, capture, stable); the old /4 dated from the retired
  // textbuffer's 4-state renderer and cost 25% more simulation work.
  logic [1:0] div3 = 0;
  logic       clk_3 = 0;
  always_ff @(posedge clk_i) begin
    if (div3 == 2) begin
      div3 <= 0;
      clk_3 <= 1;
    end else begin
      div3 <= div3 + 1;
      clk_3 <= 0;
    end
  end

  /* verilator lint_off PINMISSING */
  hvsync_generator hvsync_gen(.clk(clk_3), .reset(rst_i), .hsync, .vsync, .hpos, .vpos);
  /* verilator lint_on PINMISSING */
  
  // The interactive model deliberately lowers the whole console to one compact
  // clock domain. Select the PSG's compact preview schedule so that lowering
  // remains audible without imposing its clocks-per-sample on hardware or the
  // PICO-8 oracle renderer.
  chip #(.RED(8), .GREEN(8), .BLUE(8), .FILE("palette888.bin"),
         .PSG_PREVIEW(1)) chip(
    .clk(clk_i), 
    .cpuclk(clk_i), // Use the same clock for CPU
    .psgclk(clk_i),
    .reset(rst_i), 
    .vsync, 
    .hsync, 
    .vpos, 
    .hpos, 
    .buttons(buttons),
    .rgb,
    .audio(audio),
    .psg_dbg(psg_dbg)
  );
endmodule
