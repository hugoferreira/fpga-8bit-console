## 0. Coordination

- [x] 0.1 Append a note to `docs/agent-coordination.md`: `rtl/psg.sv` is being
      substantially rewritten, this changes the audio for celeste and breakout
      too, and the other agent should not edit it while the rewrite is in
      flight (re-read the file first, per the shared-file protocol)
- [x] 0.2 Record the pre-change reference: render each game's music with
      `make psg-wav` and keep the WAVs, so the rewrite can be A/B'd rather
      than judged from memory

## 1. Historical multiplier experiment

This experiment was motivated by a supposed 159-clock simulator budget. That
budget is retired: Verilator lowering and host performance do not constrain
hardware scheduling. The single-cycle multiplier was subsequently returned to
an exact serial implementation to save LC.

- [x] 1.1 Replace the 8-cycle shift-add sample×volume unit (`n_a`/`n_p`/`n_cnt`
      in `rtl/psg.sv`) with a single-cycle 8×8 multiply, keeping the full
      16-bit product that the current code deliberately preserves
- [x] 1.2 Confirm `make test-psg` passes unchanged - green. The *product* is
      bit-identical, but the render is not, and finding out why mattered:
      see 1.6
- [x] 1.3 Measure the new per-voice clock cost (**gate P1** met): the pipeline
      now runs `pst` 0->3 with no waits, so a voice costs **4 clocks**, better
      than design.md's estimate of 5. This measurement is historical and does
      not impose a limit on the microcoded replacement.
- [x] 1.4 Synthesise and record the LC delta for the multiplier. The
      single-cycle array form cost 346 LC and was reverted; the current serial
      sample×volume unit overlaps its iterations with BRAM write-back.
- [x] 1.6 (found during 1.1, not originally scoped) **The noise LFSR was
      clocked by the system clock, not by anything musical.** Shortening the
      multiply changed the noise, because the LFSR advanced once per system
      clock and the pipeline now takes fewer of them. Scaling to sixteen voices
      would have changed it again, silently. The LFSR now steps once per voice
      per sample, so the noise is independent of pipeline timing. Measured:
      sequence differs, RMS unchanged to within 0.01% on NEMO's sfx 8
- [x] 1.7 Narrow the exact 22050 Hz fractional accumulator from 32 to 27 bits.
      The accumulator is bounded by `CLK_HZ`, whose maximum supported value is
      the 112.5 MHz PLL output (27 bits). iCE40 synthesis falls from 5499 to
      **5489 LC** with the repaired effect multiplier present; 12-second NEMO
      and Celeste renders are byte-identical.
- [x] 1.5 Superseded: the repository now has one 112.5 MHz PLL source and an
      integer-related clock tree. No independent sound PLL or asynchronous
      register-interface crossing is planned.

## 2. Partition the voice state by rate

- [x] 2.1 Classify every `[0:3]` array in `rtl/psg.sv` as per-sample or
      per-tick. Measured 147 / 189 bits per voice against the estimated
      133 / 200, and the per-tick half splits again: ~154 bits of bulk note and
      instrument state that only the walked voice ever touches (BRAM), and
      ~12 bits of control state. The CPU never addresses a voice - its map is
      four channels - so that control state is just 16-bit vectors plus 2-bit
      tags, and the pending trigger parameters are per-channel, not per-voice.
      design.md updated; total is **2492 flops + 0.65 of one BRAM** (32% of an
      HX8K), not the ~2900 first written
- [x] 2.1a (found during 2.1, not originally scoped) **The noise gain was
      being looked up by the wrong channel's pitch.** `e_pitch` is derived from
      the sequencer's rotating ring, which only advances on ticks, so during
      synthesis it holds channel 0's note no matter which channel is being
      synthesised - every channel got channel 0's noise gain. Latched
      `snd_pitch` per channel alongside `snd_wave`/`snd_wt`/`snd_wtb` instead.
      Test 20c covers it. NEMO's music moves +0.05% RMS, so it was inaudible
      here, but it would not have been for a cart with noise on two channels at
      different pitches. Exactly the class of fault the de-rotation removes by
      construction, which is why it surfaced while classifying the state
- [x] 2.3 Replace the ring rotation with an explicit voice index. Done more
      simply than planned: index 0 during a visit to voice *v* already *is*
      voice *v*, so `name[0]` became `name[c]` (walk) and `name[pc_ch]`
      (synthesis) and both rotations were deleted outright - no working-copy
      registers needed. 34 rotation lines removed, 171 accesses now name their
      voice, both games render bit-identically, `make test-psg` and
      `make test-nemo` green.
      **This is what removes the noise-gain class of bug by construction**: the
      synthesis path contains no `[c]` index at all now (statically checked),
      so it cannot read the sequencer's voice, and any future attempt to would
      be a visible `[c]` in a `pc_ch` block rather than an invisible `[0]`
