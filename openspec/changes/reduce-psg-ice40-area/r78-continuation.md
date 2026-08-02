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
