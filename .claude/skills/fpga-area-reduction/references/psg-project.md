# Project reference — fpga-8bit-console

Exact commands, budgets and closed verdicts for this repo. The method is in
`../SKILL.md`; this file is what you actually type.

## Contents

- [Targets and what they measure](#targets-and-what-they-measure)
- [The three metrics, concretely](#the-three-metrics-concretely)
- [Candidate hunting tools](#candidate-hunting-tools)
- [The gate battery](#the-gate-battery)
- [Current budgets and ceilings](#current-budgets-and-ceilings)
- [Where the history lives](#where-the-history-lives)
- [Closed verdicts — do not retry without the stated change](#closed-verdicts--do-not-retry-without-the-stated-change)

## Targets and what they measure

`make synth-cpu | synth-psg | synth-ppu | synth-soc | synth-all` — four
top-level circuits (`rtl/target_*.sv`, thin instantiations so subsystem numbers
cannot drift from the shipping design). Guide: `docs/build-targets.md`.

```bash
PATH=/opt/homebrew/bin:$PATH make synth-psg
```

Each run prints `rtl <hash> @ <commit>` — **quote that fingerprint with every
number**. Three agents edit `rtl/` at once here; two `synth-ppu` runs minutes
apart once gave 3,790 and 4,321 cells because a core was swapped underneath.
An A/B of a shared file must run in an isolated tree copy.

`SYNTH_MIN_LC_<unit>` is a floor that fails the build when the design folds to
constants. Prove it works with `make synth-cpu SYNTH_MIN_LC_cpu=99999`.
`target_psg` is driven from **pins**, not through `chip.sv` — with no bus
master the address bus goes constant, `psg_cs` never asserts and 78% of the PSG
vanishes (1,467 vs 6,759 cells).

Never add a port to `chip.sv`: Verilator escalates `PINMISSING` to an error, so
`top_simulator.sv` fails the moment a port exists it doesn't connect. Leave
verification-only ports unconnected as the board top does (`.psg_dbg()`) —
connecting `dbg` measures trimmed logic and eats 108 pins.

`make synth-psg SYNTH_SEEDS=5` reports Fmax across five placements (~5 MHz
spread). Placement itself is seed-invariant; use this only for timing risk.

Tang Nano 20K (Gowin GW2AR-18C) is the second board: `make tangnano20k-psg`,
resource parsing via `tools/gowin_stat.py`. See the `tangnano20k-target` memory.

## The three metrics, concretely

**Pre-map structural** (~25 s) — the number immune to abc9 naming:

```bash
yosys -p "read_verilog -Irtl -sv rtl/target_psg.sv; synth_ice40 -top target_psg -run :map_luts; stat"
```

`scripts/premap.sh psg` wraps this for any target.

**Packing census** — mapped LUT4s, carries, flops, and the packed/unpackable
split plus the packing floor, ranked by register family and by LUT cone:

```bash
python3 tools/psg_ff_census.py build/targets/psg.json --top 30
```

Read its docstring first — it carries the pre-map-vs-mapped ratio table and the
`$div` worked example. `--scopes` attributes cells to preserved yosys scopes,
but see THE LAW §5: on a flattened netlist a cone is named after the flop it
drives, not the module it came from.

**Placed LC + routed Fmax** — the tail of `make synth-<unit>`, seed 1.
`synth_ice40` already defaults to abc9 (yosys 0.67); flag experiments are a
measured dead end and `-abc2` is worse. The `-dff` flag measured −19: noise.

## Candidate hunting tools

| Tool | What it gives |
|---|---|
| `tools/psg_ff_census.py` | unpackable-flop families and LUT cones, worst first |
| `make psg-lifetimes` | register live ranges in the sample walk, and which pairs could share one — derived from the RTL, not from reading. The most reliable small lever and the least predictable |
| `tools/psg_buffers.py`, `tools/psg_hw_forms.py` | buffer/arithmetic form models for exactness proofs |
| ablation | stub a cone to its **proposed replacement** and re-synthesize (SKILL.md §5) |

## The gate battery

Cost-ordered, and **area comes before correctness** — see SKILL.md §3 for why.
Stop at the first failure. Most candidates die at step 1 or 2, and everything
below step 2 is expensive, so nothing there runs until the area verdict is in.

**Two commands, in this order. Do not run the second until the first says
CANDIDATE.**

```bash
make area-psg RECORD=1                 # once, on the accepted tree
make area-psg                          # ~5 min: the verdict + the band rule
make gates-psg CART=<celeste.p8.png>   # ~20 min: only after CANDIDATE
```

`make area-psg` (`tools/psg_area_gate.sh`) builds the candidate, prints the full
vector — premap, LUT4, carry, flops, unpackable, floor, placed, EBR, Fmax — and
compares it to the recorded baseline, then returns one of three verdicts:

| Verdict | Condition | Exit | What to do |
|---|---|---|---|
| **CANDIDATE** | floor improves, placed does not regress past the band | 0 | prove exactness, then `make gates-psg` |
| **REJECT** | floor regresses, or placed regresses ≥ band | 1 | revert, record the row |
| **UNRESOLVED** | placed delta inside ±60 and floor flat | 1 | revert, record as unresolved — the battery cannot create an effect that isn't there |

The floor is LUT4 + unpackable flops, which is the ledger's acceptance rule
("improve a deterministic mapped resource and do not regress placed LCs").
Override the band with `PSG_AREA_BAND=`.

`make gates-psg` (`tools/psg_gates.sh`) runs the battery fail-fast in cost
order — `sweep models mul oracle clicks recovery pico8 celeste` — tails the
failing log and prints the resume command. Useful flags:

```bash
make gates-psg CART=... GATES_FROM=oracle   # resume after a fix
tools/psg_gates.sh --only sweep             # one stage (hygiene sweep alone)
tools/psg_gates.sh --list                   # the stage names
```

It handles the two ways these gates lie, so you don't have to:

- **A piped gate loses its exit code.** `make test-psg 2>&1 | tail -30` prints a
  Verilator compile error and returns 0. Every stage is checked directly.
- **Stale Verilator objdirs** survive a branch change carrying absolute paths
  from wherever they were built, including other machines; the failure reads
  like a real compile error in your change. Stage 0 sweeps them, checking `.d`
  files too — sweeping only `*.mk` is why one session had to sweep twice.

It also refuses to call a run green when a cart-dependent stage was skipped
(exit 2, `NOT RUN`), and the oracle stage `cmp`s every render against the anchor
rather than trusting the matrix runner's exit code — **rc=0 there means
"completed", not "clean"**.

**KNOWN RED as of 2026-08-04: the `pico8` stage fails at HEAD.** Bisected to
**`24a465a` "perf(psg): multi-pump arithmetic and reclaim the /6 schedule"**
(2026-08-01) — its parent `e1d6c2d` is GOOD, and it is the only RTL-touching
commit in the bracket. Symptoms at HEAD:

```
music 20: lock_median   0.828 -> 0.717   (tolerance 0.040)
music 20: lock_tracked  0.855 -> 0.555   (tolerance 0.060)
music 40: band 250 Hz-1 kHz  local/quiet/whole   past 0.300
music 40: band 4-8 kHz       local/whole         past 0.300
```

The cause is the mechanism already recorded in the `psg-mul-alignment` memory:
the effect microprogram gates on `!m_busy`, so shortening multiply latency lets
the micro-PC advance ~5 cycles earlier per product. That was measured **on music
10 only** (0.26%) and recorded as "every fidelity metric unchanged" — music 20
and 40 were never checked. The 59-render byte sweep stays 59/59 green through
it, because those cases do not exercise chained music patterns.

Bisect notes for whoever picks this up: restrict with `-- rtl/` (38 candidates
instead of 255), use `--entries 20` (~4.6 min/run instead of ~23), and **test
the commit after the reported first-bad** — an earlier convergence on `6b28873`
was a half-staged commit repaired by the next one, not the regression. Runner
and per-commit logs: `build/bisect-fid/`.

**Two gate facts worth internalising:**

- `tools/psg_oracle_bytecheck.py` is a **regression** gate: it byte-compares
  today's RTL against frozen renders of *our own* RTL. Anything already wrong
  when the set was frozen stays green forever — that is how wave-6 noise came
  to ignore note pitch under "59/59 byte-identical". `tools/psg_fidelity_gate.py`
  is the one that compares against real PICO-8, and it tests the **trend across
  a pitch sweep**, because a generator right at one pitch and flat elsewhere
  passes every per-pitch tolerance you'd reasonably set.
- **A gate that runs in the working tree cannot see a bad commit.** Verify from
  `git archive HEAD | tar -x` into a clean directory — two minutes, and it is
  what caught a half-staged width narrowing that rendered 199,987 of 200,000
  samples wrong while every gate passed.

`make test-psg` under iverilog rotted once (declaration-after-use); `psg_tb`
runs under Verilator per its header. Its probes read `dut.` internals
hierarchically and hard-code record strides via a `VSTR` localparam — removing
an internal reg or changing the stride breaks the bind.

Never start a Verilog `//` comment with the word "Verilator": it parses as a
metacomment and errors (BADVLTPRAGMA).

## Current budgets and ceilings

- **Current recorded baseline** (`build/gates-psg/baseline.txt`, captured at
  `c1ad243`, fingerprint `1a76c4596af2`): premap 13,482 · **6,330 LUT4 · 1,292
  carries · 1,450 flops · 498 unpackable · floor 6,828 · placed 7,052** · 14 EBR
  · 33.50/138.20 MHz. Re-record with `make area-psg RECORD=1` whenever a stage
  is accepted, or every candidate after it is measured against stale numbers.
- Accepted H139 production: **6,302 LUT4, 1,291 carries, 1,450 flops, 498
  unpackable flops, 14 EBR, floor 6,800, routed 7,018 LC @ 142.63/31.17 MHz.**
  Durable physical baseline: `build/experiments/h139/candidate.*`.
- **The lineage has drifted +28 floor cells since H139** (6,800 → 6,828, LUT4
  +28, carries +1) across H155 and the source-clarity commits. Placed moved
  +34, which is inside the ±60 band and therefore says nothing — but **the floor
  is a deterministic mapped resource and the band does not apply to it**, so
  that +28 is real. Worth knowing before attributing a future candidate's cost
  to itself; it is not this skill's call whether it should be recovered.
- `rtl/target_psg.sv` is **REVERB=0 and must stay so** — the exact per-voice
  rings are 732×int16 each = 36 EBR against 32, so every number produced at
  REVERB=1 described a build that cannot exist.
- BRAM: see the `psg-bram-budget` memory. The 14-EBR topology is a preserved property
  in every hypothesis scope.
- Attribution: `target_psg`'s harness is 32 LUT4s of 6,481 — the metric *is*
  the PSG, no denominator relief exists.
- Cycle budget and the preview-vs-hardware schedule split:
  the `psg-cycle-budget` memory, the `psg-preview-path` memory. Do not "fix" hardware
  scheduling to the simulator number.

## Where the history lives

| File | Size | Contents |
|---|---|---|
| `openspec/changes/reduce-psg-ice40-area/rtl-area-continuation.md` | 8.7k lines | **H001–H154** — the hypothesis ledger. Current State, per-H rows, Saved Artifacts table, Handoff |
| `openspec/changes/reduce-psg-ice40-area/r78-continuation.md` | 3.6k lines | the R.84 stored-state executor loop (separately owned) |
| `openspec/changes/reduce-psg-ice40-area/design.md` | 2.9k lines | §5c ledger, §3 staging constraints, §23 the `/3` numbers |
| `openspec/changes/reduce-psg-ice40-area/tasks.md` | 2.4k lines | task tree |

Before proposing anything, grep the ledger for the family name. Every rejected
row carries a **"Repeat only if"** condition — that condition is the only
licence to retry.

Memory files with the distilled state: the `psg-area-reduction` memory,
the `psg-goal-minus-1000` memory, the `psg-mul-alignment` memory, the `psg-bram-budget` memory,
the `build-targets` memory.

## Closed verdicts — do not retry without the stated change

Numbers are whole-PSG unless marked isolated.

**Rejected mechanisms (structural, from THE LAW):**

| Attempt | Verdict |
|---|---|
| Blend family, three shapes | +31 / +35 / +132 |
| Dead-mux-arm aliasing to live nets | +115 struct. `mul_start_mode`'s zero default is *live* — an alias there is a real bug |
| Seven K-adders as one masked tree | +46 struct |
| Control ROM as parallel-IF chain | +154 struct (the `(* parallel_case *) case (1'b1)` form recovers it) |
| `sfx_id` record move | wash (+23 struct) — two async writers force 24 staging flops |
| pph address fabric as a control word | −75 pre-map → **+21 LUT4**, and costs a block |
| `nz_thresh = nz_sum / 3` algebraic replacement | ablates −726 pre-map, actual **+57 LUT4 / +22 placed** |
| `cmb_old` old-voice comb sharing | 0 (the −158 was a constant-ablation artefact) |
| Operand-arm narrowing on unread **bit positions** | exactly 0 — flattening already pruned them |
| H149/H151/H152/H154 | isolated floor wins of 3–8 cells; +47 / +25 / +72 / +52 whole-PSG |

**Closed by derivation — do not re-derive:**

- `m_p` cannot narrow below 34 bits. The bound is the intermediate
  (`|A|·2^12` with `|A|` reaching `0x1CE0<<8` = 2^33), not the final product.
- The multiply landing law: `m_p after M steps = |A|·B·2^(12 − RADIX_BITS·M)`.
  Every call site has a fixed N and compensates with a constant slice offset —
  **run `make test-psg-mul` before touching any consume slice**; it reads the
  boundary and iteration counts out of the RTL and names all five offsets.
- `m_p`'s 3-mode shift topology is schedule-load-bearing (blend product gap is
  9 cycles, mode 2 needs 12) — modes cannot unify.
- The `×3`s of triangle and tilt cannot merge: buzz-triangle consumes both
  chains in one evaluation.
- Division constants are already near-minimal (exhaustive `(mult, shift)`
  search) and their low bits are not free. The split identity in SKILL.md §4 is
  the form that *does* pay.
- Noise is sequence-inexact **in principle** (RNG shared across voices) — never
  chase byte-equality there; compare statistics and their pitch dependence.

**Live traps that cost debug cycles:**

- `m_res` holds the product **in place** (bit k = product bit k). "Volumes use
  `m_res[15:8]`" is a Q8 semantic scale, not a placement offset.
- `last_addr` looks removable but is load-bearing: the CPU writes `mus_pat`
  ungated by `walk_frozen`.
- Unbanked `playing[]` clears have **two visibility classes** — note-end/length/
  fade stops render from the boundary sample, music-flow stops from boundary+1.
- A signed `(j*rand) >>> 8` is floor; the multiply service's magnitude domain
  truncates toward zero. The negative arm must round up.
- The multiply request mux **drops rather than queues** — every new launching
  phase needs a simulation assertion that the service is idle there.
- Verilator 5 attributes a task's NBA writes to the calling `always_ff` only
  while each variable has a single write site across **all** tasks; a second
  site turns it MULTIDRIVEN. Spell overrides as one clr-priority mux write.
