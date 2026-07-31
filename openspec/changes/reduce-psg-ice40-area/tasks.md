## 1. Baseline and guards

- [x] 1.1 Record the fidelity-complete RTL fingerprint, mapped
      LUT4/flip-flop/carry/BRAM counts and seed-1 placed LC/BRAM count
- [x] 1.2 Add structural accounting for clocks consumed by the worst sample
      walk and assert completion before the next `sample_en`
- [x] 1.3 Freeze the complete 50-case PICO-8 oracle result and run the oracle
      unit tests before changing storage

## 2. Atomic voice-state store

- [x] 2.1 Define a packed 256-word layout containing the 80 tick/note words,
      112 oscillator words and two 32-word sounding-parameter banks
- [x] 2.2 Add one scheduled state-memory port contract with sample priority and
      replayable tick stalls; prove one read and one write site infer
- [x] 2.3 Publish tick results through the inactive parameter bank and swap the
      active bank only after all eight slots are complete
- [x] 2.4 Remove the three old memories, synthesize the replacement as one
      `SB_RAM40_4K`, and record the LC and BRAM delta
- [x] 2.5 Run the structural PSG test and complete PICO-8 oracle matrix; reject
      the stage if publication order or audio changes
- [x] 2.6 Audit streamed/datapath resets, retaining reset only on validity and
      externally observable control; record the mapped reset-flop delta

## 3. Tick microengine

- [x] 3.0 Decide the tick pre-run (evaluate at scnt == 181 into the inactive
      bank, publish at the boundary), decoupling evaluation from
      publication; the window now scales in whole sample intervals via the
      pre_tick constant (landed: bank_ready/flip_pend handshake, placed
      6,369 (-2), 50/50 byte-identical, worst pre-run 1,159/1,275, zero
      late flips, no TB case re-baseline needed; design 3, pre-run
      implementation result)
- [x] 3.1 Implement the narrow micro-PC, flags, data register and single-site
      accumulator/store contract for tick-rate voice work (landed: acc/wrd
      word registers, the ta compare, engine read/write requests through
      the two existing port sites, generalized displaced-read replay;
      design 3, stage 3.1/3.2)
- [x] 3.2 Move record load/store, trigger metadata, row progression and pattern
      control onto the tick microprogram (row progression, trigger loads
      and the load/store shrink landed with the bookkeeping family at
      6,344; the ML chain's per-byte launch completed pattern control at
      6,214, pb staging gone; W_MUS/MS_CK keep their two compare states -
      they hold no migratable staging)
- [x] 3.3 Move pitch, volume, slide, vibrato, arpeggio, fade and instrument
      evaluation onto byte/word-serial micro-operations (landed as three
      families: the pinc prefetch retirement at 6,317, publication
      direct-to-bank at 6,220 - the largest single engine win - and the
      per-byte pattern launch at 6,214; the effect microprogram itself
      already ran on xs and the m service, so its migration was the
      register layer around it. The slide/combine cone dedup priced
      below the 5c noise floor and is recorded as an accompaniment
      candidate, not a standalone stage)
- [ ] 3.4 Remove superseded `sst` decode, named tick working-register muxes and
      standalone effect arithmetic
- [ ] 3.5 Measure mapped/routed area after each migration and retain only
      reductions that preserve the fixed publication boundary and oracle

## 4. Shared sample arithmetic

- [x] 4.0 Consolidate the mutually exclusive sample-volume and
      transition-blend products through one 16x8 shift-add service; retain the
      stage only after mapped/routed area and the complete oracle improve/pass
- [ ] 4.1 Implement one signed accumulator/shift-add service with one physical
      result write site and explicit per-operation widths/truncation
- [x] 4.2 Migrate current, old, secondary and transition phase operations onto
      one scheduled 24-bit add/sub service
- [ ] 4.3 Migrate DAMPEN, noise/brown filtering and reverb feedback arithmetic
      onto the service
- [x] 4.4 Replace the separate sample-volume, transition-blend and wavetable
      interpolation engines with the shared shift/add operation
- [x] 4.5 Store the eight mix leaves/intermediates as scratch words and execute
      all seven ordered `soft_add` operations iteratively through the service
      (landed as a three-entry stack plus a serial fold microprogram on the
      24-bit phase ALU rather than scratch words or the m service - both
      rejected shapes; see design 5b. Byte-identical, -124 placed cells)
- [ ] 4.6 Remove superseded arithmetic registers and prove the worst-case
      sample microprogram remains below 1,275 derived PSG clocks
- [ ] 4.7 Two-pass old-voice render: store main oscillator words early,
      reload old-continuation parameters into the same working registers and
      reuse the wave-read/product path, retiring s_old_*/old_smp and their
      schedule slots (design 5c; the blend fuse and wt_pf/wt_qf retirement
      inside this family were measured +31/+70 placed and rejected)

