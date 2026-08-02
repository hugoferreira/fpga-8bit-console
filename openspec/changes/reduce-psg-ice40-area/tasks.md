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
- [x] 6.2 Build and run Celeste headlessly and confirm active, non-constant
      audio (`make shot GAME=celeste FRAMES=5` passes at the selected 18.75 MHz
      clock: 3,668 samples, range -24,668..24,659, 1,073 distinct levels)
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
- [x] R.27 Reciprocal-table condensation: apply the split identity a second
      time to its own remainder, choosing k with 2^k = d + 1 so the outer
      multiplier is 1 and the recombine gains a bare add rather than a shift.
      Every index then falls under 256 and every remainder under six bits, so
      `tab15` (2048x7, four blocks), `tab7` (1024x7, two) and `org3` (512x8,
      one) become three fields - 4 + 5 + 6 = 15 bits - of ONE 256x16 word,
      read through the single port the wsel-exclusive shapes already share.
      Exhaustively verified end to end over each shape's whole ramp (368,635 /
      172,030 / 65,535 values) before the RTL moved; two folds is also proven
      minimal, since one cannot reach an index below 256. One divisor is live
      per evaluation, so one index add serves all three - select the halves,
      add once - which is 22 structural cells cheaper than three adds racing
      to a mux. Fingerprint
      `b434542f3d01`: **19 -> 13 EBR**, with the explicit trade 8,017 -> 8,092
      placed LC (+75); Yosys maps 7,076 LUT4, 1,693 carries and 1,554 flops
      (+67/+6/+7), pre-map census 16,089 -> 16,125. That is +12.5 placed cells
      per block against the +39..+47 R.15/R.16/R.17 each paid, and it takes
      the standalone target under this change's 15-EBR ceiling for the first
      time. `make test-psg` remains at 714/1,275 sample and 3,555/7,654 tick
      clocks with zero late flips, the frozen matrix is 59/59 byte-exact, and
      all five Celeste entry points are byte-identical to R.26's renders.
      Checked, not assumed, for the other three memories: `aram` is 4,608x8 =
      100% of nine blocks (the PICO-8 audio image is exactly that size),
      `crom` uses 253 of 256 words, and `state_m`'s half-empty second block is
      the deliberate landing site for the record migrations.
- [x] R.28 Control-word decode fold, and the defect it exposed. The walker
      decoded a five-bit opcode into sixteen actions every cycle - logic
      applied to a table value, paid for in R.16/R.17 when blocks were the
      binding resource. Blocks are not scarce now, and the reversal is FREE
      rather than costing one: there are exactly sixteen actions so one-hot is
      the SAME 16-bit word on the SAME shared port; all six former flag bits
      are aliases of an action's phase (SYN_A/W0, SYN_B+ISS_SEC/W1,
      ISS_OLDMAIN/W2, ISS_OLDSEC/W3, DQ_OLD/W5); and CAP_FOLD's phase IS
      PLAST, which the walk already tests. Both step decodes become
      `(* parallel_case *) case (1'b1)` - R.9's measured spelling, since a
      parallel IF chain builds a priority network (+154).
      **The first attempt FAILED its gate and that is the valuable part.**
      `make test-psg`, the 59-case matrix and the tolerance gate all passed;
      the direct byte comparison against the previous RTL did not - music 20
      diverged at 16.997 s, 39% of samples, max delta 41,475. Probing found
      the cause: `ctrl_addr` is only selected onto the shared port while
      `prun` is set, so the word registered for pph 0 was fetched a cycle
      BEFORE the walk started, while the sequencer owned the port. Slot 0
      reads a stale pitch word (measured: 0x00c2, decoding to CAP_W1) on the
      first phase of EVERY visit and executes it against the previous slot's
      state. Slots 1..7 are fine (pph_nxt wraps to 0 under prun). It was
      invisible only because CAP_W1's writes are all overwritten or gated
      before use - luck, not design, since the stale word is whichever pitch
      word the sequencer last addressed. One-hot decodes the same garbage into
      SEVERAL actions, which is not inert. Gating the word to zero at pph 0 is
      exactly "the schedule has no action at pph 0", now asserted in
      gen_psg_ctrl.py; applied to the UNCHANGED encoded design it is
      byte-identical (music 20 identical over 1,226,752 samples, PICO-8
      fidelity numbers unmoved), so it is a render-neutral prerequisite rather
      than a render change. Fingerprint `12037fb1cc6e`: 8,092 -> 8,078 placed
      LC (-14), Yosys maps 7,065 LUT4, 1,690 carries, 1,554 flops (-11/-3/0),
      **13 EBR unchanged**, pre-map census 16,125 -> 16,089 (-36). The fold
      alone is -45 LUT4 / -56 placed; the gate costs +34 LUT4 of it. The
      placed delta is inside the mapping-noise band, so the cell claim rests
      on the structural number - the real return is the defect and what it
      unblocks. `make test-psg` remains at 714/1,275 and 3,555/7,654 with zero
      late flips, the frozen matrix is 59/59 byte-exact, and all five Celeste
      entry points are byte-identical.
      Audited and found NOT foldable, so nobody re-derives it: `pinc`'s `<< 8`
      is already folded (that is why it is stored in 13 bits), `fstep` feeds an
      accumulator, the slide affine's r/b are variable-operand inputs, and
      `recip`'s only nearby constant is applied after the mux with the
      non-table tail path - folding it in would buy a second subtract.
- [x] R.29 REFUTED with numbers, do not retry in this shape. The rest of the
      walker's pph-derived fabric - `wlk_ra`/`wlk_wa`'s comparators, subtracts
      and adds, `state_sample_read`, `state_sample_we`, `state_lp_we` - was
      built as a 128 x 16 control word in its own block (absolute read and
      write words plus four enable bits; PSG_V_PAR1 = PSG_V_PAR0 + 4 and a
      parameter offset is 0..3, so bank selection is an OR of bit 2 and
      `ispar` is `ra[4] & ra[3]`, which no oscillator word sets). It is
      RENDER-EXACT - 400,000 samples of Celeste music 20 byte-identical,
      `make test-psg` unchanged, and the preview flavour keeps its expressions
      under `REALTIME_PREVIEW`. It is also not worth a block:
        shape ablation (arbitrary contents)  16,080 -> 15,992  (-88)
        real, 14-bit word, offset write addr 16,089 -> 16,016  (-73)
              -> placed 8,078 -> 8,110 (+32), LUT4 7,065 -> 7,127 (+62)
        real, 16-bit word, absolute write    16,089 -> 16,014  (-75)
              -> placed 8,078 -> 8,064 (-14), LUT4 7,065 -> 7,086 (+21),
                 carries 1,690 -> 1,667 (-23), 13 -> 14 EBR
      **-75 structural cells map to +21 LUT4s.** The reason generalises: the
      pph comparator fabric is SHARED across many consumers - the record-load
      `case (pph)`, `s_stw`, `pph == PWORK+26`, `pph == PLAST` - so peeling
      individual consumers off it removes terms without retiring the decode,
      and abc9 re-covers what is left worse than it covered the whole. A -14
      placed delta is inside the +/-60 mapping-noise band, so nothing is even
      established, and it costs one of the blocks R.27 banked.
      **The condition under which this could pay: move EVERY pph-derived
      decode at once**, the 18-arm record-load case included, so the fabric
      actually stops existing. That needs a load-slot field the 16-bit word
      has no room for, hence two blocks (13 -> 15) - still inside this
      change's EBR ceiling, and the only version worth measuring next.
- [ ] R.30 THE LARGEST REMAINING LEVER, measured: the noise walk evaluates
      `(nz_mul_j * nz_mul_rand) >>> 8` on a 17 x 8 PARALLEL multiplier - the
      one `*` left in the hardware lowering, on a chip built around one shared
      iterative service. `nz_out_r`'s cone is the biggest LUT4 family in the
      design at 480. Ablated (product replaced by a same-width non-constant
      wiring function of the same operands; clamps, accumulator and
      publication untouched): **8,078 -> 7,771 placed (-307), 7,065 -> 6,771
      LUT4 (-294), 1,690 -> 1,653 carries, 13 EBR unchanged, pre-map 16,089 ->
      15,382.** 105% -> 101% of the HX8K, 91 cells from placing.
      Destination is the EXISTING service, not new hardware: |A| = nz_mul_j is
      17 bits (inside the 2^21 ceiling), B = |nz_mul_rand| <= 128 fits mode 0.
      Two requirements: (1) `>>> 8` on a signed product is FLOOR while the
      service's magnitude domain truncates toward zero - the negative arm needs
      the +255 round-up, provable in tools/psg_mul_model.py before any RTL
      moves; (2) the operands only settle with the record load, so the two
      requests go in the load window (the service is idle there - the first
      existing request is CAP_W4) and PWORK/PSTOR/PFOLD/PLAST all shift later
      by ~8 phases together, preserving every relative relationship. ~714 ->
      ~778 clocks/sample against 561 spare. Schedule change on the most
      fidelity-delicate path: gate on the 400k-sample music-20 byte comparison
      (80-second loop) BEFORE the full battery.
      Priced alongside and CLOSED: `nz_thresh = nz_sum / 3` ablates at -726
      pre-mapping cells but R.15 already measured its exact replacement at +57
      LUT4 / +22 placed - structural cells are not LUT4s. `nz_kick_m` is
      already a masked shift-add. Re-measured standalone 2026-07-31 and the
      -726 is confirmed fiction: the divider is 713 pre-map cells and 63
      placed LCs (11:1, because `$div` lowers to a restoring array before the
      constant divisor is exploited and abc9 deletes ~92% of it), against 1:1
      for the arithmetic that would replace it. design.md section 23 has the
      table, the mechanism and the per-family ratio rule; psg_ff_census.py's
      docstring has the carve-out.
- [x] R.31 CAP_W75's two phases of slack, re-examined on request. It is the
      only non-zero in the schedule: the short six-iteration blend request
      launches at pph 70, is readable at 77, and CAP_W84 consumes it at 79.
      Closing it is EXACTLY the retime R.25 built and rejected - "moving the
      fixed walker consume two phases earlier" passed `make test-psg`, the
      59-case oracle AND the spectral tolerance gate, then diverged in Celeste
      music 20 at 21.246 s (433,450 differing samples, max delta 20,144). It
      is also worth nothing binding: 2 phases x 8 slots = 16 clocks/sample
      against 561 spare, and the slack is a WAIT, not service capacity - the
      service is free from phase 77 either way. The schedule give it reveals is
      better spent on R.30, which needs ~8 phases and returns 307 cells.
- [x] R.32 SEQ_BUDGET built and MEASURED; not landed, and it re-prices R.30.
      The visit's LENGTH is render-load-bearing: shifting PWORK/PSTOR/PFOLD/
      PLAST by +13 with no arithmetic change moves 2 of 400,000 music-20
      samples. The recorded fix - a fixed per-interval cycle offer for the
      sequencer - was written up as landed but `git grep SEQ_BUDGET` finds
      nothing in the RTL (`1261e19` is the measurement commit and never
      mentions it), so it was built here.
      Control: with a budget too large to bind, music 20 is byte-identical to
      HEAD over 400,000 samples - the counter is inert and every difference is
      the bound. (The first control used a 9-bit counter and 1023, which
      truncates to 511 and bound anyway; check the control as carefully as the
      experiment.)
      Probed: the cycles offered per interval are **a constant 565**, every
      interval, over 400,000 samples - the walk is a fixed program, so the
      leftover is fixed. The design is ALREADY deterministic at a fixed clock
      and fixed walk length; only changes to either move it.
      Measured cost of bounding below 565, on the provenance-bound gate:
        unbounded  pre-run 3,555/7,654  music-20 lock 0.83  94/110  pass
        416        pre-run 4,705/7,654  lock 0.73          59/110  pass
        288        pre-run 6,053/7,654  lock 0.71          49/110  FAIL
      Both keep psg_tb at zero late flips and the matrix at 59/59 byte-exact
      vs PICO-8 (only mix-four moves, a pure one-sample onset shift,
      bit-identical at lag +1) - **the oracle is blind to the property the
      bound changes.** Invariance needs budget <= leftover and fidelity needs
      budget >= demand; at 28.125 MHz both meet at 565, i.e. f_min = exactly
      the shipping clock and zero room for the walk to grow. Counter costs +18
      placed cells. Not landed.
      **Re-prices R.30**: its cost is not a re-frozen baseline, it is that the
      sequencer loses 104 of 565 cycles/sample, landing it in the degraded
      band above. Buy the 13 phases back inside the visit (41 of the 85 are
      multiply-latency shadow) and R.30 is free; otherwise it is a fidelity
      trade to adjudicate on the five-track gate, not a free -307 cells.
