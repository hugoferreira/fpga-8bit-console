# PSG Source Clarity Ledger

This ledger is the mandatory resume surface for the PSG clarity refactor. The
accepted H139 implementation is the behavioral and physical contract; source
clarity is useful only when that contract remains intact.

## Context

- Topic: make the production PSG RTL understandable, ergonomic, organised,
  DRY, modular, and documented in terms of the current design.
- Owner scope: `rtl/psg.sv`, `rtl/psg_common.svh`, and the ten
  service/datapath modules textually included by `psg.sv`. Testbenches and
  tooling stay only when they exercise or explain this live production tree.
- Correctness gate: preserve the complete live H139 functional, frozen-render,
  cadence, PREVIEW, recovery, click, Celeste, and clock battery. C008's
  source-contract and R.84 proofs are historical acceptance evidence, not a
  second maintained implementation.
- Physical gate: preserve 6,302 LUT4s, 1,291 carries, 1,450 FFs, 498
  unpackable FFs, 14 EBRs, floor 6,800, 7,018 routed LCs, and passing
  142.63/31.17 MHz seed-1 timing.
- Dirty-tree constraints: stage only the active clarity slice. Do not start a
  new area hypothesis, R.84/B2 work, Tang diagnostics, or testbench churn.

## Current State

- Active hypothesis: none; C011 closes the focused testbench pass.
- Next hypothesis ID: none.
- Current baseline artifacts: `build/integration-h139-r84/synth-1.{json,asc}`
  and `build/experiments/c008/`.
- Latest decision: C011 accepted. The maintained benches now describe DUT
  roles, comparison paths, holds, and context selection in current interface
  terms without changing stimulus, checks, timing, or pass criteria.
- Best accepted result: H139 at JSON SHA-256
  `4f7c4af1678ebbaf203cc63088855ec16bc44ebaa92e0f529e5d7961f0e554ff`
  and ASC SHA-256
  `cca305c10325058d5f5ea61dd225516a5de9ebcaaf516ee4b0774e91a97caabf`.
- Last updated: 2026-08-03.

## Completion Checklist

### Current-design documentation

- [x] Every production module header says what the module owns and how data or
  control moves through it.
- [x] Schedule, memory arbitration, multiplier, executor, and wrapper comments
  explain current timing and hold contracts at their points of use.
- [x] Production comments contain no experiment IDs, revision chronology,
  historical provenance, or claims framed around superseded implementations.
- [x] Comments distinguish architectural invariants from verification facts.

### Naming and ergonomics

- [x] Audit top-level composition and shared services for consistent request,
  busy, hold, replay, address, and result naming.
- [x] Audit `psg_seq.sv` working-record and FSM names; explain or replace opaque
  abbreviations without creating synthesized aliases.
- [x] Audit `psg_walk.sv` phase, capture, oscillator, noise, filter, mix, and
  fold names; give every retained short name a nearby domain explanation.
- [x] Replace repeated magic phase/action values with named constants only when
  the generated physical result remains exact.

### Organisation and modular boundaries

- [x] Document the composition tree and ownership of audio RAM, state RAM,
  control ROM, waveform evaluation, arithmetic services, sequencer, and walk.
- [x] Keep wrappers only where they express a live interface or hold boundary;
  state that boundary directly.
- [x] Group declarations and logic by transaction or pipeline stage so readers
  can follow each operation without reconstructing revision history.
- [x] Audit include guards, textual include order, and public interfaces for a
  single obvious source of shared constants and layouts.

### DRYness and modularity

- [x] Inventory duplicated arithmetic, address, action, and handshake logic.
- [x] Consolidate duplication only when the abstraction makes ownership clearer
  and the whole-PSG physical result stays at H139 exactly.
- [x] Avoid helper layers that duplicate state, widen muxes, hide cycle timing,
  or make source simpler while making the mapped PSG larger.

### Completion proof

- [x] Comment-only slices reproduce byte-identical canonical JSON and ASC.
- [x] Every structural slice passes full/PREVIEW lint and its focused tests.
- [x] C008's final source rebinding passed the H139/R.84 structural and value
  proofs; that historical evidence remains in Git after the proof stack retires.
