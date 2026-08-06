# Timing constraints for both Gowin board targets.
#
# Shared by rtl/top_tangnano20k.sv and rtl/top_tangprimer20k.sv: the two boards
# are the same die driven from the same 27 MHz crystal through the same
# rtl/pll_gowin.v, so the clock nets have the same names and the same periods.
#
# WHY THIS FILE EXISTS. Without it `nextpnr-himbaechel` places and routes
# against its DEFAULT 12 MHz target, hits it trivially, and then prints a
# "Max frequency" line that is only the critical path it happened to end up
# with - a lower bound produced under no timing pressure, not a closure result.
# Reading that number as "achieved vs needed" is how this project reported a
# 43.05 MHz PSG domain on one board and 55.31 MHz on the other from the SAME
# RTL on the SAME die: a 28% spread that was placement noise being quoted as a
# design property.
#
# `--freq` is not the fix and the Makefile was right to avoid it: it applies one
# number to every domain, and these differ by 32x, so constraining cpuclk at the
# PSG's 112.5 MHz would report a domain with 20x of margin as failing. Per-clock
# constraints are the fix, which is what this is.
#
# Periods must track rtl/pll_gowin.v and rtl/clocks.sv. They are the only copy -
# the Makefile no longer carries its own hand-written thresholds, it reports
# nextpnr's own PASS/FAIL verdict against these.

# The PLL output, undivided: rtl/pll_gowin.v makes 27 * 25 / 6 = 112.5 MHz
# exactly. NOTHING FUNCTIONAL RUNS HERE - it clocks clocks.sv's reset counter,
# its /32 counter and its modulo-6 PSG divider, and that is all. It still has to
# be constrained, because if those counters cannot run at 112.5 MHz the whole
# clock tree beneath them is wrong.
#
# This used to be the PSG's clock, because both board tops assigned
# `psgclk = pllclk` and threw clocks.sv's divided output away. That made a
# 112.5 MHz requirement out of nothing: the PSG measured 43 MHz and was reported
# as a 2.6x miss "no board fixes", when the design has never asked the PSG for
# more than 18.75.
#   1000 / 112.5 = 8.889 ns
create_clock -name pllclk -period 8.889 [get_nets pllclk]

# The PSG: 112.5 / 6 = 18.75 MHz, clocks.sv's PSGDIV. This is the domain the
# PSG datapath is designed to close in, and rtl/target_psg.sdc has used this
# exact period for the standalone PSG target all along.
#   1000 / 18.75 = 53.333 ns
create_clock -name psgclk -period 53.333 [get_nets psgclk]

# The chip clock: the rPLL's CLKOUTD, 112.5 / 32 = 3.515625 MHz. The CPU, the
# PPU, the compositor and the video timing all run here.
#   1000 / 3.515625 = 284.444 ns
create_clock -name cpuclk -period 284.444 [get_nets cpuclk]

# ---------------------------------------------------------------------------
# Two things this file CANNOT express, both of which limit what the report means
# ---------------------------------------------------------------------------
#
# 1. Neither cpuclk nor psgclk is really a primary clock. cpuclk is pllclk / 32
#    and psgclk is pllclk / 6, both off the same VCO, so all three are
#    phase-locked and rtl/clocks.sv depends on exactly that - there is no
#    synchroniser anywhere between them, and the PSG samples CPU-side register
#    writes directly. The correct spelling is
#    `create_generated_clock -source pllclk -divide_by 32`, and
#    nextpnr-himbaechel rejects it:
#
#        ERROR: Unsupported SDC command 'create_generated_clock'
#
#    So they are declared as three unrelated primary clocks, and every
#    "Critical path report for cross-domain path 'posedge cpuclk' ->
#    'posedge pllclk'" nextpnr prints is analysing a crossing that is phase-
#    locked by construction. Those cross-domain numbers are not meaningful here.
#    The three same-domain results are.
#
# 2. lcd0.cs is deliberately left unconstrained. It is a flip-flop output used
#    as a clock in rtl/lcd.sv - a generated clock, which is the command above
#    that does not exist. Declaring it with `create_clock` would assert a period
#    this file would have to invent and then silently get wrong when lcd.sv
#    changes. Left alone it keeps nextpnr's 12 MHz default, which it clears by
#    more than 20x, and the Makefile labels it as unconstrained rather than
#    letting "PASS at 12.00 MHz" read as a result.
