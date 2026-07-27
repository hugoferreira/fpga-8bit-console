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
- [ ] 3.1 Implement the narrow micro-PC, flags, data register and single-site
      accumulator/store contract for tick-rate voice work
- [ ] 3.2 Move record load/store, trigger metadata, row progression and pattern
      control onto the tick microprogram
- [ ] 3.3 Move pitch, volume, slide, vibrato, arpeggio, fade and instrument
      evaluation onto byte/word-serial micro-operations
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

- [ ] 5.1 Implement recovered integer built-in waveform formulae through the
      shared sample service, one waveform family at a time
- [x] 5.2 Replace the square and pulse ROM banks with exact phase thresholds,
      retain four non-trivial ROM banks, and prove the combined checkpoint
      meets the 15-EBR ceiling with clean oracle probes
- [ ] 5.3 Consolidate or serialize pitch, noise-gain, filter-decode, fade-step
      and microcode constants without increasing the accepted BRAM count

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
