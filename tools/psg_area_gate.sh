#!/bin/sh
# The area verdict for a PSG candidate - and the band rule that decides whether
# the number in front of you is a result at all.
#
#   tools/psg_area_gate.sh record     capture the current tree as the baseline
#   tools/psg_area_gate.sh            build the current tree and compare
#   tools/psg_area_gate.sh --reuse    re-report from existing build artifacts
#
# Why the band rule is the point of this script. Placed cells are deterministic
# across nextpnr seeds - five seeds give identical placement, only Fmax moves -
# so a placed delta at a fixed seed is netlist-real, not placer noise. But they
# are NOT insensitive: adding an unused module parameter, which leaves the
# pre-mapping netlist bit-for-bit identical, still moves placed cells by 59.
# That is abc9's LUT covering being order- and naming-sensitive. So a placed
# delta below PSG_AREA_BAND is not a small win - it is not a measurement, and
# nothing downstream can turn it into one.
#
# This exists because a session measured a candidate at 7,052 placed cells
# against a 7,055 baseline and then ran the entire correctness battery on the
# 3-cell difference: roughly 50 tool calls spent validating a mapping reshuffle.
#
# The acceptance rule is the ledger's: improve a deterministic mapped resource
# (the packing floor = LUT4 + unpackable flops) without regressing placed LCs.
set -e

BAND=${PSG_AREA_BAND:-60}
DIR=${PSG_AREA_DIR:-build/gates-psg}
SYNTH=build/targets
MODE=compare

for a in "$@"; do
  case "$a" in
    record)   MODE=record ;;
    --reuse)  REUSE=1 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

mkdir -p "$DIR"

# ---------------------------------------------------------------- measurement

# Pre-map structural cells: the number that does NOT move under abc9 naming, so
# it answers "did gates actually leave the netlist?" - which placed cells alone
# cannot. Judge realness here, fit below.
premap_cells() {
  yosys -p "read_verilog -Irtl -sv rtl/target_psg.sv; \
            synth_ice40 -top target_psg -run :map_luts; stat" 2>/dev/null \
    | awk '/=== design hierarchy ===/{h=1} h && /^ *[0-9]+ +cells$/{print $1; exit}'
}

if [ -z "$REUSE" ]; then
  PREMAP=$(premap_cells)
  make synth-psg > "$DIR/synth.out" 2>&1 || {
    echo "synth-psg FAILED - see $DIR/synth.out" >&2; tail -5 "$DIR/synth.out" >&2; exit 1; }
else
  PREMAP=$(cat "$DIR/premap.txt" 2>/dev/null || premap_cells)
  test -f "$SYNTH/psg.json" || { echo "no build artifacts to reuse" >&2; exit 2; }
fi
echo "$PREMAP" > "$DIR/premap.txt"

# One token, no spaces: the whole vector is stored as key=value pairs and read
# back with eval, so a fingerprint with a space in it would split the record.
FP="$(cat rtl/*.sv rtl/*.v 2>/dev/null | shasum | cut -c1-12)@$(git rev-parse --short HEAD 2>/dev/null || echo no-git)"

# LUT4 / CARRY / FF and the packed split all come from one census pass; the
# floor is LUT4 + unpackable flops, because an unpackable flop burns a whole
# cell whose LUT half a mapped LUT4 count never shows.
CENSUS=$(python3 tools/psg_ff_census.py "$SYNTH/psg.json" | sed -n 2p)
LUT4=$(echo "$CENSUS"  | sed -E 's/.*LUT4 +([0-9]+).*/\1/')
CARRY=$(echo "$CENSUS" | sed -E 's/.*CARRY +([0-9]+).*/\1/')
FF=$(echo "$CENSUS"    | sed -E 's/.*FF +([0-9]+).*/\1/')
UNPK=$(echo "$CENSUS"  | sed -E 's/.*, ([0-9]+) unpackable.*/\1/')
FLOOR=$((LUT4 + UNPK))

PLACED=$(grep -E 'ICESTORM_LC: +[0-9]+/' "$SYNTH/psg.pnr.log" | tail -1 \
         | sed -E 's#.*ICESTORM_LC: +([0-9]+)/.*#\1#')
