`include "pll_gowin.v"

/**
 * Bring-up diagnostic for the Tang Primer 20K + Dock. NOT the console.
 *
 * Written 2026-08-07, when the first hardware load produced three dead outputs
 * at once - white panel, silent speaker, and two LEDs whose meaning was
 * ambiguous because their polarity had never been established. Three failures
 * sharing nothing but the clock and the reset is a signal to stop reasoning
 * about pin maps and go and establish the fundamentals one at a time.
 *
 * It deliberately has the SAME PORT LIST as rtl/top_tangprimer20k.sv, so it
 * builds against rtl/tangprimer20k.cst unchanged and every pin is exercised
 * exactly where the real design would drive it.
 *
 * What each output answers, independently:
 *
 *   led_reset  blinks at ~0.8 Hz straight off the 27 MHz input pin, through a
 *              counter and NO PLL. If this blinks: H11 really is the crystal,
 *              the FPGA is configured, and L16 really is a user LED we drive.
 *              If it sits still: nothing below it can be trusted.
 *   led_lock   blinks at ~0.8 Hz off the PLL output instead. Blinking here and
 *              not on led_reset is impossible; blinking on led_reset but not
 *              here isolates the fault to the rPLL.
 *   audio_pwm  a ~412 Hz square wave, both channels. Audible directly - the
 *              PMOD-AUDIO's PAM8403 will happily amplify a square wave. This
 *              tests the pin, the connector orientation and the amplifier
 *              without involving the PSG, the delta-sigma modulator or the CPU.
 *   scl/sda    ~1.6 Hz and ~0.8 Hz square waves on the panel's clock and data
 *   cs/rs      pins, slow enough to follow on a multimeter or a slow scope.
 *              This is how you confirm the PMOD2 mapping is what the module
 *              actually sees, without needing the panel to work.
 *
 * The Dock's own PT8211 outputs are held quiet and its amplifier disabled, so
 * the only thing making noise is the PMOD.
 *
 *   make tangprimer20k-blink
 *   make tangprimer20k-blink-prog
 */
module top(input  bit clk,
           input  bit key1, input bit key2,
           output bit led_reset,
           output bit led_lock,
           output bit sda, output bit scl, output bit cs, output bit rs,
           output bit lcd_rst,
           output bit audio_pwm,
           output bit audio_pwm_r,
           output bit hp_bck, output bit hp_ws, output bit hp_din,
           output bit pa_en);

  // ---- straight off the input pin, no PLL anywhere -----------------------
  logic [25:0] raw = 0;
  always_ff @(posedge clk) raw <= raw + 1'b1;

  // ---- the same thing, but clocked by the PLL ----------------------------
  wire pllclk, pllclk_div, pll_locked;
  pll_gowin pll0(.clock_in(clk), .clock_out(pllclk), .clock_div(pllclk_div),
                 .locked(pll_locked));

  logic [25:0] frompll = 0;
  always_ff @(posedge pllclk) frompll <= frompll + 1'b1;

  // THE ONE UNDER TEST. pllclk_div is the rPLL's CLKOUTD - 112.5/8 =
  // 9.375 MHz - and it is what feeds masterclk, videoclk and cpuclk in the
  // real design. Nothing the console lights up proves this clock runs: its two
  // LEDs are driven from the pllclk domain and from the PLL's own lock flag.
  // If CLKOUTD were dead the console would show exactly what it does show -
  // both LEDs healthy, a white panel (lcd.sv is on videoclk) and a silent
  // speaker (no CPU, so nothing ever writes the PSG).
  //   9.375 MHz / 2^23 = 1.1 Hz, about the same rate as the raw counter.
  //   The bit moved with DYN_SDIV_SEL: at /32 this was 2^22.
  logic [23:0] fromdiv32 = 0;
  always_ff @(posedge pllclk_div) fromdiv32 <= fromdiv32 + 1'b1;

  // 27 MHz / 2^25 = 0.8 Hz. Both LEDs blink if everything is healthy; which
  // one stops tells you which side of the PLL failed. Polarity is unknown and
  // does not matter here - a blink is a blink either way, which is exactly why
  // this is more useful than the console's static "both mean healthy" scheme.
  // led_reset carries the CLOCK UNDER TEST, led_lock the control. If the
  // control blinks and the other has stopped, CLKOUTD is the fault.
  assign led_reset = fromdiv32[23];
  assign led_lock  = raw[25];

  // ~412 Hz square wave: 27e6 / 2^16. Loud, obviously artificial, and nothing
  // to do with the audio pipeline.
  assign audio_pwm   = raw[15];
  assign audio_pwm_r = raw[15];

  // Slow enough to meter. Distinct rates so the four panel pins can be told
  // apart from each other at the connector.
  assign scl     = raw[24];
  assign sda     = raw[25];
  assign cs      = raw[23];
  assign rs      = raw[22];
  assign lcd_rst = 1'b1;

  // The Dock's own DAC path: held quiet, amplifier off.
  assign hp_bck = 1'b0;
  assign hp_ws  = 1'b0;
  assign hp_din = 1'b0;
  assign pa_en  = 1'b0;

  /* verilator lint_off UNUSED */
  wire unused = &{key1, key2, pll_locked, raw[21:16], frompll[25:0], fromdiv32[22:0]};
  /* verilator lint_on UNUSED */
endmodule
