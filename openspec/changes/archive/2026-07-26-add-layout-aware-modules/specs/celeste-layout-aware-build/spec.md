## ADDED Requirements

### Requirement: Typed Celeste Module Migration
The layout-aware Celeste build SHALL convert every eligible direct byte
`lda`/`sta` through `pObj` or `pOth` from a legacy `O_*` displacement to an
explicit typed field operand in generated layout-owned modules. It SHALL leave
non-equivalent indexed sequences unchanged and SHALL NOT edit
`src/celeste/`.

#### Scenario: Direct field operation is eligible
- **WHEN** a generated Celeste module contains
  `lda (pObj), #O_HBW`
- **THEN** frontend input contains
  `lda [pObj + CelesteObject.hitbox.w]` and emits identical instruction bytes

#### Scenario: High fixed-point byte is eligible
- **WHEN** an operation uses `#O_SPDX+1`
- **THEN** migration uses `CelesteObject.speed_x.integer`

#### Scenario: Indexed operation is not equivalent
- **WHEN** source loads Y with an `O_*` value and uses `(pObj),y`
- **THEN** the generated module preserves that raw instruction sequence

### Requirement: Migrated Full-ROM Equivalence
The conformance gate SHALL require a nonzero expected typed-operation count
across generated Celeste modules and SHALL compare all 65,536 output bytes
against the direct current source.

#### Scenario: Generated modules are accepted
- **WHEN** all eligible direct operations have been translated and assembled
- **THEN** the typed-operation count matches the migration manifest and the
  complete ROM is byte-for-byte identical
