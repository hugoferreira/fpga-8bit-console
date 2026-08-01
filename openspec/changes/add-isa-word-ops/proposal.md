## Why

The console's game logic is full of 16-bit values — ball position with a
fractional byte, pointers into the sprite shadow, frame timers, the score — and
the 6502 has no 16-bit anything. `src/main.asm` contains **122** operands
referencing the high half of a pair (`ballx+1`, `t_slow+1`, `sd_t+1`).

The interesting part is what is *not* there: **zero** textbook 16-bit add chains
(`clc`/`lda`/`adc`/`sta`/`lda`/`adc`/`sta`). The 16-bit work has been
hand-scheduled into whatever registers happened to be free, spread across the
routine, interleaved with unrelated code. That is precisely the symptom this
slice targets — a 16-bit add is not *hard*, it is a seven-instruction
bookkeeping exercise that the programmer breaks up and hides, and which then
cannot be read as a single thought.

Because the idiom is diffuse rather than literal, this slice qualifies under the
**rewrite-measured evidence** clause of gate G3: `ball_step` and `update_pills`
are rewritten both ways and both measurements reported.

## What Changes

Zero page becomes the 16-bit register file. Eight instructions in opcode column
`$x3` high half operate on zero-page **pairs** (`zp` = low byte, `zp+1` = high
byte) with no 16-bit register and no widened ALU — each is a multi-cycle
sequence over the existing 8-bit datapath.

| Opcode | Instruction | Bytes | Cycles | Replaces | Was |
| --- | --- | --- | --- | --- | --- |
| `$83` | `MOVW zp, #imm16` | 4 | 6 | 4 instructions | 8 B / 10 c |
| `$93` | `MOVW zp, zp` | 3 | 8 | 4 instructions | 8 B / 12 c |
| `$A3` | `ADDW zp, #imm16` | 4 | 9 | 7 instructions | 15 B / 22 c |
| `$B3` | `ADDW zp, zp` | 3 | 11 | 7 instructions | 15 B / 24 c |
| `$C3` | `SUBW zp, #imm16` | 4 | 9 | 7 instructions | 15 B / 22 c |
| `$D3` | `CMPW zp, #imm16` | 4 | 8 | 6 instructions | 12 B / 16 c |
| `$E3` | `INW zp` | 2 | 8 | 4 instructions | 8 B / 13 c |
| `$F3` | `DEW zp` | 2 | 8 | 4 instructions | 8 B / 13 c |

- **None of these touch `A`, `X` or `Y`.** A 16-bit update in the middle of a
  routine no longer costs the accumulator, which is why the corpus's 16-bit code
  is currently spread out instead of written where it belongs.
- **`ADDW`/`SUBW` carry internally and require no `clc`/`sec`.** Their carry-out
  and `N`/`Z`/`V` reflect the 16-bit result, so they compose into 24- and 32-bit
  chains with `ADC` if ever needed.
- **`CMPW`** sets `N`, `Z`, `C` from the 16-bit comparison, so the existing
  `beq`/`bne`/`bcc`/`bcs` work on 16-bit quantities unchanged.
- **`INW`/`DEW`** are the 16-bit counter primitives — the corpus's frame timers
  (`t_slow`, `t_expand`, `sd_t`) are all 16-bit down-counters written by hand.

`SUBW zp, zp` and a 16-bit `CMPW zp, zp` do not fit the eight-slot column and go
to the `$02` prefix page if measurement justifies them.

## Impact

- Affected specs: `cpu-isa`
- Affected code: `rtl/cpu6502_arlet.sv`, `rtl/cpu6502_tb.sv`,
  `src/isa/ext_word.asm` (new), `src/main.asm`, `docs/opcodes.md`
- Depends on: `add-isa-ergonomic-gates`, `add-custom-assembler`,
  `add-isa-core-ergonomics`
- Declared G5 target: **≥ 120 instructions removed**, and the two rewritten
  routines each at least halve their instruction count. Declared G6 target:
  plumbing ratio non-increasing.
