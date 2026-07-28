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
      words 64..255 reserved as the microcode home; filter-decode and
      fade-step remain)

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
