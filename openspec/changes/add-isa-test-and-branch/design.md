## Context

The 6502 answers questions about memory by destroying the accumulator: to ask
"is `state` equal to `ST_PLAY`?" you must load `state` into `A`. The corpus does
this 92 times. This slice makes the question askable without the load.

## Goals / Non-Goals

- **Goal**: test memory and branch, preserving all registers and flags.
- **Goal**: retire "branch out of range" as a category of programmer work.
- **Non-Goal**: single-bit `BBR`/`BBS` in the Rockwell encoding. Those slots
  (`$x7`, `$xF`) are reserved by policy, and the corpus's bit tests are
  multi-bit masks (`and #$0F`), which a mask form covers and a single-bit form
  does not.
- **Non-Goal**: comparing two memory locations. The corpus compares against
  constants 55 times and against zero page 5 times.

## Decisions

### Decision: compare-and-branch preserves flags as well as registers

`CBEQ zp, #imm, rel` performs the comparison internally and does **not** write
`N`, `Z` or `C`. This is the same reasoning as `MOV` in slice 3: an instruction
that leaves no trace can be inserted anywhere, including between an existing
comparison and its branch. It also removes the most common reading error in
6502 — losing track of which comparison the flags currently reflect.

The cost is that `CBxx` cannot be chained the way `cmp` plus multiple branches
can. Where a program branches twice on one comparison, `cmp` remains available
and is the better tool.

### Decision: four comparison forms, not six

`CBEQ`, `CBNE`, `CBLT`, `CBGE` cover the corpus (`beq`/`bne`/`bcc`/`bcs` after
`cmp`). Signed forms and `>`/`<=` are omitted: `>` is `CBGE` with `k+1`, and the
corpus has no signed comparisons after `cmp`. Two saved slots go to `BSR`/`BRA`.

### Decision: mask test, not bit test

`TBZ zp, #mask, rel` branches when `(zp & mask) == 0`. The corpus's uses are
`and #$0F` (blink phase) and `and #$10` (blink half) — a single-bit instruction
would cover the second and not the first.

### Decision: long branches live on the prefix page and are never hand-written

The `$02` prefix opens a second page; the long form of a branch is
`$02, <same low nibble encoding>, lo, hi` — 4 bytes, giving a full 16-bit
displacement. The programmer writes `beq label` in every case and customasm's
fewest-bits rule selects:

```
#ruledef branch {
    beq {t: u16} => { r = t - $ - 2,
                      assert(r >= -0x80), assert(r <= 0x7f),
                      0xf0 @ r[7:0] }
    beq {t: u16} => { r = t - $ - 4, 0x02 @ 0xf0 @ r[7:0] @ r[15:8] }
}
```

The short rule asserts its range and the long rule always matches, so the
assembler picks the short form when it fits. The two rules differ in size, which
avoids customasm's ambiguity error.

**Convergence risk**: the displacement depends on the size of instructions
between here and the target, which depends on their displacements. customasm
iterates to a fixed point, but a program can be constructed where the choice
oscillates. The mitigation is that the short-form assertion is monotone — a
branch that fits at pass *n* with a smaller intervening region still fits at
pass *n+1* — so shrinking converges. A convergence failure is a hard build
error, never a silently wrong branch.

### Decision: `BRA` takes an extension slot rather than `$80`

`$80` is the canonical 65C02 `BRA` and is reserved by the allocation policy.
Taking `$7B` keeps this slice independent of any decision to adopt the 65C02
set. If that adoption happens, `$80` becomes canonical, `$7B` is retired to the
free list, and the assembler ruledef changes in one place.

### State sequences

Budgets against Arlet's one-access-per-cycle model, confirmed by the testbench
for gate G4.

```
CBEQ zp,#imm,rel   T0 fetch op | T1 fetch zz | T2 fetch ii | T3 read [zz],
                   compare | T4 fetch rel | T5 add to PC if taken
                   = 5 not taken, 6 taken, 7 on page cross
TBZ zp,#mask,rel   identical, with AND instead of compare
BSR rel            T0 | T1 fetch rel | T2 push PCH | T3 push PCL | T4/T5 add
                   = 6, reusing the JSR states
BRA rel            = 3, the existing taken-branch path with the condition
                   forced true
long forms         prefix fetch + 1 cycle, + 1 for the second displacement byte
```

`CBxx`/`TBxx` need a comparison that does not commit to the flag register — an
extra ALU result mux, not an extra ALU.

### Opcode claims

| Slot | Instruction | Clobbers | Flags |
| --- | --- | --- | --- |
| `$0B` | `CBEQ zp, #imm, rel` | nothing | none |
| `$1B` | `CBNE zp, #imm, rel` | nothing | none |
| `$2B` | `CBLT zp, #imm, rel` | nothing | none |
| `$3B` | `CBGE zp, #imm, rel` | nothing | none |
| `$4B` | `TBZ zp, #mask, rel` | nothing | none |
| `$5B` | `TBNZ zp, #mask, rel` | nothing | none |
| `$6B` | `BSR rel` | stack | none |
| `$7B` | `BRA rel` | nothing | none |

## Risks / Trade-offs

- **`BRA`'s G3 evidence is unverified.** There are 44 `jmp` sites, but only
  those whose target is within ±127 bytes convert. The count must be measured
  during implementation; if it falls below 8, `BRA` is cut and `$7B` returns to
  the free list. This is recorded as an explicit task.
- **Four-byte instructions in a 6502.** `CBxx` is the longest instruction in the
  extended set. It is still shorter than the six bytes it replaces, but it makes
  hand-computed branch displacements harder — mitigated by the assembler owning
  displacement selection entirely.
- **Flag-preserving compare is a semantic trap in reverse**: a reader used to
  `cmp` may expect `CBNE` to leave usable flags. Mitigated by the mnemonic being
  visibly different and the registry documenting "flags: none".
- **Prefix-page decode adds a cycle to every long branch.** Accepted: long
  branches are rare by construction, and the alternative (16-bit displacements
  in the primary encoding) costs a byte on every branch in the program.

## Migration Plan

1. Land the RTL and ruledefs; corpus unchanged; conformance and byte-identity
   gates pass.
2. Enable the long-branch rules and rebuild — no source change should be needed,
   and the binary should be byte-identical because every existing branch fits.
3. Migrate the 92 test sites in three passes by idiom.
4. Measure `jmp`-within-range before migrating to `BRA`.

## Open Questions

- Should `CBxx` gain an `abs` form for MMIO polling? The corpus polls
  `SPR_FRAME` in the main loop, which is 1 site. Deferred.
- Is a `CBxx zp, zp, rel` form worth a prefix-page slot for the 5 zero-page
  comparisons? Below the G3 threshold; deferred.
