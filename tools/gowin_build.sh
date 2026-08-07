#!/bin/sh
# Build a Tang board bitstream with the VENDOR Gowin toolchain (gw_sh).
#
#   tools/gowin_build.sh <board> <device-name> <part-number> <top.sv> <cst> [out.fs]
#
# With GOWIN_RUN=syn it stops after synthesis and writes no bitstream - that is
# `make gowin-check`, the portability gate. Synthesis alone is where the
# SystemVerilog dialect problems surface, and it takes ~35 s.
#
# This is the default flow for the Tang boards; `make PNR=nextpnr ...` selects
# the yosys + nextpnr-himbaechel path instead. Both read the same RTL and the
# same .cst; only the SDC differs (see rtl/gowin_vendor.sdc).
#
# WHY THE VENDOR FLOW IS THE DEFAULT. It is not only that it is faster
# (measured: 80 s for synthesis + place-and-route + bitstream, against 570 s
# for nextpnr's place-and-route alone). It also CHECKS things the open-source
# flow does not. Both of the hardware bugs found on 2026-08-07 were found this
# way and by nothing else:
#
#   * dedicated configuration pins. Gowin refuses to place a signal on one
#     without the matching -use_*_as_gpio, where nextpnr places it silently
#     and gowin_pack emits a bitstream with a dead peripheral. On the Tang
#     Nano 20K that was ALL THREE I2S pins - a silent board.
#   * rtl/lcd.sv's ROM lookup, which GowinSynthesis rejected outright and
#     which turned out never to have been synthesised as intended at all.
#
# HOW IT IS INVOKED. gw_sh cannot be run straight from the app bundle: its
# rpath uses $ORIGIN (a Linux-ism macOS does not resolve) and it wants a Tcl
# 8.6 framework. Contents/MacOS/gowinide sets DYLD_FRAMEWORK_PATH and
# DYLD_LIBRARY_PATH to IDE/lib, and so does the Makefile.
#
# The build runs in a scratch directory holding a symlink to rtl/, because the
# RTL loads memory images with paths relative to the working directory
# ("./rtl/attrram.hex") AND with bare names ("setup_st7789_565.hex"); running
# anywhere else breaks one or the other. It also keeps Gowin's impl/ output
# out of the repository root.
set -e

BOARD=$1; DEVNAME=$2; PARTNO=$3; TOP=$4; CST=$5; OUT=$6
RUN=${GOWIN_RUN:-all}
[ -n "$CST" ] || { echo "usage: $0 <board> <device> <partno> <top> <cst> [out.fs]"; exit 2; }
[ -x "$GW_SH" ] || {
  echo "error: gw_sh not found at '$GW_SH'"
  echo "       set GOWIN_APP to the Gowin EDA .app, or build with PNR=nextpnr"
  exit 2
}

REPO=$(pwd)
DIR=build/gowin_vendor/$BOARD
rm -rf "$DIR"; mkdir -p "$DIR"
ln -s "$REPO/rtl" "$DIR/rtl"
cp "$REPO/rtl/gowin_vendor.sdc" "$DIR/"

cat > "$DIR/run.tcl" <<EOF
set_device -name $DEVNAME $PARTNO
add_file rtl/$(basename "$TOP")
add_file rtl/$(basename "$CST")
add_file gowin_vendor.sdc
set_option -top_module top
set_option -verilog_std sysv2017
set_option -include_path rtl
# Release the SSPI pins for ordinary I/O. Both boards wire peripherals to them
# and are dead without it; see GOWIN_PACK_GPIO in the Makefile for the same
# fact on the nextpnr side. Do NOT add -use_jtag_as_gpio: that costs you the
# programming interface.
set_option -use_sspi_as_gpio 1
set_option -output_base_name $BOARD
run $RUN
EOF

cd "$DIR"
env $GW_ENV "$GW_SH" run.tcl > build.log 2>&1 || {
  echo "--- gowin build FAILED; errors: ---"
  grep -E "^ERROR" build.log | head -20
  exit 1
}

grep -E "^ERROR|^WARN .*(PR2017|PA2060)" build.log | head -10 || true
cd "$REPO"

if [ "$RUN" = syn ]; then
  echo "  $BOARD: GowinSynthesis ok"
  exit 0
fi

mkdir -p "$(dirname "$OUT")"
cp "$DIR/impl/pnr/$BOARD.fs" "$OUT"
python3 tools/gowin_vendor_report.py "$DIR" || true
echo "  wrote $OUT"
