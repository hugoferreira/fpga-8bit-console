#!/bin/sh
# The PSG correctness battery, as one fail-fast command.
#
#   tools/psg_gates.sh --cart <celeste.p8.png>
#   tools/psg_gates.sh --cart ... --from oracle    resume at a stage
#   tools/psg_gates.sh --list                      show the stages
#
# Run this only AFTER `make area-psg` returns CANDIDATE. These gates cost about
# twenty minutes; the area verdict costs one command, and most candidates do not
# survive it. A recorded session ran this whole battery concurrently with the
# area build and spent ~50 tool calls on a candidate whose placed delta turned
# out to be 3 cells - inside the naming band, i.e. not a measurement at all.
#
# It exists as a script because the battery was previously spread across the
# Makefile, the ledger and two docs, so every session spent ten to fifteen tool
# calls rediscovering it - and looked for "smoke" and "lint" targets that do not
# exist. If you add a gate, add it here.
#
# Two ways these gates lie, both handled below:
#   - a piped gate loses its exit code. `make test-psg 2>&1 | tail -30` prints a
#     Verilator compile error and returns 0. Everything here is checked directly.
#   - stale Verilator objdirs survive a branch change carrying absolute paths
#     from wherever they were built, including other machines. The failure reads
#     like a real compile error in your change. Stage 0 sweeps them.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

DIR=${PSG_GATES_DIR:-build/gates-psg}
ANCHOR=${PSG_ORACLE_ANCHOR:-build/psg_oracle/adopt-exact/rtl}
CASES=${PSG_ORACLE_CASES:-build/psg_oracle/cases}
CLOCK=${PSG_ORACLE_CLOCK:-18750000}
FROM=""
CART=""

STAGES="sweep models mul oracle clicks recovery pico8 celeste"

while [ $# -gt 0 ]; do
  case "$1" in
    --cart) CART=$2; shift 2 ;;
    --from) FROM=$2; shift 2 ;;
    --only) ONLY=$2; shift 2 ;;
    --list) echo "$STAGES" | tr ' ' '\n'; exit 0 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Fail before the twenty minutes, not after them - but only when a cart-needing
# stage is actually in this run (`--only sweep` should not demand one).
NEEDS_CART=yes
case "$ONLY" in ?*) case "$ONLY" in pico8|celeste) ;; *) NEEDS_CART=no ;; esac ;; esac

if [ "$NEEDS_CART" = yes ] && [ -z "$CART" ] && [ -z "$PSG_GATES_SKIP_CART" ]; then
  echo "usage: tools/psg_gates.sh --cart <celeste.p8.png>" >&2
  echo "  the pico8 and celeste stages need a cart; set PSG_GATES_SKIP_CART=1" >&2
  echo "  to run without them - they will be reported as NOT RUN, not as passes." >&2
  exit 2
fi

# `build/` is gitignored, so a fresh git worktree inherits NO frozen renders,
# case set or reference audio image - and the stages then fail with messages
# ("no anchor render set", "missing Celeste audio image") that read exactly
# like real regressions in the candidate. That cost two battery runs. Seed the
# read-only inputs from the main checkout instead of making every new worktree
# rediscover it. Only ever copies IN, never overwrites, and never touches the
# main checkout.
seed_from_main() {
  main=$(git worktree list 2>/dev/null | head -1 | awk '{print $1}')
  [ -n "$main" ] || return 0
  [ "$main" != "$(pwd)" ] || return 0
  for rel in "$CASES" "$(dirname "$ANCHOR")" build/p8ref; do
    src="$main/$rel"
    [ -d "$src" ] || continue
    [ -d "$rel" ] && continue
    mkdir -p "$(dirname "$rel")" && cp -R "$src" "$rel" \
      && echo "  seeded $rel from the main checkout"
  done
}

mkdir -p "$DIR"
seed_from_main
SKIPPED=""
STARTED=$(date '+%H:%M:%S')

for s in $FROM $ONLY; do
  case " $STAGES " in
    *" $s "*) ;;
    *) echo "no such stage: $s (have: $STAGES)" >&2; exit 2 ;;
  esac
done

# Stages run in order; --from skips everything ahead of the named one, --only
# runs exactly one (which is also how the hygiene sweep is used on its own).
SKIP_UNTIL=$FROM
active() {
  if [ -n "$ONLY" ]; then [ "$1" = "$ONLY" ]; return $?; fi
  [ -z "$SKIP_UNTIL" ] && return 0
  [ "$1" = "$SKIP_UNTIL" ] && { SKIP_UNTIL=""; return 0; }
  return 1
}

skip_reason() { if [ -n "$ONLY" ]; then echo "--only"; else echo "--from"; fi; }