- [x] R.33 Radix-4 multiply service. The section-20 landing law generalises to
      `m_p after M steps = |A|*B * 2^(12 - RADIX_BITS*M)`, so a radix-4 step
      retiring TWO multiplier bits means **M = N/2 lands exactly where radix-2
      at N did and no consumer slice moves anywhere**: 12->6, 10->5, 8->4,
      6->3. Mode 3's nine is the one odd count; loading `B << 1` for that mode
      alone restores its landing, and its B < 2^9 contract leaves room. Average
      latency 10.0 -> 5.6 cycles. 3A is combinational: registering it costs 23
      flops to save an adder and measured 282 LC / 99.7 MHz against 259 /
      118.9. `tools/psg_mul_model.py` now reads the radix from the write-back
      shift and the pre-shift from the m_p load, and gates the engine against
      the SHIPPED radix-2 reference over every mode, every corner B, the whole
      |A| sweep and both signs - a permanent check, not a one-off.
      Fingerprint `6aaa743b4414`: pre-map 16,089 -> 16,173 (+84), Yosys 7,156
      LUT4 (+91), 1,711 carries (+21), 1,553 flops (-1), 13 EBR unchanged,
      placed 8,078 -> 8,171 (+93). The cost is real, not noise; R.34 pays it.
      Buys with ZERO schedule work: the tick side stalls on `!m_busy`, not on
      fixed phases, so `psg_tb` goes 3,555 -> **3,356** of 7,654 tick clocks
      with zero late flips - **-199 clocks/tick free**. The walk stays at
      714/1,275 because it is phase-pinned by the control ROM.
      **NOT render-neutral, and the mechanism matters.** The arithmetic is
      bit-identical (matrix 59/59 byte-exact vs PICO-8 AND byte-identical vs
      the anchor; music 20 byte-identical over 400,000 samples), but
      `psg_seq`'s effect microprogram STALLS on the service - `K_FX: if
      (!m_busy && ...)` gates the whole arm - so a shorter latency advances the
      micro-PC ~5 cycles earlier per product, six per slot, and the tick
      program finishes sooner. Where that crosses a sample boundary the render
      moves: **music 10, 2,202 of 848,896 samples (0.26%), first at 25.496 s**;
      the other four entry points byte-identical. Every fidelity number is
      unchanged (pitch 87.9%, spectrum 0.997, lock 0.72 at 37/75, rms 5,529 vs
      5,534) and the gate passes. SEQ_BUDGET would NOT have made this
      transparent - a fixed offer still lets a faster sequencer get further.
      Byte-neutrality would need `m_busy` padded to the radix-2 window, which
      is mutually exclusive with the recompaction unless the walk and the
      sequencer get separate busy signals. Retained as a render change on the
      evidence that no fidelity metric moves.
      Rejected with numbers: radix-8 (+253 LC standalone, Fmax -41%); folding
      the first step into the load cycle (+56 LC for one cycle, and it moves
      when `m_busy` RISES, which psg_seq's fire-and-forget `ptick_pend &&
      !m_busy` capture depends on - radix-4 only moves the deassert, which is
      why it is transparent); per-site mode retuning (real over-provisioning,
      but radix-4 collapses the gap to one cycle).
- [x] R.34 Control-ROM recompaction onto the radix-4 latency. Respacing every
      launch to `p + steps + 1` collapses the chain from 65 phases to 43 and
      the visit from **85 to 63**. Two collisions: W15 and W17 both want +11
      and ARE `s_snd_wt`-exclusive, so they share one action (guard inside, in
      both the request mux and the capture case); W26 and W27 canNOT merge -
      W26 writes the smp_b W27's operand reads - so they stay a phase apart and
      the non-wavetable chain waits it out with its product parked. Everything
      phase-relative outside the ROM moved with it and now reads a
      non-drifting source where possible: the late dampen writes are stated
      against `PLAST-2`/`PLAST-1`, the wavetable lerp base reads
      `cap[CAP_W26]`. gen_psg_ctrl.py asserts the store window and late writes
      still fit. Fingerprint `ffdb1243f85f`: pre-map 16,173 -> 16,138 (-35),
      7,094 LUT4 (-62), 1,718 carries (+7), 1,553 flops, 13 EBR, placed 8,171
      -> **8,123** (-48).
      **Walk 714 -> 538 of 1,275 clocks/sample; tick pre-run 3,356 -> 2,289 of
      7,654, 5,365 spare, zero late flips.** With R.33 the pair costs +45
      placed and returns 176 clocks a sample.
      **This settles R.32/R.30.** The sequencer's per-interval offer rises 565
      -> ~741. R.30 needs 8 phases at radix-4 (live launched at 18 readable 23,
      old at 23 readable 28, PWORK 19 -> 27) = 64 clocks, leaving the sequencer
      more than it has ever had - so R.30 no longer takes anything from it and
      the fidelity trade R.32 priced is bought out.
      Matrix 59/59 byte-exact vs PICO-8 AND byte-identical vs the anchor - a
      22-phase reschedule that moved no oracle sample. `make test-psg` passes.
      PICO-8 fidelity within tolerance on all five entry points; music 10's
      contour improved 0.967 -> 0.972.
- [x] R.35 Fidelity against PICO-8 as a REGRESSION gate
      (`tools/psg_pico8_fidelity.py`, `make test-psg-pico8`). The track gate's
      verdict is an ABSOLUTE tolerance, which is how R.32's SEQ_BUDGET=416 went
      green while moving music 20's lock 0.83 -> 0.73; seeing it needed two
      logs diffed by hand. This renders all five entry points, measures them
      against the committed recordings, and compares to a baseline in
      `tests/psg/pico8-fidelity.json`: a metric that worsens beyond tolerance
      FAILS, one that improves never does. Measured set is what actually moved
      in this campaign - lock median and blocks-holding-lag (sequencer timing
      drift), the contour correlation (the unpitched metric), and the twelve
      band levels. The baseline is fidelity against PICO-8, NOT against our own
      previous render: ours is not ground truth. That is what lets a schedule
      change that moves samples pass while a change that moves the sound fails.
- [x] R.30 DONE. The noise walk's 17x8 PARALLEL multiplier - the last `*` in
      the hardware lowering, and the largest LUT4 family in the design - moves
      onto the shared service as two ordinary mode-0 requests. |A| = j is 17
      bits (inside the 2^21 ceiling), B = |rand| <= 128 fits mode 0, and mode 0
      is four radix-4 steps landing four places left, so the magnitude is
      `m_res[27:4]`. Three requirements, all met:
      (1) `>>> 8` on a signed product is FLOOR while the magnitude domain
      truncates toward zero, so the negative arm rounds up (+255 equivalent);
      (2) the old step used to be evaluated at CAP_W1, AFTER CAP_W0's edge, so
      on a restart sample it saw the s_last_inc that CAP_W0 had just copied
      into s_old_inc - running it in the load window needs that decision
      factored into `blend_restart` and the increment selected as
      `blend_restart ? s_last_inc : s_old_inc`. Missing this was wrong on
      exactly the tick boundaries (2,202 music-20 samples in an earlier
      attempt); (3) the service is idle through the load window, so NZ_OLD
      launches at 19 (the first phase its cone is valid, s_eff_a being the last
      word in) readable at 24, and NZ_LIVE takes the service on that cycle,
      readable at 29 - so only the old product needs a register. PWORK 19 -> 29
      with PSTOR/PFOLD/PLAST following. A simulation assertion fires if either
      phase ever finds the service busy, because the request mux drops rather
      than queues. `nz2_rand_r` retires - both draws are pre-advance now.
      Fingerprint `2dc67844558a`: pre-map 16,138 -> **15,674 (-464)**, 6,923
      LUT4 (-171), 1,718 carries, 1,563 flops (+10), 13 EBR, placed 8,123 ->
      **7,931 (-192)**. **103% of the HX8K, 251 cells from placing.**
      Visit 63 -> 73 phases: walk 538 -> 618 of 1,275, still 96 below where
      this session started; tick pre-run 2,443/7,654, 5,211 spare, zero late
      flips. Music 20 byte-identical over 400,000 samples, matrix 59/59
      byte-exact vs PICO-8 AND byte-identical vs the anchor, PICO-8 fidelity
      within tolerance on all five entry points.
- [x] R.36 Group the multiply requests by OPERANDS, not by phase. A per-module
      census misleads on a flattened netlist: `u_mul` reads 670 LUT4 for one
      iterative engine because `m_a`'s D-cone (~250) is the flattened REQUEST
      MUX named after the flop it drives. The service's operand selection was
      ~470 LUT4 - THE LAW as a measurement.
      Seven arms, one per launching phase, but the phases are mutually
      exclusive and several ask the same shape: the two noise requests are one
      expression (`J = 8*dp + 1120` against `|draw|`) on different increments
      and draws; the wavetable lerp is the same 9-bit delta x 10-bit fraction
      at W4 and W15; the G pass is `|z| x G` at W4 and W27; and the retained
      `x*341` limb is IDENTICAL at W15 and W40. Seven arms become four - three
      25-bit arms, a 17-bit adder and a duplicated 12-bit constant stop
      existing, replaced by a 13-bit select, a 9-bit select and two one-bit
      ones. Fingerprint `d583d0cd1b29`: pre-map 15,674 -> **15,506 (-168)**,
      6,868 LUT4 (-55), 1,709 carries (-9), 1,563 flops, 13 EBR, placed 7,931
      -> **7,877 (-54)**. **102% of the HX8K, 197 cells from placing.**
      Schedule and arithmetic untouched: test-psg unchanged at 618/1,275 and
      2,443/7,654, music 20 byte-identical over 400,000 samples, matrix 59/59
      byte-exact vs PICO-8 AND byte-identical vs the anchor, PICO-8 fidelity
      within tolerance.
      **Reusable: when two arms of a wide selector want the same expression,
      select its OPERANDS - selection should happen where the values are
      narrowest.**
- [x] R.37 Lifetime retirement: the old noise step has no register of its own.
      `mx_old` is dead from the visit's start until CAP_W51 writes it at pph
      60, and the old noise step is written at PNZ_LIVE (24) and read at
      CAP_W1 (30) - thirty phases of clear air. |step| <= 33,324, so mx_old's
      seventeen signed bits hold it exactly, and `nz2_step_r` retires.
      **The two metrics DISAGREE here and the flop one is right**: pre-map
      15,487 -> 15,505 (**+18**, the fanout-entanglement signature that
      refuted reusing smp_a for gz_s1_r in R.18), but placed 7,907 -> **7,869
      (-38)** with 6,861 LUT4 (-29) and 1,563 -> 1,545 flops (-18). The
      retired flops were UNPACKABLE - whole logic cells - which is the entire
      reason tools/psg_ff_census.py exists. **A lifetime retirement must be
      judged on placed cells and the flop count, never on the pre-mapping
      census.** 189 cells from placing.
      `make test-psg` unchanged at 618/1,275 and 2,443/7,654, music 20
      byte-identical over 400,000 samples, matrix 59/59 byte-exact vs PICO-8
      AND byte-identical vs the anchor.
- [ ] R.38 Record migration, RE-PRICED and the plan inverted. Collapsing each
      array to a single shared register bounds what moving it into the record
      can return: `sfx_id[8]` alone **-76** pre-map (~25 cells), `trg_row[4]` +
      `trg_len[4]` **-134** (~44), additive at -210. **R.7's advice to lead
      with sfx_id is backwards**: trg_row/trg_len are the bigger half AND the
      easier one - one-shot parameters, CPU-written, consumed once at
      T_FL/K_ADV and cleared - while sfx_id is read COMBINATIONALLY by
      `ch_base = rec_base(sfx_id[c])` throughout the trigger pass, which is
      what forced R.6b's working-register staging and made it price as a wash.
      At this session's measured structural->placed conversion (~0.35) the
      -210 bound is about -73 placed, and the asynchronous CPU writes eat into
      it: they need either a direct record write when `etk_we` is free plus a
      small pending buffer for collisions, or staging that costs back much of
      what the array gave. Realistically -40..60 placed.
- [x] R.39 Lifetime analysis as a tool, and the retirement it found.
      `tools/psg_lifetimes.py` (`make psg-lifetimes`) derives every walk
      register's live range from the RTL and lists the pairs whose ranges are
      disjoint and whose widths fit. Three things it has to model, each of
      which made the first draft WRONG in the unsafe direction:
      (a) record-streamed state is live from its LOAD phase to its STORE
      phase, not just where the action arms touch it - without this it
      proposed retiring `s_lp`, which would corrupt saved state;
      (b) reads inside tasks - `noise_filt_step`, `stage_leaf`, `fold_launch`
      do most of the walk's register writing, and missing them UNDER-reports a
      live range;
      (c) elaboration - REALTIME_PREVIEW arms are not in the hardware
      lowering, and without stripping them `sa_hold` looks like a live host
      that does not exist.
      **Found and landed: `mx_prod` (live 67..69) retires into `smp_a` (live
      30..47), twenty phases clear.** smp_a is 18 bits to mx_prod's 17, so the
      role is `$signed` of its low slice and the writes sign-extend.
      Placed 7,869 -> **7,805 (-64)**, 6,808 LUT4 (-53), flops 1,545 ->
      **1,493 (-52)** - three times the seventeen the register itself holds,
      so its D-mux and enable fabric went with it. Pre-map 15,505 -> 15,165.
      **101% of the HX8K, 125 cells from placing.**
      `make test-psg` unchanged at 618/1,275 and 2,443/7,654, music 20
      byte-identical over 400,000 samples, matrix 59/59 byte-exact vs PICO-8
      AND byte-identical vs the anchor.
      Remaining candidates the tool ranks, each ~17 flops and each needing its
      own measurement: `mx_filt` into `smp_a`/`smp_b` (22 phases clear),
      `mx_new` into `nz_old_out_r` (7), `gz_s1_r` into `mx_filt` (9). The tool
      does NOT predict whether one pays - fanout entanglement decides that,
      and the prior is one win (R.37, -38) against one loss (R.18's smp_a /
      gz_s1_r, +24 despite -17 flops).
- [x] R.40 REJECTED: retire `mx_filt` into `smp_b`. The derived live ranges are
      disjoint by 22 phases: `smp_b` is live at 32..47 and the filtered result
      at 69..72. This is the surviving `mx_filt` pairing named by R.39 after
      R.39 itself extended `smp_a` through phase 69; it is not a retry of the
      rejected `gz_s1_r` -> `smp_a` pairing. Baseline fingerprint
      `9915c1bd1ccf`: 6,780 LUT4, 1,692 carries, 1,483 flops, 13 EBRs and
      7,774 placed LCs (94 over capacity). Replace the dedicated 17-bit
      register with a signed low-slice role on the existing 18-bit `smp_b`,
      sign-extending the phase-69 write. It removed sixteen mapped flops but
      added five LUT4s and reduced carries by five; placement moved 7,774 ->
      **7,775 (+1)**, so the fanout/D-mux entanglement consumed the entire
      retirement. Reverted before the render battery. Repeat only if a later
      schedule or fanout change alters either register's live range or packing
      cone.
- [x] R.41 REJECTED: retire `mx_new` into `nz_old_out_r`. The derived live
      ranges are disjoint with seven phases clear: `nz_old_out_r` is live at
      30..40 and `mx_new` at 47..67. The 18-bit host can carry the complete
      signed 17-bit result by sign-extending both existing writes. Baseline is
      unchanged from R.40: fingerprint `9915c1bd1ccf`, 6,780 LUT4, 1,692
      carries, 1,483 flops, 13 EBRs and 7,774 placed LCs. Accept only if the
      structural/render gates pass and placement falls. It removed eleven
      mapped flops but added 22 LUT4s and one carry; placement moved 7,774 ->
      **7,791 (+17)**. The early noise-state fanout and late mix-result fanout
      do not pack as one register. Reverted before the render battery. Repeat
      only if a later schedule or fanout change alters either lifetime or
      packing cone.
- [x] R.42 REJECTED: merge `mx_filt` and `gz_s1_r`. Their derived live ranges
      are disjoint with nine phases clear: the reciprocal/gain limb is live at
      40..60 and the filtered result at 69..72. Unlike R.40/R.41, both roles
      remain inside the gain/filter arithmetic family and neither host carries
      waveform or persistent-noise fanout. Keep the existing 17-bit
      `gz_s1_r` storage, expose its late role as signed, and replace the
      phase-69 `mx_filt` write. Baseline: fingerprint `9915c1bd1ccf`, 6,780
      LUT4, 1,692 carries, 1,483 flops, 13 EBRs and 7,774 placed LCs. Accept
      only if the structural/render gates pass and placement falls. It removed
      sixteen mapped flops but added 44 LUT4s and five carries; placement moved
      7,774 -> **7,812 (+38)**. Reverted before the render battery. Together,
      R.40/R.41/R.42 are three consecutive failures of the same lifetime-merge
      mechanism, so close the remaining smaller pairings under the research
      stop rule. Repeat only after a schedule or fanout change materially
      changes the register cones.
- [x] R.43 ACCEPTED: retire `psg_aram.last_addr`. A synthesis-port borrow raises
      `seq_frozen`, which is part of `psg_seq.seq_hold`; the sequencer state and
      therefore `seq_addr` stay unchanged throughout both the borrow and the
      following `replay` cycle. The explicit 13-bit address copy is therefore
      redundant: keep the replay hold but select `seq_addr` directly whenever
      `syn_rd` is false. This is control-contract elimination, not another
      lifetime merge, and design section 5b already identified `last_addr` as
      unpackable remaining state without recording an experiment. Baseline:
      fingerprint `9915c1bd1ccf`, 6,780 LUT4, 1,692 carries, 1,483 flops, 13
      EBRs and 7,774 placed LCs. Accept only if the structural/render gates
      pass and placement falls; repeat only if the borrow/freeze contract or
      sequencer address generation changes. Fingerprint `509c0b4911a6`:
      6,750 LUT4, 1,693 carries, 1,470 flops, 13 EBRs and 7,737 placed LCs,
      **-37 placed cells** and -13 flops from the unchanged baseline. The
      standalone target is now 57 cells over capacity. `make test-psg` passes
      at 618/1,275 sample clocks and 2,443/7,654 tick clocks with zero late
      flips; the noise-fidelity, 9/9 reference and structural gates pass; and
      `tools/psg_oracle_bytecheck.py` is 59/59 byte-identical against the
      latest accepted lifetime render set.
- [x] R.44 REJECTED: migrate `trg_row[4]` and `trg_len[4]` from 44 unpackable
      flops into one dedicated 256x8 EBR, spending one of the two blocks still
      available under the 15-EBR ceiling. Row and length use separate byte
      addresses so each CPU write is a complete single-port memory write;
      four row-valid and four length-valid bits preserve consume-and-clear
      without clearing the RAM. Synchronously read both values during `V_LD`,
      staging row in dead `note_lo[4:0]` and length in dead `arp_p[5:0]`, then
      consume the staged values at `T_FL`. A CPU write to the foreground slot
      being loaded during `V_LD` or `K_ADV` bypasses into the staging register
      to avoid read-during-write ambiguity. At `T_FL`, a coincident CPU write
      wins validity for the next trigger, matching the old later textual
      assignment. Baseline is R.43: fingerprint `509c0b4911a6`, 6,750 LUT4,
      1,693 carries, 1,470 flops, 13 EBRs and 7,737 placed LCs. Accept only at
      <=15 EBRs, lower placed LC, and all R.43 structural/render gates clean;
      repeat only if trigger ownership, V_LD scheduling, or the spare-EBR
      budget changes. Fingerprint `371994e67dbc`: the intended EBR inferred,
      but the read/write addressing, validity and collision-bypass fabric
      raised LUT4 6,750 -> **6,811 (+61)** while carries fell 1 and flops fell
      only 18, to 1,452. EBRs rose 13 -> 14 and placement moved 7,737 ->
      **7,748 (+11)**, failing the required placed-cell reduction. Reverted
      before the render battery. Repeat only if the bytes can share an
      existing address-selected store or a changed visibility contract removes
      the asynchronous write/bypass fabric.
- [x] R.45 ACCEPTED: migrate full-schedule `clr_ack[8]` into the existing
      oscillator record. The acknowledgement is walker-owned, read and written
      only for `pc_ch`, and oscillator word 3 has one spare high bit while its
      scheduled load precedes `CAP_W0` and its scheduled store follows the
      clear decision. Stream that bit through one `s_clr_ack` working flop and
      keep the preview-only acknowledgement array behind `REALTIME_PREVIEW`,
      where the phase-0 inactive-slot fast path still needs random access.
      This is the address-selected-storage shape R.44 could not use: no new
      EBR, no CPU write port, no collision validity or bypass fabric. Baseline
      is R.43: fingerprint `509c0b4911a6`, 6,750 LUT4, 1,693 carries, 1,470
      flops, 13 EBRs and 7,737 placed LCs; the census attributes eight
      unpackable flops and 257 LUT4s to `clr_ack`. Accept only if placement
      falls, EBR remains <=15, the preview/full structural deadlines pass,
      and the 59-case render set remains byte-identical. Repeat only if the
      oscillator record layout or preview fast-path ownership changes.
      Fingerprint `23a3f6a47f82`: 6,717 LUT4 (-33), 1,692 carries (-1),
      1,463 flops (-7), 13 EBRs and **7,698 placed LCs (-39)**. The target is
      now only 18 cells over capacity. `make test-psg` passes the noise-fidelity
      gate, 9/9 reference checks and all structural cases at unchanged
      618/1,275 sample and 2,443/7,654 tick clocks with zero late flips;
      `tools/psg_oracle_bytecheck.py` is 59/59 byte-identical. The preview
      elaboration retains its array path and completes at 196/1,275 sample and
      1,616/7,654 tick clocks with zero overruns, late flips or lost state
      writes (its broad bench still reports the preview-specific dampen and
      disabled-reverb feature checks, outside this structural gate).
- [x] R.46 RETAINED, ROUTED CUMULATIVELY WITH R.49, TIMING OPEN: migrate the matching
      full-schedule `clr_tog[8]` request
      token into address-selected storage. Oscillator word 32 already streams
      `w_row` through `V_LD`/`V_ST` and has eleven spare bits, so carry one
      `w_clr_tog` there, toggle it at `T_FL`, and publish it in the existing
      sounding word-3 bit. The full walker loads that bit before `CAP_W0` and
      compares it with R.45's streamed acknowledgement. Keep the direct
      `clr_tog` array only for `REALTIME_PREVIEW`; after elaboration the full
      target should trim it because it has no consumer. This removes another
      random-index sequencer array without a new port or EBR, but may delay a
      clear from trigger service to atomic parameter publication, so the
      59-case byte gate decides render equivalence. Baseline is R.45:
      fingerprint `23a3f6a47f82`, 6,717 LUT4, 1,692 carries, 1,463 flops,
      13 EBRs and 7,698 placed LCs. Accept only if the target fits at <=15 EBR,
      full and preview structural gates pass, and renders remain 59/59 exact;
      repeat only if trigger/publication ordering changes. Fingerprint
      `29478ed500ad`: 6,687 LUT4 (-30), 1,691 carries (-1), 1,457 flops (-6),
      13 EBRs and **7,669 placed LCs (-29)**, the first sub-capacity result in
      this resumed loop with 11 cells spare. The publication-timing risk is
      clean: `tools/psg_oracle_bytecheck.py` is 59/59 byte-identical. Routing
      did not converge at this density: after more than eight minutes the
      seed-1 router remained stuck with 8,761 arcs and no progress, so the run
      was stopped. A second run at the actual 28.125 MHz constraint reproduced
      the same 8,761-arc stall, excluding the default 50 MHz target as the
      cause. R.49 adds enough headroom for the cumulative R.46 logic to route,
      so the storage migration is retained; the cumulative timing result is
      still below 28.125 MHz. Repeat only if trigger/publication ordering
      changes.
- [x] R.47 REJECTED: remove reset and consume-clear muxes from `trg_row[4]` and
      `trg_len[4]` without moving their values. Keep the 44 value flops, add
      four row-valid and four length-valid bits, set validity on each CPU field
      write, select zero at `T_FL` when invalid, and clear only the eight valid
      bits. The values are then unobservable before their first write and need
      neither reset nor a T_FL zero assignment. A CPU write coincident with
      `T_FL` still wins because its later validity assignment is retained.
      This is not R.44's rejected dedicated-RAM mechanism: there is no EBR,
      address port, synchronous read or bypass fabric. Baseline is the R.46
      candidate: fingerprint `29478ed500ad`, 6,687 LUT4, 1,691 carries, 1,457
      flops, 13 EBRs and 7,669 placed LCs. Accept the cumulative R.46/R.47
      checkpoint only if seed-1 routes, full/preview structural gates pass and
      renders remain 59/59 exact; repeat only if trigger-field reset or
      consume semantics change. Fingerprint `734cec2e45da`: the eight validity
      flops replaced the removed reset cells exactly, but selecting zero at
      consume added 57 LUT4s; mapped totals were 6,744 LUT4, 1,691 carries,
      1,465 flops and 13 EBRs. Placement regressed 7,669 -> **7,721 (+52)**.
      Reverted before functional gates. The value arrays are cheaper with
      their direct clear arms; do not retry validity masking without a storage
      or interface change that removes the value mux too.
- [x] R.48 REJECTED: factor the audio-RAM upload address into its natural
      256-byte page and byte fields. The current 16-bit `wraddr - 16'h3100`
      plus `<4608` validity check hides that the accepted interval is exactly
      pages `$31..$42`: let `up_page = wraddr[15:8] - 8'h31`, accept
      `up_page < 18`, and form the zero-based 13-bit EBR address as
      `{up_page[4:0], wraddr[7:0]}`. This preserves every in-range address,
      every out-of-range rejection and full 16-bit auto-increment behavior,
      while replacing a 16-bit subtract/compare cone with an eight-bit page
      cone and wiring. Baseline is the R.46 candidate: fingerprint
      `29478ed500ad`, 6,687 LUT4, 1,691 carries, 1,457 flops, 13 EBRs and
      7,669 placed LCs. Accept the cumulative checkpoint only if exhaustive
      address equivalence passes, seed-1 routes, and the R.46 structural/render
      gates remain clean. Exhaustive comparison over all 65,536 addresses
      proved identical validity (4,608 accepted, 60,928 rejected) and indices
      0..4,607. Fingerprint `a0ac54edfe27` maps 6,686 LUT4 (-1), 1,695 carries
      (+4), 1,457 flops and 13 EBRs; placement regresses 7,669 -> **7,671
      (+2)**. Seed-1 routing completes under both the default 50 MHz and actual
      28.125 MHz targets, but reaches only **21.24 MHz**, below the required
      28.125 MHz. The structural suite remains at 618/1,275 sample clocks and
      2,443/7,654 tick clocks with zero late flips, and the frozen renders are
      59/59 byte-identical. Reverted because it adds no headroom and does not
      close timing. Repeat only if the upload interval or synthesis mapping
      changes.
