`include "chip.sv"
`include "lcd.sv"
`include "scalescreen.v"
`include "pll_gowin.v"
`include "clocks.sv"
`include "dsigma.sv"
`include "i2s_out.sv"

/**
 * Board top for the Sipeed Tang Nano 20K (Gowin GW2AR-LV18QN88C8/I7).
 *
 * The sibling of rtl/top.sv, which is the myStorm BlackIce MX (iCE40 HX8K)
 * top. Everything between the two that is the console rather than the board -
 * chip.sv, lcd.sv, the whole of the chip - is shared verbatim. What differs is
 * board-level: the PLL primitive, the pin names, the audio output stage, where
 * the chip clock is divided (see the clocking note below), and one parameter.
 *
 * That parameter is the point of this board. rtl/top.sv has to build the chip
 * with RAM_ADDR_BITS(13), an 8 KB main memory, because 64 KB is 512 kbit
 * against an HX8K's 128 kbit of block RAM: yosys cannot map it, expands it
 * into fabric as 1.7 M gates, and the bitstream that comes out the far end
 * cannot run a program - $FFFC and $1FFC are the same byte, so the reset
 * vector aliases into the program. See the comment above the `chip`
 * instantiation in rtl/top.sv, and docs/memory-subsystem.md.
 *
 * The GW2AR-18C has 828 kbit of block RAM in 46 blocks, and the 64 KB array
 * maps to 32 of them. So this top passes RAM_ADDR_BITS(16) - the real machine,
 * the same value the simulator uses - and is the first bitstream in this
 * project that is a whole console rather than a measurement vehicle.
 *
 * Placed and routed (`make tangnano20k`; nextpnr-himbaechel's own numbers):
 *
 *   LUT4        8493 of 20736   40%
 *   ALU         2218 of 15552   14%
 *   DFF         3231 of 15552   20%
 *   BSRAM         45 of 46      97%   <- the tight one
 *   MULT18X18      1 of 48       2%
 *
 * Block RAM is what this device is nearly out of, not logic, and the 64 KB
 * main memory is 32 of the 45. Anything that wants another block - the second
 * overlay plane in docs/hardware-gaps.md gap 9, for instance - has one to
 * spend, and then it is out.
 *
 * The multiplier line is new: the PSG's volume multiply infers one MULT18X18
 * and three MULT9X9 here. On the HX8K there is no SB_MAC16 at all, which is
 * why the Makefile leaves yosys `-dsp` off for that device and why
 * docs/hardware-gaps.md records that a hardware multiply cannot be helped by
 * the target. On this device it can be.
 *
 * Timing, against what rtl/clocks.sv asks of each domain: cpuclk closes at
 * 55.22 MHz against 3.515625 - 15.7x of margin - and pllclk at 49.62 against
 * 112.5, which is the PSG's known 2.3x miss and is an RTL defect rather than a
 * board one (it is 28.24 MHz on the hx8k). No hold violations; see the note on
 * the clock network below.
 *
 * See docs/boards.md for the toolchain, the pin map and the wiring.
 */
module top(input  bit clk,                    // 27 MHz crystal, pin 4
           input  bit key1, input bit key2,   // the two user keys, active low
           output bit led_reset,              // LEDs are active low on this board
           output bit led_lock,
           output bit sda, output bit scl, output bit cs, output bit rs,
           output bit lcd_rst,
           output bit audio_pwm,              // 1-bit delta-sigma, header pin
           output bit i2s_bclk, output bit i2s_lrck, output bit i2s_din,
           output bit pa_en);                 // MAX98357A SD_MODE

  localparam SCALE = 2, WIDTH = 320, HEIGHT = 240;
  localparam RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "./rtl/palette565.bin";

  // The clock the PSG actually runs at - the PLL output undivided, not the
  // board pin. 27 MHz in, 112.5 MHz out, exactly (rtl/pll_gowin.v), so this is
  // the same number the BlackIce top uses and the PSG needs no board-specific
  // retune to land on its 22050 Hz virtual sample rate.
  // ONE knob for the PSG's rate, as rtl/top.sv has it: PSG_DIV is both the
  // divider clocks.sv uses and the divisor on the frequency the PSG computes
  // its sample rate from, so the two cannot drift apart.
  //
  // This top used to hand the PSG the UNDIVIDED 112.5 MHz, which rtl/clocks.sv
  // says in capitals does not close - and it also gave the PSG 5102 clocks per
  // sample instead of 850, so this board rendered different audio from the
  // BlackIce and the simulator. 18.75 MHz is the design's stated operating
  // point; rtl/target_psg.sdc has constrained psgclk to 53.333 ns all along.
  localparam PSG_DIV    = 6;
  localparam PSG_CLK_HZ = 32'd112_500_000 / PSG_DIV;   // 18.75 MHz

  logic reset;
  logic masterclk;
  logic videoclk;
  logic cpuclk;
  logic psgclk;
  logic pllclk, pllclk_div32, pll_locked;
  pll_gowin pll0(.clock_in(clk), .clock_out(pllclk), .clock_div(pllclk_div32),
                 .locked(pll_locked));

  // clocks.sv is instantiated for its RESET COUNTER only; its /32 divider is
  // left unconnected and yosys trims it. The chip clock comes from the PLL's
  // own divided output instead.
  //
  // Not a preference - a correctness fix. clocks.sv divides in a counter, which
  // makes the chip clock a flip-flop output, and nextpnr routes that as an
  // ordinary signal: 2.04 ns of skew across the die, and three HOLD violations
  // in the PPU blit as a result. See the header comment in rtl/pll_gowin.v for
  // the report. The ratio, the frequencies and the phase lock are unchanged -
  // CLKOUTD comes off the same VCO as CLKOUT - so everything rtl/clocks.sv
  // documents about there being no asynchronous crossing still holds.
  //
  // The BlackIce top keeps the counter because SB_PLL40_CORE has no second
  // divided output to use instead. That board should be re-checked for the same
  // hazard; it has never been placed, so nobody has looked.
  // clocks.sv supplies the reset counter AND the PSG clock now; its /32 outputs
  // stay unconnected because the rPLL's CLKOUTD does that on a real clock
  // network. psgclk has no second PLL output to use, so it is clocks.sv's
  // modulo-6 divider output - a flip-flop net. nextpnr-himbaechel promotes
  // clock nets to the global network by itself (there is no BUFG in yosys's
  // Gowin library to force it); if that ever stops happening the symptom is
  // hold violations, which the build checks for.
  /* verilator lint_off PINCONNECTEMPTY */
  clocks #(.PSGDIV(PSG_DIV)) clocks0(.clk(pllclk), .reset,
                 .masterclk(), .videoclk(), .cpuclk(), .psgclk(psgclk));
  /* verilator lint_on PINCONNECTEMPTY */

  assign masterclk = pllclk_div32;
  assign videoclk  = pllclk_div32;
  assign cpuclk    = pllclk_div32;

  assign lcd_rst  = ~reset;
  // Both LEDs are active low and both mean "healthy", so a working board shows
  // two lit LEDs a fraction of a second after power-on: led_lock as soon as the
  // rPLL reports lock, led_reset when clocks.sv finishes its 65536-cycle reset
  // and the CPU starts fetching. One lit and one dark localises a dead board to
  // one side of the PLL without any instrumentation.
  assign led_reset = reset;        // lit once reset is released
  assign led_lock  = ~pll_locked;  // lit once the PLL has locked

  logic vsync;
  logic hsync;
  logic [RGB-1:0] rgb;
  logic [7:0] vp;
  logic [8:0] hp;
  logic [6:0] vpos;
  logic [7:0] hpos;

  // lcd0 runs on pllclk (112.5 MHz), NOT videoclk. It used to shift one bit per
  // 3.515625 MHz videoclk with a dead cycle between bytes - 2.5 fps - on a board
  // with a 112.5 MHz PLL sitting idle. SPI_HALF=3 gives SCL = pllclk/6 =
  // 18.75 MHz and 15.3 fps, pacing a console pixel to every 6 masterclk. 2 was
  // 4 masterclk against the compositor's 3.02 requirement - too tight, and the
  // sprite pass was the thing that got starved out and sprite_compositor.sv keeps its 483-clock line
  // budget. hpos/vpos/vsync therefore change in the pllclk domain; see the
  // header of rtl/lcd.sv for why that is safe against the 32:1 masterclk ratio.
  lcd #(.WIDTH(WIDTH), .HEIGHT(HEIGHT), .SPI_HALF(3)) lcd0(.clk(pllclk), .reset, .rgb, .sda, .scl, .cs, .rs, .vsync, .hsync, .vpos(vp), .hpos(hp));
  scalescreen #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) scaler0(.clk(videoclk), .reset, .vp, .hp, .vpos, .hpos);

  // The two onboard keys, as the only buttons a bare board has. The bit
  // assignment is the simulator's ($4007, see sim/console.cpp): 0x10 is
  // PICO-8's O and 0x20 its X, the two a port actually needs to get past a
  // title screen. Left/right/up/down have no key here and read 0 - a real
  // gamepad needs the DS2 pins on the headers and a controller reader, which
  // this does not have.
  //
  // Keys short to ground, so a press reads 0 and the sense is inverted. The two
  // flops are the synchroniser: the keys are asynchronous to every clock here.
  //
  // There is no debounce counter, deliberately. `vsync` is `state == 2` in
  // lcd.sv - the start_frame state, one `cs` period long - so this samples for
  // about nine master clocks once every 58443, and holds the result for the
  // rest of the frame. A contact bounce is only visible if an edge lands inside
  // that window, and the worst case if one does is a single frame reading the
  // wrong way. That is under a game's reaction threshold; a counter would be
  // real logic spent on a fault nobody can perceive.
  logic [1:0] key_sync0, key_sync1;
  logic [7:0] buttons;
  always_ff @(posedge masterclk) begin
    key_sync0 <= {key2, key1};
    key_sync1 <= key_sync0;
    if (vsync) buttons <= {2'b00, ~key_sync1[1], ~key_sync1[0], 4'b0000};
  end

  logic signed [15:0] audio;
  /* verilator lint_off PINCONNECTEMPTY */
  // psg_dbg is a verification-only bus; unconnected here so it synthesises away.
  chip #(.RED(RED), .GREEN(GREEN), .BLUE(BLUE), .FILE(FILE), .CLK_HZ(PSG_CLK_HZ),
         .RAM_ADDR_BITS(16), .PSG_DBG(0), .PSG_MULTIPUMP(0), .REVERB(0))
    chip(.clk(masterclk), .cpuclk(cpuclk), .psgclk(psgclk),
         .psgfastclk(pllclk), .reset, .vsync,
         .hsync, .vpos, .hpos,
         .buttons(buttons), .rgb, .audio(audio), .psg_dbg());
  /* verilator lint_on PINCONNECTEMPTY */

  // Audio, two ways, because the board supports both and they cost almost
  // nothing side by side:
  //
  //   i2s_*  the onboard MAX98357A and the speaker pads. Nothing to wire.
  //   pa_en  its SD_MODE pin: high enables the amplifier. Held at the PLL
  //          lock so the speaker is not driven while the clock is still
  //          settling, which is an audible click on power-up otherwise.
  //   audio_pwm  the same PCM as a 1-bit delta-sigma stream on a header pin,
  //          for an external amp through an RC low-pass (~1k + ~10nF). This is
  //          what the BlackIce build has, kept so a known-good output stage is
  //          available if the I2S wiring is ever in doubt.
  //
  // Both run on psgclk: a delta-sigma modulator's noise shaping is only as
  // good as its oversampling ratio, and the I2S divider wants the fast clock
  // to reach a sane bit rate.
  // HALF is retuned with PSG_DIV: psgclk is 18.75 MHz now, not 112.5, so
  // HALF = 6 gives BCLK = 18.75 / 12 = 1.5625 MHz and LRCK = 48.83 kHz - still
  // inside the MAX98357A's 8-96 kHz window, and about twice the PSG's 22050 Hz
  // virtual rate, which is the zero-order hold this stage has always relied on.
  // Leaving HALF at 40 would have put LRCK at 7.3 kHz, below the part's floor.
  i2s_out #(.HALF(6)) i2s0(.clk(psgclk), .reset(reset), .pcm(audio),
               .bclk(i2s_bclk), .lrck(i2s_lrck), .din(i2s_din));
  assign pa_en = pll_locked & ~reset;

  dsigma dsigma0(.clk(psgclk), .reset(reset), .pcm(audio), .out(audio_pwm));

endmodule
