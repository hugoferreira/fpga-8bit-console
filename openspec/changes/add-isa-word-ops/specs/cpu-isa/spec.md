## ADDED Requirements

### Requirement: Zero-Page Word Operands

The CPU SHALL treat a zero-page address `zp` given to a word instruction as a
little-endian 16-bit operand occupying `zp` and `zp+1`, with the high byte
address computed modulo 256.

#### Scenario: Pair wraps at the top of zero page

- **WHEN** a word instruction addresses `$FF`
- **THEN** it uses `$FF` as the low byte and `$00` as the high byte

### Requirement: Word Assignment

The CPU SHALL provide `MOVW zp, #imm16` (opcode `$83`, 4 bytes, 6 cycles) and
`MOVW zp, zp` (opcode `$93`, 3 bytes, 8 cycles), which write a 16-bit value to a
zero-page pair without using or modifying `A`, `X`, `Y` or any processor flag.

#### Scenario: Constant assigned to a pair

- **WHEN** `MOVW $40, #600` executes
- **THEN** `$40` holds `$58` and `$41` holds `$02`

#### Scenario: Registers and flags preserved

- **WHEN** either `MOVW` form executes
- **THEN** `A`, `X`, `Y` and the processor status register are unchanged

### Requirement: Word Addition And Subtraction

The CPU SHALL provide `ADDW zp, #imm16` (opcode `$A3`, 4 bytes, 9 cycles),
`ADDW zp, zp` (opcode `$B3`, 3 bytes, 11 cycles) and `SUBW zp, #imm16` (opcode
`$C3`, 4 bytes, 9 cycles). Each SHALL carry internally between the two bytes,
SHALL require no preparatory carry state, SHALL operate in binary regardless of
the decimal flag, and SHALL NOT use or modify `A`, `X` or `Y`.

Each SHALL set `C` from bit 16 of the result, `N` from bit 15, `Z` from the full
16-bit result being zero, and `V` from signed 16-bit overflow.

#### Scenario: Carry propagates between bytes

- **WHEN** `$40` holds `$FF`, `$41` holds `$00`, and `ADDW $40, #1` executes
- **THEN** `$40` holds `$00` and `$41` holds `$01`

#### Scenario: No preparatory carry needed

- **WHEN** the carry flag is set on entry and `ADDW $40, #1` executes
- **THEN** the result is the same as if the carry flag had been clear

#### Scenario: Registers preserved

- **WHEN** any word arithmetic instruction executes
- **THEN** `A`, `X` and `Y` are unchanged

#### Scenario: Zero flag reflects the whole word

- **WHEN** `$40` holds `$01`, `$41` holds `$00`, and `SUBW $40, #1` executes
- **THEN** the zero flag is set

### Requirement: Word Comparison

The CPU SHALL provide `CMPW zp, #imm16` (opcode `$D3`, 4 bytes, 8 cycles),
setting `N`, `Z` and `C` from the 16-bit comparison exactly as `CMP` sets them
for 8 bits, so that existing conditional branches work unchanged. It SHALL NOT
modify memory, `A`, `X` or `Y`.

#### Scenario: Existing branches work on 16-bit values

- **WHEN** `CMPW $40, #0` is followed by `BEQ` and the pair holds zero
- **THEN** the branch is taken

#### Scenario: Unsigned ordering

- **WHEN** the pair holds `$0100` and `CMPW $40, #$00FF` executes
- **THEN** the carry flag is set and the zero flag is clear

### Requirement: Word Increment And Decrement

The CPU SHALL provide `INW zp` (opcode `$E3`, 2 bytes, 8 cycles) and `DEW zp`
(opcode `$F3`, 2 bytes, 8 cycles), which add or subtract one from a zero-page
pair, carrying internally. Each SHALL set `N` and `Z` from the 16-bit result,
SHALL leave `C` unchanged, and SHALL NOT use or modify `A`, `X` or `Y`.

#### Scenario: Increment carries into the high byte

- **WHEN** `$40` holds `$FF`, `$41` holds `$02`, and `INW $40` executes
- **THEN** `$40` holds `$00` and `$41` holds `$03`

#### Scenario: Decrement to zero sets the zero flag

- **WHEN** the pair holds 1 and `DEW` executes
- **THEN** the pair holds 0 and the zero flag is set

#### Scenario: Carry flag is untouched

- **WHEN** the carry flag is set and `INW` executes
- **THEN** the carry flag is still set
