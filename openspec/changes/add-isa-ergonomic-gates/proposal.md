## Why

Hand-writing 6502 for this console is dominated by plumbing, not by the game.
Measured over `src/main.asm` (1919 instructions, the Breakout port):

| Category | Instructions | Share |
| --- | --- | --- |
| `lda X` → `sta Y` adjacent pairs (data moved only because it must pass through A) | 460 | 24.0% |
| Flag-only ceremony (`clc`/`sec`/`cld`/`sei`/…) | 95 | 5.0% |
| Register transfers (`tax`/`txa`/`tay`/…) | 47 | 2.4% |
| Stack spills (`pha`/`pla`/`php`/`plp`) | 28 | 1.5% |
| **Total plumbing** | **630** | **32.8%** |

A third of the program exists to route bytes through a single accumulator and
to satisfy instruction preconditions. That is the target of a planned series of
ISA extensions.

Extending an ISA is easy to do badly: it is tempting to add instructions that
are *interesting* rather than instructions that are *load-bearing*, and there is
no natural feedback signal telling you an addition did not pay for itself. This
change installs that signal **before** any opcode is added — a measurable
definition of "more ergonomic", a tool that computes it, a recorded baseline, and
a single opcode registry so that independent slices cannot collide.

The gates already earn their keep: `DBNZ` (decrement-and-branch) was in the
original slice-1 sketch and the corpus shows only 5 candidate sites, so it fails
gate G3 and is cut. See `design.md`.

## What Changes

- **New capability `cpu-isa`** describing the extended instruction set as a
  whole: the compatibility contract with the NMOS 6502, the opcode allocation
  policy, the purity rules every added instruction must satisfy, and the
  acceptance gates.
- **Instruction purity rules** (normative, reviewable at spec time):
  - **P1 — No preconditions.** An added instruction MUST be total: its result
    MUST NOT depend on any flag or register the programmer has to set first.
  - **P2 — Declared, minimal clobber set.** An added instruction MUST document
    exactly which registers and flags it modifies, and MUST NOT modify `A`, `X`
    or `Y` unless that register is its named result.
  - **P3 — No hidden temporaries.** An added instruction MUST be expressible in
    one source line naming only the program's own symbols.
- **Eight acceptance gates (G1–G8)**, from purity through corpus reduction,
  cycle non-regression, and NMOS binary compatibility. A slice may not be
  archived until its gates pass.
- **`tools/isa_metrics.py`** — computes the corpus metrics above from
  `src/*.asm`, emits JSON, and fails with a non-zero exit code when a gate
  regresses. Wired into a new `make metrics` target.
- **`docs/opcodes.md`** — the single opcode registry. Every slice claims its
  slots here; two changes claiming one slot is a merge conflict by construction.
- **Opcode allocation policy**: columns `$x3` and `$xB` are the extension space;
  `$02` is reserved as a prefix byte opening a second instruction page; every
  opcode defined by the WDC 65C02 or Rockwell R65C02 is reserved for its
  canonical meaning and MUST NOT be reused.
- **`docs/isa-baseline.json`** — the recorded pre-extension measurement that all
  future gates are scored against.
- **A CPU conformance test** (Klaus Dormann's `6502_functional_test`) added to
  `make test`, so gate G7 (binary compatibility) is mechanically checkable.

No RTL behaviour changes in this proposal. It is measurement, policy and
tooling only.

## Impact

- Affected specs: `cpu-isa` (new capability)
- Affected code: `tools/isa_metrics.py` (new), `docs/opcodes.md` (new),
  `docs/isa-baseline.json` (new), `Makefile` (new `metrics` target, extended
  `test` target), `rtl/cpu6502_functional_tb.sv` (new)
- Downstream: `add-custom-assembler`, `add-isa-core-ergonomics`,
  `add-isa-test-and-branch`, `add-isa-word-ops`, `add-isa-pointer-ops`,
  `add-isa-frame-pointer` all depend on the gates and the registry defined here.
