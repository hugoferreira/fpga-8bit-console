# PSG area continuation ledger

This is the compact resume surface after the long-form design/task ledger in
the main worktree reached R.78.  Detailed prior rows remain in that ledger and
git history; do not repeat them without the recorded changed condition.

## Current accepted checkpoint

- **Generic full PSG:** R.81B / `ca18727` plus the required walker-address
  width correction `e099e52`.  Scratch commit `5d172ab` applies that exact
  one-file correction after the isolated executor work.  R.81B's detune
  recurrence still carries its one-bit live/old context in the otherwise
  constant `p[26]`; the address correction prevents `pc_ch[2]` being lost by
  a wide concatenation operand.
- Fresh clean-scratch seed-1 HX8K router2 after the correction: **7,504/7,680
  LCs**, 14/32 EBRs, 145.99 MHz fast and 30.21 MHz PSG against
  112.5/18.75 MHz requirements.  Yosys maps **6,598 LUT4s, 1,597 carries and
  1,478 flops** at RTL fingerprint `343f28025ab0`.  The pre-correction R.81B
  7,421-LC number is historical and is no longer the integration baseline.
- **Separate generic branches, not composed:** H023 plus the canonical H027
  clamp spelling is recorded as `4166e9f` on `codex/psg-rtl-direct-here`:
  6,550 LUT4s, 1,464 carries, 1,476 flops, 14 EBRs and 7,306 seed-1 placed
  LCs at 146.69/32.99 MHz.  The independent continuation then accepted H030
  / `a747493`, an exact trigger-length saturation decode, at 6,546 LUT4s,
  1,462 carries, 1,476 flops, 14 EBRs and 7,297 seed-1 LCs at
  133.69/31.08 MHz.  They change `psg_walk.sv` / `psg_seq.sv`, are not on
  main or in this R.84 scratch tree, and earn no R.84 integration credit;
  composition requires regenerated C2-C-C lineage plus the complete cadence,
  render and physical battery.  H030 has been sent to the coordinating task
  for branch adjudication.
- Fresh preserved-scope accounting attributes 2,557 LUT4s / 564 flops /
  150 unpackable flops / one EBR to `u_walk`, and 1,972 / 535 / 256 / one
  EBR to `u_seq`.  Their joint floor is **4,935 cells**; the full netlist floor
  is 7,130 and actual placement adds 374 cells, so the corrected fixed base
  outside both controllers is 2,569 placed cells.
- **Isolated shared executor:** accepted R.84H-B maps 528 LUT4s, 23 carries,
  34 flops, 26 unpackable flops and exactly two EBRs, for a 554-cell floor and
  559 placed LCs at 68.24 MHz.  It proves G-F's normalized advance family plus
  the complete owner-zero address/data transaction boundary; it implements no
  sample service semantics and is not composed into the generic PSG.
- **Scratch sample frontier:** accepted C2-C-C / `5c133aa` proves the live
  legacy source/value boundary for 30 roots / 27 groups / 18 fixed writes.
  D1-A / `bd6188a` materializes the physical-pool requirements, and the
  current D1-B source audit proves that existing observations close none of
  154 packing fields and only six of 78 path/fold lifetimes.  These are
  proof-only foundations: no candidate transitions, write data, adapter,
  generic integration, synthesis or area credit exists.
- Exact generic gates at the last full checkpoint remain 530 walker + 272
  sequencer clocks in the 850-clock `/6` interval; 59/59 hardware renders
  byte-identical; P.1/P.2 and `click-v1` clean; full/PREVIEW lint, clocks and
  Celeste smoke pass.  The address correction separately passed the generic
  structural test and Tang's 3,600,000-cycle mapped-slot comparison.

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
- R.83: do not retry a register-fed scalar waveform engine.  Both a direct
  expression FSM and an explicit single-chain ALU cost more than `u_wave`;
  serialization must reuse an existing substrate or address-selected state.

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

### R.83 - Replace the complete waveform pipeline with a scalar service

- **Hypothesis:** return the iCE40 PSG domain from `/6` to `/4`, retain the
  invariant 272 sequencer credits, and spend the recovered clocks evaluating
  live-primary, live-secondary, old-primary and old-secondary through one
  scalar waveform service.  Retiring the complete four-context `psg_wave`
  pipeline, rather than respelling its individual expressions, should cross
  the first 7,000-LC milestone while preserving exact R.81B behavior.
- **Scope:** mathematical/cycle proof in `tools/psg_wave_serial_model.py`,
  isolated radix-4/radix-8 small-divider and full waveform-service spikes,
  and synthesis only.  Integration into `psg_walk`, clock changes and the
  expensive render/click battery are conditional on the isolated service
  fitting the measured replacement budget.  Unrelated dirty main files stay
  untouched.
- **Baseline:** accepted R.81B is 6,520 LUT4s, 1,592 carries, 1,478 flops,
  14 EBRs and 7,421 LCs.  The R.78 flattened ownership is `u_walk` 2,670
  LUT4s / 576 flops, `u_seq` 1,980 / 533 and `u_wave` 737 / 97; the three own
  5,387 of 6,536 LUT4s.  Removing only `u_wave` at `/4` placed a non-functional
  6,550-LC ceiling, so even before R.81B's 16-cell improvement a replacement
  may spend no more than about 450 LCs to reach sub-7k.
- **Mathematical result:** exhaustive proof covers every one of the 524,288
  unsigned 19-bit numerators for `/3`, `/7` and `/15`, plus all 2,097,152
  combinations of 32 wave/alternate/primary-secondary contexts and 65,536
  phases against exact R.78/R.81B waveform semantics.  A cycle-state
  interpreter executes every micro-operation on a separate edge and proves
  every commit again.  It exposed two hidden assumptions: inactive low-organ
  phases must feed canonical zero, not a masked negative value, to the
  unsigned divider; and the high tilted-saw working value reaches 368,634,
  so the proposed 18-bit signed accumulator was impossible.  R.81B's
  alternate-organ secondary remains +/-1535, while `wave_pair()` expects
  +/-3071; the 59-render matrix does not exercise that combination, so the RTL
  behavior remains the area oracle and the discrepancy stays separate.
- **Divider result:** both small-divider shapes pass all 1,572,864
  numerator/divisor transactions.  Isolated radix-4 is 67 LUT4s, 20 carries,
  49 flops and 113 LCs at 116.52 MHz.  Radix-8 is 79 LUT4s, 47 carries,
  50 flops and 162 LCs at 87.11 MHz.  The 49-LC premium buys three clocks per
  divide and is materially different from the rejected wide radix-8
  multiplier; both easily clear the 28.125 MHz PSG domain.
- **Change:** variant A implemented the original fixed sixteen-edge service
  directly from the context-specific expressions.  Variant B used radix-8 to
  decompose the maximal path into genuine single-add micro-operations, with
  one explicit 20-bit add/sub chain, one accumulator write site and one
  selected scratch destination.  Both variants pass all 2,097,152 exact RTL
  transactions with the result captured on edge sixteen.
- **Physical result:** both shapes fail the pre-integration area gate.
  Variant A maps 1,215 LUT4s, 295 carries and 132 flops, placing at **1,329
  LCs** and routing at 40.91 MHz.  The explicit-chain variant improves to 847
  LUT4s, 179 carries, 114 flops and **1,018 LCs** at 47.68 MHz, but it is still
  larger than the complete 737-LUT `u_wave` it would replace and more than
  twice the roughly 450-LC milestone budget.  Its divider is small; operand,
  operation and destination selection dominate.  Integration therefore
  cannot improve the accepted PSG, so it was not attempted.
- **Decision:** rejected after the two-shape stop rule.  Experimental service
  RTL is discarded; the exhaustive model is retained as the durable proof and
  negative result.  The 7k rung must remove an execution substrate rather than
  add another register-fed service.
- **Repeat only if:** waveform state/operands move into address-selected
  storage, an existing walker/sequencer execution substrate performs the
  operations without another wide request/result mux, or measured `u_wave`
  ownership changes materially.

### R.84 - Replace both mutually exclusive controllers with one stored-state executor

- **Hypothesis:** the full-schedule walker and tick sequencer are not two
  concurrent machines.  `prun | state_replay | fold_busy` freezes the
  sequencer for the complete sample job, and the walker is idle for every
  sequencer credit.  Replace both full-mode controllers, their decoded
  working-register files and their separate destination muxes atomically with
  one micro-PC, one 16-bit program word and the unused per-slot state words as
  an address-selected working store.  Keep PREVIEW on the accepted controller
  pair.  This is the whole-substrate/address-selected condition left open by
  R.83, not another register-fed ALU or partial control-word migration.
- **Scope:** a new full-only executor and generated 256x16 program image,
  `psg.sv` composition, the existing state-store port, exact executor/model
  tests, `tools/psg_ff_census.py`, and the standard PSG gates.  The current
  `psg_walk`/`psg_seq` stay as the PREVIEW implementation until the full
  executor is accepted.  Audio RAM, waveform formulae, multiplier/divider
  arithmetic, public register behavior and frozen renders do not change.
- **Baseline:** accepted R.81B fingerprint `2cae31b4a425`; 6,520 LUT4s,
  1,592 carries, 1,478 flops, 533 unpackable flops, 14 EBRs and 7,421 placed
  LCs at 128.12 MHz fast / 29.90 MHz PSG.  `psg_ff_census.py --scopes` now
  derives preserved-scope ownership directly from the mapped JSON:

  | subtree | LUT4 | carry | flop | unpackable | EBR | LC floor |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | full design | 6,520 | 1,592 | 1,478 | 533 | 14 | 7,053 |
  | `u_walk` including `u_dq` | 2,216 | 572 | 564 | 150 | 1 | 2,366 |
  | `u_seq` | 2,027 | 349 | 531 | 252 | 1 | 2,279 |
  | both controllers | 4,243 | 921 | 1,095 | 402 | 2 | 4,645 |

  The pair therefore owns 65% of mapped LUTs, 74% of flops and 66% of the
  netlist's `LUT4 + unpackable-flop` placement floor.  The remaining
  conservative floor is 2,408.  Actual placement exceeds the total floor by
  368 cells, so, holding that routing/packing overhead fixed, a replacement
  executor predicts `placed = 2,776 + executor_floor`.
- **Milestone bound:** the maximum replacement floors are 4,224 for 7,000
  LCs, 3,224 for 6,000, 2,724 for the 5,500-LC OpenSpec ceiling and 2,224 for
  5,000.  Against the current 4,645-floor pair these require reductions of
  421, 1,421, 1,921 and 2,421.  Replacing only the walker leaves a predicted
  5,055-cell zero-cost base; its replacement budgets are 1,945/945/445/-55.
  Replacing only the sequencer leaves 5,142; its budgets are
  1,858/858/358/-142.  Therefore neither one-controller rewrite can establish
  the 5k rung even with a free replacement: the ownership merge is mandatory.
  The bound is conservative because the shared subtotal still includes the
  multiplier's 448-LUT `req_a` and 179-LUT `req_b` selection families, which
  a stored-state requester may reduce.
