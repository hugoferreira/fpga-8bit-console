`include "chip.sv"
`include "lcd.sv"
`include "rgb_quant.sv"
`include "scalescreen.v"
`include "pll_gowin.v"
`include "clocks.sv"
`include "dsigma.sv"
`include "pt8211_out.sv"

/**
 * Board top for the Sipeed Tang Primer 20K on the Dock ext-board
 * (Gowin GW2A-LV18PG256C8/I7).
 *
 * The third board top, after rtl/top.sv (BlackIce MX, iCE40 HX8K) and
 * rtl/top_tangnano20k.sv (Tang Nano 20K, GW2AR-18C). Read this one next to the
 * Tang Nano top: they are deliberately near-identical, and the differences are
 * the whole content of this file.
 *
 * WHY THIS PORT IS CHEAP. The Tang Nano 20K's GW2AR-18C and this board's
 * GW2A-18C are the SAME DIE - the `R` part is that die with 64 Mbit of SDRAM
 * added inside the package. Same 20,736 LUT4, same 46 block RAMs, same 48
 * multipliers, and apicula and nextpnr use the same `GW2A-18C` chipdb for both.
 * The crystal is 27 MHz on both boards as well, so rtl/pll_gowin.v is reused
 * with no retune and every frequency rtl/clocks.sv derives is identical. The
 * 64 KB main memory therefore maps to 32 block RAMs here exactly as it does
 * there, and this top passes RAM_ADDR_BITS(16) - the real machine - for the
 * same reason.
 *
 * So essentially nothing about the CHIP changes. What changes is the board:
 *
 *   1. AUDIO. The Tang Nano 20K carries a MAX98357A, an I2S class-D amplifier,
 *      and rtl/i2s_out.sv feeds it. The Dock carries a PT8211 DAC into an
 *      LPA4809 headphone amplifier, and a PT8211 is NOT an I2S receiver: its
 *      WS moves coincident with the MSB where Philips I2S moves one BCK early.
 *      Handing it a Philips stream is not a subtle error - measured, 16'sh1234
 *      arrives as 16'shdcbb. Hence rtl/pt8211_out.sv, and hence the port names
 *      here are the board's (hp_bck/hp_ws/hp_din) rather than i2s_*.
 *
 *   2. PINS. A PG256 BGA, so ball designators rather than the Nano's QN88 pin
 *      numbers, and every peripheral is on the ext-board rather than the core
 *      board. See rtl/tangprimer20k.cst.
 *
 *   3. ONE KEY IS 1.5 V. Four of the Dock's five user keys sit in the bank its
 *      DDR3 shares. Only btn_n0 is a 3.3 V input; key2 here is a 1.5 V one.
 *      That is a constraints matter, not an RTL one - it is noted because the
 *      synchroniser below treats both keys identically and should not.
 *
 * NOT VERIFIED ON HARDWARE. The bitstream builds, places, routes and packs, and
 * the numbers in docs/boards.md are read out of a real routed netlist - but no
 * .fs has been loaded onto this board. The LED polarity, the PT8211 framing
 * against the real part, and the LCD ball choices are all unproven. Nothing
 * below the bitstream should be trusted until someone has looked.
 *
 * See docs/boards.md for the toolchain, the pin map and the Dock's DIP switch,
 * which will keep the core board dead until it is set correctly.
 */