EBR=$(grep -E 'ICESTORM_RAM: +[0-9]+/' "$SYNTH/psg.pnr.log" | tail -1 \
      | sed -E 's#.*ICESTORM_RAM: +([0-9]+)/.*#\1#')
FMAX=$(grep 'Max frequency for clock' "$SYNTH/psg.pnr.log" \
       | awk '{last[$6]=$0} END {for (c in last) print last[c]}' \
       | sed -E 's/.*: ([0-9.]+) MHz.*/\1/' | sort -n | paste -sd/ -)

VEC="premap=$PREMAP lut4=$LUT4 carry=$CARRY ff=$FF unpackable=$UNPK floor=$FLOOR placed=$PLACED ebr=$EBR fmax=$FMAX fingerprint=$FP"

printf '== psg area ==\n'
printf '  rtl %s\n' "$FP"
printf '  %-11s %6s\n' premap "$PREMAP" LUT4 "$LUT4" carry "$CARRY" \
                       flops "$FF" unpackable "$UNPK" floor "$FLOOR" \
                       placed "$PLACED" EBR "$EBR"
printf '  %-11s %s MHz\n' Fmax "$FMAX"

if [ "$MODE" = record ]; then
  echo "$VEC" > "$DIR/baseline.txt"
  printf '\n  recorded as the baseline in %s\n' "$DIR/baseline.txt"
  exit 0
fi

# ------------------------------------------------------------------- compare

if [ ! -f "$DIR/baseline.txt" ]; then
  printf '\n  no baseline recorded. Capture one on the accepted tree first:\n'
  printf '    make area-psg RECORD=1\n'
  exit 0
fi

# shellcheck disable=SC2046
eval $(sed -E 's/([a-z0-9]+)=/B_\1=/g' "$DIR/baseline.txt")

d() { echo $(($1 - $2)); }
sign() { [ "$1" -gt 0 ] && printf '+%s' "$1" || printf '%s' "$1"; }

D_PREMAP=$(d "$PREMAP" "$B_premap")
D_FLOOR=$(d "$FLOOR"   "$B_floor")
D_PLACED=$(d "$PLACED" "$B_placed")

printf '\n  vs baseline rtl %s\n' "$B_fingerprint"
printf '    %-8s %6s -> %6s  %8s\n' \
  premap "$B_premap" "$PREMAP" "$(sign $D_PREMAP)" \
  floor  "$B_floor"  "$FLOOR"  "$(sign $D_FLOOR)" \
  placed "$B_placed" "$PLACED" "$(sign $D_PLACED)"

ABS_PLACED=${D_PLACED#-}
printf '\n'

if [ "$D_FLOOR" -lt 0 ] && [ "$D_PLACED" -lt "$BAND" ]; then
  printf '  VERDICT: CANDIDATE - floor %s, placed %s.\n' "$(sign $D_FLOOR)" "$(sign $D_PLACED)"
  printf '           A deterministic mapped resource improved and placement did\n'
  printf '           not regress. Now prove exactness, then run: make gates-psg\n'
  exit 0
fi

if [ "$D_FLOOR" -gt 0 ] || [ "$D_PLACED" -ge "$BAND" ]; then
  printf '  VERDICT: REJECT - floor %s, placed %s.\n' "$(sign $D_FLOOR)" "$(sign $D_PLACED)"
  printf '           Revert, and record the row with these numbers and a\n'
  printf '           "repeat only if" condition. Do not run the battery.\n'
  exit 1
fi

printf '  VERDICT: UNRESOLVED - placed delta %s is inside the +-%s abc9 naming band,\n' \
       "$(sign $D_PLACED)" "$BAND"
printf '           and the floor did not move (%s). This candidate has NO measured\n' "$(sign $D_FLOOR)"
printf '           area effect; the battery cannot create one.\n'
printf '           Revert and record it as unresolved - that is a complete result.\n'
printf '           If it is one of a family of sub-band shavings, bundle the\n'
printf '           siblings into one stage whose combined delta clears %s.\n' "$BAND"
exit 1