- **Clock schedule:** retain exactly 272 sequencer advances after each sample,
  the R.54 invariant that makes clock changes render-neutral.  `/6` leaves
  578 clocks for sample execution (48 beyond today's 530); `/5` leaves 748;
  `/4` leaves 1,003.  R.84 uses the `/4` full-mode budget for synchronous
  operand reads and keeps the shipped single-clock radix-4 sequencer-busy
  duration.  A sample program must commit `dry_valid` by clock 1,003; tick
  code receives exactly 272 non-sample executor clocks regardless of the
  remaining interval slack.  PREVIEW retains its current 159-clock compact
  schedule.  A later `/5` or `/6` return is a separate recompaction result,
  not assumed in the area bound.
- **Program and address map:** retain the existing constants EBR and fold-
  quotient EBR, and spend at most the one remaining block on a 256x16
  full-executor program, for 15 EBRs total.  Program pages are sample/fold
  `0x00..0x3f`, tick/effect `0x40..0xbf`, and trigger/music flow
  `0xc0..0xff`; ordinary instructions advance implicitly and branch-format
  words carry an eight-bit target.  Persistent per-slot words `0..32` remain
  byte-for-byte unchanged and word 33 remains reserved.  Words `34..63` are
  the mutually exclusive working store: 34/35 operand A low/high+flags,
  36/37 operand B low/high+context, 38/39 result low/high+flags, 40..43 four
  scalar temporaries, 44..46 the three fold-stack words, 47 fold metadata,
  and 48..63 owner-specific workspace.  Sample ownership uses the workspace
  for phase/wave/noise/gain/filter intermediates; tick ownership overlays the
  same addresses with voice/instrument fields, accumulator/word staging,
  volume and slide-affine intermediates.  One synchronous read supplies the
  next operand; the existing independent write port commits one result by
  address.  No general register index or wide source/destination mux is added.
- **Complete retirement boundary:** the accepted candidate removes the full
  elaborations of `u_walk` (including `u_dq`) and `u_seq`, their `pph`, `fmc`,
  `sst`, `xs`, `vcnt`, per-owner slot/control state, decoded record load/store
  muxes, walker working copies, sequencer voice/instrument working copies,
  slide/effect temporaries, and register-resident fold stack.  One executor
  micro-PC/owner/slot/flags set replaces their control state.  Semantic state
  does not disappear: `playing`, SFX/row/trigger/release arrays, music/fade
  state, LFSRs and persistent oscillator fields are re-homed unchanged behind
  executor actions or the existing record.  The constants/fold tables remain
  one block each, while the new program consumes the fifteenth block.
- **First implementation gate:** switch the complete full controller pair in
  one elaboration boundary; do not migrate one `pph`/`sst` consumer at a time.
  Prove generated program size/targets, every state address and every output
  commit in an executor model before integrated synthesis.  Reject before
  renders unless the deterministic mapped result is below the 3,224-floor
  6k budget trajectory and seed-1 placement improves; an accepted stage must
  then pass exact schedule, formula/transaction, 59-render, P.1/P.2,
  `click-v1`, lint, clock, Celeste, routing and both-clock timing gates.
- **R.84B fixed-cost result:** the controller shell implements one dynamic
  eight-bit PC, owner, slot, four conditions, direct 64-word-per-slot state
  addresses and branch/jump/slot/owner/done formats around a 256x16 program.
  The first spelling assigned the instruction register from reset, launch and
  advance sites, so Yosys could not infer a block ROM.  The retained spelling
  has one reset-free clocked read enabled only by launch or advance; reset is
  safe because `active` remains false until the first fetched instruction.
  Icarus self-checks taken/untaken branches, hold, state copy, owner, slot and
  completion.  Testbench and target Verilator lint pass.  Yosys infers exactly
  one `SB_RAM40_4K` and maps **43 LUT4s, 7 carries, 14 flops, 10 unpackable
  flops, one EBR and a 53-LC floor**.  Seed-1 nextpnr places and routes **57
  LCs / one EBR at 122.22 MHz** against 28.125 MHz.  With the R.84A fixed-base
  model this shell alone predicts 2,829 placed LCs; behavior-bearing actions
  may still spend 4,171/3,171/2,671/2,171 floor cells before the
  7k/6k/5.5k/5k rungs respectively.  This is a cost decomposition, not a PSG
  area claim: action logic, persistent-state ownership and exact program
  behavior are not yet implemented.
- **Decision:** R.84A's bound and R.84B's physical foundation are accepted;
  the complete R.84 migration remains active.  The fixed controller cost is
  negligible and the program really occupies the fifteenth EBR, so the next
  gate is the generated action/program model required above.  Repeat R.83
  only through this address-state executor; do not add another flat waveform
  request/result service.
- **R.84C hypothesis:** the legacy `pph`/`sst`/`xs` machines can be
  lowered into fewer than 256 address-state instructions without encoding
  their phase/state identities again in a wide PC decode.  Use the unused
  seven instruction bits on read/write/execute formats as a structured action
  field, pipeline synchronous state reads explicitly, and enumerate every
  persistent/scratch address, branch target and externally visible commit in
  an executable generator/model.  Sample code may wait on true service-ready
  conditions instead of storing legacy idle phases; the top-level still gives
  the sequencer exactly 272 advances per sample, so this changes no audible
  ownership boundary.  Accept this iteration only if all three program pages
  fit, every path terminates inside the `/4` 1,003-clock sample bound, and the
  action field remains address-selected rather than rebuilding flat operand
  or destination bundles.  Scope is the generator/model, controller
  interface/test/isolated target and this ledger; generic PSG integration is
  still forbidden until the model closes.
- **R.84C result:** accepted as the generated control/data-movement contract.
  The executable model extracts all 63 legacy sequencer states, removes the
  `xs`/`vcnt` loop identities into 85 address-state nodes and proves every
  node can reach `S_IDLE`.  All defined 16-bit instruction-format encodings
  round-trip; every generated branch/jump names a compiled instruction; every
  persistent address is below 34 and scratch stays in 34..63; synchronous
  reads are consumed by the following action; and the twelve externally
  visible commit families are inventoried against the legacy RTL.  The sample
  page uses 62/64 words and takes a conservative 652/1,003 `/4` clocks, leaving
  351 spare.  Tick/effect uses 99/128 words and trigger/music 26/64.  The
  generated image is freshness-checked byte-for-byte.  Sample actions use 57
  codes (family occupancy 15/3/16/14/3/6/0/0); tick actions use 85
  (13/12/9/13/13/15/10/0), so no family exceeds its sixteen-subop field.
  Icarus self-check, testbench and production-target Verilator lint, Python
  compilation and strict OpenSpec validation pass.  The production image still
  infers exactly one EBR and maps to 86 LUT4s, 7 carries, 14 flops, 10
  unpackable flops and a 96-LC floor.  Seed-1 places and routes at 100 LCs,
  one EBR and 103.16 MHz against 28.125 MHz.  This proves instruction control,
  storage movement and capacity only: arithmetic actions, output semantics,
  schedule equivalence, frozen renders and whole-PSG area remain R.84D/full
  integration gates.
- **R.84C decision:** retain the controller interface, generated image and
  executable contract.  The one-EBR image fits with two sample words, 29 tick
  words and 38 flow words spare; physical fixed cost remains negligible
  against the 3,224-floor 6k replacement budget.  Do not cite this result as
  behavioral equivalence or as a PSG LC reduction.
- **R.84D active hypothesis:** the common action substrate needs only one
  16-bit accumulator, carry/overflow/zero/negative flags and the synchronous
  `state_q` word.  Reserve action family 7 for pass, add/adc, sub/sbc, Boolean,
  shift/rotate, negate and compare micro-operations; feed `state_q` directly
  as the sole operand and publish the accumulator directly as `state_wd`.
  Operation selection occurs before one accumulator write site, and carry
  makes wider values byte/word serial without a second source or destination
  mux.  This is materially different from R.83's rejected register-fed scalar
  engine: there is no context bundle, general register index or selected
  destination, and the operand is the addressed state-memory output.  Scope is
  the isolated controller/datapath interface, a self-checking arithmetic test,
  target, and this ledger; generic `psg.sv`, `psg_walk` and `psg_seq` remain
  untouched.  Baseline R.84C is 86 LUT4s, 7 carries, 14 flops, one EBR, a
  96-LC floor and 100 placed LCs at 103.16 MHz.  Reject this spelling if the
  controller plus complete primitive core exceeds a 300-LC floor, loses the
  one-EBR inference, or requires any flat source/destination bundle.  Passing
  this gate prices a primitive substrate only; legacy macro-action semantics,
  schedule and render equivalence remain later gates, and the accepted
  controller pair stays in the whole PSG until an atomic switch.
- **R.84D result:** variant A exposed live equality, unsigned-order and
  signed-order comparisons beside separately spelt arithmetic operations.  It
  mapped 465 LUT4s, 113 carries, 34 flops, 14 unpackable flops and a 479-LC
  floor; seed-1 placed 490 LCs at 76.99 MHz.  The `cond` family alone was 216
  LUT4s.  Variant B made compare an explicit action and exposed registered
  flags only, but its five source-level arithmetic expressions still mapped
  as five physical chains: 401 LUT4s, 100 carries, 34 flops, 26 unpackable and
  a 427-LC floor; 437 placed LCs at 77.62 MHz.  The final spelling selects
  operand inversion and carry-in before one 17-bit add/sub expression, folding
  ADD/ADC/SUB/SBC/CMP/NEG onto one physical chain.  It passes 327,680
  arithmetic operand pairs spanning every low-byte pair with independently
  perturbed high bytes, plus directed Boolean, shift/rotate, negate, flag,
  inactive and non-execute cases.  The controller test and both Verilator lint
  targets pass.  The isolated target maps **271 LUT4s, 23 carries, 34 flops,
  27 unpackable flops, one EBR and a 298-LC floor**; the datapath subtree is
  193 LUT4s, 16 carries, 20 flops and a 210-LC floor.  Seed-1 places and routes
  at **303 LCs / one EBR / 68.50 MHz** against 28.125 MHz.
- **R.84D decision:** accept the factored primitive substrate.  It is 202
  mapped cells smaller than the duplicated-adder form, meets the predeclared
  300-floor gate and leaves 2,926 floor cells inside R.84's 3,224-cell 6k
  replacement budget.  The changed condition versus R.83 is now physical:
  one addressed memory operand, one accumulator destination and one carry
  chain, with compare serialized into that chain.  This does not yet prove any
  legacy macro action, schedule or render and is not a whole-PSG area result.
- **R.84E hypothesis:** lower one complete owner-side record
  movement family onto the controller plus common accumulator using a real
  synchronous state-memory model.  Generated action metadata must identify
  the consumed read and committed write address without adding a general
  register index or another EBR.  Prove every transaction against the legacy
  record layout and account every extra hold clock before adding arithmetic
  macro semantics.  Work remains isolated; do not partially replace a
  `pph`/`sst` consumer in the whole PSG.
- **R.84E result:** accepted after the generated program invalidated the first
  apparently passing spelling.  `V_LD0..7` read persistent words
  `3,4,5,8,9,26,32,26`; actions 1..7 stream the first seven returns into
  scratch `48..54`, and the existing `K_ADV` action drains the final repeated
  word 26 into scratch 53.  `V_ST0..4` copy scratch `48,49,50,52,54` back to
  persistent `3,4,5,9,32`.  No general register index, movement register,
  second EBR or hold clock is introduced.
- **R.84E defect and correction:** the first test put `K_ROT` immediately
  before `V_ST0` and therefore passed, but the real generated paths are
  `K_ROT -> PC0..PC3 -> V_ST0` and the evaluated `P_W0..P_W3 -> V_ST0` path.
  Both overwrite the synchronous read output, so a `K_ROT` scratch-48 prime
  was invalid.  The corrected contract issues scratch 48 on `PC3` or `P_W3`,
  after each action has consumed its current `state_q`; they are the two
  immediate predecessors of `V_ST0`.  The executable generator now pins both
  codes, successors and all V_LD/V_ST word metadata, and the synchronous
  memory test executes both store paths.  This is why R.84E is a transaction
  proof rather than a decode-only test.
- **R.84E gates and physical result:** the generated image remains
  byte-identical at 62/64 sample, 99/128 tick and 26/64 flow words; all 85 PC
  nodes still reach idle and the conservative sample path remains 652/1,003
  clocks.  Icarus passes the controller redirection test, all 327,680 R.84D
  arithmetic pairs and the synchronous 8-load plus two-by-5-store movement
  test; controller, movement and production target Verilator lint are clean.
  Against R.84D's 271 LUT4 / 23 carry / 34 flop / 298-floor / 303-placed
  baseline, the retained target maps **324 LUT4s, 24 carries, 34 flops, 27
  unpackable flops, one EBR and a 351-LC floor**.  Seed-1 places and routes at
  **357 LCs / one EBR / 68.77 MHz** against 28.125 MHz.  The complete movement
  family therefore costs 53 floor cells and 54 placed cells, leaving 2,873
  floor cells inside R.84's 3,224-cell 6k replacement budget.
- **R.84E decision:** retain the zero-hold address-selected movement family.
  It validates that real record movement is cheap only when reads and writes
  are scheduled at the actual synchronous-memory predecessors.  This remains
  an isolated executor result: legacy macro actions, exact schedule/renders
  and whole-PSG area are not yet proven, and the accepted full PSG still uses
  `psg_walk` plus `psg_seq` until the atomic integration gate.
- **R.84F hypothesis:** lower the complete flow-owned advance family
  (`K_ADV` plus `EA0..EA5`; the earlier `EA6` spelling was a ledger error) as
  address-selected macro actions before changing the generated program.  This
  first price isolates the exact counter, previous-value, length and row
  formulae from microcode capacity and synchronous-read ordering.  Reject the
  shape even when it fits the gross 6k budget if mutually exclusive formulae
  rebuild arithmetic that the legacy schedule already shares.
- **R.84F result:** the ten-action macro passed 58,982,912 exhaustive RTL
  transactions over every counter/speed tuple, every previous-value field,
  every encoded play length and row, and every loop bound/released state.
  The R.84D datapath still passed 327,680 arithmetic pairs and both production
  lint modes were clean.  This proves the individual formulae only: the
  generated `EA0..EA5` nodes remained placeholders, so no program, synchronous
  controller or whole-PSG behavior claim was made.
- **R.84F physical result:** against R.84E's 324 LUT4 / 24 carry / 34 flop /
  351-floor / 357-placed baseline, the isolated target mapped **512 LUT4s, 101
  carries, 34 flops, 12 unpackable flops, one EBR and a 524-LC floor**.  Seed-1
  placed and routed **581 LCs / one EBR / 71.48 MHz** against 28.125 MHz: +188
  LUT4s, +77 carries, -15 unpackable flops, +173 floor cells and +224 placed
  LCs.  The macro module alone is 190 LUT4s and 77 carries.  Those 77 carries
  are the separately spelt rollover, two loop/end families, bound compare,
  counter increment and length decrement; legacy `psg_seq` deliberately
  time-selects these through one `ta_a`/`ta_b` compare.
- **R.84F decision:** rejected and fully reverted before commit.  Although its
  524-cell floor fits the gross R.84 budget, it repeats R.83's foundational
  failure inside the new executor: parallel operation cones selected after
  computation instead of time-serialized address-state work.  Do not retry
  the macro shape merely because it fits.  The exhaustive result is retained
  in this row; no R.84F RTL, test harness or stale generated image lands.
- **Repeat only if:** the macro actions select operands before the existing
  common arithmetic chain, rather than owning any independent `+`, `-`, `<`
  or `>=` expression, or a later whole-program measurement proves that added
  branch/read words cost more than the 77 duplicated carries they replace.
- **R.84G next permitted hypothesis:** make branch condition and sense
  explicit in the `Node` contract, then lower the real foreground and
  instrument advance paths as synchronous reads, common-ALU operations,
  branches and writes.  Duplicate control words across the two bank layouts
  where that removes `abank` data muxes; spend the measured 29 tick-page and
  38 flow-page spare words before introducing any named working register.
- **R.84G-A active hypothesis:** first replace successor-order branch
  inference with explicit ordered `(condition, sense, target)` edges, one
  explicit default edge and explicit tick/flow page ownership.  Add a pinned
  action-code API and a synthetic non-ordinal, negative-sense, repeated-target
  and cross-page emission proof.  Existing unlowered legacy nodes may retain
  their provisional ordinal conditions only through a visibly named helper;
  the emitter itself must never invent a predicate.  The generated image must
  remain byte-identical at 99/128 tick words and 26/64 flow words.  Scope is
  `tools/psg_exec_model.py`, its generated-image freshness check and this
  ledger; no RTL or whole-PSG behavior claim is permitted in this foundation.
  Reject if the abstraction changes an existing word, loses repeated-target
  priority, permits hard-zero condition indices 4..7, or obscures which nodes
  are still unlowered.
- **R.84G-A result:** accepted as a byte-identical control-model foundation.
  `Node` now carries ordered `Branch(target, condition, sense)` tuples, one
  explicit default, explicit tick/flow page ownership and a visible lowered
  marker.  `emit()` consumes only those fields; the regex topology cannot
  choose a predicate.  The provisional helper preserves all 85 unlowered
  legacy nodes visibly, while the synthetic proof emits condition 12, a
  false-sense edge, two ordered edges to the same target and a cross-page
  default jump.  Pinned action allocation is checked at common action `0x71`,
  generated branches reject hard-zero condition indices 4..7, page ownership
  has no implicit default, and a missing default cannot silently become DONE.
- **R.84G-A gates and decision:** the existing image is byte-identical at
  62/64 sample, 99/128 tick and 26/64 flow words; all 85 nodes still reach
  idle and are reported as **0 lowered / 85 visibly unlowered**.  Python
  compilation/model, controller self-check, 327,680 common datapath pairs,
  both five-store movement paths, full/PREVIEW production lint and strict
  OpenSpec validation pass.  Retain this foundation.  It changes no RTL or
  generated word and therefore inherits R.84E's physical result rather than
  claiming a new area or behavior measurement.
- **R.84G-B next permitted hypothesis:** define only the field projection and
  result-packing actions required to drive rollover, length and row work
  through R.84D's existing `wide` expression.  Synthesize each selected-ALU
  spelling before program expansion; reject any variant with a second carry
  chain or source-level free-variable arithmetic outside `wide`.  Cheap
  equality/bitfield packing may remain owner actions, but `<`, `>=`, increment
  and decrement must be serialized through the common chain.
- **R.84G-B active hypothesis:** reserve tick actions `0x47..0x4f` for three
  counter steps (low increment, rollover compare, high increment), one
  length decrement/test, loop-bound compare, two row-to-temporary increments,
  row-to-loop-end compare and row-to-record-end compare.  Each action may only
  select or align `acc`/`state_q` fields and pack `wide` back into `acc`; the
  sole arithmetic expression remains R.84D's 17-bit `wide` chain.  The
  record-end bound may use zero/high-bit tests and a mux, not a second
  comparator.  Exhaustively prove fcnt 255, speed zero, length zero/one,
  row 31, lpe zero and all 8-bit loop bounds before synthesis.  Baseline R.84E
  is 324 LUT4s, 24 carries, 34 flops, a 351-LC floor and 357 placed LCs.
  Reject any spelling that maps more than 24 total carries, exceeds a 430-LC
  floor, adds a register, or expresses free-variable `+`, `-`, `<` or `>=`
  outside `wide`.  This prices primitives only; the image must remain
  byte-identical until R.84G-C lowers the synchronous program.
- **R.84G-B variant A result:** the nine direct projections pass 23,265,280
  exhaustive counter, length, loop and row transactions and map exactly one
  arithmetic chain, but the selected result formats rebuild a wide
  accumulator-input mux.  The isolated target is 480 LUT4s, 24 carries, 34
  flops, 18 unpackable flops, one EBR, a 498-LC floor and 505 placed LCs at
  56.03 MHz.  The accumulator cone alone is 217 LUT4s; three partial-byte
  result packings are the measured excess.  Reject this spelling in place.
- **R.84G-B variant B active hypothesis:** factor the same behavior into eight
  actions with only three accumulator result shapes.  `COUNT_CMP` records
  `fcnt+1>=speed`; `COUNT_STEP` selects either the rollover word or one whole
  `wide` increment while preserving flags.  `LEN_DEC_CLASS` returns one whole
  `wide` decrement and classifies pre-state length zero/one and row 31.
  `LOOP_CMP` records `lps>=lpe`.  Voice/instrument `ROW_CMP` selects either
  `lpe` or the exact legacy end bound before the same chain, recording loop in
  C and end in V; voice looping is suppressed when released.  Voice/instrument
  `ROW_STEP` packs either `lps` or the incremented row while preserving those
  decisions.  This differs materially from variant A by deleting three
  partial accumulator formats from the measured dominant cone.  Apply the
  same 24-carry / 34-flop / one-EBR constraints and reject the selected-
  projection family if its floor exceeds 430 or placement exceeds 470.
- **R.84G-B variant B result:** the factored actions pass 27,262,976
  exhaustive RTL transactions over every counter/speed tuple, encoded length,
  row, loop-bound word, released state and voice/instrument row layout.  The
  target retains exactly 24 carries, 34 flops and one EBR, but maps **500
  LUT4s, 18 unpackable flops and a 518-LC floor**.  The datapath alone is 339
  LUT4s and the accumulator cone remains 225 LUT4s.  Since the deterministic
  floor already exceeds both the 430 acceptance gate and the 470 placement
  ceiling, place-and-route cannot rescue it and was not run.  Netlist audit
  finds only the intended sixteen datapath carries from `wide`; coarse AIG
  size rises from R.84E's 1,013 AND nodes to 1,765 for variant A and 1,816 for
  variant B.  The regression is therefore Boolean selection/packing, not a
  hidden second arithmetic chain or a mapping anomaly.
- **R.84G-B decision:** reject both selected-projection spellings and restore
  the R.84E/R.84G-A datapath exactly.  Selecting eight or nine legacy field
  roles in front of one chain preserves arithmetic hardware but rebuilds a
  larger operand/result/flag cover than the formulas it would retire.  The
  common chain is a useful primitive only for microcode operations whose
  operands already have the common `acc`/`state_q` shape; owner-specific field
  projections must move into address-selected words before execution, not
  into another combinational selector family.
- **Repeat only if:** the persistent/scratch record layout makes the counter,
  length and row operands whole addressed words with common result shape, or
  a complete lowered program proves that removing later pack/move actions
  retires more than this isolated 167-cell excess over R.84E.  Do not retry by
  changing action count or flag spelling around the same field projections.
- **R.84G-C active hypothesis:** normalize legacy counter, length, loop-bound
  and row fields into fixed addressed 16-bit scratch words before arithmetic.
  A pure movement layer may zero-extend a fixed byte/row field or merge one
  normalized result into a fixed persistent word, but it owns no register,
  carry chain, comparison or accumulator feedback.  The unchanged R.84D
  common actions then perform all increment, decrement and compare operations
  on whole `acc`/`state_q` words, and explicit branches preserve foreground
  length-stop, released-loop suppression, loop-before-end priority and the two
  row layouts.  This is the changed substrate permitted by R.84G-B: selection
  terminates at an address-selected write rather than feeding arithmetic or
  the accumulator D mux.
- **R.84G-C first gate:** derive the complete synchronous microprogram and
  prove its instruction count against the 29 spare tick and 38 spare flow
  words, allowing explicit cross-page edges before editing the image.  Price
  the fixed normalizer beside the exact R.84E datapath before program
  expansion.  Reject if it adds a carry or flop, loses the one-EBR inference,
  exceeds a 430-LC floor, or needs a general source/destination index.  If it
  passes, exhaust every counter/speed tuple and every length/row/loop/released
  combination, then lower only the complete EA family; no partial generic-PSG
  integration or whole-PSG area claim is permitted at this stage.
- **R.84G-C hold prerequisite:** the resume audit found that `psg_execctl` and
  `psg_execmove` suppress advance and writes on `hold`, but `psg_execdp`
  qualifies execution only with `active`.  A held common ADD/SUB/shift would
  therefore re-execute on every frozen clock after integration.  Gate the one
  datapath commit site with the same hold signal, inject a hold over a live
  arithmetic instruction in the self-check, and re-price the isolated R.84E
  baseline before accepting any normalizer result.  This is a correctness
  prerequisite, not an area hypothesis.
- **R.84G-C hold prerequisite result:** accepted as an independent correctness
  foundation.  `psg_execdp` now qualifies its sole commit site with `!hold`,
  and the arithmetic self-check holds a live ADD while proving accumulator and
  flags remain unchanged.  Controller, movement, generated-image/model and
  both production lint modes pass; the common datapath still passes all
  327,680 arithmetic pairs.  The canonical isolated HX8K target maps **328
  LUT4s, 24 carries, 34 flops, 25 unpackable flops, one EBR and a 353-LC
  floor** and seed-1 router2 places **359 LCs** at **54.76 MHz**, versus
  R.84E's 324/24/34/27/one-EBR/351-floor/357-placed result.  The two-cell
  cost is retained because every integrated executor must freeze atomically;
  it does not establish any R.84G-C normalizer or whole-PSG result.
- **R.84G-C physical probe:** the cheapest six-action sidecar only
  zero-extends a fixed low byte, high byte or voice/instrument row and merges
  a row back into its fixed raw word.  Folding those results into R.84E's
  existing copy write-data selector maps **356 LUT4s, 24 carries, 34 flops,
  25 unpackable flops, one EBR and a 381-LC floor** on the canonical toolchain;
  seed-1 router2 places **387 LCs** and routes at **62.31 MHz**.  This is an
  optimistic +28-cell price over the hold-corrected R.84E baseline, with no
  added carry or flop, but it is only a primitive probe: previous-value,
  `ins_use` and side-effect actions are not present.
- **R.84G-C program-capacity result:** the fixed normalized manifest cannot
  fit the one-EBR instruction store.  Scratch 34..45 hold constants 1/32,
  normalized fcnt/tcnt/speed/length/row/lps/lpe/end-bound, tcnt-or-length and
  row-plus-one; the exact end bound is lps only when lpe is zero and lps is
  1..31, otherwise 32.  The explicit voice and instrument paths require 69
  and 50 words.  Exhaustive layout removes every unconditional transfer whose
  target can physically fall through, four and one respectively, leaving a
  fixed-manifest lower bound of **65 + 49 = 114 words**.  Every remaining word
  is a distinct READ, WRITE, EXEC or conditional BRANCH; the three-bit opcode
  cannot combine those effects, and synchronous reads already issue the next
  address in the preceding consume operation.
- **R.84G-C capacity arithmetic and decision:** the live image is 62 sample +
  99 tick + 26 flow words, and `K_ADV/EA0..EA5` occupy exactly
  4+1+1+1+4+1+4 = 16 tick words.  Replacement yields
  `62 + (99-16+65) + (26+49) = 285` words: tick is 148/128, flow is 75/64,
  and the 4,560-bit image exceeds one 4,096-bit EBR by **29 words / 464 bits**.
  Cross-page packing cannot help because tick+flow alone is 223/192.  This is
  an optimistic failure: preinitialized constants cost no words, while exact
  `ins_use`, cpz/pend-stop and any missing side effect can only add work.
  Reject the fixed one-EBR scratch-normalized spelling before RTL or image
  expansion.  The six-action pricing sidecar remains scratch-only; no R.84G-C
  RTL, test or generated image lands.
- **R.84G-D next permitted hypothesis:** bank the program with the already
  registered execution owner: address two 256x16 banks as `{owner, pc}` so
  the 62-word sample program and 223-word tick/flow program each fit without
  widening the PC, branch target or instruction.  This is a whole-substrate
  resource exchange, not a one-EBR retry: atomic integration retires the
  walker's and sequencer's two control EBRs, so a two-EBR executor preserves
  the accepted whole-PSG total of 14, still below the 15-EBR ceiling.  First
  prove owner-bank fetch alignment, byte-identical program semantics and the
  isolated two-EBR controller cost; do not restore the normalizer until that
  foundation routes and its whole-PSG EBR accounting is explicit.
- **R.84G-D active hypothesis:** expand only the control-store address to
  `{owner, pc}` while leaving the registered owner, eight-bit PC, branch
  target and sixteen-bit instruction unchanged.  Owner zero contains the
  62-word sample program and owner one contains the current 125-word
  tick/flow program; each branch and jump must remain inside its selected
  bank unless an explicit `OP_OWNER` changes the bank for the following
  fetch.  The test must distinguish the same PC in both banks, prove an owner
  change fetches from the new bank without a bubble, and prove hold freezes
  bank, PC and instruction together.  The generated image must be exactly
  512 words and the isolated HX8K target must infer exactly two EBRs.  This
  iteration establishes only the banked foundation and future 223/256
  tick/flow capacity; it does not yet restore normalization, lower the
  advance family or claim whole-PSG behavior/area equivalence.
- **R.84G-D result:** accepted as the owner-banked control-store foundation.
  The generated image is exactly 512 words: owner zero contains the unchanged
  62-word sample program, and owner one contains the unchanged 99-word tick
  plus 26-word flow program.  The generator validates branch and jump targets
  independently inside each bank, and proves the normalized replacement will
  occupy 148+75 = **223/256** owner-one words.  The controller self-check
  distinguishes two instructions at the same PC in different banks, proves
  `OP_OWNER` fetches the following instruction from the new bank without a
  bubble, and holds bank, PC and instruction stable together.  Controller,
  movement, all 327,680 datapath arithmetic pairs, generated-image freshness,
  full/PREVIEW lint and strict OpenSpec validation pass.
- **R.84G-D physical result and decision:** canonical Yosys maps **328 LUT4s,
  24 carries, 34 flops, 27 unpackable flops and exactly two EBRs**, for a
  **355-LC floor**.  Seed-1 HX8K router2 places **361 LCs** and routes at
  **61.85 MHz**.  Versus the hold-corrected one-bank foundation, logic and
  flop counts are unchanged; the ninth address bit costs only two unpackable,
  floor and placed cells while the second 4-kbit image consumes one EBR.
  Retain this foundation because atomic R.84 integration exchanges the two
  legacy walker/sequencer control EBRs for these two executor EBRs and thus
  preserves the accepted whole-PSG total of 14.  No partial integration or
  whole-PSG equivalence claim is made here.
- **Repeat only if:** execution ownership is no longer mutually exclusive,
  owner changes cannot precede their bank transition, either complete program
  exceeds 256 words, or atomic integration fails to retire both legacy control
  EBRs.  Do not retry a larger flat PC or wider instruction for this capacity
  problem.
- **R.84G-E hypothesis:** re-derive the complete advance-family program as an
  executable generated manifest before adding any normalization RTL.  The
  223-word G-D figure deliberately omitted `ins_use` and skip/stop effects;
  the owner-one bank has 33 apparent spare words, so exact K_ADV priority,
  previous-value updates, length/loop/end priority and all exit side effects
  must be represented and counted rather than assumed to fit.
- **R.84G-E result:** accepted as the exact generated-control foundation.  The
  independent legacy audit found no EA6: K_ADV plus EA0..EA5 lower to a
  **68-word voice path** and a **49-word instrument path**.  The three words
  missing from G-D's optimistic voice bound are the `ins_use` edge, the
  converged voice-stop effect and the skip-path `cpz := !playing` effect.
  Replacing the old 16 words therefore yields
  `(125 - 16) + 68 + 49 = 226/256`, leaving **30 owner-one words**.
  `tools/psg_exec_model.py` now constructs all 117 instructions, repacks the
  83 remaining tick and 26 flow words around them, resolves every branch and
  jump inside the bank, and emits that exact 226-word image instead of merely
  asserting a capacity estimate.  Owner-zero's 256 words remain byte-identical
  to G-D.
- **R.84G-E semantic result:** **15,534,336 decomposed cases** exhaust the
  counter rollover, modulo tick count, six-bit foreground length, all raw
  loop-start/loop-end bytes, every row/released combination, exact end-bound
  construction and fixed unrelated-bit-preserving merges.  The manifest keeps
  trigger before advance-skip, commits both counters before later decisions,
  updates previous pitch/volume only on rollover, gives foreground length
  priority over loop/end, gives valid unsuppressed loop priority over end, and
  sends instrument no-roll/loop/end paths to I_NL.  Image freshness and the
  bank/hold controller self-check pass.  The program-only image change is
  physically identical to G-D: canonical Yosys maps **328 LUT4s, 24 carries,
  34 flops, 27 unpackable flops and exactly two EBRs** for a **355-LC floor**;
  seed-1 HX8K router2 places **361 LCs** at **61.85 MHz**.  This remains a
  control/semantic model:
  the fixed movement/merge decoder, owner predicates and side effects are not
  RTL yet, so no full transaction or whole-PSG equivalence claim is made.
- **R.84G-E integration guards:** V_LD0 must initialize scratch 34 to one and
  K_ADV scratch 35 to 32; scratch 36..45 have the recorded normalized fields
  and 48..54 retain the raw record stream.  The current placeholder hardcodes
  active parameter word 26, while legacy selects 26 or 30 from `spar_bank`;
  P/PC publication addresses have the same active/inactive-bank dependency.
  Also, `pend_stop` and `cpz` effects must remain in the sequencer's existing
  arbitrated sequential block so same-edge clears/releases preserve legacy
  nonblocking-assignment priority.  R.84G-F must prove those hazards in a real
  synchronous transaction harness before atomic integration.
- **Repeat only if:** the state-word layout, synchronous read latency, branch
  predicates, effect priority or K_ADV/EA transition graph changes.  Do not
  return to the unreproducible 65/49 prose bound or treat the 30 spare words as
  proof that the missing RTL decoder is behaviorally complete.
- **R.84G-F active hypothesis:** the exact 117-word G-E manifest can execute
  the complete foreground and instrument advance transaction through a fixed
  six-action normalization/merge decoder plus R.84D's unchanged common ALU,
  without recreating G-B's field-selected accumulator mux.  Each action has a
  fixed source or destination shape: zero-extend one low byte, high byte or
  voice/instrument row into the already addressed word; or merge one
  normalized row/value back into its fixed persistent word.  Synchronous read
  overrides and writes are derived from the numbered manifest, not inferred
  from action names.  Branch conditions add only the four exact owner facts
  `trig_req`, `walk_tick && playing`, `ins_use` and `released`.
- **R.84G-F scope and baseline:** work only in the isolated executor/model,
  movement/datapath/controller tests, generated image and this ledger; generic
  `psg.sv`, `psg_walk`, `psg_seq`, Tang/H015 and atomic integration remain
  untouched.  Baseline G-E is 328 LUT4s, 24 carries, 34 flops, 27 unpackable
  flops, exactly two EBRs, a 355-LC floor, 361 placed LCs and 61.85 MHz.  The
  fixed decoder must add no carry, flop, EBR, general register index or free-
  variable arithmetic expression.  Its only data selection must terminate at
  a fixed addressed write; all increment, decrement and compare work remains
  whole-word execution through the existing `wide` chain.
- **R.84G-F transaction gates:** initialize scratch 34 to one at `V_LD0` and
  scratch 35 to 32 at `K_ADV`; select active parameter word 26 or 30 from
  `spar_bank`, and derive every P/PC active/inactive publication address from
  the same bank.  Instrument previous pitch is persistent word 9 bits 5:0 and
  previous volume is bits 11:9.  Prove every manifest instruction against a
  real synchronous memory model, including read-issue/consume alignment,
  every fixed merge, all four new predicates, both parameter banks, trigger,
  skip, stop, loop and instrument exits.  Keep `pend_stop` and `cpz` updates in
  the sequencer's existing arbitrated sequential owner in the future adapter;
  the isolated harness must emit effects rather than create a competing
  writer, and must prove same-edge priority before generic integration.
- **R.84G-F result:** accepted as the complete normalized advance-transaction
  foundation.  V_LD0 writes scratch 34 = 1, V_LD6 captures active parameter
  word 26 or 30 into scratch 53, and K_ADV repurposes the redundant repeated
  read edge to write scratch 35 = 32.  All P/PC sources and destinations are
  literal bank-selected addresses; there is no variable address arithmetic.
  The fixed decoder implements the six projection/merge shapes, exact word-9
  instrument previous-pitch/volume fields, four owner predicates and emitted
  VOICE_STOP/SKIP_CPZ effects.  Effects remain outputs for the future existing
  sequencer owner rather than gaining a competing sequential writer.
- **R.84G-F transaction gates:** the executable production-image model passes
  **19,728,640 decomposed semantic cases** and **131,087 synchronous
  counter-domain/path transactions**, with the 512-word image byte-identical
  and the exact 68+49-word manifest still occupying 226/256 owner-one words.
  The controller bank/hold test, all 327,680 common-datapath arithmetic pairs,
  fixed movement test and 11-path production-image synchronous RTL harness
  pass.  The latter covers trigger, skip, both parameter banks, voice and
  instrument no-roll/roll, length priority, stop same-edge priority,
  loop-before-end, released-loop suppression and instrument done.  Isolated
  target plus generic full/PREVIEW Verilator lint pass.
- **R.84G-F physical result and decision:** canonical Yosys maps **530 LUT4s,
  23 carries, 34 flops, 26 unpackable flops and exactly two EBRs**, for a
  **556-LC floor**.  Seed-1 HX8K router2 places **561 LCs** and routes at
  **64.01 MHz** against 28.125 MHz.  Versus G-E this is +202 LUT4s, -1 carry,
  no added flops/EBRs, -1 unpackable flop, +201 floor and +200 placed.  Netlist
  audit finds sixteen carries only in the unchanged common datapath and seven
  in controller PC/slot/program addressing; the fixed decoder adds none.  The
  complete advance family therefore leaves 2,668 floor cells inside R.84's
  3,224-cell 6k replacement budget and is retained.  P_W publication data,
  all other owner actions, generic composition, schedule, renders and
  whole-PSG area remain unproved; no such claim is made by this iteration.
- **Repeat only if:** the numbered manifest, state-word layout, parameter-bank
  publication rule, synchronous read latency, side-effect arbitration or
  legacy field layout changes.  Do not retry G-B's selected arithmetic or
  G-C's one-bank capacity shape inside this decoder.
- **R.84H next permitted hypothesis:** price and lower the remaining complete
  owner action inventory into the same fixed-address/common-service substrate,
  then switch the full-mode walker and sequencer only at one atomic composition
  boundary.  Before any generic RTL edit, enumerate every still-placeholder
  sample/tick/flow action, persistent-state owner, service handshake and output
  commit against the corrected 2,875-floor 6k budget.  Do not partially replace a
  pph/sst consumer, add a register-fed request bundle, or treat G-F's isolated
  transaction proof as render equivalence.

### R.84H - Rebuild both controllers as one memory-native service graph

- **ID / decision:** R.84H is active after a docs-only resume audit.  No new
  semantic RTL is authorized until the action, ownership, service and budget
  facts below are executable in the model.  The one-file `e099e52` address
  correction was first reconciled into scratch as `5d172ab`, because an atomic
  replacement proved against the old aliased walker addresses would have the
  wrong generic behavior.
- **Hypothesis:** the remaining area is not removed by implementing the old
  `pph` and `sst` action cases behind a new PC.  Rebuild their dependency graph
  around the state store: persistent words are read at their actual use,
  owner-specific projections terminate in fixed addressed writes, and the
  existing wave, multiply, divide, detune, ARAM and fold services capture only
  their own fixed request state.  Explicit microinstructions represent fixed
  latency and ready waits.  One owner adapter preserves the legacy
  nonblocking-assignment priority for global/public state.  When every action
  is covered, switch both full-mode controllers together; PREVIEW keeps the
  accepted legacy pair.  This is the whole-substrate/address-selected changed
  condition left open by R.83 and R.84G-B, not a macro decoder or register-fed
  request bundle.
- **Corrected physical baseline:** the fresh `343f28025ab0` generic target is
  6,598 LUT4s / 1,597 carries / 1,478 flops / 532 unpackable / 14 EBRs, with a
  7,130-cell floor and 7,504 routed LCs.  `u_walk + u_seq` own a 4,935-cell
  floor.  Holding the measured 374-cell packing/routing excess fixed gives
  `predicted placed = 2,569 + replacement_floor`.  The replacement limits are
  therefore 4,431 for 7k, 3,431 for 6k, 2,931 for the 5.5k OpenSpec ceiling
  and 2,431 for 5k.  G-F's 556-cell floor leaves **3,875 / 2,875 / 2,375 /
  1,875 cells** for the remaining 7k / 6k / 5.5k / 5k behavior respectively.
  These replace the pre-`e099e52` 4,224/3,224/2,724/2,224 limits.
- **Owner-zero inventory:** all **57 sample actions are semantic
  placeholders**.  They are 18 record/parameter read actions, two noise
  service starts plus fourteen CAP actions, fourteen ordinary oscillator
  stores plus two late dampen stores and one leaf store, and six fold actions.
  The 62-word image proves only PC/address occupancy and a Python clock count.
  Its `Action.wait` credits are not encoded in the program or controller.
- **Owner-one inventory:** G-F's 117-word advance manifest is exact, but
  **56 action sites remain wholly placeholder** and P_W0..P_W3 have only their
  inactive-bank addresses lowered, not publication data.  Eight V_LD, five
  V_ST and K_ROT/PC0..PC3 provide eighteen proved memory transactions, but
  V_LD does not populate the legacy `w_*` flops and V_ST4's completion,
  audible-row update, slot advance and bank arbitration remain legacy.  The
  generator still reports 78 visibly unlowered non-advance nodes.
- **No partial handoff:** G-F makes normalized scratch and persistent words
  authoritative; current K_NL/I_NL/ES/P_W logic reads old working flops.
  Therefore an advance-only switch is behaviorally invalid even though its
  isolated memory transactions pass.  The minimum owner-one boundary is the
  complete `S_IDLE -> V_LD -> trigger/advance/effect/publication -> V_ST ->
  W_MUS -> S_IDLE` graph, including CPU, tick/sample-boundary and fade
  arbitration.  The minimum generic boundary switches owner zero and owner one
  together so both old control EBRs actually retire.
- **Owner-zero state contract:** per-slot words 10..23 are the persistent
  oscillator tuple, active words 24..27 are sounding inputs, and scratch is
  owner-overlaid.  Do not mirror the whole record into another working file by
  default: re-read persistent words at their use, and place only values whose
  cross-service lifetime requires storage into fixed scratch addresses.
  Sample-global state is lfsr/lfsr2, noise alternation and bank-edge state,
  optional reverb ring position/history and `dry16/dry_valid`.  Service-owned
  state remains inside `psg_wave`, `psg_dqsvc`, multiplier, divider, ARAM,
  fdiv5 and ring-read pipelines and is not re-expanded into action arithmetic.
- **Owner-one state contract:** scratch 34..45 is the accepted normalized
  advance workspace and 48..54 is the raw V_LD stream.  Remaining trigger,
  note, effect, slide, publication and music-flow actions must consume those
  addressed values or add a fixed addressed lifetime.  They may not recreate
  `w_row`, `w_ins_row`, previous-value, effect, slide or publication register
  files behind an action mux.
- **Service contract:** fixed waits become explicit owner-bank instructions;
  true variable waits branch on owner-qualified ready facts without replaying
  an issue action.  The 194 spare owner-zero words are the first resource to
  spend.  `psg_wave` remains the measured irreducible fixed-latency waveform
  service with its reciprocal EBR and pipeline registers; ARAM's adjacent
  issue/consume cadence remains exact.  Multiplier, divider and detune starts
  occur once and retire only on their real ready/done contract.  R.84G-F's
  common accumulator is still the only generic arithmetic chain.
- **Three model defects to close before semantic RTL:** owner-zero condition 0
  currently means slot wrap and condition 1 means fold-more, but the common
  datapath exposes Z/N at those indices; assign owner-qualified external
  conditions instead.  The provisional fold reads slot-zero word 48 twice and
  has no seven-leaf/stack address schedule.  Its arithmetic is signed 18-bit,
  wider than the 16-bit common accumulator; derive a multiword program or
  explicitly price retention of the existing fold service.  Finally, the
  652/1,003 sample clock report must be regenerated from executable
  instructions, not Python-only wait metadata.
- **Global/public ownership:** the single adapter must preserve the exact
  ordering `service response < tick/sample boundaries < action effects <
  pre_tick queue/fade < CPU writes < fade_len/mask tail`.  This covers the
  observed same-edge winners: T_NL over a pending response clear, pre_tick over
  S_IDLE's tick clear, CPU trigger over T_FL, CPU music stop over ML_L3,
  VOICE_STOP over the tick-boundary pending-stop clear, and V_ST completion
  after boundary bank logic.  Do not implement these as competing always_ff
  writers.
- **Observable commit inventory:** state writes, ARAM and service requests,
  `dry_valid`, `spar_bank`, `bank_ready`, `playing`, `trig_req`, `sfx_id`,
  `aud_row`, `mus_playing`, `mus_pat`, `mus_mask`, `fade_len`, `clr_tog` and
  final `pcm` publication each need one named owner and a transaction proof.
- **EBR accounting:** G-D's two program blocks are only a free exchange when
  atomic composition retires both legacy control blocks.  The walker fdiv5
  block and sequencer constants block are semantic dependencies, not control
  blocks that may be counted twice.  Recount named EBR owners at composition;
  reject any claim above 15 total or any unexplained retained legacy block.
- **Bounded lowering order:** H-A derives the authoritative addressed-state
  and service-dependency manifests for both owners, including real condition
  indices, explicit waits, fold addresses and global priority.  H-B proves
  owner-zero persistent read/write transactions without a working-register
  mirror.  H-C lowers the fixed-latency `psg_wave`/ARAM cadence.  H-D lowers
  noise/detune/multiply/divide/ring and the complete signed fold.  H-E lowers
  remaining owner-one trigger/note/effect/slide/publication/music flow and the
  single public-state arbiter.  Only then may H-F perform one atomic full-mode
  composition and retire both legacy controllers.
- **Per-stage gates:** write the row before implementation; run executable
  image/capacity, formula and synchronous transaction proofs; controller,
  datapath and affected-service tests; full/PREVIEW lint; strict OpenSpec; and
  isolated HX8K mapped/floor/placed/routed timing.  Commit an accepted result
  or a reverted-source rejection before the next family.  H-F additionally
  requires the full structural test, exact sample/tick schedule, all 59 frozen
  renders, P.1/P.2, `/4`--`/6` clocks, `click-v1`, five-entry Celeste fidelity
  and smoke, whole-PSG seed-1/multi-seed area, routing and both-clock timing.
- **Stop rule:** reject a family before generic integration if it introduces a
  general source/destination index, a flat request/result bundle, arithmetic
  outside the common/service chain, non-addressed working state, an
  unaccounted EBR, or cannot prove one owner for every overlapping public
  write.  Stop the 6k path if the complete replacement floor exceeds 3,431;
  continue toward 5.5k/5k only while it remains below 2,931/2,431 or a measured
  later retirement has a concrete bound that closes the gap.
- **Repeat only if:** persistent word layout, service latency/ownership,
  external NBA priority, program capacity, the `e099e52` address behavior or
  measured subtree ownership changes.  Do not retry R.83's scalar service,
  R.84F's parallel macros, G-B's selected field arithmetic, G-C's one-bank
  program or a partial pph/sst consumer migration.

### R.84H-A - Make the complete service graph executable before RTL

- **Hypothesis:** both owner programs can name every remaining action family,
  fixed service wait, persistent/scratch address, fold edge, condition bit and
  public-write priority without rebuilding `pph`, `sst`, a flat request bundle
  or a register-resident fold stack.  Owner zero may spend its otherwise idle
  bank on an unrolled literal schedule; owner one retains the exact G-F
  advance image while the remaining semantic sites stay visibly classified.
- **Scope:** `tools/psg_exec_model.py`, its generated 512-word
  `rtl/psg_exec.hex`, this ledger, and isolated executor proof/synthesis only.
  No generic PSG RTL, sample action decoder, service adapter, owner-one
  completion logic or public-state writer is introduced by this iteration.
- **Rejected first draft:** the first executable spelling used 212 owner-zero
  words and reported 702/1,003 clocks, but it moved the seven old conservative
  CAP wait credits behind W84.  That preserved a total clock count while
  collapsing the accepted W6--W15, W15--W26, W27--W40, W40--W51 and
  W75--W84 service dependencies.  A service graph cannot consume or relaunch
  multiplier/wave results early merely because its total visit length is
  conservative.  The draft was corrected before generation or commit; do not
  restore the 212/702 result.
- **Accepted owner-zero program:** the final bank uses **222/256 words** and
  executes in **782/1,003 clocks**, leaving 34 words and 221 clocks.  Its 61
  fixed action codes are 18 addressed loads, 16 named noise/CAP service
  edges, 18 addressed stores and nine fold actions.  Eighty-one stored HOLD
  words encode the two four-clock noise gaps, the exact seventeen holes in
  the accepted W0..W84 cadence and eight post-launch clocks for each of seven
  worst-case fold nodes.  The model imports `gen_psg_ctrl.py` and reads the
  live PNZ constants from `psg_walk.sv`, then checks every visit against those
  source facts; waits are no longer Python-only metadata.
- **Fold and condition result:** leaves and intermediates occupy per-slot
  scratch words 48/49 as signed 18-bit low/high pairs.  All 262,144 signed
  18-bit values round-trip through that representation.  The literal sequence
  proves the exact non-associative tree `(0,1)->0`, `(2,3)->2`, `(0,2)->0`,
  `(4,5)->4`, `(6,7)->6`, `(4,6)->4`, `(0,4)->0`; every read and write is
  checked against its slot and word.  Owner-zero slot wrap is external
  condition 8, common Z/N/C/V remain 0..3, hard-zero 4..7 remain unused, and
  owner-one's external advance predicates remain 8..11 under owner-qualified
  condition selection.
- **Owner-one and public ownership result:** the image retains G-F's exact
  226/256 owner-one bank byte-for-byte (SHA-1
  `21e4d10952a56460be37cf76de2803b31389e085`).  The executable inventory keeps
  eighteen proved movement transactions, four address-only P_W sites and 56
  visibly placeholder sites split as 19 trigger/note, 27 effect/service and
  ten music-flow actions.  The legacy source-order audit pins the single future
  public adapter as `service < boundary < action < pre_tick < CPU < tail` and
  inventories dry/bank/play/trigger/music/fade/clear commits without claiming
  that adapter exists yet.
- **Gates and physical result:** the model passes the exact 19,728,640
  decomposed advance cases, 131,087 synchronous advance transactions, the
  signed-18/fold/address/cadence/condition/priority checks and byte-identical
  image freshness.  Controller, 327,680-pair datapath, movement and 11-path
  production-image Icarus tests pass; isolated target plus generic full and
  PREVIEW Verilator lint pass.  Fresh canonical HX8K synthesis is unchanged
  at **530 LUT4s / 23 carries / 34 flops / 26 unpackable / two EBRs / 556-cell
  floor**; seed-1 router2 places **561 LCs** and routes at **63.58 MHz** against
  28.125 MHz.  Strict OpenSpec validation passes.
- **Decision:** accept H-A as the generated control/dependency foundation.
  It fixes the three R.84H model defects and proves program capacity, but it
  implements no sample semantics and retires no generic controller.  Do not
  cite 782 clocks as a whole-PSG schedule or 561 LCs as a PSG area result.
- **Repeat only if:** the accepted NZ/CAP schedule, state-word layout, fold
  representation/order, condition ownership, public NBA priority or either
  program manifest changes.
- **R.84H-B next permitted hypothesis:** lower the complete owner-zero
  persistent read/write transaction family through fixed addressed actions
  and a real synchronous state-memory harness, re-reading words at use and
  storing only the cross-service lifetimes already named by H-A.  First prove
  all eight slots, both parameter banks, repeated words 14/15, leaf words
  48/49 and no hidden record mirror.  Price the fixed decoder before adding
  wave, ARAM, multiplier, detune or fold arithmetic semantics.

### R.84H-B - Prove the owner-zero state transaction boundary

- **Hypothesis:** H-A's literal program already carries every fixed slot/word
  address; the only owner-zero address logic needed before service semantics
  is selecting active sounding words 24..27 or 28..31 from `spar_bank`.
  Execute the production image against one real synchronous 8x64x16 memory,
  observe each returned word on its following consume action and inject
  synthetic semantic write data only through the controller's existing
  single `state_wd_i` boundary.  This should prove the complete memory
  transaction graph without copying the oscillator record into another
  register or scratch file and without selecting any service result.
- **Scope:** `rtl/psg_execmove.sv`, a new owner-zero production-image
  synchronous transaction test, and the controller/target plus existing
  owner-one harnesses only as needed to expose and prove the state-memory
  read enable.  `tools/psg_exec_model.py` and the 512-word image remain
  unchanged.  Generic `psg.sv`, `psg_state_mem`, `psg_walk`, `psg_seq`,
  sample-service semantics, fold arithmetic and public-state arbitration
  remain unchanged.
- **Grounded transaction count:** one complete bank run is the accepted 782
  clocks and issues exactly **172 reads / 158 writes**: 144 persistent reads
  across eight slots plus 28 literal fold reads; 128 persistent oscillator
  writes, sixteen leaf writes to words 48/49 and fourteen fold-result writes.
  Each slot writes words 10..23, then deliberately writes 15 and 14 again,
  then writes leaf low/high 48/49.  The seven fold nodes read four word pairs
  and write two words each at their literal source/destination slots.
- **Required proof:** run the full owner-zero image for both `spar_bank`
  polarities from distinct data in every slot and word.  Check the exact
  issue address, one-cycle returned `state_q`, consuming action, write slot,
  write word and injected data for all transactions; distinguish every slot;
  prove active parameter reads select 24..27 or 28..31; prove both occurrences
  and final overwrite order of words 14/15; prove leaf and intermediate word
  48/49 traffic follows H-A's seven-node tree; and prove hold freezes the
  program and causes no memory transaction.  The generated image must remain
  byte-identical.
- **Physical gate:** the retained decoder adds no sequential state, carry,
  EBR, general register index, action-selected data source or variable
  arithmetic.  Against H-A's 530 LUT4 / 23 carry / 34 flop / 26 unpackable /
  two-EBR / 556-floor / 561-placed baseline, reject if total carries, flops or
  EBRs grow, if the floor exceeds **580 cells**, if seed-1 placement exceeds
  **585 LCs**, or if routed timing falls below 28.125 MHz.  Passing proves an
  address/data transaction boundary only; it is not sample semantics,
  schedule equivalence or a generic-PSG area result.
- **Rejected read-enable drafts:** the first transaction harness privately
  clock-enabled its test memory and therefore concealed that the committed
  generic state memory updates its output unconditionally during controller
  hold.  Adding `state_re` only for `OP_READ` closed that owner-zero test but
  broke the accepted G-F owner-one production image: WRITE and EXEC actions
  deliberately prime the synchronous operand stream, including P_W3, K_ROT,
  V_ST0..3 and normalized whole-word operations.  Neither draft is a valid
  state-EBR contract.
- **Retained read-enable contract:** `state_re = active && !hold`.  Every
  executing instruction edge may prime `state_q` for its successor, exactly
  as G-F's synchronous model already does; external hold freezes the output
  register with PC, IR and slot.  The owner-zero harness counts only
  `OP_READ` instructions as semantic reads while exercising this wider
  physical clock enable.  Atomic H-F integration must connect `state_re` to
  the real state EBR output-register enable; H-B does not claim that the
  currently unchanged generic `psg_state_mem.sv` already implements it.
- **Functional result:** controller, movement, all 327,680 common-datapath
  pairs and the eleven-path owner-one production-image harness pass.  The new
  owner-zero harness executes both parameter banks and proves exactly 782
  active instructions per run: 172 READ, 158 WRITE, 406 EXEC, 29 SLOT, eight
  JUMP, eight BRANCH and one DONE.  It checks every read issue/next-action
  consume, all eight slots, active words 24..27 or 28..31, the late overwrites
  of words 15/14, leaf/intermediate words 48/49, all 158 injected writes and a
  three-clock held PC5 with stable `state_q` and no transaction.  The model
  still passes 19,728,640 decomposed cases and 131,087 owner-one synchronous
  transactions, and the generated image remains byte-identical.  Isolated,
  full and PREVIEW lint plus strict OpenSpec validation pass.
- **Physical result and decision:** canonical Yosys maps **528 LUT4s / 23
  carries / 34 flops / 26 unpackable / two EBRs / 554-cell floor**; seed-1
  router2 places **559 LCs** and routes at **68.24 MHz** against 28.125 MHz.
  Relative to H-A this is -2 LUT4s, unchanged carry/flop/unpackable/EBR, -2
  floor cells and -2 placed cells.  The small decrease is an abc9 cover
  reshuffle, not a negative intrinsic cost assigned to the decoder.  Accept
  H-B as the address/data transport boundary under the original 580-floor /
  585-placed gate.  It proves no waveform, ARAM, noise, detune, multiply,
  divide, fold or public-state behavior and no generic-PSG schedule, render or
  area equivalence.
- **Repeat only if:** the per-slot state layout, active-bank convention,
  synchronous read latency, H-A literal fold graph or controller write-data
  boundary changes.  Do not satisfy this row with a second record image,
  owner-zero working-register bundle, action-selected service mux or inferred
  transaction trace that does not execute the production image.
- **R.84H-C next permitted hypothesis:** lower the fixed-latency `psg_wave`
  and adjacent ARAM issue/consume cadence onto the accepted addressed stream.
  Preserve service-owned request state, use explicit stored waits, and do not
  open noise/detune/multiply/divide/fold semantics or generic composition in
  the same iteration.

### R.84H-C - Stream fixed-latency wave and ARAM service transactions

- **Hypothesis:** H-B's physical read enable makes `state_q` itself the narrow
  waveform context stream.  Existing common-HOLD instructions can prefetch
  current phase word 10; W0 can prefetch current phase2 word 12; and W1 can
  prefetch old-phase word 16.  Extract `psg_wave`'s existing 21-bit first-stage
  contract and drive those three phase values plus one retained old-q value
  directly through its fixed W0--W3 roles.  The 512-word image, 782 owner-zero
  clocks and 172-read/158-write semantic state trace should remain exact,
  without a scratch mirror, phase queue, general context index, result register
  or new arithmetic.
- **Pre-RTL refinement:** the first docs-only H-C bound in `c2d3698` assumed
  all four phase views had to survive from the initial LOAD stream and proposed
  an 86-bit holder.  A final independent manifest audit found the addressed
  prefetch above before any RTL was written.  The 86-bit direction is therefore
  superseded, not implemented: holding four contexts would duplicate
  information already carried by the synchronous state output.
- **Information bound:** actions 0x02/0x08 assemble the sixteen-bit old-q from
  oscillator words 11 and 17.  Fixed LOAD projections capture only the live
  controls `{snd_id, wt, wave, det, buzz}` and old controls
  `{wave, mode, alternate}`, another sixteen bits, from words 14/22/25/26.
  The current and secondary ARAM adjacent requests retain only their six-bit
  phase index: the low ten phase bits can affect neither address, and q16 is
  transformed before its index is captured.  The exact adapter bound is thus
  **38 flops**.  The first RTL lint made this algebra visible by reporting
  `phase_hold[9:0]` unused; no synthesis result or committed RTL used the
  earlier 48-bit estimate.  The adapter does not capture current phase,
  phase2, old phase, either increment, last-context restart fields or `dq17`;
  restart/noise/detune updates remain H-D.
- **Addressed issue stream:** while owner zero is active, common-HOLD actions
  override the physical read address to word 10, so the final pre-W0 HOLD
  primes current phase without adding a semantic READ.  W0 overrides the next
  address to word 12 and W1 to word 16.  W0 therefore issues current primary
  from `state_q`; W1 issues current secondary from the q16 transform of
  `state_q`; W2 issues old primary from `state_q`; and W3 issues old secondary
  from retained old-q.  This adds no instruction, state write or counted
  semantic read.  Owner one and every H-B transaction remain unchanged.
- **Exact cadence:** for a built-in slot, W0--W3 issue the four direct 21-bit
  `{phase, wave, alternate, secondary}` contexts and W2--W5 consume them two
  active action edges later.  Inactive built-ins still execute all four roles,
  as the legacy old-arm/leaf schedule does.  Wavetable slots do not need a
  built-in `z_eval` request; their q16 phase transform remains narrow logic.
  When wavetable and `play_bits[slot]` are both true, W0--W3 issue exactly four
  ARAM reads and W1--W4 consume them one active edge later.  The address is
  `256 + 68*snd_id + phase[15:10]`, with six-bit `+1` wrap for each adjacent
  point.  Amplitude does not gate the requests, and wavetable implies the two
  secondary requests are active.
- **Core boundary:** factor the retained waveform pipeline around its existing
  direct 21-bit first-stage context and one step enable.  A behavior-identical
  legacy wrapper preserves the current parallel interface for generic and
  PREVIEW elaborations.  H-C selects only the four fixed roles; it introduces
  no variable role index or result mux.  The reciprocal EBR and both following
  registered stages remain the same service rather than being copied.
- **Hold contract:** stored common-HOLD instructions are elapsed service clocks
  and continue to execute.  An external executor hold instead freezes the 38
  adapter bits, all waveform context/reciprocal/second-stage registers, ARAM
  `seq_q` and the synthesis-borrow replay bit together with PC/IR/slot and
  `state_q`.  Gating request strobes alone is invalid: the current waveform
  pipeline shifts unconditionally, and current ARAM replay can overwrite W0's
  borrowed byte while a held W1 waits to consume it.  The direct wave core
  advances through W4 to drain W3; ARAM's W4 edge consumes the fourth byte and
  performs the final sequencer replay.
- **Scope:** `rtl/psg_wave.sv` for the direct enabled core plus unchanged legacy
  wrapper, `rtl/psg_aram.sv` for freezeable synthesis-borrow state plus
  unchanged legacy behavior, a new fixed `psg_execwave` adapter, direct-core
  and production-image service tests, an isolated target and this ledger.
  `psg_exec_model.py`, `psg_exec.hex`, controller/datapath/movement RTL,
  generic `psg.sv`/`psg_walk`/`psg_seq`, state-memory CE integration,
  noise/detune/multiply/divide/fold semantics, sample result storage and public
  state remain unchanged.
- **Required proof:** keep both 256-word banks byte-identical, owner zero at
  222/256 words and 782/1,003 clocks, and its exact instruction histogram and
  172/158 semantic state trace.  Prove all 2,097,152 waveform contexts through
  direct-core versus legacy-wrapper equivalence.  Execute both parameter banks
  and all eight slots from the production image; cover built-in/wavetable,
  play/inactive, secondary on/off, amplitude zero/nonzero, signed ARAM bytes,
  adjacent-index wrap, W0--W5 tags and replay restoration.  Inject external
  holds at every W0--W5/replay boundary and prove an identical resumed trace.
  Re-run H-B owner-zero transport, G-F owner-one transactions, controller,
  datapath and movement tests, full/PREVIEW lint and strict OpenSpec.
- **Physical gate:** H-B's address-state executor is 528 LUT4 / 23 carries /
  34 flops / 26 unpackable / two EBRs / 554-floor / 559-placed.  The corrected
  generic `u_wave` is retained fixed-base hardware at 711 LUT4 / 290 carries /
  97 flops / 47 unpackable / one EBR / 758-floor; `u_aram` likewise remains a
  fixed-base nine-EBR service.  Report (A) executor plus adapter excluding the
  retained cores and (B) the same wrapper with retained services against an
  identically wrapped no-adapter baseline.  Row A must retain exactly 23
  executor carries, two executor EBRs and 34 controller/datapath flops plus the
  exact 38 adapter flops.  Reject any adapter arithmetic, memory, result state
  or scratch traffic, any floor above **810 cells**, placement above **834
  LCs**, or routed timing below 28.125 MHz.  That ceiling leaves 2,621 floor
  cells of the corrected 3,431-cell 6k replacement budget for H-D/H-E.
- **Claim boundary:** passing H-C proves addressed LOAD/control projections,
  fixed waveform/ARAM issue and consume latency, and hold/replay correctness.
  It does not prove CAP_W0 restart substitution or CAP_W0/W1 phase updates;
  H-D must supply those values at the same named issue boundary.  No generic
  sample, render or whole-PSG area equivalence may be claimed.
- **Repeat only if:** the owner-zero LOAD order, physical read-enable contract,
  W0--W5 cadence, persistent field layout, waveform latency, ARAM replay or
  restart ownership changes.  Do not replace the 38-bit bound with captured
  phase arrays, a scratch context queue, variable role selector or second wave
  implementation.
- **Result:** accepted as the fixed-latency addressed-service boundary.  The
  direct `psg_wave_ctx` core retains the reciprocal EBR and all three enabled
  pipeline boundaries; the public `psg_wave` wrapper remains behavior-identical
  in full and PREVIEW elaborations.  `psg_aram_core` freezes the synthesis-read
  output and pending sequencer replay together, while the public `psg_aram`
  wrapper ties freeze low and preserves the accepted generic behavior.  The
  executor adapter uses words 10, 12 and 16 as the live phase stream and owns
  exactly **38 flops**: 16 old-q, 16 fixed controls and one six-bit ARAM index.
  It owns no result register, scratch write, new instruction, image change or
  generic composition.
- **Production transaction proof:** both parameter banks and all eight slots
  execute the unchanged 222-word owner-zero image at exactly **782 active
  edges, 172 semantic reads and 158 writes** with the accepted instruction
  histogram.  Built-in and wavetable cases cover playing/inactive slots,
  amplitude zero/nonzero, secondary on/off, signed ARAM bytes and six-bit
  adjacent index 63-to-0 wrap.  External hold is injected independently at
  every W0--W5 role for both service families.  Every hold freezes the complete
  38-bit adapter context, PC/IR/slot, `state_q`, waveform pipeline, ARAM byte
  and replay bit; every built-in W2--W5 take is checked against the exact
  W0--W3 context result, and every ARAM take/replay resumes byte-identically.
- **Formula and regression gates:** the direct core matches the legacy full
  and PREVIEW wrappers over all **2,097,152** phase/wave/alternate/secondary
  contexts plus old-context and hold/resume cases.  The ARAM core passes
  synthesis-borrow hold/replay while the independent CPU port writes.  H-B
  passes both banks at 172 reads/158 writes; G-F passes all eleven production
  transaction paths; the common datapath passes 327,680 arithmetic pairs;
  controller and movement tests pass.  The executable model remains at
  **19,728,640 semantic cases and 131,087 synchronous transactions**, and the
  generated 512-word image is byte-identical.  Executor, paired-target,
  production-test, ARAM-test, full and PREVIEW Verilator lint pass, as does
  strict OpenSpec validation.
- **Physical row A:** final-name canonical Yosys maps **582 LUT4s / 23 carries
  / 72 flops / 60 unpackable / two EBRs / 642-cell floor**.  The flops are
  exactly H-B's 34 controller/datapath bits plus the 38 adapter bits.  Seed-1
  router2 places **647 LCs** and routes at **67.72 MHz** against 28.125 MHz,
  clearing the 810-floor/834-placed gate by 168/187 cells.
- **Physical row B:** the paired wrapper marks every adapter stream/tag as
  retained so issue/take-only decode cannot be pruned.  Its no-adapter baseline
  is **1,404 LUT4 / 384 carries / 183 flops / 128 unpackable / 12 EBR /
  1,532-floor / 1,584 placed / 46.42 MHz**; H-C is **1,526 / 384 / 221 / 140 /
  12 / 1,666 / 1,718 / 46.89 MHz**.  The complete retained-service delta is
  therefore **+122 LUT4, +0 carries, exactly +38 flops, +12 unpackable, +0 EBR,
  +134 floor and +134 placed LCs**.  Reproducible final artifacts are under
  `build/r84hc/final/`.
- **Decision and claim boundary:** retain H-C.  It proves addressed LOAD/control
  projections, fixed waveform/ARAM issue-to-consume association and complete
  external-hold recovery below the physical ceiling.  It does not prove CAP_W0
  restart substitution, CAP_W0/W1 phase updates, noise/detune/multiply/divide,
  fold/public commits, generic sample schedule, renders or whole-PSG area.
- **R.84H-D next permitted hypothesis:** lower the remaining owner-zero
  noise/detune/multiply/divide/ring services and the literal signed fold onto
  the H-A dependency graph without changing H-C's W0--W5 issue boundary.  First
  derive each service-owned request/result lifetime, ready wait, scratch word
  and restart/phase-update value in the model; price an isolated complete
  service wrapper before any generic composition.  Do not add a flat request
  bundle, general result register, second arithmetic chain or partial generic
  handoff.

### R.84H-D - Compile the complete sample service graph into stored waits

- **Hypothesis:** H-A already stores every service edge and elapsed clock, and
  every EXEC/HOLD word already has an independent six-bit `state_word` field.
  Compile the remaining sample graph into those existing fields: ordinary
  service actions name issue/consume edges, while HOLD words name physical
  operand prefetches or fixed ring/fold microsteps.  One 70-bit transient pool
  can cover the mutually dead waveform/multiply values and then be reused by
  the post-walk fold.  This should lower the complete owner-zero dataflow
  without another opcode, PC, fold counter, flat request/result bundle,
  scratch file or arithmetic chain.
- **Grounded instruction result:** all 81 current HOLD words encode action
  `0x70` with word zero.  `psg_execctl` already exposes `state_word` and clocks
  the state EBR on every active instruction.  Regenerate the owner-zero image
  so the final pre-W0 HOLD reads word 10, W0 and W1 retain the word-12 and
  word-16 primes, the four W40--W51 holds name the ring read/capture sequence,
  and each fold node's eight holds name steps one through eight.  Other HOLD
  fields may directly prefetch a persistent operand for the following fixed
  action.  Remove H-C's blanket HOLD-to-word-10 override; retain no previous-PC
  or previous-word tag register.
- **Image claim:** the generated bank remains 222/256 words, 782/1,003 active
  clocks, 172 semantic reads, 158 writes and the same action histogram, but it
  is intentionally no longer byte-identical to H-C because stored HOLD operand
  fields become meaningful.  Owner one must remain byte-identical.  Every
  changed word, physical read and following consumer must be emitted and
  checked by the executable model before RTL.
- **Exact service schedule:** action 0x20 at W-10 launches the old-noise
  multiply and live-DQ recurrence; both terminate on action 0x21 at W-5, which
  consumes the old-noise result, captures live DQ and chains the old-DQ
  request.  The four following HOLDs end at W0, where the live-noise result and
  old-DQ terminal value are ready.  W0--W6 retain the accepted wave/ARAM
  issue/consume cadence and consume old/live DQ at W5/W6.  W4->W15,
  W15->W26/W27, W27->W40, W40->W51 and W75->W84 are the existing fixed
  multiplier transactions; no request may depend on a dynamic ready branch.
- **Ring schedule:** in REVERB builds the W40--W51 gap names current-tap read,
  old-tap read plus current capture, old capture and one drain edge.  W75 sees
  both captured values, and the existing pre-close edge writes filtered PCM
  only for a playing slot.  `ring_rp` advances exactly once per sample.  The
  HX8K target keeps REVERB disabled, but generic semantic proof must cover both
  elaborations without charging nonexistent ring storage to the HX8K row.
- **Critical W0--W3 substitution law:** W0 issues the pre-update primary phase.
  W1 must issue the post-W0 secondary phase, including the amplitude-zero
  clear.  W2 must issue the restart/noise-selected old primary after W0 and
  the possible W1 old-noise advance.  W3 must issue the restart-selected old
  secondary, not H-C's stale retained old-q.  These are explicit H-D inputs to
  the accepted direct wave/ARAM boundary; duplicating or retiming the waveform
  service is forbidden.
- **Restart and phase priority:** at W0, restart snapshots the live tuple into
  the old tuple; an amplitude-zero restart clears current phase and phase2;
  the noise/filter step may then replace snapped old phase with the selected
  noise seed.  W1 applies old-noise advance, W5 applies old DQ only when old
  gain is nonzero and old noise is off, and W6 applies live DQ only while the
  current slot is playing with nonzero amplitude.  The model must reproduce
  this source/NBA order rather than algebraically commuting the writes.
- **Transient information bound:** use four shared fields A18, B18, N17 and
  O17, exactly **70 bits**, as the candidate sample pool.  Wavetable A/B pack
  `{fraction10,signed-byte8}` then hold their reachable signed-15 interpolated
  results.  N/O successively hold DQ/noise bridges, gain limbs and current/old
  arms; dead A bits hold sign/audible flags, and W84 may overwrite a dead arm
  with the final filtered value.  This is a hypothesis to prove in the model,
  not permission to add a general result register or action-selected mux.
- **Fold reuse bound:** after all eight leaves are committed to words 48/49,
  every sample transient is dead.  The signed fold therefore reuses the same
  pool.  Its simultaneous minimum is A18 plus B-low16 plus the seven-bit
  `fdiv5_q`; threshold class bits reuse dead B bits, and HOLD step tags replace
  `fmc`.  The literal seven-node tree and word-48/49 signed representation stay
  exact.  Do not allocate another stack, counter or EBR, and do not confuse
  this owner-zero `fdiv5` table with owner-one `psg_divsvc`.
- **Scratch boundary:** words 48/49 remain the only owner-zero scratch, for
  leaves and fold intermediates.  Words 34..47 and 50..63 remain unallocated
  unless the executable lifetime proof demonstrates a value that cannot fit
  the 70-bit pool and a separate measured variant justifies the spill.  A
  convenience mirror of the persistent oscillator record is not such proof.
- **Hold and readiness contract:** stored HOLD instructions are elapsed active
  service clocks and continue to advance services.  External executor hold
  freezes PC/IR/state output, the 70-bit pool, H-C wave/ARAM state, DQ, slow and
  fast multiplier handshakes, ring captures and fold state together.  Prove
  the DQ terminal-edge chained request, all multiplier consume gaps and fold
  worst-case padding explicitly; an assertion-only dropped request is not a
  transaction proof.
- **Fold formula domains:** keep the 262,144 signed-18 word-pair encodings
  distinct from arithmetic coverage.  The independent model must cover all
  131,071 signed-int16 sums and all 40,961 reachable `/5` excess values, plus
  exact threshold, rounding, sign and literal-tree order.  The final action
  writes slot-zero word48/49, publishes `dry16`, pulses `dry_valid` once and
  then reaches DONE.
- **Scope:** first extend `psg_exec_model.py` and regenerate `psg_exec.hex` with
  the exact prefetch/tag manifest and value/lifetime model.  Only after that
  passes, add one bounded owner-zero sample adapter, direct service tests and
  isolated/paired synthesis targets.  Retain `psg_wave`, `psg_aram`,
  `psg_dqsvc`, `psg_mulmp` and one `fdiv5` EBR as services.  Generic `psg.sv`,
  `psg_walk`, `psg_seq`, public arbitration and state-memory integration remain
  outside H-D.
- **Required semantic proof:** execute both banks and all slots from the
  production image; check every physical prefetch, semantic read/write,
  service request/result association, persistent word 10..23 writeback,
  leaf/fold word 48/49 value and external hold boundary.  Prove built-in and
  wavetable paths, playing/hidden/inactive slots, amplitude zero/nonzero,
  restart/no-restart, noise/buzz/detune/dampen modes, transition counts and
  optional ring.  Re-run H-C wave/ARAM, H-B transport, G-F owner-one,
  controller/datapath/movement, full/PREVIEW lint and strict OpenSpec.  H-D
  still makes no generic schedule, render or whole-PSG equivalence claim.
- **Physical lower bound:** H-C row A is 642 floor cells.  The retained DQ
  service is 133 floor cells and the literal fold island is 295 LUT4s plus up
  to 67 flops, one EBR and a conservative 295--362 floor cells.  H-C plus these
  disjoint irreducibles is already **1,070--1,137 floor cells** before request,
  substitution, ring and writeback logic.  A credible accepted cumulative
  H-C+H-D result should be **1,800--1,900 floor cells**; reject at or above
  **2,200 floor or placed cells**, or below 28.125 MHz routed timing.
- **Capacity and EBR law:** the corrected fixed placed base leaves replacement
  ceilings 4,431/3,431/2,931/2,431 cells for the 7k/6k/5.5k/5k ladder.  H-C
  leaves H-D+H-E 3,789/2,789/2,289/1,789 cells respectively.  The paired H-D
  build has program2 + ARAM9 + wave1 + fold1 = **13 EBRs**; adding the two-EBR
  state store reaches the final **15-EBR ceiling**.  H-D may add no EBR, and
  H-E must re-home the legacy sequencer constants rather than retain another.
- **Physical proof rows:** report (A) H-C executor/adapter plus the complete
  owner-zero adapter, DQ and fold with retained external services abstracted;
  and (B) identical kept wave/ARAM/multiplier cores with and without H-D while
  retaining every request/result stream.  Credit none of the multiplier's
  approximately 590-LUT request-input cone until row B measures its removal.
  Save canonical mapped, placed, routed and timing artifacts before deciding.
- **Stored-wait foundation result:** the generator now emits the final pre-W0
  word-10 prime, literal W0/W1 word-12/16 primes, four W40--W51 ring tags and
  steps 1..8 for all seven fold nodes.  Exactly 61 of 81 HOLD words are
  nonzero and 63 owner-zero image words change; owner zero remains 222 words,
  782 clocks, 172 semantic reads and 158 writes, while the complete owner-one
  bank remains byte-identical at SHA-1
  `21e4d10952a56460be37cf76de2803b31389e085`.  The model checks every stored
  tag and rejects any other nonzero HOLD field.  Controller, movement,
  eleven-path owner-one, two-bank owner-zero transport and production
  wave/ARAM tests pass; isolated, full and PREVIEW lint plus strict OpenSpec
  pass.  Accept this as image/address foundation only: the 70-bit value model,
  sample service semantics, new RTL and physical result remain unproved.
- **Transient/fold model result:** the executable model now runs separate
  built-in and wavetable lifetimes through A18+B18+N17+O17.  It checks every
  producer/consumer and rejects an overwrite, width overflow or live value at
  leaf commit.  Wavetable fraction/base packing is exactly eighteen bits and
  its convex interpolation range is -16,384..16,256, so the replacement
  signed-15 value fits before the fields are reused.  After leaf commit the
  same pool executes a counter-free fold.  Independently, all 131,071
  signed-int16 pair sums match the shipped reciprocal form, and all 40,961
  reachable excesses match the base-256 `fdiv5` lowering with address <=414
  and seven-bit table output.  Accept the **70-bit no-spill bound** and fold
  formula foundation; restart/noise/phase value transactions, semantic RTL
  and physical cost remain the next unproved H-D boundary.
- **Phase-substitution model result:** a second independent addressed-state
  form now matches the legacy source/NBA sequence over **73,728 W0--W6
  cases** spanning every reachable play/amplitude/wavetable/restart/old-noise/
  old-gain control combination, all waves and detune modes, and signed/wrapping
  numeric boundaries.  Direct convictions prove W0 observes pre-update phase,
  W1 observes an amplitude-zero restart clear, W2 observes the later noise
  seed/old-noise update, W3 observes restart old-q, W5 applies old DQ only to
  a non-noise built-in arm, and W6 applies live DQ only while running.  Accept
  this substitution/writeback law; multiplier/noise/blend value semantics,
  semantic RTL and physical cost remain unproved.
- **Sample-arithmetic model result:** **4,784,128** bounded formula cases now
  prove the seven exact DQ coefficients, radix-4 positional reconstruction,
  signed noise-product floor correction with maximum step 33,324, both noise
  scale constants, amplitude boost and gain formation, and the comb, blend
  and dampen truncation-toward-zero laws.  The independent retained-service
  gates also pass all 524,288 DQ formula cases, 57,344 chained DQ transactions,
  every legal radix-4 multiplier landing, all 131,071 signed-int16 fold sums
  and all 40,961 reachable `/5` excesses.  Accept this arithmetic foundation;
  production-image service transactions, semantic RTL and physical cost remain
  unproved.
- **Production-image semantic-model result:** the exact 222-word owner-zero
  image now executes through a synchronous 8x64x16 state model for **64
  complete runs / 512 slots / 50,048 active instructions** across both
  parameter banks and both ring elaborations.  **8,052** named DQ, noise,
  wave/ARAM, multiply, retained-result and ring transactions prove producer,
  readiness and consumer association; 64 injected freezes cover every one of
  the 34 service/fold/HOLD action classes without aging active-service time.
  Coverage assertions convict all eight waves, built-in/wavetable,
  playing/hidden/inactive, zero/nonzero amplitude, restart/no-restart,
  old-noise/buzz/noise, detune and dampen modes, transition counts 0/1/63/64
  and optional ring state.  Every run preserves 172 semantic reads, 158
  writes and all 782 active edges, matches an independent direct legacy
  source/NBA oracle at every persistent word 10..23 and scratch word 48/49,
  executes the literal seven-node tagged fold, and pulses one exact `dry_valid`
  with matching `dry16`.  The existing controller/datapath/movement,
  owner-one, owner-zero, production wave/ARAM, 2,097,152-context wave and ARAM
  replay RTL gates remain clean.  Accept the complete **model composition**;
  no new semantic RTL, physical result, generic schedule or render equivalence
  is claimed yet.
- **DQ hold-control RTL foundation:** `psg_dqsvc_core` now exposes one
  recurrence clock-enable, while the source-compatible `psg_dqsvc` wrapper
  ties it active for the untouched legacy walker.  The H-D adapter can
  therefore freeze all 27 recurrence bits and its `busy`/`done`/`start_ready`
  boundary on the same edge as PC, IR and state output without changing the
  generic interface or adding a request/result register.  The exhaustive gate
  still passes 57,344 coefficient/input transactions and the chained terminal
  request; a new gate freezes each of counts 5..1 for three clocks, including
  a presented terminal result, ignores an in-hold request, and resumes to the
  exact quotient.  Full and PREVIEW generic lint plus the complete production
  semantic model pass.  Accept this two-file service-freeze prerequisite only;
  the 70-bit adapter, multiplier freeze, semantic RTL and physical cost remain
  unproved.
- **Multi-pumped hold-control RTL foundation:** `psg_mulmp_core` now freezes
  the slow request payload/toggle, acknowledge synchronizer and sequencer pad
  together with the fast request synchronizer, radix recurrence and return
  toggle.  The source-compatible `psg_mulmp` wrapper ties freeze inactive, so
  the generic caller and its named consume-gap contract remain unchanged.  The
  retained 6,020-transaction radix-2/radix-4 comparison passes, as do all ten
  related-clock offsets.  A new gate freezes every radix-2 recurrence count
  8..1 and the completed-result acknowledge crossing for eighteen fast clocks;
  all payload, synchronizer, recurrence, toggle, result and busy state remains
  bit-stable and each transaction resumes to the exact positioned product.
  Full and PREVIEW generic lint and isolated iCE40 mapping pass.  Accept this
  two-file multiplier-freeze prerequisite only; semantic sample RTL and
  physical H-D rows remain unproved.
- **Explicit wave-context RTL foundation:** `psg_execwave_core` now accepts
  the exact explicit W1/W2/W3 phase values that H-D must form after its
  restart/noise/phase NBA sequence, while the source-compatible
  `psg_execwave` wrapper retains H-C's old-q lifetime and action-derived
  word-10/12/16 primes.  The core still owns only the fixed controls and one
  six-bit ARAM index; it adds no result register, scratch traffic, arithmetic
  service or generic caller edit.  A direct test covers all 24 built-in
  wave/mode contexts, explicit W0--W3 substitutions including 17-bit
  wrap/truncation, wavetable primary/adjacent indices, inactive suppression,
  external hold/resume and owner isolation.  The unchanged production-image
  test still passes both service families, all eight slots and W0--W5 holds;
  the 2,097,152-context waveform proof, ARAM replay, controller, 327,680-pair
  datapath, movement, both owner-zero banks, eleven owner-one paths and the
  complete semantic model remain clean.  Full/PREVIEW and executor lint plus
  strict OpenSpec pass.  The H-C row-A map is physically neutral at **578
  LUT4s / 23 carries / 72 flops / 60 unpackable / two EBRs / 638-cell floor**
  versus 582/23/72/60/two/642 before; the four-LUT decrease is an abc9 cover
  reshuffle, not an H-D area credit.  Accept this three-file explicit-context
  prerequisite only; the 70-bit semantic adapter, production-image RTL and
  routed H-D rows remain unproved.
- **Explicit old-tuple prerequisite hypothesis:** the semantic-composition
  audit found that the accepted core makes only W1/W2/W3 phase values
  explicit.  It still captures `old_wave`, `old_mode` and `old_alt` from the
  initial LOAD stream, while the legacy W0 restart edge replaces that exact
  tuple with `last_wave`, `last_mode` and `last_alt` before W2/W3 issue.  A
  semantic adapter cannot reproduce the source/NBA oracle through the current
  boundary.  Move those six context bits to explicit core inputs, retain the
  same six LOAD-captured bits in the H-C compatibility wrapper, and convict
  the direct core with contradictory LOAD versus explicit contexts.  Reject
  if the legacy production cadence, 38-bit H-C wrapper state, exhaustive wave
  proof, hold behavior or isolated H-C physical row changes materially.  This
  is a bounded interface prerequisite only; it adds no 70-bit adapter state,
  sample arithmetic, state write, generic caller or integration claim.
- **Explicit old-tuple prerequisite result:** accepted as the final waveform
  interface prerequisite.  The direct core now receives the exact six-bit
  old wave/mode/alternate tuple, while the source-compatible H-C wrapper keeps
  those same six LOAD-captured bits; contradictory direct-core LOAD values
  prove that only the explicit tuple controls W2/W3.  Direct 24-context
  W0--W3/ARAM/hold proof, unchanged production-image cadence, all 2,097,152
  waveform contexts, ARAM replay, 524,288 DQ formulae plus 57,344 chained
  transactions, 6,020 multi-pumped transactions, controller, 327,680-pair
  datapath, movement, both owner-zero banks, eleven owner-one paths, the full
  semantic model, full/PREVIEW/executor lint and strict OpenSpec pass.  Row A
  is **606 LUT4 / 23 carries / 72 flops / 60 unpackable / two EBRs / 666-cell
  floor / 671 placed / 72.87 MHz**, versus 582/23/72/60/two/642/647 before.
  The +24-cell movement is below the measured roughly 60-cell abc9 sensitivity
  band; no flop, EBR or service state was added.  Retain this correctness
  boundary without area credit.  The 70-bit adapter, semantic sample RTL and
  complete H-D physical rows remain unproved.
- **R.84H-D1 fixed-tail manifest result:** rejected by executable physical
  provenance, before semantic RTL.  The current sixteen persistent STORE
  actions do not consume the word they write: PC `0x3c` word-10 sees
  `state_q=word0`, PC `0x3d` word-11 sees word10, and the stream remains one
  destination behind through the duplicate word-15/14 commits.  The composed
  Python machine hid this by decoding fourteen oscillator plus four parameter
  words into a 202-bit `SampleRecord`, a 42-bit `SampleParams` and then a
  complete derived `SampleTrace`; every persistent write selected
  `trace.final_words`.  The 70-bit A/B/N/O proof remains valid for service and
  fold transients only and cannot justify that record-shaped mirror.  A fixed
  read-address repair is necessary but insufficient because final phase,
  phase2, old phase/q, noise/filter state and selected old context must still
  reach their commits.  Do not transcribe this machine into RTL.
- **R.84H-D2 next permitted hypothesis:** relocate the existing fourteen
  unique persistent commits onto fixed W0/W1/W5/W6/W84 or elapsed-HOLD edges
  where each packed word becomes final, and reuse the tail instruction slots
  as elapsed fixed actions.  Preserve exactly 222 program words, 782 active
  clocks, 172 semantic reads and 158 writes; add no hidden action-side write,
  record mirror, scratch word, EBR, result bundle or schedule edge.  First emit
  a numbered commit table with physical `state_q` source, packed merge inputs,
  write address and finalization edge, then execute it without `loaded_words`,
  `params_words`, `SampleTrace` or direct memory reads before any RTL.
- **R.84H-D2 commit-manifest foundation:** an alternate owner-zero image is
  now generated and checked in memory without replacing `psg_exec.hex`.
  Sixteen fixed STORE actions still appear exactly once: words 20/21/22/18/19
  commit in the pre-W0 waits after restart selection; word23 and word10 commit
  between W6 and W15; words 11/16/17/13 commit before W26, word12 before W40,
  words 14/15 immediately after W84, and the existing word15/14 repeats remain
  at the tail.  Twelve displaced unique tail writes become elapsed HOLDs, so
  the candidate remains exactly 222 words, 782 active clocks, 172 semantic
  reads and 158 writes.  Each action owns one literal write address while its
  instruction word primes the next fixed `state_q` source; there is no hidden
  action-side write or dynamic destination.  Forty owner-zero image
  words differ and owner one is untouched.  This is an address/lifetime
  candidate only: the accepted image remains byte-identical, and value
  construction without the Python record/trace oracle is still the next gate.
- **R.84H-D2A finalization-edge correction:** the first value-lifetime audit
  rejected keeping word23 and word10 until the W6-to-W15 waits: final noise
  state and phase then overlap the W2/W3 wave peak and recreate the storage
  gap D1 exposed.  The candidate now makes the existing W0 and W1 instructions
  `OP_WRITE` while retaining their CAP action codes; W0 commits word23 and W1
  commits word10 on the edges where those values become final.  The displaced
  later instructions revert to elapsed HOLDs.  No action code, write, clock,
  scratch word or state bit is added, and the 222/782/172/158 invariants plus
  every fixed `state_q` source still pass.  The corrected owner-zero candidate
  differs in 39 words and contains sixteen fixed write actions; W0/W1 are no
  longer literal STORE actions.  This corrected candidate, not the earlier
  W6-to-W15 placement, is the input to the no-mirror value executor.
- **R.84H-D2B active hypothesis:** execute the corrected candidate through a
  second physical-value machine whose action logic can observe only the real
  registered `state_q`, retained H-C wave context, A18+B18+N17+O17 and
  service-owned state/tokens.  The direct legacy evaluator may build expected
  memory outside this machine, but the machine itself may contain no decoded
  record/parameter object, word array, derived trace, direct state-memory read
  or persistent spill.  Assert the 38+70-bit boundary structurally in the
  model, execute both parameter banks, all slots and both ring elaborations,
  and compare every word10..23/48/49 commit plus `dry16`/`dry_valid` to the
  independent direct oracle.  Reject before image or RTL if any candidate
  write lacks a value composed solely from its fixed `state_q` source and
  bounded live state; accept only with unchanged 222/782/172/158 counts and
  explicit external-hold freeze coverage.
- **R.84H-D2B result and decision:** rejected before image or RTL.  In the
  worst built-in live-wave0/7 mode-2 plus selected-old-wave6/non-alt case, PC
  `0x1b` must retain independent DQ-live14, old-noise-step17, live-delta13,
  amplitude12, noise-lowpass16, updated-brown13, phase2-msb1 and
  old-noise-phase4, plus restart1 and clear1: **92 bits**.  This corrects
  the earlier 99-bit count: old-noise continuation makes `old_nz_r_on` true,
  while CAP_W5 applies old DQ only under `!old_nz_r_on`, so the thirteen-bit
  old-DQ operand/result and old-q carry are semantically dead on the named
  path.  The retained q13 noise-phase nibble remains live until q10 supplies
  current phase at W0.  The A18+B18+N17+O17 pool plus every H-C field dead on
  that path (ARAM index6 and
  built-in-unused sound ID3) provides at most **79 bits**, an unavoidable
  thirteen-bit shortfall.  Two later physical-stream holes independently convict
  the candidate: updated word20 reaches `state_q` on anonymous HOLD/word-zero
  PC `0x2f`, and filter-low word15 does the same on PC `0x39`; neither has a
  fixed consumer before the stream overwrites it.  The model asserts all
  three failures against the exact D2A candidate.  No accepted image or RTL
  changes.
- **R.84H-D2C next permitted hypothesis:** spend the two already-counted
  duplicate word14/15 tail writes as typed early transactions.  Move the
  word14 repeat to PC `0x1b` so updated brown plus selected old mode commit
  while q14 is present, then prefetch that stored word for W4; retain the
  post-W84 word14 final rewrite.  Move the word15 repeat to PC `0x39` so the
  filter-low q15 edge is typed without adding a write, action or state bit;
  retain the post-W84 word15 final rewrite.  Move the word20 prime to the last
  pre-W40 wait so unique CAP_W40 consumes q20.  Re-run the numbered q-source,
  operation-count and allocation proof before retrying the no-mirror machine.
- **R.84H-D2C stream-correction foundation:** a second alternate candidate
  spends exactly those existing writes.  PC `0x1b` now executes the fixed
  word14-repeat action while q14 is present, then CAP_W3 primes stored word14
  so CAP_W4 consumes the updated brown value.  PC `0x39` executes the fixed
  word15-repeat action while q15 is present; the final word14/15 actions after
  W84 remain unchanged.  The word20 prime moves from PC `0x2e` to the final
  pre-W40 wait at PC `0x30`, so CAP_W40 consumes q20 directly.  The worst
  worst old-noise payload falls from 92 to an exact **79 bits**, equal to the
  strongest fixed 79-bit pool/H-C overlay.  This is a necessary bound, not a
  complete allocation proof across all current/old/wavetable paths.  The
  candidate differs from the accepted owner-zero image
  in 42 words and retains 222 used words, 782 active clocks, 172 reads, 158
  writes and sixteen fixed write actions.  This is still an address/lifetime
  foundation only: the accepted image and RTL are untouched, and the complete
  no-mirror value executor remains the next gate.
- **R.84H-D2C audit result:** rejected as the direct no-mirror input.  PC
  `0x2d` primes updated word17, but moving the q20 prime changed PC `0x2e`
  back to anonymous HOLD/word-zero.  Final blend-count q17 therefore has no
  fixed consumer before the stream overwrites it.  This does not invalidate
  D2C's q14/q15/write reuse.  The later semantic-liveness correction removes
  the claimed allocation contradiction on the named old-noise path; D2C is
  rejected here only for the untyped q17 arrival.
- **R.84H-D2D typed-blend correction:** PC `0x2e` now stores HOLD/word17.  Its
  unique action/word pair consumes the q17 primed by PC `0x2d`, then performs
  a harmless redundant word17 prime; PC `0x30` still primes word20 and CAP_W40
  still consumes q20.  The alternate candidate differs in 43 owner-zero image
  words while preserving 222 used words, 782 active clocks, 172 reads, 158
  writes and the D2C fixed write set.  No accepted image or RTL changes.  This
  fixes the q17 provenance hole.  The corrected PC-`0x1c` bound is the input
  to D2E; no fixed-capacity contradiction remains.
- **R.84H-D2E initial PC-`0x1c` result (`ff0d12d`):** replaced the false
  path-insensitive "exact-fit" claim and proved the central semantic
  correction.  The four-bit old noise phase remains live until its equality
  operand arrives in q10 at W0, but old-noise continuation and the CAP_W5
  old-DQ update are mutually exclusive; CAP_W5 also suppresses old DQ for
  wavetable.  Its first 32,768-class enumeration reported provisional maxima
  of 77/79 built-in and 76/92 wavetable.
- **R.84H-D2E-A control-provenance correction:** the first enumeration omitted
  two independent control facts: restart must survive through W0/W1 to select
  snapshot/phase2 and seed behavior, and q13 clear-ack must be compared with
  the parameter clear toggle for W0 state effects and final acknowledgement.
  The corrected executable enumeration covers **65,536** current/old
  wave/mode/noise/buzz/restart/clear classes.  Built-in paths overlay dead
  sound-ID3 and ARAM-index6 fields and peak at an exact **79/79** on live
  wave0/7 mode-2, noise-off, selected-old-noise.  Wavetable peaks at **78/92**.
  Brown plus old-noise is 78/79 and brown plus old-DQ is 75/79.  No
  PC-`0x1c` class requires control recoding or DQ reordering.  A separate
  read-only whole-window audit found plausible tight later classes at 79/79
  and 83/83 after fixed old-noise context compression, but that remains a
  hypothesis until D2F supplies literal field packing.
- **R.84H-D2F next permitted hypothesis:** carry D2E through W0--W6 as an
  executable physical allocation.  Enumerate every A18+B18+N17+O17 put/take
  and typed q arrival for the same 65,536 classes; prove W0--W3 reconstruction,
  restart/clear tags, old-noise versus old-DQ service liveness, external-hold
  freeze and every D2D fixed consumer without a decoded record/trace mirror.
  Preserve D2D's 43-word candidate and 222/782/172/158 invariants.  Do not add
  path tags, move a DQ request, add scratch/EBR/state or write RTL unless the
  physical allocation itself exposes a contradiction.
- **R.84H-D2F active hypothesis:** test the unchanged D2D stream at every
  W0--W6 boundary before allowing a repair.  The candidate counterexample is
  the no-restart built-in path with ordinary selected-old DQ immediately
  after W2: current primary, the selected old phase retained for W5, live DQ,
  reconstructed phase2, amplitude, old phase delta and the old-q carry are
  all independent.  Bind the proof to the literal CAP_W4/CAP_W5 word stream,
  the exact 70-bit A/B/N/O pool and H-C's 38-bit context, and reject D2F if the
  required payload exceeds the path-specific overlay.  Scope is this ledger
  plus `tools/psg_exec_model.py`; accepted `rtl/psg_exec.hex`, RTL, generic
  PSG, main and Tang remain untouched.  Baseline is D2E-A `3a6e5ec` with the
  43-word D2D candidate and 222/782/172/158 invariants.  Repeat only if a
  fixed existing q prefetch removes the selected-old-phase lifetime or the
  W5 old-DQ consumer moves; do not add a path tag, request, scratch word, EBR
  or state bit to make the unchanged stream fit.
- **R.84H-D2F result and decision:** rejected by the first literal W0--W6
  allocation counterexample.  The model binds CAP_W2/W4/W5 to PCs
  `0x1f/0x21/0x22` in the exact D2D image and proves CAP_W4 still primes word
  zero.  On the no-restart built-in ordinary-old-DQ path, immediately after
  W2 the independent live set is current-primary18, selected-old-phase16,
  live-DQ14, reconstructed-phase2-17, amplitude12, old-phase-delta13 and
  old-q-msb1: **91 bits**.  H-C's 38 bits must still retain old-q-low16 and
  old wave/mode/alternate6, so only sixteen can overlay the 70-bit A/B/N/O
  pool.  The unchanged stream therefore has **86 available and a five-bit
  deficit**.  This is path-specific: restart aliases selected old-q to phase2,
  while old-noise and wavetable suppress the W5 old-DQ update.  The complete
  executable model remains clean at 19,728,640 decomposed cases, 131,087
  synchronous transactions, 65,536 D2E-A classes and 64 production-image
  runs; accepted image and RTL remain byte-identical/untouched.  Do not retry
  the unchanged CAP_W4 word-zero stream.
- **R.84H-D2F-A next permitted hypothesis:** change only the alternate D2D
  candidate's CAP_W4 stored word from 0 to 16, leaving its action, operation,
  W5 edge and every request/write/clock unchanged.  The synchronous state
  port then presents original word16 as q16 at W5: no-restart ordinary old-DQ
  can consume the selected old phase there instead of retaining its W2 copy;
  restart keeps q10 in H-C storage freed because selected old-q aliases
  phase2; old-noise and wavetable ignore the extra q16 on W5.  First prove
  literal packing for all 65,536 paths, both restart branches, W0--W3
  reconstruction, hold freeze and every D2D typed consumer.  Preserve 222
  words, 782 clocks, 172 reads, 158 writes, sixteen fixed writes, the two-EBR
  budget and all accepted-image/RTL boundaries.  Reject before RTL if any
  path still spills or if the q16 prime changes a semantic consumer.
- **R.84H-D2F-A stream-foundation result:** accepted as an in-memory
  candidate only.  CAP_W4 at PC `0x21` keeps its `OP_EXEC` and CAP action,
  still consumes q14, and changes only its next-read word from 0 to 16; CAP_W5
  at PC `0x22` therefore receives q16.  Exhaustive classification of all
  **65,536** D2E-A paths selects that q16 for 15,360 no-restart ordinary
  old-DQ cases, the retained q10 snapshot for 15,360 restart ordinary-old-DQ
  cases, and no old-DQ source for 34,816 wavetable/old-noise cases.  The
  candidate retains 222 words, 782 clocks, 172 reads, 158 writes and every
  D2D action/edge.  Since CAP_W4's literal instruction changes, it is
  necessarily **44 words different** from the accepted image rather than
  D2D's 43; this is not another action, clock or topology change.  The
  accepted image and RTL remain untouched.  This foundation proves the
  source selection and schedule only, not a complete physical allocation,
  mirror-free executor or semantic sample implementation.
- **R.84H-D2F-B next permitted hypothesis:** construct the literal path-
  sensitive A18/B18/N17/O17 plus H-C allocation on the D2F-A candidate through
  every W0--W6 edge.  Cover built-in and wavetable, selected old-noise and
  ordinary old-DQ, restart and no-restart, both clear states, all typed q
  consumers and external hold.  Prove the packed values reconstruct the
  direct W0--W3 phase/wave contexts and all persistent commits, not merely
  that their summed widths fit.  Preserve the 44-word candidate and
  222/782/172/158 counts; reject before image or RTL if any container slice is
  multiply owned, a live value is reconstructed from an untyped source, or a
  service/request lifetime changes.
- **R.84H-D2F-B literal-packing result:** accepted as the physical allocation
  foundation, not as a semantic adapter.  The executable table assigns every
  named value piece to literal A18/B18/N17/O17 and path-dead H-C containers,
  then bit-packs and reconstructs each logical field to reject overlap,
  missing split bits or a summed-width-only argument.  Fifteen tight/edge rows
  cover built-in ordinary/old-noise and wavetable old-noise/old-other,
  restart/no-restart and the PC1c/W0--W3 peaks.  The initial exact fits were
  built-in selected-old-noise at PC1c (**79/79**) and wavetable selected-old-
  noise/no-restart at W3 (**97/97**).  C-B1 adds both missing path/wave-6
  discriminators and recodes the old tuple from six bits to exact
  `{old_wave,old_alt,old_mode_is2}`, making built-in ordinary/no-restart W2 a
  third exact **108/108 physical-bit** fit.  Restart and old-noise retain
  headroom.  No path spills.
- **D2F-B source/arithmetic convictions:** exhaustive all-32,768-state proof
  shows CAP_W0's one LFSR shift preserves the pre-advance `nz_hold` byte as
  post-W0 `lfsr[8:1]`; a transient eight-bit copy is unnecessary.  The
  initially reported 87/86 counterexample was therefore withdrawn.  The
  packed old-noise step plus kick is bounded by 39,491 inside signed17, and
  exhaustive phase/wave/alternate evaluation bounds the built-in primary plus
  secondary sum at -18,432..18,432 inside signed18.  D2F-A's q16 stream and
  44-word/222/782/172/158 invariants remain unchanged.  Accepted image and RTL
  are untouched.  This iteration does not yet prove the fixed q11/q13/q17
  merges, restart-old-noise phase2 copy, external packing-state hold or final
  persistent values.
- **R.84H-D2F-C next permitted hypothesis:** execute every D2F-B packed
  transition and fixed persistent merge against the independent direct oracle.
  At PC `0x27`, choose typed q11's old noise-hold or post-W0 `lfsr[8:1]` under
  the refresh bit while merging old-q low; at PC `0x28` commit final old phase;
  at PC `0x29` merge typed q17's blend count and old-q high under restart; at
  PC `0x2a` merge typed q13's clear ack, final nz phase, phase2 high and gain
  high; at PC `0x2d` commit phase2 low.  Prove old-delta/DQ zero qualification
  leaves the fixed request cadence unchanged, copy restart-old-noise phase2
  after W4 and before W6, and inject external hold at every W0--W6 transition.
  Retain the exact D2F-B layouts and 44-word/222/782/172/158 candidate; reject
  before RTL/image if any final word depends on the decoded record/trace oracle
  or an untyped memory value.
- **R.84H-D2F-C result and decision:** rejected and reverted as a proof-
  architecture failure before image or RTL.  The first composed machine stored
  literal frames but never unpacked one into a transition; instead its W0--W6
  payloads, persistent writes, W15--W84 values, filter, leaf and fold were fed
  directly from decoded `SampleRecord`/`SampleParams` and the independent
  `SampleTrace` oracle.  Its nominal seven hold checks therefore froze an
  oracle tuple beside an unchanged frame rather than a physical state
  transition.  The proposed W15 side dictionary was also physically false:
  on built-in paths B18 still owns the old source from W3 through W27, so a
  live-gain limb there aliases an independent value; on wavetable paths that
  limb is not produced until W40, so introducing it at W15 is a future-value
  leak.  The existing pool model independently fixes those lifetimes.  The
  64-run production surface further held `clear` at one value only.  No part
  of this failed machine is retained; D2F-B `c9f6e0e`, the 44-word in-memory
  candidate, accepted image and all RTL remain unchanged.
- **R.84H-D2F-C-A next permitted hypothesis:** write the complete physical
  transition manifest before another executor.  For every edge from PC1c
  through W84 and every fold step, name each live value's A/B/N/O or exact H-C
  slice, typed `state_q` or service-token source, production edge, last
  consumer and replacement.  In particular, retain built-in B18 until the
  W27 old-gain launch and forbid a wavetable live-gain limb before W40.  The
  executor may then consume only unpacked manifest state plus fixed typed
  inputs, and every write must retain `(pc, action, q-source, address, value)`
  provenance through duplicate commits and the literal fold/dry-valid path.
  First prove both clear states and all D2F-B path classes structurally; do not
  write semantic RTL or replace `psg_exec.hex` until the full manifest and
  no-oracle executor both pass with the 44-word/222/782/172/158 invariants.
- **R.84H-D2F-C-A manifest result:** accepted as a structural foundation only.
  The candidate now keeps all eighteen per-slot writes as exact
  `(pc, action, q-source, destination, value-origin)` records, including both
  word-14/15 writes and the leaf writes, rather than reducing them to the last
  value per address.  Literal post-W6 allocations use the full A18+B18+N17+O17
  plus exact H-C aliases Q=`old_q[15:0]`, T=old tuple, C=live context,
  I=`phase_index_hold` and D=`snd_id`.  After two independent audits added the
  current/old sign bits, both wave-6 decisions, `snd_wt` discriminator,
  audible gate, W84 reverb lifetimes and wavetable old-gain enable, the
  built-in W15 row peaks at **106/108 bits**.  C-B1 adds the omitted wavetable
  old-fraction18 and old-adjacent8 operands: that path is **100/108 before
  CAP_W15**, atomically replaces them with primary interpolation and relocated
  control payload, then is **89/108** after the edge.  Every declared
  replacement is non-overlapping.
- **D2F-C-A address/fold convictions:** PC36 CAP_W51 encodes word26, but the
  committed movement layer bank-remaps 24..27 only for `OP_READ`; owner-zero
  CAP is `OP_EXEC`.  Therefore D2F-C-B must make this one action-qualified
  physical read select active word26/30 before using dampen at CAP_W75.  The
  manifest also proves each of seven literal 20-PC fold nodes, four typed
  word48/49 inputs, steps 1..8, two fixed writes and q49 at `FOLD_FINISH`.
  Its stepwise A/B/N allocation peaks at **36/70 bits** and retains the signed
  A18 result through both writes and dry publication; the previous prose that
  emptied the pool before `FOLD_FINISH` was invalid.  Accepted image and all
  RTL remain untouched.
- **R.84H-D2F-C-B next permitted hypothesis:** execute the manifest as value
  transitions, not as field-name intervals.  Mechanically unpack every D2F-B
  PC1c/W0--W3 row, perform the W4/W5/W6 replacements into the 106/108 or
  89/108 pre-W15 frame, and consume only that frame, typed q values and named
  service results through W84 and the literal fold.  Model the CAP_W51
  active-bank 26/30 read explicitly, exercise both clear values, and preserve
  ordered write provenance plus external-hold freeze.  Reject before RTL if a
  value appears from a source string rather than a packed predecessor or if
  fold/dry publication reads memory directly.  Preserve the 44-word candidate
  and 222/782/172/158 invariants.
- **R.84H-D2F-C-B active hypothesis:** the first independent late-lifetime
  audit found that C-A's single `filtered_value` role was false.  At W84 the
  audible/ring value is `sample_f`, but the persistent lowpass is
  `lp_final = damp ? sample_f : lp0`; they differ whenever damp is zero.
  Correct the physical replacement atomically to A18=`{audible,sample_f}`,
  B16=final word14 and Q16 (built-in) or O16 (wavetable)=final word15.  The
  allocation is 50/108 at W84, 34/108 after PC3c and 18/108 after PC3d through
  both leaf writes.  Then implement the unpack-only predecessor transitions,
  explicitly mapping PC36 `OP_EXEC`/`CAP_W51` action `0x2d` word26 to physical
  active-bank word26/30.  Baseline is structural C-A `5f6cb83`; scope remains
  this ledger and `tools/psg_exec_model.py`, with accepted image and all RTL
  immutable.  Reject if either result is reconstructed from the oracle, if a
  typed q/source edge is bypassed, or if hold can expose a partial W84
  replacement.
- **R.84H-D2F-C-B predecessor audit:** C-A's wavetable row is also one edge
  late.  D2F-B W3 retains the 18-bit old fraction/base and CAP_W4 supplies an
  eight-bit old adjacent value; both remain physical operands until CAP_W15
  launches the old interpolation.  The exact restart peak is 100/108 before
  CAP_W15 and replaces atomically with C-A's 89/108 post-CAP row.  Restart
  must independently retain original phase2 as final old-q even when
  amplitude-zero clears current phase2 before W6.  The built-in W2 row further
  omitted one of the `snd_wt`/`live_is_wave6` discriminators.  The bounded
  D2F-C-B1 repair is zero-state: after the early word14 commit, modes 0/1 are
  identical for old phase view and modes are irrelevant for waves 0/7, so
  recode the old tuple from six bits to
  `{old_wave[2:0],old_alt,old_mode_is2}`.  Spend that freed bit and W2's one
  existing spare on the two discriminators, and prove the literal decode plus
  W4/W5/W6 predecessor replacements before constructing the late executor.
  Reject C-B1 if any path exceeds the same 108 physical bits or needs a path
  tag outside the existing H-C context/service facts.
- **R.84H-D2F-C-B1 predecessor result:** accepted as the corrected bridge
  foundation.  The executable packing table places `snd_wt` in the existing
  ordinary-W2 spare and `live_is_wave6` in the bit freed by the exact old-mode
  recode; the former 107/108 row is exactly 108/108.  Exhaustive phase-view
  proof covers every 16-bit phase, eight old waves and all four encoded modes.
  The late manifest retains wavetable B18 old fraction and A8 old adjacent
  through CAP_W15, then proves the atomic 100/108 to 89/108 replacement.
  The manifest now keeps original phase2 for restart old-q distinct from final
  current phase2, including amplitude-zero; the literal W4--W6 value transition
  remains part of the executor gate.  Full model, accepted-image/RTL
  immutability and strict OpenSpec gates pass; no executor, image or RTL is
  claimed yet.
- **R.84H-D2F-C-B2 result and decision:** rejected and reverted as another
  disconnected-executor proof.  The suffix machine itself passed 64 runs / 512
  slots, 12,800 nominal held transitions, 32 stopped-wavetable paths, both
  clear states, all damp levels, ordered suffix writes, arms, ring, blend, the
  W84 split and literal fold.  Those counts are not semantic evidence: its
  wrapper seeded the packed PRE_W15 frame and typed/service inputs directly
  from `evaluate_sample_slot()` output, including final phase/state, wave and
  ARAM results, primary interpolation, live-gain limb and final words.  The
  source-level oracle guard inspected only `execute_d2fcb_late`, excluding the
  leaking wrapper.  This is the same architectural defect that rejected the
  first D2F-C machine, now hidden behind a better late executor.  All B2 model
  code is removed; accepted image, RTL and B1 foundation `7f776da` are
  unchanged.
- **R.84H-D2F-C-B3 next permitted hypothesis:** begin from literal D2F-B
  packed W2/W3 rows, mechanically unpack them, then execute the W4, W5 and W6
  edge replacements into the corrected PRE_W15 frame before any late suffix
  comparison.  The direct evaluator may construct only the final expected
  result after execution; it may not seed a frame, typed q value, service
  result, persistent word or fold input.  Derive every wave/ARAM/multiply token
  from the modeled issue/return edge, make stopped-wavetable zero
  normalization explicit, and obtain active word26/30 through the modeled
  action-qualified state read before CAP_W51.  Extend the oracle guard across
  the harness as well as the executor.  Reject before image or RTL if any
  predecessor or suffix value is copied from the expected trace, or if a hold
  changes packed state, service state, write provenance or publication.
- **R.84H-D2F-C-B3 resume audit:** D2F-B does not yet expose a frame that B3
  can mechanically unpack.  Its local `row()` checker assigns sequential
  offsets independently for each snapshot, fills fields with synthetic hash
  values, round-trips that one row and returns only name/used/capacity.  There
  is no W2-to-W3 bit identity, producer equation or retained service-token
  state.  `TF`, `X`, `WF` and `MF` are virtual capacity names rather than
  physical H-C slices, while `phase2_next`, `post_w1_flags`, `old_bias`, the
  fourteen-bit restart `old_phase` and `old_noise_sample` are not bound to
  source equations.  Treating those dictionaries as B3 input would merely
  move B2's expected-value seeding earlier.  B1 remains a path-sensitive
  capacity/phase-view foundation, not an executable bridge.
- **R.84H-D2F-C-B3-A active hypothesis:** introduce a typed physical-state IR
  whose only containers are A18/B18/N17/O17/Q16/T6/C7/I6/D3.  Each field must
  declare literal slices, an exact producer expression, birth/last-use edge
  and don't-care guard; each transition must name typed q provenance, public
  inputs, service-token takes/issues, equations, fixed writes and its complete
  destination row.  Replace TF with the freed T2 bit after recoding the old
  tuple, and replace X/WF/MF with the five freed C bits while preserving C6
  `snd_wt` and C3 `live_is_wave6`.  Symbolically execute CAP_W3 through W6 and
  reject undefined leaves, hidden path tags, nonphysical slices, multiple bit
  ownership, a token without an issue edge or any expected/trace dependency.
  Only after this manifest closes may B3 evaluate values or reconnect the
  already-rejected late suffix; accepted image and RTL remain immutable.
- **R.84H-D2F-C-B3-A result and decision:** rejected before model code.  The
  real-slice mapping is recoverable: T5:3/T1/T0 hold old wave/mode-is-two/alt,
  freeing T2 for `live_is_wave6`; wavetable C6 and C3 retain `snd_wt` and
  `live_is_wave6`, while C0/C5:4/C2:1 are the X/WF/MF pieces and reconstruct
  primary-adjacent bits 3/5:4/7:6 beside T5:3 bits 2:0.  But a per-slot row IR
  is still not an executable boundary.  On stopped wavetable slots the legacy
  ARAM issues no request and W1--W4 capture the service's held `seq_q`; the
  direct evaluator instead normalizes the inaudible arm to zero.  Therefore
  expected `SampleTrace` cannot prove internal bridge values even when used
  only after execution.  The proposed row also omitted this cross-slot ARAM
  service register.  Separately, active parameter q is a synchronous token:
  the 44-word candidate must launch physical word 26/30 at CAP_W51 and consume
  it at CAP_W75; it may not be side-loaded or consumed at W40/W51.  External
  hold must freeze both pending service registers.  No B3-A model code, image
  or RTL is retained.
- **B3-A old-noise conviction:** D2F-B's `old_bias17` has no exact producer.
  RTL first forms an eighteen-bit selected seed plus kick, stores its wrapped
  low sixteen bits at W0, then at W1 sign-extends that stored value and adds
  the seventeen-bit old-noise step before clamping.  On no-restart/no-`nz_tick`
  paths the predecessor row retains neither original old phase nor the
  selected seed, and q16 does not arrive until W5.  Reinterpreting `old_bias`
  as the W1 pre-clamp sum also fails: signed16 seed plus a step bounded by
  33,324 spans conservatively -66,092..66,091 and requires signed18, not 17.
  The previous 39,491 bound covered step plus kick but omitted the independent
  seed and W0's sixteen-bit wrap.  The later old-noise sample additionally
  needs selected-old-inc bit13 to choose x68/x80, yet no D2F-B W1/W2 row binds
  that bit.  Thus the old-noise rows and any peak using them are withdrawn as
  physical-allocation evidence pending a new exact producer/layout proof.
- **R.84H-D2F-C-B3-B next permitted hypothesis:** move the proof boundary
  back to the production eight-slot edge stream and derive a typed transducer
  from the literal 44-word candidate plus source equations.  Persist ARAM,
  wave, multiplier and state-read output registers across slots; model absent
  request as hold, not zero, and bind every CAP_W3--W6 replacement to its
  actual service output.  Generate only real A/B/N/O/Q/T/C/I/D slices from
  those transitions, but first repair the old-noise predecessor with exact W0
  wrap/W1 pre-clamp equations and selected-old-inc bit13.  Then compare
  externally committed record/leaf/fold/dry results with the direct evaluator
  after the full run.  The direct evaluator must never supply an internal
  field or service value.  Reject before late suffix, image or RTL if the
  repaired row exceeds 108 physical bits, source extraction leaves an opaque
  producer, any service state is per-slot reset, or CAP_W51--W75 does not carry
  the selected 26/30 value through a held cycle.
- **R.84H-D2F-C-B3-B1 result and decision:** rejected and reverted before any
  image or RTL.  The proposed 12/16/18 to 16/18/19 next-read shift has correct
  scalar bounds but not a complete transition.  First, q18 at W2 removes q16
  exactly when the ordinary built-in path issues its selected-old-phase wave
  context; the exact 108/108 W2 row contains no replacement old phase.
  Second, built-in old-noise cannot contain `old_noise_sample18` at W2 because
  its x68/x80 selector q19[4] arrives only at W3: B18 must hold the signed18
  pre-sum until an atomic W3 replacement.  Third, q16 plus old-noise step still
  omits W0's kick across the mandatory signed16 wrap; no B1 row or service
  token retains that independent value.  The measured bounds remain useful:
  step -33,324..33,063, W1 pre-clamp -66,092..65,830 signed18, sample
  -82,640..82,240 signed18 and final phase signed14.  All experimental model
  code is removed; accepted image, RTL and prior B1 model are unchanged.
- **R.84H-D2F-C-B3-B2 next permitted hypothesis:** retain q16 through both W1
  and W2, and move only the CAP_W2 next-read to word19 so W3 receives selected
  old-inc bit13.  Add an explicit W0-to-W1 kick lifetime after the W0 edge
  frees its consumed noise-lowpass/phase inputs; prove that slice in every
  built-in and wavetable old-noise row.  At W1 replace seed+kick with the exact
  signed18 pre-sum; at W3 atomically replace built-in B18 pre-sum with the
  x68/x80 sample while separately retaining the clamped phase, and discard the
  pre-sum on wavetable paths after deriving signed14 phase.  Ordinary W2 must
  still issue selected old phase from q16.  Reject before any eight-slot
  executor, suffix, image or RTL if kick spills, q16 is lost, the W3
  replacement exceeds 108 bits or any value appears before its typed q edge.
- **B3-B2 resume correction:** q12 is also non-negotiable at W1.  Every PC1c
  layout retains only phase2's MSB; q12 supplies the low sixteen bits used by
  the W1 live-secondary phase and the later W6 update.  Therefore CAP_W0 must
  continue to prime word12 and CAP_W1 must continue to prime word16.  The only
  zero-cycle q-stream edit still open is CAP_W2 word18 to word19, yielding
  q10/q12/q16/q19/q14 at W0--W4.  Delay old-noise continuation from W1 to W2:
  W0 retains either the already wrapped selected seed when restart/`nz_tick`
  chooses noise-lowpass, or the independent kick when q16 old phase is still
  required; W1 consumes q12 and carries that mutually exclusive seed state;
  W2 consumes q16, forms the exact signed18 pre-sum and feeds its signed14
  clamp directly to the W2 old-primary issue; W3 consumes q19[4] and replaces
  built-in B18 pre-sum with the x68/x80 sample.  Before code, the next manifest
  must prove the W0--W2 seed/kick union and the simultaneous pre-sum/final-phase
  lifetime fit; do not assume the former `old_bias17` slot can hold both.
- **R.84H-D2F-C-B3-B2 result and decision:** rejected and reverted before any
  image or RTL.  The one-word q-stream edit and old-noise arithmetic bounds
  are sound: W0--W5 receives q10/q12/q16/q19/q14/q16, the step spans
  -33,324..33,063, the signed18 pre-sum spans -66,092..65,830 and q19[4]
  supplies selected-old-inc bit13 at W3.  The physical wavetable accounting
  was false, however.  Moving the primary interpolation request from W4 to W2
  may consume the arriving pre-edge ARAM adjacent byte and the fraction, but
  the magnitude-only multiplier retains neither the signed base byte nor the
  delta sign.  Legacy W15 reconstructs `base + signed_product`, so base8 and
  sign1 must survive W2--W15.  The claimed W2/W3 60/68-bit rows therefore
  become at least 69/77, not a 26-bit retirement.  A direct pre-edge `seq_q`
  bypass is also mandatory because `wt_p1` updates only after the W2 edge.
  Those corrected early rows fit the 97-bit wavetable envelope.  At PRE_W15,
  C-A's generic 100/108 frame carried final-old-phase16; B3-B2 has already
  clamped that value to signed14, so adding retained base8 and sign1 is net
  +7 and the corrected old-noise peak is 107/108.  That is aggregate capacity
  only: no literal 97-to-69-to-77-to-107 replacement map exists, and service-
  held state, stopped-wavetable behavior and hold-frozen ARAM/multiplier
  transactions remain unproved.  All experimental model code is removed;
  accepted image and RTL are unchanged.
- **R.84H-D2F-C-B3-B2-A next permitted hypothesis:** retain B3-B2's exact
  q12/q16/q19 and seed/kick sequence, but represent the W2 request as an
  explicit pre-edge ARAM return bypass plus a retained `{base8,delta_sign}`
  token through W15.  Bind every surviving bit to literal physical slices and
  prove the complete 97-to-69-to-77-to-107 replacement map across all built-in,
  wavetable and stopped paths plus hold-frozen ARAM/multiplier state.  Reject
  before an eight-slot executor, image or RTL if a registered W2 value is
  consumed on its birth edge, a held service token is normalized, any
  multiplier transaction advances under external hold, or the repaired
  PRE_W15 row exceeds 108 physical bits.
- **R.84H-D2F-C-B3-B2-A1 active-path result:** accepted as a bounded physical
  transition foundation, not as B3-B2-A completion.  The model changes only
  candidate PC1f CAP_W2 word18 to word19, preserving q W0--W5 as
  10/12/16/19/14/16, 44 changed words and 222/782/172/158 topology.  For the
  active `play && amplitude != 0` wavetable/selected-old-noise path, every
  successor frame is decoded from and repacked from its predecessor: W1/W2/W3/
  PRE_W15/post-W15/W26 occupy 108/80/79/107/96/64 of 108 physical bits, with
  overlay 97/69/77.  The executed transitions select wrapped seed versus
  q16+sign-extended kick under exact `restart || nz_tick`, clamp at +/-6143,
  derive wavetable gain from retained amplitude, consume pre-edge adjacent
  bytes into named multiplier tokens, preserve W6 old-N-to-O ordering and
  carry primary then secondary base/sign through their real consumers.  The
  generic C-A manifest is corrected independently: an old interpolation
  launched at W15 also retains base8+sign1 until W26, so its post-W15 row is
  98/108 rather than 89/108.  Two independent audits accept this exact scope;
  stopped paths, ARAM request identity/timing, service readiness, external
  hold/freeze, late semantic execution, image and RTL remain unproved.
- **R.84H-D2F-C-B3-B2-A2 next permitted hypothesis:** compose one persistent
  source-derived service transducer around A1.  Its only cross-edge state is
  ARAM `seq_q`/replay/pending request identity, the literal packed frame, and
  multiplier kind/operands/result/busy/ready age.  Execute played and stopped
  wavetable slots: W1 captures the returned or held base, W2 consumes pre-edge
  `seq_q` directly and launches primary interpolation, W15 consumes it and
  atomically launches secondary interpolation, and W26 consumes that result.
  Inject holds before/inside/after both transactions and prove controller,
  frame, ARAM sidebands/output and slow+fast multiplier state are unchanged.
  Stopped slots issue no ARAM request and must reuse the held byte rather than
  zero-normalize it.  Reject before an eight-slot executor, image or RTL if a
  token lacks an issue edge, ages while held, is consumed before ready, or any
  expected/direct-oracle value seeds internal state.
- **R.84H-D2F-C-B3-B2-A2 result and decision:** rejected and fully reverted
  before image or RTL.  Its self-check executed 256 nominal active plus 256
  stopped slots, four tagged ARAM issue/takes on each active slot, multiplier
  ages of seven clocks to W15 and five clocks to W26, and 11,520 nominal hold
  snapshots.  Those counts do not prove the required composition.  `hold()`
  compared two reads of an untouched Python object without attempting a
  controller, packed-frame, ARAM or multiplier transition, so the freeze gate
  was tautological and the A1 literal frame was absent.  ARAM requests carried
  their returned byte directly, replay injected an independent seeded value,
  and the stored kind merely rechecked its own tag; there was no addressable
  audio memory, pre-edge registered-output ordering or returned-address
  identity.  Multiplier readiness was likewise an assumed `age >= 5`
  abstraction rather than the retained slow/fast transaction boundary.  Two
  independent audits agree on these defects.  The complete model still passed
  only because this isolated abstraction was internally self-consistent; all
  A2 code is removed, `tools/psg_exec_model.py` is byte-identical to A1
  `dd8a65d`, and accepted image/RTL remain untouched.
- **R.84H-D2F-C-B3-B2-A2-A next permitted hypothesis:** build one literal
  edge-state transducer rather than another service summary.  Its state must
  contain the actual A1 packed frame, controller edge, an addressable 4,608-byte
  ARAM with registered `seq_q` plus borrow/replay request address, and the
  retained multiplier's slow-request/fast-recurrence/acknowledge state (or an
  explicitly source-proven bisimulation of that state).  Derive all four active
  bytes and the stopped held byte by executing literal ARAM addresses against
  the same memory; model same-edge pre-update `seq_q` consumption and replay
  from that memory, never from request payloads.  Express one CE-gated
  next-state function and convict external hold by comparing an attempted held
  step with the exact pre-state across controller, frame, ARAM, replay and all
  multiplier fields.  Compose W1/W2/W15/W26 by unpacking and repacking A1's
  literal slices, including base/sign lifetimes.  Reject before late suffix,
  image or RTL if any return value is injected, any frame is parallel scalar
  state, multiplier readiness is an unproved age constant, or stopped service
  state is reset/normalized between slots.
