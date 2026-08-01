## ADDED Requirements

### Requirement: No Compatibility Memory-map Module

Production Celeste SHALL NOT contain or include
`src/celeste/memmap.inlay.asm`. Stable storage SHALL be described by semantic
layouts, overlays, pools and locations, while target ISA register definitions
remain in the selected target prelude.

#### Scenario: Production source is audited

- **WHEN** the migration is complete
- **THEN** the compatibility file is absent and the root contains no raw or
  semantic include naming it

### Requirement: Scoped Memory Ownership

Celeste physical locations and constants SHALL belong to the narrowest
namespace that owns their meaning. Shared calling-convention locations SHALL
live under `Machine`; subsystem state SHALL live under `Game`, `Objects`,
`Collision`, `Draw`, `Fx`, `Fixed`, `Room`, `Audio` or `Platform` as
applicable. Cross-module access SHALL use exported qualified names.

#### Scenario: Collision scratch is referenced

- **WHEN** collision code consumes its box coordinates or tile-walk scratch
- **THEN** those locations resolve within `Collision` rather than through
  global `c_*` aliases

#### Scenario: Input mask is referenced

- **WHEN** player or game code tests the jump button
- **THEN** it uses an exported `Platform.Input` value rather than global
  `BTN_JUMP`

#### Scenario: Shared receiver location is referenced

- **WHEN** object-kind procedures use the common receiver location
- **THEN** their placement resolves through the declared shared machine
  convention rather than an undeclared global target symbol

### Requirement: Typed Stable-memory Access

Celeste SHALL access persistent game state, video and PSG MMIO, room/tile
storage, effects storage, object storage, row pointers, overlay shadow and
framebuffer through their declared semantic locations or overlays wherever an
equivalent target operation exists.

#### Scenario: Game clock advances

- **WHEN** the frame counter is read, compared, incremented or cleared
- **THEN** source names `GameState.frames` through the fixed game-state overlay

#### Scenario: Video control is initialized

- **WHEN** room setup writes video control, clipping or overlay color
- **THEN** source names the corresponding `VideoRegisters` field

#### Scenario: Effect array is indexed

- **WHEN** an effect loop accesses a cloud or particle component
- **THEN** source names an explicitly offset `FxStorage` array with its
  physical index

#### Scenario: Overlay is copied by page

- **WHEN** shadow bytes are copied to the write-only framebuffer
- **THEN** source uses corresponding explicit page-view fields over the two
  existing regions

### Requirement: Single Source of Layout Truth

Celeste SHALL NOT repeat an address, capacity, stride or field offset as a raw
numeric alias when that value is derivable from a declared overlay, pool,
array or layout query. Explicit address assertions SHALL pin externally fixed
hardware and RAM boundaries.

#### Scenario: Object capacity is consumed

- **WHEN** object iteration needs the slot count
- **THEN** it derives the value from the typed object pool rather than
  `OBJ_MAX`

#### Scenario: Hair count is consumed

- **WHEN** hair traversal needs its node count
- **THEN** it uses `countof` on the declared hair array rather than
  `HAIR_NODES`

#### Scenario: Fixed hardware address changes

- **WHEN** a video, PSG, zero-page or RAM overlay no longer matches its
  established address
- **THEN** a compile-time assertion fails before target assembly

### Requirement: Bounded Raw Memory Exceptions

Any remaining raw numeric memory operand SHALL belong to a reviewed category
whose machine-state contract cannot be expressed by the implemented semantic
operations. Conformance SHALL enumerate those sites and reject additions.

#### Scenario: Semantic operation is available

- **WHEN** conformance finds a raw alias or numeric address with an equivalent
  typed location or overlay operation
- **THEN** the build fails with the source location and required semantic form

#### Scenario: Raw operation preserves extra behavior

- **WHEN** a site depends on flags, volatility, page encoding or physical
  clobbers absent from the semantic operation
- **THEN** it remains raw with an inline exception and a frozen conformance
  count

### Requirement: Legacy Alias Elimination

Production Celeste source SHALL contain no references to the global MMIO,
zero-page, game-state, object, collision, drawing, effects or fixed-region
aliases formerly declared by `memmap.inlay.asm`.

#### Scenario: Legacy alias reappears

- **WHEN** source introduces a former name such as `SPR_CTRL`, `BTN_JUMP`,
  `c_x`, `frames`, `CL_XL`, `OBJPOOL` or `OVLSHADOW`
- **THEN** conformance rejects it and identifies its typed or scoped owner
