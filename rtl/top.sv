`include "chip.sv"
`include "por.sv"
`include "slower_clk.sv"
`include "lcd.sv"
`include "scalescreen.v"
`include "pll.v"
`include "clocks.sv"
`include "dsigma.sv"

module top(input  bit clk, output bit yellow_led,
           output bit sda, output bit scl, output bit cs, output bit rs, output bit lcd_rst,
           output bit tx, output bit audio_pwm);

  localparam SCALE = 2, WIDTH = 320, HEIGHT = 240;
  localparam RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "palette565.bin";

  // The clock the PSG actually runs at, fed to it so its 22050 Hz virtual
  // sample rate comes out right. It is the PLL output divided by PSG_DIV - see
  // rtl/pll.v and rtl/clocks.sv - not the board pin, and not the undivided PLL
  // either: the PSG measures Fmax 27.98 MHz, so the full 112.5 does not close.
  //
  // This used to read 25 MHz, the crystal, which was wrong in a way that hid
  // for a long time: at 25 MHz this video timing (161 x 121 x 3 clocks) runs
  // at 428 fps, so it was never the frequency anything actually ran at. The
  // chip clock is 112.5/32 = 3.515625 MHz, which is 60.155 Hz.
  // ONE knob for the PSG's rate. PSG_DIV goes to clocks.sv as the divider and
  // to chip.sv as the frequency the PSG derives 22050 Hz from; deriving both
  // from the same number is what stops the divider and the assumed frequency
  // drifting apart, which would detune the audio with nothing to show for it.
  // /6 is the lowest proven render-exact clock: the 578-clock walk plus the
  // fixed 272-cycle sequencer budget exactly fills its 850-clock interval.
  localparam PSG_DIV    = 6;
  localparam PSG_CLK_HZ = 32'd112_500_000 / PSG_DIV;

  logic reset;
  logic masterclk;
  logic videoclk;
  logic cpuclk;
  logic psgclk;
  logic pllclk, pll_locked;
  /* verilator lint_off PINCONNECTEMPTY */
  pll pll0(.clock_in(clk), .clock_out(pllclk), .locked(pll_locked));
  /* verilator lint_on PINCONNECTEMPTY */
  clocks #(.PSGDIV(PSG_DIV)) clocks0(.clk(pllclk), .reset, .masterclk, .videoclk, .cpuclk, .psgclk);

  assign lcd_rst = ~reset;
  assign yellow_led = ~reset;

  logic vsync;
  logic hsync;
  logic [RGB-1:0] rgb;
  logic [7:0] vp;
  logic [8:0] hp;
  logic [6:0] vpos;
  logic [7:0] hpos;

  lcd #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) lcd0(.clk(videoclk), .reset, .rgb, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos(vp), .hpos(hp));
  scalescreen #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) scaler0(.clk(videoclk), .reset, .vp, .hp, .vpos, .hpos);
  logic signed [15:0] audio;
  /* verilator lint_off PINCONNECTEMPTY */
  // psg_dbg is a verification-only bus; unconnected here so it synthesises away.
  // ---------------------------------------------------------------------
  // TEMPORARY, and it makes this bitstream non-functional: the RAM is 8 KB
  // here, not the machine's 64 KB.
  //
  // 64 KB is 512 kbit against the hx8k's 128 kbit of block RAM - 4x the whole
  // device before any logic - so yosys does not map it to block RAM at all and
  // expands it into fabric: 1.7 M AND gates for a 7680-cell part, which never
  // finishes placing. Nothing about the FPGA path could be measured while that
  // was true. 8 KB is enough to get synthesis and place-and-route to complete
  // so the rest of the design has real numbers.
  //
  // A program will NOT run from this: the address is truncated, so $FFFC and
  // $1FFC are the same byte and the reset vector aliases into the program.
  // Do not flash it expecting a game. The external-memory abstraction is what
  // fixes this properly; when it lands, delete RAM_ADDR_BITS here and in
  // chip.sv so both tops agree again.
  // ---------------------------------------------------------------------
  chip #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE(FILE), .CLK_HZ(PSG_CLK_HZ),
         .RAM_ADDR_BITS(13), .PSG_DBG(0), .PSG_MULTIPUMP(1), .REVERB(0))
    chip(.clk(masterclk), .cpuclk(cpuclk), .psgclk(psgclk),
         .psgfastclk(pllclk), .reset, .vsync,
         .hsync, .vpos, .hpos,
         .buttons(8'h00), .rgb, .audio(audio), .psg_dbg());
  /* verilator lint_on PINCONNECTEMPTY */

  // Delta-sigma output: 8-bit PCM -> 1-bit density stream on audio_pwm.
  // Wire this pin to a speaker/amp through an RC low-pass (~1k + ~10nF).
  // On psgclk, not masterclk: a delta-sigma modulator's noise shaping is only
  // as good as its oversampling ratio, and 18.75 MHz against a 22050 Hz sample
  // is still over 6x what the video clock gives it.
  dsigma dsigma0(.clk(psgclk), .reset(reset), .pcm(audio), .out(audio_pwm));

  /* wire tx_ready;

  uart_tx u_uart_tx (
    .clk (clk),
    .reset (~user_reset),
    .tx_req (1'b1),
    .tx_ready (tx_ready),
    .tx_data (8'h55),
    .uart_tx (tx)
  ); */
endmodule
