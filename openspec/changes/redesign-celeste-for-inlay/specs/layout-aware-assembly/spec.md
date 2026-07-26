## ADDED Requirements

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

The frontend SHALL provide an explicit operation that places a resolved field
offset into a declared physical target location. The operation SHALL perform no
memory access and SHALL publish target clobbers.

#### Scenario: Offset is loaded into an index register

- **WHEN** source requests
  `offset y, CelesteObject.core.kind`
- **THEN** the target receives the resolved displacement and physical
  destination `y`

#### Scenario: Offset does not fit

- **WHEN** the resolved displacement cannot be represented by the selected
  target location or operation
- **THEN** lowering fails with the actual displacement and supported range

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