- **R.84H-D2F-C-B3-B2-A2-A result and decision:** rejected and fully reverted
  before image or RTL.  The first executable version did materially repair
  A2: its self-check passed 64 active plus 64 stopped literal-frame slots,
  address-derived four-byte ARAM reads and replay, CPU upload during synthesis
  freeze, a translated radix-2 request/synchronizer/ten-step/acknowledge
  recurrence, 1,920 held edges, eleven count/ack freeze points and all 262,144
  equal-endpoint interpolation quotients.  Those passing counts still conceal
  two boundary errors.  `held_step()` invoked the frozen ARAM and multiplier
  functions but never invoked the controller/frame transition, so its unchanged
  offset and packed frame were assumptions rather than the required attempted
  CE-gated step.  It also used one `active` bit for both play and nonzero
  amplitude.  Source RTL issues all four wavetable reads under `play_bits`
  alone, but refreshes `wt_pf`/`wt_qf` only under
  `play_bits && s_eff_a != 0`; a playing zero-amplitude slot therefore reads
  distinct bytes while retaining preceding fractions and is neither the
  proved active arm nor the equal-endpoint stopped quotient.  The complete
  model passed because it omitted that third state class.  All A2-A model code
  is removed; `tools/psg_exec_model.py` is byte-identical to A1 `dd8a65d`, and
  accepted image/RTL remain untouched.
