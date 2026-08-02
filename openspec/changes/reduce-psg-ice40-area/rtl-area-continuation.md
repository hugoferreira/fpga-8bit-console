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
- Next hypothesis ID: H014.
- Current evidence: `build/experiments/h001/` and
  `build/experiments/h002/`, `build/experiments/h003/`, and
  `build/experiments/h005/`, `build/experiments/h007/`, and
  `build/experiments/h009/`, `build/experiments/h010/`, and
  `build/experiments/h012/` and `build/experiments/h013/` synthesis,
  placement, click, recovery, and smoke artifacts as applicable.
- Latest decision: H007 accepted. Its 46-LUT4, 13-carry, and two-flop mapped
  reductions are deterministic; the 57-LC placed improvement is positive but
  remains just inside the known roughly 60-LC placement-sensitivity band and
  is not claimed as robust.
- Latest rejected variant: H013 proves the internal multiplier recurrence fits
  29 bits, but both the two-service and target-only forms add 24 LUT4s/three
  carries and 26 placed LCs while removing two flops. H012 proves the true-
  busy OR is invariant-redundant and locally saves one LUT4, but whole-PSG
  mapping adds 48 LUT4s/five carries and seed-1 placement regresses by 50 LCs.
  H011 proves the reflected ramp is a bitwise complement, but both spellings
  map identically in the registered-use cone. H010's phase-qualified pending
  bit is exact and saves four LUT4s/one flop in the isolated timing cone, but
  whole-PSG mapping adds 29 LUT4s/five carries and seed-1 placement regresses
  by 36 LCs. H009's shift token failed similarly; H005's `< 3` suffix remains
  rejected on fast-clock timing; H004, H006, and H008 remain rejected as
  indexed below.
- Best accepted result: 6,522 LUT4s, 1,553 carries, 1,476 flops, 14 EBRs;
  seed-1 7,392/7,680 LCs; 134.70 MHz fast and 30.95 MHz PSG.
- Last updated: 2026-08-02.

## Next Experiment Gate

- Next permitted experiment: perform the H014 resume audit and record one new,
  bounded, source-exact generic-RTL hypothesis outside multiplier widths.
- Required verification for any accepted H014: focused algebraic or exhaustive
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
| H009 | rejected | Keep the countdown form: the exact shift token is smaller alone but adds 36 LUT4s, five carries, and 36 placed LCs in the full PSG. |
| H010 | rejected | Keep the countdown form: the exact pending bit saves one local flop but adds 29 LUT4s, five carries, and 36 placed LCs in the full PSG. |
| H011 | rejected | Keep the subtract spelling: Yosys already maps `16'hffff - wx` exactly as `~wx`, with identical registered-use resources. |
| H012 | rejected | Keep the defensive true-busy OR: removing it is exact in-contract and locally smaller but adds 48 LUT4s, five carries, and 50 placed LCs globally. |
| H013 | rejected | Keep the 34-bit internal service form: the proved 29-bit recurrence removes two flops but adds 24 LUT4s, three carries, and 26 placed LCs. |

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

## Handoff

- Next allowed experiment: H014 only after its hypothesis row and baseline are
  recorded; it must use a new generic-RTL mechanism outside R.84 ownership.
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
- Files to avoid staging: all executor/controller proof files, companion
  continuation edits, and unrelated repository changes.