## 5. Waveforms and scheduled tables

- [x] 5.1 Implement recovered integer built-in waveform formulae one waveform
      family at a time, using the shared sample service only where its routing
      is cheaper than a direct shift form (retained:
      bounded tilted-saw and saw shift forms, triangle and organ remain in
      one EBR; 6,258 placed / 14 EBR / 40.72 MHz, 50/50 diagnostic-clean;
      exact and triangle-formula alternatives rejected in design 5.1)
- [x] 5.2 Replace the square and pulse ROM banks with exact phase thresholds,
      retain four non-trivial ROM banks, and prove the combined checkpoint
      meets the 15-EBR ceiling with clean oracle probes
- [ ] 5.3 Consolidate or serialize pitch, noise-gain, filter-decode, fade-step
      and microcode constants without increasing the accepted BRAM count
      (pitch landed: 13-bit words in the constants EBR, 6,199 at the
      15-block ceiling, byte-identical; noise-gain deleted as dead code;
      fade-step landed in the same EBR at R.15; words 144..255 remain the
      microcode home; filter-decode remains)

## 6. Final verification and evidence

- [x] 6.0 Record a reproducible handover fingerprint, seed-1 mapped/routed
      checkpoint, structural deadlines, full oracle result and explicit
      remaining LC gap
- [x] 6.1 Pass oracle unit tests, the complete PICO-8 matrix and
      `rtl/psg_tb.sv` with deadline assertions
- [ ] 6.2 Build and run Celeste headlessly and confirm active, non-constant
      audio
- [ ] 6.3 Run seed-1 and multi-seed iCE40 synthesis, recording the final
      fingerprint, mapped cells, routed LC/BRAM and Fmax
- [ ] 6.4 Confirm the final standalone result is no more than 5,500 LCs and 15
      BRAMs; document rejected variants and remaining timing headroom
- [x] 6.5 Validate the OpenSpec change strictly and reconcile every completed
      task with the recorded evidence

## Resumed after adopt-pico8-integer-audio (2026-07-28)

- [x] R.0 Re-baseline. `rtl/target_psg.sv` now instantiates REVERB=0:
      adoption 2.5's exact per-voice rings are 732 x int16 EACH, 36 EBR
      against the part's 32, so measuring this target at REVERB=1
      measured a build that cannot exist. Baseline 8,064 LC / 11 EBR.
- [x] R.1 `tools/psg_ff_census.py` - the packing metric promoted out of a
      session scratchpad, where it was lost. Grades a yosys JSON by
      PLACED cells: an iCE40 flop shares its cell only with the LUT
      driving its D, at fanout 1, so unpackable flops are whole cells a
      mapped LUT4 count never shows. Also ranks LUT cones by driven-net
      family, which needs the yosys chain suffix cut or every LUT is its
      own family.
- [x] R.2 The divider's numerator: one 24-bit adder behind a two-way mux
      instead of two adders behind a three-way one. **-63 LC** (8,064 ->
      8,001), oracle 57/57 unchanged.
- [x] R.3 REFUTED, with numbers, and they re-confirm the bulk-only rule
      at this density: retiring arp_r's self-feedback arm (slide and
      both arpeggios re-publish what the register already holds, so the
      arm is pure mux) measured **+23**; folding vol_r's step-10 write
      into step 11 measured **-9 against that**, i.e. both together
      **+14** over the R.2 baseline. Reverted. Arm-counting arguments do
      not survive abc9 re-buffering below ~50 cells - only families that
      take their arithmetic or decode with them pay.
- [x] R.4 REFUTED by proof, not measurement: none of stage 2's
      reciprocal constants can be truncated. recip7 (149797), recip15
      (279621) and recip3 (174763) all need full precision over the
      domains the wave cone presents - 0 low bits free on the first two,
      and recip3 breaks at bit 1. The slide's K behaved the same way, so
      treat "shorten the constant" as closed for this design.
- [x] R.5 **THE PSG PLACES: 7,672 / 7,680 LC, 18/32 EBR, routed 39.71
      MHz against the 28.125 the design needs.** 8,064 -> 7,672 (-392).
      Found by ABLATION, not by reading the RTL: stubbing each stage-2
      reciprocal priced the organ's /3 at 161 LC and the tilt /7 + /15
      pair at 219 - 380 of the 878-cell wave cone in three constant
      multiplies, which is almost exactly the gap that was open. The
      constants themselves are near-minimal (a search over every exact
      (mult, shift) pair found 149797 and 279621 already cheapest, and
      /3 only one CSD term better), and psg_hw_forms had already proved
      their low bits are not free - so the win had to come from a
      different SHAPE.
      That shape is the split identity: 2^k*h + l with 2^k = d*m + 1
      gives x/d = m*h + (h + l)/d EXACTLY, and h+l stays small enough
      that the remainder is a table. 256h = 3*85h + h (512 entries),
      512h = 7*73h + h (1024), 256h = 15*17h + h (2048). Eleven-plus CSD
      adds become four, and the table read IS the pipeline register the
      cone already had - so no stage is added and no schedule moves.
      REVERB=0 is what pays for it: 11 spare blocks, where the campaign
      that priced these dead was under a 15-EBR ceiling. Oracle 57/57
      byte-exact at every step; psg_tb ALL PASS, deadline 906/1275,
      pre-run 5,052/7,654. The critical path is now tab7's output into
      smp_b, which is the expected cost of putting a block read in the
      wave cone and leaves 11 MHz of margin.
