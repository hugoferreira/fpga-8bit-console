# Which ISA should this console run?

Opened when the ergonomic gates were found to measure the corpus against itself
(`openspec/changes/amend-isa-gates-intent`). If the gates cannot tell "does not
need X" from "was written to avoid X", then the prior question is open: extend
the 6502, or adopt something else?

## What the workload actually is

These games are PICO-8 ports. PICO-8's only number type is **16.16 fixed
point**, so every arithmetic operation in the source is a 32-bit operation.

The celeste port does **8.8**. `src/celeste/math.asm` is titled "8.8
fixed-point helpers"; `fx.asm` comments read "spd = 1 + rnd(4), in 8.8". The
cart's constants include `0.70710678118`, `0.05`, `0.15` — an 8.8 representation
of 0.05 is 13/256, a 1.6% error that accumulates every frame.

That is the sharpest piece of evidence in this whole question, and it is not
about speed: **the ISA cost the port precision, not just cycles.** A 6502 could
do 16.16; it would cost roughly double the arithmetic, and the author chose
accuracy loss over that.

## The measurement

The core of a PICO-8 physics step — per-object gravity, friction, sub-pixel
accumulation, axis-separated collision, over a 16-object list — written in C as
the Lua means it (16.16), compiled `-Os`, against the same job in the shipped
6502 port (`obj_move` + `obj_update_all`, excluding the solid-tile lookup which
the C calls out to):

| | RV32I | RV32IMC | Z80 | Z80 | 6502 port |
| --- | --- | --- | --- | --- | --- |
| how | compiled | compiled | compiled | compiled | **hand-written** |
| fixed point | 16.16 | 16.16 | 16.16 | 8.8 | **8.8** |
| instructions | 61 | 61 | 331 | 225 | 64 |
| code bytes | 244 | **172** | 668 | 388 | **142** |
| loads/stores | 22 | 22 | 223 | 145 | 33 |
| ALU width | 32 | 32 | 8 | 8 | 8 |

The Z80 columns are `sdcc 4.6.0 -mz80 --std-c99`; RISC-V is
`riscv64-unknown-elf-gcc -Os`; the 6502 is the shipped port. `long` is 32-bit on
both compiled targets, which `int` is not — the first version of this
measurement compared 32-bit RISC-V against 16-bit Z80 without noticing.

Two controls make the table readable, because it contains three different
variables at once.

**A compiler on an 8-bit machine costs about 3.5x.** Z80 compiled at 8.8 is 225
instructions and 388 bytes; the 6502 hand-written at the same precision for the
same job is 64 and 142. Same width, same work, different author. That ratio is
the price of "just write it in C" on an 8-bit target, and it is paid in exactly
the currency this machine is short of.

**32-bit arithmetic on an 8-bit machine costs about 1.7x.** Z80 at 16.16 is 331
instructions against 225 at 8.8, 668 bytes against 388. That is what native
PICO-8 precision costs a byte-wide ALU, and it is why the port chose 8.8.

**RISC-V pays neither.** 61 instructions, 172 bytes, compiled, at full 16.16.

So the two things one might want most from a change of ISA — *a compiler* and
*the cart's own arithmetic* — are precisely the two things an 8-bit data path
charges for, and they multiply: 5.4x the instructions and 3.9x the bytes of
RV32IMC once you ask for both.

Three things fall out of this that are worth stating plainly.

**The 6502 is denser than RISC-V.** 142 bytes against 172 compressed, and
against 244 uncompressed. On a machine where instruction fetch is **77% of all
bus traffic** (`make cpu-bandwidth`), density is not an aesthetic preference, it
is the performance model. Un-compressed RV32I would be a *regression* here.
RVC is not optional for this design.

**The compiler and the 8-bit bus are in direct conflict.** That is the finding
that was not obvious before measuring. An 8-bit machine can be compact *or* it
can be compiled, and this corpus wants 16.16 as well, which is a third demand on
the same 8 bits.

**But the 6502 is doing half the arithmetic.** Normalising celeste's 8.8 up to
the cart's 16.16 roughly doubles the arithmetic without touching the control
flow — call it ~95 instructions and ~215 bytes. Then:

| for equal work, at the cart's own precision | RV32IMC | 6502 |
| --- | --- | --- |
| instructions | 61 | ~95 |
| code bytes | 172 | ~215 |
| loads/stores | 22 | ~50 |
| approximate bus traffic (bytes + data) | **194** | **265** |

So RISC-V is roughly **25-30% less bus traffic for four times the arithmetic
width** — real, and much less than the "32-bit must be far faster" intuition
predicts. The 6502's density claws most of it back.

## The three options

### A. Adopt RISC-V (RV32IMC)

**For.** A compiler. That is the entire argument and it is a very large one:
games get written in C instead of hand-assembly, the ports stop being
transcriptions, 16.16 comes free, and the seven `add-isa-*` slices become
unnecessary. Verification exists (`riscv-tests`, `riscof`). 32 registers cut
memory traffic by more than the ISA's lower density costs.

**Against.** Discards three working ports, the customasm rule definitions, the
Python test tooling and the 1.51 M-case conformance harness. RV32I needs a
32x32-bit register file — 1024 bits, which on an iCE40 is a block RAM this
design does not have spare, or ~1000 flops against a whole 6502 that is 1232
logic cells. And it stops being an 8-bit console, which is a question about what
the project is for, not an engineering one.

### B. Extend the 6502 toward the intent

**For.** The measured deficit is **arithmetic width and addressing modes**, not
register count. Nothing in the evidence asks for 32 registers; it asks for
16-bit values (119 half-pair operands in breakout), field access without an
index instruction (286 `ldy`/`ldx` in celeste), and cheaper locals. Preserves
the verified core, the harness, the assembler and three ports. Keeps the best
code density available, which is what a bandwidth-bound machine wants.