- [x] 2.2 Move **all** per-voice state to a BRAM register file, not just the
      per-tick half. Synthesis (3.5) shows the marginal cost of a voice is 366
      LUT4 + 316 flops and 336 bits is one voice's state: the muxes to reach
      per-voice registers are the whole scaling cost, and the datapath is
      already shared. Target ~3900 LUT4 / ~1100 flops / ~18 BRAM for sixteen
      voices - cheaper than today's four. The corrected classic PICO-8 model
      has eight playback slots (four foreground plus four music), stored in
      `vmem`, `spar_m` and `sosc_m`; all three infer `SB_RAM40_4K`. Measured
      standalone: **5489 LC / 19 BRAM**, versus 9378 LUT4 / 5811 flops for the
      abandoned sixteen-register-slot model.
- [x] 2.2a One PLL at 112.5 MHz as the design's single clock source, with
      everything an integer division of it. `rtl/pll.v` regenerated
      (`icepll -i 25 -o 112.5`, exact), instantiated in `top.sv` for the first
      time; `clocks.sv` divides /32 for the chip (3.515625 MHz, 60.155 Hz
      frames) and currently /4 for the PSG (28.125 MHz). Both derive from the
      same source, so there is no asynchronous crossing. The architectural PSG
      target remains the undivided source once routed timing permits it.
      **Corrects a long-standing wrong constant**: `top.sv` fed the PSG
      `BOARD_CLK_HZ = 25 MHz`, but this video timing at 25 MHz is 428 fps, so
      that was never the real rate. The design has always run at ~3.5 MHz
      (161 x 121 x 3 x 60 = 3,506,580 exactly), which is why `chip.sv`'s
      default said so
- [x] 2.2a1 Measure Fmax with nextpnr: **29.62 MHz** routed at seed 1 on HX8K,
      so 112.5 MHz is disproven. The critical path is the mixer leaf into the
      first reduction level. 56.25 MHz (/16) is not yet a valid fallback
      either; timing optimisation remains separate from this area pass.
- [x] 2.2a2 Retire the console simulator's 159 clocks/sample as an RTL budget.
      It describes one Verilated lowering on one host, not the derived hardware
      clock. Simulation SHALL verify sample/tick boundary behaviour at a
      declared `CLK_HZ`; wall-clock execution speed is non-normative.
- [x] 2.2a3 Superseded: matching a simulator's host stepping ratio is not a
      prerequisite for hardware scheduling or area optimisation.
- [ ] 2.2b (superseded) Swap only the bulk note/instrument state to BRAM.
      **Deliberately after section 3**: de-rotate, scale the pool, prove
      allocation, and only then rework storage, so the audible change is
      verifiable before the risky part and 8-voices-in-flops stays a fallback
- [x] 2.4 Confirm `make test-psg` still passes with the eight-slot
      foreground/music model - the partition changes storage, not behaviour
- [x] 2.5 Synthesise and confirm `vmem`, `spar_m` and `sosc_m` each map through
      the iCE40 block-RAM path (**gate P2**)

## 3. Scale the pool to sixteen voices

- [x] 3.1 Widen the voice arrays and the walk from 4 to 16
- [x] 3.2 Add the two-bit logical channel tag per voice
- [ ] 3.3 Point the music sequencer at voices tagged 0-3 rather than at
      channels 0-3 directly
- [ ] 3.4 Map the CPU-facing `$10-$17` channel registers onto "the voice
      carrying this tag", so an explicitly addressed channel behaves exactly
      as it does today
- [x] 3.5 Synthesise and record LC/BRAM usage (**gate P3 FAILED as built, and
      that is the useful result**): 4 voices = 4991 LUT4 / 2023 flops, 8 =
      6285 / 3287, 16 = 9378 / 5811, against an HX8K's 7680 LCs which must also
      hold the CPU, PPU and compositor. Sixteen voices in flip-flops does not
      fit. `NV` is therefore left at 4 in the tree - the parameterisation is
      done and proven, the count moves once 2.2 lands. Whole-chip synthesis
      could not be run: `bin/toplevel.json` currently depends on the other
      agent's in-flight `rtl/golden/*.v`

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

## 9. Microcode-oriented PSG