- [x] R.49 ACCEPTED AREA/ROUTE, TIMING OPEN: retire the full-schedule `dry16`
      handoff register. The
      serialized fold already leaves its completed signed result in `fstk[0]`
      throughout the following `dry_valid` commit cycle, so full mode can
      drive the handoff directly from that persistent stack word while preview
      keeps its dedicated result register. `psg.sv` still qualifies `pcm` with
      the registered `dry_valid`, preserving the commit edge. This is not a
      retry of the pre-fold final-mix removal: the address-selected fold stack
      did not exist for that experiment, while the current census identifies
      all 16 `dry16` flops as unpackable. Baseline is R.46: fingerprint
      `29478ed500ad`, 6,687 LUT4, 1,691 carries, 1,457 flops, 13 EBRs and 7,669
      placed LCs. Accept only if mapped flops and placement fall, seed-1 routes
      at the actual 28.125 MHz constraint, and the structural/render gates
      remain exact. Fingerprint `13975f7d1225` maps 6,687 LUT4, 1,689 carries
      (-2), 1,441 flops (-16) and 13 EBRs; placement falls 7,669 -> **7,651
      (-18)** and seed-1 routing completes with 29 cells spare. Routed Fmax
      improves only to **21.48 MHz**, still below 28.125 MHz, so this is an
      accepted area/route stage rather than timing closure. `make test-psg`
      passes at unchanged 618/1,275 sample and 2,443/7,654 tick clocks with
      zero late flips; the frozen renders are 59/59 byte-identical. Repeat only
      if the fold destination or commit timing changes.
- [x] R.50 ACCEPTED, ROUTED TIMING FIT: replace the pitched-noise kick
      threshold's constant divide
      with its exact scaled comparison. The R.49 route's critical path runs
      from `s_eff_inc` through `nz_sum / 3`, the LFSR threshold compare and
      kick/filter cone to `s_noise_lp`: 20.62 ns logic plus 25.93 ns routing,
      for 21.48 MHz. For `g = {lfsr[14:7], lfsr[4:0]}`, rewrite
      `g < floor((dp+500)/3)` as `3*g <= dp+497`. R.15 closed this form only
      because its ~23-cell area improvement was inside the then-binding
      mapping-noise floor; a completed route now identifies the divider as the
      timing bottleneck, which is the new evidence permitting the retry.
      Exhaustively prove all 8,192 x 8,192 `(dp,g)` pairs before editing.
      Baseline is R.49: fingerprint `13975f7d1225`, 6,687 LUT4, 1,689 carries,
      1,441 flops, 13 EBRs, 7,651 placed LCs and 21.48 MHz routed. Accept only
      if seed-1 routed Fmax materially improves without an area regression and
      all structural/render gates remain exact. Exhaustive NumPy comparison of
      all **67,108,864** pairs proves the two predicates identical. Fingerprint
      `164161d6ad9e` maps 6,682 LUT4 (-5), 1,681 carries (-8), 1,441 flops and
      13 EBRs; placement falls 7,651 -> **7,607 (-44)**, leaving 73 cells
      spare. Seed-1 routes at **34.93 MHz**, passing the actual 28.125 MHz
      clock by 6.80 MHz and replacing the divider path with a new wave-to-sample
      critical path. `make test-psg` passes at unchanged 618/1,275 sample and
      2,443/7,654 tick clocks with zero late flips; the noise-fidelity gate and
      9/9 reference tests pass; the preview elaboration builds; and the frozen
      renders are 59/59 byte-identical. This is the first cumulative R.46+
      checkpoint that both routes and meets the hardware clock. Repeat only if
      the noise threshold or timing path changes.
- [x] R.51 REJECTED: publish the secondary-oscillator increment as derived
      sounding state instead of recomputing it in the sample-rate wave cone.
      `psg_wave.dq17` is a pure function of the published increment, wave,
      detune mode and wavetable flag; those inputs change only when the
      sequencer publishes a sounding tuple, while the current 17-bit
      add/shift/round network is live on every sample visit and also feeds the
      old-voice context. Ablating only that network establishes a hard upper
      bound against the R.50 baseline: fingerprint `164161d6ad9e`,
      6,682 LUT4, 1,681 carries, 1,441 flops, 13 EBR, 7,607 placed LCs and
      34.93 MHz routed. The ablation maps 6,511 LUT4 and 1,577 carries and
      places at **7,408 LCs (-199)** with 13 EBR unchanged, so the cone is
      large enough to continue. Merely narrowing the output 17 -> 14 bits was
      rejected at mapping (6,725 LUT4 / 1,685 carries): synthesis already sees
      the upper zeroes, while the port-width/name perturbation re-covered the
      surrounding logic worse. The value itself is nevertheless proven to fit
      14 bits: `tools/psg_dq_model.py` exhaustively checks all 524,288
      `(wavetable,wave,mode,dp)` cases and the exact serialized x63/x6 identities,
      with maximum 16,254.
      Implement through a foundational state-store split: the logical 512x16
      memory already costs two EBRs but uses almost nothing in words 32..63.
      Spell it as low/high 256x16 banks and expose the high-bank port in
      parallel with ordinary low-bank traffic. Compute the live value during
      the tick microprogram, publish it atomically in high-bank words, and
      snapshot old/last values there alongside the existing transition tuple.
      This must retain two state EBRs and establishes reusable address-selected
      storage for later array migrations. Acceptance requires fewer placed
      LCs, at most 15 EBRs, the unchanged 618/1,275 sample and 2,443/7,654
      tick deadlines, 59/59 byte-identical renders, and routed Fmax above
      28.125 MHz.
      The implementation inferred the intended two state EBRs and passed the
      524,288-case arithmetic model, Verilator 5.050 application build, audio
      analysis tests and complete structural PSG suite. The sample deadline
      stayed 618/1,275; tick preparation grew four clocks to 2,447/7,654 with
      zero late flips. But the sequencer arithmetic, auxiliary memory-port
      selection and three 14-bit walker lifetimes cost more than the retired
      combinational cone: 6,905 LUT4, 1,647 carries, 1,525 flops and 13 EBRs,
      with placement regressing **7,607 -> 7,864 (+257)** and failing to fit.
      Reverting only this implementation restores 6,682 LUT4, 1,681 carries,
      1,441 flops, 13 EBRs, 7,607 placed LCs and 34.93 MHz routed; the explicit
      Verilator phase-wrap cast and exhaustive `tools/psg_dq_model.py` proof
      remain. The ablation is a bound, not a realizable saving through this
      publication shape. Repeat only if the sounding-state publication,
      transition ownership, or shared-service operand cost changes.
- [x] R.52 REJECTED: halve the PSG clock. There are two plausible readings:
      halve the routed-Fmax round number 35 MHz to 17.5 MHz, or change the
      shipping 112.5/4 clock to 112.5/8 = 14.0625 MHz. The latter provides
      only 637 clocks per sample, 19 beyond the fixed 618-clock synthesis
      walk, and at most about 114 non-walk clocks across the six-sample tick
      pre-run window. More decisively, rebuilding the provenance-bound model
      with matching RTL and renderer clocks and byte-comparing the 59 frozen
      cases gives only **1/59 identical at 17.5 MHz** and **0/59 at 14.0625
      MHz**; `wave-0-triangle` is the first differing case at both rates.
      Fmax is an upper implementation limit, not an invitation to change the
      scheduled clock: the audio is pinned to the current 28.125 MHz timing
      fixed point. Repeat only after sequencing is made clock-invariant and a
      long pattern-chain gate proves that property.
