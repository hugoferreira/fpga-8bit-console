## Context

This is the first slice whose evidence is mostly *counterfactual*: the corpus
does not use pointers much, and the claim is that it does not use them because
they are expensive. That is a weaker argument than a pattern count, and the
design has to be honest about it.

## Goals / Non-Goals

- **Goal**: advancing a pointer costs no register and no branch.
- **Goal**: bulk copy and fill cost per byte, not per byte plus loop.
- **Non-Goal**: the 65C02 `(zp)` addressing mode across the whole instruction
  set. Those opcodes are reserved by policy for a possible 65C02 adoption; this
  slice adds pointer *movement*, not a full mode.
- **Non-Goal**: hardware DMA. Block copy is a CPU instruction that holds the bus
  and is interruptible; it is not a coprocessor. A DMA engine belongs with the
  PPU, not the ISA.

## Decisions

### Decision: auto-increment advances 16 bits, always

`LDA (zp)+` loads through the pair and then increments the whole pair, carrying
into the high byte. No branch, no `Y`, no special case at a page boundary. That
last part is the ergonomic content — the `inc lo` / `bne` / `inc hi` idiom is
where hand-written pointer walks go wrong, because the branch is easy to omit
when the buffer "never crosses a page".

The pointer is updated **after** the access, so `(zp)+` following the C
convention reads as "use it, then advance".

### Decision: block operations are interruptible and resumable

`CPY` holds the bus for 6 cycles per byte. Copying a 512-byte tilemap would be
3072 cycles of blocked interrupts, which the video timing cannot tolerate.

The instruction therefore keeps its state in its operands: source pointer,
destination pointer and count are updated in memory as it progresses. On an
interrupt, the program counter is backed up to the instruction itself, so `RTI`
re-enters it and it resumes where it left off. This is the HuC6280 and Z80 `LDIR`
approach and it is the only design that is both a single instruction and
interrupt-safe.

Consequence: the operands are modified by the instruction. `CPY` leaves the
pointers past the end of their regions and the count at zero. This must be
documented loudly, because it is the one place in the extended ISA where an
instruction rewrites its own arguments.

### Decision: separate 8-bit and 16-bit count forms

`CPY` with an immediate count covers copies up to 255 bytes in 4 bytes of
encoding. `CPYW` takes the count from a zero-page pair for the larger cases and
for computed lengths. Splitting them avoids paying two bytes of encoding for
every small copy.

### Decision: `FILL` before `CPY` in the migration order

Clearing the overlay and initialising the tilemap are fills, they are the
simplest to verify, and they exercise the interruptible-resume machinery with
only one pointer to reason about.

### Opcode claims

Column `$xB` high half. All eight slots consumed.

| Slot | Instruction | Clobbers | Flags |
| --- | --- | --- | --- |
| `$8B` | `LDA (zp)+` | `A`, the pointer | `N Z` |
| `$9B` | `STA (zp)+` | the pointer | none |
| `$AB` | `MOV (zp)+, #imm` | memory, the pointer | none |
| `$BB` | `MOV zp, (zp)+` | memory, the pointer | none |
| `$CB` | `ADDW (zp), #imm8` | the pointer | `N Z C` |
| `$DB` | `CPY (zp), (zp), #imm` | both pointers, memory | none |
| `$EB` | `CPYW (zp), (zp), zp` | both pointers, count, memory | none |
| `$FB` | `FILL (zp), #imm, zp` | the pointer, count, memory | none |

## Evidence and the G3 problem

| Instruction group | Corpus sites | G3 status |
| --- | --- | --- |
| Auto-increment load/store | 16 `(zp),Y` uses | passes |
| `ADDW (zp), #imm8` | to be measured | unknown |
| Block copy / fill | hand-written loops, count unknown | **rewrite-measured** |

This slice may not proceed on the auto-increment evidence alone. Before the
block instructions are implemented, the following named routines are rewritten
and measured: the overlay clear (`msg_clear`), the level build (`build_level`)
and the sprite shadow update. If the block instructions do not remove at least
half the instructions in those routines, they are cut and their slots returned.

There is also a **corpus-shape risk** specific to this slice: the argument is
that the program avoids pointers because they are expensive, so the fix will
change how the program is written. That is a hypothesis, and the honest test is
to write one new routine — not to migrate an old one — that uses pointers
naturally, and see whether it is shorter and clearer than the indexed version a
6502 programmer would otherwise reach for.

## Risks / Trade-offs

- **Self-modifying operands.** `CPY` updates its pointers and count in memory.
  This is unusual, it is required for interruptibility, and it will surprise
  someone. Mitigated by documentation and by the mnemonic taking its operands by
  pointer rather than by value.
- **Interrupt-resume correctness is the hard part of this slice.** The PC
  backup, the partial-progress state and the `RTI` re-entry must be exactly
  right or a copy silently corrupts memory under interrupt load. This needs a
  dedicated test that fires an interrupt at every cycle offset within a copy.
- **Bus occupancy.** Even interruptible, a block copy holds the bus for its
  duration between interrupt checks. The per-byte cost must be checked against
  video and audio DMA contention.
- **The counterfactual premise may be wrong.** Perhaps this program is flat
  because its data is flat. The new-routine test above is the check; if it
  fails, the slice reduces to the auto-increment forms.

## Migration Plan

1. Auto-increment forms first: land, migrate the 16 `(zp),Y` sites, measure.
2. `FILL`, with the interrupt-resume test suite.
3. `CPY`/`CPYW` only after `FILL`'s resume machinery is proven.
4. The counterfactual test: write one new routine pointer-first and compare.

## Open Questions

- Should `LDA (zp)+` have `STA`/`LDX`/`LDY` siblings, or is `A` enough? Proposed:
  `A` only until measured.
- Does the PPU already provide a shadow-update path that makes `CPY` redundant
  for the largest copy in the program? Must be checked before implementing.