- [x] Final full battery passes all functional/render/cadence/PREVIEW/recovery/
  click/Celeste/clock gates and two byte-identical canonical physical builds.
- [x] C008 audited all 5,265 then-maintained lines. C009 narrows the live
  production boundary to the actual 4,350-line, 12-source PSG tree.
- [x] C009 passes live regressions and preserves the accepted physical image.
- [x] C010's second reader pass preserves synthesized-token, behavioral,
  render, cadence, and physical identity.
- [x] C011's focused benches retain their exact behavioral checks while using
  current core, adapter, service, context, and multi-pump vocabulary.

## Source Audit Matrix

| Source | Current contract | Naming/organisation/DRY | Evidence |
| -- | -- | -- | -- |
| `psg.sv` | C001/C010 accepted | C004/C010 accepted | token-exact + full battery |
| `psg_common.svh` | C001/C010 accepted | C003/C010 accepted | token-exact + full battery |
| `psg_aram.sv` | C001/C010 accepted | C003/C010 accepted | token-exact + full battery |
| `psg_timing.sv` | C001/C010 accepted | C003/C010 accepted | token-exact + full battery |
| `psg_state_mem.sv` | C001/C010 accepted | C003/C010 accepted | token-exact + full battery |
| `psg_mulsvc.sv` | C001/C010 accepted | C003/C010 accepted | token-exact + full battery |
| `psg_mulmp.sv` | C001/C010 accepted | C003/C010 accepted | token-exact + full battery |
| `psg_dqsvc.sv` | C001/C010 accepted | C003/C010 accepted | token-exact + full battery |
| `psg_divsvc.sv` | C001/C010 accepted | C003/C010 accepted | token-exact + full battery |
| `psg_wave.sv` | C001/C010 accepted | C003/C010 accepted | token-exact + full battery |
| `psg_walk.sv` | C001/C010 accepted | C002/C010 accepted | token-exact + full battery |
| `psg_seq.sv` | C001/C010 accepted | C002/C010 accepted | token-exact + full battery |

The maintained production set is 12 files and 4,350 lines. The former
`psg_exec*` research implementation was disconnected from `psg.sv`; its C003,
C007, and C008 evidence remains in repository history rather than imposing a
second architecture on the live source tree.

## Next Experiment Gate

- Next permitted experiment: none; C011 is accepted.
- Reopen source refactoring only if a maintained PSG source or H139 acceptance
  gate changes.
- Blocked repeat families: no source-level refactor is accepted from LOC,
  readability, isolated synthesis, or generated-code size alone.

## Recent Hypothesis Index

| ID | Decision | Resume effect |
| -- | -- | -- |
| C001 | accepted | Current-contract comments; exact H139 JSON/ASC and timing. |
| C002 | accepted | Sequencer/walk source maps and short-name guides; exact JSON/ASC. |
| C003 | accepted | Smaller-module maps and duplication audit; exact JSON/ASC. |
| C004 | accepted | Top-level declarations precede consumers; exact H139 ASC. |
| C005 | rejected | Exact function adds 41 LUT4s and 40 floor cells; reverted. |
| C006 | rejected | Exact macro adds 31 LUT4s and 33 floor cells; reverted. |
| C007 | accepted | Named record-load actions; exact movement and H139 ASC. |
| C008 | accepted | v7 binds all 16 sources; normalized proofs and H139 envelope exact. |
| C009 | accepted | Removed the disconnected executor research/proof stack; live PSG remains H139. |
| C010 | accepted | Second reader pass; synthesized tokens and full H139 behavior exact. |
| C011 | accepted | Current testbench roles; focused arithmetic, memory, waveform, and clock gates pass. |

## Hypothesis C001

- **ID:** C001.
- **Hypothesis:** replacing revision/provenance commentary with concise module,
  ownership, timing, and interface contracts will make the current PSG easier
  to understand without changing one compiled RTL token.
- **Scope:** comments only in the sixteen production PSG source/header files;
  no declarations, expressions, interfaces, generated files, or testbenches.
