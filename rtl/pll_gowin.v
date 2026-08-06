/**
 * PLL configuration - Gowin GW2A/GW2AR
 *
 * Shared by BOTH Gowin boards: the Tang Nano 20K (GW2AR-18C) and the Tang
 * Primer 20K (GW2A-18C). They are the same die and both run from a 27 MHz
 * crystal, so this file needs no retune between them and neither board has a
 * variant of it. Only the input BALL differs - Nano pin 4, Primer H11 - which
 * is a constraints matter and appears in neither this file nor `clocks.sv`.
 *
 * The Gowin counterpart of rtl/pll.v, which is an SB_PLL40_CORE and therefore
 * iCE40-only. Same contract: one input clock in, 112.5 MHz out, plus a lock
 * flag. rtl/clocks.sv derives everything else by integer division, so nothing
 * downstream of here knows which device it is running on.
 *
 *   Input:  27.000 MHz (the board crystal: Nano pin 4, Primer ball H11)
 *   Output: 112.500 MHz (achieved exactly)
 *
 * Exactly, not approximately, which is the reason this board needed no retune:
 *
 *   CLKOUT = CLKIN * (FBDIV_SEL + 1) / (IDIV_SEL + 1) = 27 * 25 / 6 = 112.5
 *   VCO    = CLKOUT * ODIV_SEL                        = 112.5 * 8  = 900 MHz
 *
 * so the video timing (161 x 121 x 3 clocks at 112.5/32 = 3.515625 MHz, i.e.
 * 60.155 Hz) and the PSG's 22050 Hz virtual sample rate come out identical to
 * the BlackIce build. 25/6 is the only small ratio that lands on 112.5 from a
 * 27 MHz crystal, and it lands on it with zero error.
 *
 * The two numbers that decide whether a set of dividers is legal at all:
 *
 *   PFD = CLKIN / (IDIV_SEL + 1) = 27 / 6 = 4.5 MHz    (GW2A range 3-400 MHz)
 *   VCO = 900 MHz                                      (GW2A range 400-1200)
 *
 * Both are comfortably inside their windows, so this is not a marginal PLL
 * setting that a speed-grade change would invalidate.
 *
 * On the Tang Nano 20K only: the crystal on pin 4 is the 27 MHz oscillator, NOT the MS5351 clock
 * generator on pins 10/11/13. The MS5351 outputs are programmed over I2C by
 * the onboard BL616 and default to 27 MHz too, but they are reported not to
 * bring an rPLL's LOCK high when used as its reference. Pin 4 is the one to
 * feed a PLL from.
 */

/*
 * `clock_div` is the second output, and it is not a convenience.
 *
 * rtl/clocks.sv makes the 3.515625 MHz chip clock by dividing the PLL output
 * by 32 in a counter. That is a flip-flop output used as a clock, and on this
 * device nextpnr routes it as an ordinary signal: measured **2.04 ns of skew**
 * across the die, (31,5) to (1,13). Against a 1.5 ns data path that is a HOLD
 * violation, and nextpnr reported three of them, all in the PPU blit -
 *
 *     ERROR: Hold/min time violation for clock 'posedge cpuclk':
 *       clk-skew -2.04 -2.04 Net cpuclk (31,5) -> (1,13)
 *
 * - which is a bitstream that does not work, not a bitstream that is slow. The
 * iCE40 build does not show it because a different device placed it luckily,
 * not because the structure is sound.
 *
 * The rPLL divides internally and puts the result on the clock network, where
 * a clock belongs. CLKOUTD is CLKOUT/DYN_SDIV_SEL, from the same VCO, so the
 * 32:1 ratio and the phase lock that rtl/clocks.sv depends on - a chip-clock
 * signal stable for 32 PSG clocks, no synchroniser anywhere - are exactly what
 * they were. Only the skew is gone.
 */
module pll_gowin(
	input  clock_in,
	output clock_out,	// 112.5 MHz
	output clock_div,	// 112.5 / 32 = 3.515625 MHz, on the clock network
	output locked
	);

  /* verilator lint_off PINMISSING */
  rPLL #(
		.FCLKIN("27"),
		.IDIV_SEL(5),		// / 6
		.FBDIV_SEL(24),		// x 25
		.ODIV_SEL(8),		// VCO = 900 MHz
		.DEVICE("GW2A-18C"),
		.CLKFB_SEL("internal"),
		.DYN_IDIV_SEL("false"),
		.DYN_FBDIV_SEL("false"),
		.DYN_ODIV_SEL("false"),
		.CLKOUTD_SRC("CLKOUT"),
		.CLKOUTD_BYPASS("false"),
		.DYN_SDIV_SEL(32),	// CLKOUTD = CLKOUT / 32 = 3.515625 MHz
		.PSDA_SEL("0000"),
		.DUTYDA_SEL("1000"),
		.DYN_DA_EN("false")
	) uut (
		.CLKIN(clock_in),
		.CLKFB(1'b0),
		.RESET(1'b0),
		.RESET_P(1'b0),
		.FBDSEL(6'b0),
		.IDSEL(6'b0),
		.ODSEL(6'b0),
		.PSDA(4'b0),
		.FDLY(4'b0),
		.DUTYDA(4'b0),
		.CLKOUT(clock_out),
		.CLKOUTD(clock_div),
		.LOCK(locked)
		);
  /* verilator lint_on PINMISSING */

endmodule
