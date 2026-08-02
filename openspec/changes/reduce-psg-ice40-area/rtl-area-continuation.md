# PSG RTL area continuation ledger

This is the resume surface for small, generic-RTL area and source-simplicity
experiments running independently of the R.84 stored-state executor work in
`r78-continuation.md`. Do not edit or integrate the R.84 executor from this
loop. Detailed earlier area history remains in `design.md`, `tasks.md`, and
`r78-continuation.md`.

## Context

- Topic: exact generic PSG RTL simplification and iCE40 HX8K area reduction.
- Owner scope: existing production RTL outside the R.84 executor/controller
  replacement; current H001 is limited to `rtl/psg_wave.sv`.
- Correctness gate: proof of exact arithmetic, focused model/unit tests,
  `make test-psg`, 59-render PICO-8 regression, and no weakened tolerance.
- Physical gate: canonical `PATH=/opt/homebrew/bin:$PATH make synth-psg` with
  seed-1 router2 placement, routed timing, mapped resources, and 14 or fewer
  EBRs. An accepted area change must improve a deterministic mapped resource
  and not regress placed LCs.
- Dirty-tree constraints: branch `codex/psg-rtl-area-continuation`; stage only
  the active RTL, proof, generated artifact, and this ledger. Companion R.84
  files and unrelated user work are excluded.

## Current State

- Active hypothesis: none; H001 accepted.
- Next hypothesis ID: H002.
- Current evidence: `build/experiments/h001/{baseline,candidate}.synth.log`
  and matching `.pnr.log` files.
- Latest decision: H001 accepted. The mapped carry reduction is deterministic;
  the nine-LC placed improvement is positive but below the known roughly
  60-LC placement-sensitivity band and is not claimed as a robust area delta.
- Best accepted result: 6,602 LUT4s, 1,577 carries, 1,478 flops, 14 EBRs;
  seed-1 7,495/7,680 LCs; 150.53 MHz fast and 30.71 MHz PSG.
- Last updated: 2026-08-02.

## Next Experiment Gate

- Next permitted experiment: perform the H002 resume audit and record one new,
  bounded, source-exact generic-RTL hypothesis before editing RTL.
- Required verification for any accepted H002: focused algebraic or exhaustive
  proof, waveform/form tests, full structural PSG, 59-render exact regression,
  mapped resources, seed-1 placed LCs, both routed clocks, strict OpenSpec
  validation, and `git diff --check`.
- Blocked repeat families: R.40--R.42 lifetime aliases; R.63/R.64 multiplier
  adder sharing; R.67 parallel reciprocal port; R.68/R.69 partial schedule
  encodings; R.76--R.78 detune-result lifetimes; R.79 held CDC payload;
  R.80 reciprocal coefficient factoring; R.82 detune recomputation; R.83
  register-fed waveform services; all R.84 executor/controller work.

## Recent Hypothesis Index

| ID | Decision | Resume effect |
| -- | -- | -- |
| H001 | accepted | Keep the exact narrow tilted-saw ceiling form; treat the mapped carry reduction as the durable physical result. |

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

## Active DNR Index

- Selected arithmetic and service families: R.63, R.64, R.80, R.83.
- Lifetime and CDC payload families: R.40--R.42, R.76--R.79, R.82.
- Partial schedule/control encodings: R.68, R.69 and R.84 partial integration.
- Reciprocal memory topology: R.67.

## Saved Artifacts

| Artifact | Command | Notes |
| -- | -- | -- |
| `build/experiments/h001/baseline.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` at `86d4fab` | H001 baseline mapping. |
| `build/experiments/h001/baseline.pnr.log` | same | H001 baseline seed-1 placement and timing. |
| `build/experiments/h001/candidate.synth.log` | `PATH=/opt/homebrew/bin:$PATH make synth-psg` with H001 | H001 accepted mapping. |
| `build/experiments/h001/candidate.pnr.log` | same | H001 accepted seed-1 placement and timing. |
| `build/experiments/h001/clicks/{hardware,preview}.wav` | exact SFX-10 renders at 22,050 Hz | `click-v1` zero-click evidence. |
| `build/experiments/h001/celeste-smoke.ppm` | five-frame headless Celeste run | Boot and active/nonconstant audio smoke. |

## Handoff

- Next allowed experiment: H002 only after its hypothesis row and baseline are
  recorded; it must be a new generic-RTL mechanism outside R.84 ownership.
- Blocked/rejected mechanisms: the Active DNR index above and all companion-
  owned R.84 work.
- Verification still missing: none for H001.
- Files to avoid staging: all executor/controller proof files, companion
  continuation edits, and unrelated repository changes.
