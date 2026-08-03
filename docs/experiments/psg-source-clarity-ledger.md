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

- Active hypothesis: C002, make the sequencer and sample-walk organisation
  readable from current operation and ownership rather than terse local names.
- Next hypothesis ID: C003.
- Current baseline artifacts: `build/integration-h139-r84/synth-1.{json,asc}`.
- Latest decision: C001 accepted; production comments now describe current
  contracts and the canonical netlist/route remain byte-identical to H139.
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
- [ ] Comments distinguish architectural invariants from verification facts.

### Naming and ergonomics

- [ ] Audit top-level composition and shared services for consistent request,
  busy, hold, replay, address, and result naming.
- [ ] Audit `psg_seq.sv` working-record and FSM names; explain or replace opaque
  abbreviations without creating synthesized aliases.
- [ ] Audit `psg_walk.sv` phase, capture, oscillator, noise, filter, mix, and
  fold names; give every retained short name a nearby domain explanation.
- [ ] Replace repeated magic phase/action values with named constants only when
  the generated physical result remains exact.

### Organisation and modular boundaries

- [ ] Document the composition tree and ownership of audio RAM, state RAM,
  control ROM, waveform evaluation, arithmetic services, sequencer, and walk.
- [ ] Keep wrappers only where they express a live interface or hold boundary;
  state that boundary directly.
- [ ] Group declarations and logic by transaction or pipeline stage so readers
  can follow each operation without reconstructing revision history.
- [ ] Audit include guards, textual include order, and public interfaces for a
  single obvious source of shared constants and layouts.

### DRYness and modularity

- [ ] Inventory duplicated arithmetic, address, action, and handshake logic.
- [ ] Consolidate duplication only when the abstraction makes ownership clearer
  and the whole-PSG physical result stays at H139 exactly.
- [ ] Avoid helper layers that duplicate state, widen muxes, hide cycle timing,
  or make source simpler while making the mapped PSG larger.

### Completion proof

- [ ] Comment-only slices reproduce byte-identical canonical JSON and ASC.
- [ ] Every structural slice passes full/PREVIEW lint and its focused tests.
- [ ] Final source rebinding passes the H139/R.84 structural and value proofs.
- [ ] Final full battery passes all functional/render/cadence/PREVIEW/recovery/
  click/Celeste/clock gates and two byte-identical canonical physical builds.
- [ ] Final audit covers all 5,250 production-source lines and closes every
  checklist item with evidence.

## Source Audit Matrix

| Source | Current contract | Naming/organisation/DRY | Evidence |
| -- | -- | -- | -- |
| `psg.sv` | C001 accepted | pending | exact JSON/ASC |
| `psg_common.svh` | C001 accepted | pending | exact JSON/ASC |
| `psg_aram.sv` | C001 accepted | pending | exact JSON/ASC |
| `psg_timing.sv` | C001 accepted | pending | exact JSON/ASC |
| `psg_state_mem.sv` | C001 accepted | pending | exact JSON/ASC |
| `psg_mulsvc.sv` | C001 accepted | pending | exact JSON/ASC |
| `psg_mulmp.sv` | C001 accepted | pending | exact JSON/ASC |
| `psg_dqsvc.sv` | C001 accepted | pending | exact JSON/ASC |
| `psg_divsvc.sv` | C001 accepted | pending | exact JSON/ASC |
| `psg_wave.sv` | C001 accepted | pending | exact JSON/ASC |
| `psg_walk.sv` | C001 accepted | C002 active | exact JSON/ASC |
| `psg_seq.sv` | C001 accepted | C002 active | exact JSON/ASC |
| `psg_execctl.sv` | C001 accepted | pending | comment/source audit |
| `psg_execdp.sv` | C001 accepted | pending | comment/source audit |
| `psg_execmove.sv` | C001 accepted | pending | comment/source audit |
| `psg_execwave.sv` | C001 accepted | pending | comment/source audit |

## Next Experiment Gate

- Next permitted experiment: C002, audit and improve the `psg_seq.sv` and
  `psg_walk.sv` reader path without changing operation, state, or timing.
- Proof required before editing: inventory each declaration/FSM/schedule group,
  and classify proposed changes as comment-only, rename-only, or structural.
- Required verification: comment-only changes need exact canonical JSON/ASC;
  any RTL-token change needs focused proof plus the complete H139 battery.
- Blocked repeat families: no source-level refactor is accepted from LOC,
  readability, isolated synthesis, or generated-code size alone.

## Recent Hypothesis Index

| ID | Decision | Resume effect |
| -- | -- | -- |
| C001 | accepted | Current-contract comments; exact H139 JSON/ASC and timing. |
| C002 | active | Audit and clarify sequencer/walk organisation and naming. |

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
- **Change:** pending source-map audit.
- **Result:** pending.
- **Decision:** active.
- **Repeat only if:** the source map or later reader audit still requires
  reconstructing ownership or schedule order from terse local names alone.

## Saved Artifacts

| Artifact | Command | Notes |
| -- | -- | -- |
| `build/integration-h139-r84/synth-1.json` | retained I004 canonical build | Accepted H139 JSON baseline. |
| `build/integration-h139-r84/synth-1.asc` | retained I004 seed-1 route | Accepted H139 ASC baseline. |
| `build/experiments/c001/candidate.json` | `/opt/homebrew/bin/yosys` canonical synthesis | Byte-identical to H139. |
| `build/experiments/c001/candidate.asc` | `/opt/homebrew/bin/nextpnr-ice40` canonical seed-1 route | Byte-identical to H139. |

## Archive

- Full historical rows: none yet.
- Resume-audit history: branch and baseline recorded in this ledger.
- Archived DNR table: the closed area loop remains in
  `openspec/changes/reduce-psg-ice40-area/rtl-area-continuation.md`.

## Handoff

- Next allowed experiment: C002 only.
- Blocked/rejected mechanisms: all new area work and any clarity abstraction
  that changes H139 resources or relies on local/source-only evidence.
- Verification still missing: C002 onward and final source rebinding/battery.
- Files to avoid staging: non-PSG RTL, Tang files, unrelated OpenSpec changes,
  build products, and existing area-loop evidence.