- [x] R.53 REJECTED: rewrite `psg_wave.dq17` in the natural 13-bit input / 14-bit
      result domain while preserving its 17-bit module interface and sample
      schedule. This is not R.51's failed 17 -> 14 port perturbation and does
      not publish state. Factor the exact forms into shared narrow ceiling
      terms: `dp-ceil(63*dp/256)`, `dp-ceil(6*dp/256)`,
      `2*dp-ceil(dp/64)`, `dp-ceil(dp/128)` and
      `dp-ceil(dp/256)`. Extend `tools/psg_dq_model.py` to prove the narrow
      form over all 524,288 cases before editing RTL. Baseline is R.50:
      6,682 LUT4, 1,681 carries, 1,441 flops, 13 EBRs, 7,607 placed LCs and
      34.93 MHz routed. The exhaustive proof and warning-clean Verilator 5.050
      build pass, but synthesis maps 6,730 LUT4 (**+48**), 1,676 carries
      (-5), 1,441 flops and 13 EBRs; placement regresses **7,607 -> 7,652
      (+45)**. Routed Fmax rises slightly to 35.10 MHz, which does not repay an
      area regression. Reverted before the render battery. Together with
      R.51's failed publication shape and the earlier output-width probe, this
      closes the `dq17` mechanism under the research stop rule. The exhaustive
      model remains as evidence. Repeat only if the wave/detune formula set or
      mapper arithmetic lowering changes.
- [x] R.54 ACCEPTED: make the 618-clock sample walk clock-invariant and select
      the useful non-power-of-two PLL division. This is not R.52's blind clock
      change: a direct credit sweep found `mix-four` differs for every budget
      from 232 through 271 and becomes byte-identical at exactly 272. The full
      schedule now grants exactly 272 non-walk sequencer advances per sample;
      the common value uses an eight-bit counter seeded at 239 plus one phase
      bit, while generic budgets retain the direct counter. `psg_aram` restores
      `last_addr` because a frozen sequencer's current address names the next
      byte, not the synchronous read already issued. The lower clock also
      exposed a constants-ROM collision: a simultaneous `$22` fade lookup now
      takes priority and the walker holds one phase while its displaced control
      word is reissued. The retained `s_phase` update is explicitly cast to 16
      bits, so the Verilator 5.050 WIDTHTRUNC failure is gone.

      `/5` gives 22.5 MHz and at least 1,020 clocks/sample: 618 walk + 272
      credit leaves 130 spare. `/6` gives only 850 and is 40 short; its
      structural run aborts on the explicit insufficient-credit assertion.
      The registered modulo divider runs on the PLL falling edge, so its PSG
      rising edges cannot coincide with CPU/master rising edges and CPU/video
      clocks do not change. This is not a synchronizer: the minimum edge
      separation is half a 112.5 MHz period, about 4.44 ns, and must remain an
      explicit timing/CDC constraint. No synchronizer was added with only seven
      placed LCs spare.

      Final source fingerprint `44f732e11f49`: 6,723 LUT4, 1,690 carries,
      1,464 flops, 13 EBRs; seed-1 places 7,673/7,680 LCs and routes at
      34.94 MHz, 12.44 MHz above the actual 22.5 MHz requirement despite the
      report's generic 50 MHz failure. `make test-psg` passes at 618/1,020
      sample clocks and 4,791/6,123 tick-preparation clocks, with 1,332 spare
      and zero late flips; the frozen matrix is 59/59 byte-identical.
      `make test-clocks` passes `/4`, `/5` and `/6` period, duty and phase.
      `make shot GAME=celeste FRAMES=5` builds warning-clean and reports active
      audio. The final 400,000-sample Celeste music-0 renders at 28.125 and
      22.5 MHz are byte-identical with SHA-256
      `970b0691a90202d2be83ef158be4c750adc4ec66b4528454c9a80abb581737d5`;
      host render time falls 57.612 -> 46.830 s (18.7%, non-normative).
      Repeat only if the walk length, sequencer latency, publication boundary,
      or clock-domain contract changes; `/6` additionally needs an exact
      five-phase-per-slot walk reduction to recover its missing 40 clocks.
- [x] R.55 ACCEPTED: retire `psg_aram.last_addr` again under R.54's arbitrary
      sequencer-credit freezes by preserving the synchronous EBR output rather
      than repeatedly reading the previously issued address. This is not a
      retry of R.43: R.43 relied on a synthesis borrow freezing `seq_addr`,
      whereas R.54 proved that an ordinary credit freeze can hold a state whose
      current address already names the next byte. The new mechanism holds
      `seq_q` through ordinary `seq_hold` cycles using the inferred RAM read
      clock-enable, preserves every `syn_rd` wavetable read, and after a
      synthesis borrow reissues the held current `seq_addr` under the existing
      replay contract. Baseline fingerprint `44f732e11f49`: 6,723 LUT4,
      1,690 carries, 1,464 flops, 13 EBRs, 7,673/7,680 placed LCs and
      34.94 MHz routed at the selected 22.5 MHz PSG clock. Scope:
      `rtl/psg_aram.sv` and only the calling/test contracts required to infer
      read enable. Reject immediately if synthesis demotes or changes the nine
      audio EBRs; accept only with <=13 total EBRs, fewer real flops/LUTs and
      placed LCs, a routed fit above 22.5 MHz, `make test-psg`, 59/59 oracle
      byte identity, and a 400,000-sample cross-clock Celeste comparison if
      the sequencer schedule changes. Fingerprint `83ebc6c79f11`: all nine
      audio-RAM blocks infer `RCLKE=aram_rd`; the total remains 13 EBRs while
      Yosys falls 6,723 -> **6,705 LUT4** and 1,464 -> **1,451 flops**, with
      carries unchanged at 1,690. The census reports 905 packed and 546
      unpackable flops; the `last_addr` family is gone. Seed-1 placement falls
      7,673 -> **7,642/7,680 LCs**, leaving 38 spare. The default router
      repeated a fixed 7,398-arc impasse at both 50 and 22.5 MHz; `router2`
      completes normally on the same seed/netlist at **33.21 MHz**, passing
      the selected 22.5 MHz clock by 10.71 MHz. `make test-psg` is unchanged
      at 618/1,020 sample clocks and 4,791/6,123 tick clocks with 1,332 spare
      and zero late flips; `tools/psg_oracle_bytecheck.py` is 59/59 identical.
      The schedule and clock contract did not move, so R.54's 400,000-sample
      cross-clock proof remains the applicable schedule gate. A forced
      Verilator 5.050 application rebuild is warning-clean, including the
      earlier explicit 16-bit `s_phase` cast. Repeat only if RAM read-enable
      inference, the freeze/replay protocol, or the synchronous issue/consume
      schedule changes.
- [x] R.56 REJECTED: clock-enable the two-stage `psg_wave` pipeline and its
      reciprocal EBR only across the scheduled four-context evaluation burst.
      Each slot issues live-primary, live-secondary, old-primary and
      old-secondary contexts on W0..W3; the first pipeline boundary therefore
      needs clocks on those four phases and the second boundary/reciprocal read
      on W1..W4. Today both boundaries and the EBR read every PSG clock even
      though `z_eval` is consumed only on W2..W5. Export the two schedule
      enables from `psg_walk`, use native FF clock-enables and the reciprocal
      EBR's `RCLKE`, and leave combinational `dq17`/`q16` live. Baseline R.55
      fingerprint `83ebc6c79f11`: 6,705 LUT4, 1,690 carries, 1,451 flops,
      13 EBRs and 7,642 placed LCs; seed-1 `router2` routes at 33.21 MHz.
      Scope: `rtl/psg_walk.sv`, `rtl/psg.sv`, and `rtl/psg_wave.sv`. Accept
      only if the 618+272 schedule, `make test-psg`, 59/59 byte identity,
      warning-clean application build, 13-EBR inference and routed 22.5 MHz
      fit all survive without a placed-area regression; report host work only
      from paired identical-render timing, and report clock-enable inference
      rather than claiming unmeasured power. Fingerprint `41c2aac2ee92`: the
      reciprocal EBR inferred the intended `RCLKE`, 78 ordinary FFs became
      enabled FFs, and `make test-psg` remained exact at 618/1,020 sample and
      4,791/6,123 tick clocks. The enable routing nevertheless raised Yosys
      6,705 -> **6,729 LUT4s** while carries fell three and the 1,451 flops / 13
      EBRs stayed unchanged. Seed-1 `router2` placement regressed 7,642 ->
      **7,664 LCs (+22)**; Fmax improved 33.21 -> 36.07 MHz, which is not the
      binding resource. The structural test runtime moved only 35.427 ->
      35.320 s (~0.3%, noise), so there is no measured Verilator return to
      justify the area cost and no power claim without hardware measurement.
      Reverted before the full render battery. Repeat only if the wave-issue
      schedule, pipeline latency, iCE40 enable packing, or a real power/work
      measurement changes the trade.
- [x] R.57 ACCEPTED: rewrite `psg_wave.dq17` by quotient/remainder decomposition,
      not by R.53's direct natural-width spelling. New algebraic evidence
      changes the closed mechanism: for triangle detune-1, split
      `dp = 256*q + r` so `floor(193*dp/256) = 193*q +
      floor(193*r/256)`; the coefficient then applies to five-bit `q`, while
      the low-byte term is `r - ceil(63*r/256)` and has a two-bit residue
      correction. For phaser detune-1, split `dp = 128*q + r` so
      `ceil(6*dp/256) = 3*q + ceil(3*r/128)`, applying the product to six- and
      seven-bit values. The `/64`, `/128`, and `/256` corrections similarly
      become high quotient plus a low-nonzero bit. Extend
      `tools/psg_dq_model.py` to prove every wavetable/wave/mode/input tuple
      against the shipped expression before changing RTL. Baseline R.55:
      fingerprint `83ebc6c79f11`, 6,705 LUT4, 1,690 carries, 1,451 flops,
      13 EBRs, 7,642 placed LCs and 33.21 MHz with seed-1 `router2`. Accept
      only with fewer mapped LUT/carry resources and placed LCs, unchanged
      schedule, `make test-psg`, 59/59 byte identity, warning-clean application
      build, <=13 EBRs and routed Fmax above 22.5 MHz. Repeat only if the
      quotient/remainder proof, detune formulas, or mapper lowering changes.
      `tools/psg_dq_model.py` proves the new form over all 524,288 tuples with
      the unchanged 16,254 maximum. Fingerprint `0e5e9be9e713`: Yosys remains
      at 6,705 LUT4s and 1,451 flops but falls **1,690 -> 1,663 carries** and
      9,867 -> 9,819 total mapped submodules; 13 EBRs remain. Seed-1
      `router2` placement falls 7,642 -> **7,619/7,680 LCs (-23)**, leaving
      61 spare, and routes at **33.80 MHz**, 11.30 MHz above the selected
      clock. `make test-psg` remains 618/1,020 sample clocks and 4,791/6,123
      tick clocks with 1,332 spare and zero late flips; the frozen render set
      is 59/59 byte-identical; and the forced Verilator 5.050 console build is
      warning-clean. This new quotient/residue shape, not R.53's direct narrow
      restatement, is the evidence that justifies reopening and accepting the
      formerly closed `dq17` family.
- [x] R.58 ACCEPTED: make the accepted `/6` clock feasible by shortening the
      fixed full-schedule walk from 73 to 68 phases per slot, recovering
      exactly 5 x 8 = 40 clocks per sample. `/6` supplies 850 clocks/sample;
      the clock-invariant contract consumes 618 walk + 272 sequencer credits
      today, so the reduced walk must consume 578 + 272 = 850 with no hidden
      margin. This is a legitimate retry of R.31 because R.54 now fixes the
      sequencer credit count: moving the walk no longer changes the amount of
      sequencer progress granted per sample. Candidate reductions are to
      launch blend at `CAP_W51`, consume the short product on its first
      readable phase, combine blend output with the dampen/filter commit,
      move `PSTOR` two phases earlier, and set `PLAST` 72 -> 67. Before
      editing, prove every oscillator and late `s_lp` store sees finalized
      state; a same-edge filter commit must consume a combinational blend
      result rather than the nonblocking-assigned prior `smp_a`. Accept only
      if `/6` passes the exact 578+272 structural contract, all arithmetic and
      59/59 byte-identity gates, a warning-clean Verilator application build,
      <=13 EBRs, no placed-area regression large enough to lose the fit, and
      seed-1 routing above the selected 18.75 MHz clock. Reject and revert the
      RTL if any store dependency, render, area, or timing gate fails.

      Landed as a 68-phase visit. `PSTOR` moves 53 -> 51 and streams words
      51..64; W84 consumes the blend on its first readable phase at 65 and
      commits dampen/filter directly from the combinational blend result; the
      two late state writes land at 66/67; and phase 67 also closes the slot
      and launches the fold (`PFOLD=PLAST=67`). The earlier CAP_W51 blend-launch
      shape was functionally exact after fixing its bypass but mapped at 6,840
      LUT4 and failed placement at 7,768 LCs, so it was replaced by the retained
      CAP_W75 launch. Repeat that early-launch shape only if the operand mux or
      placement cone materially changes.

      Final fingerprint `85d2e30c4873`: forced synthesis after the authoritative
      `target_psg` clock edit maps **6,708 LUT4, 1,663 carries, 1,451 flops and
      13 EBRs**. Seed-1 places **7,625/7,680 LCs**; ordinary router2 held one
      overused wire, while router2's alternate weights complete at **31.30 MHz**
      against 18.75 MHz. `make test-psg` passes at exactly **578/850** sample
      clocks and **4,070/5,103** tick-preparation clocks with 1,033 spare, zero
      late flips and no lost state writes. The multiplier model, 524,288-case
      dq17 model, lifetime audit and `/4`/`/5`/`/6` clock bench pass. The frozen
      matrix is 59/59 byte-identical at explicit `--clock 18750000`. A forced
      Verilator 5.050 Celeste build is warning-clean, including the explicit
      16-bit `s_phase` wrap that fixes WIDTHTRUNC; the five-frame smoke reports
      3,668 samples, range -24,668..24,659 and 1,073 distinct levels. `make
      psg-viz` is warning-clean and reports 68 hardware / 24 preview phases.
      `/6` has no minimum-interval margin: any walk growth or sequencer-credit
      change must re-open this clock decision.
- [x] R.59 ACCEPTED: retire the effect program's `arp_r` and `pvol_r` holding
      registers by moving the two existing inactive-bank increment writes to
      the point where the final increment is available, and by reading the
      previous-volume operand directly from its stable voice fields. This is
      not R.3's rejected self-feedback-arm edit: R.3 retained `arp_r` and only
      perturbed one input mux, whereas the current netlist attributes 208 LUT4s
      to the complete `arp_r`-driven family and the direct-to-bank publication
      machinery accepted in task 3.3 now provides an address-selected home for
      the final value. Reuse `P_W0/P_W1` for the early writes, resume `K_FX`
      at its prior micro-step, and enter `P_W2/P_W3` at the old publication
      point; no sample-walk phase or fixed 272-credit contract may change.

      Baseline R.58 fingerprint `85d2e30c4873`: 6,708 LUT4, 1,663 carries,
      1,451 flops, 13 EBRs and 7,625/7,680 placed LCs; alternate-weight
      router2 reaches 31.30 MHz at the selected 18.75 MHz clock. Scope:
      `rtl/psg_seq.sv` plus the arithmetic/model or OpenSpec evidence needed
      by the result. Accept only if mapped resources and seed-1 placed LCs
      fall, EBR remains <=13, `make test-psg` keeps the exact 578/850 sample
      contract and zero late flips, all 59 frozen renders remain byte-identical
      at 18.75 MHz, and the forced Verilator 5.050 Celeste build remains
      warning-clean. Reject and revert if early writes alter replay/collision
      behavior, if a final increment is not stable across both writes, or if
      area does not improve. Repeat only if effect ordering, publication-bank
      ownership, or the `arp_r`/previous-volume operand cones materially
      change.

      The retained schedule writes P_W0/P_W1 after the increment becomes
      final, then resumes K_FX at xs 3 after slide or xs 8 for every other
      effect. K_FX xs 11 enters P_W2/P_W3 directly, so the same four inactive-
      bank words are written and the pass uses the same number of sequencer
      states. Slide holds its final synchronous table address across the two
      writes; effects 6/7 similarly hold the arpeggiated pitch address. The
      volume interpolation reads the previous volume directly from the stable
      voice fields, removing the second holding register without changing its
      arithmetic.

      Fingerprint `81eb0cefc834`: Yosys maps **6,665 LUT4 (-43), 1,662
      carries (-1), 1,435 flops (-16) and 13 EBRs**. Seed-1 placement falls
      **7,625 -> 7,586/7,680 LCs (-39)**; the placed delta alone is inside the
      mapper's +/-60 naming sensitivity, while the independent LUT/flop
      reductions establish a real netlist saving. Router2 with alternate
      weights completes at **34.42 MHz**, 15.67 MHz above the selected 18.75
      MHz clock. `make test-psg` remains exactly 578/850 sample clocks and
      4,070/5,103 tick-preparation clocks with 1,033 spare, zero late flips and
      no lost state writes. `tools/psg_oracle_bytecheck.py --clock 18750000`
      is 59/59 byte-identical, and a forced Verilator 5.050 console rebuild is
      warning-clean. R.59 is retained as the first direct-to-bank retirement
      of a complete effect working-register family; the remaining `vol_r`
      arithmetic family still needs a separate address-selected or serial
      accumulator hypothesis rather than another borrowed-register merge.