- **Baseline:** accepted H139 physical metrics and artifact hashes in Current
  State; branch starts clean at integration commit `fc74906`.
- **Change:** remove revision IDs and before/after narratives; describe what
  each current boundary does and how its handshakes, phases, or arithmetic work.
- **Result:** comment diff audit and provenance search pass. Full multi-pump and
  PREVIEW lint pass with the established 52/49 warnings. Canonical Homebrew
  Yosys reproduces 6,302 LUT4s, 1,291 carries, 1,450 FFs, and 14 EBRs; seed-1
  routing reproduces 7,018 LCs at 142.63/31.17 MHz. Candidate JSON and ASC are
  byte-identical to H139 at the hashes in Current State. The shell-default OSS
  CAD Suite produces different metadata and is not a valid byte comparator.
- **Decision:** accepted.
- **Repeat only if:** a later audit finds remaining provenance or a comment that
  still requires historical context to understand current behavior.

## Hypothesis C002

- **ID:** C002.
- **Hypothesis:** readers can follow the two large serialized machines if their
  declarations and logic are grouped by record ownership, transaction stage,
  and schedule phase, and if every retained short name has a current domain
  explanation. The first pass can improve orientation without changing RTL.
- **Scope:** `rtl/psg_seq.sv` and `rtl/psg_walk.sv`; build a complete source
  map, improve section/stage comments in existing line positions, and propose
  any rename or modular extraction separately before changing tokens.
- **Baseline:** accepted C001, byte-identical to H139 JSON/ASC with 52/49 lint
  warnings and the full H139 physical metrics.
- **Change:** line-stable source maps and short-name guides recorded below.
- **Result:** full/PREVIEW lint and canonical physical artifacts remain exact.
- **Decision:** accepted.
- **Repeat only if:** the source map or later reader audit still requires
  reconstructing ownership or schedule order from terse local names alone.

### C002 Result

- **Change:** line-stable section maps divide `psg_seq.sv` into persistent
  state, working record, tick program, memory schedules, arithmetic,
  publication, controller, and adapters; `psg_walk.sv` now exposes visit state,
  waveform, wavetable, noise, transition, mix, multiplier, PREVIEW, fold,
  reverb, and controller stages. Local guides define the retained short names.
- **Result:** the diff changes comments only and preserves every source-token
  line. Full/PREVIEW lint passes at 52/49 warnings. Canonical JSON and ASC are
  byte-identical to H139 at the hashes in Current State, including 7,018 routed
  LCs and 142.63/31.17 MHz timing.
- **Decision:** accepted.

## Hypothesis C003

- **ID:** C003.
- **Hypothesis:** consistent interface-group, ownership, and transaction-stage
  maps across the smaller modules will make composition understandable and
  reveal which apparent repetitions are genuine abstractions versus deliberate
  timing-local logic.
- **Scope:** `rtl/psg.sv`, `rtl/psg_common.svh`, all service/memory/wave modules,
  and the four `psg_exec*.sv` modules. Comments and a duplication inventory
  first; any identifier or logic change becomes a later hypothesis.
- **Baseline:** accepted C002, byte-identical to H139 JSON/ASC.
- **Change:** add line-stable section and interface maps to `psg.sv`,
  `psg_wave.sv`, and the executor modules; tighten the multi-pump transaction
  contract; classify the repeated mechanisms before attempting an abstraction.
- **Result:** full/PREVIEW lint passes at the established 52/49 warnings.
  Canonical JSON and ASC are byte-identical to H139 at the hashes in Current
  State, with 7,018 routed LCs and 142.63/31.17 MHz timing.
- **Decision:** accepted.
- **Repeat only if:** a later reader audit cannot identify a module's state
  owner, handshake, or relationship to its adapter/core from the source.

### C003 Duplication and boundary inventory

- `psg_mulsvc`, `psg_mulmp`, and, structurally, `psg_dqsvc` each contain a
  radix recurrence. Their operand shapes, clocks, completion rules, and held
  state differ, so a shared helper would hide rather than clarify ownership.
- Audio RAM, DQ, multi-pump multiplication, waveform evaluation, and executor
  waveform logic use core/adapter pairs to express real hold, replay, context,
  or clock-domain boundaries. The adapters are not accidental duplication.
