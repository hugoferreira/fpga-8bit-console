#!/bin/sh
# Sample the DISTRIBUTION of a PSG tree's mapped floor, instead of one point.
#
#   tools/psg_area_dist.sh [N] [label]        # N samples, default 10
#   PSG_DIST_JOBS=8 tools/psg_area_dist.sh 20 candidate
#
# Why this exists. abc9's LUT covering is sensitive to how the design is
# ENCODED, not just to what it computes. So a single build does not measure a
# circuit; it draws one sample from that circuit's mapping distribution. A
# point A/B of two spellings therefore cannot separate a structural win from a
# covering reshuffle, which is how this campaign produced pre-map -81 -> floor
# 0, pre-map -52 -> floor +31, and the two composed -> floor -33.
#
# Which perturbation, and why this one. Kahng & Mantik, "Measurement of
# Inherent Noise in EDA Tools" (ISQED'02), measured the taxonomy: cell/net
# ORDERING is canonicalised away by the tools and yields byte-identical
# solutions; RNG seeds move quality by only ~0.25%; but NAMING moves it by up
# to ~7%, and scrambling name-encoded hierarchy by up to 12%. Measured here:
# renaming a third of each file's internal wires moves this design's floor by
# ~18 cells over just three samples, while whitespace/line-shift perturbation
# (an ordering perturbation) moves it by exactly zero. So: rename.
#
# Two guards, both from bugs this script actually shipped:
#   * the perturbation must demonstrably change the tree, or we refuse to
#     report - the first version's `pad=$(awk ...)` had its trailing newlines
#     eaten by command substitution, perturbed nothing, and reported a
#     confident spread of 0 that read as "the tool is stable";
#   * the pre-map cell count must be identical across samples. Pre-map is taken
#     before abc9 covers, so it is naming-invariant; if it moves, the rename
#     collided with an existing identifier and that sample is a DIFFERENT
#     CIRCUIT. It is discarded rather than allowed to widen the spread.
#
# Cost. One yosys pass per sample (the pre-map stat is teed out of the same
# run via -run :map_luts / -run map_luts:, not a second invocation), and
# samples run in parallel - they are independent. Nothing here runs nextpnr or
# any correctness gate: pick the spelling first, gate it once, at the end.
#
# Read the SPREAD before the median. If two arms' ranges overlap, neither has a
# demonstrated mapping advantage no matter where their medians sit.
set -e