- [x] R.60 ACCEPTED: narrow the shared multiplier's real magnitude/accumulator
      boundary from 21 to 18 bits. This legitimately reopens R.11's width
      mechanism: R.11's 21-bit proof used the old shift-scaled pitch increment
      ceiling `0x1CE0 << 8`, while every current request supplies the unshifted
      value and restores its fixed-point position only in the consumer slice.
      The complete live-arm audit is: signed waveform and blend operands are
      at most 18 bits (including -131072), the noise J operand is 17 bits,
      slide fraction is 16, and every sequencer pitch/volume operand is <=13.
      Keep the public 34-bit `m_res` bit positions unchanged by zero-extending
      the narrower internal product; no request mode, iteration count, landing
      offset, consume slice or schedule phase may move.

      Baseline R.59 fingerprint `81eb0cefc834`: 6,665 LUT4, 1,662 carries,
      1,435 flops, 13 EBRs, 7,586/7,680 placed LCs and 34.42 MHz routed at the
      selected 18.75 MHz clock. Scope: `rtl/psg_mulsvc.sv`, the cycle-exact
      `tools/psg_mul_model.py` width/overflow proof, and result evidence.
      Accept only if the full model proves all modes, signs, corner operands
      and named consume offsets; mapped resources and placed LCs fall; the
      exact 578+272 `/6` contract, 59/59 byte identity and warning-clean
      application build survive; and seed-1 routes above 18.75 MHz at <=13
      EBRs. Reject and revert if any current arm exceeds the bound, a result
      bit moves, or area fails to improve. Repeat only if request operand
      ranges, fixed-point representation or multiplier landing changes.

      Fingerprint `95095b93cabb`: the internal magnitude narrows 21 -> 18 bits,
      its accumulator and radix-4 add path narrow with it, and the 34-bit
      public result keeps the same bit positions by zero-extension. The
      cycle-exact model proves every mode, sign, landing, overflow bound and
      named consumer slice. Yosys maps **6,648 LUT4 (-17), 1,656 carries
      (-6), 1,429 flops (-6) and 13 EBRs**. Seed-1 placement falls 7,586 ->
      **7,566/7,680 LCs (-20)**; router2 completes at **33.87 MHz**, 15.12 MHz
      above the selected 18.75 MHz clock. `make test-psg` remains exactly
      578/850 sample clocks and 4,070/5,103 tick-preparation clocks with zero
      late flips; all 59 frozen renders are byte-identical at 18.75 MHz; and
      the forced Verilator 5.050 console build is warning-clean. Repeat only
      if a request operand range, fixed-point representation or multiplier
      landing changes.
- [x] R.61 REJECTED: retire the effect program's remaining `vol_r` family by
      consuming the already-persistent service results and publishing the
      final volume directly. This is not another R.40-R.42 arbitrary walker
      register merge: `psg_ff_census.py` attributes 144 LUT4s and 13
      unpackable flops to the complete sequencer volume family, and the
      proposed storage already exists in `d_res`, `m_res` and the stable voice
      fields. The initial volume source is stable for the whole effect pass;
      the effect divider result remains valid through xs 8; the instrument
      divider result remains valid through xs 10 and P_W3; and the optional
      music-gain product remains in `m_res` through P_W3. Select those values
      at their consumers, remove all four `vol_r` writes, and let the existing
      inactive-bank P_W3 store become the only final commit. No multiplier or
      divider request, microstep, publication word, sample-walk phase or fixed
      272-credit contract may move.

      Baseline R.60 fingerprint `95095b93cabb`: 6,648 LUT4, 1,656 carries,
      1,429 flops, 13 EBRs, 7,566/7,680 placed LCs and 33.87 MHz routed at the
      selected 18.75 MHz clock. Scope: `rtl/psg_seq.sv` plus proof/evidence
      required by the result. Accept only if mapped resources and placed LCs
      fall, EBR remains <=13, `make test-psg` keeps the exact 578+272 `/6`
      contract and zero late flips, all 59 frozen renders remain byte-identical
      at 18.75 MHz, and a forced Verilator 5.050 console build remains
      warning-clean. Reject and revert if any service result is overwritten
      before its consumer, publication changes, or area fails to improve.
      Repeat only if the effect microstep order, service-result persistence or
      publication-bank contract changes.

      The candidate removed all twelve mapped `vol_r` flops and consumed the
      stable voice fields, `d_res` and `m_res` directly. It was functionally
      exact: the forced Verilator 5.050 console build was warning-clean,
      `make test-psg` stayed at 578/850 sample clocks and 4,070/5,103
      tick-preparation clocks with 1,033 spare and zero late flips, and the
      explicit 18.75 MHz byte gate was 59/59 identical. The storage removal
      nevertheless widened the consumer selection cones. Candidate fingerprint
      `f7b2e1e9705b` maps **6,674 LUT4 (+26), 1,655 carries (-1), 1,417 flops
      (-12) and 13 EBRs**; seed-1 placement regresses **7,566 -> 7,590 LCs
      (+24)** and routes at **30.79 MHz**. The area acceptance rule therefore
      fails even though timing remains above 18.75 MHz. Reverted exactly to
      R.60 fingerprint `95095b93cabb`. Do not retry direct service-result
      consumption unless the effect order, service-result persistence or
      publication cone changes enough to remove the added selection logic.
- [x] R.62 REJECTED: compact the computed-wave stage boundary by registering
      only the payload selected by the current shape. Today `z_lin_r` and
      `tri4_r` both hold triangle-derived values even though triangle-alt uses
      only `tri4_r`; `t_pre_r`, `t_h7_r`, `t_h15_r` and `org_h_r` similarly
      hold four mutually exclusive forms before a downstream shape mux selects
      one. Fold triangle-alt's pre-scaled value into `z_lin_r`, fold the four
      divide inputs into one 15-bit `div_arg_r`, and derive registered
      `tilt_hi` from the already-registered `{wsel_r2,walt_r2}`. This is not an
      arbitrary lifetime merge: all values cross the same pipeline edge for
      one context, the shape tag already selects the live interpretation, and
      the downstream selection retires with the unused fields. No waveform
      formula, reciprocal address, pipeline latency, sample phase or `/6`
      credit may move.

      Baseline R.60 fingerprint `95095b93cabb`: 6,648 LUT4, 1,656 carries,
      1,429 flops, 13 EBRs and 7,566/7,680 placed LCs; the fresh seed-1 route
      reaches 34.06 MHz at the selected 18.75 MHz clock. Scope:
      `rtl/psg_wave.sv` plus result evidence. The source transformation should
      retire 48 stage flops: 18 from `tri4_r`, 29 from the four-to-one divide
      payload, and one redundant `tilt_hi_r`. Accept only if mapped flops and
      LUTs plus placed LCs fall, EBR remains 13, `make test-psg` keeps the
      exact 578+272 schedule and zero late flips, all 59 frozen renders remain
      byte-identical at 18.75 MHz, and seed-1 routes above 18.75 MHz. Reject
      and revert if shape selection adds back the register saving in LUTs or
      changes any pipeline result. Repeat only if the wave-stage payloads,
      shape exclusivity or pipeline boundary changes.

      Candidate fingerprint `fb9c4d6512fe` is functionally exact: the
      524,288-case dq17 proof passes, `make test-psg` remains 578/850 sample
      clocks and 4,070/5,103 tick-preparation clocks with 1,033 spare and zero
      late flips, and the explicit 18.75 MHz render set is 59/59 identical.
      The source removes 48 stage fields, but mapping retires only 29 flops and
      expands the shape-selection/fanout cones: **6,702 LUT4 (+54), 1,656
      carries, 1,400 flops (-29) and 13 EBRs**. Seed-1 placement regresses
      **7,566 -> 7,591 LCs (+25)** and routes at **33.13 MHz**. Reverted exactly
      to R.60 fingerprint `95095b93cabb`. Together with R.61, this closes
      selector-fed register retirement as a current mechanism: removing state
      is not a win when a new wide input/fanout selector replaces the existing
      parallel shape islands. Repeat only if the pipeline payloads or their
      shape fanout materially change.
- [x] R.63 REJECTED: time-share the multiplier accumulator adder with request-time
      signed-to-magnitude conversion. The service currently implements an
      18-bit `0-A` chain on the `m_a` load edge and a separate 21-bit
      `m_acc+m_add` chain on busy edges; those operations are cycle-disjoint.
      Select the existing accumulator-adder operands so its idle/load use is
      `{A ^ sign}+sign`, then load `m_a` from that result. Keep the radix-4
      digit add, product register, count, result alignment and public 34-bit
      output unchanged. This is arithmetic-unit sharing, not selector-fed
      lifetime retirement: one carry chain must physically disappear and no
      new state is introduced.

      Baseline R.60 fingerprint `95095b93cabb`: 6,648 LUT4, 1,656 carries,
      1,429 flops, 13 EBRs and 7,566/7,680 placed LCs; seed-1 routes at
      34.06 MHz in the fresh reproduction. Scope: `rtl/psg_mulsvc.sv` and the
      cycle-exact multiplier model/evidence. Accept only if the model proves
      all signs, modes, landings and named slices; mapped carries/LUTs and
      placed LCs fall; the exact 578+272 schedule, 59/59 byte gate and 13 EBRs
      remain unchanged; and seed-1 routes above 18.75 MHz. Reject and revert
      if operand selection recreates the removed negate chain or worsens
      placement. Repeat only if the multiplier load/step arithmetic or mapper
      carry lowering changes.

      The cycle-exact model passes every sign, mode, landing, overflow bound
      and named result slice, but candidate fingerprint `5ee62b672b50` maps
      **6,668 LUT4 (+20), 1,639 carries (-17), 1,429 flops and 13 EBRs**.
      Selecting load-versus-step operands in front of the shared 21-bit chain
      costs more LUT fabric than the removed negate carry chain saves; seed-1
      placement regresses **7,566 -> 7,610 LCs (+44)** and routes at
      **31.10 MHz**. Reverted exactly to `95095b93cabb` before the render
      battery because the binding area gate already fails. A second placement
      of the conversion on the radix-digit adder is the only materially
      different sharing shape left; stop this mechanism if it repeats the
      selector cost.
- [x] R.64 REJECTED: time-share request-time signed-to-magnitude conversion with
      the radix-digit `3A` adder instead of R.63's accumulator adder. The load
      edge and radix steps are cycle-disjoint, and only digit 3 currently uses
      this 20-bit adder; select its operands between `{A ^ sign} + sign` on a
      real request load and `A + 2A` on a digit-3 step, then load `m_a` from
      the shared result. Keep the accumulator chain, product register, count,
      result alignment, public 34-bit output and schedule unchanged.

      Baseline R.60 fingerprint `95095b93cabb`: 6,648 LUT4, 1,656 carries,
      1,429 flops, 13 EBRs and 7,566/7,680 placed LCs; the fresh seed-1 route
      reaches 34.06 MHz at the selected 18.75 MHz clock. Scope:
      `rtl/psg_mulsvc.sv` and the cycle-exact multiplier model/evidence.
      Accept only if the model proves all signs, modes, landings and named
      slices and both mapped LUT/carry resources and placed LCs fall. Reject
      and revert before long render gates if placement does not improve. If
      this second adder-sharing variant again trades carries for LUTs or LCs,
      close the arithmetic-sharing mechanism under the two-variant stop rule.
      Repeat only if the radix-digit arithmetic or mapper carry lowering
      changes.

      The cycle-exact model passes every sign, mode, landing, overflow bound
      and named result slice. Candidate fingerprint `536732e78c3d` maps
      **6,681 LUT4 (+33), 1,640 carries (-16), 1,429 flops and 13 EBRs**.
      The selected input cones also make more multiplier flops unpackable;
      seed-1 placement regresses **7,566 -> 7,609 LCs (+43)** and routes at
      **33.87 MHz**. Reverted exactly to R.60 fingerprint `95095b93cabb`
      before the render battery because the binding area gate fails. R.63 and
      R.64 both trade one removed carry chain for more LUT/placed fabric, so
      current multiplier-adder sharing is closed under the two-variant stop
      rule. Repeat only if the multiplier digit arithmetic, request boundary
      or mapper carry lowering materially changes.
- [x] R.65 REJECTED: narrow the remaining effect-volume value path from 12 to
      11 bits. Every source is `volume * 256` for a three-bit volume, hence at
      most `7 * 256 = 1,792 < 2^11`. Effects 1/4/5 respectively interpolate
      between two such values or attenuate by `fcnt/sp` and `(sp-fcnt)/sp`;
      instrument scaling is at most `7/7`; music gain is at most `256/256`.
      Exhaustively prove all valid speed/count, instrument-volume and gain
      combinations before editing. Then narrow `vol_direct`, `pvol_now`,
      `vol_r`, `fxv_next`, `a_post` and their multiplier/result slices while
      retaining the exact signed-difference width and publishing the same
      12-bit zero-extended field.

      This is a new invisible value bound, not R.61's rejected direct-result
      consumption: the holding register, effect order, divider/multiplier
      requests, publication word and schedule all remain. Baseline R.60
      fingerprint `95095b93cabb`: 6,648 LUT4, 1,656 carries, 1,429 flops,
      13 EBRs, 7,566 placed LCs and 34.06 MHz routed. Scope:
      `rtl/psg_seq.sv` plus a durable exhaustive bound/equivalence gate if the
      candidate survives synthesis. Accept only if mapped resources and
      placed LCs fall, the exact 578+272 schedule and 59/59 byte gate survive,
      and routing remains above 18.75 MHz. Reject and revert if any high bit
      is reachable or the narrower spelling worsens area. Repeat only if the
      volume/effect/instrument arithmetic or value representation changes.

      The pre-edit exhaustive proof covers 6,315,840 valid effect cases plus
      every instrument volume and all 256 music gains. Every initial, effect,
      post-instrument and final value stays in `0..1,792` (`0x700`), bit 11 is
      always zero, and the signed endpoint delta `-1,792..1,792` fits 12 bits.
      Candidate fingerprint `a15823bc80b2` is therefore arithmetic-exact, but
      maps **6,655 LUT4 (+7), 1,651 carries (-5), 1,428 flops (-1) and 13
      EBRs**. Seed-1 placement regresses **7,566 -> 7,572 LCs (+6)**; routing
      then stalls at 7,819 unresolved arcs and is terminated because both
      mapped LUTs and binding placement already fail acceptance. Reverted
      exactly to R.60 fingerprint `95095b93cabb` before functional/render
      gates. The mapper already absorbs the provably zero high volume bit into
      the surrounding selection/arithmetic; repeat only if that cone or the
      value representation changes.

