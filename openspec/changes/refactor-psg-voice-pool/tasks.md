## 0. Coordination

- [x] 0.1 Append a note to `docs/agent-coordination.md`: `rtl/psg.sv` is being
      substantially rewritten, this changes the audio for celeste and breakout
      too, and the other agent should not edit it while the rewrite is in
      flight (re-read the file first, per the shared-file protocol)
- [x] 0.2 Record the pre-change reference: render each game's music with
      `make psg-wav` and keep the WAVs, so the rewrite can be A/B'd rather
      than judged from memory

## 1. Buy the simulator's cycles: replace the serial multiply

Hardware has the clocks already (16 voices = 17% of a 25 MHz sample budget).
This section exists for the simulator, whose console runs ~7x slower and would
be at 121%.

- [x] 1.1 Replace the 8-cycle shift-add sample×volume unit (`n_a`/`n_p`/`n_cnt`
      in `rtl/psg.sv`) with a single-cycle 8×8 multiply, keeping the full
      16-bit product that the current code deliberately preserves
- [x] 1.2 Confirm `make test-psg` passes unchanged - green. The *product* is
      bit-identical, but the render is not, and finding out why mattered:
      see 1.6
- [x] 1.3 Measure the new per-voice clock cost (**gate P1** met): the pipeline
      now runs `pst` 0->3 with no waits, so a voice costs **4 clocks**, better
      than design.md's estimate of 5. 16 voices = 64 clocks: 40% of the
      simulator's 159 and 5.6% of hardware's 1134
- [ ] 1.4 Synthesise and record the LC delta for the multiplier
- [x] 1.6 (found during 1.1, not originally scoped) **The noise LFSR was
      clocked by the system clock, not by anything musical.** Shortening the
      multiply changed the noise, because the LFSR advanced once per system
      clock and the pipeline now takes fewer of them. Scaling to sixteen voices
      would have changed it again, silently. The LFSR now steps once per voice
      per sample, so the noise is independent of pipeline timing. Measured:
      sequence differs, RMS unchanged to within 0.01% on NEMO's sfx 8
- [ ] 1.5 If 1.1 does not buy enough, fall back to a PLL: both of the HX8K's
      PLLs are unused and `rtl/pll.v` (25 -> 50 MHz) is already written but not
      instantiated. Cost is a clock-domain crossing on the register interface
      and the audio-RAM upload port, so this is the reserve option, not the
      first move

## 2. Partition the voice state by rate

- [ ] 2.1 Classify every `[0:3]` array in `rtl/psg.sv` as per-sample or
      per-tick, and write the split into design.md if it differs from the
      estimate (~133 vs ~200 bits per voice)
- [ ] 2.2 Move the per-tick half into a BRAM-backed register file addressed by
      voice index: read the record, run the existing per-tick states against a
      single working copy, write it back
- [ ] 2.3 Replace the `[0:3]` ring rotation with an explicit voice index in the
      sequencer walk
- [ ] 2.4 Confirm `make test-psg` still passes with four voices - the
      partition must not change behaviour, only storage
- [ ] 2.5 Synthesise and confirm one `SB_RAM40_4K` covers the per-tick state
      (**gate P2**)

## 3. Scale the pool to sixteen voices

- [ ] 3.1 Widen the voice arrays and the walk from 4 to 16
- [ ] 3.2 Add the two-bit logical channel tag per voice
- [ ] 3.3 Point the music sequencer at voices tagged 0-3 rather than at
      channels 0-3 directly
- [ ] 3.4 Map the CPU-facing `$10-$17` channel registers onto "the voice
      carrying this tag", so an explicitly addressed channel behaves exactly
      as it does today
- [ ] 3.5 Synthesise and record LC/BRAM usage against design.md's estimate of
      ~2100 flops + 1 BRAM (**gate P3**: total device usage must leave room
      for the PPU, compositor and CPU)

## 4. Hardware auto-allocation

- [ ] 4.1 Add the auto-allocate register write: start SFX n on a voice that is
      not playing, scanning in a fixed order
- [ ] 4.2 Drop the request when no voice is free, without disturbing any
      playing voice
- [ ] 4.3 Testbench: five auto-allocated sounds over four music voices all
      sound and the music is untouched
- [ ] 4.4 Testbench: a full pool drops the request and stops nothing
- [ ] 4.5 Testbench: an explicit channel trigger still replaces the voice
      carrying that tag

## 5. Delete the borrow/restore machinery

- [ ] 5.1 Remove `sav_sfx`, `sav_row`, `sav_valid` and the preempt/restore
      paths, and the `launched` clearing that exists to stop a borrowed voice
      pacing the pattern
- [ ] 5.2 Remove test 18b/18c from `rtl/psg_tb.sv`, replaced by the pool tests
      in section 4 - record in the test file *why* they went, so the races
      they cover are not silently reintroduced
- [ ] 5.3 Keep the reservation mask register readable and writable, but stop
      treating it as load-bearing

## 6. PICO-8 mixing

- [ ] 6.1 Implement `soft_add`: pass through below ±24576, compress the excess
      5:1 above it, using the binary's `(excess * 52429) >> 18` form
- [ ] 6.2 Reduce the sixteen voices through a pairwise tree in voice order
- [ ] 6.3 Testbench: quiet material below the threshold sums unchanged, and a
      loud mix compresses rather than wrapping
- [ ] 6.4 Testbench: the pairwise result differs from a flat sum for a mix
      that crosses the threshold, confirming the tree is really pairwise
- [ ] 6.5 A/B the rendered music for all three games against the section 0
      reference and listen (**gate P4**)

## 7. Software and tooling

- [ ] 7.1 Collapse `src/nemo/sound.asm`'s `sfx_play` to a single store to the
      auto-allocate register; drop `sfx_busy` and the `bitmask` scan
- [ ] 7.2 Do the same for breakout's copy in `src/main.asm`
- [ ] 7.3 Check whether celeste auto-picks and convert it too (coordinate
      first - it is the other agent's corpus)
- [ ] 7.4 Extend `--psg-trace` in `sim/console.cpp` to report voices with
      their tags, keeping the existing four-channel view derivable so
      `tools/p8_music_trace.py` comparisons still work
- [ ] 7.5 Update `docs/hardware-gaps.md`: gaps 2 (sixteen voices) and 3
      (nonlinear pairwise mixer) are closed

## 8. Verification

- [ ] 8.1 `make test-psg` green
- [ ] 8.2 `make test-nemo` green, all three games build and run
- [ ] 8.3 `make psg-rows` on NEMO's SFX 8 no worse than before the change
- [ ] 8.4 Play each game and confirm no sound effect can interrupt the music,
      by scrolling the NEMO level selector as fast as the input allows
      (**gate P5** - the symptom that started this)
