#!/bin/sh
# Sample the distribution of a PSG tree's mapped floor by perturbing the
# NETLIST, not the source.
#
#   tools/psg_map_dist.sh [N] [label]
#   PSG_DIST_JOBS=8 tools/psg_map_dist.sh 30 baseline
#
# Supersedes tools/psg_area_dist.sh, which perturbed RTL identifiers. Same
# question - what is the spread of abc9's covering for one fixed circuit? -
# but asked one layer lower, where it is much cheaper and much safer.
#
# Why the netlist and not the source. The nuisance parameter is the encoding
# abc9 receives, and RTL identifiers are two layers upstream of that. Doing it
# in text cost three bugs: whitespace padding that was silently a no-op;
# renames that desynchronised `psg_common.svh` macro bodies (PSG_OSC_W14
# expands to {s_lp[16], old_mode_r, s_brown}) and so implicitly declared
# undriven nets; and port names that must not be renamed on one side of
# `.port(signal)`. All three vanish here:
#
#   * Elaborate ONCE to the pre-map netlist and snapshot it as RTLIL. Every
#     sample loads that same snapshot, so all samples are literally the same
#     circuit - behaviour-neutrality is structural, not something we check.
#   * RTLIL connects objects by identity, not by name, so renaming cannot
#     alter connectivity. Only CELLS are renamed; a cell name has no external
#     contract at all, unlike a wire that may be a port.
#   * The front end (read_verilog, hierarchy, proc, opt, techmap) is paid once
#     instead of N times. That is most of the per-sample cost.
#
# The pre-map count is reported once and is invariant by construction. It is
# still asserted per sample: if it ever moves, this script's premise is broken
# and the numbers must not be believed.
set -e

N=${1:-16}
LABEL=${2:-tree}
JOBS=${PSG_DIST_JOBS:-6}
ROOT=$(pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

command -v yosys >/dev/null || { echo "yosys not on PATH" >&2; exit 2; }
test -f rtl/target_psg.sv || { echo "run from a tree with rtl/target_psg.sv" >&2; exit 2; }

# ------------------------------------------------------- elaborate once
yosys -p "read_verilog -Irtl -sv rtl/target_psg.sv; \
          synth_ice40 -top target_psg -run :map_luts; \
          tee -o $WORK/premap.txt stat; \
          write_rtlil $WORK/premap.il" > "$WORK/elab.log" 2>&1 || {
  echo "elaboration FAILED - see $WORK/elab.log" >&2; tail -5 "$WORK/elab.log" >&2; exit 1; }

PREMAP=$(awk '/=== design hierarchy ===/{h=1} h && /^ *[0-9]+ +cells$/{print $1; exit}' "$WORK/premap.txt")

# ------------------------------------------------------- build rename scripts
python3 - "$WORK" "$N" <<'PYEOF'
import sys, re, pathlib, random
work, n = pathlib.Path(sys.argv[1]), int(sys.argv[2])
il = (work / 'premap.il').read_text().splitlines()
# RTLIL: `  cell <type> <name>`. Cells only - a cell name binds nothing
# outside the netlist, whereas a wire may carry a port contract.
cells = [m.group(1) for m in
         (re.match(r'\s*cell\s+\S+\s+(\S+)\s*$', ln) for ln in il) if m]
for k in range(n):
    lines = ['read_rtlil %s/premap.il' % work]
    if k:
        rng = random.Random(k)
        for c in rng.sample(cells, max(1, len(cells) // 3)):
            lines.append('rename %s %s_p%d' % (c, c, k))
    lines += ['synth_ice40 -top target_psg -run map_luts:',
              'tee -o %s/pm%d.txt stat' % (work, k),
              'write_json %s/s%d.json' % (work, k)]
    (work / ('k%d.ys' % k)).write_text('\n'.join(lines) + '\n')
print('%d cells available to rename' % len(cells))
PYEOF

# -------------------------------------------------------------------- run
run_one() {
  yosys -s "$WORK/k$1.ys" > "$WORK/y$1.log" 2>&1 \
    || echo "sample $1 FAILED (see $WORK/y$1.log)" >&2
}
i=0; k=0
while [ "$k" -lt "$N" ]; do
  run_one "$k" &
  i=$((i + 1)); k=$((k + 1))
  [ $((i % JOBS)) -eq 0 ] && wait
done
wait

# ---------------------------------------------------------------- collect
printf '== psg floor distribution: %s (%s samples, %s-way, pre-map %s) ==\n' \
       "$LABEL" "$N" "$JOBS" "$PREMAP"
printf '  %-7s %8s %8s %8s\n' sample LUT4 unpack floor

FLOORS=""
k=0
while [ "$k" -lt "$N" ]; do
  if [ ! -f "$WORK/s$k.json" ]; then
    printf '  %-7s %8s\n' "$k" FAILED; k=$((k + 1)); continue
  fi
  CENSUS=$(python3 "$ROOT/tools/psg_ff_census.py" "$WORK/s$k.json" | sed -n 2p)
  LUT4=$(echo "$CENSUS" | sed -E 's/.*LUT4 +([0-9]+).*/\1/')
  UNPK=$(echo "$CENSUS" | sed -E 's/.*, ([0-9]+) unpackable.*/\1/')
  FLOOR=$((LUT4 + UNPK))
  printf '  %-7s %8s %8s %8s\n' "$k" "$LUT4" "$UNPK" "$FLOOR"
  FLOORS="$FLOORS $FLOOR"
  k=$((k + 1))
done

# Median and IQR, not mean and stddev: these outcomes are lumpy, not Gaussian,
# and the decision rule is non-overlap of ranges rather than a t-test.
echo "$FLOORS" | tr ' ' '\n' | grep -v '^$' | sort -n | awk -v label="$LABEL" '
  { v[NR]=$1; s+=$1 }
  function q(p,  i) { i=int(p*(n-1))+1; return v[i] }
  END {
    n=NR; if (n==0) { print "\n  no valid samples"; exit 1 }
    med = (n%2) ? v[(n+1)/2] : (v[n/2]+v[n/2+1])/2
    printf "\n  n=%d  min=%d  q1=%d  median=%.1f  q3=%d  max=%d  mean=%.1f\n",
           n, v[1], q(0.25), med, q(0.75), v[n], s/n
    printf "  spread=%d  IQR=%d\n", v[n]-v[1], q(0.75)-q(0.25)
    printf "  RAW %s:", label; for (i=1;i<=n;i++) printf " %d", v[i]; printf "\n"
  }'
