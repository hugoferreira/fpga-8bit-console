# PSG Source Clarity Ledger

This ledger is the mandatory resume surface for the PSG clarity refactor. The
accepted H139 implementation is the behavioral and physical contract; source
clarity is useful only when that contract remains intact.

## Context

- Topic: make the production PSG RTL understandable, ergonomic, organised,
  DRY, modular, and documented in terms of the current design.
- Owner scope: `rtl/psg.sv`, `rtl/psg_common.svh`, the ten service/datapath
  modules textually included by `psg.sv`, and the four shared-executor modules.
  Testbenches and proof tooling change only when a production boundary
  genuinely requires them.
- Correctness gate: preserve the complete H139 functional, frozen-render,
  cadence, PREVIEW, recovery, click, Celeste, clock, source-contract, and R.84
  proof battery.
- Physical gate: preserve 6,302 LUT4s, 1,291 carries, 1,450 FFs, 498
  unpackable FFs, 14 EBRs, floor 6,800, 7,018 routed LCs, and passing
  142.63/31.17 MHz seed-1 timing.
- Dirty-tree constraints: stage only the active clarity slice. Do not start a
  new area hypothesis, R.84/B2 work, Tang diagnostics, or testbench churn.

## Current State

- Active hypothesis: C008, rebind the accepted clarity source set to the H139/
  R.84 structural and value proofs and close the final audit.
- Next hypothesis ID: none while C008 is active.
- Current baseline artifacts: `build/integration-h139-r84/synth-1.{json,asc}`.
- Latest decision: C007 accepted; record-load actions are named and the H139
  JSON and routed ASC remain byte-identical.
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
- [ ] Every structural slice passes full/PREVIEW lint and its focused tests.
- [ ] Final source rebinding passes the H139/R.84 structural and value proofs.
- [ ] Final full battery passes all functional/render/cadence/PREVIEW/recovery/
  click/Celeste/clock gates and two byte-identical canonical physical builds.
- [ ] Final audit covers all 5,250 production-source lines and closes every
  checklist item with evidence.

## Source Audit Matrix

| Source | Current contract | Naming/organisation/DRY | Evidence |
| -- | -- | -- | -- |
| `psg.sv` | C001 accepted | C004 accepted | exact area/ASC + full battery |
| `psg_common.svh` | C001 accepted | C003 audited | exact JSON/ASC |
| `psg_aram.sv` | C001 accepted | C003 audited | exact JSON/ASC |
| `psg_timing.sv` | C001 accepted | C003 audited | exact JSON/ASC |
| `psg_state_mem.sv` | C001 accepted | C003 audited | exact JSON/ASC |
| `psg_mulsvc.sv` | C001 accepted | C003 audited | exact JSON/ASC |
| `psg_mulmp.sv` | C001 accepted | C003 accepted | exact JSON/ASC |
| `psg_dqsvc.sv` | C001 accepted | C003 audited | exact JSON/ASC |
| `psg_divsvc.sv` | C001 accepted | C003 audited | exact JSON/ASC |
| `psg_wave.sv` | C001 accepted | C003 accepted | exact JSON/ASC |
| `psg_walk.sv` | C001 accepted | C002 accepted | exact JSON/ASC |
| `psg_seq.sv` | C001 accepted | C002 accepted | exact JSON/ASC |
| `psg_execctl.sv` | C001 accepted | C003 accepted | exact JSON/ASC |
| `psg_execdp.sv` | C001 accepted | C003 accepted | exact JSON/ASC |
| `psg_execmove.sv` | C001 accepted | C007 accepted | movement/contract + exact ASC |
| `psg_execwave.sv` | C001 accepted | C003 accepted | exact JSON/ASC |

## Next Experiment Gate

- Next permitted experiment: C008, bind the final source revision and hashes to
  the H139/R.84 source certificate, structural traces, and value lineage.
- Proof required before editing: commit C007 so the certificate has one exact
  revision; inventory every changed source against H139 and C004.
- Required verification: independent A/B source generation, structural/value
  audits, final source audit, and the complete H139 acceptance envelope.
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
| C008 | active | Rebind final source proofs and close the audit. |

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
- **Change:** pending final revision/hash rebinding and source audit.
- **Result:** pending.
- **Decision:** active.
- **Repeat only if:** the accepted production/source-proof revision changes.

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

## Archive

- Full historical rows: none yet.
- Resume-audit history: branch and baseline recorded in this ledger.
- Archived DNR table: the closed area loop remains in
  `openspec/changes/reduce-psg-ice40-area/rtl-area-continuation.md`.

## Handoff

- Next allowed experiment: C008 only.
- Blocked/rejected mechanisms: all new area work and any clarity abstraction
  that changes H139 resources or relies on local/source-only evidence.
- Verification still missing: final C008 source rebinding and completion audit.
- Files to avoid staging: non-PSG RTL, Tang files, unrelated OpenSpec changes,
  build products, and existing area-loop evidence.
