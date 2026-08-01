## ADDED Requirements

### Requirement: Target-default Calling Convention

Every selected target environment SHALL declare one default calling
convention. A procedure without a `using` clause SHALL use that convention.
The source SHALL use `using NAME` only when a procedure deliberately overrides
the target default; it SHALL NOT repeat the default convention explicitly.

Convention resolution SHALL be deterministic: an explicit procedure override
takes precedence over the target default. Translation SHALL fail when neither
exists rather than inferring parameter, return or frame behavior from the
target name.

#### Scenario: Ordinary procedure uses the target default

- **WHEN** the `console6502` target declares its normal convention as default
  and source declares `proc Player.update`
- **THEN** parameter assignment, returns, frames and invocation use that
  convention without `using console6502`

#### Scenario: Procedure overrides the default

- **WHEN** source declares `proc interrupt using console6502_interrupt naked`
- **THEN** that procedure uses the named override while other procedures
  continue to use the target default

#### Scenario: Redundant default is written explicitly

- **WHEN** source declares an ordinary procedure with
  `using console6502` while `console6502` is the target default
- **THEN** translation rejects the redundant clause and directs the author to
  omit it

#### Scenario: Target has no default

- **WHEN** a procedure omits `using` and the selected target environment has
  not declared a default convention
- **THEN** translation fails before parameter or frame locations are assigned

### Requirement: Qualified Compile-time Operand Values

Qualified constants, enum members and layout properties SHALL be usable in
frontend-owned semantic operands without exposing generated target symbols.
Resolution SHALL retain width, signedness and source ownership.

#### Scenario: Enum member initializes a physical byte

- **WHEN** source assigns `ObjectKind.smoke` to a declared byte location
- **THEN** lowering receives its resolved byte value without an intermediate
  `T_SMOKE` definition

#### Scenario: Layout property is materialized

- **WHEN** source requests the offset of
  `CelesteObject.payload.player.dash_time`
- **THEN** the frontend provides the resolved field displacement rather than a
  generated `O_*` or `__la_*` name

### Requirement: Qualified Procedure-address Data

The frontend SHALL support bounded data declarations containing low byte, high
byte or complete target addresses of declared procedures. The backend SHALL
receive the resolved procedure identity and relocation part.

#### Scenario: Split dispatch table is declared

- **WHEN** source emits `low(Player.update)` and `high(Player.update)` into
  separate byte tables
- **THEN** both entries relocate to the target symbol selected for the same
  qualified procedure

#### Scenario: Unknown procedure address is used

- **WHEN** a data declaration names an undeclared qualified procedure
- **THEN** translation fails before target assembly

### Requirement: Typed Field-offset Materialisation

The frontend SHALL provide prefix compile-time layout-query operators
`offset`, `sizeof`, `alignof`, `countof` and `strideof`. A query SHALL bind to
the qualified layout path immediately following it and SHALL be usable as a
semantic `mov` source without a target-specific immediate marker. A query
SHALL perform no memory access.

`offset` SHALL place a resolved field displacement into the declared physical
destination and SHALL publish target clobbers. `countof` and `strideof` SHALL
reject scalar fields. Layout paths SHALL NOT implicitly select one of these
properties.

#### Scenario: Offset is loaded into an index register

- **WHEN** source requests
  `mov y, offset CelesteObject.core.kind`
- **THEN** the target receives the resolved displacement and physical
  destination `y`

#### Scenario: Offset does not fit

- **WHEN** the resolved displacement cannot be represented by the selected
  target location or operation
- **THEN** lowering fails with the actual displacement and supported range

#### Scenario: Array layout is queried

- **WHEN** source requests
  `mov count, countof CelesteObject.payload.hair.hair`
- **THEN** lowering receives the array element count without a generated
  property symbol

#### Scenario: Legacy offset statement is used

- **WHEN** source uses `offset y, CelesteObject.core.kind`
- **THEN** translation rejects it in favor of the prefix query operand

### Requirement: Typed Word Field Transfers

The frontend SHALL support explicit load and store operations between a
declared physical word location and a typed `u16`, `i16` or fixed-width
two-storage-unit field. It SHALL preserve byte order and reject scalar-width
or alignment mismatches.

#### Scenario: Fixed-point field is loaded

- **WHEN** a two-byte `Fixed8_8` field is loaded from `self` into physical word
  location `w0`
- **THEN** the backend receives the pointer base, field displacement, byte
  order, destination and required scratch/clobber contract

#### Scenario: Byte field is used as a word

- **WHEN** a typed word operation names a one-byte field
- **THEN** translation fails with an access-width diagnostic

### Requirement: Typed Word Arithmetic

The frontend SHALL support explicit add, subtract and compare operations over
declared physical word locations and compatible immediate or physical
operands. The target SHALL define flag semantics and clobbers; the frontend
SHALL NOT infer a compound expression tree.