- **R.84H-D2F-C-B3-B2-A2-A1 next permitted hypothesis:** retain A2-A's
  addressable ARAM and exact slow/fast multiplier recurrence, but drive one
  pure edge-state function with explicit `play`, nonzero-amplitude and CE
  inputs.  Compute a complete next controller/frame/service state on every
  call, then select pre-state atomically when CE is false; a hold test must
  demonstrate both the different enabled successor and exact frozen state.
  Execute three persistent cross-slot classes: audible playing, playing with
  zero amplitude, and stopped.  Only stopped may use the equal-endpoint
  quotient.  The zero-amplitude class must issue four address-derived bytes
  while consuming literal retained fractions from the preceding slot, and
  must show whether those products can reach an old-arm/fold/public commit
  before any canonicalization is allowed.  Reject before late suffix, image or
  RTL if the frame/controller CE is an early return, fractions are reseeded,
  or a service witness supplies candidate state.
- **R.84H-D2F-C-B3-B2-A2-A1-S result and decision:** accepted only as a
  bounded sampled W1-through-POST_W26 wave-service lemma, not as A2-A1
  completion or public equivalence.  One immutable next-state function now
  computes the enabled successor before a CE selects that successor or the
  bit-identical prestate across schedule offset, literal A1 packed frame,
  addressable 4,608-byte ARAM/replay and every slow/fast multiplier field.
  Sixty-four seeded cases in each of audible playing, playing at zero amplitude
  and stopped classes pass 8,640 attempted offset/frame/service freezes,
  exact four-read pre-edge ARAM identity, live CPU upload under synthesis
  freeze, all ten radix-2 recurrence counts plus acknowledge freeze, and
  262,144 equal-endpoint interpolation cases.  The playing-zero class executes
  the real four reads with preceding fractions and a canonical-zero candidate;
  only retained multiplier request/result payload differs, and 64 following
  audible runs plus 64 following stopped runs converge the complete sampled
  frame/ARAM/multiplier state after that payload is overwritten.  Source
  assertions bind the distinct play/read and play-and-amplitude/fraction gates,
  gain-zero algebra and old-arm use of `mx_new`.
