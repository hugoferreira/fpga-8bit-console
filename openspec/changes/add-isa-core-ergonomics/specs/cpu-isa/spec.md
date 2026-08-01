## ADDED Requirements

### Requirement: Register-Free Memory Store

The CPU SHALL provide `MOV` instructions that write a value to memory without
using or modifying `A`, `X` or `Y`, and without modifying any processor flag.

The following forms SHALL be provided:

- `MOV zp, #imm` — opcode `$03`, 3 bytes, 4 cycles
- `MOV abs, #imm` — opcode `$13`, 4 bytes, 5 cycles
- `MOV zp, abs,X` — opcode `$23`, 4 bytes, 6 cycles (7 when the indexed address
  crosses a page boundary)

Operand order SHALL be destination first, and the encoded byte order SHALL match
the source order.

#### Scenario: Immediate stored to zero page

- **WHEN** `MOV $30, #7` executes
- **THEN** location `$30` holds `7`

#### Scenario: Registers and flags are preserved

- **WHEN** any `MOV` form executes
- **THEN** `A`, `X`, `Y` and the processor status register hold exactly the
  values they held before the instruction

#### Scenario: Store between a compare and its branch

- **WHEN** a `CMP` is followed by a `MOV` and then a conditional branch
- **THEN** the branch is taken on the result of the `CMP`, unaffected by the
  `MOV`

#### Scenario: Indexed source reads through X

- **WHEN** `MOV $30, $1000,X` executes with `X` = 5 and location `$1005` holding
  `42`
- **THEN** location `$30` holds `42` and `X` still holds `5`

### Requirement: Carry-Free Addition And Subtraction

The CPU SHALL provide `ADD` and `SUB` instructions that require no preparatory
flag state. `ADD` SHALL add with a carry-in of 0 and `SUB` SHALL subtract with a
borrow-in of 0, regardless of the carry flag on entry. Both SHALL operate in
binary regardless of the decimal flag.

The following forms SHALL be provided:

- `ADD #imm` — opcode `$33`, 2 bytes, 2 cycles
- `ADD zp` — opcode `$43`, 2 bytes, 3 cycles
- `SUB #imm` — opcode `$53`, 2 bytes, 2 cycles
- `SUB zp` — opcode `$63`, 2 bytes, 3 cycles

Both SHALL write their result to `A` and SHALL set `N`, `V`, `Z` and `C` exactly
as `ADC` and `SBC` respectively set them, using the same borrow polarity for
`C`, so that an `ADD` may be continued by an `ADC`.

#### Scenario: Addition ignores an incoming carry

- **WHEN** the carry flag is set and `ADD #1` executes with `A` = 10
- **THEN** `A` holds 11

#### Scenario: Addition ignores decimal mode

- **WHEN** the decimal flag is set and `ADD #1` executes with `A` = `$09`
- **THEN** `A` holds `$0A`

#### Scenario: Multi-byte chain starts with ADD

- **WHEN** `ADD` on the low byte produces a carry and the following `ADC` adds
  the high bytes
- **THEN** the 16-bit result is correct without any `CLC`

#### Scenario: Subtraction ignores an incoming borrow

- **WHEN** the carry flag is clear and `SUB #1` executes with `A` = 10
- **THEN** `A` holds 9

### Requirement: Diagnostic Trap Instruction

The CPU SHALL provide `TRAP #imm` (opcode `$73`, 2 bytes, 2 cycles), which
signals the immediate value to the host environment for one cycle and then
continues with the next instruction. It SHALL NOT modify any register, flag, or
memory location, and SHALL NOT push state or vector.

The simulator SHALL interpret the immediate: `$00` breakpoint, `$01` register
dump with the enclosing symbol name, `$02` assertion failure, `$10`–`$7F` user
log points, `$80`–`$FF` reserved. On hardware the signal SHALL have no
observable effect.

#### Scenario: Trap is transparent to the program

- **WHEN** `TRAP #$01` executes
- **THEN** all registers, flags and memory are unchanged and execution continues
  at the following instruction

#### Scenario: Simulator reports a register dump

- **WHEN** `TRAP #$01` executes under the simulator with a symbol file loaded
- **THEN** the simulator prints `A`, `X`, `Y`, `P`, `S` and `PC` together with
  the nearest preceding label and its offset

#### Scenario: Hardware ignores the trap

- **WHEN** `TRAP #$01` executes on the FPGA build
- **THEN** the program's observable behaviour is identical to a build in which
  the instruction is absent, apart from the two cycles it consumes
