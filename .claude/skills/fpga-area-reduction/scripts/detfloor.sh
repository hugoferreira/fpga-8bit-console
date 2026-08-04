#!/usr/bin/env bash
# The two DETERMINISTIC area numbers for one synthesis target.
#
#   scripts/detfloor.sh psg              # one target
#   scripts/detfloor.sh psg ppu cpu      # several
#
# Use this INSTEAD of judging a candidate on a single abc9 build.
#
# The problem it solves. abc9's LUT covering is sensitive to how the netlist is
# encoded - cell and net names, and the tie-breaks they drive - not just to
# what the circuit computes. Measured on this repo's PSG: renaming a third of
# the design's cells, with the circuit provably identical (pre-map cell count
# pinned), moves the packing floor over a range of **62-72 cells**. That is
# larger than the +-60 "naming band" the campaign had been using as its
# resolution limit, which means a single abc9 build cannot resolve anything
# smaller than about a hundred cells. Most sub-100-cell verdicts taken that way
# were never measurements. See Kahng & Mantik, "Measurement of Inherent Noise
# in EDA Tools" (ISQED'02): ordering is canonicalised away, RNG seeds move
# quality ~0.25%, but NAMING moves it by up to ~7%.
#
# The fix is to measure with a low-variance instrument and ship with the
# high-quality one. Two instruments here, both immune to naming:
#
#   pre-map cells   gates/carries/flops before any covering. Pure circuit
#                   complexity. Invariant under renaming by construction.
#   -noabc floor    Yosys' built-in LUT techmapping instead of abc. MEASURED
#                   SPREAD 0 over renamed samples. Absolute quality is much
#                   worse than abc9 (PSG: 8,879 vs ~6,840), so never quote it
#                   as "the area" - it is a ruler, not a result.
#
# A third option sits between them: `-noabc9` (classic abc) measured spread 9
# with absolute quality only ~100 cells off abc9, so it maps in a style much
# closer to what ships. Reported here as well.
#
# How to read it. A candidate must move the deterministic numbers in the right
# direction. If pre-map and -noabc disagree in sign, the change is not a
# structural improvement and no amount of abc9 sampling will make it one. Only
# once they agree is it worth sampling the abc9 distribution (n>=16, compare
# with a rank test, never two point builds).
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "$repo_root"

if [ $# -eq 0 ]; then
  echo "usage: $(basename "$0") <unit> [unit...]   (cpu | psg | ppu | soc)" >&2
  exit 2
fi

census=tools/psg_ff_census.py
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

floor_of() {  # <json> -> "LUT4 <n> unpack <n> floor <n>", or LUT4-only fallback
  if [ -f "$census" ]; then
    python3 "$census" "$1" | sed -n 2p \
      | sed -E 's/.*LUT4 +([0-9]+).*, ([0-9]+) unpackable.*/\1 \2/' \
      | awk '{printf "LUT4 %-6s unpack %-5s floor %s", $1, $2, $1+$2}'
  else
    echo "(no $census; floor needs the unpackable-flop split)"
  fi
}

for unit in "$@"; do
  top="target_$unit"
  src="rtl/$top.sv"
  [ -f "$src" ] || { echo "no $src" >&2; exit 2; }

  premap=$(yosys -p "read_verilog -Irtl -sv $src; \
                     synth_ice40 -top $top -run :map_luts; stat" 2>/dev/null \
           | awk '/=== design hierarchy ===/{h=1} h && /^ *[0-9]+ +cells$/{print $1; exit}')

  yosys -p "read_verilog -Irtl -sv $src; \
            synth_ice40 -top $top -noabc9 -noabc -json $work/$unit.na.json" \
    > "$work/$unit.na.log" 2>&1
  yosys -p "read_verilog -Irtl -sv $src; \
            synth_ice40 -top $top -noabc9 -json $work/$unit.ca.json" \
    > "$work/$unit.ca.log" 2>&1

  fp="$(cat rtl/*.sv rtl/*.v 2>/dev/null | shasum | cut -c1-12)@$(git rev-parse --short HEAD 2>/dev/null || echo no-git)"
  echo "== $unit  rtl $fp =="
  printf '  %-24s %s\n' "pre-map cells"          "$premap"
  printf '  %-24s %s\n' "-noabc floor (spread 0)" "$(floor_of "$work/$unit.na.json")"
  printf '  %-24s %s\n' "classic-abc floor"       "$(floor_of "$work/$unit.ca.json")"
  echo "  (abc9 is NOT reported here: it needs a distribution, not a build.)"
done