- **A2-A1-S exclusion:** `EdgeState.offset` is not the production
  PC/IR/action/state-q controller.  `source()` supplies correlated sampled
  non-service fields rather than all legal frames or a production eight-slot
  stream.  The zero-gain witness proves only that interpolation-specific gain
  input is zero; real W27/W51, ring, blend, dampen, fold and public commits are
  absent, and dampen may still emit prior `s_lp`.  Rebuilding a later frame
  proves service-state convergence only, not convergence of omitted persistent
  suffix state.  Accepted image and all RTL remain untouched.
- **R.84H-D2F-C-B3-B2-A2-A1-B next permitted hypothesis:** replace the
  sampled offset harness with the literal candidate-image PC/IR/action/state-q
  transaction stream for a production-derived eight-slot state.  Reuse the
  accepted ARAM/multiplier pure functions but obtain every frame and persistent
  value from predecessor state or a typed public input, never `source()` or an
  internal expected value.  Execute W27/W51 through ring/blend/dampen, all
  seven fold nodes and dry/public commit, including nonzero prior `s_lp`, then
  compare only final persistent and public outputs with the direct oracle.
  A held call must compute a different complete enabled successor before CE
  selects exact prestate across PC, IR, state-q, frame and services.  Reject
  before image or RTL if zero-amplitude canonicalization changes any suffix
  state/output, a new 20-bit fraction store appears, or any controller/service
  value is injected from the oracle.
