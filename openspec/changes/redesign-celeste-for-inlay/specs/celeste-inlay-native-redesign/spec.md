## ADDED Requirements

### Requirement: Pure Celeste Layout Module

The production Celeste layout module SHALL contain nominal layouts, enums,
overlays, typed locations, pools and compile-time assertions only. It SHALL NOT
include ISA rule definitions or define compatibility `T_*`, `O_*` or generated
`__la_*` aliases.

#### Scenario: Object field offset is consumed

- **WHEN** game code needs an object field displacement
- **THEN** it uses a prefix `offset` query as a semantic operand or a typed
  operation directly

### Requirement: Scoped Generated Assets and Effects

Generated graphics declarations and effects constants SHALL live in `Gfx` and
`Fx` namespaces. Each module SHALL explicitly export its public data and entry
points while retaining implementation constants privately.

#### Scenario: Player sprite is referenced

- **WHEN** player drawing needs the player sprite
- **THEN** it names an exported qualified `Gfx` member

#### Scenario: Effects capacity is internal

- **WHEN** another module attempts to reference a private cloud or particle
  capacity constant
- **THEN** namespace visibility rejects the reference

### Requirement: Typed Celeste Memory Regions

Celeste SHALL describe video, PSG, palette, sprite staging, tile map, overlay
framebuffer, zero-page working locations and persistent game state with nominal
layouts or typed overlays wherever the storage has a stable shape. Raw address
constants SHALL remain only where required by target bank/vector directives or
unsupported storage semantics.

#### Scenario: Indexed PSG channel is written

- **WHEN** audio selects a runtime PSG channel
- **THEN** source uses the typed PSG channel array rather than `PSG_CH,y`

#### Scenario: Persistent state is accessed

- **WHEN** game code reads or writes clock, title or restart state
- **THEN** the source path identifies the owning game-state view

### Requirement: Namespaced Fixed-point Library

Fixed-point comparison, sign, absolute value and approach behavior SHALL be
provided through a `Fixed` namespace with declared physical contracts. Eligible
word arithmetic SHALL use the custom CPU word operations rather than expanded
byte chains or global helper calls.

#### Scenario: Value approaches a target

- **WHEN** player physics invokes fixed-point approach
- **THEN** it calls the exported `Fixed` operation with explicit physical word
  locations and no unqualified global helper name

### Requirement: Scoped Object-pool API

Object allocation, destruction, traversal, movement and lifecycle dispatch
SHALL be owned by an `Objects` namespace. Dispatch metadata SHALL be emitted
from qualified procedure addresses and SHALL NOT contain backend-mangled symbol
spellings in source.

#### Scenario: Lifecycle table is emitted

- **WHEN** the object-kind dispatch tables are assembled
- **THEN** their entries derive from qualified `Player`, `Spawn`, `Smoke` and
  `Title` procedure identities

#### Scenario: Object is destroyed

- **WHEN** a lifecycle procedure frees its receiver
- **THEN** it invokes or tail-calls the scoped object API with an explicit
  receiver contract

### Requirement: Structured Object-kind Procedures

Player, spawn, smoke and title behavior SHALL expose init, update and draw
procedures and SHALL scope helpers and constants under the owning object-kind
namespace. Large lifecycle bodies SHALL be split into named procedures when
their physical inputs, outputs and clobbers can be declared without hidden
value preservation. Public lifecycle procedures SHALL carry the `export`
modifier on their declarations. Ordinary Celeste procedures SHALL rely on the
`console6502` target's default calling convention and SHALL omit redundant
`using console6502` clauses.

#### Scenario: Player update is reviewed

- **WHEN** the production player module is inspected
- **THEN** input, environment, horizontal motion, jump/dash, vertical motion
  and animation responsibilities are represented by scoped procedures or
  explicitly documented inseparable blocks

#### Scenario: Player physics constant is referenced

- **WHEN** code uses maximum run speed or dash acceleration
- **THEN** it resolves a private qualified `Player` constant rather than a
  global `MAXRUN`-style name

#### Scenario: Player lifecycle is declared

- **WHEN** the `Player` namespace defines its public initialization entry
- **THEN** source spells it `export proc init` without a detached `export init`
  or redundant `using console6502`

#### Scenario: Procedure needs a non-default convention

- **WHEN** a Celeste target-boundary procedure deliberately requires a
  convention other than the `console6502` default
- **THEN** its declaration names that override with `using` and conformance
  records why the default is unsuitable

### Requirement: Minimal Main Composition Root

`main.inlay.asm` SHALL be limited to target selection, bank/layout composition,
module inclusion, reset/vector binding and transfer to the top-level game
entry. Platform startup and services SHALL belong to `Platform`; title/play
state and frame orchestration SHALL belong to `Game`.

#### Scenario: Main entry is inspected

- **WHEN** a maintainer opens `main.inlay.asm`
- **THEN** unrelated palette upload, sheet upload, input, title and frame-update
  routine bodies are absent

### Requirement: Visible Custom-CPU Adoption

The production source SHALL use existing custom move, pointer, carry-normalized
arithmetic, word and pseudo operations at every site whose documented contract
matches the required behavior. Conformance SHALL inventory both adopted
operations and mechanically eligible legacy sequences.

#### Scenario: Eligible accumulator move remains

- **WHEN** conformance finds a raw load/store pair that the adopted `mov`
  contract exactly replaces
- **THEN** the redesign gate fails with the source location

#### Scenario: Legacy sequence has different semantics

- **WHEN** an apparent sequence relies on flags, accumulator value, volatility
  or clobbers not preserved by the custom operation
- **THEN** it remains raw and is recorded as an explained exception

### Requirement: Redesign Resource Improvement

The final redesigned image SHALL fit the existing ROM and RAM maps, SHALL
reduce executable instruction count and manual object-offset setup from the
recorded Phase-A baseline, and SHALL publish pre/post custom-operation adoption
and footprint measurements.

#### Scenario: Final metrics are evaluated

- **WHEN** the redesign completes
- **THEN** its report identifies the baseline, final values and deltas for
  executable bytes, instruction count, object-offset setup and each custom-op
  family

### Requirement: Current Gameplay Scope Is Preserved

The redesign SHALL preserve all gameplay behavior implemented by the Phase-A
port. Adding object kinds, rooms or effects absent from that baseline SHALL
require a separate parity change and SHALL NOT be silently mixed into
structural acceptance.

#### Scenario: Structural rewrite is tested

- **WHEN** the redesigned game runs the Phase-A functional scenarios
- **THEN** boot, title transition, physics, collision, dash, smoke, rendering,
  audio, HUD and room transitions retain their established observable results
