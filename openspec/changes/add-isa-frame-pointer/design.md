## Context

Every other slice in this programme is a local optimisation with a measurable
before and after. This one is a change of programming model, and it has to be
treated differently: it cannot be justified by pattern-matching the existing
corpus, because the corpus is written the way it is *because* the feature is
absent.

## Goals / Non-Goals

- **Goal**: a subroutine can declare local storage without consulting a
  program-wide allocation map.
- **Goal**: the failure mode of over-allocating is detectable, not silent.
- **Non-Goal**: a C-compatible calling convention. `cc65` has its own software
  stack and this does not need to interoperate with it.
- **Non-Goal**: parameter passing. Arguments continue to go in `A`, `X`, `Y` or
  globals. Adding a calling convention on top of a frame pointer is a separate
  question and should be answered after frames have been lived with.
- **Non-Goal**: a 16-bit stack pointer or moving the stack out of page 1.

## Decisions

### Decision: frames are in zero page, not on the hardware stack

The obvious design is stack-relative addressing off `S`, as the 65CE02 does.
Rejected: the hardware stack is 256 bytes in page 1, page 1 access is no faster
than zero page, and the 6502 cannot address page 1 with a short operand — every
access would be a 3-byte absolute. Putting frames in zero page keeps local
access at 2 bytes plus the prefix.

The cost is that zero page must be shared between the existing globals and the
frame region. The frame allocator starts at the top of zero page and grows
downward; globals are allocated upward from `$00` as they are today.

### Decision: frame overflow is detectable

The allocator's low-water mark is compared against a configurable floor. When
`ENTER` would push a frame below the floor, the CPU raises the `TRAP` signal
with a reserved code. On hardware this is inert, in the simulator it stops with
a message naming the routine. This is what "detectable rather than silent" buys
and it is the reason frames are worth having at all in a machine this small —
the current failure mode, two routines quietly sharing a scratch byte, is the
worst bug class in the codebase.

### Decision: frame addressing is prefix-page only

`f+n` costs a prefix byte and a cycle over `zp`. That is deliberate:

- The primary opcode columns are already spent, and this slice should not
  displace instructions with hard evidence behind them.
- Locals *should* be slightly more expensive than globals here. A programmer who
  puts a hot inner-loop variable in a frame and notices the cost is getting
  correct feedback.

### Decision: interrupts save and restore `F`

`F` is pushed on interrupt entry and pulled by `RTI`, alongside `P`. Without
this, a handler that uses frames corrupts the interrupted routine's locals, and
the resulting bug would be untraceable. The cost is two cycles on interrupt
entry and exit.

This is a **change to `RTI`'s behaviour**, and therefore the one place in the
whole programme that touches the NMOS compatibility contract. It is handled by
making the save conditional on a mode bit that is clear at reset: with frames
disabled, interrupt entry and `RTI` are cycle-identical to today. Gate G7 tests
both settings.

### Decision: `ENTER`/`LEAVE` rather than manual `F` manipulation

```
sub:  enter #4          ; 4 bytes of locals, old F pushed
      mov  f+0, #0
      ...
      leave
      rts
```

Exposing `F` as a general register that routines adjust by hand would recreate
the bookkeeping problem one level up. `ENTER`/`LEAVE` are the only supported way
to move it, so every frame is balanced by construction and the simulator can
walk the chain.

## The gate for this slice

There is no pattern to count. The gate is:

1. **Three routines are rewritten** to use frames: one leaf routine with
   temporaries (`pad_zone`), one mid-level routine (`ball_step`), and one that
   currently shares scratch bytes with a caller (`update_pills` / `swap_ball2`).
2. **The global map shrinks.** The declared target is that at least **20** of
   the 141 `.define`s become frame locals and disappear from the global map.
   This is the metric that actually matters — it measures namespace pressure,
   not instruction count.
3. **G5 is inverted for this slice.** Frames will *increase* instruction count
   and bytes slightly, because `ENTER`/`LEAVE` are real instructions and frame
   access costs a prefix. The declared budget is **no more than 2% growth** in
   instructions and bytes, and G8 (frame-work cycles) still applies unchanged.
   A slice that makes the program measurably slower is not shipped.
4. **A recursion test**: implement one genuinely recursive routine that is
   impossible today, to demonstrate the model works rather than just fits.

If the rewrites do not free 20 globals, the honest conclusion is that this
program is small enough not to need frames, and the slice is abandoned. That is
an acceptable outcome and the reason it is sequenced last.

## Risks / Trade-offs

- **This is the only slice that touches interrupt behaviour**, and therefore the
  only one that can break compatibility. Mitigated by the reset-clear mode bit
  and by testing G7 in both settings.
- **Zero page is 256 bytes and already holds 141 globals.** The frame region may
  be too small to be useful. This is measured in step 2 of the gate before any
  broad migration.
- **The premise may be wrong at this scale.** A 2600-line program may simply not
  need locals. The gate is designed to be able to say so.
- **`F` is another piece of machine state to track**, which cuts against the
  programme's own first principle. The counter-argument is that `F` replaces
  tracking 141 global lifetimes with tracking one register that `ENTER`/`LEAVE`
  manage for you — but this tension is real and should be revisited after the
  rewrites.
- **Debugging becomes worse before it becomes better**: a value in a frame has
  no fixed address, so a memory watch cannot find it. Mitigated by the `TRAP`
  frame-chain reporting, which must land with the slice, not after it.

## Migration Plan

1. Land `F`, `ENTER`/`LEAVE` and frame addressing with the mode bit clear;
   confirm cycle-identical behaviour (**gate G7**).
2. Simulator frame-chain reporting and the overflow trap.
3. Rewrite the three named routines; measure freed globals.
4. **Gate decision point** — proceed or abandon.
5. If proceeding: migrate routine by routine, running `make metrics` each time.

## Open Questions

- Should `F` be 8-bit (zero page only) or 16-bit (frames anywhere in RAM)?
  Proposed: 8-bit, because 16-bit frames lose the short-operand advantage that
  motivated zero-page frames in the first place.
- Should parameter passing follow in a later change, or is "arguments in
  registers, locals in frames" the stable end state? Deferred until frames have
  been used.
- Does the overflow floor belong in a register or is a build-time constant
  enough? Proposed: a register, so the simulator can tighten it for testing.