N=${1:-10}
LABEL=${2:-tree}
JOBS=${PSG_DIST_JOBS:-6}
# Mapper flags, e.g. PSG_DIST_MAP="-noabc9 -noabc" to sample a DETERMINISTIC
# mapper instead of abc9. Empty means the shipping abc9 flow.
MAP=${PSG_DIST_MAP:-}
ROOT=$(pwd)
# Cache keyed by the RTL fingerprint, the mapper, and N. An A/B re-measures the
# baseline on every candidate otherwise, which is the larger half of the cost
# and pure waste when the baseline has not moved. Fingerprint covers rtl/ only,
# so tool or doc edits do not invalidate it.
CACHE=${PSG_DIST_CACHE:-build/gates-psg/dist}
# rtl/pll.v is generated (gitignored) - exclude it or identical trees key differently.
FP=$(cat rtl/*.sv $(ls rtl/*.v 2>/dev/null | grep -v '^rtl/pll\.v$') 2>/dev/null | shasum | cut -c1-12)
MAPKEY=$(echo "${PSG_DIST_MAP:-abc9}" | tr -cd 'a-z0-9')
KEY="$CACHE/$FP.$MAPKEY.txt"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

command -v yosys >/dev/null || { echo "yosys not on PATH" >&2; exit 2; }
test -f rtl/target_psg.sv || { echo "run from a tree with rtl/target_psg.sv" >&2; exit 2; }

report() {  # <label> <premap> <floors...>
  L=$1; PM=$2; shift 2
  printf '== psg floor distribution: %s (rtl %s, pre-map %s) ==\n' "$L" "$FP" "$PM"
  echo "$@" | tr ' ' '\n' | grep -v '^$' | sort -n | awk -v label="$L" '
    { v[NR]=$1; s+=$1 }
    function q(p,  i) { i=int(p*(n-1))+1; return v[i] }
    END {
      n=NR; if (n==0) { print "  no valid samples"; exit 1 }
      med = (n%2) ? v[(n+1)/2] : (v[n/2]+v[n/2+1])/2
      printf "  n=%d  min=%d  q1=%d  median=%.1f  q3=%d  max=%d  mean=%.1f\n",
             n, v[1], q(0.25), med, q(0.75), v[n], s/n
      printf "  spread=%d  IQR=%d\n", v[n]-v[1], q(0.75)-q(0.25)
      printf "  RAW %s:", label; for (i=1;i<=n;i++) printf " %d", v[i]; printf "\n"
    }'
}

if [ -z "${PSG_DIST_FORCE:-}" ] && [ -f "$KEY" ]; then
  HAVE=$(sed -n 2p "$KEY" | wc -w | tr -d ' ')
  if [ "$HAVE" -ge "$N" ]; then
    CPM=$(sed -n 1p "$KEY")
    CF=$(sed -n 2p "$KEY" | tr ' ' '\n' | head -n "$N" | tr '\n' ' ')
    printf '  (cached: %s samples for rtl %s, using %s - PSG_DIST_FORCE=1 to re-measure)\n' \
           "$HAVE" "$FP" "$N"
    report "$LABEL" "$CPM" "$CF"
    exit 0
  fi
fi

cat > "$WORK/perturb.py" <<'PYEOF'
import sys, re, pathlib, random
d, k = pathlib.Path(sys.argv[1]), int(sys.argv[2])
rng = random.Random(k)

srcs = sorted(d.glob('*.sv')) + sorted(d.glob('*.svh'))
text = {f: f.read_text() for f in srcs}
whole = '\n'.join(text.values())

# Ports are excluded: a name that is a port in ANY file is part of a module
# interface, and renaming one side of `.port(signal)` desynchronises it.
ports = set(re.findall(
    r'^\s*(?:input|output|inout)\s+(?:wire\s+|logic\s+|bit\s+)?(?:signed\s+)?'
    r'(?:\[[^\]]*\]\s*)?([a-z_][a-z0-9_]*)', whole, re.M))

decls = set(re.findall(
    r'^\s*(?:wire|logic)\s+(?:signed\s+)?(?:\[[^\]]*\]\s*)?([a-z_][a-z0-9_]*)\s*[;=,]',
    whole, re.M))

cand = sorted(n for n in decls - ports if ('%s_p%d' % (n, k)) not in whole)
if cand:
    # ONE global map applied to every file including .svh. The macros in
    # psg_common.svh expand to signal names (PSG_OSC_W14 is
    # {s_lp[16], old_mode_r, s_brown}), so renaming only *.sv leaves those
    # bodies pointing at the old identifiers, Verilog implicitly declares them
    # undriven, and the CIRCUIT changes - which is what the pre-map guard
    # caught the first time this was attempted.
    for n in rng.sample(cand, max(1, len(cand) // 3)):
        pat = re.compile(r'(?<![.\w])%s\b' % re.escape(n))
        rep = '%s_p%d' % (n, k)
        for f in srcs:
            text[f] = pat.sub(rep, text[f])

for f in srcs:
    f.write_text(text[f])
PYEOF

# ------------------------------------------------------------------- stage
k=0
while [ "$k" -lt "$N" ]; do
  D="$WORK/s$k"; mkdir -p "$D"; cp -R rtl "$D/rtl"
  if [ "$k" -gt 0 ]; then
    python3 "$WORK/perturb.py" "$D/rtl" "$k"
    if diff -rq rtl "$D/rtl" >/dev/null 2>&1; then
      echo "sample $k: perturbation was a NO-OP - refusing to report a fake spread" >&2
      exit 3
    fi
  fi
  echo "$k" >> "$WORK/list"
  k=$((k + 1))
done

# -------------------------------------------------------------------- run
# Independent samples, so run them concurrently. One yosys invocation each:
# stop at map_luts, tee the pre-map stat, then resume to the end and write the
# JSON - rather than paying the whole front end twice.
# A plain job pool rather than `xargs -P -I`: macOS xargs refuses to assemble
# a replacement command this long ("command line cannot be assembled").
run_one() {
  cd "$WORK/s$1" || return 1
  yosys -p "read_verilog -Irtl -sv rtl/target_psg.sv; \
            synth_ice40 -top target_psg $MAP -run :map_luts; tee -o premap.txt stat; \
            synth_ice40 -top target_psg $MAP -run map_luts:; write_json psg.json" \
    > yosys.log 2>&1 || echo "sample $1 FAILED (see $WORK/s$1/yosys.log)" >&2
}

i=0
for k in $(cat "$WORK/list"); do
  run_one "$k" &
  i=$((i + 1))
  [ $((i % JOBS)) -eq 0 ] && wait
done
wait

# ---------------------------------------------------------------- collect
printf '== psg floor distribution: %s (%s samples, %s-way) ==\n' "$LABEL" "$N" "$JOBS"
printf '  %-6s %8s %8s %8s %8s\n' sample premap LUT4 unpack floor

FLOORS=""; PM0=""; PREMAP0=""
k=0
while [ "$k" -lt "$N" ]; do
  D="$WORK/s$k"
  if [ ! -f "$D/psg.json" ]; then
    printf '  %-6s %8s\n' "$k" FAILED; k=$((k + 1)); continue
  fi
  PM=$(awk '/=== design hierarchy ===/{h=1} h && /^ *[0-9]+ +cells$/{print $1; exit}' "$D/premap.txt")
  CENSUS=$(python3 "$ROOT/tools/psg_ff_census.py" "$D/psg.json" | sed -n 2p)
  LUT4=$(echo "$CENSUS" | sed -E 's/.*LUT4 +([0-9]+).*/\1/')
  UNPK=$(echo "$CENSUS" | sed -E 's/.*, ([0-9]+) unpackable.*/\1/')
  FLOOR=$((LUT4 + UNPK))
  [ -z "$PM0" ] && PM0="$PM"
  [ -z "$PREMAP0" ] && PREMAP0="$PM"
  if [ "$PM" != "$PM0" ]; then
    printf '  %-6s %8s %8s %8s %8s   DISCARDED (pre-map moved: rename changed the circuit)\n' \
           "$k" "$PM" "$LUT4" "$UNPK" "$FLOOR"
  else
    printf '  %-6s %8s %8s %8s %8s\n' "$k" "$PM" "$LUT4" "$UNPK" "$FLOOR"
    FLOORS="$FLOORS $FLOOR"
  fi
  k=$((k + 1))
done

# Persist for reuse: an unchanged baseline should never be measured twice.
mkdir -p "$CACHE"
printf '%s\n%s\n' "$PREMAP0" "$(echo $FLOORS)" > "$KEY"

report "$LABEL" "$PREMAP0" "$FLOORS"
