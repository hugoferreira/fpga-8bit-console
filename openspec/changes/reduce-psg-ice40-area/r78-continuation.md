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
- [ ] R.84G: lower the same exact family as explicit condition-indexed,
      synchronous address-state micro-operations through the common chain.
- [x] R.84G-A: make explicit branch/default/page/action metadata a
      byte-identical generated-control foundation before lowering the family.
- [ ] R.84G-B: price field-selected operations through the existing common
      chain before spending program words on the complete advance sequence.

## Handoff rule

Before opening R.84, record its whole-substrate area bound, state/address map,
schedule and retirement set.  Then finish it with exact formula, transaction, schedule,
render, mapped, placed, routed and timing evidence.
Commit either the accepted RTL or the reverted-source rejection record as one
scoped iteration.  Never stage unrelated files from the dirty main worktree.