- The current/preceding reverb-comb arithmetic in `psg_walk` is the strongest
  later DRY candidate because both arms apply the same signed comb operation.
- `psg_execmove` deliberately spells fixed action projections as constants.
  Replacing them with a general indexed mux would weaken the physical and
  timing contract even if it shortened the source.

## Hypothesis C004

- **ID:** C004.
- **Hypothesis:** moving top-level interface declarations before their first
  consumers will make `psg.sv` readable from top to bottom without changing
  any identifier, width, expression, instance connection, or behavior.
- **Scope:** declaration order and adjacent ownership comments in `rtl/psg.sv`.
- **Baseline:** accepted C003, byte-identical to H139 JSON/ASC.
- **Change:** move the existing state-memory, tick-sequencer, walk-service,
  waveform-context, and streaming-result declarations into ownership groups
  before the instances or arbitration blocks that first consume them. No
  identifier, width, expression, instance connection, or behavior changes.
- **Result:** full/PREVIEW lint remains 52/49. Canonical synthesis preserves
  6,302 LUT4s, 1,291 carries, 1,450 FFs, 498 unpackable FFs, and 14 EBRs; JSON
  differs only in moved source locations. Seed-1 routing is byte-identical to
  H139 at the accepted ASC hash, with 7,018 LCs and 142.63/31.17 MHz timing.
  Hardware forms, `make test-psg`, `make test-clocks`, all 59 frozen renders,
  six cadence profiles, both PREVIEW rates, synthetic/Celeste recovery, both
  click renders, and the byte-identical Celeste smoke all pass.
- **Decision:** accepted.
- **Repeat only if:** a later top-level edit again leaves an interface declared
  below the instance or arbitration block that first consumes it.

## Hypothesis C005

- **ID:** C005.
- **Hypothesis:** a module-local `reverb_comb` helper can state the signed comb
  operation once for current and preceding arms, remove four duplicated
  intermediate expressions, and inline to the exact H139 physical result.
- **Scope:** the current/preceding comb expressions in `rtl/psg_walk.sv` plus a
  source-derived exhaustive equivalence check; no state, schedule, or interface
  changes.
- **Baseline:** accepted C004 with exact H139 area and routed ASC.
- **Change:** replace the two explicit comb expressions and four intermediate
  wires with one signed `reverb_comb` function called for each arm.
- **Result:** arbitrary-input SAT proves exact output equality. Full/PREVIEW
  lint reaches only established warning classes, with the removed intermediate
  nets reducing counts from 52/49 to 51/48. Canonical whole-PSG synthesis
  regresses 6,302 -> 6,343 LUT4s and floor 6,800 -> 6,840 while keeping 1,291
  carries, 1,450 FFs, and 14 EBRs; one more FF packs only because the larger
  logic cover changes placement. Production is restored exactly to C004;
  routing and the fidelity battery are skipped after the hard area failure.
- **Decision:** rejected and reverted.
- **Repeat only if:** a helper spelling that fails the physical gate is retried
  only after its signed-width or inlining behavior is materially different.

## Hypothesis C006

- **ID:** C006.
- **Hypothesis:** a temporary macro can keep one source spelling for the comb
  operation while expanding into C004's exact named wires, avoiding the
  function inlining/mapping regression and keeping timing visible at the call
  sites.
- **Changed condition versus C005:** preprocessing emits the original
  accumulator, round-toward-zero, and result declarations with their original
  names instead of introducing function-local cells.
- **Scope:** the same two comb expressions in `rtl/psg_walk.sv`; define the
  macro immediately before use and undefine it immediately afterwards.
- **Baseline:** restored accepted C004.
- **Change:** define one temporary comb macro, invoke it for both arms with the
  original intermediate names, and undefine it immediately after use.
- **Result:** preprocessing emits the intended named accumulator,
  round-toward-zero, and result declarations, and full/PREVIEW lint remains at
  52/49. Canonical whole-PSG synthesis nevertheless regresses 6,302 -> 6,333
  LUT4s, 1,291 -> 1,295 carries, 498 -> 500 unpackable FFs, and floor 6,800 ->
  6,833. Production is restored exactly to C004; route and fidelity are
  skipped after the hard area failure. With both a function and a literal
  preprocessor expansion rejected, the reverb-comb helper family is closed.