module top(input  bit clk,                    // 27 MHz crystal, ball H11
           input  bit key1, input bit key2,   // the two user keys, active low
           output bit led_reset,              // LEDs are active low on this board
           output bit led_lock,
           output bit sda, output bit scl, output bit cs, output bit rs,
           output bit lcd_rst,
           output bit audio_pwm,              // delta-sigma -> PMOD0 IL
           output bit audio_pwm_r,            // ...and IR, same mono signal
           output bit hp_bck, output bit hp_ws, output bit hp_din,
           output bit pa_en);                 // LPA4809 enable

  localparam SCALE = 2, WIDTH = 320, HEIGHT = 240;
  localparam RED = 5, GREEN = 6, BLUE = 5, RGB = RED + GREEN + BLUE, FILE = "./rtl/palette565.bin";

  // ONE knob for the PSG's rate, exactly as rtl/top.sv has it. PSG_DIV goes to
  // clocks.sv as the divider AND divides the frequency the PSG computes its
  // sample rate from, so the two cannot drift apart - which rtl/clocks.sv warns
  // "detunes the audio silently".
  //
  // This top used to hand the PSG the UNDIVIDED 112.5 MHz and declare
  // PSG_CLK_HZ to match. That was wrong twice over, and rtl/clocks.sv says so
  // in capitals: "PSGDIV EXISTS BECAUSE THE UNDIVIDED CLOCK DOES NOT CLOSE."
  //
  //   Timing - the PSG closes here at 43.05 MHz, so 112.5 was a 2.6x miss that
  //   this file invented. Against the designed 18.75 it is a 2.3x PASS.
  //   Render  - psg_timing derives the 22050 Hz sample tick from CLK_HZ, so
  //   112.5 MHz gave the PSG 5102 clocks/sample instead of 850. The sequencer
  //   gets whatever the walk leaves over and the phase count is render-load-
  //   bearing (docs/hardware-gaps.md), so this board rendered DIFFERENT AUDIO
  //   from the BlackIce and the simulator, and no gate builds this top to
  //   notice.
  //
  // 18.75 MHz is the design's own stated operating point: rtl/target_psg.sdc
  // has constrained `psgclk` to 53.333 ns all along.
  localparam PSG_DIV    = 6;
  localparam PSG_CLK_HZ = 32'd112_500_000 / PSG_DIV;   // 18.75 MHz

  logic reset;
  logic masterclk;
  logic videoclk;
  logic cpuclk;
  logic psgclk;
  logic pllclk, pllclk_div, pll_locked;
  pll_gowin pll0(.clock_in(clk), .clock_out(pllclk), .clock_div(pllclk_div),
                 .locked(pll_locked));

  // clocks.sv is instantiated for its RESET COUNTER only; its /32 divider is
  // left unconnected and yosys trims it. The chip clock comes from the PLL's
  // own divided output instead.
  //
  // Not a preference - a correctness fix, and it carries over to this board
  // unchanged because it is a property of the fabric, not of the package.
  // clocks.sv divides in a counter, which makes the chip clock a flip-flop
  // output, and nextpnr routes that as an ordinary signal: on the Tang Nano
  // that measured 2.04 ns of skew and three HOLD violations in the PPU blit.
  // See the header comment in rtl/pll_gowin.v.
  // clocks.sv supplies the reset counter AND the PSG clock; its /32 outputs are
  // left unconnected because the rPLL's CLKOUTD does that job on a real clock
  // network (see below). psgclk has no such second PLL output available, so it
  // comes off clocks.sv's modulo-6 divider - a flip-flop net, which is exactly
  // the shape that gave cpuclk 2.04 ns of skew and three hold violations.
  //
  // What saves it is that nextpnr-himbaechel promotes clock nets to the global
  // network by itself ("net was routed using global resources only" in the
  // place-and-route log); there is no BUFG primitive to instantiate in yosys's
  // Gowin library to force it. THAT PROMOTION IS THE LOAD-BEARING ASSUMPTION
  // HERE - if a future netlist stops promoting psgclk, the symptom is hold
  // violations, not slow logic. The build checks for them.
  /* verilator lint_off PINCONNECTEMPTY */
  clocks #(.PSGDIV(PSG_DIV)) clocks0(.clk(pllclk), .reset,
                 .masterclk(), .videoclk(), .cpuclk(), .psgclk(psgclk));
  /* verilator lint_on PINCONNECTEMPTY */

  assign masterclk = pllclk_div;
  assign videoclk  = pllclk_div;
  assign cpuclk    = pllclk_div;

  assign lcd_rst  = ~reset;
  // Both LEDs are assumed active low and both mean "healthy", so a working
  // board should show two lit LEDs a fraction of a second after power-on:
  // led_lock as soon as the rPLL reports lock, led_reset when clocks.sv
  // finishes its 65536-cycle reset and the CPU starts fetching. One lit and one
  // dark localises a dead board to one side of the PLL without instrumentation.
  //
  // If BOTH stay dark on a board that is otherwise alive, the Dock's LEDs are
  // active high and these two lines are the fix - drop the inversions.
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
  // with a 112.5 MHz PLL sitting idle.
  //
  // SPI_HALF=1 is SCL = pllclk/2 = 56.25 MHz, the rate the panel was qualified
  // at on hardware under a per-pixel grid pattern.
  //
  // It was 3 (18.75 MHz, 15.2 fps) because the divider was 32:1, which forced
  // a console pixel to be at least 3 * 32 = 96 pllclk and so PIXCLK >= 48. The
  // compositor was never the binding constraint - see the header of rtl/lcd.sv,
  // which used to claim it was.
  //
  // SPI_HALF=1 AND RGB565 IS NOT A VALID PAIR at this divider, even though it
  // would give 45.5 fps: PIXCLK would be 32, and 32/12 is not an integer, which
  // breaks the phase argument below. The pairs that work at 12:1 are the ones
  // whose PIXCLK divides by 12, and RGB444/SPI_HALF=1 (PIXCLK=24) is the fastest
  // of them. Colour depth and clock rate are not independent knobs here.
  //
  // hpos/vpos/vsync change in the pllclk domain; the same header explains why
  // that is safe, and that the argument depends on PIXCLK staying an integer
  // multiple of the 12:1 ratio. RGB444 makes PIXCLK 24, and 24/12 = 2.
  //
  // THE PANEL SEES RGB444, THE CONSOLE STAYS RGB565. rgb_quant is the whole
  // difference between 45.5 and 60.6 fps - 25% fewer bytes a frame on a link
  // that is the constraint - and it is a rounding, not a truncation, so the
  // error is +-1 output step rather than always downward. The compositor, the
  // line buffer and the palette are untouched at 16 bits, which is what a
  // future parallel or TMDS output wants.
  wire [11:0] rgb444;
  rgb_quant #(.IN_R(RED), .IN_G(GREEN), .IN_B(BLUE),
              .OUT_R(4), .OUT_G(4), .OUT_B(4)) quant0(.din(rgb), .dout(rgb444));

  lcd #(.WIDTH(WIDTH), .HEIGHT(HEIGHT), .RGBSIZE(12),
        .INIT_FILE("setup_st7789_444.hex"), .SPI_HALF(1))
    lcd0(.clk(pllclk), .reset, .rgb(rgb444), .sda, .scl, .cs, .rs,
         .vsync, .hsync, .vpos(vp), .hpos(hp));
  scalescreen #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) scaler0(.clk(videoclk), .reset, .vp, .hp, .vpos, .hpos);

  // Two of the Dock's five user keys, as the buttons a bare board has. The bit
  // assignment is the simulator's ($4007, see sim/console.cpp): 0x10 is
  // PICO-8's O and 0x20 its X, the two a port actually needs to get past a
  // title screen. Left/right/up/down have no key here and read 0.
  //
  // key1 (T10, btn_n0) is X and key2 (T3, btn_n1) is O - the O that PICO-8
  // also binds to the C key, which is Celeste's jump. It was the other way
  // round until 2026-08-07 and the swap is a deliberate request, not a fix:
  // with only two keys the pair has to cover starting the game and jumping.
  //
  // IF THE TWO COME OUT BACKWARDS ON HARDWARE, swap them here and nowhere
  // else. Which silkscreen legend sits above which ball is not something this
  // file can know, and this board is already on record disagreeing with itself
  // about that: its LEDs are silkscreened LED4/LED5 where litex calls the same
  // two led0/led1.
  //
  // Three more keys are wired on the Dock and are deliberately NOT taken: they
  // are in the 1.5 V DDR3 bank, and spending four more balls on directions is
  // a decision for whoever wires a real gamepad, not for board support.
  //
  // Keys short to ground, so a press reads 0 and the sense is inverted. The two
  // flops are the synchroniser: the keys are asynchronous to every clock here.
  //
  // There is no debounce counter, deliberately, for the reason spelled out in
  // rtl/top_tangnano20k.sv - `vsync` is one `cs` period long, so this samples
  // for about nine master clocks once every 58443 and holds the result for the
  // rest of the frame. The worst case a bounce can cause is one frame reading
  // the wrong way, which is under a game's reaction threshold.
  logic [1:0] key_sync0, key_sync1;
  logic [7:0] buttons;
  always_ff @(posedge masterclk) begin
    key_sync0 <= {key2, key1};
    key_sync1 <= key_sync0;
    // key_sync1[0] is key1 and drives bit 5 (X); key_sync1[1] is key2 and
    // drives bit 4 (O).
    if (vsync) buttons <= {2'b00, ~key_sync1[0], ~key_sync1[1], 4'b0000};
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

  // Audio, two ways, as on the Tang Nano - but the primary path is a DAC here,
  // not an amplifier with a digital input:
  //
  //   hp_*   the Dock's PT8211 DAC and the 3.5mm headphone jack. Nothing to
  //          wire. LSB-justified 16-bit framing, NOT Philips I2S; see the
  //          header of rtl/pt8211_out.sv for why that distinction is not
  //          cosmetic.
  //   pa_en  the LPA4809's enable: high enables the amplifier. Held off until
  //          the PLL locks so the output is not driven while the clock is still
  //          settling, which is an audible click on power-up otherwise.
  //   audio_pwm  the same PCM as a 1-bit delta-sigma stream on a header pin,
  //          for an external amp through an RC low-pass (~1k + ~10nF). This is
  //          the BlackIce's output stage, kept because it is the only one of
  //          the three that has a known-good reference, and because the PT8211
  //          path here has never been heard.
  //
  // Both run on psgclk, which is now 18.75 MHz rather than the 112.5 MHz this
  // file used to (wrongly) run the PSG at, so HALF is retuned by the same 6:
  // BCK = 18.75 MHz / (2 * 6) = 1.5625 MHz and the frame is 48.83 kHz - within
  // 1.8% of the 1.536 MHz / 48 kHz Sipeed's own example clocks this exact part
  // at, and closer to it than the old setting was.
  //
  // dsigma is the one thing the divide costs: a delta-sigma modulator's noise
  // shaping is only as good as its oversampling ratio, and that ratio drops 6x.
  // It is the fallback output, not the intended one, and rtl/top.sv has always
  // run it at this same 18.75 MHz - so this matches the BlackIce rather than
  // regressing against it.
  pt8211_out #(.HALF(6)) dac0(.clk(psgclk), .reset(reset), .pcm(audio),
                              .bck(hp_bck), .ws(hp_ws), .din(hp_din));
  assign pa_en = pll_locked & ~reset;

  // The MuseLab PMOD-AUDIO on PMOD0 is an analogue-input class-D amplifier
  // (PAM8403) behind a 22K/1uF network, so this delta-sigma stream is exactly
  // what it wants - it is the reconstruction filter docs/boards.md says this
  // stage needs off-board. Both of its channels take the same mono signal.
  dsigma dsigma0(.clk(psgclk), .reset(reset), .pcm(audio), .out(audio_pwm));
  assign audio_pwm_r = audio_pwm;

endmodule
