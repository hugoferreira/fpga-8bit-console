## Context

The console's software is 3064 lines of hand-written assembly built by
`ca65 -t none` → `ld65 -C src/memory.cfg` → `hexdump` → `rtl/ram.hex`. The ISA
extension programme needs an assembler that can be taught new instructions
without recompiling the assembler.

## Goals / Non-Goals

**Goals**

- New instructions are added by editing a text file, in the same commit as the
  RTL decode.
- The migration is provably lossless: byte-identical output on the existing
  corpus.
- Better authoring ergonomics as a side effect (shortest-encoding selection,
  argument assertions with real error messages, symbol output for the sim).

**Non-Goals**

- Keeping `cc65` viable for C on this console. C is not how this console is
  programmed; if C is wanted later, `cc65` still targets stock 6502 and its
  output can be assembled separately.
- Object files, libraries, and relocatable linking. One program, one binary.

## Decisions

### Decision: adopt customasm rather than build our own

customasm's model is exactly the shape of this problem. An instruction set is a
`#ruledef`:

```
#ruledef nmos6502 {
    lda #{v: u8}      => 0xa9 @ v
    lda {a: u8}       => 0xa5 @ a
    lda {a: u16}      => 0xad @ a[7:0] @ a[15:8]
    beq {t: u16}      => { r = t - $ - 2, assert(r <= 0x7f), assert(r >= -0x80),
                           0xf0 @ r[7:0] }
}
```

Adding slice 3's store-immediate is then three lines in `src/isa/ext_core.asm`:

```
#ruledef ext_core {
    mov {a: u8},  #{v: u8}  => 0x03 @ a @ v
    mov {a: u16}, #{v: u8}  => 0x13 @ a[7:0] @ a[15:8] @ v
    mov {d: u8},  {s: u8}   => 0x23 @ d @ s
}
```

Properties that matter here:

- **Instruction set as data.** Slices become additive `#include`s; a build
  without a slice's file simply cannot assemble that slice's mnemonics, which is
  the correct failure mode for a console whose gateware may or may not have the
  extension.
- **Fixed-point assembly with fewest-bits selection.** When two rules match, the
  one producing the fewest bits wins. Long branches therefore need no programmer
  involvement: define `beq` twice (rel8 with an `assert` on range, rel16
  without) and the assembler picks. This is a genuine ergonomic feature we would
  otherwise have to build.
- **`$assert` / `#assert`.** Rules can reject out-of-range arguments with a
  custom message, so "zero page address expected, got 0x4006" is an assembler
  error rather than silent truncation.
- **`#bankdef`** expresses the memory map directly, replacing `memory.cfg`.
- **A native Verilog output format.** `-f readmemh` emits exactly what
  `$readmemh` wants — hex, MSB-first, grouped per bank width, no addresses — so
  `rtl/ram.hex` is written directly and the `hexdump` stage disappears.
  Note that customasm's own `hexdump` format is *not* this: it emits an address
  column and an ASCII sidebar (`src/util/bitvec_format.rs`), which `$readmemh`
  would read as data. `binary`, `mif`, `intelhex` and `symbols` are also
  available; the full list is 28 formats.
- **Bounded fixed-point resolution.** The iteration count is a CLI option
  (`-t`/`--iters`), so convergence is bounded rather than guaranteed. The build
  pins it and treats non-convergence as an error.
- **Rust**, matching `tools/` and `rust/`; installed with `cargo install`,
  pinned by version in the Makefile.

### Alternatives considered

**A. `ca65` macro pack (`.macro mov …` emitting `.byte`).** Zero tool work and
it can ship this week — this is the recommended *bridge* while customasm lands.
Rejected as the destination: macro operands cannot express addressing modes
naturally, the assembler cannot range-check them, error messages point inside
the macro, and the listing/disassembly is unreadable.

**B. Fork `ca65`.** The opcode table is data inside a C program, so adding
instructions is genuinely small work. Rejected because it makes the project
responsible for building and distributing a toolchain fork on every developer
machine and CI, in exchange for a linker and object-file model this project does
not use.

**C. Write our own assembler in Rust.** Full control, and the parts we would
most want (error messages, listings, debug info for the simulator) are exactly
the parts that are weeks of work rather than days. Rejected as premature:
customasm already provides the ruledef mechanism, and if it is outgrown, the
`src/isa/*.asm` ruledefs are a specification we could re-implement against.

