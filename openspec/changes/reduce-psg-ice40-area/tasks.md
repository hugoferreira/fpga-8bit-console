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
- [ ] R.5 The remaining gap is 321 LC and needs a bulk restructure. The
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
      ML_L0-L3 write sites need the port. Estimate -150..250; the wave
      cone (smp_b, 887 cells) is the only larger target and is task 4.1's
      sample-side engine.
