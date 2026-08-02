# PSG area continuation ledger

This is the compact resume surface after the long-form design/task ledger in
the main worktree reached R.78.  Detailed prior rows remain in that ledger and
git history; do not repeat them without the recorded changed condition.

## Current accepted checkpoint

- **R.81B / `2cae31b4a425`**: the detune recurrence carries its one-bit
  live/old context in the otherwise constant `p[26]`, removing the 13-bit
  operand hold without a phase-decode cone.
- Seed-1 HX8K router2: 7,421/7,680 LCs, 14/32 EBRs, 128.12 MHz fast and
  29.90 MHz PSG against 112.5/18.75 MHz requirements.
- Yosys: 6,520 LUT4s, 1,592 carries and 1,478 flops.
- Exact gates: 530 walker + 272 sequencer clocks in the 850-clock `/6`
  interval; 59/59 hardware renders byte-identical; P.1/P.2 and `click-v1`
  clean; full/PREVIEW lint, clocks and Celeste smoke pass.

## Do not repeat

- R.40--R.42: cross-family lifetime aliases; three variants lost their flop
  saving to D-input/fanout entanglement.
- R.63/R.64: selecting another operation through the multiplier's existing
  adder; operand muxing cost more than the retired arithmetic.
- R.67: a parallel reciprocal-table port for the tilted-saw tail; +86 LCs.
- R.68/R.69: partial or overlaid schedule/control encodings; the shared decode
  did not retire.
- R.76--R.78: revisit the detune result lifetimes only if a request enters the
  idle interval, a consumer moves, or the physical service itself can
  disappear.  R.81B separately removed the service's duplicated operand hold.

## Active hypothesis

### R.79 - Batch noise and detune in the multi-pumped transaction

- **Hypothesis:** phases 19 and 24 already launch one noise product and one
  detune product concurrently.  In the HX8K `MULTIPUMP=1` lowering, execute
  each pair as one closed-loop fast-domain transaction: eight radix-2 steps
  for the noise product followed by five narrow radix-4 steps for the exact
  detune coefficient.  If the batch acknowledges by the existing launch+5
  boundary, the complete slow-domain `psg_dqsvc`, its request state, and the
  old/live result plumbing can retire from the hardware target.
- **Scope:** `rtl/psg_mulmp.sv`, `rtl/psg_walk.sv`, `rtl/psg.sv`, multi-pump
  service tests/model, and only the generated/proof artifacts required by
  those files.  Single-clock full rendering and PREVIEW retain the R.78 local
  detune service.
- **Baseline:** `PATH=/opt/homebrew/bin:$PATH make synth-psg`; 7,437 LCs,
  14 EBRs, 144.80/29.94 MHz; 6,536 LUT4s, 1,596 carries, 1,490 flops.
- **Change:** tested an optional held 13x9 detune request in the closed-loop
  multiplier transaction, preserving the primary product while the narrow
  recurrence completed.  The live/old results borrowed dead windows in
  `mx_new`/`mx_old`, so no walker result register was added.  Historical
  single-clock and PREVIEW elaborations retained R.78's local service.
- **Result:** exact arithmetic and schedule, wrong physical shape.  The paired
  boundary passed 63,364 transactions, including all 57,344 detune
  operand/coefficient combinations; true radix-2 busy remained four PSG-clock
  observations.  All ten relative fast/slow offsets passed.  `make test-psg`
  remained at 524/850 observed clocks, fixed 530+272 with 48 spare, tick
  preparation 4,008/5,103 with 1,095 spare and zero late flips.  Fingerprint
  `ad5fe5fe874f` mapped 6,602 LUT4s, 1,585 carries, 1,482 flops and 14 EBRs;
  seed-1 router2 placed 7,515 LCs and routed at 128.93 MHz fast / 31.77 MHz
  PSG.  Versus R.78 this is +66 LUT4s, -11 carries, -8 flops, unchanged EBRs
  and **+78 placed LCs**.  Unpackable flops rose 525 -> 553: the held
  cross-domain payload made `req_dq_a` the largest 333-LUT cone and the
  preserved primary product added 24 unpackable flops.
- **Decision:** rejected and source restored to R.78.  Cross-domain payload
  storage and routing cost more than the complete local recurrence it retired.
- **Repeat only if:** the fast boundary gains a queue/address-selected payload,
  the two results no longer require simultaneous storage, or the clock ratio
  and request phases eliminate a held transaction lifetime.  Do not retry by
  adding another flat held operand bundle.

### R.80 - Factor the complete reciprocal coefficient family