- **Decision:** rejected and reverted.
- **Repeat only if:** the macro's preprocessed expansion or physical result is
  not identical to the explicit C004 structure.

## Hypothesis C007

- **ID:** C007.
- **Hypothesis:** naming the eight record-load action codes will remove the
  last unexplained raw action values from `psg_execmove` without changing its
  deliberately fixed projections or the synthesized PSG.
- **Scope:** the action dictionary and record-load case labels in
  `rtl/psg_execmove.sv`; no decoder structure, address, or output changes.
- **Baseline:** restored accepted C004.
- **Change:** define `V_LD0` through `V_LD7` beside the movement action
  dictionary, use `V_LD0` for the fixed initialization edge, and replace raw
  `7'h01` through `7'h07` case labels with the corresponding names.
- **Result:** the movement bench passes dynamic loads/stores, fixed actions,
  banks, and emitted effects. The generated action/address contract passes all
  27 pinned actions and both parameter banks. Isolated executor lint is clean;
  full/PREVIEW lint remains 52/49. Canonical target JSON and seed-1 ASC are
  byte-identical to C004/H139, retaining 6,302 LUT4s, 7,018 routed LCs, and
  142.63/31.17 MHz timing.
- **Decision:** accepted.
- **Repeat only if:** a later generated program adds a record-load action not
  represented in the movement dictionary.

## Hypothesis C008

- **ID:** C008.
- **Hypothesis:** the final clarity-only source revision can replace H139 as
  the live source certificate while retaining H139's normalized program,
  structural transactions, value lineage, behavior, and physical image.
- **Scope:** source-contract metadata and any source-aware proof patterns needed
  to recognize the accepted C001--C004/C007 spellings; no production behavior
  change.
- **Baseline:** accepted C007 and H139/R.84 source contract v6.
- **Change:** retain every v6 H095--H139/R.84 lineage anchor, then add a v7
  child boundary from integrated H139 `fc74906` to clarity source revision
  `1251f49`. The child hashes all sixteen maintained PSG sources, names the
  exact eleven-source change set, and independently validates revision, parent,
  worktree, changed-source, schema, count, and model-live-source relations.
- **Result:** independent A/B generation produces byte-identical v7 source
  contracts at SHA-256 `8ce444ea240f7a6c4836cb00828bde5d98079a25c8f965d2346780158206abef`
  and H139-identical candidate, manifest, control, requirements, controller,
  and event artifacts. Fresh live-RTL traces are byte-identical to I004/H139.
  Both binding audits pass 152,893 structural rows and convict all 22 source
  mutations across sixteen files; both value audits pass 192,896 pairs and
  43,459 service transactions. The default model, all hardware forms,
  full/PREVIEW lint at 52/49 warnings, `make test-psg`, `make test-clocks`, and
  59/59 frozen renders pass directly on the final source. C004 supplies the
  already accepted six cadence profiles, both PREVIEW rates, synthetic/Celeste
  recovery, zero-click hardware/PREVIEW renders, and byte-identical Celeste
  smoke; C007's focused movement/action proof and canonical build bind the only
  later production-token change. C004 and C007 canonical JSON are mutually
  byte-identical at `dbe15b79...`; both routed images are byte-identical to H139
  at `cca305c1...`, retaining 6,302 LUT4s, 1,291 carries, 1,450 FFs, 498
  unpackable FFs, 14 EBRs, floor 6,800, 7,018 routed LCs, and 142.63/31.17 MHz.
  The final source audit covers 5,265 lines with no experiment ID, provenance,
  revision narrative, or TODO/FIXME residue.
- **Decision:** accepted.
- **Repeat only if:** the accepted production/source-proof revision changes.

## Hypothesis C009

- **ID:** C009.
- **Hypothesis:** deleting the disconnected R.84 executor model, RTL,
  generated program, dedicated benches/targets, and proof-only budget-trace
  paths will make the repository's maintained PSG boundary obvious without
  changing production RTL, simulation behavior, or the H139 physical image.
