## MODIFIED Requirements

### Requirement: Multi-source Semantic Compilation
The portable frontend SHALL compile a deterministic graph of replayable source
modules as one semantic program without requiring their bytes or line records
to be flattened into one contiguous buffer. Every pass SHALL retain stable
source ids and original line numbers. Existing single-stream callers SHALL
retain their behavior through a bounded one-module replay adapter.

#### Scenario: Declaration and use span modules
- **WHEN** one module declares a nominal layout and another module uses it in a
  typed operand
- **THEN** all declaration passes complete before cross-module resolution and
  the graph resolves as one semantic program

#### Scenario: Total source exceeds one-module capacity
- **WHEN** the sum of valid module bytes exceeds 65,535 while every individual
  module and semantic table fits its declared capacity
- **THEN** translation succeeds without a total flattened-source-capacity
  diagnostic

#### Scenario: Legacy single input is compiled
- **WHEN** a caller supplies the existing streaming input without a module
  resolver
- **THEN** it is replayed as one bounded source and all events retain the
  input's source id as before

### Requirement: Typed Physical Locations

The frontend SHALL allow a source name to be declared as a typed alias for a
target physical location. A location SHALL accept scalar, pointer and
`codeptr` types and MAY bind to an explicit compile-time physical address.
Locations SHALL participate in lexical namespaces and procedure placement
SHALL accept qualified location names. A typed location SHALL NOT be a virtual
register, SHALL NOT imply storage allocation and SHALL NOT cause its value to
be preserved.

#### Scenario: Zero-page pointer pair receives a type and address

- **WHEN** source declares
  `location object : ptr CelesteObject at $10`
- **THEN** field operands based on `object` resolve against `CelesteObject` and
  the target receives physical address `$10` with its pointer width

#### Scenario: Code-pointer location is declared

- **WHEN** source declares `location function : codeptr at $14`
- **THEN** placement and invocation use the target's code-pointer width and
  byte order rather than treating the location as a byte

#### Scenario: Qualified location is used for placement

- **WHEN** a procedure declares
  `self : ptr CelesteObject in Machine.object`
- **THEN** `Machine.object` resolves lexically and supplies the procedure
  member's physical location

#### Scenario: Base type disagrees with explicit field type

- **WHEN** a location typed as `ptr NemoObject` is used with a field path
  explicitly rooted at `CelesteObject`
- **THEN** translation fails with a base-type mismatch

#### Scenario: Location declaration emits no storage

- **WHEN** a typed fixed-address location is declared
- **THEN** the generated target output may define a symbolic alias but contains
  no allocation, clearing or initialization solely for that declaration

#### Scenario: Physical views overlap

- **WHEN** two explicitly addressed locations name the same storage for
  different subsystem roles
- **THEN** both remain non-owning views and the frontend does not infer
  exclusivity, liveness or automatic preservation

## ADDED Requirements

### Requirement: Fixed-overlay Address Materialization

The frontend SHALL extend semantic `address` to fixed overlays and their field
paths. It SHALL resolve the overlay base plus field displacement and publish
the destination location, target address width and relocation without reading
the field.

#### Scenario: Tile-map address is loaded

- **WHEN** source requests `address destination, tile_map.patterns`
- **THEN** the backend receives the fixed tile-map base, the `patterns`
  displacement and the declared physical pointer destination

#### Scenario: Address destination has the wrong width

- **WHEN** an overlay address is materialized into a byte or incompatible
  code-pointer location
- **THEN** translation fails with the source and required address widths

#### Scenario: Backend cannot materialize the address

- **WHEN** the selected target has no registered sequence for the destination
  and relocation
- **THEN** translation fails rather than inventing scratch storage

### Requirement: Evidenced Fixed-overlay Operations

The frontend SHALL support registered fixed-overlay byte operations needed by
the Celeste corpus: load, store, target-defined `mov`, accumulator compare,
compare/test-and-branch, increment, decrement, mask/update and one
physical-index unit-stride access. Each operation SHALL retain base,
displacement, access width, volatility, index, scratch, flags and clobbers.

#### Scenario: Persistent state is incremented

- **WHEN** source increments `[game + GameState.frames]`
- **THEN** the backend receives a volatile-safe or nonvolatile fixed-overlay
  byte RMW event for the resolved absolute address

#### Scenario: MMIO value is compared

- **WHEN** source compares the accumulator with
  `[video + VideoRegisters.frame]`
- **THEN** the backend receives a volatile byte compare and preserves the
  target's documented flag behavior

#### Scenario: Indexed effects field is accessed

- **WHEN** source loads `[Fx.storage + FxStorage.cloud_x_low[x]]`
- **THEN** lowering receives its fixed base, explicit field displacement,
  unit stride and physical index `x`

#### Scenario: Typed form changes machine state

- **WHEN** no registered semantic operation preserves the raw sequence's
  volatility, flags, scratch or clobber contract
- **THEN** translation rejects that typed form and the source retains an
  explicit reviewed raw operation

### Requirement: Explicit Fixed-storage Views

Structures, unions, overlays and fixed-address locations SHALL permit multiple
declared views over the same memory region. Such views SHALL describe access
shape only and SHALL NOT allocate, initialize, copy or synchronize storage.

#### Scenario: Framebuffer has byte and page views

- **WHEN** the same framebuffer address is declared as a linear byte overlay
  and as explicit 256-byte page fields
- **THEN** both paths resolve to the same underlying addresses without
  creating a second buffer

#### Scenario: Structure-of-arrays effects storage is declared

- **WHEN** `FxStorage` declares unit-stride arrays at explicit offsets
- **THEN** indexed field access preserves the existing structure-of-arrays
  addresses rather than imposing an array-of-structures layout