**D. Keep `ca65` and abandon ISA extensions**, relying on macros over stock
6502. This is the honest null option and it does get perhaps 60% of the
ergonomic win with no hardware change. It cannot deliver the other 40%: macro
expansions silently clobber `A` and the flags, which is precisely the invisible
state the programme exists to remove. Documented in `add-isa-ergonomic-gates`
as the reason purity rule P2 exists.

### Decision: `$` migration is a mechanical rewrite

customasm reserves `$` for the current address, so `$4000` must become `0x4000`.
This touches every literal in the corpus and is the single largest mechanical
edit in the migration. It is scripted, and gate A2 (byte identity) is what makes
it safe: a mis-rewritten literal changes the binary and fails the build.

### Decision: memory map moves from `memory.cfg` to `#bankdef`

```
#bankdef zp    { #addr 0x0000, #size 0x0100, #outp 0 }
#bankdef stack { #addr 0x0100, #size 0x0100 }
#bankdef ram   { #addr 0x0200, #size 0xfdfa, #outp 8 * 0x0200 }
#bankdef vec   { #addr 0xfffa, #size 0x0006, #outp 8 * 0xfffa }
```

`ZEROPAGE` and `BSS` become `#bankdef`s with no output, so zero-page variables
keep being declared by address as they are today (141 `.define`s) without the
linker's `zp` segment machinery.

## Acceptance gates

Beyond the programme-wide gates in `add-isa-ergonomic-gates`:

| Gate | Statement |
| --- | --- |
| **A1 Coverage** | Every `ca65` directive and syntax form used by the corpus has a documented customasm equivalent in `docs/assembler.md`. |
| **A2 Byte identity** | `customasm` output for the migrated corpus is byte-identical to the `ca65`/`ld65` output for the pre-migration corpus. This is the migration's correctness proof. |
| **A3 One command** | Producing `rtl/ram.hex` from source takes one assembler invocation and no intermediate object file. |
| **A4 Build time** | Whole-program assembly of the corpus completes in under 1 second. |
| **A5 Diagnostics** | Assembling a zero-page instruction with an absolute address, and a branch beyond range with no long form available, each produce an error naming the source line and the offending value. |
| **A6 Symbols** | The simulator loads `build/main.sym` and can resolve a PC to the nearest preceding label. |

A2 is the gate that de-risks the whole change: until it passes, the `ca65` path
stays as the default.

## Risks / Trade-offs

- **No linker.** Whole-program assembly of 3k lines is instant and simpler, but
  there is no path to linking pre-built libraries. Accepted: none exist.
- **Upstream dependency.** customasm is a single-maintainer project. Mitigation:
  pin an exact version in the Makefile, vendor the binary's version in
  `README.md`, and keep `src/isa/*.asm` as a portable description of the ISA.
- **Convergence failures.** Fixed-point assembly can fail to converge when
  instruction size depends on a label whose address depends on that size.
  Mitigation: the long-branch rules added in `add-isa-test-and-branch` must be
  written so that the short form's `assert` is monotone in the displacement;
  a convergence failure is a build error, not silent miscompilation.
- **Ambiguous rules are errors.** Two rules producing the same bit count for the
  same syntax cannot be disambiguated. Mitigation: `#ruledef` files are reviewed
  as part of each slice, and A5 covers the diagnostics.
- **`cc65` removal is breaking** for anyone building the repo from the README.
  Mitigation: `make asm-ca65` retained for one release; README updated in the
  same change.

## Migration Plan

1. Land `src/isa/nmos6502.asm` and assemble the *unmodified-semantics* corpus
   alongside the `ca65` build; iterate until A2 passes.
2. Switch the default `asm` target to customasm; keep `make asm-ca65`.
3. Remove `src/memory.cfg`, the `.o` intermediate and the `hexdump` stage.
4. Update `README.md` prerequisites (`cargo install customasm`, drop `cc65`).
5. Remove the `ca65` path in the release after the ISA core slice lands.

Rollback at any point before step 5 is switching the `asm` target back.

## Open Questions

- Pin customasm by crates.io version or by vendored git submodule? Proposed:
  crates.io version pin, revisit if a needed fix is unreleased.
- Should `src/isa/nmos6502.asm` model the NMOS illegal opcodes? Proposed: no —
  the extension space overlaps them, and the conformance test only covers
  documented behaviour.
