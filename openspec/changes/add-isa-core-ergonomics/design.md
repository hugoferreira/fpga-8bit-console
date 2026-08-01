## Context

Arlet's core executes one memory access per cycle, driven by a state machine
with `casex(IR)` decode. Every instruction here is expressible as a short state
sequence over the existing 8-bit datapath — no ALU widening, no new bus
behaviour, no extra ports.

## Goals / Non-Goals

- **Goal**: remove the accumulator from stores it has no business being in, and
  remove the carry flag from additions that never wanted it.
- **Non-Goal**: general memory-to-memory operations. The corpus does not justify
  them (4 `zp`→`zp` sites) and they would consume the whole extension column.
- **Non-Goal**: indexed *destination* forms (`MOV abs,X, #imm`, 14 sites). Above
  the G3 threshold only in aggregate across two modes; revisit after slice 3's
  migration re-measures the corpus.

## Decisions

### Decision: operand order is `MOV dst, src`, and byte order matches

`mov ballx, #0` reads as an assignment, left to right. The encoding places the
destination address first so that source order, byte order and disassembly order
all agree:

```
$03 zz ii        mov zz, #ii
$13 lo hi ii     mov (hi:lo), #ii
$23 zz lo hi     mov zz, (hi:lo),X
```

### Decision: `MOV` sets no flags

`MOV` modifies memory and nothing else. This is what makes it composable — you
can insert a store between a compare and its branch. It is also the one
behavioural difference from the `lda`/`sta` pair it replaces, which sets `N` and
`Z` from the loaded value.

The migration risk is therefore real but measured: **1** of the 230 `lda`/`sta`
pairs in the corpus is immediately followed by a branch. `tools/isa_metrics.py`
gains a check that flags any `lda`/`sta` pair whose `N`/`Z` result is consumed
before being overwritten, so the migration cannot silently break one.

### Decision: `ADD`/`SUB` are binary-only and carry-free

- Carry-in is forced (0 for `ADD`, 1 for `SUB`), so there is no precondition.
- The decimal flag is ignored: `ADD` is always binary. Depending on `D` would be
  a precondition and would violate P1. `ADC`/`SBC` keep their existing
  `D`-dependent behaviour, so the compatibility contract is untouched.
- Carry-*out*, `N`, `V` and `Z` are set exactly as `ADC`/`SBC` set them, so
  `ADD` still starts a multi-byte chain that `ADC` continues:

  ```
  add  dx          ; low byte, no clc needed
  lda  y+1
  adc  dy+1        ; high byte, carry from the add
  ```

  This is the ergonomic shape: the common case is short and safe, the chained
  case is explicit.

### Decision: `TRAP #imm` semantics

`TRAP #imm` asserts a `trap` output alongside the immediate for one cycle and
continues. On hardware nothing observes it and it costs 2 cycles. In the
simulator it is dispatched by code:

| Code | Meaning |
| --- | --- |
| `$00` | breakpoint — halt and enter the debugger |
| `$01` | dump `A`, `X`, `Y`, `P`, `S`, `PC` with the enclosing label from `build/main.sym` |
| `$02` | assertion failed — print the source location and stop |
| `$10`–`$7F` | user log points, printed with their code |
| `$80`–`$FF` | reserved |

`TRAP` is deliberately not a `BRK` variant: `BRK` pushes state and vectors,
which costs 7 cycles and perturbs the stack — exactly the wrong properties for
something you want to leave in a hot loop while debugging.

### State sequences

Sketched against Arlet's existing states; cycle counts are budgets, confirmed by
the testbench for gate G4.

```
MOV zp,#imm    T0 fetch op | T1 fetch zz -> ADL | T2 fetch ii -> DO | T3 write   = 4
MOV abs,#imm   T0 | T1 fetch lo | T2 fetch hi | T3 fetch ii -> DO | T4 write     = 5
MOV zp,abs,X   T0 | T1 fetch zz | T2 fetch lo | T3 fetch hi, ADD X | T4 read
               | T5 write (+1 on page cross)                                     = 6
ADD #imm       reuses the ADC immediate path with carry-in forced to 0           = 2
ADD zp         reuses the ADC zero-page path with carry-in forced to 0           = 3
TRAP #imm      T0 | T1 fetch imm, assert trap                                    = 2
```

`ADD`/`SUB` need no new states at all — they are the existing `ADC`/`SBC` paths
with the carry-in mux forced and the decimal adjust disabled. `MOV` needs one
new register (a held destination address) and four to six states.

### Opcode claims

Column `$x3` low half, per the allocation policy. All eight slots are consumed;
slice 4 onward uses column `$xB`.

| Slot | Instruction | Clobbers | Flags |
| --- | --- | --- | --- |
| `$03` | `MOV zp, #imm` | memory only | none |
| `$13` | `MOV abs, #imm` | memory only | none |
| `$23` | `MOV zp, abs,X` | memory only | none |
| `$33` | `ADD #imm` | `A` | `N V Z C` |
| `$43` | `ADD zp` | `A` | `N V Z C` |
| `$53` | `SUB #imm` | `A` | `N V Z C` |
| `$63` | `SUB zp` | `A` | `N V Z C` |
| `$73` | `TRAP #imm` | nothing | none |

## Risks / Trade-offs

- **Flag-behaviour change on migration.** Covered above; 1 affected site, and a
  detector in the metrics tool.
- **`MOV zp, abs,X` page-cross timing.** The extra cycle on a page cross must
  match the existing indexed-read behaviour or the cycle-accurate tests will
  diverge. Handled by reusing the existing indexed address-generation states.
- **Column `$x3` is fully consumed.** Slice 3 leaves no headroom in its column;
  any follow-up (indexed destinations, `MOV zp, abs,Y`) goes to the `$02` prefix
  page and pays a byte and a cycle. Accepted: those forms are below the G3
  threshold today.
- **`ADD` ignoring `D` is a silent difference** for anyone porting 6502 code
  that assumes decimal mode. Mitigation: `ADC`/`SBC` are unchanged, and the
  behaviour is stated in the opcode registry.
- **`TRAP` left in shipped code** costs 2 cycles per site. Mitigation: the
  assembler ruledef for `TRAP` is in a file that a release build can exclude,
  turning any remaining use into a build error rather than dead cycles.

## Migration Plan

1. Land the RTL and the ruledef; corpus unchanged. Gate G7 (byte identity of the
   unmigrated corpus, conformance suite) must pass here.
2. Migrate mechanically in three passes — immediate-to-zp, immediate-to-abs,
   indexed-to-zp — running `make metrics` after each.
3. Migrate `clc`/`adc` and `sec`/`sbc` pairs, skipping any flagged by the
   flag-consumption detector.
4. Final `make metrics` run against the declared G5/G6 targets.

Rollback is per-pass: each is an independent commit and the previous binary
remains buildable.

## Open Questions

- Should `MOV zp, abs,X` have a `,Y` sibling? The corpus is `X`-dominated;
  deferred until post-migration re-measurement.
- Should `SUB` set carry with 6502 borrow polarity (`C=1` means no borrow, as
  `SBC` does) or the inverse? Proposed: keep `SBC` polarity, because mixing
  polarities between `SUB` and `SBC` in one chain would be a new trap for the
  reader — consistency beats intuitiveness here.
