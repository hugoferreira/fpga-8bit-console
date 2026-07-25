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

| | RV32I | RV32IMC | 6502 port |
| --- | --- | --- | --- |
| instructions | 61 | 61 | 64 |
| code bytes | 244 | **172** | **142** |
| loads/stores | 22 | 22 | 33 (52% of instructions) |
| ALU width | 32 | 32 | 8 |
| fixed point | 16.16 | 16.16 | **8.8** |

Two things fall out of this that are worth stating plainly.

**The 6502 is denser than RISC-V.** 142 bytes against 172 compressed, and
against 244 uncompressed. On a machine where instruction fetch is **77% of all
bus traffic** (`make cpu-bandwidth`), density is not an aesthetic preference, it
is the performance model. Un-compressed RV32I would be a *regression* here.
RVC is not optional for this design.

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

**Against.** No compiler, and no realistic path to one. Every game stays
hand-written. `add-isa-word-ops` gets to 16 bits, not 32, so 16.16 stays out of
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

## What this document is not

An answer. The measurements are honest but narrow: one kernel, one corpus,
static counts rather than a dynamic profile, and a C transcription of Lua that a
human wrote (me) and could have written differently. Before committing to A or
C, the thing worth doing is transcribing two or three more routines and getting
a dynamic instruction profile, because everything above weights by code written
rather than code executed.
