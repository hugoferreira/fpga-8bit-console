## Why

The 6502's indirect addressing is crippled in a specific way: `(zp),Y` exists,
`(zp)` does not, and there is no way to advance a pointer without the
`inc lo` / `bne skip` / `inc hi` dance. The result is that walking a pointer
costs a register (`Y`) *and* a branch, so hand-written code avoids pointers and
uses indexed absolute addressing with a bounded `X` instead.

That avoidance is visible in the corpus: only **16** `(zp),Y` uses against
**41** `ldy` and 62 `ldx`. The program is not pointer-light because its data is
flat — the sprite shadow, the tilemap and the SFX tables are all sequential
structures — it is pointer-light because pointers are expensive to move.

The other missing primitive is bulk copy. Filling the tilemap, clearing the
overlay and pushing the sprite shadow are all copy loops written by hand, each
paying loop overhead per byte.

## What Changes

Eight instructions in opcode column `$xB` high half.

| Opcode | Instruction | Bytes | Cycles | Notes |
| --- | --- | --- | --- | --- |
| `$8B` | `LDA (zp)+` | 2 | 7 | load through pointer, then advance it 16-bit |
| `$9B` | `STA (zp)+` | 2 | 7 | store through pointer, then advance it |
| `$AB` | `MOV (zp)+, #imm` | 3 | 8 | store immediate through pointer, advance |
| `$BB` | `MOV zp, (zp)+` | 3 | 9 | pointer read to variable, advance |
| `$CB` | `ADDW (zp), #imm8` | 3 | 9 | advance a pointer by a stride |
| `$DB` | `CPY (zp), (zp), #imm8` | 4 | 8 + 6/byte | block copy, count in the immediate |
| `$EB` | `CPYW (zp), (zp), zp` | 4 | 8 + 6/byte | block copy, 16-bit count from a pair |
| `$FB` | `FILL (zp), #imm, zp` | 4 | 6 + 4/byte | block fill, 16-bit count from a pair |

- **Auto-increment forms advance the full 16-bit pointer**, carrying into the
  high byte, with no branch and without touching `Y`. A pointer walk becomes a
  straight line, so `Y` is free for its actual job.
- **Block copy and fill are single instructions** whose cost is per byte rather
  than per byte plus loop overhead. They are interruptible: the instruction
  keeps its progress in the pointer and count operands, so an interrupt resumes
  rather than restarts.
- **`ADDW (zp), #imm8`** advances a pointer by a row stride — the tilemap and
  sprite-shadow walks step by a constant, not by one.

## Impact

- Affected specs: `cpu-isa`
- Affected code: `rtl/cpu6502_arlet.sv`, `rtl/cpu6502_tb.sv`,
  `src/isa/ext_pointer.asm` (new), `src/main.asm`, `docs/opcodes.md`
- Depends on: `add-isa-ergonomic-gates`, `add-custom-assembler`,
  `add-isa-core-ergonomics`, `add-isa-word-ops`
- **Gate G3 is now satisfied**, by the second corpus rather than the first.
  Breakout Hero has 19 `(zp),Y` sites; the NEMO port (`add-nemo-corpus`) has
  **44**, more than twice as many, plus a class chain whose method dispatch is an
  indirect jump through a descriptor with a base-class fallback loop, a
  first-child/next-sibling scene graph, and an event bus of {handler, context}
  pairs. See `docs/corpora.md`. The asymmetry is the point of having more than one
  corpus, and it is recorded against this slice's entry in the opcode registry.
- The **block copy and fill** instructions are still not covered by a pattern
  count and remain justified by rewriting the named copy loops — see `design.md`.
  Only the auto-increment forms are cleared by the corpus evidence.

## Measured before building — and the answer is no

Counted over both customasm corpora with the survey in this change's notes,
the idioms the eight instructions above target barely occur:

| What it would replace | breakout | celeste | total |
| --- | --- | --- | --- |
| `ptr += k` (`lda p / add #k / sta p / bcc / inc p+1`) | 3 | 2 | 5 |
| `ptr++` (`inc p / bne / inc p+1`) | 2 | 1 | 3 |
| block copy body (`lda (a),y / sta (b),y / iny`) | 0 | 1 | 1 |
| block fill with a constant | 0 | 0 | 0 |

Eleven high-byte increments exist in the two corpora **in total**, and some of
those are frame counters rather than pointers. Six unbuilt opcodes
(`$AB $BB $CB $DB $EB $FB`) would serve roughly eight sites. Against
`add-isa-word-ops` at 94 bytes for eight opcodes and `add-isa-test-and-branch`
at a projected 120, this is not close.

The 14 celeste sites that look like fill loops are not. They are sequential
field writes through a fixed pointer with a *running* `Y`
(`lda #0 / sta (pObj), y / iny / lda t3 / sta (pObj), y / iny`). Auto-increment
does not serve them: it advances the pointer, not `Y`, and the pointer is
needed afterwards. They are also exactly the sites the slice-2 migration
declined as "Y read by iny", so they are known, and neither this slice nor that
one addresses them. An instruction that advanced `Y` and left the pointer alone
would - that is a different proposal, and it should be written against these 14
sites rather than against block copies that do not exist.

**Also stale:** this table claims `$8B`/`$9B` for `LDA (zp)+`/`STA (zp)+`, but
those slots shipped in slice 2 as `LDA (zp), #d`/`STA (zp), #d` and are in
`rtl/cpu6502_decode.sv` today. Any revival of this proposal needs new slots.

**Recommendation: do not build.** Block copy and fill are the interesting half
and the corpus does not contain them; if a future corpus does, re-measure.