- **R.84H-D2F-C-B3-B2-A2-A1-B0 production boundary audit:** accepted as a
  docs-only replacement manifest; no model, image or RTL changes.  The existing
  `SampleImageMachine` is useful only for its literal owner-zero PC/IR/state-q,
  memory-address, fold and dry-public skeleton.  It calls
  `evaluate_sample_slot()` immediately after the 14 record plus four parameter
  loads, then launches 24 service tokens directly from `self.trace`: DQ/noise,
  all four built-in or ARAM results, both interpolation and gain chains, ring
  reads and blend.  Twenty-six trace-dependent equality assertions merely
  compare those injected tokens with their own source.  The remaining direct
  semantic roots are selected final-record words, `trace.leaf`, next LFSR/LFSR2
  and a final-word decode that controls blend launch.  Therefore its reported
  64 production-image runs, 512 slots, 8,052 service transactions and exact
  fold/dry commits prove image topology and oracle consistency, not a
  mirror-free semantic executor.
- **B0 atomic replacement rule:** do not graft A2-A1-S into only CAP_W0--W26
  while retaining any other `self.trace` launch, direct store, leaf, control or
  LFSR use; that would again let the direct evaluator supply candidate state.
  Keep `SampleTrace` only outside the machine as a final-output oracle.  Inside,
  the first acceptable cut replaces all 24 token values plus the six direct
  state/output roots from loaded words, public inputs, addressable ARAM, exact
  service recurrences and predecessor candidate state in one executable path.
  The 26 trace comparisons must become comparisons at the final record, ring,
  leaf and dry boundaries only.  Preserve the literal PC/IR/state-q and fold
  skeleton, but replace its snapshot `inject_hold()` with the A2-A1-S pure
  enabled-successor/CE selection across every new persistent field.
- **R.84H-D2F-C-B3-B2-A2-A1-B1 next permitted hypothesis:** first define a
  typed producer manifest for those 30 atomic roots, grouped by the earliest
  production edge that can derive each value.  Every root must name loaded-word
  slices or a public input, service request/response, exact birth and last use,
  physical A/B/N/O plus H-C slices, and its final persistent/public consumer.
  Reject before executor code if a root names `SampleTrace`, if two groups hide
  the same arithmetic behind different names, if ring/dampen/fold state is
  absent, or if any root exceeds the already-proved frame capacity/lifetime.
  Only a complete manifest may drive the atomic no-oracle executor rewrite.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-A result and decision:** accepted only as a
  bounded executable injection inventory, not as B1's physical manifest.  It
  mechanically discovers the existing 24 `issue()` launch sites and six
  direct trace uses, requires one of 30 typed rows for each, and reduces only
  exact retained duplicates to 27 value groups.  Every row names a source
  equation, production birth/last-use edge, coarse service/frame/state owner
  and final consumer; no producer may name Trace or an oracle.  The audit
  corrected two previously hidden physical facts: interpolation services hold
  a nineteen-bit magnitude while signed base/sign remain in the frame, and
  W75--W84 retains a 23-bit blend product rather than a seventeen-bit filtered
  sample.  PC2E is the explicit blend-count birth.  The full model and image
  immutability gate pass; accepted image and all RTL remain untouched.
- **B1-A exclusion:** owner strings are classifications, not literal slice
  tuples.  The inventory does not sweep bit collisions or per-edge capacity.
  `leaf_commit` still compresses audible, sample_f, q26/q30 damp, prior
  lowpass, filtered result, lp_final and word14/15 into prose.  Ring write and
  persistent ring position are absent; the LFSR roots omit W0's retained byte
  through the word11 merge; `record_commit` hides eighteen timed merges; and
  fold membership does not bind word48/49 through A/B/N slices to dry16.  An
  independent audit rejects any broader B1 claim for exactly these reasons.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B next permitted hypothesis:** expand the 27
  values plus the omitted persistent transitions into literal
  `{container,lsb,width}` pieces at every birth/replacement/death edge.  Split
  all eighteen record merges and the complete W75--word15 late chain; add
  playing-only ring write, ring-position advance, W0 LFSR-byte retention and
  every fold word48/49/dry transfer.  Reuse A1/D2F-C-A slice names only after
  mechanically matching their producer and guard, then sweep ownership and
  capacity at every production edge for built-in, wavetable, silent, stopped,
  reverb and dampen classes.  Reject before executor code if any path exceeds
  A18+B18+N17+O17 plus H-C, if a service-resident bit is double-counted as
  frame state, or if a prose bundle hides independently timed values.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B active hypothesis:** starting from clean
  scratch `c0e7302`, replace B1-A's coarse owner strings with a typed physical
  manifest whose every retained value has literal `{container,lsb,width}`
  pieces and whose service outputs are named outside the 108-bit frame.
  Split the eighteen fixed writes, W75--word15 filter/dampen chain, playing-
  only ring write and ring-position advance, W0 LFSR-byte provenance and the
  complete word48/49-to-fold-to-dry path.  Mechanically sweep bit ownership at
  every named replacement edge for active built-in, active wavetable,
  playing-zero-amplitude, hidden-silent, stopped-wavetable, reverb, dampen and
  combined reverb+dampen classes.  Baseline gates are the full executable
  model, Python compilation, strict OpenSpec validation and byte-identical
  accepted image/all-RTL immutability.  Reject before executor/image/RTL on
  any collision or spill, a missing class/commit/fold edge, an oracle-derived
  producer, service/frame double accounting, or an independently timed value
  hidden behind a bundle name.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B result and decision:** rejected before
  model/image/RTL change by an independent literal-slice audit.  B1-A's
  `dq_live_hold -> frame:N17` classification is physically impossible:
  original/final phase2 already occupies N17 through W6.  The exact live DQ
  payload is fourteen service bits in the chained DQ live-result register;
  W6 zero-extends them while atomically replacing N with final phase2.  The
  old DQ result likewise stays in the DQ recurrence until W5.  Noise services
  expose a 24-bit multiplier slice plus the still-stable random sign before
  replacing O with a signed seventeen-bit old step; interpolation changes
  from a nineteen-bit service magnitude plus base/sign to a signed fifteen-
  bit frame value; reciprocal results require a retained seventeen-bit limb
  plus `m_p[28:3]`, not one direct multiplier slice.  Treating any of those
  stages as one retained value would either collide or double-count state.
- **B1-B late-path audit:** the existing D2F-C-A built and wavetable rows are
  collision-free only after keeping those services external to the frame.
  The exact ring path still needs post-read sixteen-bit current/old captures,
  the playing-only `sample_f[15:0]` ring write and one persistent ten-bit ring
  position advanced once per sample.  A viable W75 replacement retires both
  arms, ring values, reverb flags and blend count while retaining a seventeen-
  bit blend base, one difference-sign bit and one product-pending bit beside
  damp/audible; count 64 takes the no-product arm.  This bridge needs a new
  arithmetic/value proof and service-valid state.  The current CAP_W51
  `OP_EXEC word26` also remains physically wrong for parameter bank one:
  `psg_execmove` remaps 26 to 30 only for `OP_READ`.
- **B1-B persistent/output audit:** the eighteen write sites remain split at
  PCs 14/15/16/17/19/1b/1d/1e/27/28/29/2a/2d/39/3c/3d/4c/4d, but D2F-C-A
  proves only action/q/destination provenance; it does not provide eighteen
  independent value equations.  Their exact q/destination pairs are
  20/20, 21/21, 22/22, 18/18, 19/19, 14/14, 10/23, 12/10, 11/11, 16/16,
  17/17, 13/13, 12/12, 15/15, 14/14, 15/15, 0/48 and 48/49.  W0's pre-edge
  LFSR byte needs no new store:
  after the shift, new `lfsr[8:1]` is exactly old `lfsr[7:0]` through the
  word11 merge.  Fold arithmetic/slices remain reusable, but the no-oracle
  word48/49-to-A/B/N-to-final-A-to-`dry16` transfer is still unbound:
  `SampleImageMachine.FOLD_FINISH` currently rereads slot-zero word48 rather
  than publishing retained A, so it proves memory consistency instead of the
  proposed physical boundary.  Ring RP also has no reset assignment in the
  generic walker, so an integrated executor needs an explicit initialization/
  provenance contract rather than silently assuming a start address.
  Active built-in/wavetable rows therefore do not prove playing-zero,
  hidden-silent, stopped-wavetable, reverb or dampen suffix behavior.  The
  accepted model/image/all RTL are unchanged; B1-B is not a complete physical
  manifest.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1 next permitted hypothesis:** build only the
  exact service/take and W75-to-W84 transition IR.  Give DQ, multiplier, wave,
  ARAM and ring services literal result/valid slices outside A/B/N/O+H-C;
  split every width-changing take into separate service and frame values;
  prove the count-64/product-pending bridge, both ring captures, play-only
  ring write/RP update and active-bank 26/30 source algebra across built-in,
  wavetable, playing-zero, hidden, stopped, reverb and dampen classes.  Stop
  before record commits, fold/public equivalence, image or RTL.  Reject if a
  service bit enters the 108-bit capacity sweep, an absent request is treated
  as a zero result, or the post-W75 row exceeds the existing late-path bound.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1 active hypothesis:** starting from clean
  scratch `0aa9471`, add only a model-level typed service/take IR.  DQ,
  multiplier, wave, ARAM and ring results each carry explicit valid and kind
  state outside the 108-bit frame; every take either consumes the matching
  issued kind or is rejected, and every width-changing take names its exact
  raw slice plus retained context.  Prove the W75 bridge as a signed-17 base,
  difference sign and product-pending bit, with count 64 taking no multiplier
  result; retain damp, audible and the two filter words through W84.  Prove
  both synchronous ring captures, play-qualified low-16 write and the live
  RTL's actual pointer rule: `ring_rp` advances once at every accepted sample
  start regardless of play, from an explicit predecessor because generic RTL
  gives it no reset value.  Prove the required action-qualified CAP_W51
  word-26 to physical-26/30 bank selection for the immediately following
  CAP_W75.  Sweep built-in, wavetable, playing-zero-amplitude, hidden,
  stopped-wavetable, reverb, dampen and combined classes.  Baseline gates are
  the full model, Python compilation, strict OpenSpec validation and
  byte-identical image/all-RTL.  Stop before record values, fold/public,
  image or RTL and reject on an untagged/stale take, service/frame double
  accounting, absent-request zero substitution or a late-frame collision.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1 result and decision:** rejected before
  model/image/RTL landing by two independent audits.  The candidate's static
  foundations are sound: the exact late control topology is PC34 current-ring
  issue, PC35 current capture plus old issue, PC36 old capture plus CAP_W51;
  action-qualified word 26 selects physical 26/30; the service boundary is
  177 bits including 31 genuinely new valid/tag bits; W75 grows
  22 -> 38 -> 54/108 and W84 is 50/108 without collision; and the supplied
  blend/reverb/dampen arithmetic is exact.  Its execution claim is not: a
  Python `(kind,value)` FIFO issues and takes immediately, so valid/kind
  widths are metadata, all CE checks freeze empty pipes, count 64 never faces
  stale `m_res`, and DQ/wave/ARAM/ring never execute their synchronous
  recurrence or response cadence.  Taken gain/reciprocal results are discarded
  before W75 and replaced by injected arms; amplitude is unused; q26/30 never
  supplies the late damp/reverb fields; ring labels do not mutate one shared
  eight-slot memory or write address; and lowpass is not clear-qualified.
  No B1-B1 model, image or RTL is accepted or landed.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-A next permitted hypothesis:** retain only
  those static foundations and replace the FIFO sketch with one immutable,
  cycle-indexed successor over the literal candidate PCs.  Encode multiplier
  kind/valid and ready cycles, DQ live/old validity, the two-stage wave tags,
  ARAM q-origin/replay and ring rd/current/old validity; compute the complete
  enabled successor before CE selects it.  Carry actual service results through
  interpolation, gain, reciprocal, W75 and W84; drive damp/reverb from poisoned
  physical word 26/30; distinguish `play` from `play && amplitude != 0`; and
  qualify old lowpass by clear.  Execute both REVERB builds as accepted samples
  with one RP advance and eight slots sharing it, explicit PC34/35/36 NBA
  ordering and addressed PC3c writes.  Reject unless all 22 take equations
  execute, stale retained outputs remain unusable, count 64 bypasses a nonzero
  stale product by validity, every literal row round-trips, and all 732 RP
  predecessors times eight slots satisfy the physical address law.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-A active hypothesis:** starting from the
  docs-only B1-B1 rejection, implement only that immutable model proof in
  `tools/psg_exec_model.py`.  Keep the accepted image and all RTL untouched;
  stop again before record commits, fold/public equivalence, executor image,
  synthesis or generic integration.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-A result and decision:** rejected and
  reverted after two independent source audits; no model, image or RTL lands.
  The experimental model passed its own 32 persistent slot runs, 438 service
  transactions, 1,344 hold/row checks, 5,856 ring-address cases and both
  REVERB builds, but those counters are not an execution proof.  It executed
  the radix-4 recurrence although production `psg.sv` instantiates
  `psg_mulmp` with `RADIX_BITS=1`; encoded damp/reverb in parameter bits 1:0
  and 3:2 instead of the production state-q bits 13:12 and 11:10; and formed
  ARAM origins as `64*snd_id+index` instead of the physical
  `256+68*snd_id+index` layout and three-bit sound ID.  The stopped-wavetable
  case injected four addressed bytes without four requests, while the clear
  case pre-zeroed word14/15 instead of carrying W0's enabled lowpass update.
- **B1-B1-A proof defects:** `SlotContext` remained a hidden semantic sidecar
  for phases, gains, fractions, path flags and origins.  Generic 108-bit
  dataclass pack/unpack proved only identity, not per-PC literal ownership or
  collision freedom.  Disabled CE aliased the prestate without evaluating a
  disabled successor; wrong-tag checks observed labels without attempting a
  rejected take; DQ takes cleared metadata without applying the old-q/phase2
  equations; noise results were discarded; ring validity was set but never
  required at W75; and aggregate service issue/take equality allowed
  cross-service cancellation.  The two audits also found no playing
  wavetable/zero-amplitude class, no old-gain-zero arm, and an extra old-DQ
  result register inconsistent with the claimed recurrence-retained boundary.
- **B1-B1-A retained narrow evidence:** literal candidate PC/action gaps,
  PC34 current-ring issue -> PC35 current capture plus old issue -> PC36 old
  capture NBA order, action-qualified PC36 word26 -> physical 26/30 followed
  by PC37 consumption, isolated W75/W84 signed arithmetic, count-64 rejection
  of a nonzero stale product, raw-play versus audible gating, the
  `730 -> 731 -> 0` two-sample RP example and all 5,856 pure ring-address
  algebra cases remain useful foundations.  They do not prove service
  execution, frame ownership, persistent record updates or suffix behavior.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-B next permitted hypothesis:** start with
  the physical transition schema, not another executor.  Mechanically derive
  each PC's exact state-word slices, A18/B18/N17/O17+H-C ownership, producer,
  enabled-successor equation and last use from the candidate image and live
  radix-2 RTL.  Bind parameter word26/30 bits 13:10, the physical
  `256+68*snd_id+index` ARAM address and retained/replayed stopped-wavetable
  `seq_q`; include playing-zero-amplitude and old-gain-zero classes.  Require
  per-service issue/take balance, an actually evaluated disabled successor,
  attempted wrong-kind/origin takes, DQ old-q/phase2 commits and ring valid
  consumption.  Reject before whole executor code unless every production
  edge has a literal overlap-free row and no semantic value comes from a
  context/oracle sidecar.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-B active hypothesis:** starting from clean
  scratch `c9e40bf`, add only a source-derived physical transition-schema
  proof.  It may name production state words, public inputs and the existing
  service recurrence state, but no sampled `Path`/`SlotContext`, injected
  value or final-output oracle.  Every admitted PC row must carry literal
  physical slices, guard, q/address origin, enabled successor and last use;
  every service must balance independently.  Bind the instantiated radix-2
  multiplier, parameter bits 13:10, physical ARAM base/stride, stopped held
  `seq_q`, DQ phase commits and ring validity.  Exercise a real CE-selected
  successor and explicit rejected wrong-kind/origin takes.  Stop before value
  execution, record/fold/public semantics, image, RTL, area or render work and
  revert if any row still depends on a semantic sidecar or prose ownership.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-B result and decision:** rejected and
  reverted after two independent audits; no model, image or RTL lands.  The
  draft correctly bound the HX8K target to `RADIX_BITS=1`, parameter damp/rev
  to q bits 13:12/11:10, and all 1,024 reachable three-bit-sound-ID ARAM
  addresses to `256+68*id+wrapped_index`.  It also preserved the candidate's
  sixteen named action PCs, late state words and corrected built-O versus
  wavetable-N and Q-versus-O destination spelling.  These are source facts,
  not a transition proof.
- **B1-B1-B proof defects:** its 26 hand-written transition rows cover only 19
  of the 42 PCs from 13 through 3c.  Guard/source/result/last-use fields are
  unchecked prose, row validation sees neither cross-row lifetime collisions
  nor the H-C aliases, and the six late snapshots omit live path/control bits.
  The radix-2 slow+six-fast CDC successor, DQ terminal-and-relaunch edge,
  W0-W5 wave tags, ARAM replay/stopped `seq_q`, ring validity/RP/write and W0
  clear-qualified seventeen-bit lowpass were not executed.  Equal service
  tuples, an invented `Boundary` ternary and Boolean wrong-token probes do not
  prove balance, CE freeze or rejected takes.  PC36 bank-one still physically
  reads word26 because the required OP_EXEC CAP_W51 26->30 override is absent.
- **Stop rule and next permitted evidence:** B1-B1-A and B1-B1-B are two
  consecutive rejected Python mirrors of the same transition mechanism; do
  not retry it with another prose manifest, sampled context or Python state
  machine.  A future B1-B1-C is permitted only if it changes the evidence
  source: instrument the existing RTL primitive benches to emit deterministic
  per-edge traces for the instantiated radix-2 multiplier, chained DQ, wave
  pipeline, ARAM borrow/replay and ring NBA sequence, then mechanically join
  those traces to all 42 literal candidate PCs and the existing D2F-C-A slice
  lifetimes.  Require the real held clock enables and deliberately invalid
  kind/origin requests to be observed at the RTL boundary.  Stop before an
  executor or generic integration until that trace join has no missing PC,
  live bit, q/address origin or service transition.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-C active hypothesis:** starting from clean
  scratch `57a1e07`, change the evidence source by adding deterministic,
  machine-readable edge traces to the existing RTL primitive benches.  Begin
  with the instantiated radix-2 multiplier and chained DQ services, recording
  pre/post slow state, all six fast edges, request/ack/valid identity, CE/freeze
  and terminal take/relaunch order.  The trace consumer may check structure
  and join keys only; it must not reimplement arithmetic or inject expected
  results.  Commit this bounded primitive foundation before wave/ARAM/ring or
  the 42-PC join.  Reject if the trace omits NBA-visible prestate, derives
  values outside RTL, or cannot convict a held and deliberately invalid edge.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-C1 result and decision:** accepted as a
  bounded primitive-only trace foundation.  Optional `+PSG_EDGE_TRACE`
  output from the existing radix-2 multiplier and DQ benches is filtered by
  the `PSGTRACE ` prefix into self-describing `psg_edge_v1` JSON.  Every row
  records pre-NBA state and the settled `#1` poststate; request inputs,
  retained payload, real toggle synchronizers, recurrence, acknowledge,
  padding, output and hold controls come directly from the DUT.  Bench-case
  and edge/subedge fields are diagnostic coordinates only; transaction
  identity must be derived from real toggle/count transitions and causal
  order from time/domain/edge/phase.
- **C1 trace evidence:** two independent runs are byte-identical.  The
  multiplier emits 105 slow pre/post epochs and exactly six coherent fast
  pre/post edges for every epoch, with no orphan, partial or split-case group;
  fourteen observed slow accepts join fourteen fast loads and completions.
  All 27 slow and 162 fast frozen pairs preserve the complete emitted state.
  The DQ trace has 61 pre/post edges and seven accepts/completions; its
  terminal live result 16254 is visible before the same-edge old-context
  relaunch, the old result 5526 remains held, and fifteen `ce=0` attempts
  preserve state, including twelve asserted starts while not ready and three
  terminal-ready but held starts.  Both independent source audits accept this
  bound after one half-epoch trace-window defect was found, fixed and
  re-audited.  The ordinary 6,020-transaction multiplier bench, 524,288-case
  DQ model and 57,344-transaction DQ bench remain unchanged and pass.
- **C1 hard boundary and next permitted C2:** neither primitive contains the
  candidate image, PC/IR, semantic kind/origin or a consumer take strobe, so
  C1 does not prove any of the 42 candidate PCs, issue/take ownership,
  wrong-kind/origin rejection, cross-row lifetime, wave/ARAM/ring, record,
  fold or public behavior.  C2 must expose actual controller/adapter
  active/hold/owner/slot/PC/IR/action, state-memory activity and real
  issue/take strobes on the same slow-edge timeline, then join those events to
  C1's observed toggles/counts and deterministic wave/ARAM/ring RTL traces.
  A bench label or hand-authored PC map may not supply causality.  Stop again
  before executor semantics, image change, generic integration or physical
  claims until every one of the 42 PCs and D2F-C-A lifetimes is joined.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-C2-A active hypothesis:** expose the
  accepted production-image controller/state/wave/ARAM edge sequence in the
  existing `psg_execwave_tb.sv`, without changing production RTL or image.
  Optional `+PSG_EDGE_TRACE` rows shall record actual pre-NBA and settled
  post-NBA active/hold/owner/slot/PC/IR/op/action, controller read/write port,
  state-q, wave issue/CE/take/context/result and ARAM request/read-address/
  replay/take/result signals.  Structural TB provenance may be driven only by
  actual `state_re/state_ra`, `wave_issue/wave_ce` and `aram_req`; it must be
  labelled as proof state and may not inject a semantic kind, result or PC
  label.  Mechanically require every accepted-image PC `0x13..0x3c`, exact
  pre/post pairing, state-q read-origin continuity, the real W0--W3 to W2--W5
  wave pipeline and W0--W3 to W1--W4 ARAM borrow/replay chain in both built-in
  and wavetable runs, including external hold.  Baseline is clean scratch
  C1 `34973c2`: thirteen production-image runs each execute 782 enabled
  clocks, 172 semantic reads and 158 writes; built-in runs observe 32 wave
  issues/takes and wavetable runs observe sixteen ARAM issues/takes.  Scope is
  this ledger and `rtl/psg_execwave_tb.sv`; accepted `rtl/psg_exec.hex`, all
  production RTL, generic PSG, main and Tang remain immutable.  This iteration
  cannot claim D2F's 44-word in-memory candidate, semantic write data, C1
  multiplier/DQ causality, ring, record/fold/public behavior or physical
  results: those adapters do not exist in this harness.  Reject if any join
  needs a bench-case label, expected-value oracle, hand-authored PC/action map
  or an unobserved production valid/tag.  Repeat only if the accepted image,
  synchronous state-port contract or real wave/ARAM issue boundary changes.
- **C2-A result and decision:** accepted as a bounded structural
  production-image transaction proof.  The optional trace emits **8,808**
  valid `psg_edge_v1` JSON rows forming **4,404** exact pre/post-NBA pairs;
  two complete runs are byte-identical.  Each of thirteen cases observes all
  42 PCs `0x13..0x3c` in all eight slots, for 4,368 state-q origin checks tied
  to real `state_re/state_ra` events and the controller's loaded image word.
  The strobe-derived wave pipeline joins **224 issues to 224 takes** and binds
  phase plus wave controls through the real first stage before the shared-CE
  tag advances; the ARAM chain joins **96 requests to 96 takes**, including
  24 final replay reads of sequencer address `0x055`.  Thirty-six traced held
  pre-edges suppress both state ports and every service strobe while preserving
  controller, state-q, proof-token, wave, ARAM byte and replay state.
- **C2-A audit corrections and gates:** the first trace attempt was invalid
  JSON because reset-time unknowns were emitted as bare values; capture is now
  restricted to the initialized candidate-PC window and the legitimately
  unknown early waveform result is quoted.  Independent review then rejected
  hand-authored `take_action=issue_action+latency` checks and an unbound phase
  token; both action equations were removed, and the phase/control token is
  now checked against `u_wave.wx_r/wsel_r/wsec_r/walt_r` on real `wave_ce`
  before both pipelines shift.  Two independent final audits accept a queue
  reconstruction using only actual issue/take/CE strobes.  The production
  wave/ARAM bench passes at 782/172/158 per case and reports joins
  4,368/224/96; direct wave-core and ARAM-hold benches pass; the complete
  19,728,640-case/131,087-transaction model and byte-identical image pass;
  executor plus generic full/PREVIEW lint, `make test-psg` including fidelity,
  93 audio-analysis tests and the complete PSG RTL test, strict OpenSpec and
  diff checks pass.  `make test-psg` required the existing Homebrew Python
  because OSS-CAD's bundled Python lacks NumPy.  No production RTL or image
  changed.  Therefore this proves accepted H-C image PC/state/wave/ARAM
  lineage only: synthetic write data, the 44-word D2F candidate, C1
  multiplier/DQ causality, ring, semantic commits, fold/public, integration
  and physical results remain outside the claim.
- **R.84H-D2F-C-B3-B2-A2-A1-B1-B1-C2-B active hypothesis:** materialize the
  latest literal D2F control candidate and execute its complete instruction
  stream in the real controller before adding a semantic adapter.  The model's
  `sample_b3b2a_candidate` is a complete 256-word owner-zero bank: it retains
  222 nonzero words and is exactly 44 words different from the accepted bank;
  all later D2F-B/C-A/B1 validators consume it read-only and produce no newer
  image.  Add an explicit candidate-output option that serializes this bank
  plus the unchanged 256-word owner-one bank as one deterministic 512-word
  artifact under `build/`, while keeping `rtl/psg_exec.hex` byte-identical.
  A new candidate-only bench shall load that full artifact into the existing
  non-`TEST_PROGRAM` controller after its time-zero production-image load and
  before the first clock, deriving the 44-word difference mask mechanically
  from the two full images.  Require every fetched IR to equal the candidate,
  every changed PC to execute in all eight slots, unchanged termination and
  782/172/158 plus operation histogram, synchronous state-q read origin, and
  three-cycle hold/resume identity at each of the 44 changed PCs.  No changed
  PC list or action meaning may be hand-authored into the bench.  Baseline is
  clean C2-A `f4342c5`; scope is this ledger, `tools/psg_exec_model.py` and one
  new RTL testbench.  Do not edit the accepted image, controller, movement,
  generic PSG, Tang or ring RTL.  This proves only deterministic candidate
  artifact/fetch/control-flow/state-port behavior: synthetic write data, fixed
  destinations, CAP_W51's pending active-bank 26/30 remap, packed A/B/N/O+H-C
  transitions, wave/ARAM/DQ/multiplier causality, persistent commits, fold/
  public behavior, integration and physical results remain later gates.
  Reject if materialization mutates `rtl/psg_exec.hex`, emits a partial/patch
  image, needs a production loader change, or if any changed PC is unreachable
  or cannot hold/resume from its real candidate IR.
