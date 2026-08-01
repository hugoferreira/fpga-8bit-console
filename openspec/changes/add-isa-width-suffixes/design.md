## Context

`src/isa/pseudo.asm` exists to let an instruction be adopted, counted and
scored *before* it earns a decode row. Its header states the contract rule: a
pseudo-op and its eventual hardware form are not interchangeable in general, so
each rule documents the **weakest** behaviour of the two, and code written
against it is correct under either.

This slice adds a width axis to that layer. It is prompted by arithmetic shift
right, which the 6502 lacks entirely and which every corpus therefore
open-codes — in two shapes that differ only by operand width.

## Goals / Non-Goals

**Goals**

- One spelling convention for operand width across the pseudo layer.
- `asr` available at both widths, byte-identical to what it replaces.
- The width axis to be a *modifier*, so an operation is counted once for gate
  G3 rather than once per width.

**Non-Goals**

- Renaming silicon. `addw`/`subw`/`cmpw`/`ldab`/`stab` are decode rows; their
  mnemonics match `rtl/cpu6502_decode.sv` and stay as they are.
- Claiming an opcode. This slice ships no hardware; the projection in
  `pseudo.txt` is a claim, not an allocation.
- An `l` (32-bit) width. Nothing in any corpus asks for one.
- Retrofitting a byte marker onto existing source. Bare already means byte.

## Decisions

### Decision: width is an operand modifier, not part of the mnemonic

`asr` and `asrw` are one operation at two widths, not two operations. This
is what lets the idiom clear gate G3 (7 + 2 = 9 sites) where the two shapes
scored separately would both fail. It also matches how the corpus actually
reads: the sites are the same *thought* — halve a signed value — differing only
in how wide the value is.

### Decision: a bare mnemonic is the byte form

`ror` keeps meaning the byte rotate. Making a width marker mandatory would
rewrite every shift site in three corpora to buy nothing, and would invalidate
the counted forms (`asl a, N`) landed by `redesign-celeste-for-inlay` task 10.9.
The counted and width axes compose: `asr a, 3`.

### Decision: the width marker is `w`, not `.w`

The m68k dotted spelling was the starting point and was tried first. It
assembles correctly in raw customasm — `ror.w`, `ror.b`, `ror zp` and bare `ror`
coexist and produce `6621 6620 | 6620 | 6620 | 6a`. It is nevertheless
unusable here, because `.` is the **Inlay frontend's member separator**: the
same dot as in `Fixed.word1` and `CelesteObject.core`. At statement position a
dotted mnemonic is lexically indistinguishable from a qualified name, and Inlay
resolved `asr.w Fixed.word1` into
`__inlay_q3_asr1_w __inlay_q5_Fixed5_word1`, which then failed to assemble.

Teaching the frontend to except a mnemonic whitelist would make `.` mean one
thing at statement start and another everywhere else. That positional ambiguity
is precisely the failure mode that produced the `asl 3` miscompile, so the
separator changes instead of the language.

A trailing `w` also happens to be the spelling this ISA already uses for width,
in `addw`/`subw`/`cmpw`. It remains part of the mnemonic token, so it cannot be
confused with an addressing mode — which is the property that mattered.

### Decision: `asr`'s contract is exact; `asrw`'s is not

This is the substantive difference between the two widths, and it is why they
need separate contract notes even though they are one operation.

`cmp #$80` sets `C` to the sign bit; `ror` then rotates that sign back into bit
7. The result is an arithmetic shift right, and the flags it leaves — `N` = the
preserved sign, `Z` = result is zero, `C` = the bit shifted out, `V`
untouched — are exactly what a hardware `ASR A` would leave. Neither side
refines the other because they agree. `A` is the operand, so the clobber is the
result.

The word form cannot make that claim:

- it must load the high byte to test the sign, so it **clobbers `A`**, whereas a
  hardware `ASRW zp` would preserve it under purity rule P2;
- its final `N`/`Z` come from the **low** byte, the last `ror` executed, while
  hardware would set them from the 16-bit result.

So `asrw`'s contract is "clobbers `A`; `Z` and `N` are UNDEFINED". That is the
same shape as the existing `addw16` entry, which is the file's worked example of
a contract where neither implementation refines the other. Code written against
`asrw` must not branch on the result without re-testing it.

