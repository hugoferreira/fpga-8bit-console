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
  // The PSG gets the raw input clock; everything else runs at half of it. The
  // single-domain lowering this replaced gave the PSG 159 clocks per 22050 Hz
  // sample, and its synthesis walk has not fitted in that since the tick
  // engine stopped deferring a sample boundary it overran (4658091) - the
  // chip then renders silence, which is what `make run` had been doing. The
  // compact preview walk needs ~225; PSGSIMDIV = 2 gives 318.
  //
  // This is the simulator's analogue of rtl/clocks.sv's PSGDIV, inverted:
  // hardware divides the PLL DOWN to the PSG, the simulator divides the input
  // clock down to the core and hands the PSG the undivided one. Both keep the
  // two clocks phase-locked bits of one counter, so there is still no
  // asynchronous crossing and no synchroniser.
  localparam int PSGSIMDIV = 2;

  logic coreclk = 0;                    // clk_i / PSGSIMDIV: CPU, PPU, video
  always_ff @(posedge clk_i) coreclk <= ~coreclk;

  // Pixel clock: divide the CORE clock by 3. The PPU display pipeline needs 3
  // clocks per pixel (read, capture, stable); the old /4 dated from the
  // retired textbuffer's 4-state renderer and cost 25% more simulation work.
  logic [1:0] div3 = 0;
  logic       clk_3 = 0;
  always_ff @(posedge coreclk) begin
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
  
  // The interactive model lowers the console to two phase-locked clocks. The
  // PSG keeps its compact preview schedule - that is what keeps live audio
  // affordable without imposing the simulator's clocks-per-sample on hardware
  // or the PICO-8 oracle renderer - but it must be told the rate it is
  // actually clocked at, or its sample divider detunes: CLK_HZ is the core
  // rate times PSGSIMDIV, so 318 psgclks per 22050 Hz sample.
  chip #(.RED(8), .GREEN(8), .BLUE(8), .FILE("palette888.bin"),
         .PSG_PREVIEW(1), .CLK_HZ(32'd3_506_580 * PSGSIMDIV)) chip(
    .clk(coreclk),
    .cpuclk(coreclk), // Use the same clock for CPU
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