- [x] R.66 REJECTED: retire the slide affine's 16-bit `sl_rlo` register into
      dead `sl_uhi[15:0]`. `sl_rlo` is written from the synchronous constants
      word at `K_SL5` and read only by `sl_u` during `K_SL6`; `sl_uhi` has no
      value before its complete overwrite from `sl_u[29:12]` on the `K_SL6`
      edge. Load `{2'b0,crom_q}` into `sl_uhi` at `K_SL5`, read its low word in
      `sl_u`, then perform the existing full `sl_uhi` write at `K_SL6`.

      This is not one of R.40-R.42's rejected cross-family walker merges: both
      roles are adjacent stages of the same slide affine, the host already
      feeds the only consumer, and no result/fanout selector is added. Baseline
      R.60 fingerprint `95095b93cabb`: 6,648 LUT4, 1,656 carries, 1,429 flops,
      13 EBRs, 7,566 placed LCs and 34.06 MHz routed. Scope:
      `rtl/psg_seq.sv`. Accept only if mapped flops/LUTs and placed LCs fall,
      the multiplier model and exact 578+272 schedule pass, all 59 renders are
      byte-identical, and routing stays above 18.75 MHz. Reject and revert if
      the host D mux/fanout consumes the register saving. Repeat only if the
      slide microprogram or affine staging changes.

- [x] R.67 REJECTED: spend the two EBRs still available under the 15-block
      ceiling on the tilted-saw `/7` remainder, reversing only that part of
      R.27's six-block condensation. The exact one-fold identity is
      `x/7 = 73*(x>>9) + ((x>>9)+x[8:0])/7`; exhaustive evaluation over every
      16-bit phase gives `t_pre <= 172,001` and a direct table index <=844, so
      a 1,024x7 synchronous table costs exactly two EBRs. Keep `/3` and `/15`
      in the existing condensed block, select the direct `/7` quotient on the
      same pipeline edge, and remove `/7` from the second-fold address and
      remainder terms. No waveform formula, pipeline latency or walk phase
      may move.

      This is a deliberate LC-for-EBR trade, not a retry of R.62's selected
      payloads. R.27 measured the complete reverse direction at +75 LCs for
      -6 EBRs; the current 13-EBR design has room to price the largest direct
      reciprocal independently. Baseline R.60 fingerprint `95095b93cabb`:
      6,648 LUT4, 1,656 carries, 1,429 flops, 13 EBRs, 7,566 placed LCs and
      34.06 MHz routed. Scope: `rtl/psg_wave.sv` plus exact waveform gates.
      Accept only at <=15 EBRs with fewer mapped LUT/carry resources and placed
      LCs, unchanged dq17/model and 578+272 schedule, 59/59 byte identity, and
      routing above 18.75 MHz. Reject and revert if the second port or quotient
      selection costs more logic than the restored table saves. Repeat only if
      the reciprocal partition or EBR ceiling changes.

      The arithmetic proofs pass, and candidate fingerprint `b3408a401fff`
      infers the intended 1,024x7 table, but maps **6,737 LUT4 (+89), 1,655
      carries (-1), 1,429 flops and 15 EBRs**. Keeping the condensed `/3` and
      `/15` port while adding a second registered table/output selector costs
      substantially more than the `/7` second fold it removes. Seed-1
      placement regresses **7,566 -> 7,652 LCs (+86)** and routes at 32.13
      MHz. Reverted exactly to R.60 fingerprint `95095b93cabb` before the
      structural/render battery. Partial reciprocal de-condensation is closed;
      retry only as a whole partition replacement with independently measured
      port removal, or if the EBR ceiling and downstream selection change.

      Candidate fingerprint `034fb20afb4e` removes all 16 intended flops and
      maps **6,665 LUT4 (+17), 1,650 carries (-6), 1,413 flops (-16) and 13
      EBRs**. The census confirms unpackable flops fall 547 -> 531, but the
      added `K_SL5` host write arm costs the saving back in LUT selection.
      Seed-1 placement moves **7,566 -> 7,557 LCs (-9)** and routes at 34.29
      MHz; that placed delta is inside the known +/-60 mapping-sensitivity
      band and the deterministic LUT count regresses. Reverted exactly to
      R.60 fingerprint `95095b93cabb` before the render battery. Even an
      adjacent same-family register reuse must remove its surrounding logic,
      not merely move a write mux; repeat only if the slide staging changes.

- [x] R.68 REJECTED AT AREA GATE: migrate the complete
      full-schedule `pph` decode into one dedicated 128x16 auxiliary control
      EBR. This is the only retry permitted
      by R.29: move the record-read code, record-write code, record-load
      destination (four bits, with the sounding sub-index derived from the
      current read code), store-data selection, both late writes, final close,
      and the PNZ_OLD/PNZ_LIVE requests together so the shared comparator/
      subtract fabric actually retires. Keep `REALTIME_PREVIEW` on its direct
      `pph` expressions and prefetch the auxiliary word with `pph_nxt`, primed
      to word zero while idle.

      Baseline was freshly forced before editing: fingerprint
      `95095b93cabb`, **6,648 LUT4, 1,656 carries, 1,429 flops, 13 EBRs,
      7,566/7,680 placed LCs and 34.06 MHz routed** at the selected 18.75 MHz
      clock. Scope: `tools/gen_psg_ctrl.py`, one generated auxiliary hex image,
      `rtl/psg_walk.sv`, `rtl/psg.sv`, and only required evidence/docs.
      Acceptance requires the intended total-domain decode retirement, <=15
      EBRs, lower mapped LUT area and placed LCs, the exact 578+272 `/6`
      schedule with zero late flips/lost writes, 59/59 byte identity at 18.75
      MHz, a warning-clean application build, and routed Fmax above 18.75 MHz.
      Gate mapped LUT/EBR and placement before long render tests.

      R.68a fingerprint `293899b6ce84` inferred the intended single extra EBR
      but maps **6,676 LUT4 (+28), 1,636 carries (-20), 1,429 flops and 14
      EBRs**. Placement moves 7,566 -> **7,560 LCs (-6)**, inside the known
      +/-60 mapping-sensitivity band, and routing completes at 31.93 MHz. The
      deterministic LUT regression fails the first gate, so long render tests
      are skipped.

      R.68b was the one justified final encoding variant: R.29's absolute write
      address mapped 41 LUTs smaller than its offset-address form. Encode
      ordinary writes as absolute record offsets 10..23, reserve codes 1/2
      for the two late writes, and decode store payload directly from those
      absolute codes. This removes both the offset-to-address add and the full
      schedule's store-index subtract. Candidate fingerprint `820b4e170776`
      improves on R.68a but still maps **6,663 LUT4 (+15), 1,629 carries
      (-27), 1,429 flops and 14 EBRs**. Placement reaches **7,538 LCs (-28)**
      and 35.66 MHz, but the placed delta remains inside the +/-60 sensitivity
      band; routing was stopped after two million iterations because the
      deterministic LUT gate had already failed. Long render tests are again
      skipped. Both materially different write encodings regress mapped LUT
      area, so the complete auxiliary mechanism is rejected, reverted exactly
      to R.60, and closed under the two-variant stop rule. Repeat only if the
      schedule, record layout, encoding, or mapper changes materially.

- [x] R.69 REJECTED AT AREA GATE: repack the existing shared
      constants/control ROM word as a
      phase-class union, migrating the same full decode domain as R.68 without
      adding a second EBR or registered table output. The schedule classes are
      disjoint: class 1 carries a five-bit read code plus four-bit load code;
      class 2 carries the ten early one-hot actions plus PNZ_OLD/PNZ_LIVE; and
      class 3 carries an absolute five-bit write code plus the four late
      one-hot actions. The physical word remains 16 bits in the existing
      constants EBR. Phase zero retains one direct oscillator read because the
      shared port cannot prefetch word zero before `prun`; all other full-mode
      read/load/write/action/late/final decode moves together.

      This is materially different from both closed forms: R.29 peeled only
      addresses into a new EBR, and R.68 migrated the full domain but paid a
      second registered port. Baseline is the freshly restored and synthesized
      R.60 fingerprint `95095b93cabb`: **6,648 LUT4, 1,656 carries, 1,429
      flops, 13 EBRs, 7,566 placed LCs and 34.06 MHz routed**. Scope:
      `tools/gen_psg_ctrl.py`, `rtl/psg_walk.sv`, the schedule visualizer if
      required by its generated-word contract, and result evidence. Gate first
      on unchanged 13 EBRs, lower mapped LUTs and lower placed LCs; only then
      run the exact 578+272 schedule, 59-render and application gates.
      R.69a fingerprint `9bbdf431ee0b` keeps 13 EBRs and maps **6,652 LUT4
      (+4), 1,632 carries (-24) and 1,429 flops**. Placement falls 7,566 ->
      **7,534 LCs (-32)** and routing reaches 33.88 MHz, but the placed delta
      remains inside mapping sensitivity and mapped LUTs still regress, so the
      first gate fails and long tests are skipped.

      R.69b was the final encoding variant. Three one-hot class bits leave 13
      payload bits, enough for the 12-bit early-action payload and both
      nine-bit state payloads, and remove the binary-class equality
      comparators. Candidate fingerprint `cd68339eaeb4` nevertheless maps
      **6,698 LUT4 (+50), 1,636 carries (-20), 1,429 flops and 13 EBRs**.
      Seed-1 placement regresses **7,566 -> 7,576 LCs (+10)** and routing
      completes at **31.61 MHz**. Both required area gates fail, so long
      functional/render tests are skipped and the source is reverted exactly
      to R.60 fingerprint `95095b93cabb`. R.69a and R.69b close existing-word
      phase overlays under the two-variant rule. Repeat only if the class
      partition, phase-zero port ownership, schedule or mapper changes.

- [x] R.70 ACCEPTED: retire the serial fold's complete `fx_r`/`f_over`
      lifetime by replacing its corrected shift series with an exact
      base-256 quotient split. For every reachable nonnegative excess
      `x = 256*h + l`, `floor(x/5) = 51*h + floor((h+l)/5)` because
      `256 = 51*5 + 1`. Exhaustive NumPy evaluation proves the identity for
      all 40,961 reachable excesses and proves the reconstructed `soft_add`
      over all 131,071 possible pair sums; `h <= 160`, `h+l <= 414` and the
      quotient remains <=8,192.

      Infer one 512x7 EBR for `floor(index/5)`, store the detected excess in
      the selected fold-stack word, and use the existing 18-bit phase ALU to
      form `3*h`, `51*h`, add the table quotient and restore the signed
      threshold. This removes the 18-bit `fx_r`, `f_over` and the old
      correction series; only the underflow sign remains. The worst underflow
      fold shrinks from eleven microsteps to nine, so the exact 578+272 `/6`
      schedule cannot grow. This is not R.19/R.20's lifetime reuse: those kept
      the old series and therefore retained the original excess in `fx_r`;
      R.70 changes the quotient representation so that lifetime disappears.

      Baseline R.60 fingerprint `95095b93cabb`: 6,648 LUT4, 1,656 carries,
      1,429 flops, 13 EBRs, 7,566 placed LCs and 34.06 MHz routed. Accept only
      at <=15 EBRs with lower mapped LUT area and lower placed LCs, exact
      exhaustive arithmetic, the unchanged 578+272 schedule with zero late
      flips, 59/59 byte identity at 18.75 MHz, a warning-clean application
      build and routed Fmax above 18.75 MHz. Reject if the new EBR port or
      recombine selection costs back the retired fold cone. Repeat only if the
      fold arithmetic, table budget, or phase-ALU contract changes.

      Retained fingerprint `6e8aa593ff4f` infers the intended 512x7 quotient
      table and maps **6,589 LUT4 (-59), 1,664 carries (+8), 1,410 flops
      (-19) and 14 EBRs (+1)**. The flop census moves 547 -> **524
      unpackable flops**. Seed-1 placement falls **7,566 -> 7,488/7,680 LCs
      (-78)** and routing completes at **35.01 MHz**, 16.26 MHz above the
      selected 18.75 MHz clock. R.70 therefore clears both deterministic
      mapped and binding placed-area gates while remaining below the 15-EBR
      ceiling.

      The arithmetic proof is now durable as `make test-psg-fold`, integrated
      into `make test-psg`: it exhaustively proves all **40,961** reachable
      excesses, bounds `h <= 160`, `h+l <= 414`, the seven-bit table quotient
      to 82 and the final quotient to 8,192, and reproduces the shipped
      compressor for all **131,071** signed-int16 pair sums. `make test-psg`
      passes the noise gate, all 32 audio-analysis tests and every structural
      case. The observed longest synthesis path is 572/850 clocks; the fixed
      contract remains exactly **578 walk + 272 sequencer = 850 clocks** at
      `/6`. Tick preparation is 4,056/5,103 with 1,047 spare and zero late
      flips.

      `tools/psg_oracle_bytecheck.py --clock 18750000` is **59/59
      byte-identical**. `make -B GAME=celeste build/obj_dir/console` is clean
      under Verilator 5.050, including the explicit 16-bit `s_phase` wrap, and
      `make shot GAME=celeste FRAMES=5` reports active non-constant audio:
      3,668 samples, range -24,668..24,659 and 1,073 distinct levels. The
      `/6` operating point still has no minimum-interval margin; any walk or
      sequencer-credit growth must re-open the clock decision.

