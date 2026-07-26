## ADDED Requirements

### Requirement: Post-Increment Pointer Access

The CPU SHALL provide addressing forms that access memory through a zero-page
pointer pair and then advance that pair by one, carrying into the high byte,
without using or modifying `X` or `Y` and without branching.

- `LDA (zp)+` — opcode `$8B`, 2 bytes, 7 cycles, loads `A`, sets `N` and `Z`
- `STA (zp)+` — opcode `$9B`, 2 bytes, 7 cycles, stores `A`, sets no flags
- `MOV (zp)+, #imm` — opcode `$AB`, 3 bytes, 8 cycles, sets no flags
- `MOV zp, (zp)+` — opcode `$BB`, 3 bytes, 9 cycles, sets no flags

The access SHALL use the pointer value from before the increment.

#### Scenario: Access uses the pre-increment address

- **WHEN** the pair at `$40` holds `$1000` and `LDA ($40)+` executes
- **THEN** `A` holds the contents of `$1000` and the pair holds `$1001`

#### Scenario: Increment carries across a page boundary

- **WHEN** the pair at `$40` holds `$10FF` and `LDA ($40)+` executes
- **THEN** the pair holds `$1100`

#### Scenario: Index registers are preserved

- **WHEN** any post-increment form executes
- **THEN** `X` and `Y` are unchanged

### Requirement: Pointer Advance By Stride

The CPU SHALL provide `ADDW (zp), #imm8` (opcode `$CB`, 3 bytes, 9 cycles),
adding an unsigned 8-bit stride to a zero-page pointer pair with carry into the
high byte, without using or modifying `A`, `X` or `Y`.

#### Scenario: Stride carries into the high byte

- **WHEN** the pair at `$40` holds `$10F0` and `ADDW ($40), #16` executes
- **THEN** the pair holds `$1100`

### Requirement: Block Copy

The CPU SHALL provide `CPY (dst), (src), #imm` (opcode `$DB`, 4 bytes) copying
an 8-bit count of bytes, and `CPYW (dst), (src), zp` (opcode `$EB`, 4 bytes)
taking a 16-bit count from a zero-page pair. Both SHALL cost approximately 6
cycles per byte after a fixed setup.

Both instructions SHALL update their pointer and count operands in memory as
they progress, leaving the pointers past the end of their regions and the count
at zero on completion. A count of zero SHALL copy nothing.

#### Scenario: Region is copied

- **WHEN** `CPY` copies 32 bytes from a source region to a destination region
- **THEN** the destination holds the source's bytes in order

#### Scenario: Operands reflect completion

- **WHEN** a copy of 32 bytes completes
- **THEN** both pointers have advanced by 32 and the count operand is zero

#### Scenario: Zero count is a no-op

- **WHEN** `CPYW` executes with a count of zero
- **THEN** no memory is written and both pointers are unchanged

### Requirement: Block Fill

The CPU SHALL provide `FILL (dst), #imm, zp` (opcode `$FB`, 4 bytes), writing an
immediate byte to a region whose 16-bit length is taken from a zero-page pair,
at approximately 4 cycles per byte after a fixed setup, updating its pointer and
count operands as it progresses.

#### Scenario: Region is filled

- **WHEN** `FILL` writes `$00` over a 64-byte region
- **THEN** every byte of the region holds `$00`

#### Scenario: Registers are preserved

- **WHEN** `FILL` completes
- **THEN** `A`, `X` and `Y` are unchanged

### Requirement: Interruptible Block Operations

Block copy and fill SHALL be interruptible. When an interrupt is taken during
one of these instructions, the CPU SHALL have committed its progress to the
pointer and count operands and SHALL set the pushed return address to the block
instruction itself, so that `RTI` resumes the operation rather than restarting
it or skipping the remainder.

#### Scenario: Copy resumes after an interrupt

- **WHEN** an interrupt is taken partway through a 256-byte copy and the handler
  returns with `RTI`
- **THEN** the copy completes and the destination holds exactly the source's 256
  bytes

#### Scenario: Interrupt at any point is safe

- **WHEN** a copy is interrupted at each successive cycle offset across its
  duration, with the handler returning normally each time
- **THEN** every run produces the same final memory contents as an
  uninterrupted copy

#### Scenario: Interrupt latency is bounded

- **WHEN** an interrupt is asserted during a block operation
- **THEN** it is taken within the per-byte step time, not at the end of the
  whole operation