- [x] 9.1 Record the reproducible pre-microcode baseline: RTL fingerprint
      `f58e26f4c158` at `919522d`, 5489 LC / 19 BRAM, 29.62 MHz routed Fmax,
      full PSG regression passing, and byte-exact 12-second NEMO
      (`ba4e256cecb490f614412b4a0e550d81da6169ea`) and Celeste
      (`9c4a7f017bc04ce1580580eb3ca539e58c9dc067`) reference renders
- [x] 9.2 Define a compact microinstruction and working-register contract for
      tick-rate pitch, volume, slide, vibrato, arpeggio, fade and instrument
      evaluation, preserving every current width, signed operation and clamp;
      the six-op `xs` contract is documented beside the shared multiplier
- [ ] 9.3 Replace the parallel tick/effect operand and result networks with the
      microcoded engine; tick work must complete before the next 183-sample
      boundary
      - Measured and rejected: a general shared 25-bit ALU cost 5632 LC; split
        25/9/9-bit lanes cost 5646 LC. Serialising both 3x3 instrument-volume
        products reached 5446 LC but added 128 clocks per tick walk and changed
        both reference renders; serialising one cost 5526 LC. The byte-exact
        six-op engine remains until the commit schedule is decoupled from tick
        evaluation.
- [ ] 9.4 Measure LC, BRAM and routed Fmax; require `make test-psg` and the
      reference renders to remain byte-identical

## 10. Reset and register audit

- [x] 10.1 Classify every PSG reset register as control/valid state that must
      reset, or datapath/working state that is overwritten before use
- [x] 10.2 Remove resets and redundant holding registers only where validity
      gating proves their value unobservable; do not substitute
      simulation-only initialization for hardware correctness
- [x] 10.3 Measure LC/packing and rerun the full PSG and render regressions:
      fingerprint `ea4e9846edfb` at `75b121f`, 5456 LC / 19 BRAM, 32.10 MHz
      routed Fmax, full regression passing, and byte-exact NEMO/Celeste hashes
      unchanged from 9.1

## 11. Iterative reciprocal networks

- [x] 11.1 Inventory constant reciprocal and constant-product networks,
      beginning with `soft_add`'s exact `(excess * 52429) >> 18`, and record
      their synthesized logic cones; the remaining `/speed` operation is
      already a BRAM table, volume products are already serial, and `soft_add`
      is a four-adder factored constant product
- [ ] 11.2 Replace each selected network with an iterative shift/add sequence,
      preserving exact truncation, saturation and pairwise reduction order
      - Measured and rejected for LC: an exact 18-step restoring divide by five
        cost 5465 LC / 44.78 MHz; packing dividend and quotient together cost
        5468 LC / 44.27 MHz. Both improve Fmax substantially but exceed the
        retained 5456-LC factored carry-chain implementation.
- [ ] 11.3 Assert that all mix work completes before the next sample boundary
      at the current 28.125 MHz divided clock and the 112.5 MHz target
- [ ] 11.4 Measure LC/Fmax and require byte-exact reference renders

## 12. Shared ALU/DSP synthesis walk

- [ ] 12.1 Schedule phase advance, phaser ratio, noise gain, brown integration,
      low-pass filtering, volume multiplication and mix compression around one
      width-safe add/subtract/shift operation contract
- [ ] 12.2 Implement the shared engine so iCE40 uses LUT/carry logic and
      DSP-capable targets may map the same arithmetic contract to a DSP
      - Measured and rejected: applying only the phaser/detune phase increment
        to `s_phase2` over four clocks cost 5652 LC / 31.80 MHz because the
        state-conditioned register-input mux outweighed the removed adder chain.
        Further sharing must preserve one write site per working register.
- [ ] 12.3 Add deadline assertions for completion of all eight slot visits and
      pairwise mixing before each 22 050 Hz sample boundary
- [ ] 12.4 Measure LC/BRAM/Fmax after each migrated operation; reduce `PSGDIV`
      only when routed timing proves the next master-derived rate closes
- [ ] 12.5 Run `make test-psg`, all game tests, pitch/waveform analysis and
      byte-exact NEMO/Celeste render comparisons

## 13. Verification

- [ ] 13.1 `make test-psg` green
- [ ] 13.2 `make test-nemo` green, all three games build and run
- [ ] 13.3 `make psg-rows` on NEMO's SFX 8 no worse than before the change
- [ ] 13.4 Play each game and confirm no sound effect can interrupt the music,
      by scrolling the NEMO level selector as fast as the input allows
      (**gate P5** - the symptom that started this)
