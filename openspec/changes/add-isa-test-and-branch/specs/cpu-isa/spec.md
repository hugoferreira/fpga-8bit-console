## ADDED Requirements

### Requirement: Register-Free Compare And Branch

The CPU SHALL provide instructions that compare a zero-page location against an
immediate constant and branch on the result, without loading the value into a
register. These instructions SHALL NOT modify `A`, `X`, `Y` or any processor
flag.

The following forms SHALL be provided, each 4 bytes, taking 5 cycles when the
branch is not taken, 6 when taken and 7 when the taken branch crosses a page:

- `CBEQ zp, #imm, rel` — opcode `$0B`, branch when equal
- `CBNE zp, #imm, rel` — opcode `$1B`, branch when not equal
- `CBLT zp, #imm, rel` — opcode `$2B`, branch when the location is unsigned-less
- `CBGE zp, #imm, rel` — opcode `$3B`, branch when the location is
  unsigned-greater-or-equal

#### Scenario: Equality branch taken

- **WHEN** location `$30` holds `3` and `CBEQ $30, #3, target` executes
- **THEN** execution continues at `target`

#### Scenario: Registers and flags survive the test

- **WHEN** any compare-and-branch form executes
- **THEN** `A`, `X`, `Y` and the processor status register are unchanged

#### Scenario: Test does not disturb a pending comparison

- **WHEN** a `CMP` is followed by a `CBNE` on an unrelated location and then a
  conditional branch
- **THEN** the conditional branch is taken on the result of the `CMP`

#### Scenario: Zero test

- **WHEN** location `$30` holds `0` and `CBEQ $30, #0, target` executes
- **THEN** execution continues at `target`

### Requirement: Register-Free Mask Test And Branch

The CPU SHALL provide instructions that test a zero-page location against an
immediate bit mask and branch on the result, without loading the value into a
register and without modifying `A`, `X`, `Y` or any processor flag.

- `TBZ zp, #mask, rel` — opcode `$4B`, branch when `(zp & mask) == 0`
- `TBNZ zp, #mask, rel` — opcode `$5B`, branch when `(zp & mask) != 0`

Both SHALL be 4 bytes and SHALL take 5 cycles when not taken, 6 when taken and 7
when the taken branch crosses a page.

#### Scenario: Multi-bit mask clear

- **WHEN** location `$30` holds `$10` and `TBZ $30, #$0F, target` executes
- **THEN** execution continues at `target`

#### Scenario: Multi-bit mask set

- **WHEN** location `$30` holds `$10` and `TBNZ $30, #$10, target` executes
- **THEN** execution continues at `target`

#### Scenario: Registers and flags survive the test

- **WHEN** either mask-test form executes
- **THEN** `A`, `X`, `Y` and the processor status register are unchanged

### Requirement: Relative Subroutine Call And Jump

The CPU SHALL provide `BSR rel` (opcode `$6B`, 2 bytes, 6 cycles), which pushes
the return address as `JSR` does and branches relative to the program counter,
and `BRA rel` (opcode `$7B`, 2 bytes, 3 cycles), an unconditional relative jump.
Neither SHALL modify `A`, `X`, `Y` or any processor flag.

#### Scenario: Relative call returns correctly

- **WHEN** `BSR sub` calls a routine ending in `RTS`
- **THEN** execution resumes at the instruction after the `BSR`

#### Scenario: Relative call is position independent

- **WHEN** a code block containing a `BSR` and its target is assembled at a
  different origin
- **THEN** the emitted bytes for the `BSR` are unchanged

### Requirement: Long Branch Displacements

Every conditional branch, `BSR` and `BRA` SHALL have a form taking a 16-bit
displacement, encoded on the `$02` prefix page. The assembler SHALL select
between the short and long form automatically based on the distance to the
target, and SHALL report an error only when no form can reach.

#### Scenario: Distant target assembles without programmer action

- **WHEN** source branches to a label 500 bytes away
- **THEN** the long form is emitted and no out-of-range error is reported

#### Scenario: Nearby target is unaffected

- **WHEN** a program whose every branch target is within 8-bit range is
  assembled with long-branch forms available
- **THEN** the emitted binary is byte-identical to one assembled without them

#### Scenario: Encoding selection converges

- **WHEN** a program's branch encodings are selected across assembly passes
- **THEN** the assembler reaches a fixed point, or fails with a convergence
  error, and never emits a branch that does not reach its target