run() {
  name=$1; shift
  active "$name" || { printf '  %-9s skipped (%s)\n' "$name" "$(skip_reason)"; return 0; }
  printf '  %-9s ' "$name"
  if "$@" > "$DIR/$name.log" 2>&1; then
    printf 'PASS\n'
  else
    printf 'FAIL\n\n'
    echo "  --- $DIR/$name.log (tail) ---"
    tail -25 "$DIR/$name.log" | sed 's/^/  /'
    echo
    echo "  Battery stopped at '$name'."
    echo
    echo "  BEFORE ATTRIBUTING THIS TO YOUR CHANGE, run the same stage on the"
    echo "  unmodified baseline. Some gates are red on main independently of"
    echo "  any candidate - 'pico8' regressed at 24a465a (multi-pump latency"
    echo "  advancing the !m_busy-gated micro-PC) and is still open. A failure"
    echo "  here reads identically whether it is yours or pre-existing:"
    echo
    echo "    git diff rtl/ > /tmp/cand.patch && git checkout rtl/"
    echo "    tools/psg_gates.sh --cart <cart> --only $name"
    echo "    git apply /tmp/cand.patch          # restore the candidate"
    echo
    echo "  (Save a patch rather than stashing: the stash stack is shared"
    echo "   across worktrees, and a concurrent session can pop yours.)"
    echo
    echo "  The workable acceptance rule is 'no gate worse than baseline',"
    echo "  not 'every gate green' - the latter is not currently achievable."
    echo
    echo "  Then fix or revert, and resume with:"
    echo "    tools/psg_gates.sh --cart <cart> --from $name"
    exit 1
  fi
}

# -- stage 0: build hygiene ---------------------------------------------------
# A Verilator objdir records absolute paths in its .mk AND .d files. Sweeping
# only *.mk misses the .d files, which is how one session had to sweep twice.
sweep_objdirs() {
  n=0
  for d in build/obj_* build/psg_oracle/obj_*; do
    [ -d "$d" ] || continue
    if grep -rhoE '/(Users|home)/[A-Za-z0-9_.-]+/[^ :"]*' "$d" \
         --include='*.mk' --include='*.d' --include='*.cpp' --include='*.h' \
         2>/dev/null | grep -qv "^$ROOT"; then
      echo "stale objdir (foreign absolute path): $d"
      rm -rf "$d"
      n=$((n + 1))
    fi
  done
  echo "swept $n stale objdir(s)"
}

# -- stage 4: the byte-exact render sweep -------------------------------------
# The matrix runner returns 0 for "completed", not for "clean", so the exit code
# alone proves nothing - the renders have to be compared against the anchor set.
oracle_sweep() {
  test -d "$ANCHOR" || {
    echo "no anchor render set at $ANCHOR"
    echo "  This is an ENVIRONMENT gap, not a candidate failure - see seed_from_main."
    return 1; }
  test -d "$CASES"  || { echo "no case set at $CASES"; return 1; }
  refs=$(dirname "$ANCHOR")/reference
  test -d "$refs" || { echo "no reference set at $refs"; return 1; }
  out=$DIR/oracle
  rm -rf "$out"; mkdir -p "$out/reference"
  # --skip-reference means "do not RENDER references", not "do not need them":
  # a case whose reference WAV is absent sends the runner down the PICO-8 export
  # path, which dies with "could not select MUSIC mode" partway through the
  # sweep and leaves the remaining renders simply missing. Seed them first.
  cp "$refs"/*.wav "$out/reference/" 2>/dev/null || true
  echo "seeded $(ls "$out/reference" | wc -l | tr -d ' ') reference renders from $refs"
  python3 tools/psg_oracle_matrix.py "$CASES" --out-dir "$out" \
          --skip-reference --clock "$CLOCK"
  n=0; bad=0
  for w in "$ANCHOR"/*.wav; do
    b=$(basename "$w"); n=$((n + 1))
    if [ ! -f "$out/rtl/$b" ]; then
      echo "MISSING render: $b"; bad=$((bad + 1))
    elif ! cmp -s "$w" "$out/rtl/$b"; then
      echo "DIFFERS from anchor: $b"; bad=$((bad + 1))
    fi
  done
  echo "compared $n renders against $ANCHOR, $bad differing"
  [ "$bad" -eq 0 ]
}

# A cart-dependent stage with no cart is announced, never silently dropped -
# a battery that quietly ran six of eight gates reads as green when it is not.
cart_stage() {
  name=$1; shift
  active "$name" || { printf '  %-9s skipped (%s)\n' "$name" "$(skip_reason)"; return 0; }
  if [ -z "$CART" ]; then
    SKIPPED="$SKIPPED $name"
    printf '  %-9s NOT RUN (no --cart)\n' "$name"
    return 0
  fi
  run "$name" "$@" CART="$CART"
}

# -----------------------------------------------------------------------------

echo "== psg gates == started $STARTED, logs in $DIR/"
# rtl/pll.v is generated (gitignored) - exclude it from the fingerprint.
echo "  rtl $(cat rtl/*.sv $(ls rtl/*.v 2>/dev/null | grep -v '^rtl/pll\.v$') 2>/dev/null | shasum | cut -c1-12) @ $(git rev-parse --short HEAD 2>/dev/null || echo no-git)"

run sweep    sweep_objdirs
run models   make test-psg
run mul      make test-psg-mul
run oracle   oracle_sweep
run clicks   make test-psg-clicks
run recovery make test-psg-preview-recovery
cart_stage pico8   make test-psg-pico8
cart_stage celeste make test-psg-celeste-tracks

echo
if [ -n "$ONLY" ]; then
  echo "  stage '$ONLY' passed. This is one gate, not the battery."
  exit 0
fi
if [ -n "$SKIPPED" ]; then
  echo "  ALL RUN GATES PASSED, but these were NOT RUN:$SKIPPED"
  echo "  That is not a green battery. Re-run with --cart before accepting."
  exit 2
fi
echo "  ALL GATES PASSED ($STARTED -> $(date '+%H:%M:%S'))"
echo "  Record the row: baseline vector, result vector, decision, repeat-only-if."
