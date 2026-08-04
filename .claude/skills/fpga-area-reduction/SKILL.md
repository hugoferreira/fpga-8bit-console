---
name: fpga-area-reduction
description: >
  Measurement discipline and lever taxonomy for shrinking an FPGA design's area
  (logic cells, LUT4s, carries, flops, BRAM) without changing what it computes.
  Use this skill whenever the work touches synthesis area or fit: "reduce LC
  count", "it doesn't fit on the hx8k", "optimise the PSG/PPU/CPU area", "we're
  at 97% utilisation", "make this cheaper in hardware", "why did that change
  make it bigger", a `/goal` about area, or any A/B of two RTL spellings. Also
  use it when someone reports "no measurable gains" from RTL restructuring, when
  a change looked smaller in isolation but grew the whole design, or when you
  are about to quote a synthesis number as evidence — most of the failure modes
  here are measurements that silently mean nothing. Applies to yosys/nextpnr
  flows generally; `references/psg-project.md` has this repo's exact commands.
---

# FPGA area reduction

Area work fails in a specific way: you restructure RTL for hours, the numbers
don't move, and you conclude the design is already minimal. Usually the design
isn't minimal — the metric was blind, or the lever class was one that cannot
pay on this fabric. This skill is the accumulated correction, extracted from a
campaign of 154 recorded hypotheses on an iCE40 HX8K.

Two habits carry most of the value: **measure at the layer that answers your
actual question**, and **ablate rather than read** when hunting for candidates.

## 0. Budget first — this work fails by bureaucracy more often than by physics

A recorded session spent ~200k tokens and 103 tool calls to produce **one line
of changed RTL and no verdict**. The proof was excellent (5 calls). Everything
else was orientation it could have cached and verification it had to
rediscover. Before starting, hold yourself to this shape:

**A hypothesis is a transaction with a cost ceiling.** From "I have a
candidate" to "I have a whole-design verdict" should be roughly 15–25 tool
calls. If you blow through that, the hypothesis is mis-scoped, not unlucky —
kill it, record what it cost and why, and pick a smaller one. A rejected
hypothesis recorded in 20 calls is a *good outcome*; an unfinished one at 100
is not.

**Orientation is bounded, and it is not the ledger.** Read the project
reference file and the ledger's *Current State* and *Handoff* blocks. Then grep
the ledger for your family name only. Do not read its body — it is thousands of
lines and it is an archive, not a briefing. Never re-derive build commands from
the Makefile; if a command you need isn't in the reference file, add it there
once so the next session doesn't pay again.

**Get the cheap verdict before the expensive one.** The pre-map delta takes ~20
seconds and kills most candidates. Run it *first* — before the map, before the
exactness proof, long before the behavioural battery (§3). If the delta is
inside the noise band, stop there and say so; that is a complete, publishable
result, not a failure to finish.

**Batch the candidates before working any of them** (§6). One hypothesis at a
time pays orientation on every iteration and drifts toward whatever is
adjacent; a ranked pool pays it once and spends context on the best classes
first.

**The battery is the last thing you spend, and it must be one command.** Never
discover gates by grepping; never run them concurrently with the area verdict
"to save time", because a rejected candidate then pays full price. And never
pipe a gate without `set -o pipefail` — `make test-psg 2>&1 | tail -30` reports
success while failing, which has happened here.

**Fix the environment once, loudly.** Stale build objdirs carrying another
machine's paths broke two suites and took two sweep attempts in that session.
When a gate fails for a reason that isn't your change, stop and fix the cause
in the repo rather than working around it — otherwise every future session pays
the same tax and reads it as a real failure.

**Reserved IDs are not a work queue.** If the ledger says the campaign closed
by measurement, the next number is not the next task. Starting H<n+1> because
it exists is how a closed campaign reopens without a new door. What licenses a
retry is a *changed condition*, and each rejected row states its own.

**A goal that cannot be falsified cannot be finished.** "Optimise X" installs
no stopping condition, so the session runs until it exhausts context.
Restate it as something with an edge before you begin — "land or refute three
hypotheses", "reach ≤ K LC or report the honest remaining sum" — and treat
reaching that edge as success even when the answer is "no further gain is
available at this fidelity". §9 is what that report looks like.

## 1. Measure with a deterministic instrument; ship with the good one