- **Hypothesis:** the common `/3`, `/7`, and `/15` waveform reconstruction
  currently selects six shifted terms into one wide sum.  After the second
  quotient fold, its divisor-specific coefficient is exactly 85, 73, or 17.
  Factor the complete family as `85h = 5*(17h)`, `73h = 8*(9h)+h`, and
  `17h = 17h`, then add the common folded quotient and remainder terms.  Two
  selected shift/add stages should be cheaper than the present independently
  gated term set without adding a register, port, or schedule phase.
- **Scope:** `rtl/psg_wave.sv`, an exhaustive mathematical proof in
  `tools/psg_hw_forms.py`, and standard PSG proof artifacts.  The reciprocal
  EBR, its one registered port, waveform pipeline boundaries, detune service,
  walker schedule, and all result lifetimes stay unchanged.
- **Baseline:** live R.78 fingerprint `dd6d98592a1d`; 6,536 LUT4s, 1,596
  carries, 1,490 flops, 525 unpackable flops, 14 EBRs; seed-1 router2 7,437
  LCs at 144.80 MHz fast / 29.94 MHz PSG.
- **Change:** tested the factored two-step coefficient network at the existing
  combinational pipeline boundary.  Exhaustive proof covered all 65,536 phase
  inputs in both tilt modes, actual second-fold bounds `(255,335,1439)`, and
  every possible seven-bit plus six-bit folded term.
- **Result:** exact algebra, wrong mapped partition.  Candidate fingerprint
  `7f3fb27d04ab` maps 6,543 LUT4s, 1,630 carries, 1,490 flops and 14 EBRs:
  **+7 LUT4s, +34 carries**, unchanged flops/EBRs versus R.78.  Unpackable
  flops rise 525 -> 529.  Placement remains 7,437 LCs and its post-place
  estimates clear timing at 128.14 MHz fast / 31.01 MHz PSG, but router2 is
  stuck with two overused wires after 12,439 iterations.  The route was
  stopped because the deterministic mapped-area gate had already failed;
  structural and render gates were therefore not run.
- **Decision:** rejected and experimental RTL/proof code restored exactly to
  R.78.  Factoring the visible constant coefficients does not make the mapper
  share this already-optimized combinational family.
- **Repeat only if:** coefficient selection, reciprocal folding, pipeline
  boundaries, or mapper arithmetic inference changes materially.

### R.81 - Remove the detune service operand hold

- **Hypothesis:** `psg_dqsvc.start_a_hold[12:0]` duplicates operands that are
  already stable in walker registers for the complete phase-19..29 service
  window.  Feed the recurrence from those existing registers instead.  A
  fixed schedule selector keeps the live operand through the phase-24 terminal
  step/old-request handoff, then selects the old operand for phases 25..29.
  This should retire 13 flops and their launch-input lifetime without changing
  either recurrence, result lifetime, request phase or consumer.
- **Scope:** `rtl/psg_dqsvc.sv`, `rtl/psg_dqsvc_tb.sv`, `rtl/psg_walk.sv`, the
  exhaustive detune gate, standard PSG structural/render gates, and an isolated
  seed-1 HX8K synthesis.  `rtl/psg.sv`, audio RAM, H009/H015 diagnostics and
  Tang board files stay untouched.
- **Baseline:** accepted R.78 fingerprint `e12aae41e2ce`; 6,536 LUT4s, 1,596
  carries, 1,490 flops, 525 unpackable flops and 14 EBRs; seed-1 router2 7,437
  LCs at 144.80 MHz fast / 29.94 MHz PSG.
- **Change:** variant A replaced the launch-captured multiplicand with one
  recurrence operand input.  The walker selected live through phase 24 and old
  from phase 25 onward, so the first terminal step and chained coefficient
  launch remained simultaneous.  Variant B moved only that context bit into
  an otherwise constant recurrence bit, preserving it across steps.
  This removes the new phase-decode cone while retaining twelve net flop
  savings; it does not restore the 13-bit operand payload.  The recurrence
  selects `live_a` or `old_a` from `p[26]`, preserves that bit across all five
  steps, and loads it from `start_old` at each launch.
