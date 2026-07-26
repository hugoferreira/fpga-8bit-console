## ADDED Requirements

### Requirement: Byte-Preserving Refactor Boundary

This change SHALL preserve every byte of the established 65,536-byte Celeste
ROM. Refactors that select different custom-CPU instructions, remove
target-facing compatibility symbols, or reorganize control flow SHALL be
performed by a separate change with behavioral rather than byte-equivalence
acceptance criteria.

#### Scenario: Phase A is accepted

- **WHEN** the refactored production corpus is translated and assembled
- **THEN** its complete ROM equals the direct customasm oracle and established
  digest byte-for-byte

#### Scenario: A desirable refactor changes encoding

- **WHEN** a refactor would improve structure or use the custom CPU more
  effectively but changes one or more emitted bytes
- **THEN** it is recorded for the customasm-only redesign rather than included
  in this change

### Requirement: Honest Celeste Object Variants
The Celeste layout SHALL model the common 18-byte object core and the
type-specific 46-byte tail as a union containing player, spawn, smoke and title
views. Static assertions SHALL preserve every consumed offset and the 64-byte
record size.

#### Scenario: Player state is addressed
- **WHEN** player code accesses dash jumps, timers, targets or hair
- **THEN** its typed path names the player payload view rather than a flat
  universal object field

#### Scenario: Another type reuses payload storage
- **WHEN** spawn, smoke or title code accesses its state
- **THEN** its typed path names that type's payload view at the established
  byte offset

### Requirement: Nominal Celeste Object Identity
Object type identifiers and multi-state lifecycle values SHALL use fixed-width
nominal enums. Combination bit fields SHALL remain explicitly byte-valued until
a flags type exists.

#### Scenario: Dispatch table is declared
- **WHEN** object lifecycle targets are associated with object kinds
- **THEN** the layout declares the corresponding `ObjectKind` members with the
  established numeric values

### Requirement: Celeste Lifecycle Procedures
The player, spawn, smoke and title init/update/draw entry points SHALL be
namespaced procedures using the `console6502` convention and an explicit
`self : ptr CelesteObject in pObj` receiver. Dispatch remains explicit parallel
low/high target tables.

#### Scenario: Lifecycle dispatch executes
- **WHEN** an object kind selects its init, update or draw target
- **THEN** the target is the corresponding namespaced procedure and emitted
  call/return bytes equal the direct reference

### Requirement: Typed Celeste Hardware Windows
The production layout SHALL describe the video and PSG MMIO windows with
explicit-offset structures and fixed typed overlays. Eligible direct byte
loads and stores SHALL use overlay field paths.

#### Scenario: Direct video register is accessed
- **WHEN** Celeste reads the frame counter or writes a sprite staging register
- **THEN** source names the typed video overlay field and lowering emits one
  access to the established absolute address

#### Scenario: Direct PSG register is accessed
- **WHEN** Celeste reads PSG status or writes music control
- **THEN** source names the typed PSG overlay field and lowering emits one
  access to the established absolute address

### Requirement: Readable Celeste Production Source
The main, object, collision, player and draw production modules SHALL retain
human-authored comments and SHALL NOT contain long blank runs created by
comment deletion.

#### Scenario: Maintainer opens a migrated module
- **WHEN** source formatting is inspected
- **THEN** explanatory comments from the direct reference are present and no
  run exceeds three consecutive blank lines

### Requirement: Semantic Refactor Equivalence
Conformance SHALL count the expected object enums, payload union, lifecycle
procedures and hardware overlays; it SHALL also report residual raw object
offset/index operations. All 65,536 ROM bytes and the golden digest SHALL
remain unchanged.

#### Scenario: Refactored game is accepted
- **WHEN** the complete production corpus translates and assembles
- **THEN** semantic construct counts meet the migration manifest, residual
  indexed operations are nonzero and reported, and the ROM equals the oracle
  byte-for-byte