**Read this before the table in §1b, which predates it and is wrong about
resolution.** abc9's LUT covering is sensitive to how the netlist is *encoded*
— cell and net names, and the tie-breaks they drive — not only to what the
circuit computes. Measured on this repo's PSG by renaming a third of the cells
with the circuit provably identical (pre-map count pinned): the packing floor
ranges over **62–72 cells**. That is *wider than the ±60 band* the rest of this
document treats as its resolution limit. A single abc9 build therefore cannot
resolve anything below roughly a hundred cells, and most sub-100-cell verdicts
taken that way were never measurements.

This is a named, studied phenomenon — Kahng & Mantik, *Measurement of Inherent
Noise in EDA Tools* (ISQED'02). Their taxonomy transfers: cell/net **ordering**
is canonicalised away and changes nothing; **RNG seeds** move quality ~0.25%;
**naming** moves it up to ~7%, and scrambling name-encoded hierarchy up to 12%.
They also found noise is **not additive** across perturbations — which is why
two changes measuring 0 and +31 here composed to −33.

Do not judge a candidate on one abc9 build. Use a low-variance ruler:

| Instrument | Spread over renames | Use |
|---|---|---|
| **pre-map cells** | **0** by construction | circuit complexity; cheapest honest number |
| **`-noabc` floor** (built-in techmap) | **0** measured | did it survive covering? |
| `-noabc9` classic abc floor | 9 **(n=6 - underestimated)** | **do not trust alone**: read -28/-49 on H162 changes abc9 could not distinguish from zero |
| **abc9 floor** | **62–72** | the shipped metric — only ever as a *distribution* |

`scripts/detfloor.sh <unit>` prints the first three in one command.
`tools/psg_area_dist.sh N label` samples the abc9 distribution: it perturbs
names, **asserts pre-map invariance** so a rename that changes the circuit is
discarded rather than inflating the spread, and reports median/IQR/spread.

**Order of use.** A candidate must move the deterministic numbers in the right
direction first. If pre-map and `-noabc` disagree in sign, it is not a
structural improvement and no amount of abc9 sampling will make it one. Only
when they agree is it worth sampling abc9 — n≥16 per arm, compared with a
**rank test (Mann–Whitney)**, statistic named *before* looking. Never two point
builds.

**Corollary that reverses this document's earlier advice:** pre-map is not
merely a screen. It is the only number that is both stable and free, and it has
now agreed with `-noabc` on every candidate measured both ways. Read a pre-map
delta as evidence about *where the distribution sits*, not as a prediction of
one draw.

**When the deterministic instruments disagree with each other, believe the ones
with a measured spread.** On H162, classic-abc read −28 and −49 on two changes
that abc9 could not distinguish from zero (p≈0.36, p≈0.13) and that pre-map and
`-noabc` both called slightly worse. Its "spread 9" was estimated from n=6.
Fall back to sampling the shipped mapper rather than picking whichever proxy
agrees with you — and note this is exactly the moment a pre-registered rule
gets quietly reinterpreted, so re-register instead.

**Two ways a noise sampler lies, both shipped here before being caught.** A
perturbation that is silently a no-op reports a confident spread of 0 that
reads as "the tool is stable" — guard by asserting the tree actually changed.
And a perturbation that changes the *circuit* (renaming RTL identifiers
desynchronised macro bodies in a `.svh`, implicitly declaring undriven nets)
produces a beautiful, entirely fictional distribution — guard by asserting the
pre-map count is identical across samples, since pre-map is naming-invariant.

## 1b. Three metrics, three different questions

Never report "the area" — report which layer moved.

| Layer | Command shape | Cost | Answers |
|---|---|---|---|
| **Pre-map structural** | `synth_ice40 -run :map_luts; stat` | ~25 s | Did gates, carries and flops actually leave the netlist? |
| **Mapped + packing floor** | full `synth_ice40 -json`, then a packing census | ~2 min | Will the removal survive LUT covering, and do the flops pack? |
| **Placed LC + routed Fmax** | `nextpnr --seed 1` | ~3 min | Does it fit, and does it still make timing? |

The layers disagree, and each disagreement is informative rather than noise:

- **Pre-map is the number that does not move under abc9's naming sensitivity.**
  Judge whether a change is real on this one.
- **Placed cells are deterministic but not insensitive.** On this design,
  adding an *unused module parameter* left the pre-map netlist bit-for-bit
  identical (14,398 cells, every gate type, 1,610 flops) and still moved placed
  cells by **59**. That is abc9's LUT covering being order- and name-sensitive.
  So a placed delta under roughly 60 cells cannot distinguish a real saving
  from a mapping reshuffle. Placement across five nextpnr seeds is identical —
  only Fmax moves (~2.4 MHz spread) — so this is *not* placer noise, and the
  fix is not more seeds.
- **Pre-map is only a proxy, and the proxy ratio is not uniform.** Before
  believing a large structural delta, ask which cell family produced it:

  | Family | pre-map : mapped | Verdict |
  |---|---|---|
  | carry-chain arithmetic on free variables | ~1:1 | honest |
  | `$div` / `$mod` by a constant | ~11:1 | fiction |
  | shared decode fabric | n/a | count drops, nothing retires |

  Worked example: ablating a `/3` reads **−726 structural cells**. The divider
  is 713 pre-map cells but **63 placed LCs**, because yosys lowers `$div` to a
  restoring array *before* exploiting the constant divisor and abc9 then deletes
  ~92% of it. Its exact algebraic replacement is 108 pre-map cells that are all
  real, and maps **worse** (+57 LUT4, +22 placed).

## 2. The packing rule that unblocks "no measurable gains"

On iCE40 a logic cell is one LUT4 plus one flop, but the flop shares the cell
**only with the LUT driving its own D input, and only at fanout 1**. Every flop
that fails that test burns a whole cell whose LUT half is wasted — and a mapped
LUT4 count never shows it.

On this design at handover: **671 of 1,557 flops unpackable**, mapped 5,659 vs
placed 6,662. Two earlier serialization stages had been rejected on the blind
mapped number. Once the packing census existed, the route-through register
families it ranked became the targets that actually paid.

The equivalent question on any fabric: *what does my area metric structurally
refuse to see?* Find that before trusting a flat result.

## 3. Cost-ordered acceptance funnel

**Measure area before you prove correctness.** This is the opposite of the
usual instinct, and it follows from an asymmetry that matters more for an agent
than wall-clock does: synthesis is one command, ~20 seconds, ~20 lines of
output — nearly free in context. An exactness proof is an enumerator, a miter,
and several debug rounds — expensive in exactly the resource that runs out. Most
candidates are not smaller, so proving them first means paying the expensive
step for work that gets thrown away.

You do not need a candidate to be *correct* to measure its area. You need it to
be *structurally complete*: every case handled, every width final, elaborating
cleanly. A stub that skips cases is smaller because it is wrong, and measuring
it is the same error as ablating to a constant (§5).

So: derive the transform informally, write the complete candidate, and let
synthesis decide whether it earns a proof.

| # | Gate | Cost | Kills |
|---|---|---|---|
| 1 | **Pre-map delta** (`scripts/premap.sh`) | ~20 s, 1 call | most candidates |
| 2 | **Whole-design map + placed** | ~5 min, 1 call | the locally-smaller-globally-larger class |
| 3 | **Exactness proof** — exhaustive enumeration over the finite domain, or a yosys SAT miter (`prep -top <miter>; sat -prove ok 1 -verify`) | expensive in context | wrong candidates that happened to be smaller |
| 4 | **Route + timing** at the fixed seed | ~3 min | congestion and Fmax regressions |
| 5 | **Behavioural battery** | ~20 min | everything else |

Stop at the first failure, revert, and record the row. A candidate rejected at
gate 1 in two tool calls is a *complete result* — write it down with its number
and move on.

**An unresolvable delta is a stop, not a maybe.** If the placed delta is inside
the design's naming band (±60 here, §1), the candidate has *no measured area
effect* and nothing downstream can create one. Record it as unresolved and
revert. The failure this prevents is expensive and has happened: a recorded
session measured its candidate at **7,052 placed cells against a 7,055
baseline — a 3-cell delta, twenty times below the noise floor — and then ran
the entire acceptance battery on it anyway**: the model suites, the 59-render
sweep, clicks, recovery, lint, and two forced reproducibility rebuilds with
JSON/ASC byte-identity checks. Roughly 50 tool calls and most of a 200k context
spent validating a number that was never distinguishable from a mapping
reshuffle. The area verdict had been on screen since call 50.

**Never run gates 3–5 concurrently with gates 1–2 "to save wall-clock".** It
feels efficient because the machine is idle, but a candidate that fails the area
verdict has then paid the full battery price, and the outputs still have to be
read, which is the cost that actually hurts. A recorded session launched the
battery while the map was still running, spent ~60 tool calls on it, and never
reached a verdict at all.

**Isolated synthesis is a diagnostic, not a gate.** Lifting the cone
registered-in/registered-out tells you *why* a number moved, so reach for it
after a surprising whole-design result. Do not put it in the funnel: it
mispredicts, and the whole-design map it would be screening for is only a few
minutes anyway.

**Isolated wins reverse globally, routinely.** In the recorded ledger, H009,
H010, H012, H013, H016–H020, H032, H034, H036, H040 and H149–H154 were all
exact *and* locally smaller, and every one grew the whole design. Recent
examples: H152 retired 8 flops and 5 isolated floor cells, then added **72
LUT4 and 72 floor cells** whole-PSG; H154 improved the isolated floor 148 → 146
and added **51 LUT4 and 52 floor cells**.

The mechanism is always the same — see THE LAW.

## 4. THE LAW: selection eats arithmetic

**LUT4s absorb selection conditions into the arithmetic for free.** A 2-input
add with a 2-way select costs the same LUT4 count as the add alone. Deleting
the mux saves nothing — and every restructure that moves selection *out* of the
arithmetic (serial engines' operand arms, masked adder trees, microword control
tables, aliased mux defaults, shared ALUs) must **buy new selection hardware
that the combinational form got gratis**.

Measured consequences, all with numbers:

- Blend family reshaped three ways: **+31 / +35 / +132**.
- Dead-mux-arm aliasing (pointing a constant default at a live net):
  **+115 structural.** Constant default arms are already free; aliasing creates
  *series routing* between muxes, not sharing.
- Seven narrow exclusive adders folded into one masked tree: **+46**.
- Control-ROM decode replacing parallel IFs: **+154** in the priority-chain
  spelling. (The `(* parallel_case *) case (1'b1)` form recovered it to −59 —
  spelling matters more than structure here.)

**Corollary — select the operands, not the result.** Selection should happen
where the values are narrowest. A seven-arm 25-bit request mux where several
arms want the *same expression* collapsed to four arms by selecting the
13-bit inputs instead: **−168 pre-map, −54 placed**, byte-exact.

**Corollary — a partial migration off shared fabric pays nothing.** Peeling one
consumer off a shared decode network removes gates without retiring the
network, and abc9 then covers the remainder worse than it covered the whole.
Only take a structural win to synthesis when the network **stops existing**.

**Corollary — shared routing pays only through address-selected storage.** BRAM
ports have no per-bit input muxes, which is why every register-family migration
into block RAM won and every borrowed-register scheme lost (a borrowed register
costs a D-mux plus fanout-cone entanglement, and abc9 duplicates the formerly
separate islands).

### What actually pays

1. **Invisible bounds** — properties provable from table contents or algebra
   but invisible to synthesis. The richest class found. Narrowing every
   increment carrier 24→21 bits on a proved table ceiling: **−128 placed,
   −209 structural** in one stage. Adders launder visible zeros, so synthesis
   keeps full paths for values that cannot fill them.
   *But*: a bound on a **bit position** is not an invisible bound. Narrowing
   operand arms whose high bits no consumer reads is **exactly 0** — synthesis
   flattens before optimising and already pruned them. The bound must be on a
   **value**.
2. **Wide identity bundles** — removals of carry chains. Only wide retirements
   pay; narrow exclusive adders under a value mux are already optimal.
3. **Route-through register families into address-selected storage.**
4. **Whole-cell decode fabric** that stops existing.
5. **Congestion relief.** When the fabric is ~97% full, every removal un-jams
   packing: a −67 structural bundle became **−190 placed**. Placed can beat
   structural ~3×. This only appears near the fit boundary.

### A reusable arithmetic identity

For a surviving constant divisor, with `x = 2^k·h + l` and `2^k = d·m + 1`:

```
x/d  =  m·h + (h + l)/d       exactly
```

and `h + l` is small enough to be a **table**. `256h = 3·85h + h` (512 entries),
`512h = 7·73h + h` (1024), `256h = 15·17h + h` (2048). Eleven-plus CSD adds
become four. Crucially the table read *is* the pipeline register the cone
already had, so no stage is added and no schedule moves — build the index in
stage 1 from the combinational value.

## 5. Finding candidates: ablate, don't read

Reading RTL to guess where the area is wastes hours. **Two synthesis runs found
what hours of reading had not**: stubbing each reciprocal priced one divider at
161 LC and a pair at 219 — 380 of an 878-cell cone in three constants.

Two rules, both learned by getting them wrong:

- **Ablate to the proposed replacement, never to a constant.** Ablating a comb
  filter to zero priced it at −158 and looked like the session's best lead.
  Ablating it to its *actual* replacement — the identity — is **0**. A constant
  ablation prices the cone **plus everything downstream that folds with it**.
- **Ablation numbers are ceilings, and they over-attribute.** Treat them as
  "no more than this", never as a forecast.

Then census the netlist to rank targets — and **check cell names before
believing a per-module attribution.** On a flattened netlist a module read as
670 LUT4 for "one iterative multiplier"; ~470 of that was the *request mux*,
flattened in and named after the flop it drives.

## 6. Run a ranked pool, not one hypothesis at a time

Working one candidate at a time pays the orientation cost on every iteration,
and it follows the local gradient — the next register, the next ID — which is
how a campaign ends up mining 3-cell shavings while whole lever classes sit
unexamined. Generate a **pool** first, rank it, then walk it.

**Seed the pool from the census and ablation, not from reading.** §5 is the
generator: the census ranks where the flops and cones actually are, and
ablation prices the top entries. A pool built from empirical rankings covers
the design; a pool built from reading RTL covers whatever you read last.

**Rank by lever class first, magnitude second.** Per-hypothesis magnitude
estimates in this domain are badly calibrated — recorded misses include a
predicted −20 flops landing at **+70**, formally exact restructurings landing
at **+46 / +115 / +154**, and a dozen isolated-floor wins that reversed on the
whole design. What *is* predictive is the class, because those priors were
measured (§4): invisible bounds and wide carry retirements paid; every shape
that moved selection out of arithmetic charged. So sort by class prior, and let
your magnitude guess break ties within a class only.

**Reject or bundle anything under the noise band at pool time.** A candidate
whose honest ceiling is below the naming band (±60 here) cannot produce a
resolvable result on its own no matter how well it is executed. Drop it, or
bundle related ones into a single stage whose combined delta clears the band.
Skipping this is how a campaign accumulates fifteen consecutive unmeasurable
hypotheses.

**Do not over-analyse the pool.** Gate 1 costs 20 seconds and one call.
Estimating carefully costs more context than measuring, so for anything cheap
to prototype, measure. The ranking exists to order the measurement queue, not
to replace it. Reserve real estimation for candidates that are expensive to
*build* — engine rewrites, schedule changes, anything touching many files.

**Re-rank after every landing.** The pool decays as you work it: landing a
stage changes congestion (which can be worth 3× the structural delta near a
full fabric), and two candidates peeling at the same shared fabric cannot both
pay. Re-run the census after each accepted stage instead of executing a static
ranking to the end.

One line per candidate is enough:

```
| id | lever class | target family (census) | honest ceiling | build cost | blockers |
```

## 7. The hypothesis ledger

154 experiments only stay tractable because each is recorded in a fixed shape
with an explicit re-entry condition. Without the last field you will re-run
rejected work every few sessions.

```markdown
## Hypothesis H<NNN>

- **ID:** H<NNN>.
- **Hypothesis:** the exact transform, in prose, including what it exchanges
  for what ("this should exchange one newly-live payload flop and a narrow
  decode for four source-domain count flops").
- **Scope:** what must be proved, what may be edited, and every property that
  must be preserved (values, latencies, interfaces, BRAM topology, tolerances).
- **Baseline:** commit + RTL fingerprint + the full resource vector
  (LUT4 / carries / flops / unpackable flops / BRAM / packing floor /
  routed LC @ Fmax).
- **Changed condition versus H<prior>:** why this is not a repeat. Name the
  earlier hypotheses it resembles and state the difference.
- **Change:** what was actually done, in order.
- **Result:** fill EVERY instrument line; "n/r" only if genuinely not run.
  A single abc9 build is **never** a verdict - not for acceptance, not for
  rejection.

  ```
  pre-map cells      <base> -> <cand>  <d>   [deterministic]
  -noabc floor       <base> -> <cand>  <d>   [deterministic, spread 0]
  unpackable flops   <base> -> <cand>  <d>   [reliable]
  LUT4               <base> -> <cand>  <d>   [NOISY - never the verdict]
  abc9 floor         median <b> -> <c>, n>=16/arm, U=<u>/<max>, p=<p>
  EBR / placed / Fmax                        [placed+Fmax are one draw]
  ```

  Record unpackable flops **separately** from LUT4: flops are reliable, LUT4 is
  where the noise lives. One candidate predicted -12 flops and delivered
  exactly -12 while its LUT4 moved +17. And isolated synthesis is not a verdict
  either - a small cone gives the mapper fewer covering options, so it has
  *more* variance than whole-design, not less.
- **Decision:** accepted / rejected and reverted / rejected before production.
- **Repeat only if:** the specific condition that would make a retry sensible
  ("only after multiplier operand bounds, radix classes, or payload width
  change materially").
```

Also keep a **Saved Artifacts** table mapping each experiment's logs, proofs
and render evidence to the command that produced it, and a **Current State**
block naming the active hypothesis, the next free ID, and the accepted lineage.
Rejected entries are the ledger's most valuable content — they are what stops
the next session from rediscovering +115.

## 8. Traps that make a number mean nothing

- **A measurement without a fingerprint is not reproducible.** Quote
  `rtl <hash> @ <commit>` with every number. Two runs minutes apart once gave
  3,790 and 4,321 cells because another agent swapped a core underneath. An
  A/B of a shared file must run in an isolated tree copy.
- **A design with no non-constant output is trimmed away** and reports a
  spectacular Fmax. Keep a minimum-LC floor in the build that fails loudly.
- **Removing the bus master folds the subsystem behind it** — no CPU means the
  address bus is constant, chip-select never asserts, and 78% of the peripheral
  vanishes (1,467 vs 6,759 cells). Drive measurement targets from pins.
- **A probe pin that XOR-reduces its inputs** makes a replicated bus constant 0;
  the design folds to 103 cells and looks like a triumph.
- **A gate that runs in the working tree cannot see a bad commit.** An atomic
  width narrowing spanned three files; only one was staged; every gate passed
  because they all ran against the coherent working tree, and the commit
  rendered 199,987 of 200,000 samples wrong. Verify from
  `git archive HEAD | tar -x` into a clean directory. `git add <the file I
  edited>` is not `git add <the change>` — read the staged diff.
- **When someone else's change lands in your tree mid-task, you are measuring
  both.** One retirement was reported at −64, then "refuted" at +45; both trees
  were mismatched. On a coherent base it was −22.
- **A byte-compare against your own frozen renders is a regression gate, not a
  fidelity gate.** It proves nothing changed, so anything already wrong when
  the set was frozen stays green forever — that is exactly how a noise
  generator came to ignore note pitch under "59/59 byte-identical" after every
  change. Keep a separate gate that compares against the *external* reference,
  and prefer properties (trends across a sweep) over single-point tolerances.
- **Latency changes are not render-neutral when a consumer stalls on them, and
  one input is not a check.** A radix-4 multiplier that only got *faster* moved
  a music render 0.26%, because the microprogram gates on `!busy` and so
  advanced its PC ~5 cycles earlier. A fixed cycle budget does not fix this — a
  faster producer just lets the consumer get further. The mechanism was
  correctly identified at the time, checked on one track, and recorded as
  "every fidelity metric unchanged". A later bisect found that same commit is
  the first bad one for two *other* tracks: lock_tracked 0.855 → 0.555 against
  a 0.060 tolerance, and four spectral bands past 0.300. **When a change alters
  timing that feeds a stateful consumer, the fidelity check has to span the
  whole corpus** — the input you happen to pick decides whether you see it.

- **Bisect assumes monotonicity, and a half-staged commit breaks it.** A bisect
  over this history converged on a commit whose own message claimed the render
  was byte-identical. It was: the *next* commit was titled "restore the half of
  the increment narrowing I split off", and testing it directly returned GOOD.
  The convergence was on a transiently broken tree, not the regression. After
  any bisect through hand-split history, **test the commit immediately after
  the reported first-bad**; if it is good, the assumption failed and the real
  cause is later.

## 9. Knowing when to stop

Close a lever class by measurement, not by fatigue, and write the closure down.
A campaign is finished when every identified class has a measured verdict and
the honest remaining sum falls short of the target — at which point the
decision is the user's: re-scope the goal, or authorise a change that alters
behaviour. Present it that way, with the arithmetic:

> Remaining −700 is not reachable at byte-exact fidelity. Authorising crossfade
> removal (~−220) + custom instruments (~−170) + noise LP (−35) + all remaining
> honest stages (~−200) sums ~−890 from the original baseline.

Also check the denominator before promising anything: measure how much of the
target is actually the unit under study (here the harness was 32 of 6,481
LUT4s — no denominator relief existed).

## Project specifics

`references/psg-project.md` — the exact commands, tools, gate battery,
resource budgets and closed-verdict catalogue for this repo's PSG, PPU, CPU and
SoC targets. Read it before running anything here.

`scripts/premap.sh` — the pre-map structural metric for any `rtl/target_*.sv`.