**Against.** No compiler worth having: the Z80 measurement above is the
evidence, and the Z80 is a *more* compiler-friendly 8-bit target than the 6502.
Every game stays hand-written. `add-isa-word-ops` gets to 16 bits, not 32, so 16.16 stays out of
reach and the precision loss stands. Seven slices of work.

### C. A 16-bit successor in the 6502 family

The middle path, and the one the intent evidence actually points at: 6502
addressing modes and code density, a 16-bit data path, base+displacement
addressing, and a frame pointer. Essentially what the 65816 is, designed for
this workload rather than for 1983.

**For.** Targets exactly what was measured. Keeps density. `cc65` has a 65816
backend, so a compiler is not out of reach.

**Against.** The largest engineering effort of the three, and it re-opens the
conformance question — the 65x02 suite covers the 6502, not a successor.

## What decides it

**Not the cycle numbers.** They are close enough that they do not choose for us:
25-30% of bus traffic, against a rewrite of everything above the CPU.

The question that decides it is **what the console is for**:

- *"I want to write more games for it."* Then the compiler dominates every other
  consideration and the answer is A. Nothing in option B ever produces one.
- *"I want to build a console."* Then the CPU is the project, the 6502 line is
  three ports and a verified core deep, and the answer is B or C.

## One coupling worth knowing before choosing

**The ISA choice and the memory subsystem are the same decision.** The Tang Nano
20K holds the whole 64 KB map in block RAM, which can be 32 bits wide — a 32-bit
ISA would fetch one instruction per cycle there. The BlackIce MX's SDRAM is 16
bits wide, so RV32 costs two accesses per instruction on that board and the
density gap reopens.

Option A argues for the Tang Nano and a wide fetch. Options B and C work on both.
See `docs/memory-subsystem.md` and `openspec/changes/add-cpu-prefetch`.

## Caveats on the Z80 columns

- **`sdcc`'s Z80 backend is not a strong optimiser**, and 32-bit arithmetic is
  its worst case. `z88dk`'s `zsdcc` with full optimisation would narrow the gap,
  and a hand-written Z80 version would narrow it much further — the 3.5x is a
  compiler-quality figure, not an ISA figure.
- **The 8.8 control was produced by rewriting the shifts and the type**, and the
  16.16 constants no longer fit, so `sdcc` warned about constant overflow. Its
  arithmetic is therefore indicative of *shape and width*, not numerically the
  same program.
- **No `(IX+d)` advantage shows up** the way the earlier hand-argument predicted:
  46 indexed accesses at 8.8, 116 at 16.16, but they are `sdcc` spilling a stack
  frame, not the field-access idiom the intent analysis pointed at. A hand-written
  Z80 would use them very differently.

## What this document is not

An answer. The measurements are honest but narrow: one kernel, one corpus,
static counts rather than a dynamic profile, and a C transcription of Lua that a
human wrote (me) and could have written differently. Before committing to A or
C, the thing worth doing is transcribing two or three more routines and getting
a dynamic instruction profile, because everything above weights by code written
rather than code executed.

---

# Slice scoreboard, measured

Written after `src/isa/pseudo.asm` made it possible to score a slice before
building it. Every figure here is from the two customasm corpora (breakout,
celeste); nemo is still ca65 and is excluded.

| Slice | Opcodes | Sites | Bytes | Status |
| --- | --- | --- | --- | --- |
| `add-isa-core-ergonomics` (MOV/ADD/SUB/TRAP) | 8 | ~200 | large | **built** |
| `add-isa-pointer-ops`, displacement half | 2 | 239 | large | **built** |
| `add-isa-word-ops` (AB) | 8 | 18 | 94 | **built** |
| `add-isa-test-and-branch` | 8 | 60 | 120 projected | **adopted in source** |
| `add-isa-pointer-ops`, remaining half | 6 | ~8 | negligible | **do not build** |
| `add-isa-frame-pointer` | prefix page | n/a | n/a | not measurable this way |

Two things this ordering says that the original slice plan did not.

**The word ops were the weakest of the built slices, and were built anyway**
because they were sized from an idiom count rather than from adoption. 18 sites.
Worth having, but they should not have gone before test-and-branch, which is
worth more for the same opcode budget.

**The remaining pointer ops should be dropped.** Six opcodes for about eight
sites; the block copy and fill that motivated them do not occur in either
corpus. The proposal also claims two slots that slice 2 already spent.

## When the pseudo-instruction method works

It is free exactly when the expansion is the code you would have written
anyway, because then adoption is bit-identical and carries no risk to argue
about. That holds for instructions that **fuse an existing sequence** and fails
for instructions that **add architectural state**:

- fusing (test-and-branch, the word ops): expansion is the current code, so
  `make pseudo-check` proves adoption is a no-op and the projection is honest;
- new state (the frame pointer's `F`): the only emulation is `ldx fp / lda n,x`,
  which clobbers X. Adopting it would make the games worse today and the
  resulting measurement would describe the emulation, not the instruction.

A slice that introduces a register has to be justified on its own terms — for
the frame pointer, on ergonomic ones, since its claim is about the size of
program a person can hold and that was never a byte count.

## What is still unmeasured

Everything here weights by **code written**. A dynamic profile would weight by
code executed, and the two disagree: a `cbne` in a per-frame inner loop is worth
far more than one in a menu. `docs/cpu-timing-v2.json` gives per-instruction
cycles, so the missing piece is an execution histogram from the simulator, not
new hardware. That is the next thing worth building for this programme, and it
is cheaper than any of the remaining slices.
