## Why

The pseudo-op layer has grown three unrelated ways of saying "how wide is this
operand", and the corpus is starting to trip over the gap between them:

- `addw`/`subw`/`cmpw` carry the width in the mnemonic, as a `w` suffix;
- `ldab`/`stab` name the **register pair** rather than a width;
- `asl`/`lsr`/`rol`/`ror` have no width at all — they are byte-only, and the
  16-bit versions are open-coded at every site.

That third row is where it bites. The 6502 has no arithmetic shift right, so
all three corpora hand-roll one out of `cmp #$80 / ror`, in two different
shapes depending on operand width:

| Shape | Sequence | celeste | nemo | breakout | total |
| --- | --- | ---: | ---: | ---: | ---: |
| accumulator | `cmp #$80` / `ror` | 3 | 0 | 4 | **7** |
| word | `lda X+1` / `cmp #$80` / `ror X+1` / `ror X` | 2 | 0 | 0 | **2** |
| | | | | | **9** |

Scored as two separate instructions, `ASR A` (7) and `ASR.W zp` (2) **both fail
gate G3**, which requires an idiom to occur at least 8 times. Scored as one
instruction whose operand has a width, arithmetic shift right occurs **9 times
across two corpora** and passes.

That is the actual argument for width suffixes, and it is not cosmetic: making
width an operand modifier rather than part of the mnemonic changes what counts
as "one instruction" for the frequency gate. Arithmetic shift right is
load-bearing; its byte and word forms, taken separately, are not.

The convention is also self-disambiguating, which a bare operand is not. The
counted shifts added by `redesign-celeste-for-inlay` task 10.9 had to be spelled
`asl a, N` rather than `asl N` because a bare expression collides with
`asl {zaddr: u8}`, and customasm v0.14.1 resolves that collision by silently
preferring the smaller encoding — `asl 3` assembles to `06 03`, a
read-modify-write of zero page address 3, with no diagnostic. A width suffix is
part of the mnemonic token and cannot collide with an addressing mode.

## What Changes

- **A width-suffix convention for `src/isa/pseudo.asm`.** A bare mnemonic is
  the byte form and a trailing `w` is the word form, matching the `addw`/`subw`/
  `cmpw` spelling this ISA already uses. The suffix is additive and no existing
  source moves.
- **`asr` and `asrw` pseudo-operations**, byte-identical to the sequences above,
  plus the counted form `asr a, N` composing with task 10.9's counted shifts.
  `collide.inlay.asm:172` is three consecutive accumulator shifts and becomes a
  single `asr a, 3`.

  **The m68k dotted spelling was tried first and cannot be used.** It assembles
  correctly in raw customasm, but `.` is the Inlay frontend's member separator —
  the same dot in `Fixed.word1` and `CelesteObject.core` — so at statement
  position a dotted mnemonic is lexically indistinguishable from a qualified
  name. Inlay resolved `asr.w Fixed.word1` into
  `__inlay_q3_asr1_w __inlay_q5_Fixed5_word1`, which then failed to assemble.
  Excepting a mnemonic whitelist in the frontend would make `.` mean one thing
  at statement start and another everywhere else, which is the positional
  ambiguity that produced the `asl 3` miscompile in the first place.
- **Migration of the 9 measured sites** in celeste and breakout. Byte-identical
  by construction, so `make pseudo-check` and the ROM digest both hold.
- **A projection entry in `tools/65x02/pseudo.txt`** so a future hardware slice
  can be scored before it is built.
- **No renaming of `addw`/`subw`/`cmpw`/`ldab`/`stab`.** These are silicon —
  `OP_ADDW` is a decode row in `rtl/cpu6502_decode.sv` — and renaming them to
  `add.w` would decouple the assembler mnemonic from the decode table for no
  measured benefit. The convention governs the pseudo layer only.

### Cut by the measurements

The rest of the width-suffix space was surveyed across all three corpora and
**does not earn an operation**. Reported so the convention is not credited with
reach it does not have:

| Candidate | Sequence | Sites | Verdict |
| --- | --- | ---: | --- |
| `incw` | `inc X` / `bne` / `inc X+1` | 3 | fails G3 |
| `rorw` (standalone) | `ror X+1` / `ror X` | 2 | fails G3; and both sites are already inside the `asrw` window, so it is not independent evidence |
| `negb` | `eor #$FF` / `add #1` | 2 | fails G3 |
| `movw` | `lda X`/`sta Y`/`lda X+1`/`sta Y+1` | 1 | fails G3; `ldab`/`stab` already cover this in silicon |
| `aslw` | `asl X` / `rol X+1` | 0 | absent from every corpus |
| `lsrw` | `lsr X+1` / `ror X` | 0 | absent from every corpus |
| `rolw` | `rol X` / `rol X+1` | 0 | absent from every corpus |

Four of the seven candidates have **zero** sites. The convention is worth
adopting for what it does to the `asr` count, not for the table it could fill.

## Impact

- `src/isa/pseudo.asm` — new `pseudo_width` ruledef; no existing rule changes.
- `tools/65x02/pseudo_check.py` — extend the equivalence harness to the width
  forms and to `asr`'s sign behaviour.
- `tools/65x02/migrate_ext.py` — its pseudo-op discovery regex, so a migrated
  corpus does not read as unknown mnemonics.
- `tools/inlay/celeste_redesign_metrics.py`, `tools/inlay/test_conformance.py` —
  register `asr`/`asrw` in the operation whitelist. A pseudo-op missing from it
  is not merely uncounted: the annotated parser skips the line, so its expansion
  bytes vanish from `executableBytes` and a byte-neutral migration reads as a
  25-byte saving it did not make.
- `tools/65x02/pseudo.txt` — projection entries for `asr` / `asrw`.
- `src/celeste/collide.inlay.asm`, `src/celeste/draw.inlay.asm`,
  `src/main.asm` — 9 migrated sites.
- `docs/inlay.md`, `docs/corpora.md` — document the convention.
- **Not** `docs/opcodes.md`: this slice claims no opcode. The `$x3` extension
  column is fully allocated and the registry is generated from
  `rtl/cpu6502_decode.sv`; an encoding claim belongs to the hardware slice that
  adds the decode row. 14 slots remain unallocated.
