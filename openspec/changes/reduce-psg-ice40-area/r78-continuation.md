# PSG area continuation ledger

This is the compact resume surface after the long-form design/task ledger in
the main worktree reached R.78.  Detailed prior rows remain in that ledger and
git history; do not repeat them without the recorded changed condition.

## Current accepted checkpoint

- **R.78 / `e447962`**: RTL fingerprint `dd6d98592a1d` across the synthesis
  target's RTL set; retained PSG fingerprint `e12aae41e2ce` in the long-form
  ledger.
- Seed-1 HX8K router2: 7,437/7,680 LCs, 14/32 EBRs, 144.80 MHz fast and
  29.94 MHz PSG against 112.5/18.75 MHz requirements.
- Yosys: 6,536 LUT4s, 1,596 carries, 1,490 flops; 525 flops are unpackable.
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
- R.76--R.78: revisit the detune recurrence/result lifetimes only if a request
  enters the idle interval, a consumer moves, or the physical service itself
  can disappear.

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

## Handoff rule

Before opening R.80, record its row with exact formula, transaction, schedule,
render, mapped, placed, routed and timing evidence.
Commit either the accepted RTL or the reverted-source rejection record as one
scoped iteration.  Never stage unrelated files from the dirty main worktree.
