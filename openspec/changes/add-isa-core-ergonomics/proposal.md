## Why

32.8% of `src/main.asm` is plumbing (see `add-isa-ergonomic-gates`). This slice
attacks the two largest components — the accumulator toll booth and the
carry-flag ceremony — with the smallest instruction set that the corpus
evidence actually supports.

Measured occurrence counts, which are what selected these instructions:

| Idiom | Sites | Replacement |
| --- | --- | --- |
| `lda #k` / `sta zp` | 100 | `MOV zp, #imm` |
| `lda #k` / `sta abs` | 55 | `MOV abs, #imm` |
| `lda table,X` / `sta zp` | 24 | `MOV zp, abs,X` |
| `clc` / `adc` | 70 | `ADD` |
| `sec` / `sbc` | 17 | `SUB` |

Two instructions from the original sketch were **cut by the gates**, which is
the gates doing their job:

- **`MOV zp, zp`** — the headline instruction of the first draft. The corpus has
  exactly **4** zero-page-to-zero-page moves. It fails G3 (≥8 sites). The
  memory-to-memory move that actually earns a slot is the *indexed table read*
  form, `lda table,X` / `sta var`, at 24 sites.
- **`DBNZ zp, rel`** — 5 candidate sites; this program counts upward. Rejected
  in `add-isa-ergonomic-gates`.

## What Changes

Eight instructions in opcode column `$x3` low half, all satisfying purity rules
P1–P3.

| Opcode | Instruction | Bytes | Cycles | Replaces | Was |
| --- | --- | --- | --- | --- | --- |
| `$03` | `MOV zp, #imm` | 3 | 4 | `lda #k` / `sta zp` | 4 B / 5 c |
| `$13` | `MOV abs, #imm` | 4 | 5 | `lda #k` / `sta abs` | 5 B / 6 c |
| `$23` | `MOV zp, abs,X` | 4 | 6 | `lda abs,X` / `sta zp` | 5 B / 7 c |
| `$33` | `ADD #imm` | 2 | 2 | `clc` / `adc #k` | 3 B / 4 c |
| `$43` | `ADD zp` | 2 | 3 | `clc` / `adc zp` | 3 B / 5 c |
| `$53` | `SUB #imm` | 2 | 2 | `sec` / `sbc #k` | 3 B / 4 c |
| `$63` | `SUB zp` | 2 | 3 | `sec` / `sbc zp` | 3 B / 5 c |
| `$73` | `TRAP #imm` | 2 | 2 | — (diagnostic) | — |

- **`MOV` moves memory without touching `A`, `X`, `Y` or any flag.** This is the
  point of the instruction, not a side benefit: it means adding a store to a
  routine never costs you a live value or a pending comparison.
- **`ADD`/`SUB` have no carry-in and ignore the decimal flag.** They are total:
  no `clc`, no `sec`, no `cld`. `ADC`/`SBC` remain for multi-byte chains, where
  the carry is the programmer's actual intent rather than an obligation.
- **`TRAP #imm`** raises a diagnostic trap the simulator interprets — dump
  registers, assert, log — and which is inert on hardware. It is **exempt from
  gate G3 by declaration**: it replaces no idiom, it exists so that debugging a
  hand-written game does not require a separate build. The exemption is recorded
  in the opcode registry.

Also in scope:

- `src/isa/ext_core.asm` — the customasm `#ruledef` for these eight.
- Migration of `src/main.asm` to use them, and the resulting metrics run.
- `docs/opcodes.md` updated with the eight claims and the two rejections.

## Impact

- Affected specs: `cpu-isa`
- Affected code: `rtl/cpu6502_arlet.sv` (decode and new states),
  `rtl/cpu6502_tb.sv` (per-instruction tests), `src/isa/ext_core.asm` (new),
  `src/main.asm` (migration), `sim/console.cpp` (`TRAP` handling),
  `docs/opcodes.md`
- Depends on: `add-isa-ergonomic-gates`, `add-custom-assembler`
- Declared G5 target: **≥ 230 instructions removed** (~12% of the corpus);
  projected 249. Declared G6 target: plumbing ratio **≤ 15%** (projected 12.1%).
