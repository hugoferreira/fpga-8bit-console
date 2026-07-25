#!/bin/sh
# Fmax, area and a per-function logic breakdown for the CPU core.
#
#   tools/cpu_measure.sh [label]
#
# Placement varies with the seed by several MHz, so three seeds are run and all
# three reported: a single number proves nothing. Everything is measured
# through rtl/cpu_fmax_top.sv - the core against a 2 KB synchronous-read RAM,
# no arbiter - so a difference between runs is a difference in the core.
set -e
LABEL=${1:-cpu}
mkdir -p build/fmax

yosys -q -p "read_verilog -Irtl -sv rtl/cpu_fmax_top.sv; \
             synth_ice40 -top cpu_fmax_top -json build/fmax/$LABEL.json" \
      > build/fmax/$LABEL.yosys.log 2>&1

echo "== $LABEL =="
for seed in 1 2 3; do
  nextpnr-ice40 --hx8k --package tq144:4k --freq 50 --seed $seed \
      --json build/fmax/$LABEL.json --asc /dev/null \
      > build/fmax/$LABEL.s$seed.log 2>&1 || true
  printf '  seed %s  ' "$seed"
  grep "Max frequency for clock" build/fmax/$LABEL.s$seed.log | tail -1 \
    | sed 's/.*: //'
done
grep -E "ICESTORM_LC:" build/fmax/$LABEL.s1.log | sed 's/Info:/ /'

python3 - "$LABEL" <<'PY'
import json, collections, re, sys
d = json.load(open(f"build/fmax/{sys.argv[1]}.json"))
top = ([m for m in d['modules'].values() if m.get('attributes', {}).get('top')]
       or list(d['modules'].values()))[0]
b = collections.Counter()
for name, c in top['cells'].items():
    if c['type'] != 'SB_LUT4':
        continue
    n = name.replace('\\', '')
    if not n.startswith('u_cpu.'):
        continue
    base = re.split(r'_SB_|\[', n[len('u_cpu.'):])[0]
    if base.startswith(('u_dec', 'dec_')):            k = 'decode'
    elif base.startswith(('alu_', 'bin', 'sbin', 'dal', 'dah', 'sal', 'sah')): k = 'ALU + BCD'
    elif base.startswith(('ab_c', 'adr', 'adl', 'zpa')): k = 'address path'
    elif base.startswith('pc'):                        k = 'PC'
    elif base in ('a', 'x', 'y', 's'):                 k = 'registers'
    elif base.startswith('st'):                        k = 'sequencer'
    elif base.startswith('f'):                         k = 'flags'
    else:                                              k = 'other:' + base
    b[k] += 1
tot = sum(b.values())
print(f"  {'':<16}{'LUT4':>6}{'share':>8}")
for k, v in b.most_common():
    print(f"  {k:<16}{v:>6}{100*v/tot:>7.1f}%")
print(f"  {'CPU LUT4 total':<16}{tot:>6}")
PY