- [x] R.71 REJECTED: stream the preceding secondary oscillator phase from the
      existing state store instead of retaining the complete 17-bit
      `old_q0` working register. The current record splits `old_q0` across
      oscillator words 1 and 7, then loads all 17 bits at the visit start even
      though only the old-secondary issue and one later increment consume it.
      The census attributes 236 LUT4s to the family.

      Move `old_q0[15:0]` to unused per-slot word 33 in the already-inferred
      512x16 state memory, keep only `old_q0[16]` beside `bl_cnt`, and issue
      the word-33 read at phase 31 so it is present for `CAP_W3` at phase 32.
      Hold that address through the ordinary store window. A transition
      restart writes the current secondary phase into word 33 at `CAP_W0`;
      the existing old-context `dq17` add is evaluated again at the word-7
      and word-33 store phases so the updated high and low pieces commit
      without another holding register. The read port is otherwise idle in
      this window and the write phases do not collide with the oscillator or
      two late filter writes.

      This is not R.51's rejected derived-increment publication: it preserves
      the same old phase and update arithmetic, uses existing address-selected
      storage with no new EBR or auxiliary port, and removes a working
      lifetime rather than adding a published value. Baseline R.70 fingerprint
      `6e8aa593ff4f`: 6,589 LUT4, 1,664 carries, 1,410 flops, 14 EBRs,
      7,488 placed LCs and 35.01 MHz routed. Accept only if mapped LUT/flop
      resources and placed LCs fall with 14 EBRs unchanged, the exact
      578+272 `/6` schedule reports no lost state write or late flip, all 59
      renders remain byte-identical at 18.75 MHz, the forced application build
      is warning-clean and seed-1 routes above 18.75 MHz. Reject if the extra
      address/write selection costs back the register family or any restart
      observes the wrong pre-increment phase. Repeat only if the old-secondary
      issue, state-port schedule or oscillator-record layout changes.

      R.71a fingerprint `0dc564680a73` passes the exact gates: `make test-psg`
      retains the 572/850-clock observed path and 4,056/5,103 tick preparation
      with zero late flips, and the explicit 18.75 MHz render check is 59/59
      byte-identical. It maps **6,577 LUT4 (-12), 1,676 carries (+12), 1,394
      flops (-16) and 14 EBRs**, but the unpackable-flop count rises 524 -> 525
      and seed-1 placement regresses **7,488 -> 7,493 LCs (+5)**. Routing
      remains safe at 30.55 MHz. R.71a therefore fails the required placed-area
      gate and is not retained in that form.

      R.71b is the permitted second shape. The failed form selected word 33
      with a new bounded `pph >= 31 && pph <= 65` read window. The sample walk
      already owns the state port and freezes the sequencer for its complete
      visit; after the oscillator and sounding words load, every remaining
      full-schedule read cycle is idle. Hold word 33 from the end of those
      loads through `PLAST` instead, making full-mode `state_sample_read`
      simply `prun && !ctrl_stall` and removing both bounds of the new range
      decoder. This is not a mapper-only retry: it directly removes the mux
      mechanism that cost back R.71a's retired state. Accept under the same
      R.70 gates; if placement still does not fall, close the state-store
      streaming family until port ownership, schedule or mapper changes.

      R.71b fingerprint `8b4650beca18` maps **6,558 LUT4 (-31), 1,665
      carries (+1), 1,394 flops (-16) and 14 EBRs**; unpackable flops fall
      524 -> 522 and packing falls **7,488 -> 7,452 LCs (-36)**. Both lint
      flavours pass, `make test-psg` retains 572/850 clocks and zero late
      flips, and the 18.75 MHz render gate remains 59/59 byte-identical.
      The fixed-seed 50 MHz nextpnr run does not route, however: after ten
      minutes the router remains stationary at 1,000 unresolved arcs and cost
      6,661. An otherwise identical 18.75 MHz request reaches the same
      placement checksum and routing deadlock, so this is congestion rather
      than a timing-constraint failure. R.71b fails the mandatory routing gate.

      R.71c is justified beyond the ordinary two-variant stop by that new
      physical evidence. Keep R.71a's routed lower-bound ownership transition
      at phase 31, but remove only its unnecessary phase-65 upper bound: once
      word 33 takes the read port it remains selected through `PLAST`. This
      tests the smallest decoder reduction between the routed-but-area-neutral
      R.71a and area-clean-but-unroutable R.71b. It must pass every original
      R.70 acceptance gate; no fourth address-window spelling is permitted
      without a changed schedule, port contract or mapper.

      R.71c fingerprint `603f5827f568` maps **6,596 LUT4 (+7), 1,671
      carries (+7), 1,394 flops (-16) and 14 EBRs**. It fails the first mapped
      LUT gate, so placement and long functional tests are skipped. The family
      is closed after three mechanically distinct results: R.71a routes but
      costs back placement; R.71b wins mapped and placed area but cannot route;
      R.71c's single lower bound restores the mapped cost. The RTL is restored
      to R.70 plus preview-only P.1 fingerprint `d6b3811ce178`, reproducing
      **6,589 LUT4, 1,664 carries, 1,410 flops, 524 unpackable flops, 14 EBRs,
      7,488 placed LCs and 35.01 MHz** exactly. Repeat only if the old-secondary
      issue, state-port schedule, oscillator-record layout or mapper changes.

