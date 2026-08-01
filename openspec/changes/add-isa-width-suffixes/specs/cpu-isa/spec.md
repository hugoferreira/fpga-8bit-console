## ADDED Requirements

### Requirement: Pseudo-Operation Width Suffixes

The `console6502` pseudo-operation layer SHALL express operand width as a
suffix on the mnemonic: no suffix for an 8-bit operand and a trailing `w` for a
little-endian 16-bit operand occupying `zp` and `zp+1`, matching the existing
`addw`/`subw`/`cmpw` spelling.

An unsuffixed mnemonic SHALL mean the 8-bit form. Adding the convention SHALL
NOT change the meaning or encoding of any existing source.

The width suffix SHALL be part of the mnemonic token, so that a width-suffixed
pseudo-operation cannot overlap an addressing-mode rule of the same mnemonic.

The suffix SHALL NOT be spelled with a `.` separator. `.` is the Inlay
frontend's member separator, so a dotted mnemonic at statement position is
indistinguishable from a qualified name and is resolved as one.

The convention SHALL apply to `src/isa/pseudo.asm` only. The word instructions
implemented in hardware — `ldab`, `stab`, `addw`, `subw`, `cmpw` — SHALL retain
their existing spelling, which matches the decode table in
`rtl/cpu6502_decode.sv`.

#### Scenario: Bare mnemonic is unchanged

- **WHEN** existing source contains `ror`, `ror zp` or `asl a, 3`
- **THEN** each assembles exactly as it did before the convention was added

#### Scenario: Suffixed and unsuffixed forms coexist

- **WHEN** a source file uses `asrw zp`, `asr`, `ror zp` and bare `ror`
- **THEN** all four resolve unambiguously and no rule collision is reported

#### Scenario: A dotted mnemonic is rejected by the frontend

- **WHEN** a width form is spelled `asr.w zp` in an Inlay-managed module
- **THEN** the frontend resolves it as a qualified name rather than an
  instruction, which is why the convention does not use `.`

#### Scenario: Width is a modifier for frequency counting

- **WHEN** an operation's idiom-frequency evidence is gathered for gate G3
- **THEN** sites at every width count toward the same operation, because the
  widths are one instruction and not several

### Requirement: Arithmetic Shift Right

The pseudo-operation layer SHALL provide `asr` and `asrw`, performing a
signed right shift in which the sign bit is replicated into bit 7 (byte form)
or bit 15 (word form).

`asr` SHALL operate on the accumulator and SHALL accept the counted form
`asr a, N`, with `N` in 1..8, equivalent to `N` consecutive arithmetic
shifts.

`asrw zp` SHALL operate on the zero-page pair `zp` and `zp+1`.

Each form SHALL emit exactly the byte sequence it replaces, so that adopting it
leaves every corpus image bit-identical.

#### Scenario: Sign is replicated, not zero-filled

- **WHEN** `asr` executes with the accumulator holding `$80`
- **THEN** the accumulator holds `$C0`, not `$40`

#### Scenario: Byte form matches hardware flags exactly

- **WHEN** `asr` executes
- **THEN** `N` is the preserved sign, `Z` is set if the result is zero, `C` is
  the bit shifted out and `V` is unchanged — the same flags a hardware `ASR A`
  would produce, so neither form refines the other

#### Scenario: Word form declares a weaker contract

- **WHEN** `asrw zp` executes
- **THEN** it clobbers `A`, and `Z` and `N` are UNDEFINED because the expansion
  sets them from the low byte while hardware would set them from the 16-bit
  result

#### Scenario: Counted form composes with the width axis

- **WHEN** source contains `asr a, 3`
- **THEN** it emits the same bytes as three consecutive `asr` operations

#### Scenario: Adoption does not move a single byte

- **WHEN** a corpus migrates its open-coded `cmp #$80` sequences to `asr`
- **THEN** the resulting ROM image is byte-for-byte identical to the image
  built before the migration
