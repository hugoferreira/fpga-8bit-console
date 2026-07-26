## MODIFIED Requirements

### Requirement: Celeste Structured Address and Procedure Migration
The generated layout-owned Celeste modules SHALL exercise pool address
materialisation, unified procedure-member declarations, target convention
assignment and typed returns without editing `src/celeste/`. Each migrated
construct SHALL have an exact expected count and retain the current machine
bytes.

#### Scenario: Object pointer routine is migrated
- **WHEN** the generated object module is prepared
- **THEN** the existing object-address routine is expressed through a typed
  pool address operation, `using console6502`, a convention-assigned scalar
  input and an explicit `return in pObj` contract

#### Scenario: Full game is rebuilt
- **WHEN** unified procedure locations and invocation support are enabled in
  the Celeste layout build
- **THEN** the resulting 65,536-byte ROM is byte-for-byte identical to the
  direct current source

#### Scenario: No exact game migration exists
- **WHEN** a new frame-copy or invocation lowering has no existing Celeste
  sequence with identical bytes
- **THEN** it remains in the focused equivalence fixture rather than changing
  `src/celeste/` or perturbing the ROM
