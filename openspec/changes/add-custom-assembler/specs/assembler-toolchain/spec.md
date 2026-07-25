## ADDED Requirements

### Requirement: customasm As The Console Assembler

The console's assembler SHALL be [customasm](https://hlorenzi.github.io/customasm/)
(`hlorenzi/customasm`). The instruction set SHALL be expressed in its `#ruledef`
and `#subruledef` blocks, the memory map in its `#bankdef` blocks, and operand
validation in its `assert` expressions. The required version SHALL be pinned in
the `Makefile` and stated in `README.md` prerequisites alongside its acquisition
command, and the build SHALL fail with an actionable message when the assembler
is missing or does not match the pinned version.

#### Scenario: Assembler absent

- **WHEN** `make asm` runs on a machine without customasm installed
- **THEN** the build fails naming the tool, the pinned version and the
  `cargo install customasm` command, rather than failing inside a shell pipeline

#### Scenario: Version mismatch

- **WHEN** the installed customasm version differs from the pinned version
- **THEN** the build fails reporting both versions, because encoding selection and
  diagnostics are version-dependent

#### Scenario: Instruction set is expressed in the tool's own vocabulary

- **WHEN** a slice adds an instruction
- **THEN** it does so as a rule in a `#ruledef` block under `src/isa/`, with
  typed parameters (`u8`, `s8`, `i8`, `u16`) carrying the operand range, and no
  hand-assembled data bytes

### Requirement: Verilog-Loadable Image Output

The assembler SHALL write `rtl/ram.hex` in a format that Verilog `$readmemh`
accepts directly: whitespace-separated hexadecimal byte values with no address
column, no ASCII sidebar and no other annotation. customasm's `readmemh` output
format SHALL be used for this purpose.

#### Scenario: Image loads into the RAM model

- **WHEN** `make asm` writes `rtl/ram.hex` and `ram_async` loads it with
  `$readmemh`
- **THEN** every byte lands at the address the assembler placed it at, and
  simulation reports no `$readmemh` parse warnings

#### Scenario: Annotated formats are not used for the image

- **WHEN** an output format that emits addresses or annotation is selected for
  `rtl/ram.hex`
- **THEN** the build is incorrect, because `$readmemh` interprets the address
  column as data

### Requirement: Bounded Encoding Resolution

customasm resolves encodings by iterating to a fixed point under a bounded
iteration count. The build SHALL pin that bound explicitly, and a program that
fails to converge within it SHALL fail the build with an error naming the
unresolved instructions. Non-convergence SHALL NOT silently yield a longer
encoding.

#### Scenario: Resolution does not converge

- **WHEN** the iteration bound is reached with encodings still changing
- **THEN** assembly fails and names the instructions that did not settle

#### Scenario: Bound is explicit, not defaulted

- **WHEN** the build invokes the assembler
- **THEN** the iteration bound is passed explicitly, so a future default change
  in the tool cannot alter the emitted binary

### Requirement: Reproducible Assembly

Assembling unchanged sources with the pinned assembler version SHALL produce a
byte-identical image on any machine. The build SHALL NOT depend on the
assembler's legacy-behaviour mode, and SHALL NOT depend on host locale, path
layout or terminal capabilities.

#### Scenario: Same source, different machine

- **WHEN** the same commit is assembled on two machines with the pinned version
- **THEN** the resulting `rtl/ram.hex` files compare equal byte for byte

#### Scenario: Legacy mode is not relied upon

- **WHEN** the corpus is assembled with legacy behaviour disabled
- **THEN** assembly succeeds, so the migration targets current semantics rather
  than a compatibility mode that may be withdrawn

### Requirement: Data-Defined Instruction Set

The assembler SHALL take the console's instruction set from text definition
files under `src/isa/`, not from the assembler binary. Adding an instruction to
the console SHALL require editing only those files and the RTL decode.

#### Scenario: New instruction becomes assemblable

