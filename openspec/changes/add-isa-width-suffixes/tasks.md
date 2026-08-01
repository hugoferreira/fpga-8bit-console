## 1. Convention

- [x] 1.1 Add a `pseudo_width` ruledef to `src/isa/pseudo.asm` with the `.b`/`.w`
      contract comment, following the file's existing weakest-behaviour style
- [x] 1.2 Record that bare mnemonics are the byte form, and that the convention
      does not extend to the hardware word instructions
- [x] 1.3 Confirm width mnemonics coexist with every existing addressing-mode
      rule for the same mnemonic, with no ambiguity diagnostic
  - The dotted `asr.b`/`asr.w` spelling was implemented first and reverted: `.`
    is Inlay's member separator, so `asr.w Fixed.word1` resolved to
    `__inlay_q3_asr1_w __inlay_q5_Fixed5_word1` and failed to assemble.

## 2. Arithmetic shift right

- [x] 2.1 Add `asr`, expanding to `cmp #$80` / `ror`
- [x] 2.2 Add the counted form `asr a, N` for N in 1..8, enumerated one rule
      per count so the accepted range is structural
- [x] 2.3 Add `asrw zp`, expanding to `lda zp+1` / `cmp #$80` / `ror zp+1` /
      `ror zp`
- [x] 2.4 Document `asr`'s exact-match flag contract and `asrw`'s weaker one
      (clobbers `A`; `Z`/`N` undefined) at the rule site

## 3. Equivalence harness

- [x] 3.1 Extend `tools/65x02/pseudo_check.py` to parse the width mnemonics, and
      `migrate_ext.py`'s discovery regex so a migrated corpus still parses
- [x] 3.2 Assert byte-identity for every `asr` form including all counted counts
- [x] 3.3 Execute the sign cases `$00`, `$01`, `$7F`, `$80`, `$FF` under both
      incoming carries and compare the accumulator and flags against a reference
      model, so a wrong opcode cannot pass by agreeing with the assembler
- [x] 3.4 Assert the flags `asrw` actually leaves, so a later hardware swap that
      changes them is caught rather than assumed
- [x] 3.5 Assert that out-of-range counts and memory-plus-count forms fail

## 4. Projection

- [x] 4.1 Add `asr` and `asrw` rows to `tools/65x02/pseudo.txt` using
      `docs/cpu-timing-v2.json` for the measured side
- [x] 4.2 State the projected hardware encoding as a claim, and confirm the slice
      claims no opcode slot

## 5. Corpus migration

- [x] 5.1 Migrate the 7 accumulator sites (`collide.inlay.asm` ×3 as one
      `asr a, 3`; `main.asm` ×4)
- [x] 5.2 Migrate the 2 word sites (`draw.inlay.asm` `asr_w1`/`asr_w2`)
- [x] 5.3 Verify the Celeste ROM digest is **unchanged**, via
      `tools/inlay/test_conformance.py`
- [x] 5.4 Verify the breakout image is unchanged via `make pseudo-check` and the
      corpus diff
- [x] 5.5 Run the Celeste functional, framebuffer and PSG trace suites

## 6. Gates and measurement

- [x] 6.1 Record the G3 count (9 sites, two corpora) and the per-width split
- [x] 6.2 Record the surveyed candidates that were cut, with their site counts,
      so the convention is not credited with unearned reach
- [x] 6.3 Confirm G7 in its strengthened form: images bit-identical, not merely
      non-growing
- [x] 6.4 Add an adoption count to the Celeste conformance metrics, via the
      `customOperations` whitelist (`asr`=1, `asrw`=2)
  - Registering them is not optional bookkeeping: an unlisted pseudo-op has its
    annotated line skipped, which silently removed 25 bytes from
    `executableBytes` and made this byte-neutral migration look like a saving.

## 7. Documentation

- [x] 7.1 Document the convention and the two coexisting width spellings in
      `docs/inlay.md`, explaining why silicon mnemonics were not renamed
- [x] 7.2 Add the `asr` idiom to `docs/hardware-gaps.md` as a measured gap
- [ ] 7.3 Resolve the open question on whether `nemo`'s zero sites are a domain
      property before treating the 9-site count as stable

## 8. Result

- 9 sites migrated: `asr a, 3` (collide), `asrw` x2 (draw), `asr` x4 (main.asm).
- Celeste ROM `13ed7d61...` and breakout ROM `3c0385f5...` both **unchanged**.
- Celeste encoded instruction sites 2304 -> 2293; `executableBytes` unchanged at
  5155, as a bit-identical image requires.
- Projection, via `migrate_ext.py --pseudo` on breakout: 4 sites, 8 bytes and
  8 cycles if the encoding is built.