### Cost, on this core

Cycles are from `docs/cpu-timing-v2.json`, which measures *this* core, not NMOS.
This matters: `ror zp` is 4 cycles here and 5 on NMOS, and `pseudo.txt`'s header
records that scoring against the wrong baseline is exactly what gate G4 exists
to stop.

| Form | Expansion | now (bytes/cycles) | projected hw | delta |
| --- | --- | ---: | ---: | ---: |
| `asr` | `cmp #$80` / `ror` | 3 / 4 | 1 / 2 | -2 B, -2 cy |
| `asr a, 3` | ×3 of the above | 9 / 12 | 3 / 6 | -6 B, -6 cy |
| `asrw zp` | `lda X+1` / `cmp #$80` / `ror X+1` / `ror X` | 8 / 13 | 2 / 8–10 | -6 B, -3..-5 cy |

Both projected forms satisfy gate G4 (≤ in bytes and cycles, strictly smaller in
at least one). The projection is a claim until silicon exists.

### Which gates apply

This is a source-layer slice, so the hardware gates are not all live. Stating
which is which keeps the slice from being credited with checks it never ran:

| Gate | Applies | Why |
| --- | --- | --- |
| G1 Purity | partly | `asr` is pure in the P2 sense; `asrw` clobbers `A` **as a pseudo** and would be pure as hardware. |
| G2 Encoding | no | claims no slot; `docs/opcodes.md` is generated from the decode table. |
| G3 Idiom frequency | **yes** | 9 sites, the load-bearing gate for this slice. |
| G4 Strict improvement | projected | table above; not measurable until silicon. |
| G5 Corpus reduction | modified | static instruction count falls; **bytes must not change at all**, since the expansion is byte-identical. |
| G6 Plumbing ratio | yes | `asrw` removes one `lda` from the toll count at each of its sites. |
| G7 Compatibility | **yes, strengthened** | not merely "does not grow" — the ROM digest must be *identical*, checked by `make pseudo-check` and the Celeste conformance digest. |
| G8 No cycle regression | trivially | byte-identical output cannot change timing. |

## Risks / Trade-offs

- **Two width conventions coexist.** `addw` (silicon) and `asrw` (pseudo) both
  mean 16-bit and are spelled differently. Accepted deliberately: renaming
  silicon is a larger and less reversible change, and the mnemonics in
  `rtl/cpu6502_decode.sv` should keep matching the assembler. Documented in
  `docs/inlay.md` so the split is explained rather than discovered.
- **A convention justified by one operation.** Four of seven surveyed candidates
  have zero sites. The honest framing is that the width axis is adopted
  *because it makes `asr` countable as one instruction*, and is available afterwards — not
  that the corpus is full of latent word operations.
- **`asrw`'s undefined `Z`/`N` is a real trap.** Mitigated by the contract note
  and by the harness asserting the flags the pseudo actually leaves, so a future
  hardware swap that changes them is caught rather than assumed.

## Migration Plan

1. Add the `pseudo_width` ruledef; no existing rule moves.
2. Extend `pseudo_check.py` to the width forms, including sign behaviour across
   `$00`, `$01`, `$7F`, `$80`, `$FF` and both incoming carries.
3. Migrate the 9 sites. The ROM digest must not move — for Celeste that is the
   digest gated by `tools/inlay/test_conformance.py`.
4. Register the new mnemonics in `migrate_ext.py`'s discovery regex and in the
   metrics/conformance operation whitelist **before** migrating: a pseudo-op
   the annotated parser does not recognise has its line skipped entirely, so a
   byte-neutral migration would report a false byte saving.
5. Record adoption counts so a later hardware slice can be scored.

## Open Questions

- Should `asr a, N` be bounded by the same 1..8 limit as the counted shifts,
  or lower? Beyond 8 an arithmetic shift is saturated to the sign, so counts
  above 7 are already degenerate; 1..8 is proposed for consistency rather than
  because 8 is meaningful.
- `nemo` contributes **zero** sites to every candidate in this slice. Worth
  confirming that is a property of the puzzle domain rather than of the port
  being younger, before the 9-site count is treated as stable.