- **WHEN** a rule for a new mnemonic is added to a file under `src/isa/`
- **THEN** source using that mnemonic assembles to the specified opcode bytes
  with no change to the assembler binary

#### Scenario: Instruction from an absent slice is rejected

- **WHEN** source uses a mnemonic whose slice definition file is not included in
  the build
- **THEN** assembly fails with an unknown-instruction error naming the mnemonic
  and the source line

### Requirement: Layered Instruction Set Definitions

`src/isa/` SHALL separate the base instruction set, the memory map, the console
register constants, and one file per ISA extension slice. Extension files SHALL
be additive: including a slice's file SHALL NOT change the encoding of any
instruction defined outside it.

#### Scenario: Slice inclusion does not perturb the base

- **WHEN** the corpus is assembled with and without an extension slice's
  definition file, using no instruction from that slice
- **THEN** both builds produce byte-identical output

### Requirement: Single-Command Build Pipeline

Producing `rtl/ram.hex` from assembly source SHALL take one assembler
invocation, with no intermediate object file and no separate link or hex-dump
stage.

#### Scenario: Hex image is produced directly

- **WHEN** `make asm` runs
- **THEN** `rtl/ram.hex` is written directly by the assembler and no `.o` file
  is created

### Requirement: Memory Map Definition

The memory map SHALL be expressed in the assembler's own bank definitions in
`src/isa/memmap.asm`, preserving the current layout: zero page at `$0000`, stack
at `$0100`, RAM from `$0200`, code from `$0300`, and the reset/IRQ vectors at
`$FFFA`.

#### Scenario: Code lands at the same origin

- **WHEN** the corpus is assembled with the new memory map
- **THEN** the first byte of code is placed at `$0300` and the vectors occupy
  `$FFFA`–`$FFFF`

#### Scenario: Overflowing a bank is an error

- **WHEN** a bank's contents exceed its declared size
- **THEN** assembly fails naming the bank and the overflow amount

### Requirement: Migration Byte Identity

The migrated corpus SHALL assemble to a binary byte-identical to the one
produced by the pre-migration `ca65`/`ld65` pipeline. The previous pipeline
SHALL remain available as `make asm-ca65` until this equivalence has been
demonstrated on the released build.

#### Scenario: Equivalence is demonstrated

- **WHEN** both pipelines assemble their respective corpora
- **THEN** the resulting binaries compare equal byte for byte

### Requirement: Shortest Encoding Selection

When more than one encoding of an instruction is valid for its operands, the
assembler SHALL select the one producing the fewest bytes. A programmer SHALL
NOT have to choose between short and long forms of a branch.

#### Scenario: Near branch uses the short form

- **WHEN** a conditional branch targets a label within the 8-bit displacement
  range and both a short and a long form are defined
- **THEN** the two-byte form is emitted

#### Scenario: Far branch uses the long form

- **WHEN** the same branch targets a label outside the 8-bit displacement range
- **THEN** the long form is emitted and no out-of-range error is reported

#### Scenario: Far branch with no long form available

- **WHEN** a branch is out of range and no long form is defined
- **THEN** assembly fails naming the source line and the required displacement

### Requirement: Operand Range Diagnostics

The assembler SHALL reject operands outside an instruction's valid range with an
error naming the source line, the instruction and the offending value, rather
than silently truncating.

#### Scenario: Absolute address given to a zero-page instruction

- **WHEN** an instruction accepting only a zero-page operand is given `$4006`
- **THEN** assembly fails reporting that a zero-page address was expected and
  `$4006` was given

### Requirement: Symbol Output For The Simulator

The build SHALL emit a symbol file mapping labels to addresses, and the
simulator SHALL load it to resolve an address to the nearest preceding label.

#### Scenario: Trace names a routine

- **WHEN** the simulator reports a program counter inside a labelled routine
- **THEN** it prints the label name and the offset from it