- **C2-B result and decision:** accepted as the complete candidate-image and
  real-controller topology foundation.  `--candidate-out` emits exactly 512
  lower-case four-digit hex words: the latest 256-word D2F candidate plus the
  byte-identical accepted owner-one bank.  Its SHA-256 is
  `6f5713e22197d8c03bffeac070b3d9b9b2b2f7b20df98dbff4566d778b5e9177`;
  it has 44 owner-zero differences, zero owner-one differences and 222
  nonzero owner-zero words.  Two complete generator runs and their logs are
  byte-identical.  Readback reconstructs all 512 words exactly, and the
  accepted image remains SHA-256
  `59b6f86e1917c069762c2c67c3cfc33d3d1a7652c518e99f9f8437e019d4ebcf`.
  Literal, relative, symlink and existing hard-link aliases of the production
  image are rejected before any output write; an independent audit found the
  hard-link gap in the first implementation and accepted the corrected gate.
- **C2-B controller proof:** the bench derives its changed-PC mask only by
  comparing the two complete images, then replaces `u_ctl.ucode` at time 1,
  verifies all 512 words at time 2 and clocks first at time 5.  The real
  non-`TEST_PROGRAM` controller fetches all **782** instructions and every IR
  equals the candidate word.  The exact operation histogram is
  **172/158/8/29/8/0/1/406**; DONE terminates and pulses once.  All 44 changed
  PCs execute in every one of eight slots.  The first real visit to each
  changed PC receives a three-cycle hold, for 44 independent freezes with
  stable active/owner/slot/PC/IR/state-q, no state transaction and no control-
  EBR advance.  All 782 enabled state reads are checked against the pre-edge
  physical address and old memory word.  Two bench runs are byte-identical,
  and independent review found no PC/action list, semantic sidecar or weak
  origin/hold check.
- **C2-B gates and boundary:** the complete 19,728,640-case/131,087-
  transaction model, deterministic artifact repetition, production
  controller, direct wave-core, ARAM-hold, production wave/ARAM and candidate
  benches, isolated executor plus generic full/PREVIEW lint, `make test-psg`
  (fidelity PASS, 93 analysis tests, complete structural suite at 524/850 and
  4008/5103 with zero late flips), strict OpenSpec, pycompile, diff and
  production-image/RTL immutability pass.  Synthetic write data remains
  intentional.  This does not prove fixed write destinations, CAP_W51's
  active-bank 26/30 remap, A/B/N/O+H-C value transitions, wave/ARAM/DQ/
  multiplier causality, persistent commits, fold/public behavior, generic
  integration or a physical reduction.  No synthesis is claimed; the
  accepted whole-PSG baseline remains 7,504 routed LCs.
- **Next permitted C2-C:** execute candidate values, not another topology or
  Python mirror.  A bench-only semantic adapter must consume the real
  candidate PC/IR/state-q stream, implement the manifest's fixed write
  destinations including the action-qualified CAP_W51 word26-to-26/30 bank
  remap, and join existing RTL wave/ARAM/DQ/multiplier issue/take strobes under
  the same enabled-edge and external-hold rule.  It must compare only final
  persistent/fold/dry results against the accepted production-image oracle;
  no Trace record, semantic sidecar, partial PC graft or generic RTL edit is
  permitted.  Stop before atomic integration or physical claims unless every
  candidate PC, service transaction and final commit is mechanically joined.
- **C2-C result and decision:** rejected before RTL because the bounded
  bench-only composition has no source-derived enabled-successor contract at
  its first semantic edge.  After the fourteen oscillator and four parameter
  words have streamed in, candidate PC `0x13` / `NZ_OLD_LOAD_PAR_3` must use
  q20 to derive restart, selected-old, blend and noise context, launch the
  real DQ and multiplier work, and form values committed immediately by
  PCs `0x14..0x19`.  `validate_sample_d2fca_manifest()` proves widths,
  lifetimes, q provenance and eighteen fixed destinations but deliberately no
  value transition.  `validate_sample_b3b2a_slice_map()` starts at the later
  W1/W2/W3 frame and fills its roots with deterministic synthetic `source()`
  values.  `SampleImageMachine.begin_trace()` instead calls the complete
  direct `evaluate_sample_slot()` oracle and stores a `SampleTrace`; C2-B's
  real controller likewise still drives synthetic write data.  None is a
  legal implementation source for C2-C.
- **C2-C RTL audit:** the H-C compatibility wrapper overrides HOLD/CAP read
  addresses and therefore cannot carry the candidate q stream; the core must
  be instantiated directly.  No owner-zero action-to-fixed-destination/write-
  data decoder exists, and CAP_W51 remains `OP_EXEC word26` while the only
  26/30 parameter-bank remap is `OP_READ`-qualified.  Wave/ARAM, DQ and the
  multiplier have hold-correct cores but no D2F operand/result/tag adapter;
  ring, seven-node fold, leaf/dry publication and persistent/global commits
  remain private legacy-walker behavior.  Thus a nominal C2-C implementation
  must either inject `SampleTrace` values, retain a parallel semantic record,
  hand-graft selected legacy PCs, or silently become the full production
  adapter.  The first three violate the hypothesis and the last is not the
  bounded bench-only iteration claimed here.  No model, image or RTL changes
  land; accepted C2-B `4340adb` remains the scratch executable checkpoint.
- **Next permitted C2-C-A:** establish the missing complete source-bound
  semantic transition contract before another adapter attempt.  It must cover
  every owner-zero action from the eighteen literal state loads through the
  final fold/dry commit, bind each input/result to a real legacy-walker edge or
  hold-correct primitive issue/take, and contain no sampled result values,
  direct-oracle output, `SampleTrace`, working-record mirror or synthetic root.
  The contract must be executable by an RTL harness and checked against a live
  `psg_walk` oracle across enabled and held edges; a generated package may
  describe widths, slices, producers, destinations and guards, but not carry
  semantic values.  Only after complete action/PC/root coverage may the D2F
  adapter consume it.  Generic PSG/Tang RTL remains untouched until the board
  task releases ownership or an atomic integration boundary is coordinated.
- **C2-C-A active hypothesis:** a metadata-only contract generated from the
  complete D2F candidate and checked against deterministic traces from the
  live legacy walker plus the already hold-correct primitive RTL can close the
  missing source boundary without creating another semantic implementation.
  Reify the existing 30-root inventory as typed machine-readable metadata,
  mechanically attach every root to its candidate producer/consumer PC,
  literal q source, fixed destination and service class, and emit no value or
  expected-result field.  Add an optional structural trace to the existing
  full-PSG budget bench that exposes only enabled/held edge identity, slot,
  walker phase/CAP mask, state addresses/enables, real wave/ARAM/DQ/multiplier
  issue/take/done strobes, ring/fold phase and final commit strobes.  A checker
  shall join those rows to the candidate contract by decoded action and live
  source event, never by a hand-written phase table or sampled semantic value.
- **C2-C-A scope and baseline:** start from docs-only rejection `40591a5` and
  accepted executable C2-B `4340adb`.  Work only in
  `tools/psg_exec_model.py`, `rtl/psg_budget_tb.sv`, an optional focused
  binding checker/test, and this ledger.  `rtl/psg_exec.hex`, production RTL,
  generic walker/sequencer composition, Tang/H022 and `main` remain untouched.
  The full-PSG trace may observe hierarchical source signals but may not force
  data, alter scheduling, or feed anything back to the DUT.  Existing C1/C2-A
  RTL traces remain the authority for primitive freeze and executor
  wave/ARAM lineage; C2-C-A must consume their actual strobe schema rather
  than re-state their conclusions.
- **C2-C-A gates:** require all 61 owner-zero actions and every changed
  candidate PC to have one typed source binding; all 30 roots and 27 value
  groups must have complete producer/consumer/service/width/guard ownership;
  all eight slots must exercise every unconditional binding and each guarded
  binding must exercise both enabled and disabled classes.  State q origin,
  eighteen fixed writes, CAP_W51's pending 26/30 distinction, four wave and
  four ARAM contexts, both DQ chains, every multiplier role, ring reads,
  seven ordered folds, leaf/dry and persistent LFSR commits must appear in the
  joined real-RTL trace.  Require byte-identical repeated manifests/traces,
  C1 primitive freeze traces, C2-A issue/take queues, C2-B candidate control,
  full/PREVIEW lint, `make test-psg`, strict OpenSpec, image/production-RTL
  immutability and `git diff --check`.  Reject if a row carries a semantic
  value, if the checker imports `SampleTrace`/`evaluate_sample_slot`, if any
  candidate action/root remains prose-only, or if source instrumentation
  perturbs the existing regression output.  This is a source-contract gate,
  not adapter equivalence, integration, synthesis or area credit.
- **C2-C-A result and decision:** accepted as the complete metadata-only
  candidate-to-source binding foundation.  `--binding-out` emits one
  deterministic `psg_exec_binding_v1` artifact with 61 typed action rows,
  44 changed-PC bindings, 30 roots in 27 value groups and eighteen fixed
  writes.  All 44 changed PCs are explicit: 26 name a generated owner-zero
  action and eighteen name a fixed common-HOLD edge.  The source audit found
  and removed 34 fabricated `READ_PRIME` occurrences caused by decoding the
  zero-filled post-DONE ROM tail; the only reachable `READ_PRIME` is PC 1.
  Retired `STORE_0_10 -> CAP_W1` and `STORE_13_23 -> CAP_W0` aliases remain
  explicit and have no fictitious PCs.  Two complete model runs produce the
  same manifest SHA-256
  `a18fa58db07ea66fc3f0ac72cf6fd072718f3e9a2aee9dfaf5ace616e2d6d7`;
  the complete 19,728,640-formula/131,087-transaction model still reports the
  accepted image byte-identical.
- **Live HX8K source join:** the handoff's preliminary trace command used
  `MULTIPUMP_P=0`; it is not target evidence because `target_psg.sv`
  instantiates `MULTIPUMP(1)`.  The accepted trace is rebuilt with the real
  radix-2 multi-pumped target schedule.  Its focused built-in/noise/wavetable/
  reverb/silent profile emits 76,295 structural rows over 200 complete
  samples, byte-identical in two runs with SHA-256
  `19b0787d31e604842e7194111d22b00d12bec53ad7cff6a09ffb846b39d53b70`.
  The independent checker observes all eight slots, both values of wavetable,
  reverb, audible and blend guards, 28,800 exact state reads and 25,600 state
  writes, both parameter banks including the word-26/30 distinction, four
  wave plus four ARAM contexts, both DQ chains, all ten multiplier roles,
  ring read/current/old/write edges, 1,400 ordered fold-node starts, 1,600
  leaf and LFSR commits and 200 dry commits.  It rejected and corrected an
  initial false classification of `STORE_LEAF_LO/HI` as legacy state writes:
  words 48/49 are candidate destinations whose real source is the legacy leaf
  commit, not existing legacy state memory.
- **Joined primitive/executor evidence:** C1 multiplier and DQ traces are
  independently byte-identical at SHA-256
  `57afcd22903abca09f9b9c193b6e745b635fc443c71490cda9c9c5fcdd918f08`
  and `ae4dbaee54268461de475ed7483ba95f9edfecf9c68433584799666d4d861741`;
  the checker reconstructs 105 slow plus 630 fast multiplier pre/post pairs,
  exactly six fast pairs per slow edge, 189 frozen pairs, 61 DQ pairs and
  fifteen CE-held pairs including rejected starts and terminal relaunch.  The
  accepted-image C2-A trace is byte-identical at SHA-256
  `ac07e65c06c9fbc707f35447e1d160a26688ea1e23e6e34f293ec50df0b44e59`;
  4,404
  pre/post pairs retain 4,368 real state-read origins, 36 held edges, 224 wave
  and 96 ARAM issue/take joins.  No checker row imports or calls
  `SampleTrace`, `evaluate_sample_slot` or a semantic sample-value oracle.
- **C2-C-A regression gates and boundary:** the complete C2-B candidate bench
  still passes 512-word readback, all 44 changed PCs in all eight slots, 44
  independent three-cycle holds, 782 fetch/state origins and the unchanged
  172/158/8/29/8/0/1/406 opcode histogram.  Direct wave-core and ARAM-hold
  benches, full/PREVIEW/executor lint, `PATH=/opt/homebrew/bin:$PATH make
  test-psg` (fidelity PASS, 93 analysis tests, 524/850 walk deadline and
  4008/5103 tick deadline with zero late flips), strict OpenSpec, deterministic
  hashes, `git diff --check` and production RTL/image immutability pass.  This
  accepts only a structural source contract.  It does not execute candidate
  semantic values, prove persistent/fold/public result equivalence, integrate
  the adapter, alter generic PSG/Tang RTL, synthesize, route, time or earn area
  credit; the measured whole-PSG baseline remains 7,504 routed LCs.
- **Next permitted C2-C-B:** consume the accepted binding artifact in one
  bench-only adapter skeleton driven solely by the real candidate controller
  PC/IR/state-q and existing primitive issue/take interfaces.  First prove
  fixed destination selection, CAP_W51's action-qualified word-26/30 read and
  enabled/held transaction ownership with no write-data semantics.  Do not
  add a working-record mirror, sampled values, a generic production switch or
  claim persistent/fold/dry equivalence.  Commit that address/control boundary
  separately before any value equations; reject if it requires a second
  action schedule, a result register or a generic walker edit.
- **C2-C-B active hypothesis:** starting from clean accepted source-contract
  commit `3e7f37e`, generate one 128-entry action-indexed control map directly
  beside `psg_exec_binding_v1`.  Each eight-bit entry may carry only a fixed-
  commit-valid bit, the six-bit fixed destination and one CAP_W51 active-bank
  read flag; it carries no write data, operand, sampled value, phase or PC.
  A new bench-only adapter shall index that map with the real candidate
  controller action, qualify it with active, owner, hold and op, and expose
  only commit-valid/destination plus CAP_W51's OP_EXEC word-26-to-active-26/30
  read override.  Execute the complete 512-word candidate controller with
  both parameter banks, all eight slots and a held edge at every one of the
  eighteen fixed commit actions plus CAP_W51.  Require every observed binding
  to equal the generated JSON manifest, every unbound action to remain inert,
  and controller PC/IR/state-q/termination counts to remain unchanged.  Scope
  is `tools/psg_exec_model.py`, one new isolated RTL testbench, this ledger and
  generated `build/` evidence only.  Do not edit `psg_execmove.sv`, accepted
  image, production/generic PSG or Tang files.  Reject if the decoder needs a
  PC table, semantic write data, a working-record/result register, an extra
  state transaction, or cannot suppress and resume every output under hold.
- **C2-C-B result and decision:** accepted as the isolated address/control
  boundary.  `--binding-control-out` emits exactly 128 lower-case byte words
  beside the unchanged 512-word candidate and metadata manifest.  Its
  SHA-256 is
  `a9233d6ddec85fdcf531d215bc40144c7254e742d290f9413c21743140333d1c`:
  eighteen entries contain fixed-commit plus their six-bit destination, one
  disjoint CAP_W51 entry contains the active-bank-read flag, and the other
  109 entries are zero.  Generator assertions join every commit entry back
  to one manifest occurrence, its candidate PC, `OP_WRITE` and destination;
  CAP_W51 joins to its sole `OP_EXEC word26` occurrence.  Two generated
  candidate/manifest/control sets are byte-identical.  Direct, symlink and
  existing-hard-link output aliases are rejected before mutation, including
  a control hard link to `rtl/psg_exec.hex`; the production image remains
  SHA-256 `59b6f86e...`.  The audit also fixed the case where an existing
  control artifact was checked against an as-yet absent JSON output.
- **C2-C-B live-controller proof:** the first run rejected an invalid family-
  based op rule at PC `0x1d`: action `0x22` is CAP_W0 but the candidate
  deliberately encodes its final commit as `OP_WRITE`, not the usual CAP
  `OP_EXEC`.  The retained adapter therefore treats the generated valid bit
  as authoritative and separately requires `OP_WRITE`; only CAP_W51 requires
  `OP_EXEC word26`.  It drives the real controller's existing read- and write-
  override inputs rather than parallel bench muxes.  Both parameter banks execute all
  eight slots with 782 instructions and state-q origins each, the unchanged
  `172/158/8/29/8/0/1/406` histogram, all nineteen bindings in every slot and
  one three-cycle hold per binding per bank (**38 holds**).  Hold, inactive,
  owner-one, wrong-op and all 109 unbound action probes expose zero valid,
  destination, override and read-word outputs.  No extra state transaction,
  write data, result register, PC table or working-record mirror exists.
- **C2-C-B regression gates and boundary:** the complete
  19,728,640-formula/131,087-transaction model, independent literal candidate/
  JSON/control audit, accepted C2-C-A 76,295-row source join, C1 primitive
  traces and C2-A issue/take joins pass.  C2-B again proves the complete
  candidate image, 44 changed PCs in all slots and 44 independent holds;
  production execwave reports 4,368 state origins plus 224 wave and 96 ARAM
  joins, and direct wave/ARAM benches pass.  Full HX8K-multipumped, PREVIEW
  and new executor lint pass; `PATH=/opt/homebrew/bin:$PATH make test-psg`
  passes fidelity, 93 analysis tests and the complete structural suite at
  524/850 sample clocks and 4008/5103 tick clocks with zero late flips.
  Strict OpenSpec, deterministic hashes, `git diff --check` and production
  RTL/image immutability pass.  This earns no candidate value, service-result,
  persistent/fold/dry, generic integration, synthesis or area claim; the
  accepted whole-PSG baseline remains **7,504 routed LCs**.
- **Next permitted C2-C-C:** replace the missing semantic expected-value source
  with one complete value-bearing trace from the existing live RTL, not with
  equations in Python or a partial candidate executor.  Candidate PC `0x13`
  consumes parameter `q27`, selects restart/old context and launches live DQ
  plus old-noise multiply work before PCs `0x14..0x1b` commit the first six
  record values.  C2-C-B proves those destinations but supplies no legal value
  oracle: `SampleImageMachine` still imports `SampleTrace.final_words`, while
  the accepted metadata manifest intentionally contains no values.  Do not
  implement candidate write data until every root and commit can be compared
  to an observed legacy/primitive producer and consumer.
- **C2-C-C active hypothesis:** extend the proof-only target trace with a
  deterministic `psg_legacy_value_v1` stream carrying actual pre/post-NBA
  values at all 30 C2-C-A roots, their 27 value-group producer/consumer joins
  and all eighteen fixed-write source events.  Values must come directly from
  state-q/state-write, wave/ARAM, DQ, radix-2 multi-pumped multiplier, ring,
  fold, leaf/LFSR and dry-publication RTL signals.  A new checker may pair,
  tag and compare observed rows, but may not evaluate a waveform, arithmetic
  formula, record transition, `SampleTrace` or `evaluate_sample_slot`.
  Compose the existing C1 and C2-A pre/post traces where they already expose
  the authoritative primitive value; do not duplicate them with bench labels.
  The output is a live value oracle for the future adapter, not an executor.
- **C2-C-C scope and gates:** start from clean accepted C2-C-B `fe92b79` and
  work only in proof instrumentation/checking, the metadata generator if a
  typed trace key is missing, and this ledger.  Accepted image, executor
  production modules, generic PSG, main and Tang remain immutable.  Require
  both parameter banks, all eight slots, built-in/wavetable, noise/brown,
  restart/no-restart, clear, audible/hidden/stopped, reverb and blend guards;
  every root and fixed write must have an observed producer, consumer, width,
  guard and value identity.  Held edges must preserve every carried value and
  emit no issue/take/commit.  Require byte-identical repeated traces, the full
  C2-C-A structural join, C2-C-B address bench, C1/C2-A trace gates, full/
  PREVIEW lint, `make test-psg`, strict OpenSpec and production immutability.
  Reject if any expected value is reconstructed in Python, sampled from the
  direct oracle, inferred from a PC/action label without a live strobe, or if
  one of the 30 roots/eighteen commits remains prose-only.  No adapter,
  persistent/fold/dry equivalence, generic integration, synthesis or area
  claim is permitted in this iteration.
- **C2-C-C accepted live-value foundation:** proof-only instrumentation emits
  adjacent `psg_legacy_value_v1` pre/post-NBA rows from the real multipumped
  legacy target.  The metadata manifest now types distinct physical producer
  and consumer observations for all **30 roots / 27 value groups**, binds the
  **18 fixed writes** to their real sixteen-bit source and commit observations,
  fixes fold-leaf destinations at low word 48/high word 49 and records 75
  action-specific guard obligations.  The checker streams the trace rather
  than loading or evaluating a slot: it compares live state-memory movement,
  DQ/multiplier/wave/ARAM issue-result-take identities, current/old ring
  transactions keyed by kind/slot/recomputed physical address, ordered fold
  stack writes, leaf/LFSR retention and `dry16` publication.  Held edges freeze
  every carried value and emit no transaction.  It contains no waveform,
  filter, record-transition or candidate-write evaluator.
- **C2-C-C deterministic evidence:** two current generator runs are
  byte-identical at candidate SHA-256 `6f5713e2...`, control
  `a9233d6d...` and manifest `438d85a0...`.  Two fresh 400-sample structural
  traces are byte-identical SHA-256 `d9b79b51...` (**152,893 rows** each);
  two live-value traces are byte-identical SHA-256 `d5cdf3ae...`
  (**385,792 rows / 192,896 pairs** each).  The structural checker observes
  57,600 state reads, 51,200 writes and 2,800 fold nodes.  The value checker
  proves all roots/groups/writes in both banks and all eight slots, 43,459
  balanced service transactions, 4,914 fold-stack writes, 400 dry/PCM
  publications, exactly four right-censored end-of-trace LFSR producers and
  three explicit held pairs.  C1 contributes only primitive cadence/freeze
  evidence; every value identity comes from this live RTL stream.
- **C2-C-C conviction and regression gates:** missing guard obligations,
  leaf 49-to-48 aliasing, same producer/consumer endpoints, forbidden semantic
  fields, current/old ring-address corruption, a self-consistent wrong ring
  identity, missing guard or bank/slot classes, corrupt PCM and an unmatched
  DQ result all reject.  Two independent read-only audits accept the current
  `build/c2cc-*` evidence and explicitly reject older `build/r84-c2cc/*`
  artifacts as stale.  Full/PREVIEW/executor lint, Python compilation,
  `PATH=/opt/homebrew/bin:$PATH make test-psg` (fidelity, 93 analysis tests,
  524/850 sample clocks and 4008/5103 tick clocks with zero late flips),
  strict OpenSpec, `git diff --check` and production image/RTL immutability
  pass.  The accepted image remains SHA-256 `59b6f86e...`.
- **C2-C-C boundary and next permitted C2-C-D:** this accepts only the
  manifest-bound live source/value oracle.  It earns no candidate write data,
  adapter equivalence, persistent/fold/public equivalence, generic
  integration, synthesis, area, routing, timing or render claim.  The next
  bounded step may build one isolated fixed-write value adapter from the
  candidate's addressed state/service inputs and D2F physical pool, then
  compare its eighteen action-qualified outputs to this oracle.  The oracle's
  legacy values may appear only at the comparison boundary, never as adapter
  inputs; no production image, generic RTL or main landing is permitted until
  the complete isolated adapter passes every bank/slot/guard/hold class.
- **C2-C-D pre-RTL audit and rejection:** the proposed fixed-write adapter has
  no legal candidate value input yet.  The C2-C-C manifest's eighteen sources
  are final legacy observations: fourteen ordinary `STATE_WRITE/pre/state_wd`
  values, the W0/W1 legacy noise-lowpass/phase results and the two legacy leaf
  slices.  They are comparison outputs, not candidate producers.  The existing
  `psg_execbind_adapter` is deliberately address/control-only and its real
  candidate-controller bench still supplies synthetic `{slot,action,pc}` write
  data.  `psg_execwave[_core]` owns retained H-C wave context plus wave/ARAM
  issue/take/address signals, but no result pool or final record value.  No RTL
  module owns A18/B18/N17/O17, retained Q/T/C/I/D state, or a complete tagged
  DQ/multiplier/wave/ARAM/ring/fold result interface.
- **Write-by-write availability:** the six early stores at PCs
  `14/15/16/17/19/1b` have no exact-edge D2F value allocation; W0/W1 at
  `1d/1e` have legacy observations and capacity ingredients but no candidate
  noise/phase producer; nine late writes at
  `27/28/2a/2d/39/3c/3d/4c/4d` have only abstract q-plus-named-field sets in
  D2F-C-A and therefore still depend on nonexistent pool transitions.  PC
  `29` has an additional ordering defect: its required blend count is born in
  the abstract manifest at PC `2e`, after the PC `29` write.  Deriving it from
  q17 plus restart/saturation may be possible, but no exact proof or RTL owns
  that relation.  The two leaf writes additionally require retained
  `sample_f[16:0]` plus audible through both commit edges.
- **Why C2-C-D cannot be implemented honestly:** A18+B18+N17+O17 currently
  exists only in Python `Pool`, `row()` and `LiveField` capacity/lifetime
  assertions.  Those prove snapshots fit, not the enabled-edge transition
  relation that produces the next snapshot.  Their source/consumer strings
  are descriptive metadata, not executable slice assignments.  Both
  independent read-only audits therefore find **0/18** fixed writes with a
  non-legacy candidate semantic producer in existing RTL.  An adapter written
  now would have to feed final legacy values back as inputs, recreate the
  forbidden 202-record-bit plus 42-parameter-bit mirror, or invent unproved
  transition equations.  C2-C-D is rejected docs-only; no model, image, RTL,
  trace, integration or physical claim changes.
- **Next permitted C2-C-D1 prerequisite:** build the isolated physical-pool
  substrate before the fixed-write adapter.  It must own literal
  A18/B18/N17/O17 and retained Q/T/C/I/D slices; consume only tagged
  prior-address `state_q` and real service result/take strobes; define every
  enabled-edge slice write, overwrite/death point and action/guard; freeze the
  complete state and suppress transactions on hold; and emit the eighteen
  action-qualified candidate writes.  First generate a typed literal-slice
  transition manifest and prove transport/alias/lifetime coverage against the
  C2-C-C stream without semantic arithmetic or final legacy values as inputs.
  Only that manifest may drive one isolated RTL implementation.  Do not create
  a second Python semantic executor, per-write result mux or generic handoff.
- **C2-C-D1 active hypothesis:** one action-keyed literal-slice transition
  manifest can turn the existing capacity snapshots into an executable pool
  contract without adding semantic equations.  Its physical containers are
  exactly A18/B18/N17/O17 plus retained Q16/T6/C7/I6/D3.  Every enabled-edge
  assignment must name the controller action, exact destination slice, prior
  value/death rule and one typed source observation that is either the
  preceding synchronous `state_q` word or a transaction-bound service take.
  Concatenation, slicing, sign extension and bit-preserving relocation are
  transport; any add, clamp, select or filter result must instead arrive from
  a named live service result.  The manifest must be complete across load,
  NZ, W0--W84, record commits, leaf commits and fold before RTL begins.
- **C2-C-D1 scope and reject gates:** first audit the C2-C-C stream for every
  source bit required by the D2F-B/D2F-C-A rows and add proof-only raw-signal
  observations only where a real legacy producer already exists.  Reject a
  row if its source is prose, a final legacy write value, a Python expression
  or an untagged service result.  Then prove unique slice ownership, exact
  overwrite/death, no read-before-write, all path guards, both banks/eight
  slots, and complete reconstruction of the eighteen oracle outputs at the
  comparison boundary.  Held edges must freeze the entire manifest state and
  emit no source take or commit.  Require deterministic repeated manifests and
  traces, mutations for slice alias/source loss/late birth/guard loss/hold
  drift, C2-C-C/C2-C-B/C1/C2-A gates, full/PREVIEW/executor lint,
  `make test-psg`, strict OpenSpec and production immutability.  No adapter
  RTL, candidate image, generic integration, synthesis or area credit is
  permitted until this manifest closes without a legacy final-value input.
- **C2-C-D1-A active hypothesis:** materialize the previously local D2F-B
  packing rows, D2F-C-A path lifetimes and fold lifetimes as one deterministic
  proof artifact beside the complete C2-C-C root catalog.  The artifact is a
  requirements inventory, not a transition manifest: it may preserve the
  existing source descriptions only as explicitly unbound requirements and
  must not infer a source from matching prose.  It must expose every literal
  container/slice, path, birth/death edge, consumer and all 30 observed roots
  so the next source-completeness join is mechanical rather than hand-copied.
  Scope is `tools/psg_exec_model.py`, generated `build/` evidence and this
  ledger only.  Reject if any D2F row is omitted, any physical slice changes,
  generated output is nondeterministic, or the artifact claims a state-q or
  service binding it has not proved.  No proof-bench, production/image RTL,
  adapter, synthesis, area or integration claim is permitted in D1-A.
