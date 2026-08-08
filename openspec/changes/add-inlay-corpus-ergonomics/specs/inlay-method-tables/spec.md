## ADDED Requirements

### Requirement: Value-keyed Method Table Declaration
The frontend SHALL accept a `method_table NAME : ENUM[LOW .. HIGH]`
declaration naming a nominal enum and an explicit inclusive value domain.
Body lines SHALL use the language's declaration shapes with no per-line
keywords: `name : u8` declares a per-kind attribute slot, `name : code`
declares a method slot, and a bare `member = value, ...` line assigns one
enum member's slots positionally in slot declaration order. Slot lines
SHALL precede member lines. Entries SHALL be keyed by enum member value
within the domain, not by declaration order. The declaration SHALL
publish the domain's low bound as the queryable `NAME.bias` property.
Enum members with duplicate values inside the domain SHALL be rejected.

#### Scenario: Domain excludes a zero sentinel
- **WHEN** `method_table lifecycle : ObjectKind[player .. platform]`
  declares an `init : code` slot and `ObjectKind.free = 0` lies outside
  `[player .. platform]`
- **THEN** the emitted tables contain no entry for `free` and
  `lifecycle.bias` equals the value of `ObjectKind.player`

#### Scenario: Member entries key by value, not declaration order
- **WHEN** member lines are declared out of enum-value order
- **THEN** the emitted tables are ordered by enum member value over the
  domain

#### Scenario: Aliased member rejected
- **WHEN** the enum contains two members with equal values inside the
  declared domain
- **THEN** assembly fails with a stable-code diagnostic

### Requirement: Total Coverage With Slot-typed Absence
Every value in the declared domain SHALL have exactly one member line,
and every member line SHALL supply one value per declared slot. `absent`
SHALL be legal only in `code` slots, where it emits a zero entry; `u8`
slots SHALL require an explicit value. A domain value with no member
line, and a duplicate member line, SHALL each be a diagnostic.

#### Scenario: Missing member detected
- **WHEN** a new enum member is added inside the domain and the table is
  not updated
- **THEN** assembly fails naming the uncovered value

#### Scenario: Absent rejected in a value slot
- **WHEN** a `u8` slot cell is `absent`
- **THEN** assembly fails with a stable-code diagnostic

### Requirement: Table-scoped Generated Labels
Slot tables SHALL emit at the declaration's source position under labels
scoped by the table name: a `code` slot emits split
`TABLE_slot_lo`/`TABLE_slot_hi` byte tables through the same
procedure-address events as `data u8 low(...)` and `high(...)`, with
inline procedures rejected; a `u8` slot emits one `TABLE_slot` byte
table whose cells are compile-time expressions in the byte range.

#### Scenario: Generated tables byte-match handwritten predecessors
- **WHEN** a method table reproduces an existing handwritten lo/hi table
  pair with identical procedure identities and entry order
- **THEN** the generated tables are byte-identical to the handwritten
  ones

#### Scenario: Bias-relative indexed consumption
- **WHEN** raw source reads `lda lifecycle_init_lo - lifecycle.bias, x`
  with a bias of one
- **THEN** the operand resolves and assembles to the same bytes as the
  handwritten `-1, x` spelling