- [ ] R.6 Per-slot arrays: PRICED, and blocked on a product decision.
      Collapsing sfx_id and row to single registers (function broken,
      number only) measures **7,672 -> 7,423, so -249** - far more than
      the -90 a flop count suggests, because an array's flops share one
      D net behind per-slot enables, so ALL of them are unpackable AND
      the read/write decode goes with them.
      The blocker is not the sequencer: row is entirely visit-scoped
      (arow, sa_off, seed5, the advance) and sfx_id needs only staging
      at T_FL, so both fit the V_LD/V_ST working-register pattern that
      every section-3 family won with, and VSTR 32->64 costs one spare
      block. It is the OBSERVERS. `dout` answers $10-$17 with the
      AUDIBLE slot's row/sfx - documented as "the ownership state a cart
      can actually observe" - and `dbg` exports four channels at once
      for --psg-trace and tools/p8_music_trace.py. A single-port record
      cannot serve a four-slot simultaneous read.
      Three ways out, and the choice is a product one:
      (a) mirror the four audible slots (44 bits), updated at each
          slot's V_ST and at ML_L0-L3. Nets about -180. Row stays exact
          (its advance and the mirror write are the same visit), but
          when a foreground effect stops mid-tick the reported value
          lags one tick behind the audible-slot flip.
      (b) serve $10-$17 from the record through the state port. Exact,
          but the port is shared with the walk and needs collision
          handling like the aram replay path.
      (c) leave them. The design places without this.
- [x] R.6a `row` MOVED: 7,672 -> 7,587 (**-85**), 19/32 EBR, Fmax 39.71
      -> 40.65. VSTR 32 -> 64 (one spare block) with the word plumbing
      widened to six bits; row becomes w_row, loaded at V_LD word 32 and
      stored at V_ST. Both blockers the review raised dissolved: `dbg`
      is simulator-only (top.sv, top_tangnano20k.sv and
      target_harness.sv all leave .psg_dbg() unconnected - only
      top_simulator.sv wires it, for --psg-trace), and it wants exactly
      what $10-$17 wants, so ONE four-entry audible mirror serves both
      and no four-slot read survives. The PICO-8 manual specifies
      stat(46..53) as "a history of mixer state at each tick to give a
      higher resolution estimate of the currently audible state" - a
      sampled view - so refreshing the mirror as each slot's visit ends
      is faithful at 120 Hz, against the legacy indices' ~20.
      Trap: the record read issued at vcnt lands at vcnt+1, so the new
      word is issued at 6 and consumed at 7. Issuing at 7 loads the
      previous word and fails 34 tests at once.
      psg_tb's record probes hard-code the stride - they were changed to
      a VSTR localparam that must move with psg.sv's, or they read the
      wrong words silently.
- [ ] R.6b `sfx_id` NOT moved: it prices out as a wash. Unlike row it has
      two asynchronous writers - the CPU at $10-$13 and ML_L0..L3 - so
      it needs four-entry staging (24 flops) on top of the audible
      mirror (24) and the working register (6), which is 54 against the
      46 the array costs. Only worth revisiting if ML writes the record
      directly (an eng_wa slot override) AND the staging can be shared
      with trg_row/trg_len, neither of which is obviously free.
- [x] R.6c `dbg` conditionally compiled: DBG_PORT on psg, PSG_DBG on
      chip, 0 in top.sv / top_tangnano20k.sv / target_harness.sv /
      target_psg.sv, default 1 so top_simulator.sv keeps --psg-trace.
      Nothing on hardware reads it, and it was the only reader that ever
      wanted four slots at once, so removing it structurally stops it
      constraining what the per-slot state may become.
- [x] R.6d **METHODOLOGY, and it invalidates some earlier verdicts.**
      Placed cells are DETERMINISTIC - identical across five nextpnr
      seeds, with only Fmax moving (38.58-40.96 MHz) - so the campaign's
      "a placed delta at fixed seed is netlist-real" holds. But they are
      not INSENSITIVE. Adding the DBG_PORT parameter leaves the
      PRE-MAPPING netlist bit-for-bit identical (14,398 cells, every gate
      type, 1,610 flops) and still moves placed cells by 59. That is
      abc9's LUT covering being order- and naming-sensitive.
      Consequence: **a placed delta under ~60 cells does not distinguish
      a real saving from a mapping reshuffle**, so R.3's +23 and -9 prove
      nothing either way, and every sub-60 verdict in this change's
      history should be read as unresolved rather than refuted. The
      bulk-only rule may well still hold - it just was not established
      by those numbers.
      The structural metric that does not move:
        yosys -p "read_verilog -Irtl -sv rtl/target_psg.sv; \
                  synth_ice40 -top target_psg -run :map_luts; stat"
      Judge a change on that delta; use placed cells for the fit verdict.