- **Scope:** `tools/psg_exec_*`, `rtl/psg_exec*`, the three executor synthesis
  targets, and the `binding_only`/binding/value trace support in
  `rtl/psg_budget_tb.sv`; retain `tools/gen_psg_ctrl.py` and the complete live
  `psg.sv` source tree.
- **Baseline:** accepted C008 production RTL and H139 artifacts; the removed
  stack has no production, Makefile, script, or CI consumer.
- **Change:** remove 16,909 lines of disconnected executor research and
  proof-only infrastructure. Keep the historical R.84/OpenSpec record in Git.
- **Result:** no live references remain outside the intentionally preserved
  OpenSpec/ledger history. Full and PREVIEW production lint pass with only the
  three established width warnings. Both full and PREVIEW budget-testbench
  forms compile after trace removal. `make psg-viz` derives 62 hardware phases,
  24 preview phases, 63 FSM states, and 90 transitions; all 13 visualizer tests
  pass. `make test-psg` passes PICO-8 fidelity, exhaustive arithmetic/DQ gates,
  93 audio-analysis tests, the visualizer tests, and the complete structural
  PSG simulation at the exact 524/850 sample and 4,008/5,103 tick budgets.
  `make test-clocks` passes `/4`, `/5`, and `/6`; the explicit 18.75 MHz frozen
  render sweep is byte-identical 59/59. All twelve production synthesis inputs
  are byte-unchanged, and the retained H139 JSON/ASC hashes remain
  `4f7c4af1...` / `cca305c1...`, so the 6,302-LUT4, 7,018-routed-LC physical
  image and 142.63/31.17 MHz timing are unchanged by construction.
- **Decision:** accepted.
- **Repeat only if:** a live consumer of the removed stack is found or the
  production PSG's behavior or physical artifact differs after removal.

## Hypothesis C010

- **ID:** C010.
- **Hypothesis:** a second reader-oriented pass can expose remaining ownership,
  timing, state-transition, and data-shape assumptions using comments and
  declaration/section organisation while preserving every synthesized token.
- **Scope:** all twelve production sources in the Source Audit Matrix. Do not
  change synthesized interfaces, identifiers, declarations, expressions,
  generate shape, include order, or the closed C005/C006 helper family. Remove
  the unused `wt_p1`/`wt_q1` aliases under `ifndef SYNTHESIS`; their only
  consumer belonged to C009's retired value-trace path.
- **Baseline:** accepted C009 and H139 physical artifacts at the hashes in
  Current State.
- **Change:** add a system-level data-flow map; group large module ports by
  owner; define sequencer states, walk prefixes, waveform context selectors,
  packed-record suffixes, service request/result boundaries, and current
  freeze/hold behavior; reformat the top-level and timing interfaces; remove
  the final unused `wt_p1`/`wt_q1` simulation aliases. Production comments no
  longer refer to the retired executor architecture.
- **Result:** the canonicalized `SYNTHESIS` preprocessor stream is byte-identical
  before and after at SHA-256 `af8078fa40345cb0b2941c6a46bf969cb4418d92128c228e7b02f642169ce7c0`.
  Full and PREVIEW lint pass with only the three established width warnings.
  `make psg-viz` still derives 62 hardware phases, 24 preview phases, 63 FSM
  states, and 90 transitions. `make test-psg` passes PICO-8 fidelity,
  exhaustive arithmetic/DQ checks, 93 audio-analysis tests, 13 visualizer
  tests, and the complete structural simulation at 524/850 sample clocks and
  4,008/5,103 tick clocks. `make test-clocks` passes all three ratios and the
  explicit 18.75 MHz render sweep is byte-identical 59/59. Synthesized tokens
  are exact, so the retained H139 JSON/ASC, area, routing, and timing remain
  unchanged by construction.
- **Decision:** accepted.
- **Repeat only if:** the post-pass source still requires a reader to infer a
  live ownership, timing, state-transition, or data-shape contract from logic.

## Hypothesis C011

