# PSG RTL area continuation ledger

This is the resume surface for small, generic-RTL area and source-simplicity
experiments running independently of the R.84 stored-state executor work in
`r78-continuation.md`. Do not edit or integrate the R.84 executor from this
loop. Detailed earlier area history remains in `design.md`, `tasks.md`, and
`r78-continuation.md`.

## Context

- Topic: exact generic PSG RTL simplification and iCE40 HX8K area reduction.
- Owner scope: existing production RTL outside the R.84 executor/controller
  replacement; each hypothesis records its exact RTL and proof boundary.
- Correctness gate: proof of exact arithmetic, focused model/unit tests,
  `make test-psg`, 59-render PICO-8 regression, and no weakened tolerance.
- Physical gate: canonical `PATH=/opt/homebrew/bin:$PATH make synth-psg` with
  seed-1 router2 placement, routed timing, mapped resources, and 14 or fewer
  EBRs. An accepted area change must improve a deterministic mapped resource
  and not regress placed LCs.
- Dirty-tree constraints: stage only the active RTL, proof, generated artifact,
  and this ledger. Companion R.84 files and unrelated user work are excluded.
  H096 resumes from merged clean main `a84dbff` on its dedicated branch.

## Current State

- Active hypothesis: none; H001--H003, H005, H007, H022, H023, H027, H030,
  H031, H039, H044, H047, H051, H056, H057, H069, H075, H080, and H089
  accepted; H095 accepted on the direct lineage; H096 accepted on merged main.
- Next hypothesis ID: H102.
- H101 hypothesis row: store the four pending trigger row/length tuples in one
  prefetched block RAM, with resettable per-field valid bits preserving zeroed
  state and same-edge CPU-write precedence. A plain EBR has a one-cycle stale
  read counterexample; both exact forwarding variants exceed the 97-cell
  isolated reference floor. Archive audit: this inadvertently duplicated
  legacy R.44's already-closed mechanism; no production edit was repeated.
  Decision: rejected before production RTL.
- H100 hypothesis row: restrict `released` storage to the four foreground
  slots. Music-slot bits have no set path and are therefore invariant zero;
  their loop condition can bypass the foreground array. The proof passes
  2,560 transitions, but Yosys already removes the upper elements and both
  complete isolated forms map identically. Decision: rejected before
  production RTL.
- H099 hypothesis row: stop rewriting the effective channel-filter tuple from
  the base tuple and publish the already-live base tuple when `w_ins_on=0`.
  The ownership proof passes 4,224 legal paths and the isolated consumer falls
  from 29 to 12 LUT4s, but both whole-PSG variants regress. Decision: rejected
  and reverted.
- H098 hypothesis row: encode the fast multiplier's exact 3--12 active-step
  durations as start points on one four-bit maximal-LFSR segment. The token is
  exact and removes four LUT4s/two carries in isolation, but the whole PSG adds
  20 LUT4s, 19 floor cells, and 16 routed LCs. Decision: rejected and reverted.
- H097 hypothesis row: retire `ml_cpu` by reusing `walk_tick` as the
  `ML_STOP` provenance token. The invariant is exact and saves three LUT4s and
  one FF in isolation, but the whole PSG adds 18 LUT4s, four carries, 17 floor
  cells, and 20 routed LCs. Decision: rejected and reverted.
- H096 hypothesis row: retire `tch_seen` by consuming the existing launched-
  channel worklist when the left-most qualifying music channel owns pattern
  pacing. Exhaustive scan equivalence covers all 256 launch/qualifier masks.
  The complete merged-main battery passes, and two forced builds reproduce
  6,364 LUT4 / 1,321 carry / 1,459 FF / 509 unpackable / 14 EBR / floor 6,873 /
  7,095 routed LCs at 151.17/33.09 MHz. Decision: accepted as generic RTL/proof
  commit `a647185`. Repeat only if launch ordering, T_NL visitation, or pacing
  ownership changes.
- Current evidence: `build/experiments/h001/` and
  `build/experiments/h002/`, `build/experiments/h003/`, and
  `build/experiments/h005/`, `build/experiments/h007/`,
  `build/experiments/h022/`, `build/experiments/h023/`,
  `build/experiments/h024/`, `build/experiments/h025/`, and
  `build/experiments/h026/`, `build/experiments/h027/`, and
  `build/experiments/h028/`, `build/experiments/h029/`,
  `build/experiments/h030/`, `build/experiments/h031/`, and
  `build/experiments/h032/`, `build/experiments/h033/`, and
  `build/experiments/h034/`, `build/experiments/h035/`, and
  `build/experiments/h036/`, `build/experiments/h037/`,
  `build/experiments/h038/`, `build/experiments/h039/`, and
  `build/experiments/h040/`, `build/experiments/h041/`, and
  `build/experiments/h042/`, `build/experiments/h043/`, and
  `build/experiments/h044/`, `build/experiments/h045/`, and
  `build/experiments/h046/`, `build/experiments/h047/`, and
  `build/experiments/h048/`, `build/experiments/h049/`, and
  `build/experiments/h050/`, `build/experiments/h051/`, and
  `build/experiments/h052/`, `build/experiments/h053/`, and
  `build/experiments/h054/`, `build/experiments/h055/`, and the copied direct-
  frontier `build/experiments/h056/`, `build/experiments/h057/`,
  `build/experiments/h058/`, `build/experiments/h059/`, and
  `build/experiments/h060/`, `build/experiments/h061/`, and
  `build/experiments/h062/`, `build/experiments/h063/`, and
  `build/experiments/h064/`, `build/experiments/h065/`, and
  `build/experiments/h066/`, `build/experiments/h067/`, and
  `build/experiments/h068/`, `build/experiments/h069/`,
  `build/experiments/h071/`, `build/experiments/h072/`,
  `build/experiments/h073/`, `build/experiments/h074/`,
  `build/experiments/h075/`, `build/experiments/h076/`,
  `build/experiments/h077/`, `build/experiments/h078/`,
  `build/experiments/h079/`, `build/experiments/h080/`, and the accepted
  `build/experiments/h089/`, `build/experiments/h090/`, and
  `build/experiments/h091/`, `build/experiments/h092/`, and the rejected
  `build/experiments/h093/`, the rejected `build/experiments/h094/`, and the
  accepted `build/experiments/h095/` and `build/experiments/h096/`, the
  rejected `build/experiments/h097/`, `build/experiments/h098/`, and
  `build/experiments/h099/`, plus
  `build/experiments/h009/`, `build/experiments/h010/`, and
  `build/experiments/h012/` and `build/experiments/h013/` synthesis,
  placement, click, recovery, and smoke artifacts as applicable.
- Latest completed decision: H101 rejected before production because exact
  write-through state makes both EBR variants larger than the FF reference.
  H100 was rejected because the
  explicit four-bit source maps identically to Yosys's optimized eight-entry
  array. H096
  remains the accepted generic RTL/proof commit `a647185`; consuming the
  launch worklist removes 31 global LUT4s, one FF, and 28 deterministic floor
  cells from merged main.
- Latest rejected variants: H101's pending-trigger EBR is inexact without
  forwarding and locally worse with it. H100's unreachable music release bits are already
  removed by Yosys. H099's exact filter-publication ownership change
  is globally worse despite its 17-LUT4 isolated saving. H098's exact multiplier iteration token is globally
  worse despite its isolated four-LUT4/two-carry saving. H097's exact `ML_STOP` provenance reuse is globally
  worse despite its isolated three-LUT4/one-FF saving. H094's packed transition inequality is globally
  worse despite its isolated one-LUT4 saving. H093's grouped DQ table is locally
  worse. H092's result-flop merge is globally worse despite
  its isolated one-LUT4/one-FF saving. H091's remaining-ticks compression changes
  post-wrap completion. H090's shared step-count decode is locally worse.
  H079's exact reverb rounding is globally worse.
  H078's exact threshold fusion is locally worse.
  H074's affine slide carry is observably required.
  H073's aligned noise offset is already recovered
  by Yosys. H072's exact dampen post-shift correction is
  globally worse despite its carry win. H071's exact blend post-shift correction is
  globally worse despite its isolated win. H070's exact divider iteration token is globally
  worse despite its isolated win. H068's exact pre-terminal DQ result retention
  regresses deterministic floor and placement despite its isolated LUT win.
  H067's exact tilt-quotient prefix factorization is
  already recovered by Yosys. H066's exact reciprocal-index tail sentinel is
  globally worse and misses fast timing. H065's exact sample-register width contraction is
  globally worse despite its isolated four-FF saving. H064's exact selected noise-draw XOR sharing is
  globally much worse despite its isolated win. H063's exact old-arm sign lifetime retirement is
  globally much worse despite its isolated one-FF saving. H062's exact old-noise flag reconstruction is
  globally much worse despite its isolated win. H061's exact fade-state compression fails its
  isolated LUT/floor gate. H060's exact triangle `/4` payload reconstruction
  regresses every whole-PSG area metric except FF count. H059's exact organ quotient reconstruction
  regresses every whole-PSG physical area gate. H058's exact replay-flop retirement fails every
  physical area gate and does not route. H055's two signed-noise-rounding forms
  fail the complete physical gate. H054's centered triangle fold is locally worse.
  H053's fold-state publication token is globally
  worse. H052's selector-state final token is locally worse.
  H050's upload-page Boolean outputs are globally
  worse despite a zero-carry isolated form. H049's Boolean square/pulse thresholds worsen the
  global LUT/floor/placement trade. H048's two-axis selector adds 16 isolated LUT4s.
  H046's global decode/fanout remap overwhelms its
  three-LUT4 isolated win. H045's source-closed trit identity produces no
  isolated physical saving. H043's named active/advance predicates are already
  recovered by Yosys. H042's exact four-input truth table becomes
  globally worse despite its one-LUT4 isolated win. H041's shared exact prefix trades four isolated
  carries for two LUT4s, but becomes globally worse in LUT4s and placement.
  H040's explicit conditional complement becomes
  globally worse despite its isolated win. H038's residue correction costs 28 LUT4s locally.
  H037's conditional dead bit is already removed by Yosys. H036 loses its local register saving to global D-input/fanout
  remapping. H035 is mapping-identical because Yosys already
  shares the nested suffix logic. H034's exact prefix regresses every global
  area metric. H033's exact paired CPU activity bit maps identically to the current
  dynamic audible-slot lookup. H032's isolated record-base
  sharing saves one LUT4 and seven carries, but adds 32 LUT4s and 32 placed LCs.
  H029's large isolated LUT saving becomes a slight LUT/placement regression
  in the whole PSG. H028's local carry saving disappears in the full
  selector context. H026's first carry form misses only `a=255,b=0`;
  its repaired zero-bound form is exact but globally worse as above. H025's
  shared fade sum is mapping-identical. H024 proves both clamp-to-32 bounds are exact prefix
  intervals, but the whole-PSG map regresses as above. H021 proves the 32-arm filter decode is wrapped
  base-3, but the existing table maps to 23 LUT4/no carries versus 28 LUT4/70
  carries for direct arithmetic and 26 LUT4/11 carries for staged thresholds.
  H020 proves the audio-RAM busy export is contained
  inside `prun` and locally saves one LUT4, but whole-PSG mapping adds three
  LUT4s/three carries and seed-1 placement adds one LC. H019 proves whole-walk state-memory ownership is
  behaviorally exact and both forms reduce the isolated mux/store cone, but
  whole-PSG mapping adds 48 LUT4s/seven carries for the complete bundle and 22
  LUT4s/six carries for the retained-enable-OR form. H018's exact 25-bit
  half-sum trades one local carry for one LUT, but whole-PSG mapping adds 31
  LUT4s, nine carries, and 38 LCs.
  H017's full context sharing maps locally much
  smaller but globally adds 16 LUT4s and 36 placed LCs; scale-only sharing
  still adds 11 LUT4s and 22 placed LCs. Both save six mapped carries. H016 proves a nine-bit restoring subtract is exact
  and locally trades one carry for one LUT, but whole-PSG mapping adds 60
  LUT4s, eight carries, and 67 placed LCs. H015 proves the final detune subtract qualifier is
  algebraically redundant, but both registered cones map identically at 188
  LUT4s, 73 carries, and 14 flops. H014 proves all detune corrections fit eight bits,
  but the complete registered detune cone maps identically at 189 LUT4s, 73
  carries, and 14 flops: Yosys already removes the unreachable ninth bit.
  H013 proves the internal multiplier recurrence fits 29 bits, but both the
  two-service and target-only forms add 24 LUT4s/three carries and 26 placed
  LCs while removing two flops. H012 proves the true-
  busy OR is invariant-redundant and locally saves one LUT4, but whole-PSG
  mapping adds 48 LUT4s/five carries and seed-1 placement regresses by 50 LCs.
  H011 proves the reflected ramp is a bitwise complement, but both spellings
  map identically in the registered-use cone. H010's phase-qualified pending
  bit is exact and saves four LUT4s/one flop in the isolated timing cone, but
  whole-PSG mapping adds 29 LUT4s/five carries and seed-1 placement regresses
  by 36 LCs. H009's shift token failed similarly; H005's `< 3` suffix remains
  rejected on fast-clock timing; H004, H006, and H008 remain rejected as
  indexed below.
- Current post-integration accepted seed-1 result: H096 commit `a647185` atop
  merged main `a84dbff`: 6,364 LUT4s, 1,321 carries, 1,459 flops, 509
  unpackable flops, 14 EBRs, 6,873-cell floor, and 7,095/7,680 LCs at
  151.17/33.09 MHz. Versus merged main it deterministically removes 31 LUT4s,
  one FF, and 28 floor cells; the 25-LC route reduction is below placement
  sensitivity and is not independently overclaimed. Two forced builds
  reproduced JSON SHA-256 `da8f01f6...` and ASC SHA-256 `519dabc7...`
  bit-for-bit. The numerically smaller direct H095 point predates the required
  main/R.84/diagnostic-ARAM composition and is not the current integration base.
  The older H051 source lineage remains at
  6,506 LUT4s / 1,421 carries / 1,476 flops / floor 7,028 / 7,247 LCs.
- Last updated: 2026-08-03.

## Main Integration I001

- **ID:** I001.
- **Hypothesis:** accepted direct H095 `3d7a2e2`, the final accepted R.84
  proof foundation `7cc639a`, and the durable generic ledger `bca1454` can
  be composed on main `86d4fab` without losing either the direct RTL savings
  or the R.84 address/control/live-value guarantees.
- **Scope:** a dedicated integration branch only. Preserve every accepted
  direct generic RTL change, merge the committed R.84 proof/controller state,
  regenerate all source-derived C2-C-C and later proof artifacts against the
  composed RTL, then run the complete algebraic, structural, cadence, render,
  recovery, click, Celeste, forced HX8K, strict OpenSpec and scope battery.
  The dirty main worktree, Tang/image paths and unrelated user changes remain
  untouched until a verified fast-forward is possible.
- **Baseline:** direct H095 maps 6,342 LUT4s, 1,321 carries, 1,459 flops,
  504 unpackable flops, 14 EBRs, floor 6,846 and 7,066 seed-1 LCs at
  133.69/32.79 MHz. R.84 head is proof-only and makes no composed area claim.
- **Change:** merge R.84 `7cc639a` into direct H095 `3d7a2e2`, retain every
  committed source change, and repair only the four source-derived integration
  bindings: the retired H075 walk leaves in `psg_budget_tb`, H051's reachable
  DQ recurrence in `psg_dqsvc_tb`, the H075/noise-clamp source spellings in
  `psg_exec_model.py`, and this ledger row.
- **Result:** two independent model generations and two independent composed
  traces are byte-identical.  Binding audits pass 152,893 structural rows;
  value audits pass 385,792 rows / 192,896 pairs and 43,459 service
  transactions.  Full forms, full/PREVIEW and executor lints, Python compile,
  strict OpenSpec, `make test-psg`, 59/59 frozen renders, ordinary and
  multipumped `/4`--`/6` cadence, `make test-clocks`, all eight PREVIEW checks,
  synthetic/Celeste recovery, exact zero-click hardware/PREVIEW SFX-10
  renders, and the five-frame Celeste smoke pass.  Two forced HX8K builds are
  byte-identical at JSON SHA-256 `4e0d5930d1dde2ecea8d72167ff94329093879d86758ec72041ac871201bf921`
  and ASC SHA-256 `5c51c6684f861ff7481012dd921259220b367cd00f3e20f3fce81704cdb9ea19`:
  6,386 LUT4s, 1,325 carries, 1,459 flops, 504 unpackable flops, 14 EBRs,
  6,890-cell deterministic floor and 7,116 seed-1 routed LCs at 143.64 MHz
  fast / 30.95 MHz PSG.  Relative to direct H095, the required R.84 runtime
  substrate costs 44 LUT4s, four carries, 44 floor cells and 50 routed LCs;
  no area reduction is claimed for the composition itself.  Accepted model
  parent `0db0484` is also merged and rebound to I001: independent upgraded
  source certificates are byte-identical at `bcadbae4...`, all other model and
  event artifacts remain byte-identical, both binding/value audits pass, and
  the default model, complete forms, Python and strict OpenSpec gates pass.
- **Decision:** accepted.  This is the verified H095 + R.84 integration point;
  it was safely fast-forwarded through the later main landing at `a84dbff`,
  which unblocked the now-accepted H096 generic continuation. R.84 B2 remains
  companion-owned.
- **Repeat only if:** retry a rejected merge resolution only after identifying
  a concrete changed source/proof contract or an independently accepted newer
  direct/R.84 checkpoint.

## Next Experiment Gate

- Next experiment: H102 on accepted H096 `a647185`, only after a fresh source
  and DNR audit. It must not repeat H096's launch-worklist/pacing-state family,
  H097's `ML_STOP` provenance/lifetime-alias family,
  H098's fast multiplier iteration-token family,
  H099's filter-tuple ownership/publication-source family,
  H100's foreground/music release-state partition family,
  H101's pending-trigger row/length memory family,
  H095's now-composed foreground trigger-length
  prefix family, H094's now-closed packed transition-inequality
  family, H093's DQ coefficient-decoder spelling family, H092's EA2/EA4 result-
  flop lifetime family, H091's pattern-counter compression, H090's multiplier
  step-count family, or H089's state-selected pitch-add/clamp family. It must remain
  outside the closed affine-slide-carry,
  tilt-affine-reassociation, tilt-index-adder-sharing,
  aligned-noise-offset,
  dampen-rounding, blend-rounding,
  DQ-result-publication,
  quotient-prefix,
  tail-sentinel,
  sample-register-width,
  noise-draw, old-arm-sign, old-noise-flag, fade-state,
  triangle-payload,
  organ quotient-byte, and organ-high-
  predicate, organ-fold,
  signed-noise-rounding, centered-triangle-fold, noise-clamp, kick-comparator, detune-
  service-count, upload-page-transform, square/pulse-threshold, selector-
  factor, normalized-effect-class, waveform-output-shift, tilt-control-
  predicate, trit-max, counter-
  terminal, fold-final-selector, fold-publish-state, EA5-predicate, small-comparison, fade-prefix, organ-fold, aligned-
  record-base, boosted-gain, conditional-width, tilt-register, suffix-sharing,
  prefix-clamp, readback-bit, address-base, comparator-sharing, reciprocal-
  half-sum, gain-context, state-replay, divider, detune, delayed-tick,
  multiplier, soft-add-threshold, reverb-rounding, and R.84
  families.
- Required verification for any accepted hypothesis: focused algebraic or exhaustive
  proof, waveform/form tests, full structural PSG, 59-render exact regression,
  mapped resources, seed-1 placed LCs, both routed clocks, strict OpenSpec
  validation, and `git diff --check`.
- Blocked repeat families: R.40--R.42 lifetime aliases; R.44 pending-trigger
  EBR migration; R.63/R.64 multiplier
  adder sharing; R.67 parallel reciprocal port; R.68/R.69 partial schedule
  encodings; R.76--R.78 detune-result lifetimes; R.79 held CDC payload;
  R.80 reciprocal coefficient factoring; R.82 detune recomputation; R.83
  register-fed waveform services; all R.84 executor/controller work.

## Recent Hypothesis Index

| ID | Decision | Resume effect |
| -- | -- | -- |
| H001 | accepted | Keep the exact narrow tilted-saw ceiling form; treat the mapped carry reduction as the durable physical result. |
| H002 | accepted | Keep the four-interval Boolean decode for `ceil(3*r/128)`; the deterministic result is 18 fewer LUT4s. |
| H003 | accepted | Keep the exact high-bit prefix test; the deterministic result is 19 fewer LUT4s and two fewer carries. |
| H004 | rejected | Do not narrow the square/pulse threshold comparator: Yosys already removes the aligned low bits. |
| H005 | accepted | Keep the five-bit page subtract and explicit upload-page decode; the durable result is nine fewer carries with no placed regression. |
| H006 | rejected | Keep the existing multiplier step-count ternary: it already maps to one LUT, while direct result-bit logic needs two. |
| H007 | accepted | Keep the CLK_HZ-derived signed width; it deterministically removes 46 LUT4s, 13 carries, and two flops. |
| H008 | rejected | Keep the two direct counter equalities: Yosys already shares their common high-nibble decode. |
| H009 | rejected | Keep the countdown form: the exact shift token is smaller alone but adds 36 LUT4s, five carries, and 36 placed LCs in the full PSG. |
| H010 | rejected | Keep the countdown form: the exact pending bit saves one local flop but adds 29 LUT4s, five carries, and 36 placed LCs in the full PSG. |
| H011 | rejected | Keep the subtract spelling: Yosys already maps `16'hffff - wx` exactly as `~wx`, with identical registered-use resources. |
| H012 | rejected | Keep the defensive true-busy OR: removing it is exact in-contract and locally smaller but adds 48 LUT4s, five carries, and 50 placed LCs globally. |
| H013 | rejected | Keep the 34-bit internal service form: the proved 29-bit recurrence removes two flops but adds 24 LUT4s, three carries, and 26 placed LCs. |
| H014 | rejected | Keep the nine-bit source contract: all values fit eight bits, but Yosys already prunes the unreachable position and both forms map identically. |
| H015 | rejected | Keep the explicit subtract qualifier: the unconditional form is exact but maps identically in the registered full-detune cone. |
| H016 | rejected | Keep the ten-bit restoring subtract: the nine-bit form is exact and locally -1 carry/+1 LUT, but globally adds 60 LUT4s, eight carries, and 67 LCs. |
| H017 | rejected | Keep separate new/old gain cones: full and scale-only sharing save carries locally/globally but both add LUT4s and placed LCs in the whole PSG. |
| H018 | rejected | Keep the 26-bit add-then-shift: the exact 25-bit half-sum saves one carry locally but globally adds 31 LUT4s, nine carries, and 38 LCs. |
| H019 | rejected | Keep per-operation state-memory selects: both whole-walk owner forms are exact and locally smaller, but globally add LUT4s/carries; the retained-OR form also fails to route promptly. |
| H020 | rejected | Keep the redundant audio-RAM busy export: removing it saves one local LUT4 but adds three LUT4s/three carries globally and one placed LC. |
| H021 | rejected | Keep the 32-arm filter table: its wrapped base-3 identity is exact, but ABC maps the table smaller than direct or staged arithmetic. |
| H022 | accepted | Keep the eight-bit live pitch sums and exact sign/high-bit saturation decode; they trade 17 LUT4s for 14 carries and one non-robust placed LC without changing behavior. |
| H023 | accepted | Keep the exact shared slide-octave prefix predicates; they remove ten LUT4s, six carries, and 24 non-robust placed LCs. |
| H024 | rejected | Keep the nested row-bound clamps: exact prefixes save carries but add 32 LUT4s and 19 placed LCs globally. |
| H025 | rejected | Keep the repeated fade expressions: formal equivalence passes, but Yosys already maps them identically to one explicit sum. |
| H026 | rejected | Keep the relational rollover predicate: the exact carry form saves 14 carries but adds 31 LUT4s and 14 placed LCs globally. |
| H027 | accepted | Keep the exact shared-helper noise clamp prefixes; they remove 69 carries and 61 seed-1 LCs for 21 LUT4s. |
| H028 | rejected | Keep the relational arpeggio-speed test: the exact prefix loses its carry saving globally and adds LUT4s/LCs. |
| H029 | rejected | Keep the current kick inequality: the exact affine margin saves carries but adds LUT4s and placed LCs globally. |
| H030 | accepted | Keep the exact foreground trigger-length prefix; it removes four LUT4s and two carries without a placement regression. |
| H031 | accepted | Keep the time-shared sequencer comparator; it removes one LUT4 and seven carries without a placement regression. |
| H032 | rejected | Keep the two precomputed record bases: selecting the record number first is locally smaller but globally adds 32 LUT4s and 32 LCs. |
| H033 | rejected | Keep the dynamic audible-slot readback: the exact paired activity bit maps identically in the complete registered consumer. |
| H034 | rejected | Keep the relational pattern-row saturation: the exact prefix removes two carries locally but adds 15 LUT4s, four carries, and 20 LCs globally. |
| H035 | rejected | Keep the independent suffix expressions: explicit nesting is exact but maps identically in the complete registered consumer. |
| H036 | rejected | Keep the parallel tilt quotient registers: preselection saves ten flops locally but adds 54 LUT4s/seven flops globally and does not route promptly. |
| H037 | rejected | Keep the ten-bit `/7` source width: the dead live-mode bit is already pruned and both registered consumers map identically. |
| H038 | rejected | Keep the two-stage boosted gain: the exact affine/residue form adds 28 LUT4s with carries/flops unchanged. |
| H039 | accepted | Keep the aligned 11-bit `rec_base()` transform; it removes five LUT4s for one added carry and no placement regression. |
| H040 | rejected | Keep the truncated organ-ramp negation: the exact explicit fold is locally smaller but globally adds LUT4s, carries, and LCs. |
| H041 | rejected | Keep the relational fade-length tests: the shared exact prefix saves carries but adds 11 LUT4s and nine placed LCs globally. |
| H042 | rejected | Keep the gated two-bit relation: its exact Boolean truth table is locally smaller but adds LUT4s, carries, and LCs globally. |
| H043 | rejected | Keep the direct EA5 comparisons: the named exact predicates map identically in the complete registered consumer. |
| H044 | accepted | Keep the proved terminal high-bit predicate; it removes nine LUT4s deterministically with no placement regression. |
| H045 | rejected | Keep the relational filter maxima: the exact trit form maps identically in the registered consumer. |
| H046 | rejected | Keep the raw publication decodes: normalized `e_fx` reuse saves three LUT4s alone but adds 27 LUT4s and 28 routed LCs globally. |
| H047 | accepted | Keep the selected final waveform shift; it removes 28 LUT4s, 33 carries, 27 floor cells, and 29 seed-1 routed LCs. |
| H048 | rejected | Keep the direct priority selector: factoring its two axes adds 16 LUT4s in the registered cone. |
| H049 | rejected | Keep the relational square/pulse thresholds: exact Boolean prefixes add LUT4s and placed LCs globally. |
| H050 | rejected | Keep the five-bit subtract: both exact Boolean transforms regress global LUT/floor/placement. |
| H051 | accepted | Keep the five-state XOR/shift detune-service count; it removes five mapped carries for three LUT4s and no seed-1 placement regression. |
| H052 | rejected | Keep the separate final-fold flag: selector state five adds three isolated LUT4s and maps the same total flops. |
| H053 | rejected | Keep the publication flop: state ten removes one FF but adds 22 global LUT4s and 19 floor/routed cells. |
| H054 | rejected | Keep the current complement/subtract/bias triangle fold: the exact centered-phase identity saves one isolated carry but adds eleven LUT4s. |
| H055 | rejected | Keep the shared positive/negative noise limbs: duplicated unified rounding doubles isolated carries, while the shared complement form does not complete seed-1 routing. |
| H056 | accepted | Keep `z_lin_r[15] ^ z_lin_r[14]` as the exact organ high-phase predicate; it retires one FF and one deterministic floor cell with no placement regression. |
| H057 | accepted | Keep exact reconstruction of `tilt_hi_r` from the same-edge registered controls; it removes 23 LUT4s, one FF, and 19 floor cells globally. |
| H058 | rejected | Keep the explicit state-RAM replay contract: its freeze is covered by `prun | fold_busy`, but removing one FF adds 24 LUT4s, five carries, 21 floor cells, and 31 placed LCs and does not route. |
| H059 | rejected | Keep the explicit registered organ quotient byte: exact full and partial reconstruction from `z_lin_r` retire flops locally but regress whole-PSG LUT4s, carries, floor, and placement; the partial form also fails to route. |
| H060 | rejected | Keep the explicit registered alternate-triangle `/4` payload: exact reconstruction from `z_lin_r` removes 16 mapped FF but adds 54 LUT4s, one carry, 50 floor cells, and 53 routed LCs globally. |
| H061 | rejected | Keep the explicit 16-bit fade accumulator: exact high-byte reconstruction removes eight FF but adds eight isolated LUT4s and six floor cells. |
| H062 | rejected | Keep the explicit old-noise activity flag: exact same-edge tuple reconstruction is locally -2 LUT4/-1 FF/-2 floor, but globally adds 55 LUT4s, 53 floor cells, and 57 routed LCs. |
| H063 | rejected | Keep the W15 old-arm sign snapshot: the source sign is invariant through W51 and direct use removes one FF locally, but globally adds 64 LUT4s, four carries, 62 floor cells, and 69 routed LCs. |
| H064 | rejected | Keep the parallel live/old noise-draw transforms: selecting LFSR bits before one exact shared XOR chain saves two isolated LUT4s, but globally adds 55 LUT4s, four carries, 54 floor cells, and 63 routed LCs. |
| H065 | rejected | Keep the signed 18-bit sample registers: every value fits signed 16 bits and contraction removes four FF/four carries, but globally adds 27 LUT4s, 27 floor cells, and 32 routed LCs. |
| H066 | rejected | Keep the explicit tilt-tail pipeline flag: reserved-index encoding is exact and removes one FF, but adds 42 LUT4s, four carries, 40 floor cells, 47 routed LCs, and misses fast timing. |
| H067 | rejected | Keep the explicit quotient slices: sharing their four-bit source prefix with `t_pre_r` is exact, but both complete isolated consumers map identically at 19 LUT4s and 29 FF. |
| H068 | rejected | Keep the committed DQ terminal result: retaining the pre-terminal recurrence saves six isolated LUT4s but adds one global carry, twelve unpackable flops, three floor cells, and six routed LCs. |
| H069 | accepted | Keep the exact post-shift negative-remainder correction in shared `tzs`; it removes ten global LUT4s, 33 carries, and nine floor cells without a seed-1 placement regression. |
| H070 | rejected | Keep the binary divider countdown: a 24-state LFSR saves one isolated LUT4/three carries but adds 23 global LUT4s/floor cells and 17 routed LCs. |
| H071 | rejected | Keep the pre-shift blend bias: post-shift correction saves eight isolated LUT4s/six carries but both whole-PSG spellings regress LUT4s and floor cells. |
| H072 | rejected | Keep the pre-shift dampen bias: selected post-shift correction removes carries but adds 26 global LUT4s and 24 floor cells. |
| H073 | rejected | Keep the source expression `8*dp + 1120`: the exact aligned 14-bit sum maps identically in the complete registered consumer. |
| H074 | rejected | Keep the full first affine-slide accumulation: its low-12 carry changes a reachable published increment at pitch 2/fraction 9,668. |
| H075 | accepted | Keep the exact operand-XOR and sign carry-in form; it removes 23 global LUT4s, eight carries, two unpackable flops, and 25 floor cells. |
| H076 | rejected | Keep the accepted `3*x`-then-subtract form: reassociation is locally -12 LUT4/-1 carry but globally +5 LUT4/+1 unpackable/+6 floor. |
| H077 | rejected | Keep the two source index expressions: the shared-adder form is exact but maps identically in the complete registered tilt consumer. |
| H078 | rejected | Keep the serial positive/negative soft-add probes: sign-selected fusion is exact in the legal fold domain but adds six isolated LUT4s. |
| H079 | rejected | Keep pre-shift bias in the two reverb combs: post-shift correction saves two isolated carries but adds 32 global LUT4/floor cells. |
| H080 | accepted | One sign-selected fractional-sample update adder removes 24 global LUT4s, 23 carries, and 24 deterministic floor cells. |
| H081 | rejected | Keep the two slide adders: exact scheduled sharing removes 25 carries but adds 20 isolated LUT4/floor cells. |
| H082 | rejected | Keep the dedicated slide-intermediate register: storage reuse removes 18 FF but adds 28 global LUT4s and ten floor cells. |
| H083 | rejected | Keep the nested live-gain sums: exact fusion removes three carries but adds 21 isolated LUT4/floor cells. |
| H084 | rejected | Keep binary `scnt`: exact three-token LFSR encoding removes six carries but adds 26 LUT4s and 32 floor cells globally. |
| H085 | rejected | Keep numerator bias: both exact output-correction placements regress complete isolated divider/caller floor. |
| H086 | rejected | Keep the two EA5 row incrementers: exact selected sharing removes seven global carries but adds seven LUT4s and eight floor cells. |
| H087 | rejected | Keep the signed vibrato case and absolute value: direct sign/magnitude bits add one isolated LUT4. |
| H088 | rejected | Keep dedicated tick/pre-tick flops: deriving both from registered state removes two FF but adds three LUT4s and two isolated floor cells. |
| H089 | accepted | Keep one state-selected current/arpeggiated pitch add-and-clamp cone; it removes 63 global LUT4s, 15 carries, and 60 deterministic floor cells. |
| H090 | rejected | Keep the two multiplier count decodes: deriving `seq_pad` from radix-2 `req_steps` is exact but adds one isolated LUT4. |
| H091 | rejected | Keep elapsed and target pattern counters: one saturated remaining counter completes early after a reachable pending-trigger wrap. |
| H092 | rejected | Keep the two comparator-result flops: one shared flop saves one LUT4/one FF alone but adds 20 global LUT4/floor cells and three carries. |
| H093 | rejected | Keep the nested DQ coefficient decoder: the exact grouped truth table adds three LUT4s in the complete registered service cone. |
| H094 | rejected | Keep separate transition inequalities: one packed comparison saves one isolated LUT4 but adds three global LUT4/floor cells. |
| H095 | accepted | Keep the exact foreground trigger-length overflow prefix on the direct lineage; it removes four global LUT4s, three carries, and four floor cells. |
| H096 | accepted | Consume the launched-channel worklist after selecting the pacing owner; this removes 31 LUT4s, one FF, and 28 deterministic floor cells on merged main. |
| H097 | rejected | Keep the dedicated `ml_cpu` provenance bit: `walk_tick` is equivalent and saves three LUT4s/one FF alone, but adds 18 LUT4s, four carries, 17 floor cells, and 20 routed LCs globally. |
| H098 | rejected | Keep the binary multiplier countdown: an exact LFSR token saves four LUT4s/two carries alone, but adds 20 LUT4s, 19 floor cells, and 16 routed LCs globally. |
| H099 | rejected | Keep the explicit filter base-copy writes: publication ownership saves 17 LUT4s alone, but both whole-PSG variants regress deterministic floor and placement. |
| H100 | rejected | Keep the eight-entry source array: music release bits are invariant zero, but Yosys already prunes them and the explicit four-entry form maps identically at 17 LUT4s/four FF. |
| H101 | rejected | Keep pending trigger row/length in FFs: a plain EBR is one cycle stale after a CPU write, while exact one-/two-EBR forwarding forms raise the isolated floor from 97 to 107/104 cells. |

## Hypothesis H001

- **ID:** H001.
- **Hypothesis:** spelling the two tilted-saw ceiling operations as a narrow
  quotient plus a non-zero-remainder increment will preserve every value,
  simplify the source contract, and may map smaller than a wide constant add
  followed by truncation.
- **Scope:** `rtl/psg_wave.sv`, an exhaustive proof command, waveform/form
  tests, full PSG fidelity gates, canonical standalone synthesis, and this
  ledger. No schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** `PATH=/opt/homebrew/bin:$PATH make synth-psg` at `86d4fab`,
  fingerprint `92fc17f7dbd2`: 6,598 LUT4s, 1,597 carries, 1,478 flops, 14
  EBRs; seed-1 7,504 LCs; 145.99 MHz fast and 30.21 MHz PSG.
- **Change:** replace each wide add-then-shift ceiling expression with its
  explicit quotient plus one-bit non-zero-remainder increment.
- **Result:** exhaustive comparison of all 65,536 ramp values passed for both
  `/1024` and `/2048`; `tools/psg_hw_forms.py`, `make test-psg`, the 59-render
  18.75-MHz exact bytecheck, full/PREVIEW lint, `/4`, `/5`, `/6` budget tests,
  and `make test-clocks` all passed. P.1 Celeste preview checks at 1,275 and
  159 clocks/sample passed combined and masks 1/2/4 at 100%; P.2 synthetic
  and frozen-Celeste recovery passed. Exact hardware/PREVIEW SFX-10 renders
  were active and `click-v1` found zero clicks. A five-frame Celeste smoke had
  2,179/3,668 off-centre samples, range -22,013..9,151, and 1,068 distinct
  levels. Strict OpenSpec validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed 6,598 LUT4 / 1,597
  carry / 1,478 FF / 14 EBR / 7,504 placed LCs to 6,602 LUT4 / 1,577 carry /
  1,478 FF / 14 EBR / 7,495 placed LCs. Routed clocks changed from 145.99 and
  30.21 MHz to 150.53 and 30.71 MHz. The 20-carry reduction is deterministic;
  the nine-LC improvement is below placement sensitivity and is not overclaimed.
- **Decision:** accepted. It simplifies the arithmetic contract, improves a
  deterministic mapped resource, does not regress placed LCs, preserves all
  fidelity gates, and retains 14 EBRs.
- **Repeat only if:** a rejected spelling may be retried only after the
  waveform pipeline boundary, mapper arithmetic inference, or rounding
  representation changes materially.

## Hypothesis H002

- **ID:** H002.
- **Hypothesis:** the phaser detune remainder is only seven bits, so
  `ceil(3*r/128)` has four exact intervals: zero at `r=0`, one on 1--42, two
  on 43--85, and three on 86--127. Directly decoding those thresholds should
  remove the current `3*r` and round-up adders while making the bounded
  arithmetic contract explicit.
- **Scope:** `rtl/psg_wave.sv`, the `dq` proof in `tools/psg_hw_forms.py`,
  focused forms tests, complete H001 fidelity/physical gates, and this ledger.
  No schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H001 commit `609f035`: 6,602 LUT4s, 1,577 carries,
  1,478 flops, 14 EBRs; seed-1 7,495 LCs; 150.53 MHz fast and 30.71 MHz PSG.
  Isolated `synth_ice40` reconnaissance maps the current remainder expression
  to 13 LUT4s / 7 carries and a direct Boolean threshold form to 7 LUT4s /
  zero carries; whole-PSG mapping remains authoritative.
- **Change:** remove the nine-bit `3*r` and round-up adders. Decode the lower-
  six-bit thresholds 43 and 22 as Boolean trees and drive the two-bit result
  directly; add the exact remainder and full-`dp13` proofs to `sec_dq()`.
- **Result:** the complete `tools/psg_hw_forms.py` passes, including all 128
  remainders and all 8,192 `dp13` values. Full/PREVIEW lint, `make test-psg`
  (93 analysis tests, every structural test, 524/850 sample clocks,
  4,008/5,103 tick clocks, zero late flips), 59/59 exact renders, and `/4`,
  `/5`, `/6` budget regressions passed. The budget runs retained 524 sample
  clocks and tick results 5,709/7,654, 4,689/6,123, and 4,008/5,103 with zero
  lost writes, overruns, or late flips. `make test-clocks` passed. All eight
  P.1 Celeste preview checks at 1,275 and 159 clocks/sample passed at 95%
  agreement for combined and masks 1/2/4; both P.2 recovery probes passed.
  Exact hardware/PREVIEW SFX-10 renders were active and `click-v1` found zero
  clicks. The five-frame Celeste smoke again had 2,179/3,668 off-centre
  samples, range -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec
  validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed 6,602 LUT4 / 1,577
  carry / 1,478 FF / 14 EBR / 7,495 placed LCs to 6,584 LUT4 / 1,577 carry /
  1,478 FF / 14 EBR / 7,478 placed LCs. Routed clocks changed from 150.53 and
  30.71 MHz to 138.48 and 29.89 MHz; both remain above their 112.50 and
  18.75-MHz constraints. The 18-LUT4 reduction is deterministic; the 17-LC
  improvement is below placement sensitivity and is not overclaimed.
- **Decision:** accepted. It exposes the exact four-interval contract, removes
  both remainder adders, improves a deterministic mapped resource, does not
  regress placed LCs, preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** a rejected direct threshold decode may be retried only
  after the detune coefficient, remainder width, or mapper Boolean lowering
  changes materially.

## Hypothesis H003

- **ID:** H003.
- **Hypothesis:** the tilted-saw tail thresholds are exactly `0xE000` and
  `0xF000`; testing their one-prefix bits as `&wx[15:13] && (!tilt_hi ||
  wx[12])` is exact, simpler than two 16-bit comparisons, and should prevent
  the iCE40 mapper from retaining comparator carry cells.
- **Scope:** `rtl/psg_wave.sv`, an exhaustive prefix proof in
  `tools/psg_hw_forms.py`, focused forms tests, complete H002 fidelity/physical
  gates, and this ledger. No schedule, state, interface, EBR, R.84, or
  tolerance change.
- **Baseline:** accepted H002 commit `73921a5`: 6,584 LUT4s, 1,577 carries,
  1,478 flops, 14 EBRs; seed-1 7,478 LCs; 138.48 MHz fast and 29.89 MHz PSG.
  Isolated `synth_ice40` reconnaissance maps the current comparison to one
  LUT4 / two carries and the prefix form to two LUT4s / zero carries; whole-
  PSG mapping remains authoritative.
- **Change:** replace the two 16-bit comparisons with one three-bit prefix AND
  and the single distinguishing bit; add an exhaustive proof for both
  thresholds to the permanent hardware-forms gate.
- **Result:** the complete `tools/psg_hw_forms.py` passes, including all
  131,072 threshold/mode combinations. Full/PREVIEW lint, `make test-psg`
  (93 analysis tests, every structural test, 524/850 sample clocks,
  4,008/5,103 tick clocks, zero late flips), and the 59/59 exact render
  regression passed. The `/4`, `/5`, and `/6` budget runs retained 524 sample
  clocks and tick results 5,709/7,654, 4,689/6,123, and 4,008/5,103 with zero
  lost writes, overruns, or late flips. `make test-clocks` passed. All eight
  P.1 Celeste preview checks at 1,275 and 159 clocks/sample passed at 95%
  agreement for combined and masks 1/2/4; both P.2 recovery probes passed.
  Exact hardware/PREVIEW SFX-10 renders were active and `click-v1` found zero
  clicks. The five-frame Celeste smoke again had 2,179/3,668 off-centre
  samples, range -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec
  validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed 6,584 LUT4 / 1,577
  carry / 1,478 FF / 14 EBR / 7,478 placed LCs to 6,565 LUT4 / 1,575 carry /
  1,478 FF / 14 EBR / 7,453 placed LCs. Routed clocks changed from 138.48 and
  29.89 MHz to 131.72 and 30.51 MHz; both remain above their 112.50 and
  18.75-MHz constraints. The 19-LUT4 and two-carry reductions are
  deterministic; the 25-LC improvement is below placement sensitivity and is
  not overclaimed.
- **Decision:** accepted. It exposes the aligned-prefix contract, removes the
  wide comparisons, improves two deterministic mapped resources, does not
  regress placed LCs, preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** a rejected prefix form may be retried only after the
  tail thresholds, phase width, or mapper comparison lowering changes.

## Hypothesis H004

- **ID:** H004.
- **Hypothesis:** all four square/pulse thresholds are aligned to 2^11, so
  comparing `wx[15:11]` against 16, 19, 22, or 25 may remove eleven comparator
  bits while keeping the threshold contract more explicit.
- **Scope:** exhaustive scratch proof and isolated `synth_ice40` comparison of
  the current and narrowed forms. Production RTL and fidelity gates are
  conditional on a deterministic isolated mapped reduction.
- **Baseline:** accepted H003 commit `68f9a35`; isolated current square/pulse
  selection maps to seven LUT4s and five carries.
- **Change:** scratch-only five-bit threshold and phase-high-word comparison;
  no production file changed.
- **Result:** all 1,048,576 waveform-selector, alternate-mode, and 16-bit phase
  combinations matched exactly. Isolated `synth_ice40` still mapped seven
  LUT4s and five carries: Yosys already proves the eleven aligned low bits
  irrelevant through the current 16-bit spelling.
- **Decision:** rejected before production RTL. The candidate changes source
  without changing the deterministic mapped netlist.
- **Repeat only if:** the thresholds lose their 2^11 alignment, comparator
  lowering changes, or a surrounding consumer prevents the current low-bit
  pruning.

## Hypothesis H005

- **ID:** H005.
- **Hypothesis:** the audio upload base `$3100` is byte-aligned, so its RAM
  address is exactly `{wraddr[12:8] - 17, wraddr[7:0]}`. The valid
  `$3100..$42ff` window is exactly pages `3:1..f` or `4:0..2`; spelling those
  two page prefixes directly should remove the current wide subtract/compare
  while making the port's address contract explicit.
- **Scope:** `rtl/psg_aram.sv`, an exhaustive all-65,536-address proof,
  isolated and whole-PSG iCE40 mapping, the complete H003 acceptance battery
  if the mapped result improves, and this ledger. No sequencer, walker,
  schedule, interface, EBR, R.84, or tolerance change.
- **Baseline:** production RTL remains accepted H003 commit `68f9a35` (plus
  docs-only H004 commit `d1373e8`): 6,565 LUT4s, 1,575 carries, 1,478 flops,
  14 EBRs; seed-1 7,453 LCs; 131.72 MHz fast and 30.51 MHz PSG.
- **Change:** replace the 16-bit base subtraction and 4,608-byte comparison
  with a five-bit page subtraction, retain the byte offset unchanged, and
  decode valid pages as `$31..$3f` or `$40..$42`. Add this full address-space
  equivalence to the permanent hardware-forms gate.
- **Result:** `tools/psg_hw_forms.py` exhausts all 65,536 addresses, selects
  exactly 4,608, and proves every valid index. Full and PREVIEW Verilator
  lint passed. `make test-psg` passed 93 analysis tests and the complete
  structural suite at 524/850 sample clocks and 4,008/5,103 tick clocks, with
  zero late flips. The 59-case 18.75-MHz regression was byte-exact. `/4`,
  `/5`, and `/6` budget runs passed at 572/1,275 and 5,757/7,654,
  572/1,020 and 4,737/6,123, and 524/850 and 4,008/5,103 sample/tick clocks.
  `make test-clocks` passed. All eight canonical PREVIEW checks at 1,275 and
  159 clocks/sample passed at 36/38 voiced windows, rounded 95%, for masks
  7/1/2/4. Synthetic and reconstructed-Celeste recovery probes passed with
  no coalesced, delayed, or dropped samples. Exact hardware/PREVIEW SFX-10
  renders were active and `click-v1` found zero clicks. A five-frame Celeste
  smoke again had 2,179/3,668 off-centre samples, range -22,013..9,151, and
  1,068 distinct levels. Strict OpenSpec validation and `git diff --check`
  passed.
- **Rejected spelling:** writing the `$40..$42` suffix as `< 3` maps to 6,548
  LUT4s, 1,562 carries, 1,478 flops, 14 EBRs, and 7,417 placed LCs, but final
  routing reaches only 109.12 MHz on the 112.5-MHz fast clock. It is rejected
  despite its area win; evidence is `candidate-v1.{synth,pnr}.log`.
- **Physical result:** the retained `!= 3` spelling maps 6,568 LUT4s, 1,566
  carries, 1,478 flops, and 14 EBRs; seed-1 place-and-route uses 7,449 LCs and
  routes at 137.65 MHz fast / 31.16 MHz PSG. Relative to H003 this is +3
  LUT4s, -9 carries, and -4 placed LCs. The mapped carry reduction is durable;
  the placed delta remains inside sensitivity and is not overclaimed.
- **Decision:** accepted. The change makes the page-aligned port contract
  explicit, removes the wide subtract/compare, improves a deterministic mapped
  resource, does not regress placement, preserves every fidelity gate, and
  retains 14 EBRs with both routed clocks above constraint.
- **Repeat only if:** a rejected page-local decode may be retried only after
  the upload base/window, address width, or mapper constant-subtract lowering
  changes materially.

## Active DNR Index

- Selected arithmetic and service families: R.63, R.64, R.80, R.83.
- Lifetime and CDC payload families: R.40--R.42, R.76--R.79, R.82.
- Partial schedule/control encodings: R.68, R.69 and R.84 partial integration.
- Reciprocal memory topology: R.67.
- Sequencer fade-length predicate: H041.
- Triangle detune-1 residue comparison: H042.
- EA5 foreground-length predicate factoring: H043.
- Square/pulse threshold forms: H004 and H049.
- Audio-upload page transform: H050.
- State-RAM replay-flop retirement: H058.
- Organ quotient-byte reconstruction: H059.
- Alternate-triangle `/4` payload reconstruction: H060.
- Fade-progress high-byte reconstruction: H061.
- Old-noise activity-flag reconstruction: H062.
- Old-arm gain-sign snapshot retirement: H063.
- Selected live/old noise-draw XOR sharing: H064.
- Sample-register width contraction: H065.
- Reciprocal-index tilt-tail sentinel: H066.
- Tilt-quotient shared-prefix storage: H067.
- Soft-add threshold-probe fusion: H078.
- Reverb comb post-shift rounding: H079.

## Hypothesis H006

- **ID:** H006.
- **Hypothesis:** normal radix-4 multiplier counts are 4, 5, 6, 5 for modes
  0, 1, 2, 3, so spelling the result directly as
  `{1'b1, mode[1] && !mode[0], mode[0]}` should remove the duplicate mode-1
  and mode-3 comparisons in `psg_mulsvc.m_cnt` and `psg_mulmp.seq_pad`.
- **Scope:** exhaustive scratch truth-table proof and isolated registered iCE40
  synthesis. Production multiplier RTL and fidelity gates are conditional on
  an isolated deterministic mapped improvement.
- **Baseline:** accepted H005 commit `5a5a0db`. The isolated current registered
  ternary maps to one LUT4 and three flip-flops.
- **Change:** scratch-only direct count-bit expression; no production file
  changed.
- **Result:** all eight short-request/mode combinations match exactly. Isolated
  `synth_ice40` maps the direct expression to two LUT4s and three flip-flops,
  one LUT4 more than the existing ternary. Yosys already shares the equal
  mode-1 and mode-3 results through its current priority expression.
- **Decision:** rejected before production RTL. The apparent duplicate source
  comparisons are not duplicate mapped logic, and the direct bit form is
  strictly larger in the isolated authoritative metric.
- **Repeat only if:** request modes, step counts, mapper lowering, or the
  surrounding registered load contract changes materially.

## Hypothesis H007

- **ID:** H007.
- **Hypothesis:** `psg_timing.divd` always lies between
  `-(CLK_HZ-22050)` and 22,049, so `$clog2(CLK_HZ)+1` signed bits preserve the
  complete recurrence. The iCE40 target needs 26 bits at 18.75 MHz rather than
  the fixed 28, which should retire two accumulator flops and carry positions
  while making the parameter contract explicit.
- **Scope:** `rtl/psg_timing.sv`, a permanent range/recurrence proof over every
  configured PSG clock, focused timing tests, whole-PSG iCE40 mapping, the
  complete H005 acceptance battery if the mapped result improves, and this
  ledger. No sequencer, walker, waveform, interface, EBR, R.84, or tolerance
  change.
- **Baseline:** accepted H005 production commit `5a5a0db` plus docs-only H006
  `be8d984`: 6,568 LUT4s, 1,566 carries, 1,478 flops, 14 EBRs; seed-1 7,449
  LCs; 137.65 MHz fast and 31.16 MHz PSG.
- **Change:** derive the signed accumulator width as `$clog2(CLK_HZ)+1`,
  type both recurrence constants to that width, and address the sign bit by
  `DIV_W-1`. Add a permanent proof over every configured PSG clock.
- **Result:** the complete `tools/psg_hw_forms.py` passes. Its exact interval
  proof gives widths 23 at 3,506,580 Hz, 26 at 18.75/22.5/28.125 MHz, and 28
  at 112.5 MHz, and the recurrence remains inside its signed range. Full and
  PREVIEW lint passed. `make test-psg` passed the fidelity gate, 93 analysis
  tests, and the complete structural suite at 524/850 sample clocks and
  4,008/5,103 tick clocks with zero late flips. The 59-case 18.75-MHz
  regression was byte-exact. `/4`, `/5`, and `/6` budget runs passed at
  572/1,275 and 5,757/7,654, 572/1,020 and 4,737/6,123, and 524/850 and
  4,008/5,103 sample/tick clocks, with zero lost writes, overruns, or late
  flips. `make test-clocks` passed. All eight canonical PREVIEW checks at
  1,275 and 159 clocks/sample passed at 36/38 voiced windows, rounded 95%,
  for masks 7/1/2/4. Synthetic and reconstructed-Celeste recovery probes
  passed with no coalesced, delayed, or dropped samples. Exact hardware and
  PREVIEW SFX-10 renders were active and `click-v1` found zero clicks. A
  five-frame Celeste smoke again had 2,179/3,668 off-centre samples, range
  -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec validation and
  `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed 6,568 LUT4 / 1,566
  carry / 1,478 FF / 14 EBR / 7,449 placed LCs to 6,522 LUT4 / 1,553 carry /
  1,476 FF / 14 EBR / 7,392 placed LCs. Routed clocks changed from 137.65 and
  31.16 MHz to 134.70 and 30.95 MHz; both remain above their 112.50 and
  18.75-MHz constraints. The 46-LUT4, 13-carry, and two-flop reductions are
  deterministic; the 57-LC improvement remains just inside placement
  sensitivity and is not overclaimed.
- **Decision:** accepted. It makes the parameter-dependent range contract
  explicit, improves three deterministic mapped resources, reduces seed-1
  placement, preserves every fidelity gate, retains 14 EBRs, and keeps both
  routed clocks above constraint.
- **Repeat only if:** a rejected width derivation may be retried only after
  supported clock parameters, sample rate, recurrence representation, or
  mapper registered-width inference changes materially.

## Hypothesis H008

- **ID:** H008.
- **Hypothesis:** the only two non-trivial `scnt` equality decodes are 176
  (`8'hB0`) and 182 (`8'hB6`). Exposing their common high-nibble predicate
  once and decoding only the distinguishing low nibble should preserve the
  complete counter sequence while allowing iCE40 mapping to share the prefix.
- **Scope:** isolated registered decode synthesis first; `rtl/psg_timing.sv`,
  an exhaustive all-256-counter-value proof, whole-PSG mapping, and the H007
  acceptance battery only if the isolated and whole mapped results improve.
  No sequencer, walker, waveform, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5`: 6,522 LUT4s, 1,553 carries,
  1,476 flops, 14 EBRs; seed-1 7,392 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** scratch-only explicit `scnt[7:4] == 4'hB` predicate plus low-
  nibble equality decodes; no production file changed.
- **Result:** exhaustive comparison over all 256 counter values passes for
  both the 176 and 182 predicates. Isolated registered `synth_ice40` maps the
  current direct equalities and the explicit shared-prefix form identically:
  four LUT4s and two flip-flops each.
- **Decision:** rejected before production RTL. Yosys already shares the
  common high-nibble term, so the candidate changes source without improving
  a deterministic mapped resource.
- **Repeat only if:** a rejected shared-prefix decode may be retried only after
  the tick cadence constants, counter range, mapper equality sharing, or
  surrounding counter-update control changes materially.

## Hypothesis H009

- **ID:** H009.
- **Hypothesis:** `tick_hold` reaches only 0, 1, and 2 at sample boundaries,
  with the exact sequence `2 -> 1 -> 0` after each tick. Representing that
  delay as a shift token `2'b10 -> 2'b01 -> 2'b00` makes `tick_en_d` a direct
  read of bit zero and should remove the decrement and equality decode while
  preserving every clock of the delayed strobe.
- **Scope:** exhaustive event-sequence proof and isolated registered synthesis
  first; `rtl/psg_timing.sv`, permanent timing proof, whole-PSG mapping, and
  the complete H007 acceptance battery only if mapping improves. No sequencer,
  walker, waveform, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008 `519a00e`:
  6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392 LCs;
  134.70 MHz fast and 30.95 MHz PSG.
- **Change:** replace `tick_hold`'s equality, decrement, and nonzero guard with
  a two-bit right-shifting token and direct bit-zero delayed-strobe output;
  add the ten-edge sequence proof to the timing forms gate for measurement.
- **Result:** all 59,049 ten-edge sequences over no-sample, sample, and tick
  events match exactly, including held clocks and tick-reload priority. The
  isolated registered form falls from five to three LUT4s with three flops
  unchanged. Canonical whole-PSG mapping instead moves from 6,522 LUT4 / 1,553
  carry / 1,476 FF / 14 EBR to 6,558 LUT4 / 1,558 carry / 1,476 FF / 14 EBR;
  seed-1 placement moves 7,392 to 7,428 LCs. Routed clocks remain above
  constraint at 123.50 MHz fast and 29.83 MHz PSG, but both mapped and placed
  area regress. Production RTL and the conditional permanent proof are
  reverted byte-for-byte; the complete fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The isolated local saving
  worsens the authoritative flattened mapping and violates the no-placement-
  regression gate.
- **Repeat only if:** a rejected shift-token form may be retried only after
  the delayed-tick depth, tick/sample ordering, mapper state lowering, or
  surrounding timing control changes materially.

## Hypothesis H010

- **ID:** H010.
- **Hypothesis:** after a tick resets `scnt` to zero, the delayed strobe must
  occur exactly when the next two sample edges see phases zero then one. A
  single pending bit set by the tick, held while `scnt[0]` is zero, and
  consumed while `scnt[0]` is one should replace `tick_hold`'s second flop,
  decrement, nonzero guard, and equality decode while preserving every edge.
- **Scope:** exact state/phase proof and isolated registered synthesis of the
  complete sample-counter/delayed-strobe cone first; `rtl/psg_timing.sv`, a
  permanent timing proof, whole-PSG mapping, and the complete H007 acceptance
  battery only if the isolated and whole mapped results improve. No sequencer,
  walker, waveform, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H009 through
  `6fdabb5`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** replace `tick_hold` with one pending bit. Set it when the tick
  resets `scnt` to zero, retain it through phase zero, then emit the delayed
  strobe and clear it when `scnt[0]` is one; add the complete reachable-state
  equivalence proof to the timing forms gate for measurement.
- **Result:** exhaustive state exploration from reset closes over all 185
  reachable paired states and 370 held/sample-enabled edges with identical
  `tick_en`, `tick_en_d`, `pre_tick`, and `scnt`. The isolated complete timing
  cone falls from 27 to 23 LUT4s and from 13 to 12 flops with six carries
  unchanged. Canonical whole-PSG mapping instead moves from 6,522 LUT4 / 1,553
  carry / 1,476 FF / 14 EBR to 6,551 LUT4 / 1,558 carry / 1,475 FF / 14 EBR;
  seed-1 placement moves 7,392 to 7,428 LCs. Routed clocks remain above
  constraint at 119.36 MHz fast and 29.97 MHz PSG, but the mapped and placed
  area gates fail. Production RTL and the conditional permanent proof are
  reverted byte-for-byte; the complete fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The local flop reduction
  does not offset the worse flattened covering, and this is the second neutral-
  or-worse delayed-tick variant, closing that family under the ledger stop rule.
- **Repeat only if:** a rejected phase-qualified pending bit may be retried
  only after the tick/sample ordering, `scnt` representation, delayed-tick
  depth, or mapper sequential lowering changes materially.

## Hypothesis H011

- **ID:** H011.
- **Hypothesis:** the tilted-saw tail reflects its unsigned 16-bit phase as
  `16'hffff - wx`, which is identically the bitwise complement `~wx`. Spelling
  the identity directly may prevent a subtractor/carry chain while making the
  exact reflection contract simpler.
- **Scope:** exhaustive all-phase proof and isolated registered-use iCE40
  synthesis first; `rtl/psg_wave.sv`, permanent waveform proof, whole-PSG
  mapping, and the complete H007 acceptance battery only if mapping improves.
  No schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H010 through
  `032ff34`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** scratch-only replacement of `16'hffff - wx` with `~wx`; no
  production RTL or permanent proof changed.
- **Result:** exhaustive comparison passes all 65,536 unsigned 16-bit phases.
  Isolated synthesis including the complete registered `t_pre` consumer maps
  both forms identically to 93 LUT4s, 45 carries, and 19 flops. Yosys already
  canonicalizes the constant subtract, so no whole-PSG or fidelity battery is
  needed.
- **Decision:** rejected before production RTL. The alternative is source-
  equivalent but does not improve a deterministic mapped resource.
- **Repeat only if:** a rejected complement spelling may be retried only after
  the reflected-ramp width, tail arithmetic, mapper constant-subtract
  lowering, or surrounding consumer changes materially.

## Hypothesis H012

- **ID:** H012.
- **Hypothesis:** `psg_mulmp` already asserts that true transaction busy is
  never high when `seq_pad` is zero, while its transaction and relative-phase
  benches prove padded busy matches the shipped single-clock service. Under
  that closed-loop deadline, `m_busy || (seq_pad != 0)` equals `seq_pad != 0`;
  removing the redundant OR should simplify the sequencer-busy output cone.
- **Scope:** isolated output-cone synthesis first; `rtl/psg_mulmp.sv`, all
  multiplier transaction/relative-phase proofs, whole-PSG mapping, and the
  complete H007 acceptance battery only if mapping improves. No arithmetic,
  schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H011 through
  `a7e2488`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** remove `m_busy` from `m_seq_busy`, leaving the nonzero `seq_pad`
  predicate under the module's existing true-busy deadline assertion.
- **Result:** the Boolean identity holds in all 30 logical states satisfying
  the asserted `m_busy -> seq_pad!=0` invariant, and the isolated output cone
  falls from two LUT4s to one. The real multi-clock suite passes 6,020 boundary
  and randomized transactions for both radix variants; the padded-busy trace
  matches the shipped reference at all ten 1-ns relative phases. Canonical
  whole-PSG mapping nevertheless moves from 6,522 LUT4 / 1,553 carry / 1,476
  FF / 14 EBR to 6,570 LUT4 / 1,558 carry / 1,476 FF / 14 EBR; seed-1
  placement moves 7,392 to 7,442 LCs. Routed clocks pass at 145.99 MHz fast
  and 31.21 MHz PSG, but mapped and placed area regress. Production RTL is
  reverted byte-for-byte; the complete fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The exact local output
  simplification worsens flattened covering and violates both area gates.
- **Repeat only if:** a rejected busy-output simplification may be retried only
  after the CDC latency, padding contract, clock ratio/phase, mapper output
  factoring, or sequencer-busy consumer changes materially.

## Hypothesis H013

- **ID:** H013.
- **Hypothesis:** the earlier 34-bit service width predated the current live-
  request audit. Every A is now signed-18-bit-or-narrower, so `|A| <= 131072`;
  every legal B/count/landing combination yields at most 536,739,840, below
  `2^29`. At every step the accumulator stays below `2^17`, the radix-2 sum
  below `2^18`, and radix-4 sum below `2^19`. Narrowing both internal products
  to 29 bits and those sums to their proved widths should retire invisible
  sequential/arithmetic bits while the 34-bit public result remains aligned
  by five leading zeros.
- **Scope:** `rtl/psg_mulsvc.sv`, `rtl/psg_mulmp.sv`, permanent cycle-model
  bounds in `tools/psg_mul_model.py`, multiplier transaction/relative-phase
  proofs, whole-PSG mapping, and the complete H007 acceptance battery if the
  mapped result improves. No request count, schedule, state, public result
  width, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H012 through
  `516c176`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** first narrow both multiplier implementations to a 29-bit product,
  17-bit accumulator, 18-bit radix-2 sum, and 19-bit radix-4 sum while padding
  the public result with five zeros. Then attribute the result with a second
  form that restores `psg_mulsvc` byte-for-byte and narrows only the
  multipumped implementation instantiated by the HX8K target.
- **Result:** the exact model proves every live landing and named consume slice
  on 13,874 magnitudes, both signs, all modes, and both radices. The binding
  maxima are accumulator 131,008, radix-2 sum 262,080, radix-4 sum 524,160,
  and product 536,739,840, each below the proposed width. Both forms pass
  6,020 randomized/boundary transactions and all ten 1-ns relative phases,
  comparing the complete 34-bit public result. Both forms also map and place
  identically: 6,546 LUT4 / 1,556 carry / 1,474 FF / 14 EBR and 7,418 seed-1
  LCs, routed at 134.95 MHz fast / 33.10 MHz PSG. Relative to H007 this is +24
  LUT4, +3 carries, -2 flops, and +26 LCs. Production RTL and the conditional
  model extension are reverted byte-for-byte; the full fidelity battery is
  correctly skipped.
- **Decision:** rejected after two mapped variants. The invisible bound is
  mathematically sound but narrower sequential/arithmetic covering costs more
  logic and placement than the two realized flops save, closing this width
  family under the ledger stop rule.
- **Repeat only if:** a rejected internal-width form may be retried only after
  live A/B bounds, iteration counts, landing offsets, radix recurrence,
  mapper sequential-width inference, or result consumers change materially.

## Hypothesis H014

- **ID:** H014.
- **Hypothesis:** the widest detune correction is `ceil(6*dp/256)`, which
  reaches only 192 over all 8,192 `dp13` values; the `/64`, `/128`, and `/256`
  corrections reach 128, 64, and 32. Narrowing `dq_ceil6_256` and the shared
  `dq_corr` mux from nine bits to eight should remove one adder, mux, and final
  subtract position without changing any value.
- **Scope:** `rtl/psg_wave.sv`, exhaustive correction-range/equivalence proof
  in `tools/psg_hw_forms.py`, isolated registered-use synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H013 through
  `f1f127e`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** narrow `dq_ceil6_256`, the shared correction mux, every extension
  arm, and the final subtract operand by one bit; add an exhaustive proof of
  all four correction maxima. Compare both forms in one registered full-detune
  harness containing every producer, selection arm, subtract, and output flop.
- **Result:** the exhaustive proof passes all 8,192 `dp13` values and reports
  maxima 192, 128, 64, and 32. The complete registered-use cone maps both the
  nine-bit baseline and eight-bit candidate identically to 189 LUT4s, 73
  carries, and 14 flops. Yosys already propagates the range and deletes the
  unreachable ninth bit through the existing source spelling. Production RTL
  and the conditional permanent proof are reverted byte-for-byte; whole-PSG
  synthesis and the fidelity battery are correctly skipped.
- **Decision:** rejected before production RTL. The source-visible width is
  redundant, but narrowing it does not improve any deterministic mapped
  resource and therefore cannot satisfy the acceptance gate.
- **Repeat only if:** a rejected correction-width form may be retried only
  after the detune coefficients, `dp13` range, correction mux, mapper width
  inference, or downstream subtract changes materially.

## Hypothesis H015

- **ID:** H015.
- **Hypothesis:** every branch that leaves `dq_sub` false also leaves
  `dq_corr` zero. Therefore `dq_sub ? (dq_base - dq_corr) : dq_base` is
  identically `dq_base - dq_corr`; deleting `dq_sub` and the final result mux
  should simplify both the source contract and registered output cone.
- **Scope:** `rtl/psg_wave.sv`, exhaustive waveform/mode/phase equivalence in
  `tools/psg_hw_forms.py`, isolated registered-use synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  arithmetic value, schedule, state, interface, EBR, R.84, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H014 through
  `837cfaf`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** remove `dq_sub` and write the final result as one unconditional
  subtraction; add an exhaustive proof over all 524,288 wavetable/wave/mode/
  `dp13` inputs. Compare both forms in the same registered full-detune harness.
- **Result:** the exhaustive proof establishes `dq_corr == 0` on every path
  where the baseline bypasses subtraction. Both registered-use cones map
  identically to 188 LUT4s, 73 carries, and 14 flops. Yosys already folds the
  conditional base path into the correction/subtract network. Production RTL
  and the conditional permanent proof are reverted byte-for-byte; whole-PSG
  synthesis and the fidelity battery are correctly skipped.
- **Decision:** rejected before production RTL. It removes a source signal but
  does not improve a deterministic mapped resource.
- **Repeat only if:** a rejected unconditional-subtract form may be retried
  only after the detune branch structure, correction defaults, mapper
  arithmetic/mux folding, or downstream consumer changes materially.

## Hypothesis H016

- **ID:** H016.
- **Hypothesis:** the restoring divider maintains `0 <= remainder < divisor`.
  After shifting one dividend bit, `rsh < 2*divisor`; a successful subtraction
  is therefore below 256, while a failed nine-bit subtraction wraps with bit 8
  set. The current ten-bit `d_sub` and bit-9 borrow test can narrow to nine bits
  and bit 8 without changing any reachable step, potentially removing one
  carry/LUT position from the only registered divider service.
- **Scope:** `rtl/psg_divsvc.sv`, exhaustive reachable-step proof in
  `tools/psg_hw_forms.py`, isolated full-service iCE40 synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  division latency, quotient/remainder value, schedule, interface, EBR, R.84,
  or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H015 through
  `c0afe6a`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Changed condition versus closed width experiments:** H013 changed stored
  multiplier recurrence widths and mapped worse; H014 exposed a combinational
  range already removed by Yosys. H016 instead changes the live borrow encoding
  using a sequential restoring invariant that synthesis cannot infer locally.
- **Change:** narrow `d_sub` from ten to nine bits and move the borrow test from
  bit 9 to bit 8. Add an exhaustive proof over all 65,280 reachable divisor,
  remainder, and incoming-dividend-bit transitions.
- **Result:** the proof establishes the restoring invariant and exact fit/next-
  remainder equivalence. Isolated full-service synthesis moves from 51 LUT4 /
  12 carry / 45 flop to 52 LUT4 / 11 carry / 45 flop. Canonical whole-PSG
  synthesis then regresses from 6,522 LUT4 / 1,553 carry / 1,476 FF / 14 EBR /
  7,392 LCs to 6,582 LUT4 / 1,561 carry / 1,476 FF / 14 EBR / 7,459 LCs.
  Routed clocks pass at 150.53 MHz fast and 32.42 MHz PSG, but both mapped and
  placed area gates fail. Production RTL and the conditional permanent proof
  are reverted byte-for-byte; the full fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The reachable-state width
  proof is sound, but the altered borrow covering is globally much worse.
- **Repeat only if:** a rejected nine-bit divider subtract may be retried only
  after the restoring recurrence, divisor width/domain, mapper subtract
  lowering, or downstream quotient/remainder contract changes materially.

## Hypothesis H017

- **ID:** H017.
- **Hypothesis:** full-schedule gain reconstruction has three mutually
  exclusive consumers: W27 uses the new non-wavetable context, W51 uses the
  new wavetable context or the old non-wavetable context. Selecting the narrow
  `{wave, sign}` context first should let one scale mux and negate feed both
  destination arms, replacing `gz_scaled`, `gz_old_scaled`, `mx_new_w51`, and
  `mx_old_w51` with one source-exact result and simpler code.
- **Scope:** `rtl/psg_walk.sv`, exhaustive W27/W51 context equivalence in
  `tools/psg_hw_forms.py`, isolated registered-use synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  arithmetic value, schedule/action, register lifetime, interface, EBR, R.84,
  or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H016 through
  `2bf1a29`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Changed condition versus prior grouping:** R.36/H007 grouped identical
  multiplier request operands before a wide request mux. H017 applies the same
  accepted narrow-selection law to a different, post-multiply gain consumer
  whose three schedule contexts are now explicit and mutually exclusive.
- **Change:** first select old/new wave and sign before one scale/negate chain.
  Then attribute the result with a scale-only variant that selects the wave
  before one scale mux but keeps sign selection at the destination arms.
- **Result:** all 768 valid W27/W51 context combinations match. Isolated full
  sharing moves 99 LUT4 / 30 carry / 34 flop to 59 / 15 / 34; whole-PSG
  mapping instead moves to 6,538 LUT4 / 1,547 carry / 1,476 FF / 14 EBR and
  7,428 LCs, with routed clocks 134.70 MHz fast / 30.27 MHz PSG. The scale-only
  form maps locally to 90 LUT4 / 15 carry / 34 flop, but globally to 6,533
  LUT4 / 1,547 carry / 1,476 FF / 14 EBR and 7,414 LCs, routed at 140.92 MHz
  fast / 26.11 MHz PSG. Relative to H007, v1 is +16 LUT4/-6 carry/+36 LCs and
  v2 is +11 LUT4/-6 carry/+22 LCs. Production RTL and the conditional proof
  are reverted byte-for-byte; the full fidelity battery is correctly skipped.
- **Decision:** rejected after two whole-PSG variants. Selecting narrow context
  operands reduces the isolated cone, but its new schedule-control fanout
  worsens flattened destination covering and violates the placement gate.
- **Repeat only if:** a rejected selected-context gain form may be retried only
  after the W27/W51 schedule, gain reconstruction, sign ownership, mapper
  destination covering, or old/new lifetime changes materially.

## Hypothesis H018

- **ID:** H018.
- **Hypothesis:** `gz_171` currently forms the 26-bit sum `341*x + x` and then
  discards bit zero. The exact identity `floor((A+B)/2) = (A>>1) + (B>>1) +
  (A0 & B0)` can compute the same sibling with a 25-bit adder and one carry-in,
  potentially retiring one live carry position without changing truncation.
- **Scope:** `rtl/psg_walk.sv`, exhaustive live-limb proof in
  `tools/psg_hw_forms.py`, isolated registered-use synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  multiplier request/result, schedule, state, interface, EBR, R.84, or
  tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H017 through
  `cf9e8d3`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Change:** replace the 26-bit `A+B` followed by `[25:1]` with the 25-bit
  sum `(A>>1) + (B>>1) + (A0 & B0)`; add an exhaustive proof over all 131,072
  live 17-bit limbs.
- **Result:** the exact proof passes. Isolated registered-use synthesis moves
  from 25 LUT4 / 25 carry / 25 flop to 26 LUT4 / 24 carry / 25 flop. Canonical
  whole-PSG synthesis instead moves to 6,553 LUT4 / 1,562 carry / 1,476 FF /
  14 EBR and 7,430 seed-1 LCs, or +31 LUT4/+9 carry/+38 LCs versus H007.
  Routed clocks pass at 121.82 MHz fast / 29.55 MHz PSG, but both mapped and
  placed area gates fail. Production RTL and the conditional permanent proof
  are reverted byte-for-byte; the full fidelity battery is correctly skipped.
- **Decision:** rejected after whole-PSG synthesis. The smaller isolated carry
  chain worsens flattened covering and loses substantial fast-clock margin.
- **Repeat only if:** a rejected shifted-half-sum form may be retried only
  after the reciprocal identity, limb width, mapper carry lowering, or gain
  consumer changes materially.

## Hypothesis H019

- **ID:** H019.
- **Hypothesis:** `prun` already grants the sample walker exclusive ownership
  of the shared state memory for the complete walk. Selecting the read address,
  write address, write data, and write enable once by that owner should remove
  the walker's phase-qualified read request and per-operation write selects,
  while making the arbitration contract simpler and more explicit.
- **Scope:** `rtl/psg_state_mem.sv`, `rtl/psg_walk.sv`, `rtl/psg.sv`, focused
  ownership/replay proof, isolated state-store iCE40 synthesis, whole-PSG
  mapping, and the complete H007 acceptance battery if mapping improves. No
  state layout/value, walk phase/action, sequencer operation, interface outside
  the PSG, EBR, R.84 executor/controller, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H018 through
  `a1364c5`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1 7,392
  LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Ownership/replay proof obligation:** at the edge which starts a walk,
  pre-edge `prun` is still zero, so the sequencer owns and completes its current
  state-memory operation. While `prun` is one, `walk_frozen` makes `seq_hold`
  one, which forces both `eng_we` and `state_tick_we` low and therefore
  `etk_we == 0`; every `wlk_we` is already qualified by `prun`. At the final
  walk edge, the candidate may fetch an otherwise-unused walker word instead
  of the held sequencer address. The registered `state_replay <= prun` then
  holds the sequencer for the entire following reissue edge, when `prun` is
  zero and the sequencer address is fetched again. The sequencer can advance
  and consume `state_q` only on the next edge, after the reissued value is live.
- **Change:** remove `wlk_rd`/`state_sample_read`; first select the complete
  state-memory request bundle with `prun`, then attribute the result with a
  second form which retains the existing write-enable OR while selecting only
  read/write address and write data by whole-walk ownership.
- **Result:** the focused proof exhausts all four legal write-owner states, all
  29 walker words consumed across preview/hardware schedules, and the final-
  read/reissue/resume timeline. Full and PREVIEW lint pass. The complete-bundle
  form improves the isolated state-store cone from 67 LUT4 / 10 carry / 43 FF /
  two EBR to 65 / 5 / 43 / two EBR, but whole-PSG mapping moves to 6,570 LUT4 /
  1,560 carry / 1,476 FF / 14 EBR and 7,452 seed-1 LCs, or +48 LUT4/+7 carry/
  +60 LCs versus H007. Both clocks pass at 142.57 MHz fast / 32.87 MHz PSG.
  Retaining the write-enable OR improves the isolated cone further to 59 LUT4 /
  5 carry / 43 FF / two EBR, but whole-PSG mapping still regresses to 6,544
  LUT4 / 1,559 carry / 1,476 FF / 14 EBR, or +22 LUT4/+6 carry. Its seed-1
  router remains at two overused resources after more than 14,000 iterations
  and is stopped because the deterministic mapped gate has already failed.
  The complete fidelity battery is correctly skipped. All production RTL and
  the conditional proof are reverted byte-for-byte.
- **Decision:** rejected after two whole-PSG forms. Whole-walk ownership is a
  sound source simplification, but its higher-fanout owner select worsens the
  flattened mapping and neither form has a deterministic mapped improvement.
- **Repeat only if:** if rejected, retry only after the walk/replay ownership
  interval, state-memory port topology, mapper mux absorption, or sequencer
  write-gating contract changes materially.

## Hypothesis H020

- **ID:** H020.
- **Hypothesis:** audio-RAM synthesis reads are explicitly qualified by
  `prun`, and their registered one-cycle replay occurs while the walk is still
  active. Therefore `seq_frozen = syn_rd | replay` is already implied by the
  top-level `prun` hold. Removing that exported busy term while retaining the
  RAM's internal replay/reissue should simplify the hold cone without changing
  any address, data, FSM, credit, or sample clock.
- **Scope:** `rtl/psg_aram.sv`, `rtl/psg.sv`, focused phase/containment proof,
  isolated registered hold-cone synthesis, whole-PSG mapping, and the complete
  H007 acceptance battery if mapping improves. No RAM content/port operation,
  sequencer/walker action, arithmetic, state layout, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H020 setup
  through `f3e5f8d`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1
  7,392 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Containment proof obligation:** `psg_walk.syn_rd` is zero by default and
  can become one only inside `prun && !ctrl_stall`. In preview its last possible
  read is phase 13 versus `PLAST=23`; in multipumped hardware the last read is
  action W3 at phase 32 versus `PLAST=61`. Since `replay <= syn_rd`, every
  replay edge also occurs while `prun` remains one, including a stalled phase.
  Thus `syn_rd | replay` cannot add a held clock beyond `prun`; only the internal
  `aram_rd = syn_rd | replay | !seq_hold` reissue remains semantically live.
- **Change:** remove the redundant `seq_frozen` output and its top-level
  OR term, without changing `replay`, `aram_rd`, or the address mux.
- **Result:** the focused proof exhausts all six preview/hardware wavetable-read
  phases and proves their replay edges precede `PLAST`. Full and PREVIEW lint
  pass. The isolated registered hold cone falls from 13 to 12 LUT4s with six
  carries and nine flops unchanged. Canonical whole-PSG mapping instead moves
  from 6,522 LUT4 / 1,553 carry / 1,476 FF / 14 EBR / 7,392 LCs to 6,525 /
  1,556 / 1,476 / 14 / 7,393. Routed timing passes at 142.86 MHz fast / 28.95
  MHz PSG, but both deterministic mapping and no-placement-regression gates
  fail. The complete fidelity battery is correctly skipped. Both production
  RTL files are restored byte-for-byte.
- **Decision:** rejected after whole-PSG synthesis. The temporal redundancy is
  exact, but removing its explicit output changes flattened covering for the
  worse and has no accepted physical metric.
- **Repeat only if:** if rejected, retry only after wavetable-read phase,
  audio-RAM replay depth, walk termination, mapper busy-cone lowering, or
  sequencer-credit ownership changes materially.

## Hypothesis H021

- **ID:** H021.
- **Hypothesis:** `fdec(n)` is exactly the three base-3 digits of `n mod 27`,
  each stored in a two-bit field. Replacing its 32 explicit case arms with one
  wrap-at-27 step and two small quotient/remainder stages should make the
  filter contract much shorter and may share the narrow comparisons/subtracts
  better than the table mux.
- **Scope:** `rtl/psg_seq.sv`, exhaustive all-32-input equivalence, isolated
  registered decoder/consumer synthesis, whole-PSG mapping, and the complete
  H007 acceptance battery if mapping improves. No note data, filter value,
  FSM phase/action, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H021 setup
  through `5e0f19b`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1
  7,392 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Changed condition versus prior decode experiments:** task 5.3 explicitly
  leaves filter decode open. H021 replaces the entire 32-arm function using
  its arithmetic structure; it does not peel individual phase consumers from
  shared pph decode or add a new ROM/EBR.
- **Change:** exhaustively prove the identity and compare both direct `/`/`%`
  arithmetic and explicit two-stage threshold/subtract decompositions against
  the full registered table consumer. No production RTL is changed.
- **Result:** all 32 inputs match the packed base-3 digits of `n mod 27`. The
  existing table maps to 23 LUT4 / zero carry / 12 FF. Direct arithmetic maps
  to 28 LUT4 / 70 carry / 12 FF, while the staged form maps to 26 LUT4 / 11
  carry / 12 FF. Both candidates are strictly larger in the isolated complete
  consumer cone, so whole-PSG synthesis and the fidelity battery are correctly
  skipped.
- **Decision:** rejected before production RTL. The arithmetic structure is a
  useful specification, but the current truth table already receives superior
  Boolean covering from Yosys/ABC.
- **Repeat only if:** if rejected, retry only after the note filter encoding,
  consumer fields, mapper truth-table/arithmetic lowering, or constants-ROM
  port schedule changes materially.

## Hypothesis H022

- **ID:** H022.
- **Hypothesis:** for signed nine-bit `v`, clamping to unsigned 0..63 is exactly
  `v[8] ? 0 : |v[7:6] ? 63 : v[5:0]`. Spelling the sign and overflow prefixes
  directly should remove two relational comparisons from each inlined pitch
  clamp while making its saturation contract explicit.
- **Scope:** `rtl/psg_seq.sv`, exhaustive all-512-input proof, isolated
  registered synthesis of the three live clamp consumers, whole-PSG mapping,
  and the complete H007 acceptance battery if mapping improves. No pitch value,
  FSM phase/action, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H007 commit `48f0ef5` plus docs-only H008--H022 setup
  through `d703d5e`: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs; seed-1
  7,392 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- **Changed condition versus H004:** H004 narrowed one unsigned aligned waveform
  threshold which Yosys already pruned. H022 replaces both sides of a signed
  saturating clamp at three sequencer consumers using the sign/overflow prefix;
  it is a different cone and removes relational operators entirely.
- **Change:** replace the two relational comparisons in `pclamp` with the exact
  sign/high-bit decode at all three inlined consumers. Attribute the first
  whole-PSG result with a second form that also narrows the three live raw sums
  from nine to eight signed bits using their proved -24..102 range.
- **Attribution:** the general nine-bit form reduces the isolated live cone
  from 111 LUT4 / 37 carry / 18 FF to 96 / 24 / 18. Whole-PSG mapping instead
  moves to 6,546 LUT4 / 1,540 carry / 1,476 FF / 14 EBR and 7,398 seed-1 LCs,
  or +24 LUT4/-13 carry/+6 LCs versus H007. Timing passes at 150.53 MHz fast /
  30.83 MHz PSG, but placement fails the no-regression gate. The live-range
  eight-bit attribution form maps to 6,539 LUT4 / 1,539 carry / 1,476 FF / 14
  EBR and 7,391 seed-1 LCs, or +17 LUT4/-14 carry/-1 LC versus H007. Timing
  passes at 150.53 MHz fast / 29.86 MHz PSG. The carry improvement is
  deterministic; the one-LC placement change is inside sensitivity and is not
  claimed as robust.
- **Result:** exhaustive proofs cover all 512 signed-nine inputs and all 4,096
  live unsigned-six operand pairs, proving the live range -24..102 and exact
  signed-eight saturation. The complete `tools/psg_hw_forms.py`, full/PREVIEW
  lint, `make test-psg` (93 analysis tests and every structural test), and the
  59/59 exact 18.75-MHz frozen-render regression passed. The `/4`, `/5`, and
  `/6` demand tests retained 524 worst walk/sample clocks and tick results
  5,757/7,654, 4,737/6,123, and 4,008/5,103 with zero lost writes, overruns, or
  late flips. `make test-clocks` passed. All eight P.1 Celeste preview checks
  at 1,275 and 159 clocks/sample passed with 36/38 voiced windows, or 95%, for
  combined and masks 1/2/4; both P.2 recovery probes passed. Exact hardware
  and PREVIEW SFX-10 renders were active and `click-v1` found zero clicks. The
  five-frame Celeste smoke had 2,179/3,668 off-centre samples, range
  -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec validation and
  `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed H007's 6,522 LUT4 /
  1,553 carry / 1,476 FF / 14 EBR / 7,392 placed LCs to 6,539 LUT4 / 1,539
  carry / 1,476 FF / 14 EBR / 7,391 placed LCs. Routed clocks changed from
  134.70 and 30.95 MHz to 150.53 and 29.86 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The 14-carry reduction is deterministic; the
  one-LC placement improvement is inside sensitivity and is not overclaimed.
- **Decision:** accepted. It makes the proved -24..102 live range and
  saturation contract explicit, removes the signed relational comparisons,
  improves a deterministic mapped resource, does not regress placed LCs,
  preserves every fidelity gate, and retains 14 EBRs. The 17-LUT4 tradeoff is
  recorded rather than hidden.
- **Repeat only if:** if rejected, retry only after pitch operand bounds/width,
  saturation range, consumer count, or mapper signed-comparison lowering changes.

## Hypothesis H023

- **ID:** H023.
- **Hypothesis:** the six-bit slide pitch's octave thresholds have exact prefix
  predicates: `>=12`, `>=24`, `>=36`, `>=48`, and `>=60` depend only on
  compact combinations of bits 5:2. Replacing the five relational comparisons
  with those shared predicates should remove comparator carry chains while
  preserving both `sl_oct` and the existing `sl_chr = sl_int - 12*sl_oct`.
- **Scope:** scratch exhaustive proof and isolated registered synthesis of the
  complete octave/chromatic consumer cone. Production `rtl/psg_seq.sv`, the
  permanent hardware-forms proof, whole-PSG mapping, and the complete H022
  battery are conditional on a deterministic isolated mapped improvement. No
  pitch value, slide interpolation, FSM phase/action, service, memory, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H022 commit `f569fa1`: 6,539 LUT4s, 1,539 carries,
  1,476 flops, 14 EBRs; seed-1 7,391 LCs; 150.53 MHz fast and 29.86 MHz PSG.
- **Changed condition versus H004:** H004 narrowed one unsigned square-wave
  threshold and mapped identically because Yosys already discarded aligned low
  bits. H023 replaces a five-threshold ladder, exposes shared prefix terms, and
  includes the downstream octave/remainder consumers in the isolated price.
- **Change:** replace the five six-bit relational thresholds with five exact
  shared prefix predicates over `sl_int[5:2]`; retain the priority encoding and
  chromatic subtract. Add all 64 octave/remainder cases to the permanent
  hardware-forms proof.
- **Result:** the scratch proof, permanent exhaustive proof, and full
  `tools/psg_hw_forms.py` passed. The isolated registered octave/chromatic cone
  changed from eight LUT4s / 12 carries / nine flops to seven LUT4s / one carry
  / nine flops. Full and PREVIEW lint, `make test-psg`, 59/59 exact renders,
  `/4`, `/5`, and `/6` budget regressions, and `make test-clocks` passed. All
  eight P.1 Celeste preview checks at 1,275 and 159 clocks/sample passed with
  36/38 voiced windows, or 95%, for combined and masks 1/2/4; synthetic and
  frozen-Celeste recovery passed. Exact hardware and PREVIEW SFX-10 renders
  were active and `click-v1` found zero clicks. The five-frame Celeste smoke
  had 2,179/3,668 off-centre samples, range -22,013..9,151, and 1,068 distinct
  levels. Strict OpenSpec validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed H022's 6,539 LUT4 /
  1,539 carry / 1,476 FF / 14 EBR / 7,391 placed LCs to 6,529 LUT4 / 1,533
  carry / 1,476 FF / 14 EBR / 7,367 placed LCs. Routed clocks changed from
  150.53 and 29.86 MHz to 122.23 and 30.64 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The ten-LUT4 and six-carry reductions are
  deterministic; the 24-LC placement improvement is inside sensitivity and is
  not overclaimed.
- **Decision:** accepted. It makes the exact prefix structure explicit,
  improves two deterministic mapped resources, does not regress placed LCs,
  preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** if rejected, retry only after slide pitch width/range,
  octave thresholds, chromatic representation, or mapper comparison lowering
  changes materially.

## Hypothesis H024

- **ID:** H024.
- **Hypothesis:** both row-length bounds return the source value only on the
  exact interval 1--31 and return 32 otherwise. Expressing those intervals as
  non-zero low-five-bit values with zero upper prefixes should remove the two
  comparator carry cells and make the clamp contract explicit.
- **Scope:** exhaustive scratch proof and isolated registered synthesis of both
  row-bound consumers. Production `rtl/psg_seq.sv`, a permanent hardware-forms
  proof, whole-PSG mapping, and the complete H023 battery are conditional on a
  deterministic isolated mapped improvement. No row value, sequencer state,
  address, schedule, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H023 commit `e3823f5`: 6,529 LUT4s, 1,533 carries,
  1,476 flops, 14 EBRs; seed-1 7,367 LCs; 122.23 MHz fast and 30.64 MHz PSG.
  Isolated reconnaissance maps the complete current pair to nine LUT4s / two
  carries / 14 flops and the prefix pair to nine LUT4s / zero carries / 14
  flops; whole-PSG mapping remains authoritative.
- **Changed condition versus H004:** H004 narrowed one already-aligned waveform
  threshold and mapped identically. H024 collapses two nested clamp/select
  expressions to exact interval predicates and the isolated complete consumer
  cone already removes two mapped carry cells.
- **Change:** replace both nested non-zero/range clamps with exact upper-prefix
  tests and direct zero-extension of `acc[4:0]`; add exhaustive permanent proof
  during measurement.
- **Result:** exhaustive comparison passed for all 65,536 `acc` values in the
  effect-end bound and all 65,536 low-byte/`seq_q` combinations in the pattern
  bound. The isolated registered pair changed from nine LUT4s / two carries /
  14 flops to nine LUT4s / zero carries / 14 flops. The whole-PSG mapped gate
  then failed, so the full fidelity battery was not run and both production and
  permanent-proof edits were reverted.
- **Physical result:** canonical seed-1 mapping changed H023's 6,529 LUT4 /
  1,533 carry / 1,476 FF / 14 EBR / 7,367 placed LCs to 6,561 LUT4 / 1,526
  carry / 1,476 FF / 14 EBR / 7,386 placed LCs. Routed clocks changed from
  122.23 and 30.64 MHz to 132.70 and 29.40 MHz; both pass, but the 32-LUT4 and
  19-LC regressions outweigh the seven-carry reduction.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the current nested clamps; the prefix spelling is locally smaller only
  in carry count and globally worse in both LUT4s and placed LCs.
- **Repeat only if:** if rejected, retry only after row metadata semantics,
  clamp value, consumer sharing, or mapper comparison lowering changes.

## Hypothesis H025

- **ID:** H025.
- **Hypothesis:** fade advancement currently spells the same
  `fade_acc + fade_step` operation once at 17 bits for overflow and twice at
  16 bits for the next accumulator/gain. One explicit 17-bit sum should expose
  the shared carry chain, replace the constant comparison with its carry bit,
  and simplify all three consumers without changing fade behavior.
- **Scope:** scratch exact/formal equivalence and isolated registered synthesis
  of the complete fade consumer cone. Production `rtl/psg_seq.sv`, a permanent
  hardware-forms proof, whole-PSG mapping, and the complete H023 battery are
  conditional on a deterministic isolated mapped improvement. No fade rate,
  direction, stop behavior, tick cadence, state, schedule, memory, EBR, R.84
  executor, or tolerance change.
- **Baseline:** accepted H023 commit `e3823f5`: 6,529 LUT4s, 1,533 carries,
  1,476 flops, 14 EBRs; seed-1 7,367 LCs; 122.23 MHz fast and 30.64 MHz PSG.
- **Change:** scratch one explicit 17-bit sum, use its carry as overflow, and
  use its low 16/high eight bits for the accumulator and gain consumers.
- **Result:** Yosys formal equivalence proved all 25 output bits. Isolated
  registered `synth_ice40` maps both the current repeated expressions and the
  explicit shared sum to 24 LUT4s / 16 carries / 25 flops. No production or
  permanent-proof file changed, and the whole-design/fidelity gates were not
  needed.
- **Decision:** rejected before production because it changes source spelling
  without changing the deterministic mapped cone.
- **Repeat only if:** if rejected, retry only after fade accumulator/step width,
  next-gain consumers, overflow contract, or mapper common-subexpression
  lowering changes materially.

## Hypothesis H026

- **ID:** H026.
- **Hypothesis:** the sequencer's shared rollover/loop/record predicate
  `(ta_a + 1) >= ta_b` is exactly the carry-out of
  `{0,ta_a} + {0,~ta_b} + 2`. Spelling that carry directly may merge the
  increment and comparison into one chain while making the inclusive bound
  contract explicit.
- **Scope:** exhaustive/formal scratch proof and isolated registered synthesis
  of the complete predicate cone. Production `rtl/psg_seq.sv`, a permanent
  hardware-forms proof, whole-PSG mapping, and the complete H023 battery are
  conditional on a deterministic isolated mapped improvement. No counter,
  loop, row, state, address, schedule, memory, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H023 commit `e3823f5`: 6,529 LUT4s, 1,533 carries,
  1,476 flops, 14 EBRs; seed-1 7,367 LCs; 122.23 MHz fast and 30.64 MHz PSG.
- **Change:** scratch the raw two's-complement carry and then repair its sole
  `a=255,b=0` counterexample with an explicit `b==0` term. Promote the repaired
  form and exhaustive all-pairs proof for whole-PSG measurement.
- **Result:** formal equivalence refuted the raw carry at exactly the tenth-bit
  overflow corner; that form mapped to 15 LUT4s / seven carries / one flop.
  Formal equivalence and exhaustive enumeration then proved the repaired form
  for all 65,536 input pairs. The exact isolated registered cone changed from
  16 LUT4s / 16 carries / one flop to 16 LUT4s / seven carries / one flop. The
  whole-PSG mapped gate failed, so the full fidelity battery was not run and
  both production and permanent-proof edits were reverted.
- **Physical result:** canonical seed-1 mapping changed H023's 6,529 LUT4 /
  1,533 carry / 1,476 FF / 14 EBR / 7,367 placed LCs to 6,560 LUT4 / 1,519
  carry / 1,476 FF / 14 EBR / 7,381 placed LCs. Routed clocks changed from
  122.23 and 30.64 MHz to 137.42 and 30.44 MHz; both pass, but the 31-LUT4 and
  14-LC regressions outweigh the 14-carry reduction.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the current relational predicate; the explicit carry is locally and
  globally carry-smaller but globally worse in LUT4s and placed LCs.
- **Repeat only if:** if rejected, retry only after bound width/semantics,
  predicate consumers, or mapper compare/carry lowering changes materially.

## Hypothesis H027

- **ID:** H027.
- **Hypothesis:** the duplicated signed 18-bit noise clamps compare against
  exact boundaries +6144 and -6144. Direct positive and two's-complement
  negative prefix predicates may remove both comparator carry chains while
  making the saturation interval explicit.
- **Scope:** exhaustive all-18-bit proof and isolated registered synthesis of
  the complete clamp output. Production `rtl/psg_walk.sv`, a permanent
  hardware-forms proof, whole-PSG mapping, and the complete H023 battery are
  conditional on a deterministic isolated mapped improvement. No noise value,
  clamp constant, live/old path, state, schedule, memory, EBR, R.84 executor,
  or tolerance change.
- **Baseline:** accepted H023 commit `e3823f5`: 6,529 LUT4s, 1,533 carries,
  1,476 flops, 14 EBRs; seed-1 7,367 LCs; 122.23 MHz fast and 30.64 MHz PSG.
- **Changed condition versus H022:** H022's pitch clamp uses aligned sign/high-
  bit boundaries 0 and 64. H027 has the distinct unaligned symmetric audio
  interval -6143..6143, including an asymmetric two's-complement lower prefix,
  and the complete output mux is measured rather than only its predicates.
- **Change:** replace both signed relational clamp ladders with one shared helper
  that decodes the exact positive and two's-complement negative prefixes; add
  exhaustive permanent coverage of every signed 18-bit input.
- **Result:** Yosys formal equivalence and the permanent proof cover all
  262,144 inputs; full `tools/psg_hw_forms.py` passes. One isolated registered
  clamp changes from 23 LUT4s / 32 carries / 16 flops to 25 LUT4s / zero
  carries / 16 flops. Full and PREVIEW lint passed. `make test-psg` passed the
  PICO-8 noise-fidelity gate, all 93 analysis tests, and the complete structural
  suite at 524/850 sample clocks and 4,008/5,103 tick clocks with zero late
  flips. The 59-case 18.75-MHz frozen-render regression was byte-exact. `/4`,
  `/5`, and `/6` budget runs passed at 572/1,275 and 5,757/7,654, 572/1,020 and
  4,737/6,123, and 524/850 and 4,008/5,103 sample/tick clocks, with zero lost
  writes, overruns, or late flips. `make test-clocks` passed. All eight P.1
  Celeste preview checks at 1,275 and 159 clocks/sample passed with 36/38 voiced
  windows, or 95%, for combined and masks 1/2/4. Synthetic and frozen-Celeste
  recovery passed with no coalesced, delayed, or dropped samples. Exact hardware
  and PREVIEW SFX-10 renders were active and `click-v1` found zero clicks. The
  five-frame Celeste smoke had 2,179/3,668 off-centre samples, range
  -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec validation and
  `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed H023's 6,529 LUT4 /
  1,533 carry / 1,476 FF / 14 EBR / 7,367 placed LCs to 6,550 LUT4 / 1,464
  carry / 1,476 FF / 14 EBR / 7,306 placed LCs. Routed clocks changed from
  122.23 and 30.64 MHz to 146.69 and 32.99 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The 69-carry reduction is deterministic. The
  61-LC improvement is at the established roughly 60-LC sensitivity boundary
  and is recorded without claiming robustness; the 21-LUT4 tradeoff is explicit.
- **Decision:** accepted. It centralizes the duplicated saturation contract,
  removes both signed relational carry chains, improves the mapped carry count
  substantially, does not regress placement, preserves every fidelity gate,
  and retains 14 EBRs.
- **Repeat only if:** if rejected, retry only after noise width/range, clamp
  constant, live/old consumer structure, or mapper signed-comparison lowering
  changes materially.

## Hypothesis H028

- **ID:** H028.
- **Hypothesis:** the eight-bit arpeggio-speed test `eff_sp <= 8` is exactly
  zero in bits 7:4 with either bit 3 clear or all lower three bits clear.
  Exposing that prefix once for both fast/slow bit-slice selections may remove
  the relational comparator carry chain and simplify the selector contract.
- **Scope:** exhaustive scratch proof and isolated registered synthesis of the
  complete `arp_idx` consumer cone. Production `rtl/psg_seq.sv`, a permanent
  hardware-forms proof, whole-PSG mapping, and the complete H027 battery are
  conditional on a deterministic isolated mapped improvement. No effect code,
  speed, tick counter, selected index, state, schedule, memory, EBR, R.84
  executor, or tolerance change.
- **Baseline:** accepted H027 commit `9c4a1ac`: 6,550 LUT4s, 1,464 carries,
  1,476 flops, 14 EBRs; seed-1 7,306 LCs; 146.69 MHz fast and 32.99 MHz PSG.
- **Changed condition versus H004/H024:** H004's aligned waveform threshold was
  already pruned, and H024's pair of clamp outputs regressed globally. H028 is
  one shared non-aligned predicate feeding two effect-dependent bit-slice muxes;
  the complete consumer cone is priced before production.
- **Change:** replace the duplicated relational test with one exact upper-prefix
  predicate and add exhaustive permanent proof during measurement.
- **Result:** Yosys formal equivalence proves both `arp_idx` output bits, and
  exhaustive enumeration proves the predicate for all 256 speed bytes. The
  isolated registered consumer changes from nine LUT4s / four carries / two
  flops to 11 LUT4s / zero carries / two flops. Whole-PSG mapping then fails the
  physical gate, so the full fidelity battery was not run and both production
  and permanent-proof edits were reverted.
- **Physical result:** canonical seed-1 mapping changed H027's 6,550 LUT4 /
  1,464 carry / 1,476 FF / 14 EBR / 7,306 placed LCs to 6,558 LUT4 / 1,464
  carry / 1,476 FF / 14 EBR / 7,319 placed LCs. Routed clocks changed from
  146.69 and 32.99 MHz to 128.35 and 32.70 MHz; both pass, but the candidate
  adds eight LUT4s and 13 LCs without any global carry reduction.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the relational test; the prefix is locally carry-smaller but globally
  worse in both LUT4s and placed LCs.
- **Repeat only if:** if rejected, retry only after effect-speed semantics,
  counter slicing, consumer sharing, or mapper comparison lowering changes.

## Hypothesis H029

- **ID:** H029.
- **Hypothesis:** `3*nz_g <= nz_dp + 497` is exactly the non-negative sign of
  the 16-bit margin `nz_dp + 497 - 3*nz_g`; its full range is
  -24,076..8,688. Spelling the bounded margin directly may replace the current
  right-side add plus relational comparator with one shared subtract chain.
- **Scope:** formal scratch proof and isolated registered synthesis of the
  complete kick-enable cone, including the `3*nz_g` add. Production
  `rtl/psg_walk.sv`, a permanent hardware-forms range/boundary proof,
  whole-PSG mapping, and the complete H027 battery are conditional on a
  deterministic isolated mapped improvement. No noise step, kick probability,
  oscillator value, state, schedule, memory, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H027 commit `9c4a1ac`: 6,550 LUT4s, 1,464 carries,
  1,476 flops, 14 EBRs; seed-1 7,306 LCs; 146.69 MHz fast and 32.99 MHz PSG.
- **Changed condition versus H026:** H026 rewrote one incremented relational
  predicate and regressed globally. H029 fuses an affine constant add and
  variable three-times operand into one proved signed margin; the complete
  producer/consumer cone is priced before production.
- **Change:** replace the right-side add and relational comparison with the sign
  of the proved 16-bit margin `nz_dp + 497 - nz_g3`; add permanent range and
  per-`g` transition-boundary coverage during measurement.
- **Result:** Yosys formal equivalence proves the enable bit. The permanent
  proof establishes the exact signed range -24,076..8,688 and checks 24,574
  domain endpoints/transition neighbours. The isolated registered cone changes
  from 50 LUT4s / 40 carries / one flop to 28 LUT4s / 40 carries / one flop.
  Whole-PSG mapping then fails the placement gate, so the full fidelity battery
  was not run and both production and permanent-proof edits were reverted.
- **Physical result:** canonical seed-1 mapping changed H027's 6,550 LUT4 /
  1,464 carry / 1,476 FF / 14 EBR / 7,306 placed LCs to 6,553 LUT4 / 1,442
  carry / 1,476 FF / 14 EBR / 7,327 placed LCs. Routed clocks changed from
  146.69 and 32.99 MHz to 132.57 and 29.82 MHz; both pass, but the candidate
  adds three LUT4s and 21 LCs despite saving 22 carries.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the current inequality; the affine margin is locally LUT-smaller and
  globally carry-smaller, but regresses placed area.
- **Repeat only if:** if rejected, retry only after `nz_g`/`nz_dp` bounds,
  kick constant, producer sharing, or mapper affine-comparison lowering changes.

## Hypothesis H030

- **ID:** H030.
- **Hypothesis:** the foreground trigger-length write saturates an input byte to
  32, so `di > 32` is exactly any high bit 7:6 or bit 5 with a non-zero low
  suffix. Directly decoding that prefix may remove the comparator carry chain
  from the six-bit register input.
- **Scope:** exhaustive/formal scratch proof and isolated registered synthesis
  of the complete saturation consumer. Production `rtl/psg_seq.sv`, a
  permanent hardware-forms proof, whole-PSG mapping, and the complete H027
  battery are conditional on a deterministic isolated mapped improvement. No
  trigger row/length semantics, address decode, state, schedule, memory, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H027 commit `9c4a1ac`: 6,550 LUT4s, 1,464 carries,
  1,476 flops, 14 EBRs; seed-1 7,306 LCs; 146.69 MHz fast and 32.99 MHz PSG.
- **Changed condition versus H024:** H024 changed two combinational row bounds
  feeding shared sequencer comparison/mux logic. H030 is one bus-write
  saturation feeding only a six-bit register, with no shared downstream bound;
  its complete registered cone is measured before production.
- **Change:** replace the byte-wide `di > 32` comparison with the exact high-bit
  and non-zero-suffix prefix; add permanent exhaustive coverage of all 256 input
  bytes.
- **Result:** Yosys formal equivalence proves all six registered result bits;
  exhaustive coverage proves every input byte. The isolated registered cone
  changes from three LUT4s / two carries / six flops to three LUT4s / zero
  carries / six flops. Full `tools/psg_hw_forms.py`, full and PREVIEW lint,
  `make test-psg` including 93 analysis tests, and the 59/59 frozen-render
  regression passed. `/4`, `/5`, and `/6` budget runs passed at 572/1,275 and
  5,757/7,654, 572/1,020 and 4,737/6,123, and 524/850 and 4,008/5,103
  sample/tick clocks, with zero lost writes or late flips. `make test-clocks`
  passed. All eight Celeste preview checks at 1,275 and 159 clocks/sample passed
  with 36/38 voiced windows, or 95%, for combined and masks 1/2/4. Synthetic
  and frozen-Celeste recovery passed with no coalesced, delayed, or dropped
  samples. Exact hardware and PREVIEW SFX-10 renders were active and `click-v1`
  found zero clicks. The five-frame Celeste smoke had 2,179/3,668 off-centre
  samples, range -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec
  validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changed H027's 6,550 LUT4 /
  1,464 carry / 1,476 FF / 14 EBR / 7,306 placed LCs to 6,546 LUT4 / 1,462
  carry / 1,476 FF / 14 EBR / 7,297 placed LCs. Routed clocks changed from
  146.69 and 32.99 MHz to 133.69 and 31.08 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The four-LUT4 and two-carry reductions are
  deterministic; the nine-LC improvement is below placement sensitivity and is
  not overclaimed.
- **Decision:** accepted. It makes the exact saturation interval explicit,
  improves both deterministic mapped resources, does not regress placement,
  preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** an alternative trigger-length form may be retried only
  after foreground length semantics, input/register width, write decode, or
  mapper comparison lowering changes.

## Hypothesis H031

- **ID:** H031.
- **Hypothesis:** the T_NL pattern-length test `acc[7:0] >= seq_q` is active in
  a state mutually exclusive with the EA2/EA4/EA5 row-bound test
  `ta_a + 1 >= ta_b`. Selecting T_NL's operands and a zero increment into that
  existing comparator should retire the separate eight-bit relation while
  preserving both contracts and making the time sharing explicit.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of both
  registered predicate consumers. Production `rtl/psg_seq.sv`, permanent
  hardware-forms coverage, whole-PSG mapping, and the complete H030 battery are
  conditional on a deterministic isolated mapped improvement. No row/length,
  trigger, multiply, state, schedule, memory, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H030 commit `a747493`: 6,546 LUT4s, 1,462 carries,
  1,476 flops, 14 EBRs; seed-1 7,297 LCs; 133.69 MHz fast and 31.08 MHz PSG.
- **Changed condition versus H026:** H026 changed the arithmetic spelling of
  the existing row-bound predicate and regressed globally. H031 retains that
  predicate exactly while folding a second, state-exclusive comparator into
  its operand/bias selection; the complete paired consumer cone is priced
  before production.
- **Change:** select T_NL's accumulator byte and pattern-length byte into the
  existing row-bound operands, select a zero rather than one increment in that
  state, and consume the shared predicate for `tnl_len_launch`. Add permanent
  exhaustive coverage of both selected relations over all byte pairs.
- **Result:** Yosys equivalence proves both registered consumer outputs. The
  permanent proof checks all 65,536 operand pairs. The isolated paired cone
  changes from 43 LUT4s / 24 carries / two flops to 43 LUT4s / 17 carries /
  two flops. Full hardware forms and full/PREVIEW lint passed. `make test-psg`
  including 93 analysis tests and the 59/59 frozen-render regression passed.
  `/4`, `/5`, and `/6` budget runs passed at 572/1,275 and 5,757/7,654,
  572/1,020 and 4,737/6,123, and 524/850 and 4,008/5,103 sample/tick clocks,
  with zero lost writes or late flips. `make test-clocks` passed. All eight
  Celeste preview checks at 1,275 and 159 clocks/sample passed with 36/38
  voiced windows, or 95%, for masks 7/1/2/4. Synthetic and frozen-Celeste
  recovery passed with no coalesced, delayed, or dropped samples. Exact
  hardware and PREVIEW SFX-10 renders were active and `click-v1` found zero
  clicks. The five-frame Celeste smoke had 2,179/3,668 off-centre samples,
  range -22,013..9,151, and 1,068 distinct levels. Strict OpenSpec validation
  and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changes H030's 6,546 LUT4 /
  1,462 carry / 1,476 FF / 14 EBR / 7,297 placed LCs to 6,545 LUT4 / 1,455
  carry / 1,476 FF / 14 EBR / 7,287 placed LCs. Routed clocks change from
  133.69 and 31.08 MHz to 150.53 and 31.35 MHz; both remain above their 112.50
  and 18.75-MHz constraints. The one-LUT4 and seven-carry reductions are
  deterministic; the ten-LC improvement is below placement sensitivity and is
  not overclaimed.
- **Decision:** accepted. It makes the mutually exclusive comparator sharing
  explicit, improves both deterministic mapped resources, does not regress
  placement, preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** an alternative shared comparator may be retried only
  after T_NL/EA state exclusivity, row/length comparison semantics, comparator
  consumers, or mapper mux/carry lowering changes.

## Hypothesis H032

- **ID:** H032.
- **Hypothesis:** sequencer audio reads select between a channel SFX record and
  a custom-instrument record, but the current cone applies the identical
  `rec_base()` transform to both six-bit record numbers before selecting their
  13-bit results. Selecting the record number first should expose one base
  transform, reduce the address mux/add cone, and simplify the source.
- **Scope:** formal scratch proof and isolated synthesis of the complete
  registered audio-RAM address consumer. Production `rtl/psg_seq.sv`,
  permanent hardware-forms coverage, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  address schedule, record layout, memory, EBR, state, comparator, R.84
  executor, or tolerance change.
- **Baseline:** accepted H031 commit `35fd3b4`: 6,545 LUT4s, 1,455 carries,
  1,476 flops, 14 EBRs; seed-1 7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H017/H019:** those rows shared arithmetic across
  different downstream contexts or changed state-memory ownership and became
  globally worse. H032 moves one selector across two identical pure
  `rec_base()` calls inside a single address consumer; it changes neither
  ownership nor arithmetic semantics and prices the full registered cone
  before production.
- **Change:** select the six-bit channel or instrument record number before one
  `rec_base()` call instead of selecting two 13-bit transformed bases; add a
  permanent exhaustive proof over all 1,024 channel/instrument/select tuples
  for the whole-design measurement.
- **Result:** Yosys equivalence proves all 13 registered address bits over the
  full input domain. The complete isolated address cone changes from 78 LUT4s
  / 16 carries / 13 flops to 77 LUT4s / nine carries / 13 flops. The
  deterministic isolated improvement admits the production measurement.
  Permanent exhaustive forms and full/PREVIEW lint pass. Whole-PSG mapping
  then fails both deterministic area and placement gates, so the full behavior
  battery is not run and both production and permanent-proof edits are
  reverted. Strict OpenSpec validation and `git diff --check` pass after the
  revert.
- **Physical result:** canonical seed-1 mapping changes H031's 6,545 LUT4 /
  1,455 carry / 1,476 FF / 14 EBR / 7,287 placed LCs to 6,577 LUT4 / 1,448
  carry / 1,476 FF / 14 EBR / 7,319 placed LCs. Routed clocks change from
  150.53 and 31.35 MHz to 131.72 and 30.39 MHz; both pass, but the candidate
  adds 32 LUT4s and 32 LCs despite saving seven carries.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the two precomputed bases; the record-first form is simpler and locally
  smaller but globally area-worse.
- **Repeat only if:** retry only after `rec_base()`, record-number widths,
  audio-RAM address schedule, or mapper mux/add factoring changes.

## Hypothesis H033

- **ID:** H033.
- **Hypothesis:** `aud_sl(ch, play)` chooses the foreground slot when it is
  active and the paired music slot otherwise. Therefore the subsequent
  `play[aud_sl(ch, play)]` CPU readback bit is exactly
  `play[ch] | play[{1'b1,ch}]`. Spelling that invariant directly may replace
  the dynamic eight-slot lookup with two four-slot selects and one OR.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered CPU readback consumer. Production `rtl/psg.sv`, a
  permanent hardware-forms proof, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  readback value, slot selection elsewhere, state, schedule, memory, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** docs-only H032 commit `925b0b5` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition:** no earlier continuation row rewrites the CPU readback
  activity bit. This is a local Boolean identity at one registered consumer,
  not state-memory ownership, address-base sharing, or comparator arithmetic.
- **Change:** replace both `play[aud_sl(ch, play)]` uses in a scratch copy of
  the complete registered CPU readback with `play[ch] | play[{1'b1,ch}]`.
- **Result:** exhaustive coverage proves the identity for all 1,024 channel /
  play-vector tuples. Yosys temporal induction proves all eight registered
  readback bits over the full input domain. Both complete consumers map to 85
  LUT4s and eight flops, so no production or permanent-proof file changes and
  no whole-PSG or behavior gate is warranted.
- **Decision:** rejected before production because it is mapping-identical.
  Keep the current helper-based spelling, which remains clearer at its other
  sequencer call sites.
- **Repeat only if:** retry only after `aud_sl()`, foreground/music pairing,
  CPU readback semantics, or mapper dynamic-index lowering changes.

## Hypothesis H034

- **ID:** H034.
- **Hypothesis:** `pat_rows` saturates a non-zero byte to 32 when `seq_q` is
  zero. Its `acc[7:0] < 32` relation is exactly the absence of any high bit
  7:5, so a direct prefix decode may remove the comparator carry chain from
  this single six-bit pattern-length producer.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered pattern-row consumer. Production `rtl/psg_seq.sv`, a
  permanent hardware-forms proof, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  pattern length, product, state, schedule, memory, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** docs-only H033 commit `9a73699` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H024/general comparator closure:** H024 rewrote
  nested bounds feeding the shared row/end comparator and regressed globally.
  H030 subsequently accepted the same prefix principle at one six-bit
  saturation consumer. H034 is a second standalone six-bit saturation feeding
  only the pattern-length product, so H030 supplies new physical evidence for
  this bounded retry.
- **Change:** replace the standalone `< 32` relation with `|acc[7:5]`, after
  proving the complete registered consumer and measuring it in isolation.
- **Result:** Yosys equivalence proves all six registered result bits. Permanent
  exhaustive coverage proves all 65,536 accumulator/sequence-byte pairs. The
  isolated registered consumer changes from five LUT4s / two carries / six
  flops to six LUT4s / zero carries / six flops. Full hardware forms and full
  and PREVIEW lint pass. Whole-PSG mapping then fails both deterministic area
  and placement gates, so the complete behavior battery is not run and the
  production and permanent-proof edits are reverted. Strict OpenSpec and diff
  checks pass after the revert.
- **Physical result:** canonical seed-1 mapping changes H031's 6,545 LUT4 /
  1,455 carry / 1,476 FF / 14 EBR / 7,287 placed LCs to 6,560 LUT4 / 1,459
  carry / 1,476 FF / 14 EBR / 7,307 placed LCs. Routed clocks are 150.53 and
  31.34 MHz and pass, but the candidate adds 15 LUT4s, four carries, and 20
  placed LCs.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the relational spelling; the exact prefix is globally area-worse.
- **Repeat only if:** retry only after pattern-length semantics,
  `acc` width, product consumer, or mapper saturation lowering changes.

## Hypothesis H035

- **ID:** H035.
- **Hypothesis:** four exact detune corrections test whether the low two, six,
  seven, or eight bits of `dp13` are non-zero. The current independent
  reductions are strictly nested. Naming one monotone suffix chain may let the
  iCE40 mapper share its lower Boolean cones and simplify the source contract.
- **Scope:** formal scratch proof and isolated synthesis of the complete
  registered suffix/ceiling consumer. Production `rtl/psg_wave.sv`, permanent
  hardware-forms coverage, whole-PSG mapping, and the complete H031 battery are
  conditional on a deterministic isolated mapped improvement. No coefficient,
  quotient, rounding, wave/mode selection, state, schedule, memory, EBR, R.84
  executor, or tolerance change.
- **Baseline:** docs-only H034 commit `b41aee0` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H025 and the closed prefix family:** H025 shared
  two repeated full additions that Yosys already factored. H035 instead exposes
  four strictly nested Boolean reductions whose distinct outputs are consumed
  together by the same detune service. It changes no comparison or saturation
  predicate.
- **Change:** define `nz2`, extend it through bits 5, 6, and 7, then consume the
  four named suffix predicates in place of the independent reductions.
- **Result:** Yosys equivalence proves all 22 registered result bits. The
  complete current and candidate consumers both map to 24 LUT4s, 18 carries,
  and 22 flops, so no production or permanent-proof file changes and no whole-
  PSG or behavior gate is warranted.
- **Decision:** rejected before production because the explicit sharing is
  mapping-identical. Keep the independent expressions, which state each
  ceiling formula directly.
- **Repeat only if:** retry only after detune correction widths,
  suffix consumers, coefficient forms, or mapper multi-output factoring changes.

## Hypothesis H036

- **ID:** H036.
- **Hypothesis:** the tilt `/7` and `/15` quotient terms are produced in
  mutually exclusive `tilt_hi` modes, registered on the same edge, and selected
  only after that boundary. Selecting `{0,t_h7}` or `t_h15` before one 11-bit
  register should remove ten flops and make the actual lifetime explicit.
- **Scope:** formal/exhaustive scratch proof and isolated synthesis of the
  complete registered quotient consumer. Production `rtl/psg_wave.sv`, a
  permanent hardware-forms proof, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  quotient value, divisor, reciprocal EBR, pipeline edge, waveform result,
  state schedule, R.84 executor, or tolerance change.
- **Baseline:** docs-only H035 commit `790c2a6` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus R.40--R.42:** those rows aliased registers across
  unrelated operation families and lost their flop savings to D-input/fanout
  entanglement. H036 collapses two branches of one waveform calculation under
  the exact selector already registered beside them, with one downstream
  consumer and no cross-family payload.
- **Change:** select `t_h15` or zero-extended `t_h7` before one 11-bit pipeline
  register, then feed that register directly to the non-organ reconstruction.
- **Result:** a reset-constrained three-step Yosys SAT miter proves the complete
  registered consumer. Exhaustive permanent coverage proves all 4,194,304 raw
  quotient/mode tuples. The isolated cone changes from 27 LUT4s / 30 flops to
  22 LUT4s / 20 flops. Full hardware forms and full/PREVIEW lint pass. Whole-
  PSG mapping then fails the deterministic area gate, so the complete behavior
  battery is not run and the production/permanent-proof edits are reverted.
  Strict OpenSpec and diff checks pass after the revert.
- **Physical result:** canonical mapping changes H031's 6,545 LUT4 / 1,455
  carry / 1,476 FF / 14 EBR to 6,599 LUT4 / 1,455 carry / 1,483 FF / 14 EBR.
  Seed-1 router2 remains at two overused wires through iteration 14,424 and is
  stopped after the mapped gate has already failed; no placement or timing
  result is claimed.
- **Decision:** rejected and reverted. Keep the parallel mode-specific
  registers; preselection makes the global D-input/fanout partition worse.
- **Repeat only if:** retry only after tilt quotient widths,
  pipeline placement, mode selection, or mapper flop packing changes.

## Hypothesis H037

- **ID:** H037.
- **Hypothesis:** in `/7` mode, `t_h7 = t_pre >> 9` is at most 335 and therefore
  needs nine bits. Its tenth bit is reachable only in `/15` mode, when the
  parallel `t_h15_r` branch is selected instead. Narrowing only `t_h7` and
  `t_h7_r` should remove one flop without H036's pre-register mux/fanout cost.
- **Scope:** exhaustive source-domain proof and isolated synthesis of the
  complete registered quotient consumer. Production `rtl/psg_wave.sv`, a
  permanent hardware-forms bound, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  quotient value in its live mode, divisor, reciprocal EBR, pipeline edge,
  waveform result, schedule, R.84 executor, or tolerance change.
- **Baseline:** docs-only H036 commit `b131219` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H014 and H036:** H014's globally unreachable
  detune-correction bit was already pruned by Yosys. H037's bit is reachable in
  the shared combinational source but dead only under the exact registered
  `/7` selector, so the current ten-bit flop remains. Unlike H036, this keeps
  both mode-specific registers and introduces no new D-input mux.
- **Change:** narrow `t_h7` and `t_h7_r` from ten to nine bits, zero-extending
  by two bits at the existing post-register selector.
- **Result:** a reset-constrained three-step Yosys SAT miter proves the complete
  upstream arithmetic and registered consumer for every 16-bit `tramp` and
  both modes. The full input domain also bounds `/7` mode at 383, while the
  true waveform domain peaks at 335. Both complete consumers map identically
  to 78 LUT4s, 45 carries, and 12 flops, so no production/permanent-proof edit
  and no whole-PSG or behavior gate is warranted.
- **Decision:** rejected before production because Yosys already removes the
  conditionally dead stored bit. Keep the current width, which mirrors the
  common `t_pre` slice directly.
- **Repeat only if:** retry only after the `/7` numerator bound,
  mode correlation, pipeline placement, or mapper flop packing changes.

## Hypothesis H038

- **ID:** H038.
- **Hypothesis:** boosted oscillator gain is
  `floor(3*floor(5*a/4)/2)`. It equals `floor(15*a/8)` except residues 3, 6,
  and 7 are one lower; equivalently, `2*a - floor(a/8) - inc(a[2:0])`, where
  `inc` is 0, 1, or 2. This may replace two 13-bit adders with one 13-bit
  subtract and one narrow correction while documenting the nested rounding.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered gain consumer. Production `rtl/psg_walk.sv`, permanent
  hardware-forms coverage, whole-PSG mapping, and the complete H031 battery are
  conditional on a deterministic isolated mapped improvement. No amplitude,
  detune mode, wavetable selection, multiply request, state, schedule, R.84
  executor, or tolerance change.
- **Baseline:** docs-only H037 commit `8971069` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H017:** H017 shared live/old gain arithmetic across
  different downstream contexts and regressed globally. H038 changes only the
  internal arithmetic shape of the existing live boosted-gain consumer,
  retires its intermediate, and adds no context selector or shared lifetime.
- **Change:** replace the boosted branch's two rounded additions with
  `2*a - (a>>3) - inc`, where the two-bit increment is one for residues
  1/2/4/5, two for 3/6/7, and zero for residue 0.
- **Result:** Yosys equivalence proves all 13 registered result bits over the
  full input domain. The complete registered consumer changes from 26 LUT4s /
  24 carries / 13 flops to 54 LUT4s / 24 carries / 13 flops, so no production
  or permanent-proof file changes and no whole-PSG or behavior gate is
  warranted.
- **Decision:** rejected before production. Keep the nested shift-add form;
  the exact residue correction more than doubles its LUT cost.
- **Repeat only if:** retry only after gain ladder semantics,
  amplitude width, boost predicate, or mapper subtract lowering changes.

## Hypothesis H039

- **ID:** H039.
- **Hypothesis:** `rec_base(n) = 256 + 64*n + 4*n`, and every term is divisible
  by four. Factoring that alignment gives `(64 + 16*n + n) << 2`, so one
  11-bit adder can replace the visible 13-bit address additions while making
  the 68-byte record stride explicit.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered base transform. Production `rtl/psg_common.svh`,
  permanent hardware-forms coverage, whole-PSG mapping, and the complete H031
  battery are conditional on a deterministic isolated mapped improvement. No
  record number, layout, call placement, selector, address schedule, memory,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** docs-only H038 commit `04c9b76` retains accepted H031 RTL and
  physical result: 6,545 LUT4s, 1,455 carries, 1,476 flops, 14 EBRs; seed-1
  7,287 LCs; 150.53 MHz fast and 31.35 MHz PSG.
- **Changed condition versus H032:** H032 moved the channel/instrument selector
  across two `rec_base()` calls and regressed globally. H039 leaves those calls
  and the selector untouched; it only factors the common low zeros within each
  pure transform, reducing the arithmetic width before measuring one complete
  registered transform.
- **Change:** compute the aligned word address as `64 + 16*n + n` in 11 bits,
  then append two zero address bits; retain every call, selector, offset, and
  consumer. Add all 64 record numbers to the permanent hardware-forms proof.
- **Result:** Yosys equivalence proves all 13 registered address bits. The
  permanent proof checks all 64 record numbers. The isolated registered
  transform changes from six LUT4s / six carries / 12 flops to six LUT4s / six
  carries / 11 flops. Full hardware forms and full/PREVIEW lint passed.
  `make test-psg`, including 93 analysis tests, and the 59/59 exact frozen-
  render regression passed. Correctly parameterized `/4`, `/5`, and `/6`
  budget runs passed at 572/1,275 and 5,757/7,654, 572/1,020 and 4,737/6,123,
  and 524/850 and 4,008/5,103 sample/tick clocks, with zero lost writes or late
  flips. `make test-clocks` passed. All eight Celeste preview checks at 1,275
  and 159 clocks/sample passed with 36/38 voiced windows, or 95%, for masks
  7/1/2/4. Synthetic and reconstructed-Celeste recovery passed with no
  coalesced, delayed, or dropped samples. Exact hardware and PREVIEW SFX-10
  renders were active and `click-v1` found zero clicks. The five-frame Celeste
  smoke had 2,179/3,668 off-centre samples, range -22,013..9,151, and 1,068
  distinct levels. Strict OpenSpec validation and `git diff --check` passed.
- **Physical result:** canonical seed-1 mapping changes H031's 6,545 LUT4 /
  1,455 carry / 1,476 FF / 14 EBR / 7,287 placed LCs to 6,540 LUT4 / 1,456
  carry / 1,476 FF / 14 EBR / 7,284 LCs. Routed clocks change from 150.53 and
  31.35 MHz to 142.57 and 29.18 MHz; both remain above their 112.50 and
  18.75-MHz constraints. The five-LUT4 reduction is deterministic; the added
  carry is explicit, and the three-LC improvement is below placement
  sensitivity and is not overclaimed.
- **Decision:** accepted. It exposes the address alignment and record stride,
  improves a deterministic mapped resource, does not regress placement,
  preserves every fidelity gate, and retains 14 EBRs.
- **Repeat only if:** an alternative aligned record-base form may be retried
  only after record stride/base, record-number width, call contexts, or mapper
  aligned-add lowering changes.

## Hypothesis H040

- **ID:** H040.
- **Hypothesis:** the organ half-cycle ramp ignores `wx[15]` and truncates the
  16-bit negation of `{wx[14], wx[13:0]}` to 15 bits. The exact fold is the
  15-bit sum `{1'b0, wx[13:0] ^ {14{wx[14]}}} + wx[14]`; making the 14-bit
  conditional complement and carry-in explicit may prevent a wider subtract
  while exposing the triangular-ramp contract.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered organ reciprocal-address inputs. Production
  `rtl/psg_wave.sv`, permanent hardware-forms coverage, whole-PSG mapping, and
  the complete H039 battery are conditional on a deterministic isolated mapped
  improvement. No waveform values, reciprocal table, pipeline edge, schedule,
  state, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af`: 6,540 LUT4s, 1,456 carries,
  1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57 MHz fast and 29.18 MHz PSG.
- **Changed condition versus H011:** H011 replaced `16'hffff - wx` with its
  mapper-canonical bitwise complement. H040 instead removes an ignored source
  bit from a modulo-15-bit negation while preserving the carry-out required at
  the exact half-cycle boundary, and prices the complete registered organ
  consumer before production.
- **Change:** replace the truncated conditional 16-bit negation with the exact
  15-bit sum of a 14-bit conditional complement and the half-cycle bit; add
  permanent exhaustive coverage during the whole-design measurement.
- **Result:** Yosys equivalence proves all 55 internal and registered consumer
  bits. The isolated complete registered organ-address cone changes from 54
  LUT4s / 27 carries / 23 flops to 41 LUT4s / 28 carries / 23 flops. Full
  hardware forms and full/PREVIEW lint pass. Whole-PSG mapping then fails both
  deterministic mapped-resource and placement gates, so the complete fidelity
  battery is correctly skipped and both production and permanent-proof edits
  are reverted.
- **Physical result:** canonical seed-1 mapping changes H039's 6,540 LUT4 /
  1,456 carry / 1,476 FF / 14 EBR / 7,284 placed LCs to 6,553 LUT4 / 1,461
  carry / 1,476 FF / 14 EBR / 7,302 LCs. Routed clocks remain above constraint
  at 123.09 MHz fast and 31.13 MHz PSG, but the 13-LUT4, five-carry, and 18-LC
  regressions reject the candidate.
- **Decision:** rejected and reverted after the whole-design physical gate.
  Keep the current truncated negation; the explicit exact fold is much smaller
  locally but globally worse in every area metric.
- **Repeat only if:** retry only after organ ramp width, reciprocal folding,
  pipeline consumers, or mapper negation lowering changes.

## Hypothesis H041

- **ID:** H041.
- **Hypothesis:** both music-control branches test `fade_len >= 8`, which is
  exactly `|fade_len[7:3]` for an unsigned byte. One named prefix predicate may
  remove relational lowering and duplicated decode while making the minimum
  non-immediate fade duration explicit.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered fade-control consumer. Production `rtl/psg_seq.sv`,
  permanent hardware-forms coverage, whole-PSG mapping, and the complete H039
  battery are conditional on a deterministic isolated mapped improvement. No
  fade semantics, accumulator arithmetic, music state, schedule, memory, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af` plus docs-only H040 `e108538`:
  6,540 LUT4s, 1,456 carries, 1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57
  MHz fast and 29.18 MHz PSG.
- **Changed condition versus H024/H030/H034:** those rows changed saturation or
  row-bound comparisons with arithmetic consumers. H041 is one shared Boolean
  eligibility predicate used by two mutually exclusive fade-control branches,
  and prices their complete registered outputs before production.
- **Change:** replace both relations with one named `|fade_len[7:3]` predicate.
  The scratch pair models every held register as a shared explicit prior-state
  input, then compares the unconditional next-state outputs.
- **Result:** Yosys proves all 42 next-state bits for arbitrary inputs and
  arbitrary prior state; exhaustive hardware-forms evaluation also proves the
  Boolean identity for all 256 unsigned-byte values. Isolated `synth_ice40`
  changes 15 LUT4 / four carry / 18 FF to 17 LUT4 / zero carry / 18 FF.
  Canonical whole-PSG mapping changes H039's 6,540 LUT4 / 1,456 carry / 1,476
  FF / 14 EBR / 7,284 placed LCs to 6,551 LUT4 / 1,451 carry / 1,476 FF / 14
  EBR / 7,293 LCs. Routed clocks pass at 133.69 MHz fast and 31.54 MHz PSG.
- **Decision:** rejected and reverted after the whole-design physical gate.
  The five-carry saving does not offset 11 added LUT4s and nine placed LCs, so
  no full fidelity battery was run and no production or permanent-proof edit
  remains.
- **Repeat only if:** if rejected, retry only after fade-length semantics,
  register width, control consumers, or mapper constant-bound lowering changes.

## Hypothesis H042

- **ID:** H042.
- **Hypothesis:** the triangle detune-1 correction predicate
  `r[1:0] != 0 && r[7:6] >= r[1:0]` is a complete four-input truth table. Its
  exact nested Boolean form may remove the two-bit relational lowering while
  preserving the existing `floor(193*r/256)` arithmetic.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered eight-bit residue consumer. Production
  `rtl/psg_wave.sv`, permanent `dq` forms coverage, whole-PSG mapping, and the
  complete H039 battery are conditional on a deterministic isolated mapped
  improvement. No coefficient, quotient split, waveform value, pipeline edge,
  schedule, memory, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af` plus docs-only H040/H041:
  6,540 LUT4s, 1,456 carries, 1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57
  MHz fast and 29.18 MHz PSG.
- **Changed condition versus H002:** H002 replaced the full phaser
  `ceil(3*r/128)` remainder arithmetic with four seven-bit intervals. H042
  changes only an existing one-bit correction inside the separate triangle
  `floor(193*r/256)` remainder, over two independent two-bit fields.
- **Change:** replace the gated two-bit relation with the exact nested Boolean
  truth table for residue values zero, one, two, and three.
- **Result:** exhaustive enumeration proves both the correction bit and the
  complete `floor(193*r/256)` split for all 256 residues; Yosys proves all ten
  exposed correction/result bits. Isolated `synth_ice40` changes 22 LUT4 / six
  carry / eight FF to 21 LUT4 / six carry / eight FF. Canonical whole-PSG
  mapping changes H039's 6,540 LUT4 / 1,456 carry / 1,476 FF / 14 EBR / 7,284
  placed LCs to 6,564 LUT4 / 1,460 carry / 1,476 FF / 14 EBR / 7,320 LCs.
  Routed clocks pass narrowly at 112.82 MHz fast and 29.04 MHz PSG.
- **Decision:** rejected and reverted after the whole-design physical gate.
  The one-LUT4 isolated saving becomes a 24-LUT4, four-carry, and 36-LC global
  regression, so no full fidelity battery was run and no production or
  permanent-proof edit remains.
- **Repeat only if:** if rejected, retry only after the triangle coefficient,
  residue split, correction consumer, or mapper small-comparison lowering
  changes.

## Hypothesis H043

- **ID:** H043.
- **Hypothesis:** EA5 classifies the foreground length as nonzero and equal to
  one in its transition, then repeats the same classification in the memory
  write enable. For an active six-bit length, `|length[5:1]` exactly means the
  row may advance; named active/advance predicates may share the two consumers
  and simplify the stop/advance contract.
- **Scope:** exhaustive/formal scratch proof and isolated synthesis of the
  complete registered EA5 transition/write consumer. Production
  `rtl/psg_seq.sv`, permanent `seq` forms coverage, whole-PSG mapping, and the
  complete H039 battery are conditional on a deterministic isolated mapped
  improvement. No length, row, release, stop, state-memory value/address,
  schedule, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af` plus docs-only H040--H042:
  6,540 LUT4s, 1,456 carries, 1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57
  MHz fast and 29.18 MHz PSG.
- **Changed condition versus H031/H041:** H031 time-shared two arithmetic
  comparisons in mutually exclusive states, while H041 replaced a fade
  threshold spelling. H043 factors one exact zero/one classification already
  consumed twice in the same EA5 state, including its memory write enable.
- **Change:** scratch-only named active and advance predicates; no production
  file changed.
- **Result:** exhaustive enumeration proves active, stop, advance, and write-
  enable behavior for all 4,096 bank/length/row tuples; Yosys proves all nine
  exposed result bits. Isolated `synth_ice40` maps both complete registered
  consumers identically at 13 LUT4 / four carry / nine FF.
- **Decision:** rejected before production RTL because Yosys already performs
  the intended zero/one classification sharing; the candidate only changes
  source spelling.
- **Repeat only if:** if rejected, retry only after foreground-length semantics,
  EA5 transition/write consumers, row terminal value, or mapper equality
  sharing changes.

## Hypothesis H044

- **ID:** H044.
- **Hypothesis:** each persisted full-mode crossfade counter is initialized to
  zero and updated only by restart-to-zero or increment while not 64, so its
  live domain is exactly 0..64. Within that domain, bit six is the terminal
  predicate and may replace every repeated seven-bit equality/non-equality
  decode in blend selection, multiplier issue, and counter update.
- **Scope:** inductive/exhaustive scratch proof and isolated synthesis of the
  complete registered counter/terminal consumer. Production `rtl/psg_walk.sv`,
  permanent `blend` forms coverage, whole-PSG mapping, and the complete H039
  battery are conditional on a deterministic isolated mapped improvement. No
  blend value, duration, multiplier operand, oscillator record, schedule,
  memory layout, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H039 commit `47a32af` plus docs-only H040--H043:
  6,540 LUT4s, 1,456 carries, 1,476 flops, 14 EBRs; seed-1 7,284 LCs; 142.57
  MHz fast and 29.18 MHz PSG.
- **Changed condition versus H008/H041:** those rows rewrote unconstrained
  equality/range inputs and Yosys could retain or reconstruct their full
  decodes. H044 uses a persistent-state invariant to remove six provably dead
  counter states from all terminal consumers, with the initialized memory and
  update recurrence included in the proof.
- **Change:** add `blend_done = bl_cnt[6]` and use it at all five full-mode
  terminal consumers: final blend selection, product issue, counter update,
  early-consume assertion, and busy assertion. Add the initialized/restart/
  saturating recurrence proof to the permanent hardware forms.
- **Result:** exhaustive fixed-point enumeration reaches exactly 0..64 and
  proves bit six iff terminal; constrained Yosys SAT proves the complete
  registered consumer equivalent. Isolated `synth_ice40` changes 28 to 25
  LUT4s with five carries and 26 flops unchanged. Permanent hardware forms,
  full and PREVIEW lint, `make test-psg`, and all 59 frozen renders pass
  byte-exactly. Correctly parameterized `/4`, `/5`, and `/6` regressions pass
  at 572/1,275, 572/1,020, and 524/850 sample clocks and 5,757/7,654,
  4,737/6,123, and 4,008/5,103 tick clocks. All eight preview checks at
  28,125,000 and 3,506,580 Hz pass at 95% for masks 7/1/2/4; synthetic and
  Celeste recovery pass. Exact hardware/PREVIEW SFX-10 renders report zero
  `click-v1` clicks and are byte-identical to H039. The five-frame Celeste
  smoke reports 2,179/3,668 active samples, range -22,013..9,151, and 1,068
  distinct levels. `make test-clocks` passes.
- **Physical result:** canonical seed-1 mapping changes 6,540 LUT4 / 1,456
  carry / 1,476 FF / 14 EBR / 7,284 placed LCs to 6,531 LUT4 / 1,459 carry /
  1,476 FF / 14 EBR / 7,280 placed LCs. Routed clocks change from 142.57 and
  29.18 MHz to 148.77 and 30.25 MHz. The nine-LUT4 reduction is deterministic;
  the four-LC improvement is below placement sensitivity and is not
  overclaimed.
- **Decision:** accepted. It makes the bounded counter contract explicit,
  improves a deterministic mapped resource, does not regress placed LCs,
  preserves every fidelity/timing gate, and retains 14 EBRs.
- **Cross-lineage adjudication:** H044 is accepted only on its H039-derived
  lineage and is not a composing optimization claim. Applying the same RTL and
  permanent proof to clean D004 commit `34340b7` changes 6,519 to 6,546 LUT4s,
  keeps 1,441 carries and 1,460 flops, changes unpackable flops 504 to 503 and
  the LC floor 7,023 to 7,049, and routes at 7,298 rather than 7,273 LCs.
  Timing still passes at 138.97/30.70 MHz. Reverting and forcing a clean build
  exactly restores D004 at 6,519 LUT4 / 1,441 carry / 1,460 FF / 504
  unpackable / 14 EBR / floor 7,023 / 7,273 LCs / 135.46/31.52 MHz. No H044
  residue or commit remains on that lineage.
- **Repeat only if:** if rejected, retry only after crossfade duration, counter
  persistence/update, blend consumers, or mapper terminal-decode lowering
  changes.

## Hypothesis H045

- **ID:** H045.
- **Hypothesis:** `fdec()` emits three base-3 digits and therefore each filter
  mode is always 0, 1, or 2. The zero-initialized record store is written only
  from those digits or their maximum, so the invariant persists through
  `w_bf_det/rev/damp`. For trits `a,b`, `max(a,b)` is exactly `{a[1]|b[1],
  !(a[1]|b[1]) && (a[0]|b[0])}`. Using one named function for the three
  instrument/base filter merges should remove relational compare/mux lowering
  and make the base-3 contract explicit.
- **Scope:** exhaustive trit/source-closure proof and isolated synthesis of all
  three registered max consumers. Production `rtl/psg_seq.sv`, permanent
  hardware forms, whole-PSG mapping, and the complete H044 battery are
  conditional on a deterministic isolated mapped improvement. No filter value,
  instrument precedence, publication format, state address, schedule, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H044 commit `088471f`: 6,531 LUT4s, 1,459 carries,
  1,476 flops, 14 EBRs; seed-1 7,280 LCs; 148.77 MHz fast and 30.25 MHz PSG.
- **Changed condition versus H042:** H042 replaced one already compact gated
  two-bit relation and its isolated one-LUT4 win regressed globally. H045
  removes three complete relation-plus-result-mux consumers under a persistent,
  source-closed trit invariant, rather than respelling one predicate.
- **Change:** scratch-only OR-derived trit maximum and complete three-consumer
  registered synthesis probe; no production or permanent-proof file changed.
- **Result:** exhaustive enumeration proves all 32 `fdec()` outputs contain
  only digits 0..2, proves the OR-derived maximum equal to `max(a,b)` for all
  nine input pairs, and proves closure of the result. Constrained Yosys SAT
  proves all six registered result bits over three independent valid-trit
  pairs. Isolated `synth_ice40` maps both the relational and OR-derived forms
  identically at six LUT4s / six flops / zero carries.
- **Decision:** rejected before production because the source identity has no
  isolated physical result. Keep the relational maxima; no whole-PSG or
  behavior gate is warranted.
- **Repeat only if:** if rejected, retry only after filter-code radix/domain,
  base/instrument merge semantics, record-store provenance, or mapper small-
  relation lowering changes.

## Hypothesis H046

- **ID:** H046.
- **Hypothesis:** the three published effect-class flags redundantly decode
  raw current and instrument effects after `e_fx` has already applied their
  exact precedence. Exhaustively, the noise flag is `e_fx == 3`, the buzz
  flag is `(!w_ins_on || !w_ins_wt) && e_fx in {0,4,5}`, and the damp flag is
  `ins_use && fx_dfl && e_fx in {0,4,5}`. Naming the shared normalized class
  should remove duplicated raw-effect comparisons while simplifying the
  publication contract.
- **Scope:** all 256 combinations of instrument-on, wavetable, current effect,
  and instrument effect; constrained formal equivalence; isolated registered
  synthesis of the complete three-flag consumer; then, only after an isolated
  deterministic win, production `rtl/psg_seq.sv`, permanent hardware forms,
  whole-PSG mapping, and the complete H044 battery. No precedence, sounding
  word layout, effect arithmetic, state, schedule, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** accepted H044 commit `088471f`: 6,531 LUT4s, 1,459 carries,
  1,476 flops, 14 EBRs; seed-1 7,280 LCs; 148.77 MHz fast and 30.25 MHz PSG.
- **Changed condition versus H042/H045:** those rows respelled already-compact
  bounded relations. H046 removes multiple raw-effect decodes by reusing the
  already-live precedence result consumed throughout the sequencer.
- **Change:** replace the repeated raw current/instrument effect decodes with
  one shared `e_filter` predicate and the normalized `e_fx` identities; add
  the complete exhaustive identity to the permanent hardware forms.
- **Result:** exhaustive Python enumeration and unconstrained Yosys SAT prove
  all six exposed normalized-effect/result bits for all 256 input tuples.
  Isolated registered `synth_ice40` improves from 14 to 11 LUT4s with six
  flops and zero carries unchanged. Whole-PSG mapping instead changes 6,531 to
  6,558 LUT4s, keeps 1,459 carries and 1,476 flops, reduces unpackable flops
  521 to 518, raises the LC floor 7,052 to 7,076, and routes at 7,308 rather
  than 7,280 LCs. Both clocks pass at 121.60/31.45 MHz. Reverting and forcing
  a clean synthesis exactly restores H044 at 6,531 LUT4 / 1,459 carry / 1,476
  FF / 521 unpackable / 14 EBR / floor 7,052 / 7,280 LCs / 148.77/30.25 MHz.
- **Decision:** rejected and reverted because the global decode/fanout remap
  overwhelms the isolated saving and regresses both deterministic LUT4s and
  placed LCs. No fidelity gate is warranted after the physical failure.
- **Repeat only if:** if rejected, retry only after current/instrument effect
  precedence, wavetable gating, publication bit semantics, or mapper sharing
  across the `e_fx` cone changes.

## Hypothesis H047

- **ID:** H047.
- **Hypothesis:** waveform output scaling currently selects among three
  constant `tzs(z_prim, k)` networks plus an unshifted arm. The exact shift is
  `3/2` for triangle secondary/primary, `1` for every other secondary, and
  `0` otherwise. Selecting this two-bit `k` first and invoking `tzs` once,
  including its exact `k=0` identity, should share the bias/add/shift path and
  simplify the output contract.
- **Scope:** every signed 18-bit `z_prim` value and all four triangle/secondary
  contexts; unconstrained formal equivalence; isolated registered synthesis of
  the complete output consumer; then, only after an isolated deterministic
  win, production `rtl/psg_wave.sv`, permanent hardware forms, whole-PSG
  mapping, and the complete H044 battery. No waveform value, reciprocal,
  detune, pipeline register, schedule, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H044 commit `088471f`: 6,531 LUT4s, 1,459 carries,
  1,476 flops, 14 EBRs; seed-1 7,280 LCs; 148.77 MHz fast and 30.25 MHz PSG.
- **Changed condition versus the closed reciprocal/detune families:** H047
  leaves every waveform and increment expression intact and consolidates only
  the mutually exclusive final truncation-to-zero consumer after `z_prim`.
- **Change:** select `z_shift` from the triangle/secondary context and invoke
  `tzs(z_prim, z_shift)` once, including the exact zero-shift identity. Add the
  complete signed-18/context identity to the permanent hardware forms.
- **Result:** exhaustive comparison passes all 1,048,576 signed-18/context
  tuples, and unconstrained Yosys SAT proves the complete combinational result.
  Isolated registered synthesis changes 100 to 56 LUT4s and 51 to 18 carries,
  with 18 flops unchanged. Permanent hardware forms, full and PREVIEW lint,
  `make test-psg`, and all 59 frozen renders pass byte-exactly. Correctly
  parameterized `/4`, `/5`, and `/6` regressions pass at 572/1,275,
  572/1,020, and 524/850 sample clocks and 5,757/7,654, 4,737/6,123, and
  4,008/5,103 tick clocks. All eight preview checks at 28,125,000 and
  3,506,580 Hz pass 36/38 voiced windows for masks 7/1/2/4; synthetic and
  Celeste recovery pass. Exact hardware/PREVIEW SFX-10 renders report zero
  `click-v1` clicks and are byte-identical to H044. The five-frame Celeste
  smoke reports 2,179/3,668 active samples, range -22,013..9,151, and 1,068
  distinct levels. `make test-clocks` passes.
- **Physical result:** canonical seed-1 mapping changes H044's 6,531 LUT4 /
  1,459 carry / 1,476 FF / 14 EBR / 521 unpackable / 7,052-cell floor / 7,280
  routed LCs to 6,503 LUT4 / 1,426 carry / 1,476 FF / 14 EBR / 522 unpackable /
  7,025-cell floor / 7,251 routed LCs. Routed clocks change from 148.77 and
  30.25 MHz to 150.53 and 32.42 MHz. Independent direct-D004 adjudication is
  accepted as `a5052c1` atop `34340b7`: 6,519 to 6,517 LUT4s, 1,441 to 1,404
  carries, 1,460 flops unchanged, 504 to 503 unpackable flops, 7,023 to 7,020
  floor cells, and 7,273 to 7,259 routed LCs at 128.50/32.57 MHz. The D004
  placement delta is non-robust; the shared exact network and 37-carry saving
  are durable.
- **Decision:** accepted. It exposes one exact output-scale contract, improves
  deterministic mapped resources and the physical floor, reduces placed LCs,
  preserves every fidelity/timing gate, and retains 14 EBRs.
- **Repeat only if:** if rejected, retry only after waveform output-scale
  semantics, `tzs` lowering, `z_prim` width, or the final pipeline boundary
  changes.

## Hypothesis H048

- **ID:** H048.
- **Hypothesis:** the three wave-issue strobes are mutually exclusive schedule
  actions and describe four contexts: live primary, live secondary, old
  primary, and old secondary. Factoring them into independent `old` and
  `secondary` axes should replace the priority-shaped source selector with two
  orthogonal muxes before the unchanged first waveform-pipeline register.
- **Scope:** source-exact one-hot schedule audit; constrained formal equivalence
  for arbitrary phase, wave, alternate, and issue inputs; isolated registered
  synthesis of the complete first-stage selector; then, only after an isolated
  deterministic win, production `rtl/psg_wave.sv`, permanent proof, whole-PSG
  mapping, and the complete H047 battery. No waveform value, output scaling,
  reciprocal, pipeline register, action timing, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H047 commit `c1b4862`: 6,503 LUT4s, 1,426 carries,
  1,476 flops, 522 unpackable flops, 14 EBRs, 7,025-cell floor, seed-1 7,251
  LCs; 150.53 MHz fast and 32.42 MHz PSG.
- **Changed condition versus H017/R.83:** H017 shared post-multiply consumers
  across distant schedule destinations and regressed globally; R.83 replaced
  the complete waveform pipeline with a sequential service. H048 changes no
  arithmetic or destination: it only exposes the two Boolean axes already
  encoded by the four legal inputs to one existing register boundary.
- **Change:** scratch-only factorization of each issue context into independent
  old/live and primary/secondary axes; no production or permanent proof file
  changed.
- **Result:** the source-derived schedule proof passes all four legal hardware
  issue contexts, all 128 generated control words retain one-hot W1/W2/W3
  actions, and both PREVIEW contexts preserve the selector axes. Constrained
  Yosys SAT proves both combinational selectors equivalent for arbitrary phase,
  wave, alternate, and valid issue inputs. Isolated registered `synth_ice40`
  maps the current selector to 38 LUT4s, zero carries, and 21 flops, while the
  factored selector needs 54 LUT4s, zero carries, and 21 flops.
- **Decision:** rejected before production RTL. The exact factorization adds 16
  LUT4s in the complete registered cone, so it fails the deterministic isolated
  area gate; no whole-PSG or fidelity run is warranted.
- **Repeat only if:** if rejected, retry only after issue-strobe exclusivity,
  waveform-context ownership, first-stage register inputs, or mapper priority-
  mux lowering changes.

## Hypothesis H049

- **ID:** H049.
- **Hypothesis:** the square/pulse thresholds have high-five-bit values 16, 19,
  22, and 25. Their exact less-than relations are small nested prefix formulas;
  selecting those formulas directly should remove the comparator carry chain
  while preserving every phase and wave/alternate context.
- **Scope:** exhaustive and formal proof over all phase, wave, and alternate
  inputs; isolated registered synthesis of the complete signed constant-output
  consumer; then, only after a deterministic isolated win,
  `rtl/psg_wave.sv`, a permanent proof, whole-PSG mapping, and the complete
  H047 battery. No threshold, waveform amplitude, pipeline register, schedule,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H047 commit `c1b4862` plus H048 decision `dc28e97`:
  6,503 LUT4s, 1,426 carries, 1,476 flops, 522 unpackable flops, 14 EBRs,
  7,025-cell floor, seed-1 7,251 LCs; 150.53 MHz fast and 32.42 MHz PSG.
- **Changed condition versus H004:** H004 retained a relational comparison and
  only shortened its operands to the aligned high five bits; Yosys already made
  that reduction. H049 removes the relational operator and tests the complete
  exact truth table selected by wave and alternate mode.
- **Change:** replace the selected relational threshold with four exact nested
  prefix formulas; add the exhaustive permanent proof for measurement.
- **Result:** all 1,048,576 phase/wave/alternate tuples pass in both the scratch
  and permanent proof, and unconstrained Yosys SAT proves the complete signed
  constant output equivalent. Isolated registered synthesis changes five LUT4s,
  five carries, and two flops to seven LUT4s, zero carries, and two flops.
  Whole-PSG mapping changes H047's 6,503 LUT4 / 1,426 carry / 1,476 FF / 522
  unpackable / 14 EBR / 7,025-cell floor / 7,251 placed LCs to 6,529 LUT4 /
  1,418 carry / 1,476 FF / 520 unpackable / 14 EBR / 7,049-cell floor / 7,261
  placed LCs. Initial placed timing estimates pass at 149.37/32.78 MHz, but
  the route remained at two overused wires and was stopped after both mapped
  and placed area gates had already failed. Production RTL and the conditional
  permanent proof are reverted byte-for-byte.
- **Decision:** rejected after whole-PSG mapping and placement. Eight fewer
  carries do not offset 26 more LUT4s, 24 more floor cells, or ten more placed
  LCs; the second square/pulse-threshold variant closes this family.
- **Repeat only if:** if rejected, retry only after square/pulse thresholds,
  wave/alternate selection, comparator lowering, or the registered consumer
  changes.

## Hypothesis H050

- **ID:** H050.
- **Hypothesis:** the retained five-bit upload-page subtract is modulo
  `x - 17 == x + 15`: decrement the low nibble and toggle the high bit exactly
  when that nibble is nonzero. Spelling its five output bits directly should
  remove the remaining constant-adder carry chain while preserving the complete
  audio-RAM index.
- **Scope:** exhaustive and formal proof over every five-bit page and low-byte
  input; isolated registered synthesis of the complete 13-bit index consumer;
  then, only after a deterministic isolated win, `rtl/psg_aram.sv`, permanent
  proof, whole-PSG mapping, and the complete H047 battery. No upload window,
  write enable, address, memory, schedule, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H047 commit `c1b4862` plus decisions through H049 and
  D004 coordination `33be1c8`: 6,503 LUT4s, 1,426 carries, 1,476 flops, 522
  unpackable flops, 14 EBRs, 7,025-cell floor, seed-1 7,251 LCs; 150.53 MHz
  fast and 32.42 MHz PSG.
- **Changed condition versus H005:** H005 accepted the page-local five-bit
  subtract and window decode, but left the narrowed constant adder intact.
  H050 keeps that exact contract and removes only the modulo transform's carry
  representation; the accepted window decoder is unchanged.
- **Change:** variant 1 spells all five modulo output bits exactly over every
  page. Variant 2 uses the unchanged write-valid domain to reduce the fifth bit
  to `!page[4] && |page[1:0]`; both retain the same lower-nibble decrement.
- **Result:** exhaustive comparison and Yosys SAT prove variant 1 over all 8,192
  page/low-byte inputs and variant 2 over all 4,608 valid upload addresses.
  Isolated registered synthesis changes the current five LUT4 / three carry /
  13-flop index to six LUT4 / zero carry / 13 flops for variant 1 and five
  LUT4 / zero carry / 13 flops for variant 2. Whole-PSG variant 1 maps 6,523
  LUT4 / 1,423 carry / 1,476 FF / 519 unpackable / 14 EBR / 7,042-cell floor
  and routes in 7,266 LCs at 141.16/31.03 MHz. Variant 2 maps 6,520 LUT4 /
  1,423 carry / 1,476 FF / 521 unpackable / 14 EBR / 7,041-cell floor and
  routes in 7,265 LCs at 115.75/31.59 MHz. Against H047, even the local-optimum
  variant adds 17 LUT4s, 16 floor cells, and 14 placed LCs while saving only
  three carries. Production RTL and the conditional permanent proof are
  reverted byte-for-byte.
- **Decision:** both variants are rejected after the whole-PSG physical gate.
  The valid-domain fifth bit recovers the isolated LUT cost but not the global
  mapping/placement regression, so the upload-page transform family closes.
- **Repeat only if:** if rejected, retry only after upload base/window, page
  width, mapper constant-adder lowering, or the registered index consumer
  changes.

## Hypothesis H051

- **ID:** H051.
- **Hypothesis:** the detune service needs exactly five active iterations. The
  maximal-LFSR segment `6 -> 5 -> 2 -> 4 -> 1` preserves those five states,
  keeps zero idle and one terminal, and replaces the binary decrement with one
  XOR plus a shift. It should remove the countdown carry chain without changing
  arithmetic or request timing.
- **Scope:** exhaustive event/state proof including held, start, terminal-chain,
  and reset transitions; sequential formal equivalence of all public service
  signals and product values; isolated synthesis of the complete service; then,
  only after a deterministic win, `rtl/psg_dqsvc.sv`, permanent proof,
  whole-PSG mapping, and the complete H047 battery. No coefficient, product,
  request, result, schedule, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H047 commit `c1b4862` plus decisions through H050
  `abd4884`: 6,503 LUT4s, 1,426 carries, 1,476 flops, 522 unpackable flops,
  14 EBRs, 7,025-cell floor, seed-1 7,251 LCs; 150.53 MHz fast and 32.42 MHz
  PSG.
- **Changed condition versus H006/R.68/R.69:** H006 changed only the loaded
  multiplier latency value and regressed locally. R.68/R.69 partially recoded
  global schedule actions. H051 keeps the detune service's five clocks and all
  external actions fixed; only its private six-state iteration register changes
  representation.
- **Change:** load state six and advance the exact maximal-LFSR segment
  `6 -> 5 -> 2 -> 4 -> 1`; retain zero as idle and one as terminal. Decode
  readiness from the high two bits and add the state identity to the permanent
  hardware forms.
- **Result:** exhaustive transition proof covers every legal idle, active,
  terminal-chain, held, and reset case, and constrained Yosys SAT proves the
  state bijection, public busy/done/ready signals, next product state, and
  result recurrence. The complete detune service changes 120 LUT4 / 29 carry /
  28 FF to 120 LUT4 / 28 carry / 28 FF in isolation. `make test-psg-dq` passes
  524,288 arithmetic cases plus 57,344 exhaustive and chained transactions.
  Permanent hardware forms, full and PREVIEW lint, `make test-psg`, and all 59
  frozen renders pass byte-exactly. Correctly parameterized `/4`, `/5`, and
  `/6` regressions pass at 572/1,275, 572/1,020, and 524/850 sample clocks and
  5,757/7,654, 4,737/6,123, and 4,008/5,103 tick clocks, all with zero lost
  writes or late flips. All eight preview checks pass 36/38 voiced windows for
  masks 7/1/2/4 at both clocks; synthetic and Celeste recovery pass with no
  coalesced, delayed, or dropped samples. Exact hardware/PREVIEW SFX-10 renders
  are byte-identical to H047 and report zero `click-v1` clicks. The five-frame
  Celeste smoke again reports 2,179/3,668 active samples, range
  -22,013..9,151, and 1,068 distinct levels. `make test-clocks` passes.
- **Physical result:** canonical seed-1 mapping changes H047's 6,503 LUT4 /
  1,426 carry / 1,476 FF / 522 unpackable / 14 EBR / 7,025-cell floor / 7,251
  routed LCs to 6,506 LUT4 / 1,421 carry / 1,476 FF / 522 unpackable / 14 EBR /
  7,028-cell floor / 7,247 routed LCs. Routed clocks are 146.82 and 31.75 MHz
  against 112.50 and 18.75 MHz constraints. The five-carry reduction is
  deterministic; the four-LC improvement is below placement sensitivity and
  is not overclaimed.
- **Decision:** accepted. The private state contract is exact and simpler,
  removes mapped carries, preserves all behavioral and timing gates, and does
  not regress seed-1 placement despite the explicit three-LUT/floor trade.
- **Repeat only if:** if rejected, retry only after detune-service latency,
  terminal chaining, iteration arithmetic, or mapper sequential lowering
  changes.

## Hypothesis H052

- **ID:** H052.
- **Hypothesis:** full-mode fold finality need not be a separate `ffin` bit.
  The existing three-bit `fsel` has unused state five, whose operand-mux
  behavior is already the same as root state three. Encoding only the final
  root reduction as state five should preserve every reduction operand,
  destination, microstep, and `dry_valid` clock while removing one control
  flop and its update cone.
- **Scope:** exhaustive legal fold-controller transition proof, constrained
  formal equivalence of externally visible fold actions, isolated synthesis of
  the complete selector/controller consumer, then, only after a deterministic
  win, `rtl/psg_walk.sv`, permanent hardware forms, whole-PSG mapping, and the
  complete H051 battery. No arithmetic, visit/schedule cadence, `fmc`, `fpend`,
  EBR, interface, R.84 executor, or tolerance change.
- **Baseline:** accepted H051 commit `49744be`: 6,506 LUT4s, 1,421 carries,
  1,476 flops, 522 unpackable flops, 14 EBRs, 7,028-cell floor, seed-1 7,247
  LCs; 146.82 MHz fast and 31.75 MHz PSG.
- **Changed condition versus R.68/R.69 and H044:** R.68/R.69 changed global
  schedule encodings, while H044 changed a persistent counter-terminal
  predicate. H052 leaves the visit schedule and fold microstep encoding fixed;
  it uses one otherwise-unused value of the existing private operand selector
  solely during the already-required final root node.
- **Change:** remove `ffin`; after selector state four, use selector state five
  for the final root reduction, retain state three for the non-final root, and
  pulse `dry_valid` exactly when state five completes.
- **Result:** exhaustive exploration proves all 323 legal controller
  transitions across 42 terminal paths, including every arbitrary sign branch,
  operand source, destination, pending-node transition, and publication event.
  Constrained Yosys SAT proves the legal-state relation, all operand/destination
  selections, next control state, and `dry_valid` event. Isolated complete-
  controller synthesis changes 120 LUT4 / 67 FF to 123 LUT4 / 67 FF, with no
  carries in either form. The removed `ffin` flop is replaced by an additional
  mapper-created `fsel` state bit: mapped selector flops grow from four to five.
- **Decision:** rejected before production RTL. The exact encoding is locally
  larger and removes no deterministic mapped resource, so the hypothesis gate
  forbids a whole-PSG edit or physical claim. Production RTL and permanent
  hardware forms remain unchanged.
- **Repeat only if:** if rejected, retry only after the fold selector width,
  reduction topology, terminal publication boundary, or mapper sequential
  encoding changes.

## Hypothesis H053

- **ID:** H053.
- **Hypothesis:** the full-mode `dry_valid` pulse is the one clock immediately
  after final fold completion and can be represented by unused `fmc=10`.
  Decoding that existing four-bit state while excluding it from `fold_busy`
  should preserve the external pulse and busy waveforms exactly, retain
  `ffin` and every arithmetic microstep, and remove the dedicated publication
  flop without adding state width.
- **Scope:** exhaustive full-mode fold/publication transition proof,
  constrained formal equivalence of externally visible fold busy/valid
  actions, isolated synthesis of the complete controller consumer, then, only
  after a deterministic win, `rtl/psg_walk.sv`, permanent hardware forms,
  whole-PSG mapping, and the complete H051 battery. PREVIEW retains its current
  pulse register. No arithmetic, visit cadence, selector, pending count, EBR,
  interface, R.84 executor, or tolerance change.
- **Baseline:** accepted H051 commit `49744be` plus docs-only H052 `c432079`:
  6,506 LUT4s, 1,421 carries, 1,476 flops, 522 unpackable flops, 14 EBRs,
  7,028-cell floor, seed-1 7,247 LCs; 146.82 MHz fast and 31.75 MHz PSG.
- **Changed condition versus H052 and R.68/R.69:** H052 expanded the operand
  selector encoding and the mapper added a replacement selector state bit.
  H053 leaves that selector and all global schedule actions untouched; it uses
  an unused value of the already-four-bit private arithmetic counter solely to
  carry an existing registered output pulse.
- **Change:** on final fold completion set `fmc` to ten rather than zero; in
  full mode decode `dry_valid` from state ten, exclude state ten from
  `fold_busy`, and let the next controller edge return to idle zero. Keep the
  existing registered PREVIEW pulse unchanged.
- **Result:** exhaustive exploration proves exact `fold_busy` and `dry_valid`
  waveforms across 350 legal controller transitions and 42 terminal paths.
  Constrained Yosys SAT proves the state relation and next-state/public-action
  equivalence. The complete isolated controller changes 120 LUT4 / 67 FF to
  125 LUT4 / 66 FF. Canonical whole-PSG mapping changes H051's 6,506 LUT4 /
  1,421 carry / 1,476 FF / 522 unpackable / 14 EBR / 7,028-cell floor / 7,247
  routed LCs to 6,528 LUT4 / 1,422 carry / 1,475 FF / 519 unpackable / 14 EBR /
  7,047-cell floor / 7,266 routed LCs. Routed clocks pass at 147.89 and 31.01
  MHz against 112.50 and 18.75 MHz constraints.
- **Decision:** rejected and reverted. The one-flop saving costs 22 LUT4s, one
  carry, and 19 deterministic floor cells, and seed-1 placement also regresses
  by 19 LCs. Production RTL and the conditional permanent proof are restored
  byte-for-byte; the full fidelity battery is correctly skipped.
- **Repeat only if:** if rejected, retry only after the fold counter width,
  publication latency, busy contract, preview/full elaboration boundary, or
  mapper sequential encoding changes.

## Hypothesis H054

- **ID:** H054.
- **Hypothesis:** the primary triangle phase before the existing multiply by
  three is exactly a signed 15-bit centered lower phase, conditionally negated
  by the top phase bit. With `c = signed({~wx[14],wx[13:0]})`, the current
  expression equals `wx[15] ? -c : c` for all 65,536 phases. Keeping `c` at
  15 bits and only the conditional result at 16 bits should replace the
  current 17-bit complement/subtract/bias construction with a narrower exact
  fold while making the triangle symmetry explicit.
- **Scope:** exhaustive proof over all 65,536 phases, unconstrained Yosys SAT,
  isolated synthesis of the registered primary triangle consumer, then, only
  after a deterministic win, `rtl/psg_wave.sv`, permanent hardware forms,
  whole-PSG mapping, and the complete H051 battery. No organ fold, triangle
  detune residue, secondary presentation, output scaling, pipeline timing,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted H051 commit `49744be` plus docs-only H052/H053 through
  `023bedd`: 6,506 LUT4s, 1,421 carries, 1,476 flops, 522 unpackable flops,
  14 EBRs, 7,028-cell floor, seed-1 7,247 LCs; 146.82 MHz fast and 31.75 MHz
  PSG. The isolated baseline is the complete registered triangle fold and its
  existing multiply-by-three consumer; whole-PSG mapping remains authoritative.
- **Changed condition versus H040, H042, and H047:** H040 changed the organ
  ramp, H042 changed the triangle detune-1 residue comparator, and H047 shared
  final output scaling. H054 changes only the primary triangle phase fold
  before its existing multiply by three; none of those earlier cones or their
  rejected spellings is retried.
- **Change:** build the 15-bit centered phase, sign-extend it to 16 bits,
  conditionally negate it from `wx[15]`, and retain the exact existing
  multiply-by-three and truncating `/4` consumers.
- **Result:** a scalar exhaustive proof covers all 65,536 phases and
  unconstrained Yosys SAT proves both the pre-scale value and multiply-by-three
  result exactly. Isolated synthesis of the complete registered primary
  triangle and `/4` consumers changes 60 LUT4 / 45 carry / 34 FF to 71 LUT4 /
  44 carry / 34 FF. Evidence is saved under `build/experiments/h054/`.
- **Decision:** rejected before production RTL. The one-carry reduction costs
  eleven LUT4s, so it fails the deterministic physical gate. Production RTL
  and permanent hardware forms remain unchanged; no whole-PSG or behavior
  claim is made.
- **Repeat only if:** if rejected, retry only after the primary triangle
  representation, pre-scale width, pipeline boundary, or mapper arithmetic
  lowering changes.

## Hypothesis H055

- **ID:** H055.
- **Hypothesis:** the pitched-noise multiplier yields an unsigned integer
  magnitude `m` and an eight-bit discarded fraction. Its signed rounded result
  is `m` for a positive random step and `-(m + fractional_nonzero)` for a
  negative step. This is exactly
  `(m ^ {18{negative}}) + (negative && !fractional_nonzero)`. Spelling the two
  branches as one conditional complement and carry-in may replace the current
  negative add/negate plus output mux while making truncation toward zero
  explicit.
- **Scope:** exhaustive proof over all 65,536 magnitudes, both fraction classes,
  and both signs; unconstrained Yosys SAT; isolated synthesis of the complete
  registered signed-noise consumer; then, only after a deterministic win,
  `rtl/psg_walk.sv`, permanent hardware forms, whole-PSG mapping on direct
  frontier `293a5f5`, and the complete acceptance battery. No multiplier,
  noise clamp, kick predicate, LFSR, schedule, state, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H051 commit `293a5f5`: 6,488 LUT4s, 1,403
  carries, 1,460 flops, 500 unpackable flops, 14 EBRs, 6,988-cell floor,
  seed-1 7,225 LCs; 147.12 MHz fast and 31.80 MHz PSG. The isolated baseline
  includes the magnitude/fraction slice, current positive/negative rounding,
  sign selection, and registered result; whole-PSG mapping remains
  authoritative.
- **Changed condition versus H011, H027, and H029:** H011 tested a constant
  tilted-saw reflection spelling, H027 replaced signed noise saturation
  comparators, and H029 rewrote the kick-enable inequality. H055 changes only
  post-multiply signed fractional rounding; none of those expressions or
  rejected mechanisms is retried.
- **Change:** test two exact spellings. The first inlines the unified
  conditional complement/carry at both independent live and old sign
  consumers. The second retains the shared positive/negative limbs but changes
  only the negative limb from `-(magnitude + fractional_nonzero)` to
  `~magnitude + !fractional_nonzero`.
- **Result:** scalar exhaustive comparison passes all 262,144 sign/magnitude/
  fraction-class cases, and unconstrained Yosys SAT proves both candidate
  forms. A misleading single-sign probe changes 38 LUT4 / 16 carry / 18 FF to
  36 / 16 / 18. The complete two-sign consumer exposes duplication: the
  inlined form changes 71 LUT4 / 16 carry / 36 FF to 71 / 32 / 36. The shared-
  limb form instead changes it to 70 / 16 / 34 and advances. On direct
  `293a5f5`, forced mapping changes 6,488 LUT4 / 1,403 carry / 1,460 FF / 500
  unpackable / floor 6,988 to 6,473 LUT4 / 1,404 carry / 1,460 FF / 501
  unpackable / floor 6,974. Seed-1 placement uses 7,213 LCs and passes placed
  timing at 141.62/32.15 MHz, but router2 remains fixed at two overused wires
  through 21,160 iterations and produces no routed design. Production RTL and
  permanent forms are restored; the direct continuation worktree is clean.
- **Decision:** rejected and reverted. The deterministic 15-LUT and 14-floor-
  cell reductions cannot be accepted without a canonical route, and the only
  other materially distinct form doubles carries in the complete consumer.
  The full behavior battery is correctly skipped because the physical gate
  failed first.
- **Repeat only if:** if rejected, retry only after the pitched-noise product
  slice, signed rounding contract, consumer pipeline boundary, or mapper
  arithmetic lowering changes.

## Hypothesis H056

- **ID:** H056.
- **Hypothesis:** the organ primary-output branch needs the registered top phase
  bit only when the alternate-secondary bypass is inactive. In that domain,
  the completed registered linear organ sample exactly satisfies
  `wx[15] == z_lin[15] ^ z_lin[14]` for all 65,536 phases. Reusing those two
  existing registered bits should remove `org_hi_r` and its update cone while
  making the surviving-state invariant explicit.
- **Scope:** exhaustive proof over every phase and both bypass classes;
  unconstrained Yosys SAT; isolated synthesis of the complete two-stage organ
  branch consumer; then, only after a deterministic win, `rtl/psg_wave.sv`,
  permanent hardware forms, whole-PSG mapping on direct frontier `293a5f5`,
  and the complete acceptance battery. No organ ramp arithmetic, reciprocal,
  waveform output scaling, phase selection, schedule, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H051 commit `293a5f5`: 6,488 LUT4s, 1,403
  carries, 1,460 flops, 500 unpackable flops, 14 EBRs, 6,988-cell floor,
  seed-1 7,225 LCs; 147.12 MHz fast and 31.80 MHz PSG. The isolated baseline
  includes linear-organ construction, the existing second-stage registers,
  bypass controls, div/output selection, and a registered consumer.
- **Changed condition versus H040 and R.40--R.42:** H040 rewrote the
  pre-register organ ramp and regressed globally. R.40--R.42 aliased unrelated
  cross-family register lifetimes and lost their savings to input mux/fanout.
  H056 changes no arithmetic and aliases no register: it proves the needed
  predicate is already encoded in a completed registered result.
- **Change:** committed as direct-frontier `ac15778`: remove `org_hi_r` and its
  stage-one update, derive the organ primary selector from
  `z_lin_r[15] ^ z_lin_r[14]`, and retain the exhaustive identity in
  `tools/psg_hw_forms.py`.
- **Result:** the 131,072-case phase/bypass proof and unconstrained Yosys SAT
  pass. The complete isolated branch changes 81 LUT4 / 15 carry / 38 FF to
  81 / 15 / 37. On direct `293a5f5`, forced HX8K mapping changes 6,488 LUT4 /
  1,403 carry / 1,460 FF / 500 unpackable / 14 EBR / floor 6,988 to 6,489 /
  1,403 / 1,459 / 498 / 14 / floor 6,987. Seed-1 routing changes 7,225 to
  7,224 LCs, explicitly below placement sensitivity; routed timing is
  116.37/32.96 MHz against 112.50/18.75 MHz constraints. Forced synthesis
  reproduces the result. Full hardware forms, full/PREVIEW lint,
  `make test-psg`, and all 59 frozen renders pass byte-exactly. Correctly
  parameterized `/4`, `/5`, and `/6` regressions pass at 572/1,275,
  572/1,020, and 524/850 sample clocks and 5,757/7,654, 4,737/6,123, and
  4,008/5,103 tick clocks, all with zero lost writes or late flips.
  `make test-clocks`, all eight preview checks, synthetic/Celeste recovery,
  byte-identical H051 hardware/PREVIEW SFX-10 renders with zero `click-v1`
  events, and the five-frame Celeste smoke pass. The smoke reports
  2,179/3,668 active samples, range -22,013..9,151, and 1,068 levels. Strict
  OpenSpec, `py_compile`, diff, staged-scope, and status audits pass.
- **Decision:** accepted. The source and state contract are simpler, one
  mapped flop and one deterministic floor cell retire, seed-1 placement does
  not regress, and the complete exact behavior and timing battery passes.
- **Repeat only if:** do not retry another spelling of this predicate unless
  the organ linear-output representation, alternate-secondary bypass,
  pipeline boundary, or mapper sequential lowering changes.

## Hypothesis H057

- **ID:** H057.
- **Hypothesis:** `tilt_hi_r` is redundant state. Its input is exactly
  `(wsel_r == 3'd1) && walt_r`, while `wsel_r2` and `walt_r2` capture those
  operands on the same edge. Reconstructing the next-stage predicate as
  `(wsel_r2 == 3'd1) && walt_r2` should preserve every cycle and remove one
  control flop plus its D-input logic.
- **Scope:** exhaustive two-state predicate proof, unconstrained sequential
  Yosys SAT, and isolated synthesis of the complete registered reciprocal
  recombination consumer. Production `rtl/psg_wave.sv`, permanent hardware
  forms, whole-PSG mapping on direct frontier `ac15778`, and the complete H056
  battery are conditional on a deterministic mapped or floor improvement. No
  quotient arithmetic, reciprocal contents, selector encoding, payload
  register, pipeline edge, waveform output, schedule, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H056 commit `ac15778`: 6,489 LUT4s, 1,403
  carries, 1,459 flops, 498 unpackable flops, 14 EBRs, 6,987-cell floor,
  seed-1 7,224 LCs; 116.37 MHz fast and 32.96 MHz PSG. The isolated baseline
  includes selector/control capture, the mode-specific quotient registers,
  reciprocal result, full recombination network, and a registered consumer.
- **Changed condition versus H036:** H036 inserted a mode mux before a wide
  quotient payload register and moved its D-input/fanout partition, producing
  a global LUT/flop regression despite an isolated saving. H057 neither moves
  nor aliases payload state: the exact control predicate is already encoded by
  two same-edge registers used throughout the existing downstream stage, so
  only a duplicated one-bit register is removed.
- **Change:** committed as direct-frontier `c9274fc`: remove `tilt_hi_r`, define
  `tilt_hi2 = (wsel_r2 == 3'd1) && walt_r2`, use it in the reciprocal-
  recombination consumers, and retain the state identity in
  `tools/psg_hw_forms.py`.
- **Result:** exhaustive control enumeration, an inductive SAT check, and a
  three-step arbitrary-defined-state sequential SAT miter pass. The isolated
  complete consumer changes 171 LUT4 / 25 carry / 88 FF to 182 / 25 / 87, so
  its local LUT trade is negative; the whole PSG shares the registered selector
  decodes and instead changes H056's 6,489 LUT4 / 1,403 carry / 1,459 FF / 498
  unpackable / 14 EBR / floor 6,987 to 6,466 / 1,403 / 1,458 / 502 / 14 /
  floor 6,968. Seed-1 routing changes 7,224 to 7,204 LCs, explicitly below
  placement sensitivity; timing is 116.37/30.42 MHz against 112.50/18.75 MHz
  constraints. Forced synthesis reproduces the JSON and ASC bit-for-bit. Full
  hardware forms, full/PREVIEW lint, `make test-psg`, and all 59 frozen renders
  pass byte-exactly. The exact `/4`, `/5`, and `/6` matrix passes at 572/1,275
  and 5,757/7,654 clocks, 572/1,020 and 4,737/6,123 clocks, and 524/850 and
  4,008/5,103 clocks, with zero lost writes, overruns, or late flips.
  `make test-clocks`, all eight preview checks, synthetic/Celeste recovery,
  exact same-tool H056 hardware/PREVIEW SFX-10 renders with zero `click-v1`
  events, and the five-frame Celeste smoke pass. The stored H056 preview WAV
  used Verilator 5.050 and is one sample offset; rebuilding H056 and H057 with
  the same 5.051 toolchain produces byte-identical WAVs. The smoke remains at
  2,179/3,668 active samples, range -22,013..9,151, and 1,068 levels. Strict
  OpenSpec, `py_compile`, diff, staged-scope, and post-commit audits pass.
- **Decision:** accepted. The state contract is simpler, 23 mapped LUT4s, one
  mapped flop, and 19 deterministic floor cells retire, placement does not
  regress, and the complete exact behavior and timing battery passes.
- **Repeat only if:** do not retry another spelling of this state identity unless
  selector/control pipeline placement, reciprocal-recombination consumers, or
  mapper sequential lowering changes materially.

## Hypothesis H058

- **ID:** H058.
- **Hypothesis:** `state_replay` is redundant in the composed PSG. It is the
  one-cycle delayed value of `prun`. During a walk it is covered by `prun`, and
  the edge that drops `prun` for the final voice unconditionally launches the
  reduction fold, making `fold_busy` true throughout the displaced state-RAM
  read's reissue interval in both full and PREVIEW elaborations. Therefore
  `state_replay -> (prun || fold_busy)` should hold on every reachable cycle;
  removing the replay flop, top-level OR term, and unused sequencer port should
  preserve the synchronous RAM value seen when the sequencer next advances.
- **Scope:** a source-exact transition proof for full and PREVIEW walk/fold
  control, a composed state-RAM/sequencer-read timing miter, and isolated/full
  iCE40 synthesis first. Production `rtl/psg_state_mem.sv`, `rtl/psg.sv`,
  `rtl/psg_seq.sv`, permanent hardware forms, module-structure specification,
  and the complete H057 battery are conditional on a deterministic mapped or
  floor improvement. No RAM contents, address/data/write mux, controller state,
  walk/fold schedule, sequencer state, arithmetic, EBR, R.84 executor, clock,
  public PSG interface, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H019 and R.84:** H019 changed the state-memory
  request-owner mux and kept the replay contract; it regressed globally. H058
  leaves that mux and both controllers unchanged, and tests only whether the
  already-required terminal fold interval subsumes the replay freeze. R.84
  replaces both controllers and is excluded from this worktree.
- **Change:** scratch-only remove `state_replay`, its resettable flop and
  `prun` input from `psg_state_mem`, its top-level busy/ARAM-hold OR terms, and
  its unused `psg_seq` port. The memory request muxes and both controllers stay
  byte-identical. Production RTL is restored byte-for-byte after measurement.
- **Result:** a symbolic Yosys SAT proof covers every full and PREVIEW control
  input and proves both `next_state_replay -> (next_prun || next_fold_busy)`
  and equality of the baseline/candidate hold signals. Full and PREVIEW lint
  pass. Canonical H057-to-candidate mapping changes 6,466 LUT4 / 1,403 carry /
  1,458 FF / 502 unpackable / 14 EBR / floor 6,968 to 6,490 / 1,408 / 1,457 /
  499 / 14 / floor 6,989. Seed-1 placement changes 7,204 to 7,235 LCs and
  passes placed timing at 144.43/32.63 MHz, but router2 remains fixed at two
  overused wires through 55,386 iterations and produces no routed design.
  This is substantially beyond H055's recorded 21,160-iteration route-failure
  threshold. The complete fidelity battery and permanent proof/spec edits are
  correctly skipped because mapped, floor, placement, and routing gates fail.
- **Decision:** rejected and reverted. The exact state simplification removes
  one flop but worsens every deterministic combinational/floor metric, placed
  area, and routability.
- **Repeat only if:** if containment or physical mapping fails, retry only after
  the final-voice fold launch, state-RAM synchronous-read timing, walk/fold
  overlap, or top-level freeze consumers change materially.

## Hypothesis H059

- **ID:** H059.
- **Hypothesis:** `org_h_r` is redundant state. Outside the existing organ
  alternate-secondary bypass, every 16-bit phase's folded reciprocal ramp satisfies
  `org_ramp = (z_lin + 8192) mod 2^15`. Therefore its registered high byte is
  exactly `{z_lin_r[14] ^ z_lin_r[13], ~z_lin_r[13], z_lin_r[12:7]}`: adding
  64 modulo 256 changes only the top two bits. Reconstructing that byte should
  retire eight flops and their D-input cone without moving a pipeline edge or
  adding an arithmetic carry chain. During the bypass the reciprocal result is
  unobserved, so its reconstructed quotient byte is a don't-care.
- **Scope:** exhaustive all-phase proof, unconstrained Yosys SAT, and isolated
  synthesis of the complete two-stage organ reciprocal consumer. Production
  `rtl/psg_wave.sv`, permanent hardware forms, whole-PSG mapping on direct
  frontier `c9274fc`, and the complete H057 battery are conditional on a
  deterministic mapped or floor improvement. No organ-ramp arithmetic,
  reciprocal address/table/content, selector encoding, pipeline edge,
  waveform output, schedule, interface, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H040 and H056:** H040 rewrote the pre-register
  organ fold and changed mapper arithmetic covering, regressing globally.
  H056 instead proved that the completed, already-registered `z_lin_r` carries
  the organ high-phase predicate and retained that representation. H059 leaves
  H040's source ramp byte-for-byte unchanged and tests a wider exact projection
  from the same completed result, removing only duplicated downstream state.
- **Change:** prove the byte identity in a scratch probe, then price both full
  retirement of `org_h_r` and a partial form retaining only its bypass-live
  bits. Both production variants were applied only in the dedicated direct-
  frontier worktree and reverted byte-for-byte after pricing.
- **Result:** the exhaustive 524,288-case proof and unconstrained Yosys SAT
  pass. Isolated baseline/full/partial synthesis is respectively 149/42/39,
  150/27/31, and 150/27/37 LUT4/carry/FF. Whole-PSG full retirement regresses
  H057's 6,466 LUT4 / 1,403 carry / 1,458 FF / floor 6,968 / 7,204 LCs to
  6,495 / 1,408 / 1,450 / floor 6,987 / 7,229 LCs. Partial retirement maps at
  6,477 LUT4 / 1,407 carry / 1,456 FF / floor 6,977 and places at 7,221 LCs,
  then stops routing with two overused wires after 7,255 iterations. Full and
  PREVIEW lint pass for both variants; the complete fidelity battery is
  correctly skipped because both fail deterministic physical area gates.
- **Decision:** rejected and reverted. The identity is exact and saves state,
  but full and partial retirement both worsen the whole-PSG physical result.
- **Repeat only if:** retry only
  after the organ linear-output representation, reciprocal quotient consumer,
  pipeline placement, or mapper sequential lowering changes materially.

## Hypothesis H060

- **ID:** H060.
- **Hypothesis:** `tri4_r` duplicates information already captured in
  `z_lin_r`. On the only live consumer, alternate primary triangle,
  `z_lin_r == tri_v`; therefore `tri4_r == tzs(z_lin_r, 2)` after the same
  pipeline edge. Reconstructing the `/4` term should retire 18 payload flops
  and their pre-register D cone without changing the triangle generator,
  pipeline timing, or waveform arithmetic.
- **Scope:** exhaustive all-phase/control proof, unconstrained sequential Yosys
  SAT, and isolated synthesis of the complete registered alternate-triangle
  consumer. Production `rtl/psg_wave.sv`, permanent hardware forms, whole-PSG
  mapping on direct frontier `c9274fc`, and the complete H057 battery are
  conditional on a deterministic mapped or floor improvement. No triangle
  source fold, reciprocal arithmetic/table, selector encoding, pipeline edge,
  waveform output, schedule, interface, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H054 and H059:** H054 rewrote the pre-register
  centered-triangle fold and added eleven isolated LUT4s. H060 leaves that
  source cone byte-for-byte unchanged and removes only a duplicate projection
  after proving its same-edge source identity. H059 tested the analogous organ
  quotient payload but regressed globally; this distinct triangle payload has
  a different width, rounding function, and consumer cone and is therefore
  priced independently.
- **Change:** remove `tri4_r` and reconstruct its only live value as
  `tzs(z_lin_r, 2)` at the existing downstream stage. The production variant
  was applied only in the dedicated direct-frontier worktree and reverted
  byte-for-byte after pricing.
- **Result:** all 262,144 phase/alternate/secondary cases pass, and the three-
  step sequential SAT miter proves the registered consumers equivalent. The
  isolated complete consumer changes 203 LUT4 / 79 carry / 39 FF / floor 210
  to 203 / 80 / 23 / floor 208. Whole-PSG mapping instead regresses H057's
  6,466 LUT4 / 1,403 carry / 1,458 FF / 502 unpackable / floor 6,968 to 6,520
  / 1,404 / 1,442 / 498 / floor 7,018. Seed-1 routing regresses 7,204 to 7,257
  LCs; both clocks still pass at 132.03/31.57 MHz. Full and PREVIEW lint pass;
  the complete fidelity battery is correctly skipped because deterministic
  mapped, floor, and routed area all fail.
- **Decision:** rejected and reverted. The identity is exact and removes 16
  mapped flops, but its downstream rounding cone destroys the physical win.
- **Repeat only if:** retry only
  after the triangle linear-output representation, alternate-triangle
  consumer, pipeline placement, or mapper sequential lowering changes
  materially.

## Hypothesis H061

- **ID:** H061.
- **Hypothesis:** the high byte of `fade_acc` is redundant after every active
  fade update. For fade-in it equals `mus_gain`; for established fade-out it
  equals `~mus_gain`. The currently unused `fade_dir == 3` can represent the
  fresh fade-out interval, where progress is zero but the prior gain must
  remain observable until the first `pre_tick`. Retaining only the low eight
  progress bits should remove eight flops while preserving every command-
  transient and tick-visible value.
- **Scope:** symbolic next-state and sequential-invariant proof covering fade-
  in, fresh/established fade-out, completion, idle, and command interruption;
  isolated synthesis of the complete registered fade-state consumer.
  Production `rtl/psg_seq.sv`, permanent hardware forms, whole-PSG mapping on
  direct frontier `c9274fc`, and the complete H057 battery are conditional on
  a deterministic mapped or floor improvement. No fade step/table/content,
  command timing, gain value, music stop behavior, schedule, interface, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H025 and H041:** H025 only named the repeated
  combinational fade sum and mapped identically; H041 rewrote the fade-length
  eligibility predicate and regressed globally. H061 changes neither cone. It
  proves a sequential representation invariant between the already-published
  gain and accumulator state, using an otherwise unreachable direction code
  to preserve the one interval where that invariant has not yet been
  established.
- **Change:** in the scratch probe, replace the 16-bit `fade_acc` with an eight-
  bit fraction, reconstruct established progress from `mus_gain`, and encode
  fresh fade-out as `fade_dir == 3` so its prior gain remains observable until
  the first `pre_tick`. Production RTL remains untouched.
- **Result:** exhaustive evaluation passes all 4,202,496 reachable active/fresh
  fade states across the 32 source-derived fade steps. Yosys SAT proves the
  symbolic next-state invariant for arbitrary commands and `pre_tick`,
  including completion and command priority. Isolated complete-consumer
  synthesis changes 41 LUT4 / 16 carry / 27 FF / four unpackable / floor 45
  to 49 / 16 / 19 / two unpackable / floor 51.
- **Decision:** rejected before production. Eight retired flops do not offset
  eight added LUT4s, and the deterministic isolated floor regresses by six.
- **Repeat only if:** retry only
  after fade command timing, accumulator/gain publication, direction encoding,
  or mapper sequential lowering changes materially.

## Hypothesis H062

- **ID:** H062.
- **Hypothesis:** `old_nz_r_on` duplicates the old sounding tuple after the
  visit-start edge. Its captured value is `run && old_nz_on`, where a restart
  selects `s_last_wave/last_alt_r`; that same edge copies those fields into
  `s_old_wave/old_alt_r`, while a non-restart retains the existing old tuple.
  The run predicate and copied tuple remain stable through all consumers, so
  reconstructing the flag should remove one control flop and its D cone with
  no arithmetic or payload remapping.
- **Scope:** exhaustive snapshot/control proof, arbitrary-defined-state
  sequential Yosys SAT, and isolated synthesis of the complete registered old-
  noise consumer. Production `rtl/psg_walk.sv`, permanent hardware forms,
  whole-PSG mapping on direct frontier `c9274fc`, and the complete H057 battery
  are conditional on a deterministic mapped or floor improvement. No noise
  arithmetic, old-phase state, restart predicate, snapshot timing, visit
  schedule, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H057 and H058:** H057 accepted reconstruction of
  a duplicated one-bit predicate from two same-edge registered controls. H062
  applies that mechanism to a distinct walk snapshot whose selected source is
  copied into the lasting old tuple on the same edge. H058 removed a replay
  contract across a memory hold interval and regressed globally; H062 neither
  changes memory ownership nor recomputes a payload.
- **Change:** remove `old_nz_r_on` and reconstruct the downstream predicate as
  current-run active plus `s_old_wave == 6 && !old_alt_r`; retain the existing
  pre-edge `old_nz_on` only for the simultaneous old-phase seed. The production
  variant was applied only in the dedicated direct-frontier worktree and
  reverted byte-for-byte after pricing.
- **Result:** all 1,024 snapshot/control cases pass, combinational Yosys SAT
  proves the selected-source identity, and a four-step arbitrary-state miter
  proves every post-restart consumer. Isolated complete-consumer synthesis
  changes 23 LUT4 / zero carry / five FF / floor 27 to 21 / zero / four /
  floor 25. Whole-PSG mapping instead regresses H057's 6,466 LUT4 / 1,403
  carry / 1,458 FF / 502 unpackable / floor 6,968 to 6,521 / 1,403 / 1,457 /
  500 / floor 7,021. Seed-1 routing regresses 7,204 to 7,261 LCs; both clocks
  still pass at 116.28/32.94 MHz. Full and PREVIEW lint pass; the complete
  fidelity battery is correctly skipped because mapped, floor, and routed area
  fail decisively.
- **Decision:** rejected and reverted. A two-LUT isolated win and one retired
  flop are overwhelmed by global D-input/fanout remapping.
- **Repeat only if:** retry only
  after old-tuple snapshot timing, restart inputs, old-noise consumers, or
  mapper sequential lowering changes materially.

## Hypothesis H063

- **ID:** H063.
- **Hypothesis:** `mxs_old` stores only the sign of `z_old_sel` at W15 and is
  consumed only when W51 signs the old-arm gain result. W15 executes this
  capture only for a built-in wave. In that branch `smp_b` is complete at W5,
  while the old-noise selector, old-noise output, and old increment are complete
  no later than W1 and remain unchanged through W51. Using the live
  `z_old_sel[17]` at W51 should therefore retire one sign flop and its assignment
  without recomputing an arithmetic payload.
- **Scope:** source-derived assignment/phase audit, exhaustive scheduled-event
  proof, arbitrary-defined-state sequential Yosys SAT, and isolated synthesis
  of the complete old-arm sign consumer. Production `rtl/psg_walk.sv`, a
  permanent hardware form, whole-PSG mapping on direct frontier `c9274fc`, and
  the complete H057 battery are conditional on a deterministic mapped or floor
  improvement. No sample arithmetic, noise state, gain scaling, multiplier
  request, action schedule, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H058--H063 DNR families:** H063 does not remove a
  memory replay contract, reconstruct an old-noise eligibility flag, or derive
  a registered arithmetic payload. It removes a visit-local sign snapshot only
  after proving that the existing sign source itself is invariant across its
  sole capture-to-consume interval.
- **Change:** the direct-frontier experiment removed `mxs_old`, its W15
  assignment, and used `z_old_sel[17]` for the W51 old-gain sign. It was
  reverted byte-for-byte after pricing.
- **Result:** a source assignment audit passes and all 512 endpoint schedules
  agree. A 70-step Yosys SAT miter with arbitrary defined source state and
  arbitrary stalls proves the W15 snapshot equals the live W51 sign whenever
  the consumer is active. Isolated complete-consumer synthesis keeps 47 LUT4s
  and 15 carries while removing one FF. Under the same current Yosys, exact
  H057 remaps to 6,466 LUT4 / 1,403 carry / 1,458 FF / 502 unpackable / floor
  6,968, while H063 maps to 6,530 / 1,407 / 1,457 / 500 / floor 7,030. H063
  routes at 7,273 LCs versus canonical H057's 7,204 and passes timing at
  122.46/31.52 MHz. Full and PREVIEW lint pass; the complete fidelity battery
  is correctly skipped because every physical area gate except FF count fails.
- **Decision:** rejected and reverted. One retired sign flop is overwhelmed by
  global covering and fanout remapping.
- **Repeat only if:** if rejected, retry only after the old-arm sample/noise
  lifetime, gain-consume action, or mapper sequential lowering changes
  materially.

## Hypothesis H064

- **ID:** H064.
- **Hypothesis:** the live and old nine-bit signed noise draws are two identical
  adjacent-XOR transforms of `lfsr[14:6]` and `lfsr2[14:6]`. Full mode selects
  between those complete draws only for disjoint old/live multiplier requests;
  its other consumers need only each draw's sign. Selecting the nine source
  bits before one shared adjacent-XOR transform, while retaining the individual
  top XORs for sign-only consumers, should remove duplicated random-draw logic
  without adding state or changing arithmetic.
- **Scope:** exhaustive selected-draw/sign proof, combinational Yosys SAT, and
  isolated synthesis of the complete registered request/sign consumer.
  Production `rtl/psg_walk.sv`, a permanent hardware form, whole-PSG mapping on
  direct frontier `c9274fc`, and the complete H057 battery are conditional on a
  deterministic mapped or floor improvement. No LFSR recurrence, random value,
  noise rounding, multiplier cadence/mode, state, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H017, H027, H029, and H055:** H017 selected between
  complete gain arithmetic contexts and regressed globally; H027/H029/H055
  changed clamp, kick, or signed-rounding arithmetic. H064 changes none of
  those cones. It factors one identical bitwise transform across two disjoint
  request operands and leaves the independent sign observations explicit.
- **Change:** the direct-frontier experiment selected `lfsr[14:6]` versus
  `lfsr2[14:6]` before one adjacent-XOR chain, uses that shared signed draw for
  `nz_mag_req`, and replaces the two full-draw sign reads with their exact top
  XOR bits. Preview retains its existing live draw. The variant was reverted
  byte-for-byte after pricing.
- **Result:** NumPy exhaustively checks all 524,288 live/old/select tuples and
  combinational Yosys SAT proves the selected draw plus both sign identities.
  Isolated complete-consumer synthesis changes 28 LUT4 / seven carry / eleven
  FF to 26 / seven / eleven. Whole-PSG mapping instead changes H057's 6,466
  LUT4 / 1,403 carry / 1,458 FF / 502 unpackable / floor 6,968 to 6,521 /
  1,407 / 1,458 / 501 / floor 7,022. Seed-1 routing regresses 7,204 to 7,267
  LCs; both clocks pass at 139.82/32.62 MHz. Full and PREVIEW lint pass; the
  complete fidelity battery is correctly skipped because mapped, floor, and
  routed area fail decisively.
- **Decision:** rejected and reverted. The local two-LUT network saving is
  overwhelmed by flattened covering and fanout remapping; no spelling-only
  second variant is justified.
- **Repeat only if:** if rejected, retry only after noise request ownership,
  LFSR tap layout, sign consumers, or mapper XOR/mux lowering changes
  materially.

## Hypothesis H065

- **ID:** H065.
- **Hypothesis:** `smp_a` and `smp_b` are 18-bit pipeline registers, but every
  value stored in them is a single built-in/custom-wave result or the completed
  primary-plus-secondary sample. Exhaustive primitive ranges and exact
  truncation-toward-zero composition bounds place every such value in signed
  16 bits. Narrowing both registers to 16 bits and explicitly sign-extending
  all 18-bit arithmetic consumers should retire four flops plus their upper
  assignment mux logic while preserving every value.
- **Scope:** source-derived assignment/use audit, exhaustive built-in/custom
  waveform range proof, signed-width/SAT equivalence of every load and consumer,
  and isolated synthesis of the complete registered sample boundary.
  Production `rtl/psg_walk.sv`, a permanent hardware form, whole-PSG mapping on
  direct frontier `c9274fc`, and the complete H057 battery are conditional on a
  deterministic mapped or floor improvement. No waveform formula, phase,
  noise state, sample schedule, multiplier request, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H013, H014, H037, and R.18/R.39:** H013/H014/H037
  tested multiplier/detune widths that Yosys already pruned or remapped worse;
  R.18/R.39 changed register ownership and fanout. H065 changes no lifetime or
  ownership: it contracts two existing sample registers at an exact value
  boundary and keeps their consumer widths explicit.
- **Change:** change `smp_a/smp_b` to signed 16-bit registers, introduce
  explicit sign-extended 18-bit views for
  sum/old/base consumers, and leave the nine-bit wavetable-delta slices
  unchanged.
- **Result:** the source audit and exact range proof bound all stored/composed
  built-in results to -18,429..18,427 and all 67,108,864 custom-wave tuples to
  -16,384..16,256. Yosys SAT with the source assumptions passes. The complete
  isolated registered boundary improves from 70 LUT4 / 33 carry / 36 FF to
  67 / 32 / 32. Full and PREVIEW lint pass. Canonical forced whole-PSG
  synthesis instead changes H057's 6,466 LUT4 / 1,403 carry / 1,458 FF / 502
  unpackable / floor 6,968 to 6,493 / 1,399 / 1,454 / 502 / floor 6,995.
  Seed-1 routing changes 7,204 to 7,236 LCs; both clocks pass at
  120.80/32.58 MHz. The complete fidelity battery is correctly skipped
  because deterministic mapped and floor area regress decisively.
- **Decision:** rejected and reverted byte-for-byte. Four fewer flops and
  carries do not compensate for 27 more LUT4s/floor cells; no second width
  spelling is justified on this mapping context.
- **Repeat only if:** if rejected, retry only after waveform/sample bounds,
  sample-register assignments, consumer widths, or mapper sequential lowering
  changes materially.

## Hypothesis H066

- **ID:** H066.
- **Hypothesis:** `tilt_tail_r` delays one predicate to choose the direct-tail
  result after the reciprocal RAM read, while `rc_h2_r` delays the folded
  reciprocal index for the mutually exclusive non-tail result. Exhaustive
  source arithmetic bounds every live tilt/organ `rc_h2` to 0..105, leaving
  `7'h7f` unreachable. Encoding the tail token as that reserved `rc_h2_r`
  value should remove one flop and its separate predicate path without adding
  state or changing any arithmetic.
- **Scope:** exhaustive source-derived `rc_h2` range and tail/result proof,
  sequential SAT equivalence of the two-stage consumer, isolated synthesis of
  the complete registered boundary, and conditional production
  `rtl/psg_wave.sv`, permanent hardware form, whole-PSG mapping, and complete
  H057 battery. No waveform value, reciprocal contents, schedule, interface,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H003, H052, H053, and H057:** H003 simplified
  the source tail comparison but retained its pipeline state; H052/H053 added
  controller states; H057 reconstructed a predicate from same-edge control
  registers. H066 instead embeds mutually exclusive metadata in a provably
  unused code of an existing stage-aligned payload register.
- **Change:** planned direct-frontier experiment gives organ selection priority,
  writes `7'h7f` into `rc_h2_r` for non-organ tail cases, reconstructs the
  delayed tail predicate as `&rc_h2_r`, and removes `tilt_tail_r`.
- **Result:** exhaustive evaluation of 1,048,576 selector/phase cases proves
  every live tilt `rc_h2` is 0..105 and every organ value is 0..95, so 127 is
  unreachable; the tail selection and SAT induction pass. The complete
  isolated registered boundary changes 182 LUT4 / 25 carry / 87 FF to
  188 / 25 / 86. Full and PREVIEW lint pass with only existing warnings.
  Canonical forced whole-PSG synthesis changes H057's 6,466 LUT4 / 1,403
  carry / 1,458 FF / 502 unpackable / floor 6,968 to 6,508 / 1,407 / 1,457 /
  500 / floor 7,008. Seed-1 routing changes 7,204 to 7,251 LCs; the PSG clock
  passes at 31.90 MHz, but the fast clock reaches only 111.26 MHz against the
  112.50-MHz constraint. The complete fidelity battery is correctly skipped.
- **Decision:** rejected and reverted byte-for-byte. The sentinel adds six
  isolated and 42 global LUT4s for one retired flop, worsens every area floor,
  and fails timing; no alternative reserved value is justified.
- **Repeat only if:** if rejected, retry only after reciprocal-index ranges,
  tail ownership, stage alignment, or mapper payload/predicate lowering
  changes materially.

## Hypothesis H067

- **ID:** H067.
- **Hypothesis:** `t_h7_r` and `t_h15_r` store 21 bits that are both exact
  slices of the same 19-bit `t_pre` captured beside them. Their low six and
  seven bits already survive in `t_pre_r[14:9]` and `[14:8]`; their remaining
  high four bits are the identical `t_pre[18:15]` prefix. Registering that
  prefix once and rebuilding both quotient views by wiring should retire 17
  flops and duplicated D paths without a selector or arithmetic.
- **Scope:** full-domain slice identity and sequential SAT proof, isolated
  synthesis of the complete registered reciprocal consumer, and conditional
  production `rtl/psg_wave.sv`, permanent hardware form, whole-PSG mapping,
  and complete H057 battery. No quotient value, reciprocal address/content,
  waveform arithmetic, schedule, interface, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H036 and H037:** H036 inserted an 11-bit
  mode-selection mux before one register and globally remapped worse; H037
  tested one conditionally dead bit that Yosys already pruned. H067 has no
  mode selection and no unreachable-value claim: it factors the shared source
  bit positions across both quotient registers and an already-live sibling
  payload, retaining only the four genuinely missing bits.
- **Change:** planned direct-frontier experiment replaces the ten- and eleven-
  bit quotient registers with one four-bit `t_hi_r`, reconstructing
  `t_h7_r={t_hi_r,t_pre_r[14:9]}` and
  `t_h15_r={t_hi_r,t_pre_r[14:8]}`.
- **Result:** exhaustive evaluation of all 524,288 `t_pre` values proves both
  slice reconstructions, and the SAT induction proves current-state selection
  plus next-state mapping. The complete baseline and candidate registered
  consumers both synthesize to 19 LUT4s and 29 FF. Yosys already merges the
  duplicate source bits across the two declared quotient registers, so no
  production RTL, permanent proof, whole-PSG synthesis, or fidelity gate is
  warranted.
- **Decision:** rejected before production. The candidate is source-shorter
  but physically identical, and the existing spelling states the two quotient
  slices directly.
- **Repeat only if:** if rejected, retry only after `t_pre_r` ownership/width,
  quotient consumers, pipeline alignment, or mapper shared-slice lowering
  changes materially.

## Hypothesis H068

- **ID:** H068.
- **Hypothesis:** the DQ recurrence currently commits its fifth step into `p`
  only so the completed result remains visible after `done` falls. If the
  terminal no-chain edge instead holds the fourth-step state, the same fifth
  `step_next` value remains visible throughout idle and on the `done` edge.
  Exposing `step_next[21:8]` directly should remove the 14-bit done/idle result
  mux and the unnecessary terminal register write without changing any valid
  transaction, chained-start, latency, or walker-consumption behavior.
- **Scope:** exhaustive service transaction/chained-start proof, terminal-state
  SAT relation, isolated complete-service synthesis, and conditional production
  `rtl/psg_dqsvc.sv`, permanent hardware form, whole-PSG mapping, and complete
  H057 battery. No arithmetic, coefficient, phase schedule, public interface,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H051 and closed state families:** H051 recoded the
  five active count states but retained the recurrence/result contract. H068
  does not add or repurpose controller state: it removes a result selector by
  retaining the already-live pre-terminal recurrence only during idle. It is
  separate from the closed fold publication, delayed-tick, divider, multiplier-
  width, and detune-service-count families.
- **Change:** planned direct-frontier experiment assigns `result` from
  `step_next[21:8]` unconditionally and holds `p` on the terminal edge when no
  request chains; terminal chained starts still load the next transaction.
- **Result:** the global-NumPy transaction model passes all 57,344 reachable
  coefficient/input pairs, the terminal/idle SAT relation passes, and the
  existing service test passes 524,288 arithmetic formulas plus 57,344
  exhaustive/chained transactions. The complete isolated service improves
  120 -> 114 LUT4s with 28 carries and 28 flops unchanged. Canonical forced
  whole-PSG synthesis is unfavorable: 6,466 -> 6,457 LUT4s, 1,403 -> 1,404
  carries, 1,458 flops unchanged, 502 -> 514 unpackable flops, 14 EBRs
  unchanged, floor 6,968 -> 6,971, and seed-1 route 7,204 -> 7,210 LCs.
  Timing passes at 137.65/30.75 MHz, but the deterministic floor and placed
  area both regress, so the complete fidelity battery is not warranted.
- **Decision:** rejected and reverted byte-for-byte. The local result mux win
  globally changes packing classes and violates the no-floor/no-placement-
  regression gate.
- **Repeat only if:** if rejected, retry only after the DQ result consumer,
  terminal chaining contract, recurrence alignment, or mapper result-mux
  lowering changes materially.

## Hypothesis H069

- **ID:** H069.
- **Hypothesis:** signed division by `2^k` truncated toward zero is exactly an
  arithmetic right shift plus one iff the input is negative and any discarded
  bit is nonzero. Rewriting the shared `tzs(v,k)` helper in that quotient/
  remainder form should avoid the current full-width pre-shift sign-bias add
  across its five waveform/walk consumers and may simplify both source and
  mapped carry logic.
- **Scope:** exhaustive all-18-bit/all-four-shift proof, formal identity, isolated
  synthesis of the complete five-consumer helper context, and conditional
  production `rtl/psg_common.svh`, permanent hardware form, whole-PSG mapping,
  and complete H057 battery. No waveform value, schedule, register, interface,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** direct accepted H057 commit `c9274fc`: 6,466 LUT4s, 1,403
  carries, 1,458 flops, 502 unpackable flops, 14 EBRs, 6,968-cell floor,
  seed-1 7,204 LCs; 116.37 MHz fast and 30.42 MHz PSG.
- **Changed condition versus H001 and H055:** H001 optimized two unsigned
  tilted-saw ceilings at fixed widths; H055 tested paired signed noise-product
  limbs and closed that local rounding topology. H069 changes the shared exact
  power-of-two signed-division helper itself, including its variable-shift
  waveform consumer, without merging noise limbs or changing an arithmetic
  value.
- **Change:** compute `q = v >>> k`, decode the discarded remainder for k=0..3,
  and return `q + (v[17] && remainder)`.
- **Result:** the global-NumPy proof passes all 1,048,576 signed18/shift
  combinations and Yosys SAT proves the identity. The complete five-consumer
  isolated context changes 174 -> 144 LUT4s and 137 -> 97 carries. Permanent
  forms, full/PREVIEW lint, `make test-psg`, 59/59 frozen renders, the exact
  `/4`/`/5`/`/6` ordinary and multipumped cadence matrix, `make test-clocks`,
  and all eight preview checks pass. Synthetic and Celeste recovery have zero
  coalesced, delayed, or dropped samples. Hardware and PREVIEW SFX-10 WAVs are
  byte-identical to H057 and have zero `click-v1` events. The five-frame
  Celeste smoke retains 2,179/3,668 active samples, range -22,013..9,151, and
  1,068 levels. Canonical forced HX8K synthesis changes 6,466 -> 6,456 LUT4s,
  1,403 -> 1,370 carries, 1,458 -> 1,459 flops, 502 -> 503 unpackable flops,
  floor 6,968 -> 6,959, and seed-1 route 7,204 -> 7,199 LCs with 14 EBRs.
  Routed timing passes at 133.69/32.82 MHz, and the JSON/ASC reproduce exactly.
  Strict OpenSpec, `py_compile`, diff, and exact two-file scope audits pass.
- **Decision:** accepted. The shared arithmetic contract is explicit, mapped
  LUT4s, carries, and deterministic floor all improve, seed-1 placement does
  not regress, and the complete exact behavior and timing battery passes. The
  five-LC route reduction remains explicitly non-robust.
- **Repeat only if:** if rejected, retry only after the shared helper's consumer
  set, shift widths, mapper arithmetic-shift lowering, or rounding contract
  changes materially.

## Hypothesis H070

- **ID:** H070.
- **Hypothesis:** the restoring divider needs exactly 24 active iterations.
  The 24-state maximal-LFSR segment
  `12 -> 25 -> 19 -> ... -> 8 -> 16 -> 1` preserves that latency, keeps zero
  idle and one terminal, and replaces the five-bit binary decrement carry chain
  with one XOR and a shift.
- **Scope:** exhaustive state/latency proof, sequential SAT of every public
  divider output, and isolated complete-service synthesis; conditional
  production `rtl/psg_divsvc.sv`, permanent hardware form, whole-PSG mapping,
  and complete H069 battery. No dividend step, quotient, remainder, request,
  schedule, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus H016 and H051:** H016 changed the restoring
  subtract width and is closed; H070 leaves the divider datapath untouched and
  changes only its iteration token. H051 proved the same controller principle
  for a five-step detune service; H070 independently proves a distinct 24-step
  divider service with different width, recurrence, latency, and consumers.
- **Change:** scratch form loads count 12, advances
  `{count[3:0], count[4] ^ count[2]}`, and returns to zero after terminal state
  one. The current 24-to-one binary countdown is the reference.
- **Result:** exhaustive comparison proves all 50 idle/active input transitions
  and the exact 24-state sequence. Combinational SAT proves the mapped count,
  busy, quotient/remainder state, divisor state, load, and arithmetic-step next
  relations for every reachable count and arbitrary operands. The complete
  isolated divider improves 51 -> 50 LUT4s and 12 -> 9 carries with 45 flops
  unchanged. Whole-PSG synthesis is unfavorable: 6,456 -> 6,479 LUT4s,
  1,370 -> 1,363 carries, 1,459 flops and 503 unpackable flops unchanged,
  floor 6,959 -> 6,982, and seed-1 route 7,199 -> 7,216 LCs. Timing passes at
  131.94/32.06 MHz, but deterministic floor and placement both regress.
- **Decision:** rejected and reverted byte-for-byte. The isolated controller
  saving perturbs the full divider/consumer packing and violates both physical
  area gates, so the complete fidelity battery is not warranted.
- **Repeat only if:** if rejected, retry only after divider iteration count,
  request/terminal timing, counter width, or mapper LFSR/decrement lowering
  changes materially.

## Hypothesis H071

- **ID:** H071.
- **Hypothesis:** for signed 24-bit `v`, truncation toward zero after division
  by 64 is exactly `(v >>> 6) + (v < 0 && v[5:0] != 0)`. Applying that
  correction after the shift in the blend consumer should replace its
  conditional 24-bit `+63` with one remainder reduction and a narrower
  increment while preserving every bit.
- **Scope:** exhaustive NumPy and Yosys proof plus isolated synthesis of the
  complete registered blend consumer; conditional production
  `rtl/psg_walk.sv`, permanent `tools/psg_hw_forms.py` proof, whole-PSG
  mapping, and complete H069 fidelity/physical battery. No blend coefficient,
  schedule, state, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus H055 and H069:** H055 changed the two noise-step
  sign limbs and is closed. H069 proved the same rounding identity for five
  18-bit waveform shifts of zero through three; H071 applies it to a distinct
  24-bit blend result shifted by six, whose existing conditional `+63` remains
  source-visible and mapped.
- **Change:** replace `bl_acc + (negative ? 63 : 0)` followed by `>>> 6` with
  the arithmetic-shifted quotient plus one only for a negative nonzero six-bit
  remainder.
- **Result:** all 16,777,216 signed-24 values pass the global-NumPy exhaustive
  identity check, and Yosys proves all 83 points in the complete registered
  consumer. Isolated synthesis improves 137 -> 129 LUT4s and 78 -> 72 carries
  with 17 flops unchanged. The first whole-PSG spelling maps to 6,508 LUT4s,
  1,365 carries, 1,459 flops, 502 unpackable flops, and a 7,010-cell floor:
  versus H069 that is +52 LUT4s, -5 carries, and +51 floor cells. A second
  name-preserving spelling maps to 6,482 LUT4s, 1,364 carries, the same flops,
  and a 6,984-cell floor: still +26 LUT4s, -6 carries, and +25 floor cells.
- **Decision:** rejected and reverted byte-for-byte. Both allowed spellings
  violate the deterministic LUT/floor gate, so routing and the complete
  fidelity battery are not warranted.
- **Repeat only if:** if rejected, retry only after blend accumulator width,
  division/rounding contract, mapper shift/add lowering, or blend consumer
  topology changes materially.

## Hypothesis H072

- **ID:** H072.
- **Hypothesis:** dampen modes one and two/three truncate the signed 19-bit
  `dmp_acc` toward zero after division by two or four. Selecting the arithmetic
  shift first, then adding one only for a negative discarded remainder, is
  exactly equivalent to the current mode-selected pre-shift bias of one or
  three and may remove the wide conditional adder.
- **Scope:** exhaustive NumPy and Yosys proof plus isolated synthesis of the
  complete registered dampen consumer; conditional production
  `rtl/psg_walk.sv`, permanent `tools/psg_hw_forms.py` proof, whole-PSG
  mapping, and complete H069 fidelity/physical battery. No dampen coefficient,
  mode, schedule, state, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus H069 and H071:** H069 proved five signed-18
  waveform shifts of zero through three. H071's distinct signed-24 blend `/64`
  consumer is closed after global regressions. H072 targets the still-mapped
  signed-19 dampen consumer, with a two-mode selected shift and remainder width.
- **Change:** replace the mode-selected negative `+1`/`+3` followed by fixed
  slices with a selected arithmetic quotient plus one for a negative nonzero
  one- or two-bit remainder.
- **Result:** all 1,572,864 signed-19/mode tuples pass the global-NumPy
  exhaustive identity check, and Yosys proves all 89 points in the complete
  registered consumer. Isolated synthesis keeps 121 LUT4s and 17 flops while
  reducing 52 -> 50 carries. Whole-PSG synthesis maps to 6,482 LUT4s, 1,365
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, and a 6,983-cell floor.
  Versus H069 that is +26 LUT4s, -5 carries, and +24 floor cells.
- **Decision:** rejected and reverted byte-for-byte. The carry reduction does
  not compensate for the deterministic LUT/floor regression, so routing and
  the complete fidelity battery are not warranted.
- **Repeat only if:** if rejected, retry only after dampen accumulator width,
  mode contract, mapper shift/add lowering, or dampen consumer topology changes
  materially.

## Hypothesis H073

- **ID:** H073.
- **Hypothesis:** the shared noise-product operand is `8*dp + 1120`, and
  `1120 = 140*8`. Spelling it as the concatenation of the exact 14-bit
  `dp + 140` sum and three zero bits should remove three dead low positions
  from the mapped adder while simplifying the arithmetic contract.
- **Scope:** exhaustive/Yosys proof and isolated synthesis of the complete
  registered noise-request operand consumer; conditional production
  `rtl/psg_walk.sv`, permanent `tools/psg_hw_forms.py` proof, whole-PSG
  mapping, and complete H069 fidelity/physical battery. No noise distribution,
  multiplier request timing, schedule, state, interface, EBR, R.84 executor,
  or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition:** no prior continuation hypothesis rewrites the aligned
  `nz_j_req` offset. The noise-product scheduling and two-context operand
  sharing are unchanged; this tests only the source width of its surviving
  constant addition.
- **Change:** replace `{1'b0, nz_dp_req, 3'b0} + 17'd1120` with
  `{1'b0, nz_dp_req + 14'd140, 3'b0}`.
- **Result:** all 8,192 increments pass the exhaustive identity check, and
  Yosys proves all 42 points in the complete registered consumer. Both forms
  map identically at 11 LUT4s, ten carries, and 14 flops.
- **Decision:** rejected before production because Yosys already removes the
  three aligned low positions. No production or permanent-proof file changed,
  and no whole-PSG/fidelity gate is warranted.
- **Repeat only if:** if rejected, retry only after noise-product operand width,
  constant offset, multiplier request interface, or mapper aligned-add lowering
  changes materially.

## Hypothesis H074

- **ID:** H074.
- **Hypothesis:** the affine slide path retains only bits 29:12 of
  `r + frac*b_lo`, then adds the second product and discards another 17 bits.
  Omitting the first sum's low-12 carry changes the intermediate high limb by
  at most one; if that unit never crosses the final boundary over the complete
  reachable pitch/fraction domain, the source can replace its 30-bit add with
  one exact 18-bit high-limb add.
- **Scope:** exhaustive proof over all 64 pitches and 65,536 fractions using
  the permanent affine table/model; conditional isolated synthesis of the
  complete two-pass registered consumer, production `rtl/psg_seq.sv`,
  permanent `tools/psg_hw_forms.py` proof, whole-PSG mapping, and complete H069
  battery. No slide table, output increment, octave rule, schedule, state,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus H023:** H023 changes only the six-bit octave and
  chromatic decode after interpolation. H074 leaves that accepted decode
  untouched and tests a previously unpriced precision boundary inside the
  two-pass affine interpolation itself.
- **Change:** compute the retained first limb from `r[28:12] + product[27:12]`
  without the carry from their low 12 bits, then leave the second accumulation
  and octave shift unchanged.
- **Result:** exhaustive reachable-domain checking finds the first
  counterexample at pitch two, fraction 9,668: current second-stage input
  2,097,152 versus carry-dropped 2,097,151, producing increment 220 versus 219.
- **Decision:** rejected before isolated or production synthesis because the
  low-12 carry is observably required. No production or permanent-proof file
  changed, and no physical/fidelity gate is warranted.
- **Repeat only if:** if rejected, retry only after affine-table coefficients,
  first/second discard positions, reachable fraction domain, or slide
  interpolation contract changes materially.

## Hypothesis H075

- **ID:** H075.
- **Hypothesis:** wavetable interpolation currently conditionally negates the
  unsigned multiplier magnitude, then adds that signed product to the shifted
  table base. XORing the magnitude operand with its sign and using that sign as
  the addition carry-in is the exact two's-complement add/sub form and should
  replace the negate and sum carry chains with one.
- **Scope:** exhaustive/formal proof and isolated synthesis of the complete
  registered wavetable interpolation consumer; conditional production
  `rtl/psg_walk.sv`, permanent `tools/psg_hw_forms.py` proof, whole-PSG mapping,
  and complete H069 fidelity/physical battery. No multiplier request, product
  slice, interpolation fraction, table value, schedule, state, interface, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted direct H069 commit `d3ce9a6`: 6,456 LUT4s, 1,370
  carries, 1,459 flops, 503 unpackable flops, 14 EBRs, 6,959-cell floor,
  seed-1 7,199 LCs; 133.69 MHz fast and 32.82 MHz PSG.
- **Changed condition versus the historical blend update and H040:** the older
  blend consolidation operated on a 17/24-bit crossfade path and regressed
  placement; H040 changed organ-ramp complement semantics. H075 instead targets
  the distinct 20-bit wavetable base-plus-magnitude consumer whose separate
  product negate remains mapped before the sum.
- **Change:** replace signed `+/-m_res[20:2]` publication followed by the base
  add with `base + (magnitude XOR sign-mask) + sign`.
- **Result:** the global NumPy proof exhausts all 1,048,576 magnitude/sign
  tuples, the Yosys equivalence proof covers all 35 registered-consumer points,
  and the permanent full hardware forms pass. The complete isolated registered
  consumer falls from 61 to 36 LUT4s and 27 to 19 carries with 17 flops
  unchanged. Full and PREVIEW lint, `make test-psg`, the 59/59 frozen render
  regression, ordinary and multipumped `/4`--`/6` cadence, `make test-clocks`,
  all eight PREVIEW checks, synthetic/Celeste recovery, and exact SFX-10
  hardware/PREVIEW click checks pass. Same-tool H069 and H075 SFX-10 PREVIEW
  renders are byte-identical; the stored H069 PREVIEW WAV retains its known
  one-launch-sample historical tool offset. The five-frame Celeste smoke is
  unchanged at 2,179/3,668 off-centre samples, range -22,013..9,151, and 1,068
  distinct levels. Strict OpenSpec validation, `py_compile`, diff/scope audits,
  and a second forced canonical synthesis all pass; both JSON and ASC artifacts
  are bit-identical.
- **Physical result:** H069 to H075 changes 6,456 to 6,433 LUT4s, 1,370 to
  1,362 carries, 1,459 flops unchanged, 503 to 501 unpackable flops, 14 EBRs
  unchanged, and the deterministic floor from 6,959 to 6,934. Seed-1 routing
  changes 7,199 to 7,173 LCs and routed clocks 133.69/32.82 to 138.48/33.55
  MHz. The durable claim is -23 LUT4s, -8 carries, -2 unpackable flops, and
  -25 floor cells; the -26 routed LCs remain below placement sensitivity.
- **Decision:** accepted as direct commit `c634db2`. The source is shorter,
  exposes the exact add/sub contract, improves every deterministic area metric
  without an FF or EBR regression, and passes the complete H069 battery.
- **Repeat only if:** if rejected, retry only after wavetable product width,
  product landing slice, interpolation base width, or mapper add/sub lowering
  changes materially.

## Hypothesis H076

- **ID:** H076.
- **Hypothesis:** the current tilted-saw affine forms first build `3*x`, then
  evaluate `3*x-ceil(x/2048)` on the low branch or `6*x-ceil(x/1024)` on the
  high branch. Reassociating them as `2*x + (x-ceil)` and
  `4*x + (2*x-ceil)` preserves every bit while narrowing the first chain from
  the 18-bit `3*x` add to a branch-selected add/subtract no wider than 17 bits.
- **Scope:** exhaustive proof over all 65,536 ramp values and both tilt modes,
  then isolated synthesis of the complete registered tilt consumer. Production
  `rtl/psg_wave.sv`, a permanent `tools/psg_hw_forms.py` check, whole-PSG
  mapping, and the complete H075 battery are conditional on an isolated
  deterministic improvement. No ceiling value, ramp/tail selection,
  reciprocal address/table/recombine, pipeline stage, waveform output,
  schedule, state, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG.
- **Changed condition versus H001 and H074:** H001 retained the exact narrow
  ceiling boundary but did not alter the surrounding affine chains; H076 keeps
  that accepted ceiling and reassociates the full tilted-saw consumer. H074
  concerned a distinct slide interpolation carry whose removal was inexact;
  H076 drops no carry or precision and is an algebraic identity.
- **Change:** conditionally replace `3*x` followed by scale/subtract with the
  exact narrow subtract limb followed by one shifted add.
- **Result:** exhaustive comparison proves both branches over all 131,072
  actual mode/phase tuples and proves the first limb fits unsigned 17 bits.
  The complete isolated registered tilt consumer falls from 129 to 117 LUT4s
  and 69 to 68 carries with 28 flops unchanged. Canonical whole-PSG mapping
  instead changes H075's 6,433 LUT4 / 1,362 carry / 1,459 FF / 501 unpackable
  / 14 EBR / 6,934 floor to 6,438 / 1,361 / 1,459 / 502 / 14 / 6,940.
  Routing and the complete fidelity battery are correctly skipped after the
  deterministic LUT4, unpackable-flop, and floor gates fail. Production RTL
  and the conditional permanent form are restored byte-for-byte.
- **Decision:** rejected after whole-PSG mapping. The narrower first chain is
  exact and locally smaller, but its reassociated mux/adder covering is
  globally worse on the H075 frontier.
- **Repeat only if:** if rejected, retry only after the tilted-saw affine
  coefficients, ceiling boundaries, ramp width, reciprocal input contract, or
  mapper add/sub lowering changes materially.

## Hypothesis H077

- **ID:** H077.
- **Hypothesis:** the tilt pipeline forms `t_ix7 = t_pre[18:9] + t_pre[8:0]`
  and `t_ix15 = t_pre[18:8] + t_pre[7:0]` in parallel, but `tilt_hi` selects
  exactly one reciprocal family. Selecting those narrow operands first and
  evaluating one zero-extended 11-bit sum should retire the unused 10-bit
  carry chain while preserving every reciprocal address bit.
- **Scope:** exhaustive comparison of the shared index and every derived
  `/7`/`/15` address field over all 19-bit `t_pre` values and both tilt modes,
  then isolated synthesis of the complete registered tilt consumer. Production
  `rtl/psg_wave.sv`, a permanent `tools/psg_hw_forms.py` check, whole-PSG
  mapping, and the complete H075 battery are conditional on an isolated
  deterministic improvement. No tilted-saw affine value, ceiling, reciprocal
  table/content/recombine, pipeline stage, waveform output, schedule, state,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG.
- **Changed condition versus H067 and reciprocal-coefficient factoring:** H067
  tried to reconstruct two registered quotient views from a shared source
  prefix and mapped identically. H077 leaves both registered quotient views
  intact and instead replaces the two following mutually exclusive index
  adders with one operand-selected adder; it does not alter or factor the
  downstream reciprocal coefficient network.
- **Change:** replace parallel `t_ix7`/`t_ix15` additions with one 11-bit sum
  over mode-selected zero-extended operands, then take the existing mode's
  high/remainder slices from that sum.
- **Result:** exhaustive comparison covers all 1,048,576 combinations of the
  19-bit source and both tilt modes, including the current 10/11-bit native
  wrap, and proves every selected high field, remainder field, and eight-bit
  reciprocal address identical. The complete isolated registered tilt
  consumer maps identically in both forms at 129 LUT4s, 69 carries, and 28
  flops. Production RTL and the permanent form are correctly skipped.
- **Decision:** rejected before production. Yosys already folds the exclusive
  parallel index expressions into the same mapped network, so the explicit
  shared adder offers no deterministic resource or source-simplicity win.
- **Repeat only if:** if rejected, retry only after the reciprocal fold width,
  `/7` or `/15` index split, tilt-mode exclusivity, pipeline boundary, or
  mapper operand-selection lowering changes materially.

## Hypothesis H078

- **ID:** H078.
- **Hypothesis:** the full-schedule soft-add engine probes `s - 24576` and, only
  when that is negative, probes `-24576 - s`. The sign of the registered sum
  already selects the only relevant orientation, so evaluating `s - 24576`
  for nonnegative sums or `-24576 - s` for negative sums in one state should
  preserve the exact excess while removing the second probe state and its
  operand/control decode.
- **Scope:** exhaustive algebraic comparison over the complete registered-sum
  domain, sequential/form proof over every legal signed-16 operand pair, then
  isolated synthesis of the complete registered soft-add fold engine.
  Production `rtl/psg_walk.sv`, a permanent `tools/psg_hw_forms.py` check,
  whole-PSG mapping, and the complete H075 battery are conditional on an
  isolated deterministic improvement. No soft-add threshold, `/5` quotient,
  rounding, reduction-tree order, leaf value, EBR content, sample schedule,
  state-memory contract, interface, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG.
- **Changed condition versus H040/H071/H072:** those rows changed organ-fold,
  blend-rounding, or dampen-rounding arithmetic. H078 leaves all three paths
  untouched and targets the distinct serialized mixer soft-add controller;
  it changes neither the compressed value nor the existing base-256 `/5`
  implementation.
- **Change:** capture the sum sign with the first add, select the positive or
  negative threshold-subtract orientation in the next state, and branch from
  that single result to the unchanged quotient path or linear completion. The
  negative-path state remains as a timing-only token so controller latency is
  unchanged.
- **Result:** exhaustive inspection of all 262,144 registered sums finds the
  baseline's modular first probe wraps across the illegal tail
  -131,072..-106,497. Actual leaves are signed-16, their pair sum is bounded to
  -65,536..65,534, and the existing soft-add maps that complete interval back
  into signed-16; the sign-selected form is exact and cycle-identical
  throughout that inductive domain. Yosys SAT proves the registered threshold
  controller over all 4,294,967,296 signed-16 operand pairs, and the existing
  quotient construction matches exact `/5` over all 131,072 excess values.
  The complete registered fold engine instead changes 336 to 342 LUT4s, with
  25 carries, 66 flops, and one EBR unchanged. Production RTL, permanent forms,
  whole-PSG synthesis, routing, and fidelity gates are correctly skipped.
- **Decision:** rejected before production. The exact sign-selected operand
  mux costs more than the removed arithmetic probe decode in the complete
  registered consumer.
- **Repeat only if:** if rejected, retry only after the soft-add threshold,
  fold operand width, quotient implementation, controller pipeline, or mapper
  operand-selection lowering changes materially.

## Hypothesis H079

- **ID:** H079.
- **Hypothesis:** both reverb combs implement signed round-toward-zero `/2` by
  adding a full-width one to every negative 19-bit accumulator before taking
  bits `[17:1]`. After the arithmetic shift, only a negative odd accumulator
  needs correction; moving that one-bit correction after the shift should
  replace two 19-bit bias carry chains with two narrower incrementers.
- **Scope:** exhaustive/formal proof over both complete comb input domains,
  then isolated synthesis of the complete registered dual-comb and blend-
  difference consumer. Production `rtl/psg_walk.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H075
  battery are conditional on an isolated deterministic improvement. No reverb
  tap, enable, ring memory, blend arithmetic, dampen arithmetic, multiplier
  request, schedule, state, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG.
- **Changed condition versus historical comb sharing and H069/H071/H072:** the
  earlier comb experiment tried to share the live/old networks and correctly
  found no realizable saving. H079 keeps both parallel combs and changes only
  their identical fixed-shift rounding identity. H069 changed the shared
  variable-shift waveform helper; H071 and H072 changed blend and dampen
  rounding, which remain byte-for-byte untouched here.
- **Change:** replace each `acc + sign` pre-shift bias with the exact arithmetic
  half plus `sign & odd`, retaining the existing 17-bit landing slice.
- **Result:** exhaustive comparison proves the identity for all 524,288
  signed-19 accumulators and confirms the declared dual-comb input range
  -163,840..163,837 cannot overflow. SAT independently proves both complete
  signed-17 sample by signed-16 tap input domains. The complete registered
  dual-comb/blend-difference consumer changes 139 LUT4s unchanged, 85 to 83
  carries, and 52 flops unchanged. Canonical whole-PSG mapping instead changes
  H075's 6,433 LUT4 / 1,362 carry / 1,459 FF / 501 unpackable / 14 EBR / 6,934
  floor to 6,465 / 1,358 / 1,459 / 501 / 14 / 6,966. Seed-1 routing changes
  7,173 to 7,198 LCs and routed clocks 138.48/33.55 to 118.06/31.24 MHz; both
  clocks still pass. The deterministic LUT/floor gates reject the candidate,
  so the complete fidelity battery is correctly skipped and both production
  files are restored byte-for-byte.
- **Decision:** rejected after whole-PSG mapping. The four-carry global saving
  does not compensate for 32 added LUT4s/floor cells; the 25-LC route increase
  remains below placement sensitivity and is not a durable claim.
- **Repeat only if:** if rejected, retry only after reverb accumulator width,
  tap width, rounding rule, comb enable/consumer, or mapper increment lowering
  changes materially.

## Hypothesis H080

- **ID:** H080.
- **Hypothesis:** the fractional sample clock updates one signed accumulator by
  subtracting `CLK_HZ - 22050` when nonnegative and adding `22050` when
  negative. The accepted H075 netlist contains a separate 23-carry chain for
  each branch. Selecting the signed constant first and applying one shared
  addition should preserve the exact recurrence while allowing one physical
  update chain to replace both.
- **Scope:** exhaustive and symbolic proof over the complete signed accumulator
  domain, then isolated synthesis of the complete registered `psg_timing`
  consumer. Production `rtl/psg_timing.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H075
  battery are conditional on an isolated deterministic improvement. No clock
  frequency, sample rate, accumulator width, reset value, 183-sample cadence,
  tick delay, pre-tick timing, schedule, state, interface, EBR, R.84 executor,
  or tolerance change.
- **Baseline:** accepted direct H075 commit `c634db2`: 6,433 LUT4s, 1,362
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,934-cell floor,
  seed-1 7,173 LCs; 138.48 MHz fast and 33.55 MHz PSG. Its mapped netlist
  attributes 23 carries to each of `psg_timing.sv`'s two accumulator-update
  branches.
- **Changed condition versus H007--H010:** H007 accepted only a
  `CLK_HZ`-derived accumulator width; H008 tested sharing the two sample-count
  terminal equalities; H009 and H010 changed the delayed tick representation.
  H080 preserves all of those accepted or retained structures and changes only
  the arithmetic spelling of the already width-bounded fractional accumulator
  update.
- **Change:** select `DIV_UP` or `-DIV_DOWN` from the current accumulator sign,
  then assign `divd + selected_delta` once outside the branch that controls
  sample and tick side effects.
- **Result:** exhaustive checking passes all 67,108,864 canonical signed
  accumulator states and the symbolic SAT miter proves the two update forms
  equivalent. The complete isolated registered `psg_timing` consumer falls
  from 86 to 45 LUT4s and 52 to 29 carries with its flops unchanged. Full
  hardware forms, full and PREVIEW lint, `make test-psg` including all 93
  analysis tests and the structural PSG test, 59/59 frozen renders, ordinary
  and multipumped `/4`--`/6` cadence, clock tests, all eight PREVIEW checks,
  synthetic/Celeste recovery, and hardware/PREVIEW SFX-10 click checks pass.
  A clean H075 PREVIEW rebuild is byte-identical to H080 at SHA-256
  `e2dcf238ef7ae0cc8d56d7a557e64d4c34d761b07cd331a7039aed00e2dba03a`;
  the earlier one-sample offset was a stored-artifact/tool-history issue. The
  five-frame Celeste smoke retains the exact H075 activity signature. Strict
  OpenSpec validation, permanent forms under the global NumPy installation,
  `py_compile`, diff/scope audits, and a second forced canonical synthesis all
  pass; both JSON and ASC artifacts are bit-identical.
- **Physical result:** H075 to H080 changes 6,433 to 6,409 LUT4s, 1,362 to
  1,339 carries, 1,459 flops and 501 unpackable flops unchanged, 14 EBRs
  unchanged, and the deterministic floor from 6,934 to 6,910. Seed-1 routing
  changes 7,173 to 7,147 LCs and routed clocks 138.48/33.55 to 134.44/32.36
  MHz. Both clocks remain above their 112.50/18.75-MHz constraints. The durable
  claim is -24 LUT4s, -23 carries, and -24 floor cells; the -26 routed LCs
  remain below placement sensitivity.
- **Decision:** accepted as direct commit `6458450`. The source exposes one
  exact recurrence update, improves every deterministic area metric without
  an FF or EBR regression, and passes the complete H075 battery.
- **Repeat only if:** if rejected, retry only after the sample-accumulator
  width, clock/sample constants, update consumer, or mapper constant-selection
  lowering changes materially.

## Hypothesis H081

- **ID:** H081.
- **Hypothesis:** slide interpolation currently maps a 30-bit first
  accumulation consumed only at K_SL6 and a separate 26-bit second
  accumulation consumed only at K_SL8. Zero-extending the second operands and
  selecting both operand pairs before one 30-bit add should preserve both exact
  sums while allowing their mutually exclusive carry chains to share one
  physical datapath.
- **Scope:** exhaustive and symbolic proof of both full-width sums, then
  isolated synthesis of the complete registered slide consumer including the
  state selector and final table-base addition. Production `rtl/psg_seq.sv`,
  a permanent `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete
  H080 battery are conditional on an isolated deterministic improvement. No
  slide coefficient, product slice, carry, rounding, table word, state,
  schedule, register, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The mapped netlist
  attributes 29 carries to the 30-bit K_SL6 sum and 25 carries to the 26-bit
  K_SL8 sum before the retained 13-bit final table-base addition.
- **Changed condition versus H074:** H074 removed the low-12 carry from the
  first slide accumulation and changed a reachable published increment. H081
  drops no precision or carry; it preserves both original sums and exploits
  their already scheduled K_SL6/K_SL8 mutual exclusivity.
- **Change:** select `{crom_q, sl_rlo}` versus zero-extended `sl_uhi` and the
  corresponding 28-bit versus 26-bit multiplier result before one 30-bit add;
  consume its full first result at K_SL6 and its low 26-bit second result at
  K_SL8 exactly as before.
- **Result:** Yosys SAT proves both selected results for every value of the
  76-bit input/selector domain. In the complete registered slide consumer, the
  baseline maps to 39 LUT4s, 66 carries, and 31 flops; the candidate maps to 59
  LUT4s, 41 carries, and 31 flops. The selected-operand mux removes 25 carries
  but adds 20 LUT4s and therefore 20 deterministic floor cells.
- **Decision:** rejected before production or whole-PSG synthesis. The LC-area
  gate is already decisively worse in the complete isolated consumer;
  `rtl/psg_seq.sv` and permanent proof files remain byte-identical to H080 and
  no fidelity or route claim is warranted.
- **Repeat only if:** if rejected, retry only after slide-accumulator widths,
  K_SL6/K_SL8 scheduling, retained register boundaries, final table-base
  consumer, or mapper selected-operand lowering changes materially.

## Hypothesis H082

- **ID:** H082.
- **Hypothesis:** `sl_bhi` is last consumed as the K_SL6 multiplier operand and
  `sl_rlo` is last consumed by the K_SL6 first accumulation. Nonblocking
  assignments read both old values on that edge, so their now-dead
  `{sl_bhi[1:0], sl_rlo}` storage can capture the 18-bit first result for K_SL8
  and retire the dedicated `sl_uhi` register without changing either adder.
- **Scope:** source-use audit, arbitrary-defined-state sequential proof across
  K_SL4--K_SL8, then isolated synthesis of the complete registered slide
  consumer. Production `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H080
  battery are conditional on an isolated deterministic improvement. No slide
  arithmetic, coefficient, product slice, carry, rounding, table word, state,
  schedule, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The dedicated
  `sl_uhi` register is 18 flops; the source audit finds no `sl_bhi`, `sl_rlo`,
  or `sl_uhi` consumer outside their K_SL4--K_SL8 production/capture path.
- **Changed condition versus H081:** H081 retained all registers and added a
  selected-operand mux to share the two adders, which cost 20 isolated floor
  cells. H082 retains both original adders and changes only the non-overlapping
  storage allocation after both source operands are consumed.
- **Change:** at the existing K_SL6 capture edge assign the exact
  `sl_u[29:12]` result to `{sl_bhi[1:0], sl_rlo}`; form K_SL8's second sum from
  that concatenation and remove `sl_uhi`.
- **Result:** the source-use audit finds the expected closed K_SL4--K_SL8
  lifetime, SAT proves the same-edge storage transform for all arbitrary source,
  product, and final-table inputs, and exhaustive permanent checking covers all
  262,144 18-bit intermediate values. The complete isolated registered
  consumer changes 39 to 59 LUT4s, 66 carries unchanged, 65 to 47 flops, 35 to
  16 unpackable flops, and floor 74 to 75. Full and PREVIEW lint pass. In the
  whole PSG, H080 to H082 changes 6,409 to 6,437 LUT4s, 1,339 to 1,335 carries,
  1,459 to 1,441 flops, 501 to 483 unpackable flops, and floor 6,910 to 6,920;
  14 EBRs are unchanged. Seed-1 routing changes 7,147 to 7,145 LCs and clocks
  134.44/32.36 to 142.57/32.72 MHz. The two-LC route change is below placement
  sensitivity and cannot offset the ten-cell deterministic floor regression.
- **Decision:** rejected and reverted byte-for-byte before the fidelity
  battery. Production `rtl/psg_seq.sv` and permanent `tools/psg_hw_forms.py`
  are identical to H080; no render or integration claim remains.
- **Repeat only if:** if rejected, retry only after the K_SL4--K_SL8 register
  lifetimes, first-result width, source-register packing, or mapper same-edge
  overwrite lowering changes materially.

## Hypothesis H083

- **ID:** H083.
- **Hypothesis:** the live gain first optionally evaluates
  `a = x + floor(x/4)`, then always returns `a + floor(a/2)`. For boosted gain
  this is exactly `2*x - ceil(x/8) - corr`, where `corr` is one only for
  `x[2:0]` equal to 3, 6, or 7; unboosted gain remains
  `x + floor(x/2)`. Selecting the base and signed correction before one
  add/sub chain should replace the two current carry chains.
- **Scope:** exhaustive proof over all 4,096 input gains and both boost states,
  symbolic proof of the selected add/sub form, then isolated synthesis of the
  complete registered gain consumer. Production `rtl/psg_walk.sv`, a
  permanent `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete
  H080 battery are conditional on an isolated deterministic improvement. No
  gain input, boost predicate, multiplier request, scaling, sign, schedule,
  state, register, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The current gain cone
  contains the optional 13-bit 5/4 sum followed by the 13-bit 3/2 sum.
- **Changed condition versus H017:** H017 selected old/new waveform and sign
  context before the post-multiply scale/negate consumers and regressed global
  destination covering. H083 leaves those contexts and consumers untouched;
  it targets a distinct pre-multiply arithmetic identity inside `g_live`.
- **Change:** derive the boosted residue correction from the low three gain
  bits, select `x` versus `2*x` as the base and `floor(x/2)` versus the exact
  negative boosted correction as the second operand, then use one add/sub
  carry chain.
- **Result:** exhaustive checking passes all 8,192 input/boost states and Yosys
  SAT proves the selected add/sub form over the full bit-vector domain. The
  complete registered baseline maps to 26 LUT4s, 24 carries, and 13 flops; the
  candidate maps to 47 LUT4s, 21 carries, and 13 flops.
- **Decision:** rejected before production. The exact residue correction saves
  only three carries while adding 21 deterministic LUT4/floor cells;
  `rtl/psg_walk.sv` and permanent proof files remain byte-identical to H080 and
  no whole-PSG, fidelity, or route claim is warranted.
- **Repeat only if:** if rejected, retry only after the live-gain width/domain,
  boost predicate, multiplier-request consumer, or mapper selected add/sub
  lowering changes materially.

## Hypothesis H084

- **ID:** H084.
- **Hypothesis:** `scnt` is an eight-bit binary counter whose only observable
  values are 3 (sequencer pending-tick release), 176 (`pre_tick`), and 182
  (tick publication/reset). A 183-state prefix of an eight-bit maximal LFSR can
  preserve those exact sample events while replacing the binary increment
  carry chain with one XOR feedback bit and three constant-token decodes.
- **Scope:** exhaustive token-sequence proof, clock-for-clock recurrence/cadence
  comparison across reset and multiple tick periods, then isolated synthesis
  of the complete registered `psg_timing` consumer plus the logical-three
  decode. Production `rtl/psg_timing.sv`, the one `rtl/psg_seq.sv` consumer, a
  permanent `tools/psg_hw_forms.py` check, whole-PSG
  mapping, and the complete H080 battery are conditional on an isolated
  deterministic improvement. No sample rate, fractional accumulator, 183-
  sample period, pre-tick offset, tick delay, state, schedule, external
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. H080's complete
  `psg_timing` scope maps to 55 LUT4s, 29 carries, 38 flops, two unpackable
  flops, and 57 floor cells; the remaining `scnt + 1` owns a seven-carry chain.
- **Changed condition versus H008 and H070:** H008 retained binary `scnt` and
  tested sharing its two terminal equalities. H070 replaced a distinct 24-step
  divider-service count whose busy/done/control consumers caused a global
  regression. H084 targets a wider decode-only counter with exactly three
  sparse internal observable tokens and no published numeric count.
- **Change:** seed an eight-bit maximal LFSR at token `8'h01`, advance it once
  per `sample_en`, substitute the token corresponding to logical 3 at the one
  sequencer consumer, assert `pre_tick` at the logical-176 token, and reset it
  to the seed at the logical-182 token.
- **Result:** the corrected source audit finds exactly three consumers at
  logical counts 3, 176, and 182. The maximal-period proof establishes all 255
  unique LFSR states and exact tokens 08/e9/66; simulation matches 3,660 sample
  states clock-for-clock across 20 periods. The complete isolated timing plus
  logical-three consumer changes 45 to 43 LUT4s and 26 to 20 carries with its
  flops unchanged. Full hardware forms and full/PREVIEW lint pass. In the whole
  PSG, H080 to H084 changes 6,409 to 6,435 LUT4s, 1,339 to 1,333 carries,
  1,459 flops unchanged, 501 to 507 unpackable flops, and floor 6,910 to 6,942;
  14 EBRs are unchanged. Seed-1 routing changes 7,147 to 7,175 LCs and clocks
  134.44/32.36 to 136.44/32.69 MHz.
- **Decision:** rejected and reverted byte-for-byte before the fidelity
  battery. The local two-LUT/six-carry win becomes a decisive 32-cell global
  floor and 28-LC route regression. Production `rtl/psg_timing.sv`,
  `rtl/psg_seq.sv`, and permanent `tools/psg_hw_forms.py` are identical to
  H080; no render or integration claim remains.
- **Repeat only if:** if rejected, retry only after the sample-count period,
  observable token set, counter width, timing consumer, or mapper LFSR/decode
  lowering changes materially.

## Hypothesis H085

- **ID:** H085.
- **Hypothesis:** a ceiling division currently sends `n + d - 1` through the
  24-by-8 divider. Dividing unbiased `n = q*d + r` produces the same biased
  outputs as quotient `q + (r != 0)` and remainder
  `r == 0 ? d - 1 : r - 1`. Applying that exact correction after the fixed
  recurrence should replace the two wide pre-service numerator chains with
  arithmetic bounded by the actually consumed quotient and eight-bit
  remainder.
- **Scope:** symbolic quotient/remainder identity proof for arbitrary 24-bit
  numerator and nonzero eight-bit divisor, transaction-level divider proof,
  then isolated synthesis of the complete divider plus all caller-observable
  result slices. Production `rtl/psg_divsvc.sv`, `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H080
  battery are conditional on an isolated deterministic improvement. No
  numerator value, quotient, remainder, divisor, 24-cycle latency, start/busy
  contract, state, schedule, interface width, EBR, R.84 executor, or tolerance
  change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The mapped caller
  attributes 23 carries to the 24-bit numerator sum and seven more to its
  selected `d-1`, before the retained nine-carry divider subtract.
- **Changed condition versus H016 and H070:** H016 narrowed the restoring
  subtract itself and regressed globally; H070 recoded only the divider's
  iteration counter. H085 retains both the accepted subtract and binary count,
  changing only where the already-required ceiling quotient/remainder transform
  is evaluated.
- **Change:** pass unbiased `div_base` plus the ceiling flag into the divider;
  retain the flag through the transaction and expose the exact corrected
  quotient/remainder when idle, leaving non-ceiling transactions unchanged.
- **Result:** 97,920 divisor/remainder/quotient-boundary states, an all-domain
  SAT transform proof, and 1,530 complete divider transactions pass. The
  complete registered baseline maps to 84 LUT4s, 42 carries, 45 flops, eight
  unpackable flops, and floor 92. Direct combinational output correction maps
  to 93 LUT4s, 33 carries, 46 flops, nine unpackable flops, and floor 102.
  Moving the same exact correction onto the terminal recurrence edge passes a
  second 1,530 transactions but maps to 116 LUT4s, 41 carries, 46 flops, nine
  unpackable flops, and floor 125.
- **Decision:** rejected after two isolated variants, before production. The
  correction arithmetic does not pack into the existing result boundary;
  `rtl/psg_divsvc.sv`, `rtl/psg_seq.sv`, and permanent proof files remain
  byte-identical to H080, and no whole-PSG, fidelity, or route claim is
  warranted.
- **Repeat only if:** if rejected, retry only after caller result widths,
  rounding modes, remainder consumers, divider recurrence/latency, or mapper
  output-correction lowering changes materially.

## Hypothesis H086

- **ID:** H086.
- **Hypothesis:** EA5 increments `w_row` when `abank` is clear and
  `w_ins_row` when it is set. Those five-bit values and destinations are
  mutually exclusive, so selecting the source before one incrementer should
  replace two carry chains while preserving each inactive register exactly.
- **Scope:** exhaustive scalar proof and arbitrary-prior-state registered
  equivalence of both row outputs, then isolated synthesis of the complete
  paired EA5 consumer. Production `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H080
  battery are conditional on an isolated deterministic improvement. No row
  value, bank predicate, destination enable, EA5 branch, state, schedule,
  memory, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. The mapped netlist
  retains separate three-carry families for `w_row` and `w_ins_row`.
- **Changed condition versus H031:** H031 accepted selected operands for two
  state-exclusive byte comparators. H086 targets two different five-bit
  incrementers in the same EA5 state, using the already-required `abank`
  destination selection and leaving H031's comparator unchanged.
- **Change:** define `row_inc = (abank ? w_ins_row : w_row) + 1` and use that
  exact result in the existing clear/set destination branches.
- **Result:** exhaustive checking proves all 4,096 arbitrary current-row,
  instrument-row, bank, and destination-enable states, and SAT independently
  proves the complete registered pair. The complete isolated consumer changes
  12 to 11 LUT4s, six to three carries, and keeps ten flops. Full permanent
  forms and full/PREVIEW lint pass. In the whole PSG, H080 to H086 changes
  6,409 to 6,416 LUT4s, 1,339 to 1,332 carries, 1,459 flops unchanged, 501 to
  502 unpackable flops, floor 6,910 to 6,918, and 14 EBRs unchanged. Seed-1
  routing changes 7,147 to 7,142 LCs and clocks 134.44/32.36 to 133.69/31.94
  MHz; both clocks pass. The five-LC route reduction is below placement
  sensitivity and cannot offset the eight-cell deterministic floor regression.
- **Decision:** rejected and reverted byte-for-byte before the fidelity
  battery. Production `rtl/psg_seq.sv` and permanent
  `tools/psg_hw_forms.py` are identical to H080; no render or integration
  claim remains.
- **Repeat only if:** if rejected, retry only after EA5 bank exclusivity, row
  width, destination ownership, or mapper selected-increment lowering changes
  materially.

## Hypothesis H087

- **ID:** H087.
- **Hypothesis:** the eight-state vibrato LFO has magnitude zero, one, two,
  one across the low two counter bits and direction in the high counter bit.
  Its magnitude is therefore exactly
  `{eff_tcnt[1] & ~eff_tcnt[0], eff_tcnt[0]}`. Using `eff_tcnt[2]` as the
  direction even at zero magnitude leaves the final add/sub result unchanged
  and should retire the signed case plus absolute-value cone.
- **Scope:** exhaustive proof of the complete final vibrato increment over all
  eight counter phases and all 8,192 pitch increments, then isolated synthesis
  of the complete registered vibrato consumer. Production `rtl/psg_seq.sv`, a
  permanent `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete
  H080 battery are conditional on an isolated deterministic improvement. No
  vibrato sequence, magnitude, rounding, pitch value, state, schedule,
  register, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG.
- **Changed condition versus the historical vibrato quotient rewrite:** that
  experiment moved the arithmetic into a narrower published quotient and
  regressed globally. H087 preserves the accepted full-width final add/sub and
  changes only how its existing three-bit LFO phase becomes sign and magnitude.
- **Change:** replace the signed LFO case and conditional absolute value with
  the direct direction bit and two-bit magnitude expression, retaining the
  existing multiply-by-zero/one/two wiring and rounded add/sub consumer.
- **Result:** exhaustive checking passes all 65,536 staged-counter/pitch
  combinations and SAT proves the complete final increment for every 16-bit
  input tuple. The complete isolated registered consumer changes 30 to 31
  LUT4s, with 12 carries and 13 flops unchanged, under the canonical Yosys
  build.
- **Decision:** rejected before production RTL. The direct Boolean magnitude
  does not replace the mapper's optimized signed-case cone;
  `rtl/psg_seq.sv` and permanent proof files remain byte-identical to H080 and
  no whole-PSG, fidelity, or route claim is warranted.
- **Repeat only if:** if rejected, retry only after the LFO sequence, counter
  phase width, vibrato rounding, final add/sub consumer, or mapper Boolean
  lowering changes materially.

## Hypothesis H088

- **ID:** H088.
- **Hypothesis:** after a sample edge, the registered pair `sample_en &&
  scnt == 0` holds exactly while the current dedicated `tick_en` flop is high,
  and `sample_en && scnt == 177` holds exactly while `pre_tick` is high. These
  two strobes can therefore be derived from post-edge state, removing their
  output flops without changing what any same-clock consumer observes.
- **Scope:** reachable-state and arbitrary held/sample-edge sequence proof,
  then isolated synthesis of the complete registered `psg_timing` consumer.
  Production `rtl/psg_timing.sv`, a permanent `tools/psg_hw_forms.py` check,
  whole-PSG mapping, and the complete H080 battery are conditional on an
  isolated deterministic improvement. No sample accumulator, binary counter,
  183-sample cadence, delayed-tick state, pre-tick offset, state schedule,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG.
- **Changed condition versus H008--H010 and H084:** H008 only respelled the two
  pre-edge counter comparisons; H009/H010 recoded delayed-tick state; H084
  replaced the binary counter. H088 preserves every one of those retained
  structures and tests only whether the already registered post-edge state is
  the physical storage for two same-clock output strobes.
- **Change:** continuously drive `tick_en = sample_en && scnt == 0` and
  `pre_tick = sample_en && scnt == 177`, then remove only their reset and
  sequential assignments.
- **Result:** exhaustive transition exploration closes over all 370 reachable
  timing states and 68,822 explored held/sample edges, with both outputs
  identical. SAT independently proves the post-edge identities for every
  in-range counter value. The complete isolated timing consumer changes 45 to
  48 LUT4s, 29 carries unchanged, 39 to 37 flops, three to two unpackable
  flops, and floor 48 to 50.
- **Decision:** rejected before production RTL. Only one of the two retired
  output flops is physically binding, so three new combinational cells make
  the exact derived form strictly worse. `rtl/psg_timing.sv` and permanent
  proof files remain byte-identical to H080; no whole-PSG, fidelity, or route
  claim is warranted.
- **Repeat only if:** if rejected, retry only after sample-enable registration,
  counter update order, tick/pre-tick phases, output consumers, or mapper
  registered-output lowering changes materially.

## Hypothesis H089

- **ID:** H089.
- **Hypothesis:** the clamped current pitch and clamped arpeggiated pitch are
  never consumed together. Slide setup consumes only current pitch, while the
  pitch-ROM address selects the arpeggiated value only in K_PF0 and the
  effect-6/7 K_FX/P_W0/P_W1 states. Selecting the two six-bit addends before
  one signed add-and-clamp cone should preserve both results while retiring
  the second arithmetic/clamp implementation.
- **Scope:** exhaustive proof of current, arpeggiated, and state-selected pitch
  results across the complete operand/control/state domain, symbolic proof of
  the complete selected output, then isolated synthesis of the registered
  pitch-address and slide consumers. Production `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete H080
  battery are conditional on an isolated deterministic floor improvement. No
  pitch value, saturation interval, previous-pitch calculation, arpeggio
  phase, effect decode, ROM address, slide arithmetic, state, schedule,
  interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H080 commit `6458450`: 6,409 LUT4s, 1,339
  carries, 1,459 flops, 501 unpackable flops, 14 EBRs, 6,910-cell floor,
  seed-1 7,147 LCs; 134.44 MHz fast and 32.36 MHz PSG. Source and netlist audit
  finds distinct current-pitch and arpeggiated-pitch signed add/clamp cones;
  `e_pitch` reaches slide setup and non-arpeggio ROM addresses, while `e_arp`
  reaches only arpeggio-selected ROM addresses.
- **Changed condition versus H022, H046, and H048:** H022 retained all three
  raw pitch sums and replaced each clamp relation with the accepted prefix
  saturation form. H046 globally normalized effect-class decodes and H048
  factored waveform-selector axes. H089 retains those accepted/retained
  decodes and arithmetic semantics, and instead exploits the sequencer-state
  exclusivity of two pitch values before their identical add/clamp operator.
- **Change:** define whether the active ROM-address consumer needs arpeggiated
  pitch, select `arp_p` versus `w_cur_pitch` as the first operand and
  `w_cur_pitch` versus `w_ins_pitch` as the second operand under the existing
  `e_insfx` rule, then apply the existing `ins_use` add/subtract-24 and
  `pclamp` operation once. Preserve the separate previous-pitch cone and use
  the shared selected result for both slide current pitch and pitch-ROM
  address selection.
- **Result:** all 2,097,152 selected operand/control tuples and all 512
  state/effect selections pass exhaustively; unconstrained Yosys SAT proves the
  shared selected result. Permanent hardware forms pass. The complete isolated
  registered consumer changes 159 to 116 LUT4s and 40 to 28 carries with 19
  flops unchanged. Full and PREVIEW lint, Python compilation, `make test-psg`
  including 93 analysis tests and the structural PSG test, 59/59 frozen
  renders, correctly parameterized ordinary and multipumped `/4`, `/5`, and
  `/6` cadence, and `make test-clocks` pass. All eight PREVIEW checks pass
  36/38 voiced windows at both 1,275 and 159 clocks/sample for masks 7/1/2/4.
  Synthetic and Celeste recovery report no coalesced, delayed, or dropped
  samples. Four-second hardware and PREVIEW SFX-10 renders have zero `click-v1`
  events. The five-frame Celeste smoke reports 2,179/3,668 active samples,
  range -22,013..9,151, and 1,068 levels. Strict OpenSpec validation and
  `git diff --check` pass.
- **Physical result:** canonical forced H080-to-H089 HX8K mapping changes 6,409
  to 6,346 LUT4s, 1,339 to 1,324 carries, 1,459 flops unchanged, 501 to 504
  unpackable flops, 14 EBRs unchanged, floor 6,910 to 6,850, and seed-1 route
  7,147 to 7,073 LCs. Routed timing is 115.14/31.54 MHz versus 112.50/18.75
  MHz constraints; the fast margin is only 2.64 MHz. Two forced builds are
  bit-identical: JSON SHA-256
  `0a75e0feddf08fee675d1a174526d65b1a555a4e2a848de4d67d85995a70e7ad`
  and ASC SHA-256
  `bb54e280b47335f62174126dfa219e16b913bcd18c713fe47bb2e73e6ef6ddef`.
- **Decision:** accepted. It makes schedule exclusivity explicit, removes 60
  deterministic floor cells, passes every exactness/fidelity/physical gate,
  and retains 14 EBRs. The 74-LC route reduction is not treated as an
  independent robust claim.
- **Repeat only if:** retry the pitch-selection family only if sequencer state
  ownership, arpeggio effect decode, pitch-ROM consumer timing, or arithmetic
  mapper lowering changes materially.

## Hypothesis H090

- **ID:** H090.
- **Hypothesis:** with the production multiplier fixed to radix-2, its true
  fast-step count is 6 for short requests and 8, 10, 12, or 9 for normal modes
  0--3. The separately decoded slow-domain `seq_pad` count is exactly
  `ceil(req_steps / 2)`: 3, 4, 5, 6, or 5. Decoding `req_steps` once and deriving
  `seq_pad` from it should preserve both CDC deadlines while removing duplicate
  registered-load logic and simplifying the count contract.
- **Scope:** exhaustive proof over both supported radix parameters and all
  short/mode inputs, then isolated iCE40 synthesis of the complete registered
  `req_steps`/`seq_pad` load and countdown cone. Production
  `rtl/psg_mulmp.sv`, permanent hardware forms, whole-PSG mapping, and the
  complete H089 battery are conditional on a deterministic isolated floor
  improvement. No iteration count, result value, fast recurrence, CDC toggle,
  consume gap, request mode, schedule, interface, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. `psg_mulmp` currently
  spells `req_steps` and `seq_pad` as two separate mode/short ternaries.
- **Changed condition versus H006:** H006 priced a standalone direct bit
  expression for the radix-4 normal count `{4,5,6,5}` and found it one LUT4
  larger than the existing ternary. H090 does not respell that count in
  isolation: production now instantiates `RADIX_BITS=1`, exposing the exact
  cross-count relation between its radix-2 `req_steps` and preserved radix-4
  `seq_pad`, so one decoded count may feed both registered consumers.
- **Change:** define one next-step count from `RADIX_BITS`, short, and mode;
  load `req_steps` directly, and derive the matching `seq_pad` count from it
  while preserving radix-4 parameter behavior.
- **Result:** all 16 radix/short/mode tuples match exhaustively and Yosys SAT
  proves both supported radix forms for arbitrary controls. The complete
  production-radix registered load and countdown cone changes 16 to 17 LUT4s;
  three carries and seven flops are unchanged.
- **Decision:** rejected before production. The apparent source duplication is
  already cheaper than materializing the ceil-half relation in the complete
  registered cone. `rtl/psg_mulmp.sv` and permanent proof files remain
  byte-identical to H089; no whole-PSG, fidelity, or route claim is warranted.
- **Repeat only if:** if rejected, retry only after supported radix values,
  mode/short step counts, slow consume gaps, registered-load boundaries, or
  mapper lowering changes materially.

## Hypothesis H091

- **ID:** H091.
- **Hypothesis:** music pattern completion stores both a 13-bit elapsed counter
  `pticks` and a 13-bit target `ptick_tgt`, then compares the incremented
  elapsed count with the target. The asynchronous pattern-length product is
  captured while K_FX remains stalled on `m_busy`, before the visit can reach
  W_MUS and advance `pticks`. A single 13-bit remaining-ticks counter, loaded
  from the same target and decremented/saturated at W_MUS, should therefore
  preserve the completion edge and pending-trigger delay while retiring one
  register bank and the wide elapsed-versus-target comparator.
- **Scope:** exact event-model proof across the complete 1..8,160 target range,
  launch/product replacement ordering, pending-trigger delays, and terminal
  completion behavior; symbolic equivalence of the legal counter transition;
  then isolated iCE40 synthesis of the complete registered baseline/candidate
  consumer. Production `rtl/psg_seq.sv`, permanent hardware forms, whole-PSG
  mapping, and the complete H089 battery are conditional on a deterministic
  isolated floor improvement. No pattern length, speed, trigger ownership,
  music stop/loop behavior, walk cadence, schedule, interface, EBR, R.84
  executor, or tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. The completion consumer
  retains 26 counter/target bits plus a 13-bit increment and comparison cone.
- **Changed condition versus H053, H058, H061--H063, H065, and H082:** those
  rows retired pipeline, replay, sample, or effect-lifetime storage and were
  rejected when reconstruction enlarged their live consumers. H091 targets a
  distinct monotone elapsed/deadline pair and relies on the already-shipped
  K_FX multiplier stall to prove the final target is installed before the
  first decrement, so no removed value is reconstructed downstream.
- **Change:** replace `pticks`/`ptick_tgt` with one remaining-ticks register;
  load the same initial/final target before W_MUS, saturate at terminal while
  trigger requests remain, and complete on the same first trigger-free tick.
- **Result:** refuted by target 8,160 with a trigger held through 8,192 tick
  advances. On the first trigger-free tick after wrap, the baseline elapsed
  count is one and its `elapsed >= target` predicate is false, while the
  candidate remaining count is saturated at zero and completes immediately.
  Repeated CPU SFX writes can keep `trig_req` nonzero for this interval, so the
  counterexample is reachable through the public interface rather than an
  unconstrained illegal state.
- **Decision:** rejected before isolated synthesis or production. Exact
  arbitrary-trigger behavior needs both the deadline and elapsed/wrap
  information; `rtl/psg_seq.sv` and permanent proof files remain byte-identical
  to H089, and no physical or fidelity claim is warranted.
- **Repeat only if:** if rejected, retry only after target-load timing, K_FX
  multiplier stall behavior, trigger-clear bound, pattern duration, counter
  wrap semantics, completion consumers, or mapper registered-state lowering
  changes materially.

## Hypothesis H092

- **ID:** H092.
- **Hypothesis:** accepted H031 time-shares one `ta_ge` comparator across EA2,
  EA4, and EA5 but retains two result flops. `froll` is written in EA2 and read
  only in immediately following EA3; `ge_lpe` is written in EA4 and read only
  in immediately following EA5. One shared predicate flop should preserve both
  values, make their non-overlapping lifetime explicit, and retire one stored
  bit without reconstructing any downstream value.
- **Scope:** exhaustive state/value transition proof and unconstrained symbolic
  equivalence of both registered consumers, then isolated iCE40 synthesis of
  the complete comparator/result/EA3/EA5 cone. Production `rtl/psg_seq.sv`,
  permanent hardware forms, whole-PSG mapping, and the complete H089 battery
  are conditional on a deterministic isolated floor improvement. No compare
  operand, row/loop result, state transition, schedule, memory, interface, EBR,
  R.84 executor, or tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. The shared comparator
  still drives independent `froll` and `ge_lpe` flops.
- **Changed condition versus H031, H053, H063, and H068:** H031 accepted the
  shared arithmetic comparator but did not merge its disjoint registered
  results. H053/H063/H068 removed values whose downstream consumers then
  needed selection or reconstruction and regressed globally. H092 keeps the
  already-shared `ta_ge` value and replaces two adjacent-state holders with one
  holder, so no consumer-side reconstruction or new source mux is introduced.
- **Change:** replace `froll` and `ge_lpe` with one `ta_ge_r`, capture it in EA2
  and EA4, and consume it unchanged in EA3 and EA5.
- **Result:** exhaustive checking passes all four EA2/EA4 predicate histories,
  SAT equivalence passes, and the complete isolated cone improves 20->19 LUT4,
  17 carries unchanged, and 2->1 FF. The saving does not compose: canonical
  whole-PSG mapping changes 6,346->6,366 LUT4, 1,324->1,327 carries,
  1,459->1,458 FF, 504 unpackable FF unchanged, and floor 6,850->6,870.
  Seed-1 placement changes 7,073->7,098 LCs, within placement sensitivity;
  timing still passes at 129.92/32.71 MHz. Production and permanent-form edits
  are reverted byte-for-byte before fidelity gates.
- **Decision:** rejected; the isolated storage saving causes a deterministic
  whole-design LUT/carry/floor regression.
- **Repeat only if:** if rejected, retry only after EA2--EA5 state order,
  comparator operands, result consumers, register enables, or mapper flop-
  packing/lowering changes materially.

## Hypothesis H093

- **ID:** H093.
- **Hypothesis:** the DQ service coefficient is selected from only seven
  constants over the exact 32 `{wt,wave,mode}` combinations. A grouped
  `casez` truth table with the common 255/256 defaults should expose shared
  output bits more directly than the nested relational decoder and reduce the
  LUT fabric feeding the registered serial-service request.
- **Scope:** exhaustive comparison of all 64 raw selector tuples (including
  `wt` dominance), unconstrained SAT equivalence, then isolated iCE40 synthesis
  of the complete coefficient/load/first-recurrence cone. Production
  `rtl/psg_walk.sv`, permanent hardware forms, whole-PSG mapping, and the full
  H089 battery are conditional on a deterministic isolated floor improvement.
  No coefficient value, DQ recurrence, count, result publication, phase,
  schedule, state, memory, interface, EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. `dq_coeff` uses nested
  `wt`, waveform, and mode comparisons before loading `psg_dqsvc.start_k`.
- **Changed condition versus H021, H046, H051, and H067:** H021 priced the
  unrelated 32-arm filter table against arithmetic; H046 normalized effect
  classes globally and lost to fanout; H051 changed the DQ iteration token;
  H067 factored quotient prefixes after arithmetic. H093 changes only the
  small constant coefficient selection at the DQ request boundary, retaining
  every consumer, register, and recurrence.
- **Change:** replace the nested coefficient function in a scratch complete
  request cone with a grouped exact `casez` table and synthesize both forms.
- **Result:** exhaustive checking passes all 64 raw selector tuples and SAT
  equivalence passes. In the complete registered DQ coefficient/load/
  recurrence cone, the grouped table changes 134->137 LUT4 while 28 carries
  and 28 FF remain unchanged. The deterministic isolated floor therefore adds
  three cells. No production or permanent-proof file changed, and downstream
  gates are correctly skipped.
- **Decision:** rejected before production; the exact grouped spelling is
  locally larger than the nested decoder.
- **Repeat only if:** if rejected, retry only after the coefficient set,
  waveform/mode domain, DQ request boundary, or mapper truth-table lowering
  changes materially.

## Hypothesis H094

- **ID:** H094.
- **Hypothesis:** full-mode `blend_restart` separately compares six live/last
  fields and ORs their inequality results. Concatenating those same fields and
  evaluating one packed inequality is algebraically identical, makes the
  transition signature explicit, and may let ABC cover the shared XOR/
  reduction tree with fewer LUT4s.
- **Scope:** exhaustive structural tuple proof, unconstrained SAT equivalence,
  then isolated iCE40 synthesis of the complete restart/counter/snapshot
  consumer. Production `rtl/psg_walk.sv`, permanent hardware forms, whole-PSG
  mapping, and the full H089 battery are conditional on a deterministic
  isolated floor improvement. No compared bit, noise-trigger term, play gate,
  counter, snapshot, waveform, arithmetic, schedule, state, memory, interface,
  EBR, R.84 executor, or tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG. The restart predicate
  uses six independent `!=` expressions before their common OR consumer.
- **Changed condition versus H031, H035, H043, and H046:** H031 time-shared
  arithmetic comparisons across sequencer phases; H035 nested common suffixes
  that Yosys already shared; H043 named EA5 predicates; H046 normalized effect
  classes with wider fanout. H094 neither shares a comparator across phases nor
  adds a reusable predicate: it exposes one existing same-cycle packed tuple
  comparison at its sole restart consumer.
- **Change:** replace the six separately ORed field inequalities in a scratch
  complete restart cone with one inequality over their exact concatenation.
- **Result:** all 64 field-equality patterns pass, SAT equivalence passes, and
  the complete isolated restart/counter cone improves 51->50 LUT4 with five
  carries and seven FF unchanged. The saving does not compose: canonical
  whole-PSG mapping changes 6,346->6,349 LUT4, 1,324->1,323 carries, 1,459 FF
  and 504 unpackable FF unchanged, and floor 6,850->6,853. Seed-1 placement
  changes 7,073->7,076 LCs, within placement sensitivity; timing passes at
  136.28/30.27 MHz. Production and permanent-form edits are reverted byte-for-
  byte before fidelity gates.
- **Decision:** rejected; the isolated one-LUT4 saving causes a deterministic
  three-LUT4/three-floor-cell whole-design regression.
- **Repeat only if:** if rejected, retry only after the transition tuple,
  restart consumer, blend-counter update, or mapper reduction lowering changes
  materially.

## Hypothesis H095

- **ID:** H095.
- **Hypothesis:** accepted H030's exact foreground trigger-length overflow
  prefix never reached the direct H089 lineage. Replacing the unsigned
  greater-than-32 comparison with its high-prefix/non-zero-suffix decode should
  retain exact saturation while removing comparator carry logic in the current
  whole-design context.
- **Scope:** exhaustive proof over all 256 input bytes, Yosys equivalence, and
  isolated synthesis of the registered six-bit saturation consumer, followed
  by production `rtl/psg_seq.sv`, permanent `tools/psg_hw_forms.py` coverage,
  whole-PSG synthesis, and the complete H089 acceptance battery. No register
  value, address, state, schedule, memory, interface, EBR, R.84 executor, or
  tolerance change.
- **Baseline:** accepted direct H089 commit `996ee40`: 6,346 LUT4s, 1,324
  carries, 1,459 flops, 504 unpackable flops, 14 EBRs, 6,850-cell floor,
  seed-1 7,073 LCs; 115.14 MHz fast and 31.54 MHz PSG.
- **Changed condition versus H030:** H030 was accepted on an older source
  lineage whose merge base with H089 is `e3823f5`; it was absent from H089,
  whose sequencer and mapping context changed materially. H095 therefore
  re-prices the exact same narrow mechanism rather than assuming its old
  four-LUT4/two-carry saving composes.
- **Change:** define `trg_len_over = (|di[7:6]) || (di[5] && |di[4:0])` and use
  it to select 32 versus `di[5:0]` for foreground trigger-length writes; add
  permanent exhaustive coverage for all byte values.
- **Result:** all 256 values match `min(di, 32)` and Yosys proves all six result
  bits. The isolated registered consumer remains three LUT4s/six FF while
  removing both carries. Full hardware forms, full/PREVIEW lint, Python
  compilation, `make test-psg` including 93 analysis tests and the structural
  PSG test, 59/59 frozen renders, ordinary and multipumped `/4`, `/5`, and `/6`
  cadence, and `make test-clocks` pass. All eight PREVIEW checks pass 36/38
  voiced windows at both 1,275 and 159 clocks/sample for masks 7/1/2/4.
  Synthetic and Celeste recovery report zero coalesced, delayed, or dropped
  samples. Four-second hardware and PREVIEW SFX-10 renders have zero
  `click-v1` events. The five-frame Celeste smoke reports 2,179/3,668 active
  samples, range -22,013..9,151, and 1,068 levels.
- **Physical result:** forced H089-to-H095 HX8K mapping changes 6,346 to 6,342
  LUT4s, 1,324 to 1,321 carries, 1,459 flops and 504 unpackable flops
  unchanged, 14 EBRs unchanged, floor 6,850 to 6,846, and seed-1 route 7,073
  to 7,066 LCs. Routed timing is 133.69/32.79 MHz versus 112.50/18.75 MHz
  constraints. Two forced builds are bit-identical: JSON SHA-256
  `e4b26eb1cc4150a090811d8212c9ce0f62336d8f4d5d7e67238456c56ead1bf0`
  and ASC SHA-256
  `ed29d5d010a9a94015a197fc506ffea119090be1b9da66aa549aad38c23cdc17`.
- **Decision:** accepted as direct commit `3d7a2e2`. It preserves the source-
  exact saturation contract, removes four deterministic floor cells, passes
  every proof/fidelity/physical gate, and retains 14 EBRs. The seven-LC route
  reduction is not treated as an independent robust claim.
- **Repeat only if:** retry only after the trigger-length write consumer,
  comparator-sharing context, or mapper lowering changes materially.

## Hypothesis H096

- **ID:** H096.
- **Hypothesis:** `tch_seen` only remembers that the current pattern launch has
  already accepted its left-most launched non-looping channel. At that event,
  `ptick_seen` has necessarily already latched the left-most launched channel's
  default speed, and no later `launched` bit can affect either pattern pacing
  result. Consuming the launch worklist by clearing `launched` at the accepted
  pattern-length request should therefore retire `tch_seen` and its high-fanout
  compare/control cone while making the one-shot ownership explicit.
- **Scope:** symbolic/exhaustive proof of the complete T_NL launch/pacing state
  transition, followed by isolated and whole-PSG mapping. Production
  `rtl/psg_seq.sv`, permanent `tools/psg_hw_forms.py` coverage, and the complete
  merged-main acceptance battery are conditional on an early deterministic
  mapped improvement. No pattern selection, channel ordering, speed/row value,
  multiplier request, state schedule, memory, interface, EBR, R.84 executor,
  diagnostic ARAM, or tolerance change.
- **Baseline:** merged clean `main` commit `a84dbff`: canonical forced HX8K
  6,395 LUT4s, 1,321 carries, 1,460 flops, 506 unpackable flops, 14 EBRs,
  6,901-cell floor, seed-1 7,120 routed LCs; 140.92 MHz fast and 32.41 MHz PSG.
- **Changed condition versus H031 and H095:** H031 shared T_NL's byte comparator
  with another state-exclusive relation, while H095 changed an unrelated CPU
  trigger-length saturation spelling. H096 preserves those accepted arithmetic
  forms and instead retires the separate persistent one-shot state by consuming
  the already-existing launch worklist after its final live use.
- **Change:** remove `tch_seen`; define the T_NL pattern-length request from the
  current `launched[c]` bit and the accepted shared relation; when that request
  fires, clear `launched` while queueing `ptick_pend`. Add permanent proof that
  the old and new protocols issue identical requests and pacing updates over
  every launch/order/qualifier state admitted by the four-channel scan.
- **Result:** the permanent form exhausts all 256 four-channel launch/qualifier
  masks and preserves the request trace, fallback source, `ptick_seen`, and
  pending-product outcome. Full forms, full/PREVIEW lint, Python compilation,
  the default H095-bound R.84 model, `make test-psg` including 93 analysis tests
  and the structural PSG test, and the 59/59 frozen renders pass. Ordinary and
  multipumped `/4`, `/5`, and `/6` cadence passes at 572/1,275, 572/1,020, and
  572/850 ordinary sample clocks and 524/1,275, 524/1,020, and 524/850
  multipumped sample clocks; tick windows are 5,757/7,654, 4,737/6,123, and
  4,056/5,103 ordinary, and 5,709/7,654, 4,689/6,123, and 4,008/5,103
  multipumped, with zero late flips. Clock-divider checks pass. All eight
  Celeste music-0 PREVIEW checks at 1,275 and 159 clocks/sample for masks
  7/1/2/4 pass at 25/27 voiced windows (93%). Music-30 has no stable pitch
  windows on merged main, but H096's four-second PREVIEW WAV is byte-identical
  to clean `a84dbff` at SHA-256 `c4f2179d...`. Synthetic and Celeste recovery
  report zero coalesced, delayed, or dropped samples. Four-second hardware and
  PREVIEW SFX-10 renders have zero `click-v1` events. The five-frame Celeste
  smoke reports 2,079/3,668 active samples, range -21,544..7,711, and 1,014
  levels. Strict OpenSpec, diff and scope checks pass.
- **Physical result:** two forced HX8K builds reproduce JSON SHA-256
  `da8f01f61f5b915cea2f73dad6d87c6f1dc762edf6ce490989fbb3f354b55772`
  and ASC SHA-256
  `519dabc769d00349bf006af63dfa6232ac417aa00c830ae397d472a47df46d00`.
  Merged main to H096 changes 6,395 to 6,364 LUT4s, 1,321 carries unchanged,
  1,460 to 1,459 flops, 506 to 509 unpackable flops, 14 EBRs unchanged, floor
  6,901 to 6,873, and seed-1 route 7,120 to 7,095 LCs. Routed timing improves
  from 140.92/32.41 to 151.17/33.09 MHz versus 112.50/18.75-MHz constraints.
  The 31-LUT4, one-FF, and 28-floor reductions are deterministic; the 25-LC
  route reduction remains below placement sensitivity and is not overclaimed.
- **Decision:** accepted as generic RTL/proof commit `a647185`. Because H096
  changes `rtl/psg_seq.sv`, the companion must regenerate its H095-bound source
  certificate and C2-C-C live-value lineage before integration; H096 makes no
  R.84/B2 proof or integration claim.
- **Repeat only if:** retry this launch-worklist/state family only if music
  channel ordering, T_NL visitation, pacing fallback ownership, launched-bit
  consumers, or multiplier-request scheduling changes materially.

## Hypothesis H097

- **ID:** H097.
- **Hypothesis:** `ml_cpu` records only which path entered `ML_STOP`. Every
  automatic entry from `W_MUS` or its `MS_RD/MS_CK` loop-back scan is dominated
  by `walk_tick=1`, and the CPU-launch entry from `S_IDLE` can write
  `walk_tick=0`. No state between either entry and `ML_STOP` changes that bit,
  so the existing `walk_tick` register can select immediate versus delayed
  music stops and the dedicated provenance flop can be retired.
- **Scope:** exact transition/source-closure proof over every `ML_STOP` entry,
  an isolated registered provenance consumer, then `rtl/psg_seq.sv`, a
  permanent `tools/psg_hw_forms.py` check, whole-PSG mapping, and the complete
  H096 battery only after an isolated deterministic win. No launch worklist,
  pattern pacing, audio value, state-memory layout, schedule, interface, EBR,
  diagnostic ARAM, R.84 executor, or tolerance change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks.
- **Changed condition versus H096 and the lifetime DNR families:** H096 changes
  the launched-channel worklist and pacing-owner state; R.40--R.42 and
  R.76--R.79 alias arithmetic/service payload storage. H097 changes neither.
  It reuses a controller bit only after its tick-walk meaning has already
  selected the automatic music-completion path and proves all entry paths
  before changing production RTL.
- **Change:** scratch proof and measured production probe removed `ml_cpu`, wrote `walk_tick=0` when `S_IDLE` claimed
  a CPU music launch, retain the already-one bit across automatic completion
  and loop-back scan, and select `mus_stop(2'd2)` exactly when `walk_tick` is
  one at `ML_STOP`.
- **Result:** 603 direct, loop-back scan, and held-path cases preserve the
  immediate/delayed stop class. The complete isolated provenance consumer
  falls from six to three LUT4s and two to one FF. Canonical whole-PSG mapping
  instead changes 6,364 to 6,382 LUT4s, 1,321 to 1,325 carries, 1,459 to 1,458
  flops, 509 to 508 unpackable flops, floor 6,873 to 6,890, and seed-1 route
  7,095 to 7,115 LCs. Timing passes at 136.50/32.82 MHz, but all authoritative
  area gates except FF count regress.
- **Decision:** rejected after whole-PSG synthesis. Production RTL and the
  conditional permanent proof are reverted byte-for-byte; no fidelity gate or
  accepted area claim remains.
- **Repeat only if:** if rejected, retry only after `ML_STOP` entry topology,
  `walk_tick` lifetime, CPU-launch arbitration, loop-back scan, stop classes,
  or mapper sequential lowering changes materially.

## Hypothesis H098

- **ID:** H098.
- **Hypothesis:** the multi-pumped multiplier needs exactly 3, 4, 5, 6, 8,
  9, 10, or 12 active fast-clock steps across its two supported radix
  parameters. Each duration can be a start point on one four-bit maximal-LFSR
  segment ending at terminal state one, with zero retained as idle. A shift
  plus one XOR should replace the private binary decrement carry chain without
  changing any request, product, acknowledge, or slow-domain busy clock.
- **Scope:** exhaustive token/duration proof, transaction equivalence for both
  radix parameters and all request modes, isolated synthesis of the complete
  registered count/load/terminal consumer, then `rtl/psg_mulmp.sv`, permanent
  multiplier proofs, whole-PSG mapping, and the complete H096 battery only
  after an isolated deterministic win. No multiplier recurrence, operand,
  product, CDC synchronizer, request/acknowledge edge, sequencer padding,
  schedule, interface, EBR, diagnostic ARAM, R.84 executor, or tolerance
  change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks.
- **Changed condition versus H006, H051, H070, and H090:** H006 and H090
  respelled or shared the loaded duration decoder while retaining binary
  decrement; H051 accepted a separate three-bit fixed-five-step DQ token;
  H070's 24-state divider token was tested in a different service. H098 keeps
  both existing duration decoders and `seq_pad` independent, changing only the
  four-bit fast-domain multiplier iteration representation across its actual
  variable duration set.
- **Change:** the measured production probe used the primitive four-bit
  `x^4+x^3+1` maximal-LFSR recurrence,
  bind each legal duration to the unique start token that reaches one on its
  final active edge, and retain the current terminal acknowledge action.
- **Result:** 418,608 radix/mode/freeze traces preserve every busy and terminal
  edge for both supported masks; the selected `x^4+x^3+1` form passes all
  6,020 two-radix CDC transactions. Its complete isolated count consumer falls
  from 14 to ten LUT4s and two to zero carries, with five FF unchanged.
  Canonical whole-PSG mapping instead changes 6,364 to 6,384 LUT4s, 1,321 to
  1,319 carries, 1,459 flops unchanged, 509 to 508 unpackable flops, floor
  6,873 to 6,892, and seed-1 route 7,095 to 7,111 LCs. Timing passes at
  137.14/32.70 MHz, but every authoritative area metric except carries
  regresses.
- **Decision:** rejected after whole-PSG synthesis. Production multiplier,
  transaction bench, and conditional permanent proof are reverted byte-for-
  byte; no fidelity gate or accepted area claim remains.
- **Repeat only if:** if rejected, retry only after legal multiplier duration
  set, fast recurrence, terminal acknowledge, radix parameter, request-load
  decoder, or mapper sequential lowering changes materially.

## Hypothesis H099

- **ID:** H099.
- **Hypothesis:** `w_ch_{damp,rev,det,buzz,noiz}` is the effective filter tuple
  only while a custom instrument is active. On trigger without an instrument
  and on an instrument-to-ordinary-note exit, the tuple is synchronously
  rewritten from `w_bf_*` and later published unchanged. Selecting `w_bf_*`
  at `P_W2` whenever `w_ins_on=0` should remove both eight-bit register-write
  arms while retaining the stored effective tuple and all instrument maxima.
- **Scope:** exhaustive tuple/transition/publication proof over trigger,
  ordinary-note, retained-instrument, and new-instrument paths; isolated
  synthesis of the complete registered eight-bit filter/publication consumer;
  then `rtl/psg_seq.sv`, a permanent `tools/psg_hw_forms.py` check, whole-PSG
  mapping, and the complete H096 battery only after an isolated deterministic
  win. No filter code, trit maximum, base/instrument precedence, active-bank
  storage, publication format, schedule, interface, EBR, diagnostic ARAM,
  R.84 executor, or tolerance change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks.
- **Changed condition versus H045 and the lifetime DNR families:** H045 kept
  all tuple writes and only respelled the three trit maxima, mapping
  identically in isolation. H099 retains those relational maxima and every
  stored bit. It changes ownership of two redundant base-copy writes and the
  publication source, not an arithmetic/service payload lifetime alias.
- **Change:** select `w_bf_*` at publication when `w_ins_on=0`. Variant one
  removes the base-copy assignments in both `T_SP` and ordinary `K_LD`;
  variant two restores `T_SP` initialization and removes only the ordinary
  `K_LD` exit writes.
- **Result:** the transition proof passes all 4,224 legal two-operation paths,
  and the complete isolated registered consumer improves from 29 to 12 LUT4s
  with 17 FF unchanged. Variant one maps at 6,371 LUT4s / 1,321 carries /
  1,459 FF / 508 unpackable / floor 6,879 and routes at 7,100 LCs with
  144.30/32.26 MHz timing: +7 LUT4s, -1 unpackable, +6 floor cells, and +5
  routed LCs versus H096. Variant two maps at 6,398 LUT4s / 1,322 carries /
  1,459 FF / 509 unpackable / floor 6,907 and routes at 7,128 LCs with
  131.10/31.89 MHz timing: +34 LUT4s, +1 carry, +34 floor cells, and +33
  routed LCs. Both pass timing but fail every authoritative deterministic area
  gate except FF count.
- **Decision:** rejected after the two permitted whole-PSG variants; production
  RTL and the conditional permanent form are reverted byte-for-byte.
- **Repeat only if:** if rejected, retry only after filter tuple ownership,
  instrument-active state, trigger/exit topology, publication source, stored
  effective tuple, or mapper register-enable lowering changes materially.

## Hypothesis H100

- **ID:** H100.
- **Hypothesis:** only CPU foreground slots can execute the sole
  `released[...] <= 1` assignment. Music-slot triggers clear their dynamic
  array element, but music slots can never make it non-zero. Restricting
  `released` to four foreground bits and treating every music slot as not
  released should remove four unreachable FFs and the upper dynamic-write
  targets without changing loop/release behavior.
- **Scope:** exhaustive state-transition proof across reset, trigger clear,
  simultaneous CPU release, foreground/music slot selection, instrument-bank
  selection, and the EA5 loop predicate; isolated synthesis of the complete
  registered state/consumer; then `rtl/psg_seq.sv`, a permanent
  `tools/psg_hw_forms.py` invariant, canonical whole-PSG synthesis, and the
  complete H096 battery only after deterministic isolated and global wins. No
  release command, loop condition, trigger ordering, slot count, schedule,
  interface, EBR, diagnostic ARAM, R.84 executor, or tolerance change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks.
- **Changed condition versus lifetime/storage DNR families:** H037 tested a
  combinationally dead detune source bit; H062/H063 reconstructed live stored
  waveform/noise values; H092 merged two reachable result flops. H100 instead
  removes four array elements with no set transition and retains every
  reachable foreground bit plus the exact same-edge CPU-write precedence.
- **Change:** in the scratch consumer, replace the eight-entry `released`
  array with four
  foreground entries, clear it only on foreground trigger, and make the EA5
  release guard true for every music slot.
- **Result:** exhaustive induction covers 2,560 reset-reachable combinations
  of current foreground state, foreground/music slot, trigger clear,
  same-edge CPU release, and instrument-bank loop selection. The production
  JSON contains only `released[0]` through `released[3]`: Yosys already proves
  the four music elements constant. Source-matched isolated reference and
  explicit four-entry candidate both map to 17 LUT4s / zero carries / four
  FFs.
- **Decision:** rejected before production RTL because the desired state and
  logic pruning is already present in the mapped netlist; no permanent form or
  production file changed.
- **Repeat only if:** if rejected, retry only after slot partitioning, CPU
  release addressing, trigger ordering, loop/release semantics, or mapper
  dynamic-array lowering changes materially.

## Hypothesis H101

- **ID:** H101.
- **Hypothesis:** the four foreground `trg_row` and `trg_len` arrays consume 44
  unpackable FFs even though the engine holds `c[1:0]` stable throughout the
  eight-cycle `V_LD` prelude before `T_FL`. A four-entry block RAM can prefetch
  both pending fields without a new state; eight resettable valid bits retain
  the current reset/consume-to-zero contract. One EBR plus eight FFs should
  reduce the deterministic LC floor materially.
- **Scope:** isolated synthesis of the complete CPU-write, synchronous-read,
  valid-bit, consume-clear, and row/length output consumer; exact proof of
  reset, read-address settling, independent field writes, consume, and
  same-edge CPU-write precedence; then `rtl/psg_seq.sv`, permanent
  `tools/psg_hw_forms.py` schedule/transition checks, canonical whole-PSG
  synthesis, and the complete H096 battery only after deterministic isolated
  and global wins. At most two memory spellings. No trigger value/clamp,
  command ordering, channel mapping, `T_FL` cadence, state-memory layout,
  diagnostic ARAM, R.84 executor, or tolerance change.
- **Baseline:** accepted H096 commit `a647185` atop merged main: 6,364 LUT4s,
  1,321 carries, 1,459 flops, 509 unpackable flops, 14 EBRs, 6,873-cell floor,
  seed-1 7,095 LCs, and 151.17/33.09 MHz routed clocks. `trg_row` and
  `trg_len` account for 20 and 24 unpackable FFs respectively.
- **Changed condition versus state-memory DNR families:** none. The initial
  active-index audit compared only H019 and missed legacy R.44, which had
  already tested this exact pending-trigger EBR migration with valid bits,
  `V_LD` prefetch, and CPU collision bypass. H101's isolated result independently
  reproduces R.44's reason for rejection and closes the indexing gap.
- **Change:** pack row and length into one four-entry synchronous RAM;
  use independent per-field write masks if they infer one EBR, otherwise test
  two narrow EBRs as the sole fallback. Clear only valid bits at consumption.
- **Result:** the source FF consumer maps at 53 LUT4s / zero carries / 44 FFs /
  44 unpackable / zero EBRs, for a 97-cell floor. A plain packed EBR maps at
  44 LUT4s / two carries / 36 FFs / 26 unpackable / one EBR, for a 70-cell
  floor, but its registered read returns the old field for one cycle after a
  same-address CPU write. A concrete previous-cycle-write/`T_FL` trace gives
  reference row 2 and RAM row 1. The required shared `{field,slot,data}`
  write-through state maps at 78 LUT4s / two carries / 46 FFs / 29 unpackable /
  one EBR, floor 107. The two-EBR fallback maps at 75 LUT4s / two carries /
  46 FFs / 29 unpackable / two EBRs, floor 104. Both exact forms are locally
  larger than the FF reference.
- **Decision:** rejected before production RTL; no permanent form or
  production file changed. Do not repeat R.44/H101 unless its explicit repeat
  condition is met.
- **Repeat only if:** if rejected, retry only after trigger register semantics,
  CPU/engine ordering, `V_LD` prefetch cadence, iCE40 RAM write-mask inference,
  EBR budget, or mapper memory lowering changes materially.

## Saved Artifacts

| Artifact | Command | Notes |
| -- | -- | -- |
| `build/experiments/h001/baseline.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` at `86d4fab` | H001 baseline mapping. |
| `build/experiments/h001/baseline.pnr.log` | same | H001 baseline seed-1 placement and timing. |
| `build/experiments/h001/candidate.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H001 | H001 accepted mapping. |
| `build/experiments/h001/candidate.pnr.log` | same | H001 accepted seed-1 placement and timing. |
| `build/experiments/h001/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h001/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h002/candidate.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H002 | H002 accepted mapping. |
| `build/experiments/h002/candidate.pnr.log` | same | H002 accepted seed-1 placement and timing. |
| `build/experiments/h002/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h002/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h003/candidate.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H003 | H003 accepted mapping. |
| `build/experiments/h003/candidate.pnr.log` | same | H003 accepted seed-1 placement and timing. |
| `build/experiments/h003/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h003/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h005/candidate-v1.{synth,pnr}.log` | canonical synthesis with the rejected `< 3` spelling | Smaller map and placement, but routed fast-clock timing failure. |
| `build/experiments/h005/candidate.{synth,pnr}.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with retained H005 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h005/candidate-v2.{synth,pnr}.log` | retained-spelling synthesis checkpoint | Pre-canonical retained mapping and placement evidence. |
| `build/experiments/h005/celeste-audio.{hex,bin}` | reconstructed from `src/celeste/audio.inlay.asm` | 4,608-byte recovery-probe audio image. |
| `build/experiments/h005/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h005/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h007/candidate.{synth,pnr}.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H007 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h007/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h007/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h009/candidate.{synth,pnr}.log` | canonical synthesis with the rejected shift token | Exact isolated win, but whole-PSG mapped and placed regression. |
| `build/experiments/h010/candidate.{synth,pnr}.log` | canonical synthesis with the rejected pending bit | Exact isolated flop/LUT win, but whole-PSG mapped and placed regression. |
| `build/experiments/h012/candidate.{synth,pnr}.log` | canonical synthesis with the rejected sequencer-busy output | CDC proofs pass, but whole-PSG mapped and placed area regress. |
| `build/experiments/h013/candidate.{synth,pnr}.log` | canonical synthesis with both services narrowed | Exact width proof, but whole-PSG mapped and placed area regress. |
| `build/experiments/h013/candidate-v2.{synth,pnr}.log` | canonical synthesis with only the multipumped service narrowed | Mapping-identical attribution variant; rejected. |
| `build/experiments/h014/isolated-{baseline,candidate}.log` | registered full-detune `synth_ice40` comparison | Both forms map identically; production patch rejected. |
| `build/experiments/h015/isolated-{baseline,candidate}.log` | registered full-detune `synth_ice40` comparison | Unconditional subtract maps identically; production patch rejected. |
| `build/experiments/h016/isolated-{baseline,candidate}.log` | full registered divider `synth_ice40` comparison | Exact nine-bit form trades one carry for one LUT locally. |
| `build/experiments/h016/candidate.{synth,pnr}.log` | canonical synthesis with the nine-bit restoring subtract | Whole-PSG mapped and placed area regress; rejected. |
| `build/experiments/h017/isolated-{baseline,candidate}.log` | registered gain-consumer synthesis | Full context sharing is locally much smaller. |
| `build/experiments/h017/isolated-candidate-v2.log` | registered gain-consumer synthesis | Scale-only attribution form; locally smaller. |
| `build/experiments/h017/candidate-v1.{synth,pnr}.log` | canonical synthesis with full context sharing | Mapped and placed area regress; rejected. |
| `build/experiments/h017/candidate-v2.{synth,pnr}.log` | canonical synthesis with scale-only sharing | Smaller regression, but placement still exceeds H007; rejected. |
| `build/experiments/h018/isolated-{baseline,candidate}.log` | registered reciprocal half-sum synthesis | Exact 25-bit form trades one carry for one LUT locally. |
| `build/experiments/h018/candidate.{synth,pnr}.log` | canonical synthesis with the shifted half-sum | Whole-PSG mapped and placed area regress; rejected. |
| `build/experiments/h019/isolated-{baseline,candidate,candidate-v2}.log` | state-store ownership synthesis with target schedule qualifiers | Both whole-walk forms are locally smaller. |
| `build/experiments/h019/owner-{proof.py,proof.log}` | exhaustive legal-owner and replay-timeline proof | All write states, consumed reads, and replay observation points agree. |
| `build/experiments/h019/candidate-v1.{synth,pnr}.log` | canonical synthesis with complete-bundle ownership | Whole-PSG map and placement regress; rejected. |
| `build/experiments/h019/candidate-v2.{synth,pnr}.log` | canonical synthesis with retained write-enable OR | Whole-PSG map regresses; router stopped after the mapped gate failed. |
| `build/experiments/h020/containment-{proof.py,proof.log}` | exhaustive wavetable-read/replay containment proof | All six possible read phases and following replay edges remain inside `prun`. |
| `build/experiments/h020/isolated-{baseline,candidate}.log` | registered audio-RAM/top-level hold cone | Exact candidate saves one local LUT4. |
| `build/experiments/h020/candidate.{synth,pnr}.log` | canonical synthesis without exported `seq_frozen` | Whole-PSG map and seed-1 placement regress; rejected. |
| `build/experiments/h021/filter-{proof.py,proof.log}` | exhaustive wrapped-base-3 proof | All 32 filter codes agree. |
| `build/experiments/h021/isolated-{baseline,arith,staged}.log` | complete registered filter decoder/consumer synthesis | Both arithmetic forms are larger than the case table. |
| `build/experiments/h022/clamp_proof.py` and `clamp-proof.log` | exhaustive signed clamp and live-range proof | All signed-nine inputs and live signed-eight sums agree. |
| `build/experiments/h022/candidate-v2.{synth,pnr}.log` | canonical synthesis with the accepted eight-bit prefix clamp | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h022/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h022/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h023/octave_proof.py` | exhaustive scratch octave/chromatic proof | All 64 slide pitches agree with quotient/remainder. |
| `build/experiments/h023/isolated-{baseline,candidate}.log` | registered octave/chromatic `synth_ice40` comparison | Candidate removes one LUT4 and 11 carries locally. |
| `build/experiments/h023/candidate.{synth,pnr}.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H023 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h023/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h023/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h024/row_bound_probe.sv` | registered pair of current and prefix row bounds | Isolated comparison source. |
| `build/experiments/h024/isolated-{baseline,candidate}.log` | `synth_ice40` comparison of both registered bounds | Exact prefix pair removes two carries with identical LUT4/FF counts. |
| `build/experiments/h024/candidate.{synth,pnr}.log` | canonical synthesis with the rejected prefix pair | Whole-PSG map and placement regress; rejected. |
| `build/experiments/h025/fade_sum_probe.sv` | current repeated fade adds versus one explicit sum | Formal and isolated-synthesis source. |
| `build/experiments/h025/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 25 output equivalence cells proved. |
| `build/experiments/h025/isolated-{baseline,candidate}.log` | registered fade-consumer `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h026/ta_ge_probe.sv` | current relation and two carry-out variants | Formal and isolated-synthesis source. |
| `build/experiments/h026/equiv-v1.log` | Yosys equivalence of the raw carry | Refuted by the `a=255,b=0` tenth-bit overflow corner. |
| `build/experiments/h026/equiv.log` | Yosys equivalence of the repaired carry | Exact form proved. |
| `build/experiments/h026/isolated-{baseline,candidate-v1,candidate}.log` | registered predicate `synth_ice40` comparison | Repaired form saves nine carries with identical LUT4/FF counts. |
| `build/experiments/h026/candidate.{synth,pnr}.log` | canonical synthesis with the repaired carry | Whole-PSG map and placement regress; rejected. |
| `build/experiments/h027/noise_clamp_probe.sv` | current relational and exact signed-prefix clamps | Formal and isolated-synthesis source. |
| `build/experiments/h027/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 16 result bits proved for the full signed-18 domain. |
| `build/experiments/h027/isolated-{baseline,candidate}.log` | registered clamp `synth_ice40` comparison | Candidate removes all 32 carries for two LUT4s. |
| `build/experiments/h027/candidate.{synth,pnr}.log` | canonical synthesis with H027 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h027/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h027/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h028/arp_speed_probe.sv` | relational and exact-prefix `arp_idx` consumers | Formal and isolated-synthesis source. |
| `build/experiments/h028/equiv.log` | Yosys `equiv_make` / `equiv_simple` | Both output bits proved. |
| `build/experiments/h028/isolated-{baseline,candidate}.log` | registered selector `synth_ice40` comparison | Candidate removes four carries for two LUT4s locally. |
| `build/experiments/h028/candidate.{synth,pnr}.log` | canonical synthesis with the exact prefix | Whole-PSG map and placement regress; rejected. |
| `build/experiments/h029/noise_kick_probe.sv` | relational kick cone and bounded signed margin | Formal and isolated-synthesis source. |
| `build/experiments/h029/equiv.log` | Yosys `equiv_make` / `equiv_simple` | Enable bit proved over the full input domain. |
| `build/experiments/h029/isolated-{baseline,candidate}.log` | registered kick cone `synth_ice40` comparison | Candidate removes 22 LUT4s locally. |
| `build/experiments/h029/candidate.{synth,pnr}.log` | canonical synthesis with the affine margin | Whole-PSG placement regresses; rejected. |
| `build/experiments/h030/trigger_length_probe.sv` | relational and exact-prefix registered saturation consumers | Formal and isolated-synthesis source. |
| `build/experiments/h030/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All six registered result bits proved. |
| `build/experiments/h030/isolated-{baseline,candidate}.log` | registered saturation `synth_ice40` comparison | Candidate removes both carries with identical LUT4/FF counts. |
| `build/experiments/h030/candidate.{synth,pnr}.log` | canonical synthesis with H030 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h030/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h030/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h031/tnl_compare_probe.sv` | registered current and shared comparator consumers | Formal and isolated-synthesis source. |
| `build/experiments/h031/equiv.log` | Yosys `equiv_make` / `equiv_simple` | Both registered consumer outputs proved. |
| `build/experiments/h031/isolated-{baseline,candidate}.log` | registered paired-comparator `synth_ice40` comparison | Candidate removes seven carries with identical LUT4/FF counts. |
| `build/experiments/h031/candidate.{synth,pnr}.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H031 | Accepted mapping, seed-1 placement, and final routed timing. |
| `build/experiments/h031/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h031/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h032/record_base_probe.sv` | registered current and record-first address consumers | Formal and isolated-synthesis source. |
| `build/experiments/h032/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 13 registered address bits proved. |
| `build/experiments/h032/isolated-{baseline,candidate}.log` | registered audio-address `synth_ice40` comparison | Candidate removes one LUT4 and seven carries locally. |
| `build/experiments/h032/candidate.{synth,pnr}.log` | canonical synthesis with the record-first address | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h033/readback_activity_probe.sv` | registered current and paired-bit CPU readback consumers | Formal and isolated-synthesis source. |
| `build/experiments/h033/{equiv-induct,exhaustive}.log` | temporal-induction and all-tuple identity proofs | All eight registered outputs and 1,024 Boolean cases proved. |
| `build/experiments/h033/isolated-{baseline,candidate}.log` | registered CPU-readback `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h034/pattern_rows_probe.sv` | relational and exact-prefix registered saturation consumers | Formal and isolated-synthesis source. |
| `build/experiments/h034/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All six registered result bits proved. |
| `build/experiments/h034/isolated-{baseline,candidate}.log` | registered pattern-row `synth_ice40` comparison | Candidate removes two carries for one LUT4 locally. |
| `build/experiments/h034/candidate.{synth,pnr}.log` | canonical synthesis with the exact prefix | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h035/detune_suffix_probe.sv` | independent and explicitly nested suffix/ceiling consumers | Formal and isolated-synthesis source. |
| `build/experiments/h035/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 22 registered result bits proved. |
| `build/experiments/h035/isolated-{baseline,candidate}.log` | registered suffix/ceiling `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h036/tilt_quotient_probe.sv` | parallel and preselected registered quotient consumers | Formal and isolated-synthesis source. |
| `build/experiments/h036/equiv.log` | reset-constrained three-step Yosys SAT miter | Complete registered outputs proved after reset. |
| `build/experiments/h036/isolated-{baseline,candidate}.log` | registered quotient `synth_ice40` comparison | Candidate removes five LUT4s and ten flops locally. |
| `build/experiments/h036/candidate.synth.log` | canonical mapping with the selected register | Adds 54 LUT4s and seven flops globally; rejected. |
| `build/experiments/h036/candidate.pnr.log` | canonical seed-1 router2 attempt | Stopped at two overused wires after iteration 14,424. |
| `build/experiments/h037/tilt_h7_width_probe.sv` | ten-bit and live-mode-nine-bit quotient consumers | Formal and isolated-synthesis source. |
| `build/experiments/h037/equiv.log` | reset-constrained three-step Yosys SAT miter | Complete upstream/registered outputs proved. |
| `build/experiments/h037/isolated-{baseline,candidate}.log` | registered quotient `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h038/boost_gain_probe.sv` | nested shift-add and affine/residue gain consumers | Formal and isolated-synthesis source. |
| `build/experiments/h038/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 13 registered result bits proved. |
| `build/experiments/h038/isolated-{baseline,candidate}.log` | registered gain `synth_ice40` comparison | Candidate adds 28 LUT4s with carries/flops unchanged. |
| `build/experiments/h039/rec_base_probe.sv` | original and aligned registered record-base transforms | Formal and isolated-synthesis source. |
| `build/experiments/h039/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 13 registered address bits proved. |
| `build/experiments/h039/isolated-{baseline,candidate}.log` | registered record-base `synth_ice40` comparison | Candidate removes one isolated flop with LUT4/carry counts unchanged. |
| `build/experiments/h039/candidate.{synth,pnr}.log` | canonical synthesis with aligned `rec_base()` | Accepted mapping, seed-1 placement, and routed timing. |
| `build/experiments/h039/budget-{28125000,22500000}.log` | correctly parameterized `/4` and `/5` budget regressions | Both pass at the established H031 cadence. |
| `build/experiments/h039/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h039/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |
| `build/experiments/h040/org_ramp_probe.sv` | truncated negation and explicit conditional-complement organ consumers | Formal and isolated-synthesis source. |
| `build/experiments/h040/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 55 internal and registered consumer bits proved. |
| `build/experiments/h040/isolated-{baseline,candidate}.log` | registered organ-address `synth_ice40` comparison | Candidate removes 13 LUT4s locally for one carry. |
| `build/experiments/h040/candidate.{synth,pnr}.log` | canonical synthesis with explicit organ fold | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h041/fade_length_probe.sv` | registered consumers plus explicit-prior-state next-state pair | Exact scratch proof and isolated-synthesis source. |
| `build/experiments/h041/fade_length_proof.py` | exhaustive unsigned-byte enumeration | The threshold identity passes all 256 values. |
| `build/experiments/h041/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All 42 next-state bits proved for arbitrary shared prior state. |
| `build/experiments/h041/isolated-{baseline,candidate}.log` | complete registered fade-control consumer | Candidate trades two LUT4s for four carries locally. |
| `build/experiments/h041/candidate.{synth,pnr}.log` | canonical synthesis with the shared exact prefix | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h042/dq_r193_{probe.sv,proof.py}` | formal/synthesis source and exhaustive residue proof | The correction and complete split pass all 256 residues. |
| `build/experiments/h042/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All ten correction/result bits proved. |
| `build/experiments/h042/isolated-{baseline,candidate}.log` | complete registered triangle-remainder consumer | Candidate removes one LUT4 locally. |
| `build/experiments/h042/candidate.{synth,pnr}.log` | canonical synthesis with the exact Boolean carry | Whole-PSG mapping and placement regress; rejected. |
| `build/experiments/h043/ea5_length_{probe.sv,proof.py}` | formal/synthesis source and exhaustive tuple proof | Active/stop/advance behavior passes all 4,096 tuples. |
| `build/experiments/h043/equiv.log` | Yosys `equiv_make` / `equiv_simple` | All nine exposed result bits proved. |
| `build/experiments/h043/isolated-{baseline,candidate}.log` | complete registered EA5 consumer | Both forms map identically. |
| `build/experiments/h044/blend_counter_{probe.sv,proof.py}` | recurrence, formal, and isolated-synthesis source | Reachable domain is exactly 0..64; bit six is exactly terminal. |
| `build/experiments/h044/formal.log` | constrained Yosys SAT | Complete registered terminal consumers proved equivalent. |
| `build/experiments/h044/isolated-{baseline,candidate}.log` | registered crossfade-counter consumer | Candidate removes three LUT4s with carry/FF counts unchanged. |
| `build/experiments/h044/candidate.{synth,pnr}.log` | canonical synthesis with terminal high bit | Accepted mapping, seed-1 placement, and routed timing. |
| `build/experiments/h044/budget-*.log` | correctly parameterized `/4`, `/5`, and `/6` regressions | All sample/tick deadlines pass with zero late flips. |
| `build/experiments/h044/preview-*.log` | hardware/PREVIEW cadence checks at both clocks | All masks pass the 95% gate. |
| `build/experiments/h044/{recovery-*,click-*,celeste-smoke*}` | recovery, exact click renders, and five-frame smoke | Recovery passes, zero clicks, and active nonconstant audio. |
| `build/experiments/h045/filter_trit_{probe.sv,proof.py}` | complete three-consumer source and exhaustive trit proof | `fdec` and max closure pass over the full bounded domains. |
| `build/experiments/h045/formal.log` | constrained Yosys SAT | All six registered output bits prove equivalent for valid trits. |
| `build/experiments/h045/isolated-{baseline,candidate}.log` | registered filter-maximum `synth_ice40` comparison | Both forms map identically. |
| `build/experiments/h046/effect_class_{probe.sv,proof.py}` | complete normalized-effect source and exhaustive 256-input proof | All three flags and the already-live `e_fx` result agree. |
| `build/experiments/h046/formal.log` | unconstrained Yosys SAT | All six exposed result bits prove equivalent over the complete input domain. |
| `build/experiments/h046/isolated-{baseline,candidate}.log` | registered publication-consumer `synth_ice40` comparison | Candidate removes three LUT4s with carry/FF counts unchanged. |
| `build/experiments/h046/candidate.{synth,pnr}.log` | canonical whole-PSG synthesis | Global LUT4, LC-floor, and routed-LC regression; rejected. |
| `build/experiments/h047/wave_scale_{probe.sv,proof.py}` | formal/synthesis source and exhaustive signed proof | All 1,048,576 signed-18/context tuples agree. |
| `build/experiments/h047/formal.log` | unconstrained Yosys SAT | The complete selected-shift output proves equivalent. |
| `build/experiments/h047/isolated-{baseline,candidate}.log` | registered final-waveform consumer | Candidate removes 44 LUT4s and 33 carries. |
| `build/experiments/h047/candidate.{synth,pnr}.log` | canonical whole-PSG synthesis | Accepted mapping, 7,025-cell floor, 7,251 routed LCs, and passing timing. |
| `build/experiments/h047/{budget-*,preview-*,recovery-*,click-*,celeste-smoke*}` | complete cadence, fidelity, and smoke battery | All gates pass; exact click WAVs match H044. |
| `build/experiments/h048/wave_context_{probe.sv,proof.py}` | source-exact selector proof and formal/synthesis source | All legal hardware/PREVIEW contexts and generated control words pass. |
| `build/experiments/h048/{proof,formal}.log` | exhaustive schedule audit and constrained Yosys SAT | Selector axes and arbitrary valid-input outputs prove equivalent. |
| `build/experiments/h048/isolated-{baseline,candidate}.log` | registered selector `synth_ice40` comparison | Candidate adds 16 LUT4s with carry/FF counts unchanged. |
| `build/experiments/h049/square_threshold_{probe.sv,proof.py}` | exhaustive/formal source and registered synthesis probe | All 1,048,576 tuples and the complete signed output agree. |
| `build/experiments/h049/{exhaustive,formal}.log` | exhaustive enumeration and unconstrained Yosys SAT | Exact threshold relations pass. |
| `build/experiments/h049/isolated-{baseline,candidate}.log` | registered constant-output `synth_ice40` comparison | Candidate trades two LUT4s for five carries locally. |
| `build/experiments/h049/candidate.{synth,pnr}.log` | canonical whole-PSG mapping and bounded seed-1 placement/route | LUT/floor/placed area regress; route stopped at two overused wires. |
| `build/experiments/h049/candidate.census.log` | mapped flop-packing census | 6,529 LUT4, 520 unpackable, 7,049-cell floor. |
| `build/experiments/h050/upload_page_{probe.sv,proof.py}` | exhaustive/formal source and registered synthesis probe | All-page and valid-domain index identities pass. |
| `build/experiments/h050/{exhaustive,formal,formal-valid}.log` | exhaustive enumeration and Yosys SAT | Both exact domains prove. |
| `build/experiments/h050/isolated-{baseline,candidate-v1,candidate-v2}.log` | registered 13-bit index synthesis | Variant 2 removes three carries with LUT4/FF counts unchanged. |
| `build/experiments/h050/candidate-v1.{synth,pnr}.log` | canonical whole-PSG synthesis with all-page Boolean outputs | LUT/floor/placed area regress; rejected. |
| `build/experiments/h050/candidate-v2.{synth,pnr}.log` | canonical synthesis with valid-domain fifth bit | Smaller regression, but still fails LUT/floor/placement. |
| `build/experiments/h050/candidate-v{1,2}.census.log` | mapped flop-packing census | Exact mapped floors for both rejected variants. |
| `build/experiments/h051/dq_count_{probe.sv,proof.py}` | constrained formal source and exhaustive state proof | The six reachable binary states map exactly to idle plus the five LFSR states. |
| `build/experiments/h051/{formal,isolated-baseline,isolated-candidate,test-psg-dq}.log` | constrained SAT, isolated synthesis, and exhaustive service tests | Public state/product behavior is exact and the complete service removes one carry. |
| `build/experiments/h051/candidate.{synth,pnr}.log` and `candidate.census.log` | forced canonical whole-PSG synthesis | 6,506 LUT4, 1,421 carries, 7,028-cell floor, 7,247 routed LCs, and passing timing. |
| `build/experiments/h051/{budget-*,preview-*,recovery-*,click-*,celeste-smoke*}` | complete cadence, fidelity, and smoke battery | All gates pass; exact click WAVs match H047. |
| `build/experiments/h052/fold_final_{probe.sv,proof.py}` | legal-state formal source and exhaustive controller proof | All operands, destinations, transitions, and publication events agree. |
| `build/experiments/h052/{formal,isolated-baseline,isolated-candidate}.log` | constrained SAT and complete-controller `synth_ice40` comparison | Candidate adds three LUT4s with mapped flops unchanged; rejected. |
| `build/experiments/h053/fold_publish_{probe.sv,proof.py}` | legal-state formal source and exhaustive controller proof | Full-mode busy and publication waveforms agree on every legal path. |
| `build/experiments/h053/{formal,isolated-baseline,isolated-candidate}.log` | constrained SAT and complete-controller `synth_ice40` comparison | Candidate removes one FF for five LUT4s locally. |
| `build/experiments/h053/candidate.{synth,pnr}.log` and `candidate.census.log` | forced canonical whole-PSG synthesis | LUT/floor/placement regress despite the one-FF saving; rejected. |
| `build/experiments/h054/triangle_fold_{probe.sv,proof.py}` | exact centered-triangle identity, registered consumers, and exhaustive proof | All 65,536 phases and unconstrained SAT pass. |
| `build/experiments/h054/isolated-{baseline,candidate}.log` | registered primary triangle and `/4` consumer `synth_ice40` comparison | Candidate changes 60/45/34 LUT4/carry/FF to 71/44/34. |
| `build/experiments/h055/noise_round_{probe.sv,proof.py}` | exact signed product-rounding forms and exhaustive proof | All 262,144 cases and unconstrained SAT pass. |
| `build/experiments/h055/isolated-{baseline,candidate,candidate-shared}.log` | complete dual-sign registered consumer `synth_ice40` comparison | Inlining doubles carries; shared limbs save one LUT4 and expose two duplicate sign flops. |
| `/private/tmp/fpga-psg-area-direct-continuation/build/targets/psg.{json,pnr.log}` | forced direct-frontier H055 synthesis and seed-1 route | Map/floor improve, but route is stopped after 21,160 iterations fixed at two overused wires. |
| `build/experiments/h056/organ_hi_{probe.sv,proof.py}` and `formal.log` | exhaustive phase/bypass proof plus unconstrained Yosys SAT | All 131,072 cases and the arbitrary-input two-stage selector prove equivalent. |
| `build/experiments/h056/isolated-{baseline,candidate}.log` | complete two-stage organ branch synthesis | Candidate changes 81/15/38 LUT4/carry/FF to 81/15/37. |
| `build/experiments/h056/candidate.{synth,pnr}.log` and `candidate.census.log` | twice-forced canonical direct-frontier synthesis | 6,489 LUT4, 1,403 carries, 1,459 FF, 498 unpackable, floor 6,987, 7,224 routed LCs, and passing timing. |
| `build/experiments/h056/preview-*.log` | hardware/PREVIEW pitch checks at both clocks and masks 7/1/2/4 | All eight checks pass with 95% or 100% voiced-window agreement. |
| `build/experiments/h056/{recovery-*,click-*,celeste-smoke*}` | recovery, exact click renders, and five-frame smoke | Recovery passes, click WAVs are H051-byte-identical with zero clicks, and Celeste audio is active/nonconstant. |
| `build/experiments/h057/{formal,sequential,isolated-*,forms-*,hw-forms}.log` | exhaustive, SAT, isolated synthesis, and permanent forms | State reconstruction is exact; isolated mapping is +11 LUT4/-1 FF. |
| `build/experiments/h057/candidate{,-first}.{synth.log,pnr.log,json,asc}` | forced canonical HX8K synthesis | Both runs reproduce 6,466 LUT4 / 1,403 carry / 1,458 FF / floor 6,968 / 7,204 LCs and identical JSON/ASC. |
| `build/experiments/h057/{test-psg,bytecheck,budget-*,test-clocks,preview-*}.log` | complete structural, render, cadence, clock, and preview battery | All exact gates pass at the recorded demand and 95% preview agreement. |
| `build/experiments/h057/{recovery-*,click-*,celeste-smoke*}` | recovery, same-tool exact click renders, and five-frame smoke | Recovery passes, click WAVs are H056-byte-identical with zero clicks, and Celeste audio is active/nonconstant. |
| `build/experiments/h058/{state_replay_probe.sv,state-replay-formal.log}` | symbolic full/PREVIEW transition and hold-equivalence proof | Replay containment and baseline/candidate hold equality pass for all inputs. |
| `build/experiments/h058/candidate.{json,synth.log,pnr.log,census.log}` | canonical H057-based mapping and seed-1 route attempt | Candidate maps at 6,490 LUT4 / 1,408 carry / 1,457 FF / floor 6,989, places at 7,235 LCs, and remains unrouted at two overused wires through 55,386 iterations. |
| `build/experiments/h059/{organ_h_probe.sv,organ_h_proof.py,exhaustive.log,formal.log}` | exhaustive 524,288-case proof plus unconstrained Yosys SAT | Exact full and partial reconstruction of the organ quotient byte from registered `z_lin_r`. |
| `build/experiments/h059/isolated-{baseline,candidate,candidate-partial}.log` | complete registered organ reciprocal consumer synthesis | Full/partial reconstruction retire eight/two FF and 15 carries, but each adds one LUT4 locally. |
| `build/experiments/h059/candidate-{full,partial}.{json,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG mapping and seed-1 route | Both variants regress deterministic area; full routes at 7,229 LCs and partial remains at two overused wires after 7,255 iterations. |
| `build/experiments/h060/{tri4_probe.sv,tri4_proof.py,exhaustive.log,formal.log}` | exhaustive 262,144-case proof plus three-step sequential Yosys SAT | Exact reconstruction of the alternate-triangle `/4` payload from registered `z_lin_r`. |
| `build/experiments/h060/isolated-{baseline,candidate}.{json,log}` | complete registered alternate-triangle consumer synthesis | Candidate is equal in LUT4s, +1 carry, -16 FF, and -2 floor cells locally. |
| `build/experiments/h060/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +54 LUT4, +1 carry, -16 FF, +50 floor, and +53 routed LCs with both clocks passing. |
| `build/experiments/h061/{fade_state_probe.sv,fade_state_proof.py,exhaustive.log,formal.log}` | exhaustive 4,202,496-transition proof plus symbolic Yosys SAT | Active, fresh fade-out, completion, idle, and command-interruption state all preserve gain and stop behavior. |
| `build/experiments/h061/isolated-{baseline,candidate}.{json,log}` | complete registered fade-state consumer synthesis | Compression removes eight FF but adds eight LUT4s and six deterministic floor cells; rejected before production. |
| `build/experiments/h062/{old_noise_probe.sv,old_noise_proof.py,exhaustive.log,formal.log,sequential.log}` | exhaustive snapshot proof plus combinational and four-step sequential Yosys SAT | Same-edge old-tuple reconstruction is exact for all restart and retained-tuple cases. |
| `build/experiments/h062/isolated-{baseline,candidate}.{json,log}` | complete registered old-noise selector consumer synthesis | Candidate is -2 LUT4, -1 FF, and -2 floor cells locally. |
| `build/experiments/h062/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +55 LUT4, -1 FF, +53 floor, and +57 routed LCs with both clocks passing. |
| `build/experiments/h063/{old_sign_probe.sv,old_sign_proof.py,sequential.log}` | source assignment audit, 512 endpoint schedules, and 70-step arbitrary-stall Yosys SAT | The captured W15 old-arm sign equals the live W51 sign for every active built-in-wave consumer. |
| `build/experiments/h063/isolated-{baseline,candidate}.{json,log}` | complete old-arm sign consumer synthesis | Candidate keeps 47 LUT4/15 carry and removes one FF locally. |
| `build/experiments/h063/{baseline-current,candidate}.{json,synth.log,census.log}` and `candidate.{asc,pnr.log}` | same-current-Yosys mapped comparison plus canonical seed-1 candidate route | Candidate is +64 LUT4, +4 carry, -1 FF, +62 floor, and +69 routed LCs with both clocks passing. |
| `build/experiments/h064/{noise_draw_probe.sv,noise_draw_proof.py,formal.log}` | NumPy-exhaustive 524,288-case proof plus combinational Yosys SAT | Selected-source adjacent-XOR draw and both individual signs are exact. |
| `build/experiments/h064/isolated-{baseline,candidate}.{json,log}` | complete registered noise request/sign consumer synthesis | Candidate is -2 LUT4 with carries and FF unchanged. |
| `build/experiments/h064/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +55 LUT4, +4 carry, +54 floor, and +63 routed LCs with both clocks passing. |
| `build/experiments/h065/{sample_width_probe.sv,sample_width_proof.py,formal.log}` | exact range proof over all built-in/composed values and 67,108,864 custom-wave tuples plus Yosys SAT | Every stored sample fits signed 16 bits and every widened consumer is equivalent. |
| `build/experiments/h065/isolated-{baseline,candidate}.{json,log}` | complete registered sample-boundary synthesis | Candidate is -3 LUT4, -1 carry, and -4 FF locally. |
| `build/experiments/h065/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +27 LUT4, -4 carry, -4 FF, +27 floor, and +32 routed LCs with both clocks passing. |
| `build/experiments/h066/{tail_sentinel_probe.sv,tail_sentinel_proof.py,exhaustive.log,formal.log}` | exhaustive 1,048,576-case range/selection proof plus SAT induction | Live payloads are at most 105 and the reserved 127 sentinel preserves every tail choice. |
| `build/experiments/h066/isolated-{baseline,candidate}.{json,log}` | complete registered reciprocal-tail consumer synthesis | Candidate is +6 LUT4 and -1 FF with carries unchanged. |
| `build/experiments/h066/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is +42 LUT4, +4 carry, -1 FF, +40 floor, +47 routed LCs, and fails fast timing. |
| `build/experiments/h067/{tilt_prefix_probe.sv,tilt_prefix_proof.py,exhaustive.log,formal.log}` | exhaustive 524,288-value slice proof plus SAT induction | Both registered quotient views reconstruct exactly from one four-bit prefix and `t_pre_r`. |
| `build/experiments/h067/isolated-{baseline,candidate}.{json,log}` | complete registered quotient consumer synthesis | Both forms map identically at 19 LUT4s and 29 FF. |
| `build/experiments/h068/{dq_hold_probe.sv,dq_hold_proof.py,exhaustive.log,formal.log}` | 57,344-case global-NumPy transaction proof plus terminal/idle SAT relation | The held pre-terminal recurrence preserves valid results under the walker's stable-operand lifetime. |
| `build/experiments/h068/isolated-{baseline,candidate}.{json,log}` | complete DQ-service synthesis | Candidate is -6 LUT4 with carries/flops unchanged. |
| `build/experiments/h068/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H057-based whole-PSG synthesis and seed-1 route | Candidate is -9 LUT4, +1 carry, +12 unpackable FF, +3 floor, and +6 routed LCs. |
| `build/experiments/h069/{tzs_probe.sv,tzs_proof.py,exhaustive.log,formal.log}` | exhaustive 1,048,576-case global-NumPy proof plus Yosys SAT | Arithmetic shift plus negative nonzero-remainder correction is exact for every signed18 value and shift 0..3. |
| `build/experiments/h069/isolated-{baseline,candidate}.{json,log}` | complete five-consumer shared-helper synthesis | Candidate is -30 LUT4 and -40 carries. |
| `build/experiments/h069/candidate{,-first}.{json,asc,synth.log,pnr.log,census.log}` | two canonical forced H057-based whole-PSG builds | Both builds are byte-identical at -10 LUT4, -33 carry, +1 FF, +1 unpackable, -9 floor, and -5 routed LCs. |
| `build/experiments/h069/{test-psg.log,bytecheck.log,budget-*,preview-*,recovery-*,click-*,celeste-smoke*}` | complete H057 fidelity, cadence, preview, recovery, click, and smoke battery | Every gate passes; hardware/PREVIEW SFX-10 WAVs are byte-identical to H057. |
| `build/experiments/h070/{div_count_probe.sv,div_count_proof.py,exhaustive.log,formal.log}` | 50-transition exhaustive proof plus complete next-state SAT relation | The 24-state token preserves busy, load, arithmetic-step, quotient, and remainder timing exactly. |
| `build/experiments/h070/isolated-{baseline,candidate}.log` | complete restoring-divider synthesis | Candidate is -1 LUT4 and -3 carries with flops unchanged. |
| `build/experiments/h070/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H069-based whole-PSG synthesis and seed-1 route | Candidate is +23 LUT4, -7 carry, +23 floor, and +17 routed LCs with both clocks passing. |
| `build/experiments/h071/{blend_round_probe.sv,blend_round_proof.py,exhaustive.log,formal.log}` | exhaustive signed-24 proof plus complete registered-consumer equivalence | All 16,777,216 values and 83 formal points pass. |
| `build/experiments/h071/isolated-{baseline,candidate}.log` | complete registered blend-consumer synthesis | Candidate is -8 LUT4 and -6 carries with flops unchanged. |
| `build/experiments/h071/candidate{,-v2}.{json,synth.log,census.log}` | two canonical H069-based whole-PSG mappings | Both regress LUT4s and deterministic floor, so neither is routed. |
| `build/experiments/h072/{dampen_round_probe.sv,dampen_round_proof.py,exhaustive.log,formal.log}` | exhaustive signed-19/mode proof plus complete registered-consumer equivalence | All 1,572,864 tuples and 89 formal points pass. |
| `build/experiments/h072/isolated-{baseline,candidate}.log` | complete registered dampen-consumer synthesis | LUT4/FF identical; candidate removes two carries. |
| `build/experiments/h072/candidate.{json,synth.log,census.log}` | canonical H069-based whole-PSG mapping | Candidate is +26 LUT4, -5 carry, and +24 floor cells, so it is not routed. |
| `build/experiments/h073/{noise_offset_probe.sv,noise_offset_proof.py,exhaustive.log,formal.log}` | exhaustive 13-bit proof plus complete registered-consumer equivalence | All 8,192 inputs and 42 formal points pass. |
| `build/experiments/h073/isolated-{baseline,candidate}.log` | complete registered noise-request operand synthesis | Both forms map identically at 11 LUT4/10 carry/14 FF. |
| `build/experiments/h074/{slide_carry_proof.py,exhaustive.log}` | complete reachable-domain affine-slide precision check | Refuted at pitch 2/fraction 9,668 before synthesis. |
| `build/experiments/h075/{wavetable_sign_probe.sv,wavetable_sign_proof.py,formal.log,forms.log}` | exhaustive 1,048,576-tuple proof, 35-point Yosys equivalence, and permanent forms | Operand inversion plus sign carry-in exactly replaces conditional negation before the base add. |
| `build/experiments/h075/isolated-{baseline,candidate}.log` | complete registered wavetable consumer synthesis | Candidate is -25 LUT4 and -8 carries with 17 flops unchanged. |
| `build/experiments/h075/candidate{,-second}.{json,asc,synth.log,pnr.log}` | two canonical forced H069-based whole-PSG builds | Both builds are bit-identical at -23 LUT4, -8 carry, -2 unpackable FF, -25 floor, and -26 routed LCs. |
| `build/experiments/h075/{test-psg.log,bytecheck.log,budget-*,preview-*,recovery-*,click-*,celeste-smoke*}` | complete H069 fidelity, cadence, preview, recovery, click, and smoke battery | Every gate passes; same-tool H069/H075 SFX-10 PREVIEW and hardware WAVs are byte-identical. |
| `build/experiments/h076/{tilt_affine_proof.py,exhaustive.log}` | exhaustive actual-domain affine proof | Both branches match for all 131,072 mode/phase tuples and the first limb fits unsigned17. |
| `build/experiments/h076/{tilt_affine_probe.sv,isolated-baseline.log,isolated-candidate.log}` | complete registered tilt-consumer synthesis | Candidate is -12 LUT4 and -1 carry with 28 flops unchanged. |
| `build/experiments/h076/candidate.{json,synth.log,census.log}` | canonical H075-based whole-PSG mapping | Candidate is +5 LUT4, -1 carry, +1 unpackable FF, and +6 floor cells, so it is not routed. |
| `build/experiments/h077/{tilt_index_proof.py,exhaustive.log}` | exhaustive selected-index/address proof | All 1,048,576 mode/source tuples match, including native-width wrap. |
| `build/experiments/h077/{tilt_index_probe.sv,isolated-baseline.log,isolated-candidate.log}` | complete registered tilt-consumer synthesis | Both forms map identically at 129 LUT4, 69 carry, and 28 FF. |
| `build/experiments/h078/{soft_add_threshold_proof.py,exhaustive.log}` | exhaustive registered-sum and quotient proof | Legal signed-16 fold domain and controller cycles match; the illegal wrapped tail is recorded explicitly. |
| `build/experiments/h078/{soft_add_threshold_formal.sv,formal.log}` | SAT over arbitrary signed-16 operand pairs | All 2^32 operand pairs prove the registered threshold join. |
| `build/experiments/h078/{soft_add_fold_probe.sv,isolated-baseline.log,isolated-candidate.log}` | complete registered fold-engine synthesis | Candidate is +6 LUT4 with 25 carry, 66 FF, and one EBR unchanged. |
| `build/experiments/h079/{reverb_round_proof.py,exhaustive.log,reverb_round_formal.sv,formal.log}` | exhaustive and SAT dual-comb identity proof | All signed19 accumulator values and both complete input tuples match. |
| `build/experiments/h079/{reverb_round_probe.sv,isolated-baseline.log,isolated-candidate.log}` | complete registered dual-comb/blend consumer | Candidate is -2 carry with 139 LUT4 and 52 FF unchanged. |
| `build/experiments/h079/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H075-based whole-PSG synthesis and seed-1 route | 6465 LUT4 / 1358 carry / 1459 FF / 501 unpackable / floor6966 / 7198 LCs, 118.06/31.24 MHz. |
| `build/experiments/h080/{timing_update_proof.py,timing_update_formal.sv,formal.log,forms-final.log}` | all-state exhaustive proof, SAT equivalence, and permanent forms | The sign-selected delta exactly reproduces both recurrence arms. |
| `build/experiments/h080/isolated-{baseline,candidate}.log` | complete registered `psg_timing` synthesis | Candidate is -41 LUT4 and -23 carries with flops unchanged. |
| `build/experiments/h080/candidate{,-second}.{json,asc}` and `{candidate,repro}.{synth,pnr}.log` | two canonical forced H075-based whole-PSG builds | Both builds are bit-identical at -24 LUT4, -23 carry, -24 floor, and -26 routed LCs. |
| `build/experiments/h080/{click-*,celeste-smoke*,celeste-audio.*}` plus completed gate output | complete H075 fidelity, cadence, preview, recovery, click, and smoke battery | Every gate passes; clean same-tool H075/H080 SFX-10 PREVIEW WAVs are byte-identical. |
| `build/experiments/h081/{slide_adder_formal.sv,formal.log,slide_adder_probe.sv,isolated-*.log}` | all-domain SAT proof and complete registered slide-consumer synthesis | Exact, but +20 LUT4/floor cells despite -25 carries; rejected before production. |
| `build/experiments/h082/{slide_storage_formal.sv,formal.log,slide_storage_probe.sv,isolated-*}` | all-domain lifetime proof and complete registered slide-consumer synthesis | Exact; isolated -18 FF but +20 LUT4 and +1 floor. |
| `build/experiments/h082/candidate.{json,asc,synth.log,pnr.log}` | canonical H080-based whole-PSG build | -18 FF/-4 carry but +28 LUT4/+10 floor; rejected and reverted. |
| `build/experiments/h083/{gain_chain_proof.py,exhaustive.log,gain_chain_formal.sv,formal.log,gain_chain_probe.sv,isolated-*.log}` | exhaustive/SAT proof and complete registered live-gain synthesis | Exact, but +21 LUT4/floor cells for -3 carries; rejected before production. |
| `build/experiments/h084/{scnt_token_proof.py,sequence.log,scnt_token_probe.sv,scnt_token_tb.sv,cadence.log,isolated-*.log}` | maximal-sequence/cadence proof and complete registered timing synthesis | Exact and locally -2 LUT4/-6 carries. |
| `build/experiments/h084/candidate.{json,asc,synth.log,pnr.log}` | canonical H080-based whole-PSG build | +26 LUT4/+6 unpackable/+32 floor/+28 route; rejected and reverted. |
| `build/experiments/h085/{div_round_proof.py,exhaustive.log,div_round_formal.sv,formal.log,div_round_probe.sv,div_round*_tb.sv,transactions*.log,isolated-*}` | exhaustive/SAT/transaction proofs and two complete divider/caller synthesis variants | Both exact; v1 floor +10, terminal v2 floor +33; rejected before production. |
| `build/experiments/h086/{row_inc_proof.py,row_inc_formal.sv,exhaustive.log,formal.log,isolated-*}` | exhaustive/SAT proof and complete paired EA5 consumer synthesis | Exact; isolated -1 LUT4/-3 carries with flops unchanged. |
| `build/experiments/h086/candidate.{json,asc,synth.log,pnr.log,census.log}` | canonical H080-based whole-PSG synthesis and seed-1 route | +7 LUT4/-7 carries/+1 unpackable/+8 floor/-5 route; rejected and reverted. |
| `build/experiments/h087/{vibrato_decode_proof.py,vibrato_decode_formal.sv,exhaustive.log,formal.log,vibrato_decode_probe.sv,isolated-*}` | exhaustive/SAT proof and complete registered vibrato-consumer synthesis | Exact, but candidate is +1 LUT4 with carries/flops unchanged. |
| `build/experiments/h088/{timing_strobe_proof.py,timing_strobe_formal.sv,exhaustive.log,formal.log,timing_strobe_probe.sv,isolated-*}` | reachable-state/SAT proof and complete timing-consumer synthesis | Exact; candidate -2 FF/-1 unpackable but +3 LUT4/+2 floor. |
| `build/experiments/h089/{pitch_select_proof.py,pitch_select_formal.sv,exhaustive.log,formal.log}` | exhaustive selected-pitch proof and unconstrained SAT equivalence | All 2,097,152 operand/control tuples and 512 state/effect selections pass. |
| `build/experiments/h089/isolated-{baseline,candidate}.log` | complete registered pitch-address and slide-consumer synthesis | Candidate is -43 LUT4 and -12 carries with 19 flops unchanged. |
| `build/experiments/h089/candidate{,-second}.{json,asc,synth.log,pnr.log}` | two canonical forced H080-based whole-PSG builds | Both are bit-identical at -63 LUT4, -15 carry, -60 floor, and -74 routed LCs. |
| `build/experiments/h089/{preview-*,recovery-*,click-*,celeste-smoke*}` plus completed gate output | complete H080 fidelity, cadence, preview, recovery, click, and smoke battery | Every gate passes; 59/59 renders are byte-exact and both SFX-10 paths have zero clicks. |
| `build/experiments/h090/{step_count_proof.py,step_count_formal.sv,exhaustive.log,formal.log,step_count_probe.sv,isolated-*}` | exhaustive/SAT proof and complete registered count-load/countdown synthesis | Exact for both radix forms, but production-radix candidate is +1 LUT4 with carry/FF unchanged. |
| `build/experiments/h091/{remaining_counter_refutation.py,refutation.log}` | reachable pending-trigger counterexample | Target 8,160 diverges on the first trigger-free tick after the 13-bit elapsed counter wraps. |
| `build/experiments/h092/{predicate_lifetime_proof.py,predicate_lifetime_formal.sv,exhaustive.log,formal.log,predicate_lifetime_probe.sv,isolated-*,candidate.*}` | exhaustive/SAT proof, complete isolated synthesis, and canonical whole-PSG synthesis | Exact and -1 LUT4/-1 FF alone, but globally +20 LUT4/+3 carries/+20 floor cells. |
| `build/experiments/h093/{dq_coeff_proof.py,dq_coeff_formal.sv,exhaustive.log,formal.log,dq_coeff_probe.sv,isolated-*}` | exhaustive/SAT proof and complete registered DQ service synthesis | Exact, but the grouped table adds three LUT4s with carry/FF unchanged. |
| `build/experiments/h094/{transition_tuple_proof.py,transition_tuple_formal.sv,exhaustive.log,formal.log,transition_tuple_probe.sv,isolated-*,candidate.*}` | structural/SAT proof, complete isolated synthesis, and canonical whole-PSG synthesis | Exact and -1 LUT4 alone, but globally +3 LUT4/+3 floor cells. |
| `build/experiments/h095/{forms*,equiv.log,isolated-*,candidate*,cadence-*,preview-*,recovery-*,click-*,celeste-smoke*}` | exhaustive/formal proof, isolated and two forced whole-PSG builds, and complete acceptance battery | Accepted direct composition at -4 LUT4/-3 carries/-4 floor cells; all fidelity, timing, and reproducibility gates pass. |
| `build/experiments/h096/{budget-*,preview-*,recovery*,clicks*,celeste-smoke*,clocks*,bytecheck*}` plus `build/targets/psg.{json,asc}` | exhaustive protocol proof, two forced whole-PSG builds, and complete merged-main acceptance battery | Accepted `a647185` at -31 LUT4/-1 FF/-28 floor cells; all generic fidelity, timing, and reproducibility gates pass. |
| `build/experiments/h097/{provenance_proof.py,provenance-proof.log,provenance_probe.sv,isolated-*,candidate.*}` | exact path proof, complete isolated provenance synthesis, and canonical whole-PSG synthesis | Exact and -3 LUT4/-1 FF alone, but globally +18 LUT4/+4 carries/+17 floor cells/+20 routed LCs. |
| `build/experiments/h098/{count_proof.py,count-proof.log,count_probe.sv,count_*_r1.*,mulmp.log,candidate.*}` | exact token/freeze proof, isolated count synthesis, 6,020-transaction CDC bench, and canonical whole-PSG synthesis | Exact and -4 LUT4/-2 carries alone, but globally +20 LUT4/+19 floor cells/+16 routed LCs. |
| `build/experiments/h099/{filter_owner_proof.py,filter-owner-proof.log,filter_owner_probe.sv,filter_owner_*.json,filter_owner_*.log,candidate*}` | exhaustive ownership proof, complete isolated registered-consumer synthesis, and two canonical whole-PSG variants | Exact across 4,224 legal paths and -17 LUT4 alone, but both whole-PSG variants regress deterministic floor and seed-1 placement. |
| `build/experiments/h100/{released_domain_proof.py,released-domain-proof.log,released_domain_probe.sv,isolated-*-v2.*}` | exhaustive transition proof, source-matched release-array synthesis, and explicit foreground-only synthesis | Exact across 2,560 transition/consumer cases; both forms map identically at 17 LUT4s/four FF. |
| `build/experiments/h101/{trigger_pending_probe.sv,isolated-*,write_read_counterexample.py,write-read-counterexample.log}` | complete source/one-EBR/two-EBR storage synthesis and exact write/read timing counterexample | Plain EBR floor is smaller but stale for one cycle; exact forwarding raises the 97-cell reference floor to 107/104 cells. |

## Handoff

- Next allowed experiment: H102 on accepted H096 `a647185`, after a fresh
  source/DNR audit; it must remain outside the Active DNR families and
  companion-owned R.84 work.
- Blocked/rejected mechanisms: the Active DNR index above and all companion-
  owned R.84 work.
- Verification still missing: none for accepted H001--H003, H005, or H007.
  H004 and H006 were rejected before production RTL; H005's timing-failing
  spelling remains rejected. H008 was rejected before production RTL. H009
  was rejected after exact proof and whole-PSG synthesis. H010 failed the same
  full-design gate; both RTL/proof patches are reverted and the delayed-tick
  representation family is closed unless its mapped context changes. H011 was
  rejected before production because its exact spelling maps identically.
  H012 CDC proofs pass, but its global map regresses and production RTL is
  reverted. H013's two width variants are exact but physically worse; all
  production/proof changes are reverted and the multiplier-width family closes.
  H014's correction bound is exact but mapping-identical; its production/proof
  patches are reverted and no behavior or physical gate remains.
  H015's output qualifier is exact but mapping-identical; its production/proof
  patches are reverted and no behavior or physical gate remains.
  H016's nine-bit restoring subtract is exact but globally worse; its
  production/proof patches are reverted and no behavior gate remains.
  H017's two context-sharing variants are exact but globally worse; all
  production/proof patches are reverted and the family closes.
  H018's shifted half-sum is exact but globally worse; its production/proof
  patches are reverted and no behavior gate remains.
  H019's whole-walk memory ownership is exact but both mapped forms are
  globally worse; all production/proof changes are reverted and the family
  closes.
  H020's redundant audio-RAM busy export is exact but globally worse; both
  production files are reverted and the family closes.
  H021's filter-code arithmetic is exact but locally larger than the current
  table in both measured forms; no production file changed and the family
  closes.
  H022's exact bounded pitch clamp passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. H023's exact slide-
  octave prefix predicates pass the same complete battery; no verification is
  missing for either accepted RTL/proof change. Because H023 changes
  `rtl/psg_seq.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery.
  H024's prefix row bounds are exact but globally worse; both production and
  permanent-proof changes are reverted and no behavior gate remains.
  H025's explicit shared fade sum is formally exact but mapping-identical; no
  production or permanent-proof file changed.
  H026's repaired rollover carry is exact but globally worse; production and
  permanent-proof changes are reverted and no behavior gate remains.
  H027's exact signed-prefix noise clamp passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  `rtl/psg_walk.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery.
  H028's exact arpeggio-speed prefix is globally worse; production and
  permanent-proof changes are reverted and no behavior gate remains.
  H029's exact affine noise-kick margin is globally placement-worse; production
  and permanent-proof changes are reverted and no behavior gate remains.
  H030's exact trigger-length prefix passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  `rtl/psg_seq.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery.
  H031's shared comparator passes the same complete battery and also changes
  `rtl/psg_seq.sv`; eventual integration has the same proof-regeneration and
  cadence/render obligation.
  H032's record-first audio address is formally exact and locally smaller but
  globally worse; production and permanent-proof edits are reverted and no
  behavior gate remains.
  H033's paired CPU activity bit is exact but mapping-identical in the complete
  registered consumer; no production or permanent-proof file changed.
  H074's first affine-slide carry is required by a reachable exact boundary;
  no production or permanent-proof file changed.
  H034's standalone pattern-row prefix is exact and removes carries locally but
  regresses every whole-PSG area metric; production and permanent-proof edits
  are reverted and no behavior gate remains.
  H035's explicit nested detune suffixes are exact but mapping-identical in the
  complete registered consumer; no production or permanent-proof file changed.
  H036's preselected tilt quotient register is exact and locally smaller but
  globally adds LUT4s/flops and does not route promptly; production and
  permanent-proof edits are reverted and no behavior gate remains.
  H037's nine-bit live-mode `/7` register is exact but mapping-identical in the
  complete registered consumer; no production or permanent-proof file changed.
  H038's collapsed boosted-gain arithmetic is exact but adds 28 LUT4s in the
  complete registered consumer; no production or permanent-proof file changed.
  H039's aligned record-base transform passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  shared address logic in `rtl/psg_common.svh`, eventual integration with C2-C-C
  or R.84 must regenerate and rerun the live-value proof plus the complete
  cadence/render battery.
  H040's explicit organ fold is formally exact and locally smaller but globally
  worse; production and permanent-proof edits are reverted and no behavior
  gate remains.
  H041's shared fade-length prefix is exact and locally saves carries but adds
  LUT4s and placed LCs globally; production and permanent-proof edits are
  reverted and no behavior gate remains.
  H042's four-input triangle-residue truth table is exact and locally removes
  one LUT4 but adds LUT4s, carries, and LCs globally; production and permanent-
  proof edits are reverted and no behavior gate remains.
  H043's shared EA5 active/advance predicates are exact but mapping-identical in
  the complete registered consumer; no production or permanent-proof file
  changed.
  H044's terminal high-bit predicate passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  `rtl/psg_walk.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery. H044 is
  lineage-specific and regresses clean D004 `34340b7`; do not compose or
  cherry-pick it onto that lineage.
  H045's trit-max identity is exact but mapping-identical in the complete
  registered consumer; no production or permanent-proof file changed.
  H046's normalized effect-class reuse is exact and locally smaller but adds
  LUT4s and placed LCs globally; production and permanent-proof edits are
  reverted and no behavior gate remains.
  H047's selected final waveform shift passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate on the H044-derived
  lineage. Because it changes `rtl/psg_wave.sv`, eventual integration with
  C2-C-C/R.84 must regenerate and rerun the live-value proof plus the complete
  cadence/render battery. Direct-D004 composition is independently accepted as
  `a5052c1`, with the 37-carry reduction durable and the 14-LC delta non-robust.
  H048's selector-axis factorization is exact but locally larger; no production
  or permanent-proof file changed.
  H049's exact square/pulse prefix formulas remove carries but regress the
  whole-PSG LUT, floor, and placed counts; production and permanent-proof edits
  are reverted, and the square/pulse-threshold family closes.
  H050's two exact upload-page transforms remove three carries locally and
  globally, but both regress LUT4s, floor, and placement; production and
  permanent-proof edits are reverted, and the transform family closes.
  H051's exact five-state service count passes every proof, physical, fidelity,
  timing, preview, recovery, click, and Celeste-smoke gate. Because it changes
  `rtl/psg_dqsvc.sv`, eventual integration with C2-C-C/R.84 must regenerate and
  rerun the live-value proof plus the complete cadence/render battery.
  H052's exact selector-state final token adds three LUT4s and removes no mapped
  flops in the complete isolated controller; no production or permanent-proof
  file changed, and the fold-final-selector family closes.
  H053's exact fold-state publication token removes one FF but adds 22 LUT4s,
  one carry, and 19 floor/routed cells globally; production and permanent-proof
  edits are reverted, and the fold-publish-state family closes.
  H054's exact centered primary-triangle fold saves one carry but adds eleven
  LUT4s in the complete isolated registered consumer; no production or
  permanent-proof file changed, and the centered-triangle-fold family closes.
  H055's duplicated unified signed-noise rounding doubles isolated carries;
  its shared-limb form removes 15 global LUT4s and 14 floor cells but does not
  complete the canonical seed-1 route. Both production and permanent-proof
  edits are reverted in the clean direct-continuation worktree, and the signed-
  noise-rounding family closes.
  H056's completed-linear-sample predicate passes every proof, physical,
  fidelity, timing, preview, recovery, click, and Celeste-smoke gate. Because
  it changes `rtl/psg_wave.sv`, eventual integration with C2-C-C/R.84 must
  regenerate and rerun the live-value proof plus the complete cadence/render/
  physical battery. No verification remains for direct commit `ac15778`.
  H057's same-edge registered-control predicate passes every proof, physical,
  fidelity, timing, preview, recovery, click, and Celeste-smoke gate. Because
  it changes `rtl/psg_wave.sv`, eventual integration with C2-C-C/R.84 must
  regenerate and rerun the live-value proof plus the complete cadence/render/
  physical battery. No verification remains for direct commit `c9274fc`.
  H058's replay-containment proof passes, but all physical area gates regress
  and seed 1 does not route; the scratch RTL is reverted byte-for-byte and the
  complete fidelity battery is intentionally skipped.
  H059's organ quotient reconstructions are exact but regress the whole-PSG
  map; H060's exact triangle payload reconstruction does the same. H061's fade
  compression is already larger in the complete isolated consumer. H062's
  old-noise flag and H063's old-arm sign lifetime proofs pass, but both one-FF
  retirements trigger decisive global LUT/floor/route regressions. H064's exact
  shared random-draw transform also saves locally and regresses globally.
  H065's exact sample-register contraction removes four mapped flops and
  carries but adds 27 LUT4s/floor cells and 32 routed LCs. H066's exact tail
  sentinel adds 42 LUT4s and fails fast timing. All eight direct-frontier RTL
  variants are reverted byte-for-byte; no fidelity gate or accepted area claim
  remains for H059--H066. H067 is exact but mapping-identical before production;
  no production or permanent-proof file changed. H069's exact shared `tzs`
  rewrite passes the complete battery and forced reproducibility check as
  direct commit `d3ce9a6`. Because it changes `rtl/psg_common.svh`, eventual
  C2-C-C/R.84 integration must
  regenerate and rerun the live-value proof plus the complete cadence/render/
  physical battery. H070's divider-count proof passes and its isolated service
  is smaller, but the whole-PSG floor and placement regress; production and
  permanent-proof edits are reverted byte-for-byte and no fidelity gate or
  accepted area claim remains. H071's blend-rounding identity passes exhaustive
  and formal proof and saves locally, but both global spellings regress the
  deterministic floor; production and permanent-proof edits are reverted
  byte-for-byte and no route/fidelity claim remains. H072's dampen-rounding
  identity passes exhaustive and formal proof and removes carries locally and
  globally, but adds 26 LUT4s and 24 floor cells; production and permanent-
  proof edits are reverted byte-for-byte and no route/fidelity claim remains.
  H073's aligned noise offset is exact but mapping-identical in the complete
  registered consumer; no production or permanent-proof file changed. H075's
  wavetable sign fold passes every exactness, physical, fidelity, timing,
  preview, recovery, click, Celeste-smoke, and forced-reproducibility gate as
  direct commit `c634db2`. Because it changes `rtl/psg_walk.sv`, eventual
  C2-C-C/R.84 integration must regenerate and rerun the live-value proof plus
  the complete cadence/render/physical battery. H076's tilt-affine
  reassociation is exact and locally smaller but regresses the whole-PSG LUT,
  unpackable-flop, and floor counts; its production/permanent-proof edits are
  reverted byte-for-byte and no route or fidelity claim remains. H077's shared
  reciprocal-index adder is exact but mapping-identical in the complete
  registered consumer; no production or permanent-proof file changed. The two
  tilt-family variants are closed unless their recorded conditions change.
  H078's sign-selected soft-add threshold join is exact and cycle-identical
  across the complete legal consumer domain, but adds six LUT4s in the complete
  registered engine; no production or permanent-proof file changed, and the
  soft-add threshold family closes.
  H079's dual reverb round-toward-zero rewrite is exact and saves isolated
  carries, but adds 32 whole-PSG LUT4/floor cells; production and permanent-
  proof edits are reverted byte-for-byte, no fidelity claim remains, and the
  reverb-rounding family closes. H080's shared sample-accumulator update passes
  every exactness, physical, fidelity, timing, preview, recovery, click,
  Celeste-smoke, and forced-reproducibility gate as direct commit `6458450`.
  It touches only `rtl/psg_timing.sv` and `tools/psg_hw_forms.py`; no R.84
  live-value regeneration is required by this change itself. H081's exact
  scheduled slide-adder sharing is rejected before production because its
  selected operands add 20 isolated LUT4/floor cells despite removing 25
  carries. H082's exact storage reuse is also rejected and reverted: retiring
  18 global flops adds 28 LUT4s and ten deterministic floor cells.
  H083's exact live-gain fusion is rejected before production because it adds
  21 isolated LUT4/floor cells for only three removed carries. H084's exact
  three-token LFSR is also rejected and reverted because its local win becomes
  a 32-cell global floor regression. H085's two exact divider-rounding
  relocation variants are rejected before production because both regress the
  complete isolated floor. H086's selected EA5 incrementer is exact and
  smaller in isolation, but adds seven whole-PSG LUT4s and eight deterministic
  floor cells; it is rejected and reverted before fidelity gates. H087's
  direct vibrato sign/magnitude decode is exact but adds one isolated LUT4, so
  no production file changes or downstream gates remain. H088's two derived
  timing strobes are exact but add two isolated floor cells; no production
  file changes or downstream gates remain. H089's state-selected pitch cone
  passes every exactness, physical, fidelity, timing, preview, recovery, click,
  Celeste-smoke, and forced-reproducibility gate as direct commit `996ee40`.
  Because it changes `rtl/psg_seq.sv`, eventual C2-C-C/R.84 integration must
  regenerate and rerun the live-value proof plus the complete
  cadence/render/physical battery. H090's shared step-count decode is exact but
  adds one isolated LUT4; no production or permanent-proof file changed, and
  the count-sharing family closes. H091's remaining-ticks compression is
  refuted by a reachable pending-trigger counter wrap; no production or
  permanent-proof file changed, and the pattern-counter compression family
  closes. H092's exact shared comparator-result flop saves one LUT4 and one FF
  alone, but adds 20 whole-PSG LUT4/floor cells and three carries; production
  and permanent-form edits are reverted byte-for-byte, and the EA2/EA4 result-
  lifetime family closes. H093's grouped DQ coefficient table is exact but
  adds three isolated LUT4s; no production or permanent-proof file changed,
  and the coefficient-decoder spelling family closes. H094's exact packed
  transition inequality saves one isolated LUT4 but adds three whole-PSG LUT4/
  floor cells; production and permanent-form edits are reverted byte-for-byte,
  and the transition-comparison spelling family closes. H095's exact trigger-
  length prefix composes on H089 and passes every proof, physical, fidelity,
  timing, preview, recovery, click, Celeste-smoke, and forced-reproducibility
  gate as direct commit `3d7a2e2`. Because it changes `rtl/psg_seq.sv`,
  eventual C2-C-C/R.84 integration must regenerate and rerun the live-value
  proof plus the complete cadence/render/physical battery. H096 consumes the
  launch worklist after selecting the pacing owner and passes every generic
  exactness, physical, fidelity, timing, preview, recovery, click,
  Celeste-smoke, and forced-reproducibility gate as commit `a647185`. It
  changes `rtl/psg_seq.sv`, so the H095-bound source certificate and C2-C-C
  live-value lineage must be regenerated before companion integration; this
  task makes no R.84/B2 proof claim.
- Files to avoid staging: all executor/controller proof files, companion
  continuation edits, and unrelated repository changes.
