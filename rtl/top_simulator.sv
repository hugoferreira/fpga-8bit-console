/* verilator lint_off UNOPTFLAT */
`include "chip.sv"
`include "por.sv"
`include "slower_clk.sv"
// The VERILATOR macro is predefined by the Verilator tool itself; define it
// here only for other tools (redefining is fatal DEFOVERRIDE in Verilator 5)
`ifndef VERILATOR
`define VERILATOR
`endif

// PSGSIMDIV is a PARAMETER, not a localparam, so the Makefile can set it once
// with -GPSGSIMDIV= and hand the same number to sim/console.cpp as -DPSGSIMDIV=.
// The two sides must agree - console.cpp issues 3*PSGSIMDIV clock pairs per
// pixel - and a knob that lives in two files is a knob that drifts.
module top #(parameter int PSGSIMDIV = 1)
          (input logic clk_i, input logic rst_i, input logic [7:0] buttons,
           output logic hsync, output logic vsync, output logic [23:0] rgb,
           output logic signed [15:0] audio, output logic [63:0] psg_dbg);
  localparam WIDTH = 320, HEIGHT = 240;

  logic [7:0] hpos;
  logic [6:0] vpos;

  // Pixel clock: divide by 3. The PPU display pipeline needs 3 clocks per
  // pixel (read, capture, stable); the old /4 dated from the retired
  // textbuffer's 4-state renderer and cost 25% more simulation work.
  // The core runs at half the model input clock. The compact preview walk now
  // fits that same clock (worst 86 of 159 clocks/sample), so the PSG no longer
  // needs the raw input clock's duplicate edges.
  //
  // This is the simulator's analogue of rtl/clocks.sv's PSGDIV, inverted:
  // hardware divides the PLL DOWN to the PSG; the simulator selects either
  // the phase-locked input clock or the core clock. PSGSIMDIV is the resulting
  // PSG/core ratio and also scales the declared PSG frequency below.

  // AT PSGSIMDIV=1 THE DIVIDER IS PURE SIMULATION COST. Nothing then runs on
  // clk_i - psgclk is coreclk, and psgfastclk is only read under MULTIPUMP,
  // which the simulator does not set - so the flop existed solely to halve a
  // clock the model then had to be evaluated twice to produce. Every other
  // eval() was a coreclk NEGEDGE that no process is sensitive to, at full
  // per-eval cost. Driving coreclk from the input directly and halving
  // CLKS_PER_PIXEL on the C++ side is 1.37x end to end (600 frames of Celeste:
  // 10.66 s -> 7.77 s, 56 -> 77 fps), with the rendered frame and the emitted
  // WAV both BYTE-IDENTICAL over 10 s of audio.
  //
  // At PSGSIMDIV=2 the divider is real: psgclk is clk_i and coreclk is its
  // half, so both edges matter and both paths have to exist.
  logic coreclk_div = 0;
  always_ff @(posedge clk_i) coreclk_div <= ~coreclk_div;
  wire coreclk = (PSGSIMDIV == 1) ? clk_i : coreclk_div;
  wire psgclk  = (PSGSIMDIV == 1) ? coreclk : clk_i;

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
  // rate times PSGSIMDIV, so the current single-domain setting supplies 159
  // PSG clocks per 22050 Hz sample.
  chip #(.RED(8), .GREEN(8), .BLUE(8), .FILE("./rtl/palette888.bin"),
         .PSG_PREVIEW(1), .PSG_MULTIPUMP(0),
         .CLK_HZ(32'd3_506_580 * PSGSIMDIV)) chip(
    .clk(coreclk),
    .cpuclk(coreclk), // Use the same clock for CPU
    .psgclk(psgclk),
    .psgfastclk(clk_i),
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
