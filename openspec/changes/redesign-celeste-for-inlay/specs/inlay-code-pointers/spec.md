## ADDED Requirements

### Requirement: Target-sized Code Pointer Type

`codeptr` SHALL be a distinct primitive storage type for executable addresses.
Its width and byte order SHALL be declared by the selected target independently
of ordinary data-pointer representation. Layout queries and aggregate layout
SHALL use that target-provided storage width.

#### Scenario: Code pointer participates in layout

- **WHEN** a structure declares `handler : codeptr` for `console6502`
- **THEN** the field occupies two little-endian storage units

### Requirement: Direct Procedure Code-pointer Data

The frontend SHALL accept `data codeptr PROCEDURE` with one or more
comma-separated, visible procedure names. Each entry SHALL lower as one
complete target code-pointer relocation using the target's declared width and
byte order. The frontend SHALL retain `low(...)` and `high(...)` byte forms
for deliberately split tables.

#### Scenario: Reset vectors are declared

- **WHEN** Celeste emits `data codeptr Platform.reset`
- **THEN** `console6502` emits one 16-bit little-endian relocation to the
  target symbol for `Platform.reset`

#### Scenario: Multiple code pointers are declared

- **WHEN** source emits `data codeptr Player.init, Spawn.init`
- **THEN** each visible procedure produces one complete relocation in source
  order

#### Scenario: Unknown code pointer target is used

- **WHEN** a `data codeptr` entry names an undeclared procedure
- **THEN** translation fails before target assembly

#### Scenario: Split table remains intentional

- **WHEN** dispatch requires parallel low-byte and high-byte tables
- **THEN** source continues to use `data u8 low(...)` and
  `data u8 high(...)` rather than `codeptr`
