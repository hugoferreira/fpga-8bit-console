// Tang Nano 20K PLL for the standalone PSG/SDRAM player.
// 27 MHz -> 112.5 MHz fast clock and a phase-related /6 (18.75 MHz) clock.
module pll_gowin_psg_sdram(
    input  logic clock_in,
    output logic fastclk,
    output logic slowclk,
    output logic locked
  );
  /* verilator lint_off PINMISSING */
  rPLL #(
    .FCLKIN("27"),
    .IDIV_SEL(5),
    .FBDIV_SEL(24),
    .ODIV_SEL(8),
    .DEVICE("GW2A-18C"),
    .CLKFB_SEL("internal"),
    .DYN_IDIV_SEL("false"),
    .DYN_FBDIV_SEL("false"),
    .DYN_ODIV_SEL("false"),
    .CLKOUTD_SRC("CLKOUT"),
    .CLKOUTD_BYPASS("false"),
    .DYN_SDIV_SEL(6),
    .PSDA_SEL("0000"),
    .DUTYDA_SEL("1000"),
    .DYN_DA_EN("false")
  ) pll (
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
    .CLKOUT(fastclk),
    .CLKOUTD(slowclk),
    .LOCK(locked)
  );
  /* verilator lint_on PINMISSING */
endmodule
