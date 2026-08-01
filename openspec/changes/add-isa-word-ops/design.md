## Context

There is no 16-bit register on this CPU and this slice does not add one. Zero
page already *is* the program's variable space — 141 `.define`s in
`src/main.asm` — and roughly a third of those definitions are pair halves. The
design decision is to treat a zero-page pair as the natural 16-bit operand and
give it operations, rather than to introduce a register that everything would
then have to be moved into and out of.

## Goals / Non-Goals

- **Goal**: a 16-bit assignment, add, subtract, compare, increment and decrement
  each readable as one line naming the program's own variables.
- **Goal**: no widened ALU, no new architectural register, no change to the bus
  model.
- **Non-Goal**: 16-bit indexing, 16-bit shifts (`ASW`/`ROW`), or 16-bit
  logical ops. No corpus evidence; revisit if a rewrite demands them.
- **Non-Goal**: 24- or 32-bit values.

## Decisions

### Decision: zero page is the 16-bit register file

`ADDW ballx, #40` names the variable. There is no load, no store, no spill and
no question of which register holds the high half. The cost is that operands
must live in zero page and must be little-endian pairs — a convention this
codebase already follows (`ballx` / `ballx+1`).

Consequence worth stating plainly: this makes zero page even more precious,
which is the problem `add-isa-frame-pointer` addresses. These two slices are
complementary — word ops make zero page more valuable, frames make it
allocatable.

### Decision: word operations touch no register

`A`, `X` and `Y` are untouched by every instruction in this slice. This is the
whole reason the corpus's 16-bit code is currently smeared across its routines:
a hand-written 16-bit add has to happen where the accumulator is free, not where
the logic wants it. Removing that constraint is the ergonomic deliverable, and
it is why the G3 evidence is rewrite-based — the win shows up as *code that can
move*, not as a pattern that can be pattern-matched.

### Decision: flags describe the 16-bit result

`ADDW`/`SUBW` set `C` from bit 16, `N` from bit 15, `Z` from the whole 16-bit
result being zero, and `V` from signed 16-bit overflow. `CMPW` sets `N`, `Z`,
`C` as a 16-bit `CMP` would. `INW`/`DEW` set `N` and `Z` from the 16-bit result
and leave `C` alone, matching `INC`/`DEC`'s relationship to `ADC`.

The point is that `cmpw t_slow, #0` / `beq expired` reads exactly like the 8-bit
version. No new branch instructions are needed and none are added.

### State sequences

Budgets against the one-access-per-cycle model; each is a straight-line
extension of the existing read-modify-write sequences. Confirmed by the
testbench for gate G4.

```
MOVW zp,#imm16   T0 op | T1 zz | T2 lo | T3 hi | T4 write zz | T5 write zz+1  = 6
MOVW zp,zp       T0 op | T1 dd | T2 ss | T3 read ss | T4 write dd
                 | T5 read ss+1 | T6 write dd+1 | T7 done                     = 8
ADDW zp,#imm16   T0 op | T1 zz | T2 lo | T3 hi | T4 read zz | T5 write zz
                 | T6 read zz+1 | T7 write zz+1 | T8 flags                    = 9
CMPW zp,#imm16   as ADDW without the writes                                   = 8
INW / DEW        T0 op | T1 zz | T2 read | T3 write | T4 read+1 | T5 write+1
                 | T6/T7 carry and flags                                      = 8
```

`INW` is 8 cycles against the hand-written `inc zp` / `bne skip` / `inc zp+1`
(13 cycles when the low byte wraps, 8 when it does not) — but the hand-written
form is 8 bytes and branches, so `INW` wins on bytes always and on cycles in the
carry case. Gate G4 requires no *worse* in both and strictly better in one:
satisfied on bytes.

### Opcode claims

Column `$x3` high half. All eight slots consumed.

| Slot | Instruction | Clobbers | Flags |
| --- | --- | --- | --- |
| `$83` | `MOVW zp, #imm16` | memory only | none |
| `$93` | `MOVW zp, zp` | memory only | none |
| `$A3` | `ADDW zp, #imm16` | memory only | `N V Z C` |
| `$B3` | `ADDW zp, zp` | memory only | `N V Z C` |
| `$C3` | `SUBW zp, #imm16` | memory only | `N V Z C` |
| `$D3` | `CMPW zp, #imm16` | nothing | `N Z C` |
| `$E3` | `INW zp` | memory only | `N Z` |
| `$F3` | `DEW zp` | memory only | `N Z` |

## Rewrite-measured evidence (gate G3)

The corpus has no literal 16-bit chain to count, so G3 is satisfied by rewriting
two named routines and reporting both measurements:

- **`ball_step`** — 16-bit ball position with a fractional low byte, the most
  16-bit-dense routine in the program.
- **`update_pills`** — falling power-up pills at 0.7 px/frame, a 16-bit
  fixed-point accumulate per pill.

Each rewrite reports instruction count, byte count and cycles before and after.
The declared target is that each at least halves its instruction count. If
either fails, the slice is cut back to the instructions the rewrites actually
used.

## Risks / Trade-offs

- **G3 is weaker here than elsewhere.** Rewrite-based evidence is judgement
  compared to a pattern count, and the person doing the rewrite is motivated to
  make it look good. Mitigation: the before/after routines are both committed,
  so the comparison is reviewable, and gate G8 (frame cycles) bounds the result
  independently.
- **Nine-cycle instructions.** `ADDW` is the longest instruction in the extended
  set. It is less than half the 22 cycles it replaces, but it is also
  non-interruptible for that whole time; the IRQ latency worst case grows from 7
  to 11 cycles. The console's IRQ use must be checked against this before the
  slice lands — recorded as a task.
- **Pairs must be zero page and little-endian.** A program with a big-endian
  pair, or a pair split across `$FF`/`$00`, gets wrong answers. The wrap case
  must be specified and tested: `INW $FF` operates on `$FF` and `$00`.
- **Pressure on zero page increases.** See the note above; mitigated by
  `add-isa-frame-pointer`.

## Migration Plan

1. Land RTL and ruledef; corpus unchanged; conformance and byte-identity gates.
2. Rewrite `ball_step` and `update_pills`; record both measurements. **Gate
   check here** — if the rewrites do not halve, cut the slice back before
   touching the rest of the corpus.
3. Migrate the remaining 16-bit sites found by the `+1`-operand scan.

## Open Questions

- Does the console take interrupts during gameplay? If so, the 11-cycle worst
  case needs checking against the video timing budget before `ADDW` lands.
- Should `SUBW zp, zp` and `CMPW zp, zp` go on the prefix page, or wait for
  evidence from the rewrites? Proposed: wait.
