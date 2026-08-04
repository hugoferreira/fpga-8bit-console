#!/usr/bin/env bash
# Pre-map structural cell count for one synthesis target.
#
# This is the metric that does NOT move under abc9's LUT-covering naming
# sensitivity, so it is the one to judge "did gates actually leave the
# netlist?" on. It is not the fit verdict - use `make synth-<unit>` for that.
#
# Caveat before believing a large delta: ask which cell family produced it.
# Carry-chain arithmetic on free variables maps ~1:1 and is honest; $div/$mod
# by a constant is ~11:1 fiction (yosys lowers to a restoring array before
# exploiting the constant, and abc9 then deletes ~92% of it); a shared decode
# network can lose cells without retiring anything.
#
#   scripts/premap.sh psg              # one target
#   scripts/premap.sh psg > after.txt  # diff against a baseline capture
#   scripts/premap.sh psg ppu          # several
#
# Runs in ~25 s per target against the working tree. For an A/B of a shared
# file, run it in an isolated tree copy - concurrent edits make the number
# describe someone else's change.

set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "$repo_root"

if [ $# -eq 0 ]; then
  echo "usage: $(basename "$0") <unit> [unit...]   (cpu | psg | ppu | soc)" >&2
  exit 2
fi

for unit in "$@"; do
  top="rtl/target_${unit}.sv"
  if [ ! -f "$top" ]; then
    echo "no such target: $top" >&2
    exit 2
  fi

  printf '=== %s ===\n' "$unit"
  # rtl/pll.v is generated (gitignored) - exclude it from the fingerprint.
  printf '  rtl %s @ %s\n' \
    "$(cat rtl/*.sv $(ls rtl/*.v 2>/dev/null | grep -v '^rtl/pll\.v$') 2>/dev/null | shasum | cut -c1-12)" \
    "$(git rev-parse --short HEAD 2>/dev/null || echo no-git)"

  # The last "design hierarchy" block is the whole-design count including
  # submodules; the per-module blocks above it double-count nothing useful
  # here. Flops are summed across every SB_DFF* variant because which reset/
  # enable variant yosys picks is not what a candidate is being judged on.
  yosys -p "read_verilog -Irtl -sv ${top}; \
            synth_ice40 -top target_${unit} -run :map_luts; \
            stat" 2>&1 \
    | awk '/=== design hierarchy ===/{h=1} h' \
    | awk '
        /^ *[0-9]+ +[A-Za-z$_]/ {
          n = $1; name = $2
          if (name == "cells")   cells = n
          else if (name ~ /^SB_DFF/) { flops += n; det[name] = n }
          else if (n > 0 && name ~ /^\$/) { det[name] = n }
        }
        END {
          printf "A  %-26s %6d\n", "cells (pre-map)", cells
          printf "A  %-26s %6d\n", "flops (all SB_DFF*)", flops
          for (k in det) printf "B  %-26s %6d\n", k, det[k]
        }' \
    | sort -k1,1 -k2,2 \
    | cut -c2-
done