- **Result:** variant A passes 524,288 formulas, 57,344 transactions, both lint
  modes and the complete structural regression at 524/850 observed clocks,
  fixed 530+272 with 48 spare, and tick preparation 4,008/5,103 with 1,095
  spare and zero late flips.  Fingerprint `1ec43ab92a05` maps 6,538 LUT4s,
  1,590 carries, 1,477 flops and 14 EBRs; seed-1 router2 still places exactly
  7,437 LCs and routes at 127.58 MHz fast / 31.88 MHz PSG.  Versus R.78 this
  is +2 LUT4s, -6 carries, -13 flops, unchanged EBRs/LCs.  Unpackable flops
  rise 525 -> 529, so the retired state did not reduce binding cells.  Variant
  B fingerprint `2cae31b4a425` passes the same 524,288 formula and 57,344
  transaction cases, both lint modes, and the complete structural regression:
  524/850 observed clocks, fixed 530+272 with 48 spare, tick preparation
  4,008/5,103 with 1,095 spare and zero late flips.  All 59 frozen hardware
  renders are byte-identical at 18.75 MHz.  P.1 passes at 1,275 and 159
  clocks/sample (combined 93%; channels 0/1/2 100%/100%/91%; channel 3
  inactive), and P.2 passes both synthetic and frozen-Celeste recovery.
  `/4`, `/5` and `/6`, plus the lowercase five-frame Celeste smoke, pass.
  Four-second hardware and PREVIEW renders have zero `click-v1` events.
  Variant B maps 6,520 LUT4s, 1,592 carries, 1,478 flops and 14 EBRs; seed-1
  router2 places 7,421 LCs and routes at 128.12 MHz fast / 29.90 MHz PSG.
  Versus R.78 this is -16 LUT4s, -4 carries, -12 flops, unchanged EBRs and
  **-16 placed LCs**, with both clocks above their constraints.
- **Decision:** variant A is neutral and not retained.  Variant B is accepted:
  it meets every exactness, schedule, physical-area and routed-timing gate.
- **Repeat only if:** the phase-24 chained handoff moves, either source operand
  can change during its five recurrence steps, or the service interface gains
  an independent request queue.  This is not R.63/R.64 adder sharing, R.76--78
  result-lifetime work, or R.79 cross-domain payload storage.

### R.82 - Recompute the live detune result in the W5--W15 gap

- **Hypothesis:** after W5 consumes the old detune result at phase 34, phases
  35--39 are idle until W15 at phase 40.  Launch the live transaction again on
  the W5 edge and move W6 from phase 35 to its terminal phase 39.  Both W5 and
  W6 can then consume the recurrence directly, retiring the complete 14-bit
  `dq_live_r` lifetime without extending the 530-clock walk or adding a new
  arithmetic, operand hold, result register or request queue.
- **Scope:** the W6 control-store offset, `rtl/psg_walk.sv`, the exhaustive
  detune transaction test if its schedule contract needs coverage, generated
  schedule assertions/visualization, and the standard isolated PSG gates.
  `rtl/psg.sv`, audio RAM, sequencer state, H009/H015 diagnostics and Tang
  board files remain untouched.
- **Baseline:** accepted R.81B fingerprint `2cae31b4a425`; 6,520 LUT4s, 1,592
  carries, 1,478 flops and 14 EBRs; seed-1 router2 7,421 LCs at 128.12 MHz
  fast / 29.90 MHz PSG.
- **Change:** preserved the phase-19 live and phase-24 old transactions, moved
  W6 from phase 35 to phase 39, launched a third live transaction at W5, and
  removed `dq_live_r` plus its phase-24 capture.  The generated control word
  moved with W6; no other action or visit boundary changed.
- **Result:** arithmetic and schedule are exact, but the physical shape is
  wrong.  The exhaustive gate still passes 524,288 formula cases and 57,344
  transactions.  The complete structural regression passes at 524/850
  observed clocks, fixed 530+272 with 48 spare, tick preparation 4,008/5,103
  with 1,095 spare and zero late flips.  Candidate fingerprint
  `8bbc5b3e64c5` maps 6,546 LUT4s, 1,597 carries, 1,464 flops and 14 EBRs;
  seed-1 router2 places 7,454 LCs and routes at 120.16 MHz fast / 31.20 MHz
  PSG.  Versus R.81B this is **+26 LUT4s, +5 carries, -14 flops and +33 placed
  LCs**.  The third launch and late terminal selection widen the recurrence
  cover enough to cost more than the removed result lifetime.  The schedule
  visualizer was non-normative here: its existing `PLAST` parser failure
  reproduces unchanged on the accepted R.81 checkout.  Render, P.1/P.2 and
  click gates were not run after the deterministic mapped/placed gate failed.
- **Decision:** rejected and main RTL remains at R.81B.  Recomputing a result
  to avoid its lifetime does not pay when it adds another request role to this
  shared recurrence.
- **Repeat only if:** the W5--W15 gap, W6 consumer, live tuple lifetime, or
  recurrence latency changes.  This is a schedule-slack recomputation, not an
  R.40--R.42 cross-family register alias or an R.79 held payload.

## Handoff rule

Before opening the next row, record it with exact formula, transaction, schedule,
render, mapped, placed, routed and timing evidence.
Commit either the accepted RTL or the reverted-source rejection record as one
scoped iteration.  Never stage unrelated files from the dirty main worktree.
