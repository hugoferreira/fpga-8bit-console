# adopt-pico8-integer-audio — tasks

## 1. The reference model (formulas proven before any RTL)

- [x] 1.1 Build a Python model of the binary's oscillator core from
      pico8-psg-re.md: 16-bit p, 17-bit q0 with the per-mode dq derivation
      and `u16(q0 << m)` read, all eight wave functions, `scale(z) =
      tz(G*z/3072)` / noise 2048, `G = tz(3a/2)`, `tz(a*iv/256)` volume
      composition (COMPLETE as tools/psg_binary_model.py: waves, effects,
      detune/buzz/dampen/reverb, meta-instruments, the eight-leaf mix
      tree and the pattern-chain music flow; noise excluded at the
      shared-RNG boundary per task 4.2)
- [ ] 1.2 Instruction-verify the still-unchecked formulas against
      pico8.x86_64.asm (tri_raw constants, saw, fades, vibrato, slide fine
      path, the 64-sample blend, noise hold/interp) the way scale/organ/
      drop/volume were verified; record each fingerprint in design.md
- [x] 1.3 Render the deterministic oracle cases through the model and
      require byte-equality against the stored PICO-8 exports; adjudicate
      any mismatch as a notes bug before proceeding (the 0.653 precedent)
      (48/48 byte-exact via the durable `psg_binary_model.py sweep`
      harness; every adjudication recorded in design.md's milestone
      blocks)
- [x] 1.4 Freeze the model as the per-stage gate: RTL stages must equal
      the model exactly on the cases their formulas touch (the sweep
      subcommand is the gate's executable form; level-2 dampen/reverb and
      the dampen-reverb order are recorded open in design.md pending the
      task-5.1 probe additions)

## 2. Wave core in RTL (stages per the design's adoption map)

- [ ] 2.1 Secondary phase: q0 as a true 17-bit register in the repacked
      phase2 state words, universal advance with the proven dq adder
      forms (dq.k* in psg_hw_forms); retire det_ceil and the phaser's
      PWORK+7..9 serial subtracts, freeing those ALU slots
- [ ] 2.2 Wave evaluation: 16-bit z from the proven integer forms
      reading p = phase[23:8] (tilt two-add ramp + recip7/recip15,
      organ via recip3, thresholds, alt family, wavetable lerp at load
      shift 7); retire wrom, the tsaw/saw shift approximations, buzzsq,
      det_norm and the x85 phaser network
- [ ] 2.3 Amplitude: 12-bit `a` through the tick pipeline and parameter
      bank (repack), instrument sevenths via recip7, G = a+(a>>1) with
      the detune boost a+(a>>2); G*z on the m-service plus >>10 and the
      recip3 unit (svc.two_pass_G or a widened B port - decide by
      seed-1); retire the 1317 constant, K_SLPM and the 254-scale
- [ ] 2.4 Crossfade at 16-bit: one-multiply blend ((old<<6)+i*(new-old))
      on the existing service slots; transitions re-verified against
      the model
- [ ] 2.5 Filter relocation (design 7): comb-then-dampen per voice on
      the post-blend stream, dampen as the blend-form recurrence via
      biased shifts, per-voice 17-bit ring behind REVERB (design 8);
      the shared output delay retires
- [ ] 2.6 Mixer rescale: SA_TH -> 24576, exact-scale leaves, retire the
      2x internal scale and the output >>6; dry16 is the final sum
      (bound.mix_never_clips holds under the four-audible invariant)
- [ ] 2.7 Gate: byte-exact vs adopt-exact references on every case the
      wave core touches (waves, pitches, filters, mixes, transitions),
      psg_tb with deadline assertions, seed-1 placed cells and EBR
      count against the 6,199/15 checkpoint

## 3. Effect recurrences

- [ ] 3.1 Adopt drop, fade-in, fade-out exactly (idiv-truncation
      semantics); model-exact per tick
- [ ] 3.2 Adopt the slide including its fine path; retire the extra
      8-fractional-bit increment extension it replaces
- [ ] 3.3 Adopt vibrato and arpeggio recurrences; model-exact per tick
- [ ] 3.4 Verify the 64-sample crossfade against the binary's
      `tz((i*new + (64-i)*old)/64)` under the new operand forms

## 4. Noise to the boundary

- [ ] 4.1 Implement `_codo_random` (rol32 H/L) and the hold/interpolated
      modes with their intermediate truncations
- [ ] 4.2 Keep noise gates statistical; cite the shared-RNG boundary in
      the gate definitions per the spec

## 5. Gates, references, and closure

- [x] 5.1 Re-capture the oracle references once; flip every deterministic
      case to exact comparison; keep statistical gates only for
      noise-consuming cases (53 references at
      build/psg_oracle/adopt-exact; model 51/51 byte-exact including the
      three new level-2/order probes; matrix gates are mismatches_max=0
      for deterministic cases, statistical for the noise pair;
      results.json records the all-red RTL starting line the RTL
      sections must close)
- [ ] 5.2 Re-freeze the reduce-psg-ice40-area byte-compare baseline at
      this change's final renders and note it in that change's design
- [ ] 5.3 Celeste and NEMO headless runs with active audio; verify by
      capture and by ear
- [ ] 5.4 Final seed-1 and multi-seed synthesis: hold or improve
      6,199 cells / 15 EBR / 28.125 MHz timing; record the freed-EBR
      disposition (banked or spent on the microcode home)
- [ ] 5.5 Validate the change strictly and reconcile every task with
      recorded evidence