- [ ] R.7 Next, if more is wanted: the campaign's own goal is 5,500. The
      NEW fact since the campaign paused is EBR headroom: REVERB=0 uses
      11 of 32 blocks, where the old ceiling was 15 and `record 32/32
      full` is what priced the per-slot arrays dead. state_m is 8 x 32 x
      16 = one block; widening VSTR to 64 costs a second and opens 32
      words per slot. The census puts sfx_id at 48 unpackable flops, row
      38, trg_len 24, trg_row 20 - 130 whole cells plus their read muxes
      and the ch_base/sa_off cones they feed. Address-selected storage is
      the ONE shape that has always paid here (THE LAW, design 5c).
      Cost: ch_base is combinational across the trigger sequence, so
      sfx_id must stage into a working register at V_LD, and the CPU and
      ML_L0-L3 write sites need the port. Estimate -150..250. The split
      identity above may also have more to give: t_pre's /7 could use a
      k=6 split (9h, one add instead of two) for six more blocks, and
      the same shape applies anywhere a constant divisor survives.
- [x] R.8 Identity bundle: 7,646 -> 7,456 placed (**-190**), structural
      14,398 -> 14,331 (-67, CARRY -70), Fmax 38.13 -> 38.54, oracle
      59/59 byte-identical, psg_tb ALL PASS (pre-run 5,022/7,654).
      Three sub-stages, landed as ONE bundle because each alone is
      inside the ~60-cell mapping-noise floor (R.6d):
      (a) input-abs: the m service strips signs itself (one 24-bit
      negate at m_a's load); requesters pass raw signed values and the
      six per-source magnitude networks (zn/zo/blend/vl/slp/wt) retire.
      Consumer-side sign application STAYS - tz semantics scale in the
      magnitude domain, so a signed-product service would change floors.
      (b) the 24572 chain retires: 24572 = 3*8192 - 4 gives
      floor(24572r/2^13) = 3r - ceil(r/2048) (and /2^12 = 6r - ceil
      (r/1024)) exactly over the ramp, so tilt's two 31-bit adds become
      an 18-bit x3 and a 19-bit subtract. Triangle folds BEFORE its x3
      (3x-49152 and 147456-3x are both 3*(x-16384); the fold is an XOR
      plus carry-in). The two x3s canNOT merge: the buzz triangle
      consumes BOTH chains in one evaluation - measured, not assumed.
      (c) stage-2's three recombine trees (73h/17h/85h) become ONE
      masked-shift adder with per-shape enables, and the two closing
      subtractors share (the consuming shapes are wsel-exclusive).
      All identities proven exhaustively over the 16-bit domain BEFORE
      the RTL was touched (scratchpad prove_wave.py).
      **Measured lessons this stage adds to R.6d: (1) R.6b confirmed by
      implementation - sfx_id-to-record was BUILT and measured +23
      structural / -39 placed = the wash the pricing predicted; reverted.
      (2) Placed can beat structural: -67 structural mapped to -190
      placed - the retired wide adders were entangled with unpackable
      staging, so packing recovered ~3x the gate delta. The structural
      metric JUDGES a change is real; it does not bound the placed win.
      (3) make test-psg (iverilog) has NOT built since the reciprocal
      tables landed - 19 use-before-declare errors predate this stage;
      psg_tb runs under the Verilator invocation in its own header
      (now needs -Wno-PINMISSING for the DBG_PORT-era unconnected dbg).**
- [x] R.9 The sample schedule becomes a control store (`b1a89dd`):
      7,456 -> 7,397 (**-59**), 21/32 EBR. The hardware walk's step
      decode - 22 capture arms, 11 product-request labels, wave-issue
      contexts, wavetable read windows - reads from a 128x32 one-hot
      ROM (tools/gen_psg_ctrl.py -> rtl/psg_ctrl.hex) fetched at pph+1.
      Two shapes measured: parallel-IF built priority chains (+154
      structural, -46 placed); case (1'b1) over the ctrl bits with
      (* parallel_case *) - sound because the generator asserts one
      capture bit per word - is +15 structural, -59 placed. VERDICT ON
      THE WHOLE DECODE TERRITORY: ~-59 is what the equality fabric was
      worth; the mass is in data muxes and registers, which a control
      store cannot reach. The tick-side (sst) decode is smaller still
      and its next-state is branchy - priced NOT worth building.
- [x] R.10 Fold-stack width: fstk/fda/fdb/mix_leaf 22 -> 18 bits:
      7,397 -> 7,385 (**-12** placed, -71 structural - mapping absorbed
      most of the gate delta this time; kept because the structural
      metric says it is netlist-real and the change is risk-free).
      PROOF: a leaf is an int16-wrapped sample; soft_add is contractive
      toward 32768 (TH + (2*32768-TH)/5 = 32768 exactly), so every
      stack value is <= |32768| and every raw pair sum <= |65536| -
      18-bit signed carries both. Oracle 59/59, psg_tb ALL PASS.
      **Campaign state under the -1000 goal (2026-07-28): 7,646 ->
      7,385, cumulative -261, every stage byte-identical. The measured
      evidence says the remaining ~-740 is NOT reachable while every
      render byte stays fixed: all major families ablation-priced (fx
      -960 structural bound, wave -1,493, ins -327, old/crossfade -392,
      noise -66, all over-attributing); both bulk strategies were BUILT
      and measured (control store -59; identity harvest -190); the
      selection-eats-arithmetic law held in four independent
      experiments; and the sum of every remaining mapped idea - service
      reorder to retire old_smp/old_smpb, tick-side microword, ins
      decode shavings - is -150..250 optimistic. Anything larger means
      render-visible trades (crossfade, custom instruments, the noise
      process), which are product decisions, not area work.
      One more identity was tried and REFUTED after this entry: dq17's
      seven per-wave K-adders factored into one masked shift tree (all
      forms proven exact in Python first) measured **+46 structural** -
      the narrow dedicated adders plus a value mux beat the uniform
      masked tree. Reverted. The unification law refines to: retiring
      networks pays only when they are WIDE (t24572's 31-bit chains);
      16-19-bit exclusive-per-cycle adders are already optimal under a
      value mux.**
- [x] R.11 Width audit on the shared services (`pending-hash`): 7,385 ->
      7,344 (**-41** placed, -33 structural). The fold ALU narrows
      24 -> 18 - operands are 18-bit stack/series values and the widest
      result is a compare spanning +-(65,536 + 24,576) = 90,112, inside
      signed 18; the compare sign moves to bit 17. The m service's
      A-side narrows 24 -> 21 - the widest operand any arm supplies is
      base_inc, whose pitch-table ceiling is 0x1CE0 << 8 = 1,892,352 <
      2^21; m_p 37 -> 34, m_acc 25 -> 22. Synthesis cannot see either
      bound (they live in the pitch table's content and the soft-add
      algebra), which is why the bits were real cells. Oracle 59/59,
      psg_tb ALL PASS.
      ALSO CLOSED BY ARITHMETIC, not built: an fx/tick microword (the
      xs/e_fx decode into a 128x16 EBR) - its ROM output register is
      14-16 BRAM-fed unpackable flops, a whole-cell tax that eats the
      -35..60 decode win to -5..30. The pph control store only paid
      because its fabric was 2-3x larger. The decode-to-ROM lever is
      exhausted.
- [x] R.12 Width audit round 2 - the increment carriers: 7,344 ->
      7,216 (**-128** placed, -209 structural, the richest structural
      delta since the bundle). EVERY pitch-increment carrier (arp_r,
      s_eff_inc, s_old_inc, s_last_inc, einc, base_inc, fxi_next,
      fxp_res, pub_inc) narrows 24 -> 21: the pitch table's entries are
      13 bits (max 0x1CE0 -> increment 1,892,352; the vibrato 258/256
      ceiling is 1,907,136, both < 2^21), but every ADD between the
      carriers laundered that bound out of synthesis's sight - pinc_q's
      three structural zero bits die at the first adder. The bound was
      verified from rtl/psg_const.hex itself, not the notes. Record
      word layouts keep their shape ({3'b0, inc[20:16]} in the packed
      high bytes), so the TB probes and the BRAM images are untouched.
      Oracle 59/59, psg_tb ALL PASS.
      **METHOD, for what remains: "invisible bounds" - properties
      provable from table contents, algebra, or schedule that synthesis
      cannot see - is the lever class the census and ablation methods
      missed. Widths are now mined (remaining: eff_rem -4, bl_res -1
      bit = noise). The sibling classes still open: provably-dead mux
      arms (z_lin/z_prim wave-6 defaults alias to a live arm), and
      provable exclusivity (the state-port priority chain - measured
      worth ~-15..30 but deliberately kept as a structural contract).**
- [x] R.13 Dead-arm aliasing REFUTED: +115 structural, reverted.
      Constant default arms cost nothing after optimization; aliasing
      them to live nets (mul_start_a = mul_a, z_lin default = tri_v)
      chains the tick mux INTO the sample mux - series routing, not
      sharing. Trap logged: mul_start_mode's zero default is LIVE (the
      blend and T_NL products rely on it for their 8-cycle runs); an
      alias there miscounts cycles and was caught before the gates.
      Goal-campaign close-out at 7,216: five landed stages (-430
      cumulative), four refutations with numbers, all render-exact.
      LAST DOOR, closed by analysis: reusing the pph control store for
      the tick side's V_LD/V_ST word schedule (19 free rows, sunk ROM
      costs, fields time-sharing ctrl_q). It fails on freeze-resume:
      the sample walk owns the ROM address bus mid-tick-step, so
      ctrl_q is stale exactly when the resumed tick issue needs its
      word, and the repair (resume priming + a previous-word register
      threaded through the replay) rebuilds the decode it deletes -
      in the freeze/replay corner, for -35..55. The pph side only
      worked because the sample walk cannot be frozen: it IS the
      freezer. No positive-EV render-exact move remains mapped.
      THE CLOSING THEOREM (why every restructure measured ~0 or worse):
      iCE40 LUT4s absorb selection conditions into arithmetic LUTs for
      free - a mux-fed add costs what the add costs - so the design's
      combinational shape networks ARE the minimal encoding of its
      shape-conditional arithmetic. Anything that moves selection out
      of the arithmetic (serial operand arms, masked trees, microword
      tables, aliased defaults) must buy back the selection the LUT4s
      gave away free. The campaign's real wins were exactly the two
      things this theorem permits: retiring carry chains (identities,
      invisible-bound widths) and retiring whole-cell decode fabric.
- [x] R.14 Sequencer/walker redundant-work pass after the wave-6 fidelity
      closeout: the sequencer drops the unused `wrd[15:14]`, `tcnt[0]` effect
      staging and zero-only pitch-table carrier bits. The walker evaluates
      the live and old noise-walk variable products on W0/W1 through one
      multiplier cone, retaining only a nine-bit pre-advance random staging
      register so the old walk remains byte-exact. Fingerprint
      `2c7196d957fd`: 8,327 -> 8,106 placed LC (-221), 22 EBR unchanged;
      placement still fails because the design is 426 cells over the HX8K.
      Yosys maps 7,043 LUT4, 1,656 carries and 1,619 flops. The frozen oracle
      is 59/59 byte-identical, the PICO-8 noise-fidelity gate passes, and
      `psg_tb` remains 906/1,275 clocks with tick pre-run 5,022/7,654.
      Celeste music 30 also passes its provenance-bound full-track gate:
      whole-track band deltas -0.09/+0.16/+0.07/+0.14 dB and quiet 4-8 kHz
      -0.04 dB.
- [x] R.15 Sequencer constant-store consolidation: the dedicated 32x13
      `fstep_rom` moves into unused words 112..143 of the existing constants
      EBR. A borrow/replay bit freezes and reissues a displaced pitch/slide
      lookup, while `fstep_q` preserves the selected fade word for a later
      `$20` command. Fingerprint `27f53a125e75`: 22 -> 21 EBR, with the
      explicit BRAM trade 8,106 -> 8,153 placed LC (+47); Yosys maps 7,072
      LUT4, 1,656 carries and 1,633 flops. `psg_tb` remains 906/1,275 sample
      clocks and 5,022/7,654 tick clocks, the PICO-8 noise-fidelity gate
      passes, and the frozen matrix is 59/59 byte-identical. Two exact
      arithmetic rewrites were measured and reverted in the same pass:
      replacing the noise threshold `/3` with `3g+3 <= x` was +57 LUT4 /
      -16 carries / +22 placed LC; moving vibrato into its 13-bit published
      quotient was +23 LUT4 / -9 carries / +17 placed LC; narrowing
      `eff_rem` 12 -> 8 bits was +5 LUT4 / +3 carries / +8 placed LC.
      The provenance-bound Celeste music-30 gate remains unchanged at
      -0.09/+0.16/+0.07/+0.14 dB whole-track and -0.04 dB quiet 4-8 kHz.
- [x] R.16 Walker control-store encoding: replace the mutually exclusive
      22-bit one-hot action field with a five-bit opcode, retaining the
      multiplier selector and issue/context flags in a 16-bit word. Fingerprint
      `7de2f07ad0dc`: 21 -> 20 EBR, with the explicit decode trade 8,153 ->
      8,198 placed LC (+45); Yosys maps 7,122 LUT4, 1,655 carries and 1,633
      flops. The store now occupies one EBR instead of two without changing
      the schedule: `psg_tb` remains 906/1,275 sample clocks and 5,022/7,654
      tick clocks with zero late flips, the PICO-8 noise gate passes, and the
      frozen matrix is 59/59 byte-identical. Celeste music 30 retains the same
      -0.09/+0.16/+0.07/+0.14 dB whole-track deltas and -0.04 dB quiet 4-8 kHz.
- [x] R.17 Constants/control-store port sharing: embed the walker's reachable
      pph 0..108 words in unused constants words 144..252, and select that
      address while `prun` freezes the sequencer. The existing state-store
      replay cycle re-primes the sequencer address before it resumes, so the
      separate control EBR and `psg_ctrl.hex` retire. Fingerprint
      `9f327071ab8f`: 20 -> 19 EBR, with the port-routing trade 8,198 -> 8,237
      placed LC (+39); Yosys maps 7,147 LUT4, 1,662 carries and 1,633 flops.
      The frozen matrix remains 59/59 byte-identical, `psg_tb` stays at
      906/1,275 sample clocks and 5,022/7,654 tick clocks with zero late flips,
      and the PICO-8 noise gate passes. Celeste music 30 remains
      -0.09/+0.16/+0.07/+0.14 dB whole-track and -0.04 dB quiet 4-8 kHz.
- [x] R.18 Walker lifetime retirement: export the shared ROM word directly
      and qualify only its four externally active fields; accumulate the old
      primary/secondary samples in `smp_b` after the new G-product consumes
      it, retiring both old-only 18-bit registers; reuse `mxs_new` for the
      wavetable interpolation sign until W27 overwrites it. Fingerprint
      `10dd65abd3c7`: 8,237 -> 8,189 placed LC (-48), 19 EBR unchanged;
      Yosys maps 7,142 LUT4, 1,658 carries and 1,596 flops (-5/-4/-37).
      The noise/analysis gates and `psg_tb` pass at unchanged 906/1,275
      sample and 5,022/7,654 tick clocks, the frozen matrix is 59/59
      byte-identical, and Celeste music 30 remains
      -0.09/+0.16/+0.07/+0.14 dB whole-track and -0.04 dB quiet 4-8 kHz.
      Reusing `smp_a` for `gz_s1_r` was rejected and reverted: -17 flops but
      +33 LUT4, +4 carries and +24 placed cells from fanout entanglement.
- [x] R.19 Fold-series lifetime retirement: carry the compression-only
      divide-by-five series in the selected destination stack word after its
      plain sum is no longer needed, with writes qualified so an in-range fold
      retains that sum. Fingerprint `67b0b3f73e3c`: 8,189 -> 8,164 placed LC
      (-25), 19 EBR unchanged; Yosys maps 7,138 LUT4, 1,658 carries and 1,578
      flops (-4/0/-18). The first unqualified form was rejected by the
      noise-fidelity gate because it overwrote in-range sums; the corrected
      form passes `make test-psg` at 906/1,275 sample and 5,022/7,654 tick
      clocks with zero late flips, the frozen matrix is 59/59 byte-identical,
      and Celeste music 30 remains at -0.09/+0.16/+0.07/+0.14 dB whole-track
      and -0.04 dB quiet 4-8 kHz.
- [x] R.20 Fold-remainder lifetime retirement: after the compression operand
      is consumed, reuse `fx_r[3:0]` for the divide-by-five remainder and
      remove the dedicated four-bit `fr_r`. Fingerprint `0ea9c400b998`:
      8,164 -> 8,138 placed LC (-26), 19 EBR unchanged; Yosys maps 7,116
      LUT4, 1,656 carries and 1,574 flops (-22/-2/-4). `make test-psg`
      remains at 906/1,275 sample and 5,022/7,654 tick clocks with zero late
      flips, and the frozen matrix is 59/59 byte-identical. The broadened
      final Celeste gate passes entry points 10, 20, 30 and 40, while entry
      point 0 exposes a pre-existing post-pattern-3 spectral mismatch retained
      for the later fidelity pass. The 59/59 render-exact regression gate is
      the commit criterion for this optimization.
- [x] R.21 Walker control-field deduplication: select all eleven multiplier
      launches with the existing capture/action opcode, adding `CAP_W75` for
      the sole launch-only phase and retiring the four-bit `MUL_SEL` field.
      Fingerprint `a106714c2ab0`: 8,138 -> 8,127 placed LC (-11), 19 EBR
      unchanged; Yosys maps 7,099 LUT4, 1,658 carries and 1,574 flops
      (-17/+2/0). `make test-psg` remains at 906/1,275 sample and
      5,022/7,654 tick clocks with zero late flips, and the frozen matrix is
      59/59 byte-identical. The updated schedule visualizer derives launches
      from the live request mux and finds no unexplained hardware-walk phase:
      46 are multiply-busy on every profile and 15 more are conditionally
      busy. The all-Celeste final gate retains the documented pre-existing
      music-0 mismatch for the later fidelity pass; it is not an optimization
      regression.
- [x] R.22 Multiplier leading-zero retirement: run the three constant-171
      reciprocal limbs in the existing eight-iteration mode instead of
      charging ten iterations. The change is exact across all three result
      ports in the cycle model and frees four multiplier iterations per
      non-wavetable visit or two per wavetable visit. It does not retime the
      fixed schedule and increases placement 8,127 -> 8,151 (+24), an
      accepted capacity trade. Fingerprint `c06087a366b8`; Yosys remains at
      7,099 LUT4, 1,658 carries, 1,574 flops and 19 EBR. The visualizer labels
      iteration reductions as retiming potential rather than automatic
      walker-clock savings, and identifies pph 92 as a completed-product hold
      before the fixed pph 93 consume rather than unexplained empty time.
- [x] R.23 Reciprocal sibling elimination: retain `341*x` and reconstruct
      `171*x` exactly as `(341*x + x) >> 1`, removing three multiplier
      launches and the 25-bit `g_part` register. The exhaustive model proves
      the identity for all 131,072 17-bit limb values. Before retiming,
      fingerprint `2c95ddbe92d6` maps 7,112 LUT4s, 1,686 carries, 1,549 flops,
      19 EBRs and 8,126 placed cells; `make test-psg` and the frozen matrix
      remain exact.
- [x] R.24 Multiplier-chain retiming: merge the mutually exclusive old-voice
      and wavetable launch phases, assign constant 341 the spare exact
      nine-iteration mode, and consume every product on its first readable
      phase. The hardware visit falls 109 -> 85 phases, improving `psg_tb`
      906 -> 714/1,275 sample clocks and 5,022 -> 3,555/7,654 tick clocks with
      zero late flips. Fingerprint `bcb0ac999e8d` maps 7,113 LUT4s, 1,682
      carries, 1,549 flops, 19 EBRs and 8,124 placed cells. The visualizer
      measures 32 clocks of data depth versus 55 on one service, zero
      request/consume slack, and no unexplained hardware phases; the frozen
      matrix remains 59/59 byte-identical. The provenance-bound final gate
      passes Celeste entry points 0, 10, 20, 30 and 40 from one source
      fingerprint, retaining only music 0's documented later-fidelity issue.
- [x] R.25 Six-bit service requests: add an explicit short request for the
      six-bit blend and pattern-length products. It runs six iterations using
      mode 1's unchanged alignment; the two consumers compensate for the
      exact product being shifted left four bits. The walker stays at 85
      phases / 714 clocks per sample, but the visualizer now measures
      30 clocks of data depth, 53 on one service, and two attributed
      completed-product hold phases. Fingerprint `2ecf587b7999` maps 7,142
      LUT4s, 1,677 carries, 1,549 flops, 19 EBRs and 8,138 placed cells
      (+29/-5/0/0/+14 from R.24), an accepted service-capacity trade. A direct
      1,226,752-sample Celeste music-20 comparison is byte-identical to R.24;
      `make test-psg`, the frozen 59-case matrix, and the provenance-bound
      Celeste 0/10/20/30/40 final gate all pass. The rejected 83-phase retime
      and blanket nine-iteration sequencer remap first diverged at 21.246 s
      and 42.493 s respectively despite passing the narrower gates.
- [x] R.26 Multiplier alignment unification: fix the accumulator boundary at 12
      for every request so the mode names an iteration count and nothing else.
      An N-step product then lands `|A| * B << (12 - N)`; each call site's
      count is fixed, so its consumer's offset is a constant and the
      compensation is wiring. The 22-bit accumulator-read mux, the 34-bit
      re-pack mux and the `m_mode` register retire, and the three result ports
      (`m_res`/`m_res_wide`/`m_res12` - 32, 34 and 28 bits of one register)
      collapse to one 34-bit view. `tools/psg_mul_model.py` proves the landing
      law across the full |A| sweep for all five live iteration counts, proves
      no landing overflows the 34-bit register, and now names all five consume
      offsets so a later edit cannot get one silently wrong. Fingerprint
      `0dde4052c511`: 8,138 -> 8,017 placed LC (-121), 19 EBR unchanged; Yosys
      maps 7,009 LUT4, 1,687 carries and 1,547 flops (-133/+10/-2), and the
      pre-mapping census moves 16,235 -> 16,089. No schedule moves:
      `make test-psg` remains at 714/1,275 sample and 3,555/7,654 tick clocks
      with zero late flips, the frozen matrix is 59/59 byte-exact against
      PICO-8 and byte-identical against the anchor, and all five Celeste entry
      points render byte-identically to R.25's WAVs. Two experiments refuted in
      the same pass, both by the same mechanism: narrowing `mul_start_a` 25 ->
      22 bits is exactly 0 cells (yosys already prunes bits no consumer reads,
      so a bound on a POSITION is not an invisible bound), and sharing the two
      comb networks is 0 cells (the comb is the identity at REVERB=0 and yosys
      already folds it - the -158 a constant ablation reported was the
      downstream blend subtract collapsing). **Ablate to the proposed
      replacement, never to a constant.**