- **C2-C-D1-A result and decision:** accepted as a requirements-inventory
  foundation only.  The model now emits schema
  `psg_exec_pool_requirements_v1`: all **15** D2F-B packing rows, **32**
  built-in, **35** wavetable and **11** fold lifetime rows over the exact
  A18/B18/N17/O17+Q16/T6/C7/I6/D3 containers, beside all **30 roots / 27
  groups**.  Every packing row and lifetime is explicitly `unbound`; the
  artifact contains no `source_binding` and reports `bound_fields: 0`, so it
  cannot be mistaken for the missing transition proof.  Two independent
  generations are byte-identical at SHA-256
  `362e541eda351c27520c3cf5964141a16926241c740884fa2a7bc2b1d48d16a7`.
  Direct output aliasing to `rtl/psg_exec.hex` rejects; the production image
  remains SHA-256 `59b6f86e...`.  The full model, C2-C-C structural/value
  checkers (152,893 structural rows; 192,896 value pairs; 75 guard
  obligations; 43,459 service transactions), Python compilation, strict
  OpenSpec and diff checks pass.  No proof-bench/RTL/image source changed and
  no semantic, adapter, synthesis, routing, timing, render or area claim is
  made.
- **Next permitted C2-C-D1-B:** consume only this generated requirements
  inventory and the accepted C2-C-C manifest.  Bind each requirement either
  to an exact prior-address `state_q` word/slice, a transaction-bound root
  producer observation, or a preceding already-bound physical slice.  Keep
  every unmatched requirement explicit; do not use source prose, direct
  `record_commit`, `state_wd`, `final_words` or a Python expression as a
  binding.  The output is still an inventory: no pool executor or RTL until
  every load/service/transport source closes and mutations reject a lost row,
  wrong slice, direct-final-value source and false root-name match.
- **C2-C-D1-B active hypothesis:** make the D1-A inventory independently
  slice-checkable, then perform a structured source-completeness join without
  executing one pool transition.  D1-A records each packing fragment's width
  but not its logical-field or physical-container bit offset; canonical JSON
  key sorting therefore destroys the only implicit cross-container order and
  makes the required wrong-slice mutation unprovable.  Upgrade the generated
  requirements schema with explicit `field_lsb` and `container_lsb` on every
  packing fragment, preserving all fifteen rows and capacities.  Extend the
  existing structural binding checker to consume that artifact plus the
  accepted C2-C-C manifest and classify every packing field and path lifetime
  as exactly one of prior-address `state_q`, transaction-bound root slice,
  preceding physical slice or explicit unmatched.  Joins must use complete
  structured identities, never source-description text or a root name alone.
  The output remains a source-completeness inventory: it carries no semantic
  value, arithmetic, enabled-successor transition or write-data producer.
- **C2-C-D1-B scope and reject gates:** work only in
  `tools/psg_exec_model.py`, `tools/psg_exec_bindings.py`, generated `build/`
  evidence and this ledger.  Require deterministic repeated output, exact
  reconstruction of every D1-A row/piece/lifetime/root, and in-memory
  convictions for a missing row, wrong slice, forbidden direct final-value
  source and a same-name-but-wrong structured root.  Keep every unclosed
  source explicit and count it; reject `record_commit`, `state_wd`,
  `final_words`, Python expressions, prose matching or any binding wider than
  its observed physical source.  Re-run the accepted C2-C-C structural/value
  checkers, Python compilation, strict OpenSpec, production-image immutability
  and diff checks.  No proof-bench, adapter RTL, image, generic integration,
  synthesis, routing, timing, render or area claim is permitted.
- **C2-C-D1-B result and decision:** accepted as a deterministic negative
  source-completeness audit; its source-complete hypothesis is rejected.
  Requirements schema `psg_exec_pool_requirements_v2` now gives every packing
  piece explicit logical/physical offsets and anchors the complete packing
  and live-field layouts at SHA-256 `242bfc81...` / `55bb4b04...`.  The
  structured source plan is independently anchored at `c5d27461...`.  Two
  complete 19,728,640-formula / 131,087-transaction model runs produce
  byte-identical requirements SHA-256 `5a7b9809...`; two joins against the
  accepted C2-C-C manifest `438d85a0...` and independent 400-sample traces
  produce byte-identical source inventories SHA-256 `95619e61...`.
  All **154/154 packing fields are explicitly unmatched** because no
  enabled-edge physical transition exists.  Exactly **6/78 lifetimes bind**:
  four exact-edge multiplier-root slices and the active-bank q26/q30 damp
  slice on both paths; the other **72/78** remain explicit unmatched.  Thus
  all 226 unclosed rows are visible rather than inferred from prose, names or
  final legacy values.  Six in-memory convictions reject missing rows, wrong
  packing/live slices, a final-value injection, a false root identity and a
  wrong root target; an independent read-only audit also rejects attacks that
  recompute the mutated self-digests or alter the source maps.  The accepted
  production image remains SHA-256 `59b6f86e...`.  D1-B proves capacity and
  observation are not the missing mechanism: the missing object is the
  complete enabled-edge transition relation.  No D1-derived RTL hypothesis
  exists yet.
- **Next permitted C2-C-D1-C:** build a declarative edge-SSA obligation graph
  over the complete owner-zero pool-affecting execution closure, not merely
  the 44 changed PCs.  The accepted manifest has 114 action occurrences;
  every executable occurrence must either name typed destination/source
  slices, exact pre-edge operands, guard and one closed primitive kind, or be
  proved retain-only with no source take or write.  Leaves may be only tagged
  prior-address `state_q`, C2-C-C transaction roots, constants or preceding
  physical slices.  Transport kinds are limited to retain, slice,
  concatenate, extend and bit-preserving relocation.  Arithmetic/select/
  clamp/filter work becomes a named primitive obligation, not an evaluated
  Python expression.  Reject free-form expressions, trace-driven state
  mutation, a sample loop, final legacy write inputs, incomplete action
  coverage, guard gaps, multiple slice definitions, read-before-write and
  hold drift.  D1-C remains structural only and may not compute a pool state
  or candidate write value.
- **C2-C-D1-C active hypothesis:** the complete candidate image has **222**
  executable owner-zero words and admits one mechanically checkable coverage
  partition: **114 action occurrences**, **56 fold-step HOLDs**, **4
  ring-service HOLDs**, **23 pool-retaining elapsed HOLDs** and **25 control
  edges**.  Generate one row for every nonzero candidate word, join the 114
  action rows to the accepted C2-C-C action occurrence rather than only its 44
  changed PCs, and derive the fold/ring classes from exact labels, word tags
  and predecessor actions.  A pool-retaining edge may still carry a literal
  state-address prime, but it must have no pool definition, service take or
  state/candidate write.  Every row must name its exact instruction, enabled
  guard, pool effect, source/write permissions and one closed retain/control
  kind or one explicitly unproved named primitive obligation.  External hold
  is a separate global identity edge that advances no PC or pool slice and
  emits no take/write.
- **C2-C-D1-C scope and reject gates:** work only in
  `tools/psg_exec_model.py`, `tools/psg_exec_bindings.py`, generated `build/`
  evidence and this ledger.  Upgrade the D1 requirements artifact to an
  explicit snapshot/event schema before joining it: each packing row must
  carry structured path, snapshot, old-source and restart classes, and each
  live lifetime must carry exact birth/death PCs.  Do not parse event identity
  from packing-row prose.  Emit a separate deterministic edge-obligation
  artifact; reject a missing/duplicate edge, wrong action occurrence, wrong
  fold/ring tag, hidden take/write on a retain edge, guard loss, slice alias,
  read-before-birth, free-form expression, semantic value field, sample loop,
  trace-driven state mutation or final legacy value input.  Require the
  physical packing/lifetime layouts and C2-C-C manifest to remain unchanged,
  repeated byte-identical generation, independent reconstruction from the
  candidate image and accepted manifest, mutation convictions, the full model
  and C2-C-C source/value gates, `make test-psg`, Python compilation, strict
  OpenSpec, production-image immutability and diff checks.  No RTL, candidate
  image, adapter equivalence, synthesis, routing, timing, render or area claim
  is permitted in D1-C.
- **C2-C-D1-C result and decision:** rejected before commit as an edge-SSA or
  transition-completeness proof; the experimental model/checker changes are
  reverted.  The bounded positive result is a static instruction-site
  partition only: the candidate still has exactly **222** nonzero owner-zero
  words split uniquely into **114 action / 56 fold-step HOLD / 4 ring HOLD /
  23 other HOLD / 25 control** sites, and two generated static artifacts were
  byte-identical.  Both independent audits found that the graph named PCs,
  not enabled successor edges.  It had no branch-successor guards or dynamic
  slot occurrences, no explicit pool reads/definitions, and no exact
  service issue/result/take identity.  Its `q_source()` skipped control
  instructions even though `psg_execctl` issues a synchronous state read on
  every enabled instruction: at least **22** action operands at fold-control
  boundaries were therefore false or incomplete.  The requirements-v3 event
  PCs were hard-coded and self-digesting rather than related to action phase;
  fold input assembly, STEP8 correction and intermediate/root DONE meanings
  remained ambiguous.  Stronger colluding mutations of action q sources and
  fixed destinations, arbitrary labels, an unchecked semantic payload and a
  pool read before birth survived.  The unchanged D1-B source inventory and
  C2-C-C value gates still passed, and `make test-psg` passed, but those gates
  cannot repair the missing transition relation.  No RTL/image/integration or
  physical claim changes, and no D1-derived RTL hypothesis exists.
- **C2-C-D1-C-A active hypothesis:** prove the controller edge relation before
  returning to pool SSA.  Emit every reachable enabled transition occurrence,
  not one row per static PC: predecessor PC/slot, exact instruction, branch
  guard and successor PC/slot, effective state-read address after every
  owner/action override, and the successor edge on which that registered
  `state_q` becomes available.  Derive the relation from the candidate image
  plus literal `psg_execctl`/`psg_execmove` address rules; anchor the accepted
  candidate and C2-C-C manifest rather than accepting colluding mutations.
  The target is the future direct-core contract: instruction HOLD words select
  their literal address/step tags, parameter OP_READs select active-bank
  24--27/28--31, and action-qualified CAP_W51 selects q26/q30.  Do not apply
  the current H-C compatibility wrapper's blanket HOLD-to-word10 override.
  External hold must be a separate self-edge with no controller advance,
  memory enable or service transaction.  First prove complete reachability,
  unique successor guards, all eight slot classes, exact 782-cycle execution,
  and mutations for branch target, slot destination, HOLD prime word, loop
  target, read address/availability edge and hold drift.  C-A remains
  controller/address only: no D2F lifetime sites, pool reads/definitions,
  primitive values, adapter, RTL, image, synthesis or area claim.
- **C2-C-D1-C-A result and decision:** accepted as the bounded future
  direct-core controller/address-obligation foundation.  The model emits, and
  an independent closed checker reconstructs from the anchored candidate and
  C2-C-C manifest,
  **782 enabled occurrences per parameter bank / 1,564 total** with all **222**
  static owner-zero PCs and all eight slot classes reached in each run.  Each
  bank contains 172 READ, 406 EXEC, 158 WRITE, 29 SLOT, eight JUMP, eight
  BRANCH and one DONE occurrence; its state-read classes are 742 literal
  instruction words, 32 current-RTL active-bank parameter reads and eight
  future action-qualified CAP_W51 q26/q30 address obligations.  Every enabled
  occurrence records its exact predecessor q origin, state address and
  successor availability edge.  Of 316 write occurrences, **256** are the
  sixteen manifest-anchored remapped fixed-write address obligations across
  both banks; the 32 leaf and 28 fold writes already use their literal 48/49
  destinations.  No write data is present.
  External hold is a separate self-edge with controller/microcode/state/service
  enables disabled and state_q retained.  The canonical artifact is SHA-256
  `f86698f6...`; independent A/B generation, source inventory, full checker and
  value logs are byte-identical.  Hard anchors remain candidate `6f5713e2...`,
  C2-C-C manifest `438d85a0...`, owner-zero words `521f0bbd...` and production
  image `59b6f86e...`.  Ten mutations are convicted: branch target 50->51,
  fold slot destination, PC1c word10->11, loop jump 0->1, read address,
  q-availability edge, external-hold drift, manifest/graph collusion, unknown
  schema field and numeric bool/int type coercion.  A first audit found that
  Python object equality admitted the last class; acceptance uses canonical
  JSON byte equality and the repaired checker was independently re-audited.
  The full model, C2-C-C source/value proofs, unchanged D1-B source inventory,
  Python compilation and `make test-psg` pass (524/850 sample clocks,
  4008/5103 tick clocks, zero late flips).  Production/candidate images and
  generic RTL remain untouched.  Production `psg_execmove` implements the
  parameter-bank override, but does **not** yet implement candidate CAP_W51 or
  the sixteen remapped owner-zero write-address sidebands; this artifact proves
  their manifest-anchored obligation, not current-RTL equivalence.  This proves
  no pool definition/use, service value, primitive arithmetic, adapter,
  integration, synthesis, timing,
  routing, render or area property, and yields no RTL change hypothesis.
- **C2-C-D1-C-B active hypothesis:** the accepted C-A occurrence graph can
  carry one literal-slice SSA relation without reintroducing a semantic
  executor.  Every D1 physical definition/use and every C2-C-C service
  issue/result/take must bind to an exact dynamic key
  `{bank,slot,occurrence,pc,pre|post}`; symbolic W/NZ/fold names, copied word
  numbers and static PCs are not identities.  Definitions are limited to
  tagged prior-edge state_q slices, transaction-bound C2-C-C root slices,
  constants and already-defined physical slices.  Transport may retain,
  slice, concatenate, extend or relocate bits.  Select, add, clamp, filter,
  multiply, divide and fold work remains a named primitive obligation with no
  Python result value.  The graph must close both parameter banks, all eight
  slots, all path guards, every overwrite/death and all eighteen fixed-write
  comparison boundaries without consuming `state_wd`, `record_commit`,
  `final_words` or another legacy final value.
- **C2-C-D1-C-B1 active foundation:** first replace the remaining symbolic
  lifecycle vocabulary with a closed event dictionary.  Mechanically join all
  30 C2-C-C root producer/consumer events and all 78 D1 live-field birth/death
  names to exact C-A occurrence/phase sets, including the seven ordered fold
  nodes, STEP8 correction, low/high result writes and root FOLD_FINISH.  Each
  event row must state its bank/slot/guard coverage and whether it defines,
  consumes, issues, completes or takes a transaction; it must not carry a
  value or pool update.  Anchor C-A `f86698f6...`, candidate `6f5713e2...`,
  C2-C-C manifest `438d85a0...`, packing/live layouts `242bfc81...` /
  `55bb4b04...` and production image `59b6f86e...`.  Reject an ambiguous or
  missing event, wrong pre/post phase, bank/slot loss, name-only root match,
  copied q word, hold drift, colluding input/output mutation, unknown field or
  bool/int coercion.  Only after B1 closes may B2 add literal slice
  definitions/uses and enforce no-read-before-unique-definition.
- **C2-C-D1-C-B scope and reject gates:** work only in
  `tools/psg_exec_model.py`, `tools/psg_exec_bindings.py`, generated `build/`
  evidence and this ledger.  Require deterministic A/B generation,
  independent reconstruction from anchored inputs, mutation convictions, the
  full model, D1-B inventory, C2-C-C structural/value proofs, Python
  compilation, `make test-psg`, strict OpenSpec, image immutability and diff
  checks.  No candidate/production RTL or image, adapter, generic integration,
  synthesis, timing, routing, render or area claim is permitted.  Any later
  RTL hypothesis must first be sent to the coordinating optimization task.
- **C2-C-D1-C-B1 result and decision:** accepted as the bounded dynamic-event
  dictionary foundation only; D1-C-B remains unproved.  Schema
  `psg_exec_d1_event_dictionary_v1` independently reconstructs **60 root
  endpoints / 1,216 dynamic occurrences**, **22 transaction completions / 352
  exact completion occurrences**, **156 lifetime endpoints / 2,452
  occurrences** and **85 fold events / 170 occurrences**.  Every reference
  uses the complete `{bank,slot,occurrence,pc,pre|post}` key.  Transaction
  issue, result completion and take phases are separate, so pre-edge DQ/ring
  completions cannot alias their post-edge issue.  Both parameter banks and
  all eight sample slots are covered where the event is per-slot.  `PRE_W15`
  is the post-edge of PC35/CAP_W6, sample `DONE` is the post-edge of
  PC77/STORE_LEAF_HI, and each ordered fold node is anchored to its literal
  input slot, `(base+8)+STEP1..8` action-0x70 word tag, low/high write and final
  PC220/FOLD_FINISH action rather than to an unproved name alone.  Composite
  leaf, sixteen-record and per-slot-increment consumers remain distinct.
  Two complete 19,728,640-formula / 131,087-transaction model generations are
  byte-identical at SHA-256 `5b178017...`; the independently regenerated D1-B
  source inventory remains `95619e61...`.  Ten mutations reject a missing or
  duplicate dynamic event, wrong completion phase, bank/slot loss, name-only
  join, copied predecessor PC, hold drift, colluding controller/dictionary,
  unknown field and numeric Boolean coercion.  Both full structural checkers
  pass 152,893 legacy rows, the C2-C-C value checker passes 192,896 value
  pairs / 43,459 service transactions, Python compilation and strict OpenSpec
  pass, and `make test-psg` remains at 524/850 sample clocks with fixed
  530+272 credits and 48 spare, 4,008/5,103 tick clocks and zero late flips.
  Candidate, controller, manifest, requirements, layout and production-image
  anchors remain byte-identical.  The dictionary carries no value, pool
  update, primitive equation or fixed-write data and proves no pool SSA,
  adapter, RTL, image, integration, synthesis, timing, routing, render or area
  property.
- **C2-C-D1-C-B1-H095 hypothesis and scope:** rebind the accepted algebraic
  model to canonical generic H095 `3d7a2e2` without importing or editing its
  RTL.  Read the exact `psg_seq.sv`, `psg_walk.sv` and `psg_common.svh` git
  blobs as the model's live generic cones, while retaining the accepted local
  H-C freeze-enabled ARAM/multiplier and executor artifacts.  Emit a separate
  source-boundary certificate covering all ten H095 generic RTL/proof blobs
  and five local R.84 prerequisites; do not change the B1 event schema or
  claim a combined RTL image.  Scope is only `tools/psg_exec_model.py`,
  `tools/psg_exec_bindings.py`, generated `build/` evidence and this ledger.
  Baseline is accepted B1 `7cc639a` / event SHA-256 `5b178017...`; retry only
  if the canonical generic revision or an accepted local prerequisite changes.
- **C2-C-D1-C-B1-H095 result and decision:** accepted as an algebraic
  source-rebase certificate only.  Independent A/B model generations bind
  full H095 `3d7a2e2ea1ed6a59cf868570755210e8b9ef81e8`, ten exact generic
  source/proof hashes and five exact local R.84 prerequisite hashes in schema
  `psg_exec_h095_source_contract_v1`; both certificates are byte-identical at
  SHA-256 `12db76a1...`.  The model explicitly recognizes H075's XOR/carry-in
  wavetable sign fold and the accepted prefix noise clamp/kick spelling, while
  the complete H095 hardware forms prove post-shift signed remainder,
  selected wavetable sign, timing update, selected pitch clamp and trigger
  length saturation on their full stated domains.  The H095-bound model keeps
  **63** legacy states, **85** expanded PC nodes, **19,728,640** normalized
  formula cases and **131,087** normalized transactions.  Its independently
  generated B1 event dictionaries remain byte-identical to pre-H095 B1 at
  SHA-256 `5b178017...`: 60 root endpoints, 22 transaction completions, 156
  lifetime endpoints and 85 fold events.  Two independent binding audits pass
  152,893 legacy rows, all controller/event mutations plus five new source
  mutations, and reproduce source inventory `95619e61...`; two value audits
  pass 192,896 value pairs and 43,459 service transactions.  The default local
  model still passes, Python compilation and strict OpenSpec validation pass,
  and `make test-psg` remains at 524/850 sample clocks with fixed 530+272
  credits and 48 spare, 4,008/5,103 tick clocks and zero late flips.
  Production/candidate images and every generic RTL file remain untouched.
  This does **not** regenerate H095 live instrumentation traces and proves no
  combined RTL, adapter, integration, synthesis, timing, routing, render or
  area property; those remain atomic integration gates.
- **C2-C-D1-C-B1-H095-I001 integration:** accepted model/source composition
  after the separately accepted H095 + R.84 RTL merge I001 `6c9eebe`.  The
  upgraded `psg_exec_h095_r84_source_contract_v2` binds canonical H095
  `3d7a2e2`, I001, ten canonical generic hashes, twelve combined source/proof
  hashes, the three byte-identical model-live sources and the six explicit
  R.84 runtime/proof overrides.  Independent A/B certificates are
  byte-identical at SHA-256 `bcadbae4...`; five source mutations are convicted.
  Candidate `6f5713e2...`, manifest `438d85a0...`, control `a9233d6d...`,
  requirements `5a7b9809...`, controller `f86698f6...`, event dictionary
  `5b178017...` and source inventory `95619e61...` remain byte-identical to
  I001.  Both binding audits pass 152,893 rows and both value audits pass
  192,896 pairs / 43,459 service transactions.  The default combined model,
  complete hardware forms, Python compilation and strict OpenSpec validation
  pass.  This source certificate relies on I001's separately recorded complete
  RTL, cadence, render, recovery, click, Celeste, synthesis and timing gates;
  it does not reinterpret the isolated `0db0484` result as having proved them.
  B2 remains the next proof step, but must not start until this combined merge
  is safely fast-forwarded to `main`.
- **C2-C-D1-C-B1-H095-main composition:** accepted proof rebinding after
  `main` fast-forwarded to combined merge `0e951a4` and the pre-existing board
  diagnostic ARAM read was mechanically composed with the R.84 hold-frozen
  core as `9aacce1`.  Schema
  `psg_exec_h095_r84_main_source_contract_v3` binds canonical H095
  `3d7a2e2`, verified I001 `6c9eebe` and main composition `9aacce1`.  The only
  combined source hash changed from I001 is `rtl/psg_aram.sv`; the three
  model-live generic sources remain byte-identical.  Independent A/B source
  certificates are byte-identical at SHA-256 `3f8a3ec8...`; seven source
  mutations are convicted.  Candidate `6f5713e2...`, manifest `438d85a0...`,
  control `a9233d6d...`, requirements `5a7b9809...`, controller
  `f86698f6...`, event dictionary `5b178017...` and inventory `95619e61...`
  remain byte-identical.  Both structural audits pass 152,893 rows and both
  value audits pass 192,896 pairs / 43,459 service transactions.  The default
  algebraic model and complete H095 hardware forms pass.  The combined ARAM
  hold/replay bench passes and the diagnostic bench reads all 4,608 physical
  audio-RAM bytes through `$42ff`.  This closes the source/proof overlap only:
  it claims no post-diagnostic synthesis, area, timing or routing result, and
  starts no B2 literal-slice work.  B2 remains the next permitted proof step.
- **C2-C-D1-C-B2 boundary:** only after B1 closes, attach literal
  pool definitions/uses and service issue/result/take roots to exact enabled
  occurrences with pre/post phase.  Repair fold assembly, STEP8, result-write
  and final-FINISH lifetimes there; reject any read before a unique guarded
  definition.  A static site inventory or self-digesting event table is not a
  substitute.
- **Following C2-C-D1-D boundary:** prove each non-transport D1-C primitive
  separately against the live `psg_walk.sv` cone with width, signedness,
  truncation, pre/post-NBA edge phase and guard explicit.  Existing service
  arithmetic stays a transaction-bound proved root rather than being
  reimplemented.  Only after those certificates compose by induction through
  unique/disjoint slice definitions, exhaustive guards, hold identity,
  lifetime closure and all eighteen comparison-boundary writes may an RTL
  substrate be hypothesized.  Any such RTL hypothesis must first be sent to
  the coordinating optimization task.
- **Repeat only if:** the H-A service cadence, H-C wave/ARAM issue boundary,
  state-word layout, retained service latency, signed fold formula, public
  priority or measured fixed-base budget changes.  Do not retry with a second
  working-record mirror, general action ALU, new result register, fold stack or
  partial generic handoff.

### Active task queue

- [x] Prove exact waveform formulae, cycle state, widths and `/4` schedule.
- [x] Exhaustively test and physically measure radix-4/radix-8 small dividers.
- [x] Exhaustively test both sixteen-edge scalar-service shapes.
- [x] Reject before integration when both exceed the measured LC budget.
- [ ] R.84: target the mutually exclusive walker/sequencer execution
      substrates as one bulk family.  Use at most the one EBR available under
      the 15-block ceiling for a complete shared control store and keep
      operands/results in address-selected state; do not retry task 4.1's
      register-fed generic ALU or a partial decode migration.
- [x] Re-derive the 7k/6k/5k ladder from measured whole-substrate ownership
      before writing R.84 RTL.
- [x] R.84B: infer and route the complete one-EBR controller shell before
      action logic; 43 LUT4s, 14 flops, 53-LC floor, 57 placed LCs and
      122.22 MHz, with self-check and both lint configurations clean.
- [x] R.84C: generate and exhaustively validate the structured action/program
      contract, including synchronous-read alignment, page/target bounds,
      state addresses, output commits, termination and worst-case clocks.
- [x] R.84D: implement and price the address-selected action/state datapath;
      keep legacy controllers intact until an atomic full-mode switch and do
      not rebuild their wide source/destination muxes behind action decode.
- [x] R.84E: lower and prove one complete record-movement family through a
      real synchronous state-memory transaction model before macro arithmetic.
- [x] R.84F: reject the parallel advance-macro shape after exhaustive formula
      proof and mapped attribution show 190 LUT4s / 77 duplicated carries.
- [x] R.84G: lower the same exact family as explicit condition-indexed,
      synchronous address-state micro-operations through the common chain.
- [x] R.84G-A: make explicit branch/default/page/action metadata a
      byte-identical generated-control foundation before lowering the family.
- [x] R.84G hold prerequisite: prevent common datapath commits while the
      controller and movement layer are frozen; re-prove and re-price R.84E.
- [x] R.84G-B: reject two field-selected common-chain spellings after both
      exceed the physical gate without adding another arithmetic chain.
- [x] R.84G-C: reject the fixed one-EBR scratch-normalized spelling after its
      fallthrough-minimized 285-word image exceeds capacity by 29 words.
- [x] R.84G-D: prove an owner-banked two-EBR control store whose complete
      resource exchange preserves the whole-PSG EBR count before restoring
      normalization or lowering the advance family.
- [x] R.84G-E: independently re-derive and generate the complete 68+49-word
      normalized advance manifest; prove its exact branch algebra and fit the
      complete owner-one image at 226/256 words.
- [x] R.84G-F: implement the fixed normalization/merge actions, dynamic
      parameter-bank addresses and arbitrated stop/cpz effects; prove the
      complete synchronous advance transaction before generic integration.
- [x] R.84H resume audit: reconcile `e099e52`, re-baseline the corrected
      generic target, enumerate all remaining actions/owners/services/commits,
      and record the executable-control, fold-address, condition-index and EBR
      blockers before semantic RTL.
- [x] R.84H-A: derive and prove the complete addressed-state/service-dependency
      manifests, owner-qualified conditions, explicit wait states, fold
      schedule and one global-public priority function before adding another
      action decoder.
- [x] R.84H-B: prove all owner-zero persistent/scratch reads and writes through
      one synchronous state-memory transaction harness before adding service
      semantics or touching generic PSG composition.
- [x] R.84H-C: stream phase words through existing physical state reads and
      retain exactly 38 wave/ARAM context bits; prove the unchanged production
      image's W0--W5 cadence and hold recovery without adding semantic state
      transactions, result storage or generic composition.
- [ ] R.84H-D: derive and lower the complete remaining owner-zero service/fold
      graph while preserving H-C's addressed issue boundary; prove restart,
      phase updates, explicit ready waits, fixed scratch lifetimes and isolated
      physical cost before any generic composition.

## Handoff rule

Before opening R.84, record its whole-substrate area bound, state/address map,
schedule and retirement set.  Then finish it with exact formula, transaction, schedule,
render, mapped, placed, routed and timing evidence.
Commit either the accepted RTL or the reverted-source rejection record as one
scoped iteration.  Never stage unrelated files from the dirty main worktree.
