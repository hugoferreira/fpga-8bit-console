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

- Active hypothesis: none; H001--H003, H005, and H007 accepted.
- Next hypothesis ID: H009.
- Current evidence: `build/experiments/h001/` and
  `build/experiments/h002/`, `build/experiments/h003/`, and
  `build/experiments/h005/` and `build/experiments/h007/` synthesis,
  placement, click, recovery, and smoke artifacts.
- Latest decision: H007 accepted. Its 46-LUT4, 13-carry, and two-flop mapped
  reductions are deterministic; the 57-LC placed improvement is positive but
  remains just inside the known roughly 60-LC placement-sensitivity band and
  is not claimed as robust.
- Latest rejected variant: H005's `< 3` page suffix maps smaller but fails the
  routed 112.5-MHz fast-clock constraint at 109.12 MHz. H004 remains the last
  rejected production hypothesis family; H006 is rejected before production
  because its direct step-count bits map larger than the current ternary, and
  H008 is rejected because its shared counter prefix maps identically.
- Best accepted result: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs;
  seed-1 7,392/7,680 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- Last updated: 2026-08-02.

## Next Experiment Gate

- Next permitted experiment: perform the H009 resume audit and record one new,
  bounded, source-exact generic-RTL hypothesis before editing RTL.
- Required verification for any accepted H009: focused algebraic or exhaustive
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
| H002 | accepted | Keep the four-interval Boolean decode for `ceil(3*r/128)`; the deterministic result is 18 fewer LUT4s. |
| H003 | accepted | Keep the exact high-bit prefix test; the deterministic result is 19 fewer LUT4s and two fewer carries. |
| H004 | rejected | Do not narrow the square/pulse threshold comparator: Yosys already removes the aligned low bits. |
| H005 | accepted | Keep the five-bit page subtract and explicit upload-page decode; the durable result is nine fewer carries with no placed regression. |
| H006 | rejected | Keep the existing multiplier step-count ternary: it already maps to one LUT, while direct result-bit logic needs two. |
| H007 | accepted | Keep the CLK_HZ-derived signed width; it deterministically removes 46 LUT4s, 13 carries, and two flops. |
| H008 | rejected | Keep the two direct counter equalities: Yosys already shares their common high-nibble decode. |

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

## Handoff

- Next allowed experiment: H009 only after its hypothesis row and baseline are
  recorded; it must be a new generic-RTL mechanism outside R.84 ownership.
- Blocked/rejected mechanisms: the Active DNR index above and all companion-
  owned R.84 work.
- Verification still missing: none for accepted H001--H003, H005, or H007.
  H004 and H006 were rejected before production RTL; H005's timing-failing
  spelling remains rejected. H008 was rejected before production RTL.
- Files to avoid staging: all executor/controller proof files, companion
  continuation edits, and unrelated repository changes.
