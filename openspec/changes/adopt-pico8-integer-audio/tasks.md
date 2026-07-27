# adopt-pico8-integer-audio — tasks

## 1. The reference model (formulas proven before any RTL)

- [ ] 1.1 Build a Python model of the binary's oscillator core from
      pico8-psg-re.md: 16-bit p, 17-bit q0 with the per-mode dq derivation
      and `u16(q0 << m)` read, all eight wave functions, `scale(z) =
      tz(G*z/3072)` / noise 2048, `G = tz(3a/2)`, `tz(a*iv/256)` volume
      composition
- [ ] 1.2 Instruction-verify the still-unchecked formulas against
      pico8.x86_64.asm (tri_raw constants, saw, fades, vibrato, slide fine
      path, the 64-sample blend, noise hold/interp) the way scale/organ/
      drop/volume were verified; record each fingerprint in design.md
- [ ] 1.3 Render the deterministic oracle cases through the model and
      require byte-equality against the stored PICO-8 exports; adjudicate
      any mismatch as a notes bug before proceeding (the 0.653 precedent)
- [ ] 1.4 Freeze the model as the per-stage gate: RTL stages must equal
      the model exactly on the cases their formulas touch

## 2. Wave core in RTL

- [ ] 2.1 Universalize the secondary phase: q0 as 17-bit state with the
      binary's dq per waveform, riding the existing second-voice read
      slots; assert the visit still fits the schedule
- [ ] 2.2 Replace wave evaluation with the integer forms (thresholds,
      shifts, organ's ÷3) reading p = phase[23:8]; retire the
      triangle/organ ROM bank and the 5.1 tilted-saw/saw approximations
- [ ] 2.3 Move the amplitude stage to `tz(G*z/3072)` on the product
      service with the magnitude/sign pattern; retire the 254-scale and
      1317 constants
- [ ] 2.4 Gate: model-exact on all wave cases, psg_tb, seed-1 placed
      cells and EBR count against the 6,199/15 checkpoint

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

- [ ] 5.1 Re-capture the oracle references once; flip every deterministic
      case to exact comparison; keep statistical gates only for
      noise-consuming cases
- [ ] 5.2 Re-freeze the reduce-psg-ice40-area byte-compare baseline at
      this change's final renders and note it in that change's design
- [ ] 5.3 Celeste and NEMO headless runs with active audio; verify by
      capture and by ear
- [ ] 5.4 Final seed-1 and multi-seed synthesis: hold or improve
      6,199 cells / 15 EBR / 28.125 MHz timing; record the freed-EBR
      disposition (banked or spent on the microcode home)
- [ ] 5.5 Validate the change strictly and reconcile every task with
      recorded evidence