#### Scenario: Custom word addition is selected

- **WHEN** the console6502 target adds physical word `w1` to accumulator pair
  `ab`
- **THEN** lowering selects the documented custom word operation and reports
  its weakest flag contract

#### Scenario: Unsupported word operand is used

- **WHEN** the target has no registered word operation for the physical operand
  combination
- **THEN** translation rejects it rather than synthesizing an undeclared
  register allocation

### Requirement: Typed Byte Read-modify-write

The frontend SHALL support explicit increment, decrement and mask/update
operations on typed byte fields when a target registers a deterministic
lowering. Lowering SHALL state whether the access is atomic, volatile and which
physical resources it clobbers.

#### Scenario: Object timer is decremented

- **WHEN** source decrements a typed byte timer through `self`
- **THEN** the backend emits its registered sequence and preserves the
  documented read-modify-write semantics

#### Scenario: Volatile register is modified

- **WHEN** a read-modify-write operation targets a volatile MMIO overlay field
  without a target operation that preserves volatile semantics
- **THEN** translation fails rather than replacing it with an unsafe sequence

### Requirement: Indexed Fixed-overlay Access

The frontend SHALL accept one physical runtime index on an array member of a
fixed overlay. It SHALL resolve the fixed base, field displacement, element
stride, access width and volatility before lowering.

#### Scenario: PSG channel command is indexed

- **WHEN** source stores a byte to `psg.channels[y]`
- **THEN** the target receives the PSG base, channel-bank displacement, unit
  stride and physical index `y`

#### Scenario: Target cannot encode overlay index

- **WHEN** no registered target sequence can address the indexed overlay
  without unavailable scratch
- **THEN** translation fails without silently clobbering live state

### Requirement: Explicit Custom-operation Adoption

Typed semantic operations and target-specific custom or pseudo operations SHALL
remain explicit in source. The frontend SHALL NOT optimize arbitrary raw
instruction sequences by pattern matching.

#### Scenario: Programmer selects MOV

- **WHEN** source uses the target-specific `mov` operation
- **THEN** customasm receives that operation or its documented target lowering
  without the frontend reconstructing an accumulator sequence

#### Scenario: Legacy sequence remains

- **WHEN** source contains raw instructions equivalent to a custom operation
- **THEN** the frontend preserves them as written and conformance may report
  the missed adoption

### Requirement: Counted Accumulator Shifts and Rotates

The `console6502` target SHALL provide counted pseudo-operations `asl a, N`,
`lsr a, N`, `rol a, N` and `ror a, N` for the implicit accumulator forms. `N`
SHALL be a positive assembly-time integer within the target's documented
expansion limit, which is 8. Lowering SHALL be exactly equivalent to spelling
the corresponding ordinary instruction `N` consecutive times.

The explicit `a` operand SHALL be required. The shorter `asl N` spelling is
prohibited because it is not expressible without ambiguity: `asl {zaddr: u8}`
already matches a bare expression, and customasm v0.14.1 resolves the resulting
overlap by silently preferring the smaller encoding, assembling `asl 3` to
`06 03` — a read-modify-write of zero page address 3 — with no diagnostic.

The accumulator result and final processor flags SHALL equal the expanded
sequence. Counted rotates SHALL feed each repetition's carry output into the
next repetition. The initial slice SHALL NOT interpret an address operand as a
count or add counted memory forms.

Each accepted count SHALL be declared by its own rule rather than computed from
a repeated constant, so that the accepted range is structural. A computed slice
zero-extends beyond its width and would emit `00` (BRK) followed by eight
shifts for `asl a, 9`.

#### Scenario: Accumulator is shifted three times

- **WHEN** source contains `asl a, 3`
- **THEN** customasm emits the same bytes and final machine state as three
  consecutive accumulator `asl` instructions

#### Scenario: Rotate consumes and chains carry

- **WHEN** source contains `ror a, 4`
- **THEN** the first rotation consumes the incoming carry and each subsequent
  rotation consumes the carry produced by the previous rotation

#### Scenario: Count is one

- **WHEN** source contains `lsr a, 1`
- **THEN** it is accepted and emits the same instruction as plain `lsr`

#### Scenario: Count is invalid

- **WHEN** a counted shift or rotate uses zero, a negative value, a
  non-constant value or a count above the target expansion limit
- **THEN** assembly fails, citing the offending source line and therefore the
  supplied count; the accepted range is carried by the rule documentation
  rather than the diagnostic, because customasm reports an unmatched
  instruction as `no match found for instruction` and offers no hook for a
  rule-supplied message

#### Scenario: Memory form is attempted

- **WHEN** source attempts to combine a memory operand and repetition count
- **THEN** the counted pseudo-operation rejects it rather than guessing which
  operand is the count