- **ID:** C011.
- **Hypothesis:** focused PSG benches will be easier to maintain if their DUT
  roles and comparison paths use current interface vocabulary instead of
  "legacy", "new", or "historical" provenance.
- **Scope:** the eight maintained `rtl/psg*_tb.sv` benches. Rename only local
  bench signals/instances/messages and improve purpose/ownership comments;
  preserve DUT ports, stimulus, checks, timing, and pass criteria.
- **Baseline:** accepted C010 production sources and the current focused bench
  results.
- **Change:** added concise purpose headers to the audio-RAM, DQ, multiplier,
  and waveform benches; renamed bench-local `legacy` instances and outputs by
  their core/adapter roles; replaced provenance-shaped comments and failures
  with current production-adapter, recurrence, context, and multi-pump terms.
  `psg_tb.sv` and `psg_budget_tb.sv` already had complete current-purpose
  headers and required no edits. Production RTL is untouched.
- **Result:** `git diff --check` and the focused provenance-vocabulary scan
  pass. Audio-RAM hold/replay passes, and top-level readback verifies all 4,608
  bytes. DQ passes 57,344 exhaustive, chained, and held transactions. The
  multiplier passes 6,020 transactions; relative clock offsets 0 through 9
  all pass. Waveform evaluation passes 2,097,152 exhaustive contexts plus
  preceding-context selection and whole-pipeline hold checks.
- **Decision:** accepted.
- **Repeat only if:** a maintained PSG bench still describes a current
  interface relative to a superseded implementation instead of stating its
  present contract.

## Saved Artifacts

| Artifact | Command | Notes |
| -- | -- | -- |
| `build/integration-h139-r84/synth-1.json` | retained I004 canonical build | Accepted H139 JSON baseline. |
| `build/integration-h139-r84/synth-1.asc` | retained I004 seed-1 route | Accepted H139 ASC baseline. |
| `build/experiments/c001/candidate.json` | `/opt/homebrew/bin/yosys` canonical synthesis | Byte-identical to H139. |
| `build/experiments/c001/candidate.asc` | `/opt/homebrew/bin/nextpnr-ice40` canonical seed-1 route | Byte-identical to H139. |
| `build/experiments/c001/c002.json` | canonical C002 synthesis | Byte-identical to H139. |
| `build/experiments/c001/c002.asc` | canonical C002 seed-1 route | Byte-identical to H139. |
| `build/experiments/c001/c003.json` | canonical C003 synthesis | Byte-identical to H139. |
| `build/experiments/c001/c003.asc` | canonical C003 seed-1 route | Byte-identical to H139. |
| `build/experiments/c001/c004.json` | canonical C004 synthesis | Exact H139 area; moved source metadata. |
| `build/experiments/c001/c004.asc` | canonical C004 seed-1 route | Byte-identical to H139. |
| `build/experiments/c004/` | C004 live-source acceptance logs | Full H139 functional/fidelity battery passes. |
| `build/experiments/c007/` | C007 executor/physical evidence | Named actions pass; JSON/ASC exact. |
| `build/experiments/c008/` | independent v7 model, source, structural and value proof | 16 sources, 152,893 rows, 192,896 pairs; all exact. |
| `build/obj_psg_budget_c009_{full,preview}/` | fresh Verilator builds | Both remaining budget-testbench forms compile after proof-trace removal. |
| `build/experiments/c011/` | focused Icarus/Verilator bench builds | Audio RAM, DQ, multiplier, ten clock phases, and 2,097,152 waveform contexts pass. |

## Archive

- Full historical rows: none yet.
- Resume-audit history: branch and baseline recorded in this ledger.
- Archived DNR table: the closed area loop remains in
  `openspec/changes/reduce-psg-ice40-area/rtl-area-continuation.md`.

## Handoff

- Next allowed experiment: none; the clarity and executor-cleanup work is complete.
- Blocked/rejected mechanisms: all new area work and any clarity abstraction
  that changes H139 resources or relies on local/source-only evidence.
- Verification still missing: none for C001--C011.
- Files to avoid staging: non-PSG RTL, Tang files, unrelated OpenSpec changes,
  build products, and existing area-loop evidence.
