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
- [x] 1.5 Size the one stage that needs a RAM from the model instead of
      from estimates: minimal exact ring geometry, cell width, ring
      count and block cost (COMPLETE as tools/psg_buffers.py, driving
      the model through its `make_history` hook - flat 732 x int16 per
      voice, 3 EBR measured against the transcription's 7, the comb
      accumulator narrowed to `tz((2x+h)/2)`, the 15-bit blindness of
      the deterministic gate, and the fixpoint witness recorded in
      design.md)

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
      the model. Includes the OLD-state secondary: the model's
      old.render(64) advances the copied q0/dq, which the RTL's
      primary-only continuation lacks - store old_q0 (17 bits) plus its
      dq inputs by repacking the old words (after the slide adoption
      every phase/increment is <<8-aligned, so the old phase/inc low
      bytes are free)
- [ ] 2.5 Filter relocation (design 7): the comb INSIDE each rendered
      block at that oscillator state's own reverb level (so the
      crossfade's old-state continuation carries the previous SFX's
      digit, and the blend follows both combs), then dampen per voice as
      the blend-form recurrence via biased shifts. The comb is the proven
      `tz((2x+h)/2)` accumulator; the ring is its proven minimal geometry
      - flat 732 x int16 per voice, WRAPPING at the cell (captured), one
      ring on iCE40 and eight on Gowin behind REVERB (design 8). Two ring
      reads per sample during the 64-sample blend when the levels differ.
      The shared output delay retires
- [x] 2.5a COMPLETE: the comb moved inside both blocks (`cmb_new` at
      `s_ch_rev`, `cmb_old` at the new `old_rev_r`, one ring port
      sequenced at PWORK+70/+71 so a level change costs no second RAM),
      the reverb digit joined the params-changed copy set, and the
      PATTERN-ADVANCE slip closed with it. That slip was ONE SAMPLE, not
      one tick: W_MUS set the next pattern's `trig_req` at the end of the
      tick pass that had already staged its bank, S_IDLE held the trigger
      behind `bank_ready` to the boundary, and the boundary sample then
      rendered silence (the class-2 stop landed while the trigger pass
      was still queued). A trigger pass now JOINS the staged bank -
      skipped slots copy through `par_cpy` from the staged words instead
      of the active ones - so one boundary flip publishes the tick and
      its triggers together. pattern-chain, filter-reverb-onset and
      filter-reverb-level are byte-exact; 44/44 non-section-3 cases green
      (was 41), psg_tb ALL PASS, walk 906/1275, pre-run 2321/2550
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
- [x] 3.1a Volume half COMPLETE: 12-bit `a` = vol<<8 through the effect
      program (vol_r/pvol_r/fxv_next), fade-in/fade-out as the exact
      quotient and slide as a_s + tz(t*(a0-a_s), d) - the identity that
      buys one product and one divide where the literal form needs two
      of each, with the d-1 round-up on a negative delta because tz of a
      negative quotient is -ceil. a_exact and the x7 publication scale
      retire; the playhead-instrument fold is pre-scaled by 7 into
      vol_r so it publishes what it did before. The Q8 row fraction it
      replaces cost a FIXED 252/256 = 0.984375 on every effect path -
      that ratio, not the reciprocal's error, was what these cases
      measured. Closes effect-1-slide, effect-4-fade-in,
      effect-5-fade-out, effect-slide-once: 48 green (was 44). NOTE
      a_pub must read a REGISTER: publication spans four cycles a sample
      walk can freeze, and the synthesis products reuse the m service
      from PWORK+4, so a live m_res slice reads the walk's arithmetic
- [ ] 3.2 Adopt the slide including its fine path; retire the extra
      8-fractional-bit increment extension it replaces
- [ ] 3.2a With 3.1/3.2 the row-progress reciprocal has no consumer:
      `recip[s] = round(65536/s)` is not exact truncated division
      (2,538/32,640 (t,d) pairs differ - psg_buffers levers) and the
      adopted forms need exact `tz(N, d)` on a 30-bit numerator. Replace
      it with a restoring divide on the existing serial adder (three
      divides per voice-tick = 0.3% of the tick budget) and retire the
      recip EBR; record the block against the ring budget
- [x] 3.2b Divider LANDED: 24 shift-subtract steps over a 24-bit
      dividend field with the partial remainder in the top byte (rem < d
      holds from 0, so the shifted partial is 9 bits and the restored
      remainder is always back under a byte). It is its OWN unit, not a
      mode on the multiply service - the 9-bit compare-subtract is
      cheaper than muxing the 26-bit accumulator's shift direction, and
      a divide can then overlap the next product. The recip table still
      has the pitch half as a consumer and stays until 3.2
- [x] 3.1b Instrument sevenths COMPLETE: the binary composes the note's
      OWN effect first and folds the instrument after - a = tz(a*iv, 7),
      or tz(a0_note * (ia>>8), 7) when the instrument row is the one
      carrying the effect. The RTL folded vol*ivol at 1317>>8 BEFORE the
      effect ran, so both the order and the scale were wrong. The fold
      moves to steps 8/9 (product then a divide by 7 on the same
      restoring unit) and the 1317 constant, vmul/pvmul and K_SLPM's
      re-issue all retire. Two traps: by step 10 d_res holds the
      SEVENTH's quotient, so the music fade must read the captured vol_r
      (not fxv_next, which recomputes from d_res); and the fade product
      must take the POST-seventh amplitude. For a full-volume note the
      exact answer is iv<<8 on the nose - psg_tb's 1260/504 were the old
      calibration and are now 1280/512. Closes the whole sfx-instrument
      family: 56 green, 1 red
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
- [x] 5.1a Capture the cases that size the ring rather than its
      arithmetic (COMPLETE, 2026-07-28: six probes generated by
      psg_oracle.py and exported from PICO-8 - the three-rung fixpoint
      ladder, onset, level and pair). Every recorded choice moved from
      reasoned to proven, and two lost: the int16 cell **wraps** rather
      than saturating, and the comb runs inside each block's render at
      its own state's level rather than after the crossfade. Rings are
      per voice and are written unconditionally, so a pool is an
      approximation, not a reading. Model now 57/57 byte-exact
- [ ] 5.2 Re-freeze the reduce-psg-ice40-area byte-compare baseline at
      this change's final renders and note it in that change's design
- [ ] 5.3 Celeste and NEMO headless runs with active audio; verify by
      capture and by ear
- [ ] 5.4 Final seed-1 and multi-seed synthesis: hold or improve
      6,199 cells / 15 EBR / 28.125 MHz timing; record the freed-EBR
      disposition (banked or spent on the microcode home)
- [ ] 5.5 Validate the change strictly and reconcile every task with
      recorded evidence
