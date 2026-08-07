# Timing constraints for the VENDOR Gowin flow (gw_sh), both Tang boards.
#
# A separate file from rtl/gowin_boards.sdc, which is the nextpnr one, and the
# split is forced rather than chosen. Two incompatibilities:
#
#   1. SYNTAX. nextpnr's generic SDC parser accepts `[get_nets pllclk]`;
#      Gowin's wants the object list braced and rejects the bare form:
#          ERROR (TA2000) : 'syntax error' near token 'pllclk]'
#
#   2. NET NAMES. yosys and GowinSynthesis do not name nets alike. `cpuclk`
#      exists in the yosys netlist and does NOT exist here:
#          ERROR (TA2003) : Can't set timing constraint to object cpuclk
#      Gowin derives the rPLL's divided outputs itself and reports them
#      anyway - cpuclk shows up in its timing report at 3.516 MHz with no
#      constraint written for it - so nothing is lost by leaving it out.
#
# So one SDC cannot serve both flows. Everything else about the design is
# shared: the same RTL and the same .cst files feed both.
#
# Periods must track rtl/pll_gowin.v and rtl/clocks.sv, exactly as the nextpnr
# SDC's do. Two copies of these numbers is a real hazard; `make gowin-check`
# and `make tangnano20k-synth` will not catch a disagreement between them.

# The PLL output, undivided: 27 * 25 / 6 = 112.5 MHz. Only clocks.sv's reset
# counter and its two dividers run here.
create_clock -name pllclk -period 8.889 [get_nets {pllclk}]

# The PSG: 112.5 / 6 = 18.75 MHz, clocks.sv's PSGDIV.
create_clock -name psgclk -period 53.333 [get_nets {psgclk}]