- [x] P.1 ACCEPTED: restore the secondary/detune oscillator to the
      `REALTIME_PREVIEW` mixer before resuming R.71. A fresh preview model at
      28.125 MHz reproduces the user-visible Celeste soundtrack defect even
      with 1,275 clocks/sample: music 0 reports **0% voiced pitch agreement**
      against the hardware schedule for every individual channel mask 1, 2,
      4 and 8 as well as masks 7 and 15. The visible failure is an octave
      substitution (for example A#2 -> A#3 and F3 -> F4); over the combined
      mask the preview is also roughly 2--3 dB too loud through the principal
      music bands.

      The live preview schedule issues `iss_sec` at `PWORK+1`, while the
      two-stage computed-wave cone makes that secondary result available only
      after `smp_b` has captured `z_eval` at `PWORK+2`. Thus `smp_a` and
      `smp_b` both capture the main context. Move the preview secondary issue
      and its phase advance to `PWORK`, leave the primary/secondary captures
      at `PWORK+1`/`PWORK+2`, and disable the unused old-main/old-secondary
      preview issues.

      That correction alone is necessary but not sufficient: a fresh
      two-second rerun improves each mask only from 0/12 to 1/12 agreeing
      windows and the octave substitution remains. The resume audit localizes
      a second preview drift to `6b28873`, which collapsed the stored primary
      phase from 24 to 16 bits and the increment from 21 to 14 bits. The
      hardware add was correspondingly changed to `einc[13:1]`, but the
      preview arm retained its pre-collapse full-`einc` add. It therefore
      advances the primary phase at twice the accepted hardware rate. Apply
      the same high-phase increment in preview; this is a representation
      repair, not an approximation change.

      Retain only if fresh per-channel and combined Celeste
      renders recover pitch/activity, the generous-clock and console-clock
      preview gates pass, both lint flavours are warning-clean, `make test-psg`
      passes, and the hardware schedule remains 59/59 byte-identical at
      18.75 MHz. This item is preview correctness, not an area result; do not
      synthesize or resume R.71 until it closes.

      Retained as two preview-only representation/schedule repairs. The
      primary phase now advances by `einc[13:1]`, matching the 16-bit phase
      representation introduced by `6b28873`; the secondary context and its
      phase advance issue at `PWORK`, before the unchanged `PWORK+1/+2`
      captures, and unused old-context preview issues are disabled.

      The durable gate no longer mistakes `$21` reservation masks for channel
      selectors. It disables the other three bytes in private copies of every
      music pattern, then checks pitch, RMS and active-sample occupancy for the
      combined mix and each isolated channel. At both 28.125 MHz (1,275
      clocks/sample) and the console's 3,506,580 Hz (159 clocks/sample), music
      0 passes: combined 11/12 = 92%; channel 0 20/20 = 100%; channel 1 1/1 =
      100%; channel 2 13/14 = 93%; channel 3 is inactive in both models.
      Preview RMS is 88.3--92.8% of hardware on active channels and activity
      occupancy is within one percentage point.

      Both lint flavours are warning-clean, `make test-psg` passes at the
      unchanged 572/850 worst synthesis path and 4,056/5,103 tick preparation,
      and the 18.75 MHz hardware regression is 59/59 byte-identical. A forced
      Celeste console build is warning-clean; the lowercase 300-frame run
      reaches 90.39 fps and writes five seconds of active preview audio with
      18,830 distinct levels and 14.2 effective bits. Strict OpenSpec
      validation and `git diff --check` pass. R.71 may resume from R.70.

- [x] R.72 REJECTED AT ISOLATED GATE: replace the radix-4 multiplier's explicit digit-3 `3A`
      formation with an exact carried signed-digit recurrence. For each
      two-bit unsigned digit plus one carry, values 0, 1 and 2 remain
      `0`, `+A` and `+2A`; value 3 becomes `-A` with carry one into the next
      radix-4 digit, and value 4 becomes zero with carry one. A final carry is
      consumed as the extra high digit. This changes the mathematical
      representation rather than retrying R.63/R.64's rejected attempt to
      share request-time magnitude conversion with the accumulator adder.

      First extend `tools/psg_mul_model.py` to prove the complete recoded
      transaction against the shipped service for every live mode, short
      request, sign and operand bound, including the final-carry and fixed
      `m_res` alignment. Then synthesize the service in isolation against the
      same registered harness used by R.33. Only implement integrated RTL if
      the isolated form removes LUT/LC area without lowering Fmax below the
      service baseline. Integrated baseline is restored R.70 plus P.1
      fingerprint `d6b3811ce178`: 6,589 LUT4, 1,664 carries, 1,410 flops,
      14 EBRs, 7,488 placed LCs and 35.01 MHz. Retain only with lower mapped
      LUTs and placed LCs, unchanged 14 EBRs, the exact 578+272 `/6` schedule,
      59/59 byte identity, warning-clean Celeste and routed Fmax above 18.75
      MHz. Reject after two neutral/worse recurrence spellings unless a bound
      or synthesis result identifies a materially different representation.

      The exhaustive model proves the representation itself: complete
      `m_res` equivalence for every legal B at nine A-domain boundaries and
      both signs plus the broad A sweep at digit-pattern corners; the signed
      accumulator spans -43,648..87,296 and the add/sub result
      -174,720..349,440, fitting 18 and 20 bits respectively. Both full and
      preview Verilator elaborations are warning-clean.

      The same registered harness then rejects the physical form decisively.
      Baseline is **157 LUT4, 55 carries, 119 flops, 232 LC and 119.15 MHz**.
      The carried candidate is **215 LUT4 (+58), 73 carries (+18), 122 flops
      (+3), 273 LC (+41) and 107.17 MHz (-11.98)**. The carry state, signed
      digit decode/add-sub path and conditional 34-bit final correction cost
      more than the retired `3A` producer. Evidence is retained under
      `build/psg_mul_r72/{base,candidate,restored}.*`; the restored service
      reproduces the baseline exactly. No integrated synthesis or render
      battery is run because the explicit isolated prerequisite failed. The
      RTL is restored to R.70 plus P.1. Repeat only if the final carry can be
      absorbed without a public-result correction/state bit, or if the radix
      service boundary or mapper lowering changes materially.

- [x] R.73 REJECTED AT ISOLATED GATE: express each unsigned radix-4 digit as two gated partial
      products instead of constructing a selected `m_add`. Digit bit zero
      contributes `A`; digit bit one contributes `2A`; the step is therefore
      `acc + (d[0] ? A : 0) + (d[1] ? 2A : 0)`. This keeps the shipped
      unsigned recurrence, state, iteration count, fixed landing and public
      result unchanged, while allowing the iCE40 mapper to absorb digit
      selection into a three-operand/carry-save shape rather than placing the
      dedicated `A+2A` producer ahead of the accumulator add.

      This is not R.63/R.64 adder sharing: request-time magnitude conversion
      does not enter the step datapath. It is not R.72 signed-digit recoding:
      there is no carry state, negative digit or final correction. Baseline in
      the registered harness is the exactly restored **157 LUT4, 55 carries,
      119 flops, 232 LC and 119.15 MHz**. Prove the digit identity and run the
      complete multiplier model, then synthesize/place/route the isolated
      service. Reject before integration unless both LUT/LC area improve and
      Fmax remains above the baseline requirement. If it survives, apply the
      full R.70+P.1 integrated area, exact `/6`, 59-render, application and
      routed-timing gates. Repeat only if mapper evidence identifies a
      materially different compressor spelling.

      The complete multiplier model and the explicit four-digit identity pass,
      and both lint flavours are warning-clean. The candidate maps **158 LUT4
      (+1), 36 carries (-19) and the same 119 flops**. It places in exactly
      **232 LCs (no change)** and routes at **121.48 MHz (+2.33)**. Yosys did
      infer the intended compressor resource mix, but the extra LUT cover
      consumes every cell freed by the retired carries. Since neither LUT nor
      LC area improves, the isolated prerequisite fails and no integrated
      synthesis/render battery is run. Evidence is in `build/psg_mul_r73/`;
      the RTL is restored to the 157-LUT/232-LC baseline. Repeat only if a
      genuinely different compressor primitive or mapper lowering can reduce
      the LUT cover rather than merely exchanging carries for LUTs.

- [x] P.2 ACCEPTED: reproduce and repair foreground-SFX recovery in
      `REALTIME_PREVIEW`. The accepted P.1 gate starts one music pattern and
      never writes a foreground channel, so it cannot detect the reported
      failure where repeated Celeste jump SFX progressively silence the
      soundtrack. Reproduce through the actual console at 3,506,580 Hz with
      repeated jump edges, `--psg-trace` and a console WAV; distinguish a
      stuck foreground `playing`/trigger owner from oscillator or fold-state
      corruption after the owner clears. Add a deterministic compact-schedule
      takeover/retrigger/release regression before changing RTL. Retain only
      if every music slot becomes audible again after the foreground SFX ends,
      the repeated-jump console trace and audio recover, both P.1 clock gates
      still pass, full/preview structural tests and lint pass, and the
      18.75 MHz hardware schedule remains 59/59 byte-identical. This is
      preview correctness and carries no area claim; area work stays paused
      until P.2 closes.

      Root cause: after a sample walk displaced a synchronous state-store
      read, `state_replay` reissued the current word for one cycle but
      PREVIEW's fold held `seq_hold` for two cycles longer. EA2 changed its
      issue address while still held, replacing the stored `0x0020` speed
      with word 1's `0x0000`; music SFX 11 advanced every tick and stopped at
      row 31. The repair retains EA1--EA3, ES1--ES2, PC0--PC3 and V_LD consume
      addresses for the complete `seq_hold`, not only `state_replay`.

      `make test-psg-preview-recovery` now builds the 3,506,580 Hz PREVIEW
      budget model and runs both a self-contained 16/32/16-speed mix and the
      frozen real Celeste image. Both pass 64 SFX-1 retriggers with all three
      music leaves audible/nonzero for 512 visits after release, advancing
      phases, natural foreground stop, final clear acknowledgement, and zero
      coalesced ticks, delayed publications or dropped samples. P.1 passes at
      28.125 MHz and 3,506,580 Hz for the combined mix and every active
      channel. Full/PREVIEW lint, `make test-psg`, `make test-clocks` and the
      59/59 18.75 MHz bytecheck pass.

      The rebuilt lowercase `game=celeste` console ran 1,800 scripted frames
      with 25 real jump-SFX episodes. The last foreground episode ended at
      frame 1,430; frames 1,500--1,800 retain music ownership with no
      foreground activity. Its final six seconds measure -14.63 dBFS RMS and
      -24,931..22,304, while the complete capture has 37,810 distinct levels
      (15.2 effective bits). Evidence: `build/psg_p2/`. P.2 carries no area
      claim; the next area hypothesis remains a separate experiment.

- [x] R.74 ACCEPTED: multi-pump the shared multiplier from the 112.5 MHz PLL
      while the rest of the hardware PSG remains on its accepted `/6`
      18.75 MHz clock. This is a new service-boundary mechanism, not another
      radix-4 compressor spelling: R.72/R.73 kept one clock and changed the
      digit arithmetic, whereas R.74 spends the measured isolated timing
      headroom on more service iterations per PSG period and may therefore
      return to the smaller radix-2 recurrence.

      Use the standard closed-loop multi-cycle-path CDC contract. The PSG
      domain captures the complete request payload and toggles one request
      bit; two `async_reg` stages deliver that toggle to the PLL domain. The
      payload remains stable until the PLL domain finishes, holds the complete
      result, and returns an acknowledge toggle through two synchronizer
      stages. Consumers may observe the result only after the synchronized
      acknowledge. No pulse crosses a domain, no combinational result is
      sampled while changing, and no fabric-generated fast clock is added.
      The clocks are physically related, but the handshake must remain correct
      without relying on their phase relationship; timing constraints name
      the 112.5 MHz and 18.75 MHz domains separately and cut only the protected
      CDC paths.

      Baseline after P.2 is freshly forced at RTL fingerprint
      `568c1b5a5f4c`: **6,614 LUT4, 1,663 carries, 1,410 flops, 14 EBRs and
      7,511/7,680 placed LCs**, with post-place Fmax 33.72 MHz for the PSG
      domain. This is +25 LUT4, -1 carry and +23 placed LCs versus the restored
      R.70 full-schedule checkpoint; the P.2 state-read hold repair is the
      only intervening RTL mechanism. The dense seed-1 baseline route is still
      unresolved when the experiment opens, so 7,511 placed LCs is the binding
      initial comparison and routing status must be reported rather than
      inferred from R.70's older 35.01 MHz route.

      First build an isolated two-clock harness and prove every transaction
      against the shipped radix-4 result for all live modes, signs and operand
      bounds. Measure the complete CDC wrapper plus radix-4 core, then the same
      wrapper plus an exact radix-2 core, at explicit 112.5/18.75 MHz
      constraints. Integrated RTL is permitted only if one complete service
      closes the fast clock and improves isolated LC area. Preserve exact
      sequencer timing with a separate padded sequencer-busy contract while
      exposing true result readiness to the walker; prove the true result is
      always ready before the padded contract expires. Retain only if the
      combined service and crossing logic reduce full-PSG mapped LUT/flop and
      placed LC area, the fast domain routes above 112.5 MHz, the slow domain
      routes above 18.75 MHz, the fixed 578+272 schedule and all request/consume
      assertions pass, all 59 hardware renders remain byte-identical, P.1/P.2
      PREVIEW gates remain clean, and Celeste builds warning-free. Repeat only
      if the PLL frequency, clock ratio, handshake storage, multiplier
      recurrence, or request/result lifetime changes materially.

      The retained radix-2 service uses an explicit `MULTIPUMP` elaboration
      contract: only the iCE40 `/6` top, standalone target and matching
      benches enable it. Tang Nano, PREVIEW and historical 28.125 MHz oracle
      models retain the original single-clock radix-4 service. Icarus proves
      6,020 boundary/random transactions against the shipped service, with
      true completion in at most four PSG clocks and padded sequencer busy
      exact on every PSG edge. The complete isolated wrapper+radix-2 result is
      124 LUT4, 38 carries, 146 flops and 219 LCs at 151.17 MHz, versus the
      original service's 157/55/119/232 at 119.15 MHz. Evidence is under
      `build/psg_mul_r74/`.

      Integrated fingerprint `23897c2534cd` maps **6,571 LUT4, 1,646 carries,
      1,436 flops and 14 EBRs**: -43 LUT4, -17 carries, +26 handshake flops,
      and -17 combined LUT+flop cells versus the P.2 baseline. Seed-1 places
      at **7,481/7,680 LCs (-30)**. router1 reproduces the dense baseline's
      1,000-unresolved-arc plateau; router2 completes normally and routes at
      **116.95 MHz fast / 31.62 MHz slow**, clearing 112.5/18.75 MHz. The
      Makefile selects router2 for this target so `make synth-psg` reproduces
      the completed route. `make test-psg` passes at 572/850 observed clocks
      with the fixed 578+272 contract, the 18.75 MHz regression is 59/59
      byte-identical, full/PREVIEW lint are clean, P.1 passes combined and all
      active channels at both 1,275 and 159 clocks/sample, P.2 survives both
      synthetic and frozen-Celeste retriggers, and lowercase
      `make shot game=celeste FRAMES=5` builds/runs Celeste warning-free.

- [x] R.75 ACCEPTED: recompact the full walker around R.74's acknowledged
      result, without changing the sequencer's padded multiplier contract.
      The 68-phase visit is still spaced for the single-clock radix-4 service:
      W4/W15/W27/W40/W75 launch at pph 33/40/47/54/61 and their products are
      consumed at 40/46/54/60/65. R.74 proves every normal request has crossed
      back by the fourth PSG busy observation and the short request never
      exceeds its shipped three-cycle padding; consumers therefore remain
      handshake-safe at normal launch+5 and short launch+4.

      Move W15/W26/W27/W40/W51/W75/W84 to pph
      38/43/44/49/54/55/59, move the 14-word store window to 46..59 and close
      the visit with late dampen writes at 60/61. This removes six phases per
      slot, so the fixed walk must fall **578 -> 530 clocks** and the `/6`
      interval gains 48 clocks after its unchanged 272 sequencer credits.
      Baseline is accepted R.74 fingerprint `23897c2534cd`: 6,571 LUT4,
      1,646 carries, 1,436 flops, 14 EBRs, 7,481 placed LCs and router2 Fmax
      116.95/31.62 MHz fast/slow. Retain only if request/consume assertions and
      `make test-psg` prove the 530+272 contract, all 59 renders remain
      byte-identical, P.1/P.2 and lint remain clean, mapped/placed area does not
      regress, and both routed clocks still close. Repeat only if the CDC
      latency bound, PLL/PSG ratio, store window or result lifetime changes.

      Retained result: the walk is **530 clocks**, so 530+272 leaves 48 clocks
      at `/6`. All request/consume assertions, `make test-psg`, P.1/P.2,
      full/PREVIEW lint and 59 byte-identical renders pass. Yosys maps 6,565
      LUT4, 1,647 carries, 1,436 flops and 14 EBRs; seed-1 router2 places
      7,479 LCs and routes at 150.53/33.61 MHz fast/PSG. This is -6 LUT4,
      +1 carry, unchanged flops/EBRs and -2 LCs versus R.74.

- [x] P.3 ACCEPTED: repair the detected SFX-transition clicks without weakening
      `click-v1`. Baseline: four-second Celeste SFX-10 renders contain 15 full
      and 12 PREVIEW events; the committed PICO-8 music-0 reference contains
      zero. PREVIEW jumps directly at loud phaser row boundaries, while full
      mode's corresponding jump is delayed by exactly one 183-sample effect
      tick. Instrument `blend_restart`, `bl_cnt`, the old/live tuples and
      `blend_y` before changing RTL; then add a deterministic SFX-10 click gate
      and rerun P.1/P.2, 59 hardware renders, lint, structural timing and R.75
      synthesis. Keep the click repair's correctness evidence and any area
      delta separate from R.75. Repeat only if the transition trace or a
      reference capture changes the restart hypothesis.

      Full mode is repaired and its four-second SFX-10 render has zero
      `click-v1` events. PREVIEW's five-bit signature plus 32-sample blend
      reduces 12 events to two; a coarser signature regresses to 22 and is
      rejected. Trace `build/psg_clicks/pv-fix1b-walk.csv` proves the two
      survivors are gain-to-zero aliases: `s_eff_a` 112 -> 0 leaves the
      five-bit signature unchanged while the emitted leaf snaps -490 -> 0.
      The active experiment keeps the five-bit signature and adds only the
      explicit zero edge when no transition is active and `s_lp != 0`.

      The zero-edge experiment removes both survivors; the durable dual-mode
      `make test-psg-clicks` target reports zero events for full and PREVIEW.
      An exact-rate seven-second console capture with four accepted SFX-1 jump
      retriggers has no jump event and keeps music active, but reports one new
      event at frame 192's title/spawn transition. The active experiment keeps
      the existing `clr_tog` token pending until PSTOR, includes its mismatch
      in `preview_restart`, and acknowledges it only after starting the fade;
      this covers a same-signature retrigger without widening stored state.

      That removes the console event. P.1 then caught inactive fast-path slots
      folding the preceding slot's new transition leaf: they skip directly
      from phase 0 to PFOLD and never load their own `mx_filt`. The all-slot
      trace proves every interpolated value stays within its endpoints, while
      inactive slots emit a nonzero stale leaf. The active repair gates the
      PREVIEW fold leaf with existing `mx_aud`, restoring required zero leaves
      with no new state.

      The corrected level then exposes seven smaller periodic events that the
      duplicated RMS had masked. At the first, `s_eff_a` changes 1008 -> 896
      and the leaf changes 6913 -> 6044, but the stored five-bit high signature
      aliases both gains to seven. PREVIEW consumes `s_eff_a[10:4]`; storing
      those exact seven audible bits removes the alias without more state.
      The dual-mode SFX-10 gate returns to zero events at corrected PREVIEW RMS
      2985.

      P.1 passes combined and every active channel at both 1,275 and 159
      clocks/sample. P.2 passes both 64-retrigger cases with no coalesced ticks,
      delayed publications or dropped samples. Full/PREVIEW lint,
      `make test-psg`, `make test-clocks`, and the 59/59 byte-identical hardware
      matrix pass; the 530+272 schedule retains 48 `/6` clocks of margin. The
      final exact-decimated seven-second Celeste console capture has zero
      `click-v1` events across title/spawn and repeated jump SFX.

      P.3 fingerprint `f819fe4cf85c` maps 6,571 LUT4s, 1,644 carries, 1,436
      flops and 14 EBRs, places 7,483 LCs and routes at 137.76/30.22 MHz
      fast/PSG. Its independent delta from R.75 is +6 LUT4, -3 carries,
      unchanged flops/EBRs and +4 LCs.

- [x] R.76 ACCEPTED: serialize the two per-visit secondary-increment (`dq17`)
      evaluations in the phase-19..28 load-to-W0 window. The current
      `psg_wave` spelling computes every wave/mode correction in parallel on
      every clock even though a slot consumes only the live result at W6 and
      the preceding-voice result at W5. Both 13-bit increments, wave ids and
      detune modes are final by phase 18; the ten following PSG phases are
      available while the multi-pumped multiplier independently performs its
      two noise transactions. First replace only the correction network with
      a same-input, non-constant wire in a disposable synthesis candidate to
      price the realizable mapped/placed ceiling without collapsing its
      consumers. Proceed only if that ceiling comfortably repays two 14-bit
      result lifetimes plus one narrow add/sub accumulator and its control.
      If it does, add an exhaustive cycle model, compute live and old results
      through one physical 14-bit write site, and preserve W0..W84, the
      530+272 `/6` schedule, P.1/P.2/P.3, 59/59 byte identity, warning-clean
      builds, 14 EBRs and both routed clock constraints. This is not R.51's
      rejected state-store publication or R.53's parallel natural-width
      restatement: no value is published across ticks, and the parallel
      mode arms must physically retire. Repeat only if the load window,
      increment representation, detune formula set or wave/service boundary
      changes.

      A same-input non-constant ablation prices the complete parallel cone at
      an optimistic -196 LUT4, -77 carries and -202 placed LCs against P.3;
      evidence is `build/psg_r76/ablate.*`, and the source was restored before
      candidate synthesis. The retained five-step radix-4 service starts the
      live transaction at phase 19 and chains the preceding-voice transaction
      on its phase-24 terminal edge. Transition restarts select the tuple W0
      will snapshot, and PREVIEW keeps its existing combinational `dq17`.

      `make test-psg-dq` proves all 524,288 formula tuples and 57,344 Icarus
      transactions including chained requests. Candidate fingerprint
      `de8a30582959` maps **6,513 LUT4, 1,592 carries, 1,521 flops and 14
      EBRs**; versus P.3 that is -58 LUT4, -52 carries, +85 flops and unchanged
      EBRs. Seed-1 router2 places **7,454 LCs (-29)** and routes at **141.30
      MHz fast / 31.01 MHz PSG**, above both clock requirements.

      The direct structural bench passes at 524/850 observed clocks while the
      fixed schedule stays **530+272**, retaining 48 `/6` clocks of margin;
      tick preparation is 4,008/5,103 with 1,095 spare and zero late flips.
      The 18.75 MHz regression is 59/59 byte-identical. P.1 passes combined
      and all active channels at both 1,275 and 159 clocks/sample; P.2 passes
      both 64-retrigger cases; and `make test-psg-clicks` reports zero
      `click-v1` events in full and PREVIEW SFX-10 renders. Full/PREVIEW lint,
      `make test-clocks`, and a lowercase five-frame Celeste build/run pass.
      The implementation is retained despite the ablation ceiling's larger
      promise because it reduces mapped combinational resources and the
      binding placed result while preserving every schedule and correctness
      gate. Repeat only if the load window, increment representation, detune
      formula set or wave/service boundary changes.

- [x] R.77 ACCEPTED: remove the visit-local detune service's registered
      `result`/`result_tag`/`done` handoff. On the terminal `count == 1` cycle,
      `step_next[21:8]` and `active_tag` are already stable combinational
      functions of registered service state; expose them with a combinational
      terminal-valid condition and let the existing `dq_live_r`/`dq_old_r`
      destination registers capture directly on that edge. Preserve the
      five-step recurrence, terminal-cycle chained request, phases 19/24,
      W0..W84 and the fixed 530+272 `/6` contract. Baseline is R.76 fingerprint
      `de8a30582959`: 6,513 LUT4, 1,592 carries, 1,521 flops, 14 EBRs, 7,454
      placed LCs and 141.30/31.01 MHz fast/PSG. Accept only if the exhaustive
      formula/service models, structural schedule, 59 renders, P.1/P.2/P.3,
      unchanged `click-v1`, both lint flavours, application build and routed
      clocks pass with lower mapped flops/LUTs or placed LCs. This is not a
      cross-family register merge: the destination roles do not change and a
      complete redundant write boundary disappears. Repeat only if service
      latency, destination lifetime, terminal recurrence or chaining changes.

      Retained RTL fingerprint `e1097eb59c9b` maps **6,518 LUT4s, 1,592
      carries, 1,505 flops and 14 EBRs**: +5 LUT4, unchanged carries, -16
      flops and unchanged EBRs versus R.76. Seed-1 router2 places **7,449 LCs
      (-5)** and routes at **125.87 MHz fast / 31.05 MHz PSG**, clearing both
      clock requirements. The 524,288-formula and 57,344-transaction dq gate
      passes, including terminal-cycle chaining and direct terminal capture.

      A fresh structural bench reports 524/850 observed clocks while the
      fixed contract stays **530+272**, leaving 48 `/6` clocks; tick
      preparation is 4,008/5,103 with 1,095 spare and zero late flips. The
      explicit 18.75 MHz byte gate is unchanged 59/59. P.1 passes combined
      and every active channel at both 1,275 and 159 clocks/sample; P.2,
      full/PREVIEW lint and the lowercase five-frame Celeste smoke pass.
      `make test-psg-clicks` retains zero `click-v1` events in full and
      PREVIEW. Repeat only if the service latency, destination lifetime,
      terminal recurrence or request-chaining contract changes.

- [x] R.78 ACCEPTED: remove the old detune result's duplicate walker lifetime.
      The second five-step transaction terminates at phase 29 and no later
      request changes the service recurrence before W5 at phase 34, so consume
      its stable terminal result directly there. Keep only `dq_live_r`, which
      is required because the chained old request overwrites the first result.
      Remove the now-unnecessary service tag state and identify the live
      capture from the fixed phase-24 chained-request edge. Preserve phases
      19/24, every W action and the fixed 530+272 `/6` contract.

      Baseline R.77 fingerprint `e1097eb59c9b`: 6,518 LUT4s, 1,592 carries,
      1,505 flops, 14 EBRs, 7,449 placed LCs and 125.87/31.05 MHz fast/PSG.
      Accept only with fewer mapped flops and placed LCs, exact dq models and
      schedule, 59/59 byte identity, P.1/P.2, zero full/PREVIEW `click-v1`
      events, clean lint, a lowercase Celeste smoke, and both routed clocks
      above their constraints. Repeat only if a request enters phase 29..W5,
      W5 moves, or the recurrence stops holding its terminal state.

      Variant A read `step_next` directly at W5 and is rejected: 6,546 LUT4s,
      1,490 flops and 7,459 placed LCs. The retained variant commits the final
      unchained recurrence into existing register `p`, reads `p[21:8]` at W5,
      and copies only the chained live result into `dq_live_r`. The service and
      walker retire `active_tag`, `start_tag`, `result_tag` and `dq_old_r`.

      Fingerprint `e12aae41e2ce` maps **6,536 LUT4s, 1,596 carries, 1,490
      flops and 14 EBRs**: +18 LUT4s, +4 carries, -15 flops and unchanged EBRs
      versus R.77. Seed-1 router2 places **7,437 LCs (-12)** and routes at
      **144.80 MHz fast / 29.94 MHz PSG**, clearing both constraints.

      `make test-psg-dq` passes 524,288 formula cases and 57,344 transactions,
      including chaining and five idle retention phases. The structural bench
      remains 524/850 observed clocks and the fixed **530+272** schedule keeps
      48 `/6` clocks spare; tick preparation remains 4,008/5,103 with 1,095
      spare and zero late flips. The 59-render byte gate is unchanged 59/59.
      P.1 passes combined and every active channel at both 1,275 and 159
      clocks/sample; P.2 passes both 64-retrigger cases. Full/PREVIEW lint,
      `make test-psg-clicks` with zero events in both modes, `make test-clocks`,
      and the lowercase five-frame Celeste smoke pass. Repeat only if a request
      enters phase 29..W5, W5 moves, or the recurrence stops holding its
      terminal state.
