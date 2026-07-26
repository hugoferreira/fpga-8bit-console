## Why

After stores and arithmetic, the next largest plumbing cluster in
`src/main.asm` is *testing a variable in order to branch on it*. The value is
loaded into `A` purely to be inspected, then thrown away:

| Idiom | Sites | What it means |
| --- | --- | --- |
| `lda v` / `cmp #k` / branch | 30 | compare a variable to a constant |
| `lda v` / branch | 46 | test a variable for zero |
| `lda v` / `and #mask` / branch | 16 | test bits in a flag byte |
| **Total** | **92** | |

Every one of these destroys `A` to answer a yes/no question. On top of that,
`ldy` appears 41 times and `cmp` operands are 55 immediate against 5 zero page —
this program compares against constants and indexes with `X`.

There is a second, unmeasurable cost in this area: **branch range anxiety**.
`bne` reaches ±127 bytes, so growing a routine can turn a working branch into an
assembler error, and the fix is the `beq`-over-`jmp` inversion dance that makes
the source read backwards from the intent.

## What Changes

Eight instructions in opcode column `$xB` low half, plus one assembler-only
change.

| Opcode | Instruction | Bytes | Cycles | Replaces | Was |
| --- | --- | --- | --- | --- | --- |
| `$0B` | `CBEQ zp, #imm, rel` | 4 | 5/6 | `lda v` / `cmp #k` / `beq` | 6 B / 8 c |
| `$1B` | `CBNE zp, #imm, rel` | 4 | 5/6 | `lda v` / `cmp #k` / `bne` | 6 B / 8 c |
| `$2B` | `CBLT zp, #imm, rel` | 4 | 5/6 | `lda v` / `cmp #k` / `bcc` | 6 B / 8 c |
| `$3B` | `CBGE zp, #imm, rel` | 4 | 5/6 | `lda v` / `cmp #k` / `bcs` | 6 B / 8 c |
| `$4B` | `TBZ zp, #mask, rel` | 4 | 5/6 | `lda v` / `and #m` / `beq` | 6 B / 8 c |
| `$5B` | `TBNZ zp, #mask, rel` | 4 | 5/6 | `lda v` / `and #m` / `bne` | 6 B / 8 c |
| `$6B` | `BSR rel` | 2 | 6 | `jsr abs` | 3 B / 6 c |
| `$7B` | `BRA rel` | 2 | 3 | `jmp abs` | 3 B / 3 c |

- **`CBxx` compares a memory location against a constant and branches**, without
  loading anything. `A`, `X`, `Y` and all flags are preserved — testing state no
  longer costs you the accumulator.
- **`TBZ`/`TBNZ` test a bit mask and branch**, the same way, for flag bytes.
  A mask is more useful here than a single-bit form: the corpus's `and #$0F` /
  `and #$10` blink tests are multi-bit.
- **`BSR`** is a relative subroutine call — 1 byte smaller than `jsr`, and
  position-independent.
- **`BRA`** is the 65C02 relative jump. It takes an extension slot rather than
  the reserved `$80` because slice ordering should not depend on adopting the
  whole 65C02; if the 65C02 set is adopted later, `$80` becomes the canonical
  encoding and `$7B` is retired.
- **Long branches**: every conditional branch and `BSR`/`BRA` gains a 16-bit
  displacement form on the `$02` prefix page (`$02 xx` + 2 displacement bytes).
  Programmers never write these — customasm selects the shortest encoding that
  reaches, so `beq far_label` simply works. This is the ergonomic deliverable of
  the slice even though it consumes no primary opcode space.

The `CBxx` and `TBxx` families take an 8-bit displacement in their primary
encoding and rely on the prefix page for the long form, consistent with the
above.

## Impact

- Affected specs: `cpu-isa`
- Affected code: `rtl/cpu6502_arlet.sv`, `rtl/cpu6502_tb.sv`,
  `src/isa/ext_branch.asm` (new), `src/isa/nmos6502.asm` (long-branch rules),
  `src/main.asm`, `docs/opcodes.md`
- Depends on: `add-isa-ergonomic-gates`, `add-custom-assembler`,
  `add-isa-core-ergonomics`
- Declared G5 target: **≥ 150 instructions removed**; projected 184 from the 92
  test sites alone. Declared G6 target: plumbing ratio non-increasing.

## Measured before building

`src/isa/pseudo.asm` implements this slice as customasm pseudo-instructions
that expand to the sequences they replace, and both corpora have been migrated
onto them. The binaries are bit-identical (`make pseudo-check`), so this costs
nothing and can be reverted by deleting one include. What it buys is that the
slice can now be scored against real adoption instead of an idiom count.

    make pseudo-report

| | breakout | celeste |
| --- | --- | --- |
| `CBEQ`/`CBNE`/`CBLT`/`CBGE`/`TBZ`/`TBNZ` sites | 35 | 25 |
| bytes saved if built | 70 | 50 |
| zero-test sites (`lda v` / branch) | 29 | 27 |
| bytes saved by those | **0** | **0** |

**120 bytes across both corpora, for eight opcodes.** For comparison,
`add-isa-word-ops` delivered 94 bytes for eight opcodes. This slice is worth
slightly more than that one and should be sized the same way.

Three corrections to the numbers above, all of which the pseudo-op layer
surfaced and none of which were visible from an idiom count:

1. **The cycle baseline was wrong.** The table above costs the replaced
   sequence at 8 cycles, which is NMOS. This core's branches are a flat 2
   cycles - no taken penalty, no page-cross penalty - so `lda zp / cmp #k /
   beq` is **7**. The saving is 1-2 cycles per execution, not 2-3. Gate G4
   scores against this core, so the slice must be re-costed against 7.

2. **The zero test should be dropped from the justification.** `lda v / beq t`
   is already 4 bytes and 5 cycles; the proposed `CBEQ zp, #0, rel` is 4 bytes
   and 5-6. It saves no space and may cost a cycle. It buys the accumulator and
   nothing else. It is 56 of the 116 sites, so counting it makes the slice look
   roughly twice as large as it is. `pseudo.asm` keeps `bzero`/`bnzero` in a
   separate ruledef and `pseudo.txt` carries their real cost, so the projection
   cannot silently credit them.

3. **The site count was optimistic.** "92 sites in `src/main.asm`" counts
   idioms; 35 of them have a zero-page source and a plain label target, which
   is what the proposed encoding can actually express. Six are declined for an
   absolute source alone.

None of this argues against the slice - 120 bytes and a preserved accumulator
across 60 sites is a good return for one opcode column. It argues that the
sizing should come from adoption rather than from grep, which is the point of
building the pseudo-op layer first.
