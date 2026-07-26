## Why

`src/main.asm` declares **141 constants**, most of them hand-allocated zero-page
addresses in one flat map:

```
.define padx    $30
.define chaint  $33
.define flasht  $34
.define pill_yf $3E
.define t_slow  $40
.define sd_t    $57
```

This is the wall that hand-written 6502 hits. Every temporary in every
subroutine is a global. Adding a local variable means finding a free byte in a
map you maintain in your head or in a comment block, and being sure no routine
you might be called from is using it. Two routines cannot use the same scratch
byte unless you have proved they never overlap; recursion is impossible; and
the failure mode is silent corruption at a distance.

The other slices make each *line* cheaper. This one is the only slice that
changes what *size of program* a person can hold. It is also the most invasive,
which is why it is last.

## What Changes

- **A frame pointer register `F`** (8 bits, addressing a zero-page frame). Frame
  addressing `f+n` reads location `F + n` modulo 256.
- **`ENTER #n`** allocates a frame of `n` bytes: pushes the old `F`, sets
  `F` to the new frame base, and moves the frame allocation pointer.
  **`LEAVE`** reverses it.
- **Frame-relative forms** of the load/store/compare instructions and of the
  slice-3 `MOV`, so a local reads as `mov f+2, #0` rather than
  `mov scratch_used_by_nobody_else, #0`.
- **`F` is saved and restored by interrupts**, so a handler may use frames.
- All of the above live on the **`$02` prefix page**, not in the primary opcode
  columns — frame-relative access pays one byte and one cycle over zero-page
  access. That is the deliberate trade: locals cost slightly more than globals,
  which is the correct incentive for a machine where zero page is 256 bytes.

Frames live in the zero-page region above the hand-allocated globals; the frame
allocation pointer starts at the top of zero page and grows downward, so a
frame overflow collides with globals detectably rather than silently.

- **`TRAP` integration**: the debug trap reports the current frame chain, so a
  stack trace with local values becomes possible in the simulator.

## Impact

- Affected specs: `cpu-isa`
- Affected code: `rtl/cpu6502_arlet.sv` (new register, new addressing mode,
  interrupt save/restore), `rtl/cpu6502_tb.sv`, `src/isa/ext_frame.asm` (new),
  `src/isa/memmap.asm` (frame region), `src/main.asm`, `sim/console.cpp`
  (frame chain reporting), `docs/opcodes.md`
- Depends on: all preceding slices
- **This slice has no G3 pattern evidence and cannot get any** — the corpus
  cannot show a demand for a feature it has no way to express. Its gate is
  entirely rewrite-based and is defined in `design.md`; it is explicitly the
  most speculative slice in the programme and is sequenced last so that it can
  be abandoned without blocking anything.

## Why this slice cannot be pre-measured with pseudo-instructions

`src/isa/pseudo.asm` let `add-isa-test-and-branch` be adopted in source and
scored before any hardware existed. That worked because of one property: each
pseudo-op expanded to **exactly the instructions the corpus already contained**,
so adopting it was bit-identical and therefore free. `make pseudo-check` proves
that per rule.

Frame pointers fail that test, and it is worth being precise about why.

`F` is a register. The only way to emulate frame-relative addressing on this
core is zero-page indexed, which wraps modulo 256 exactly as `f+n` is specified
to:

    lda f+2          ->      ldx fp
                             lda 2, x

That expansion **clobbers X**, and X is the loop index in nearly every routine
in both corpora. So the pseudo-op's contract would have to read "clobbers X and
the flags", the hardware would preserve X, and - since the contract must be the
weaker of the two - all code written against it would have to treat X as dead
across every local access. Sound, but useless: the resulting code is longer,
slower, and more constrained than the hand-allocated globals it replaces.

Adoption would therefore make the games measurably worse today in exchange for
a future benefit, and the measurement it produced would describe the emulation
rather than the instruction. That is worse than no measurement.

**The general rule this exposes:** the pseudo-instruction technique is free
exactly when the expansion is the code you would have written anyway. It works
for instructions that FUSE an existing sequence - test-and-branch, the word ops
- and not for instructions that add architectural state. A slice that
introduces a register has to be justified on its own terms.

Which, for this slice, means on ergonomic terms rather than density ones. The
proposal already says so: *"this one is the only slice that changes what size of
program a person can hold"*. That is not a byte count, and no amount of tooling
will turn it into one. The honest way to size it is to write one non-trivial
routine both ways and compare - which is a design exercise, not a measurement,
and should be scheduled as such.
