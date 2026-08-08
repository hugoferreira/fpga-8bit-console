## ADDED Requirements

### Requirement: Value-keyed Method Table Declaration
The frontend SHALL accept a `method_table` declaration naming a nominal
enum, an explicit inclusive value domain over that enum, and one or more
columns. Rows SHALL be keyed by enum member value within the domain, not
by declaration order. The declaration SHALL publish the domain's low bound
as a queryable bias property. Enum members with duplicate values inside
the domain SHALL be rejected.

#### Scenario: Domain excludes a zero sentinel
- **WHEN** `method_table lifecycle : ObjectKind[player .. mover]` declares
  an `init : code` slot and `ObjectKind.free = 0` lies outside
  `[player .. mover]`
- **THEN** the emitted tables contain no row for `free` and
  `lifecycle.bias` equals the value of `ObjectKind.player`

#### Scenario: Aliased member rejected
- **WHEN** the enum contains two members with equal values inside the
  declared domain
- **THEN** assembly fails with a stable-code diagnostic

### Requirement: Total Coverage With Column-typed Absence
Every value in the declared domain SHALL be assigned in every column or
explicitly marked `absent`. `absent` SHALL be legal only in code-pointer
columns, where it emits a zero entry; value columns SHALL require an
explicit value for every row. A domain value neither assigned nor marked
absent SHALL be a diagnostic.

#### Scenario: Missing row detected
- **WHEN** a new enum member is added inside the domain and the table is
  not updated
- **THEN** assembly fails naming the uncovered member and column

#### Scenario: Absent rejected in a value column
- **WHEN** a `u8` column row is marked `absent`
- **THEN** assembly fails with a stable-code diagnostic

### Requirement: Generated Split Tables Under Qualified Names
Code-pointer columns SHALL emit split low/high byte tables under generated
qualified names in enum-value order over the domain; value columns SHALL
emit one byte table each. Generated table labels SHALL resolve in raw
indexed operands, including with constant offsets, so consumers can index
with the published bias.

#### Scenario: Generated tables byte-match handwritten predecessors
- **WHEN** a method table reproduces an existing handwritten lo/hi table
  pair with identical procedure identities and row order
- **THEN** the generated tables are byte-identical to the handwritten ones

#### Scenario: Bias-relative indexed consumption
- **WHEN** raw source reads `lda lifecycle_init_lo - lifecycle.bias, x`
- **THEN** the operand resolves and assembles to the same bytes as the
  handwritten `-1, x` spelling for a bias of one
