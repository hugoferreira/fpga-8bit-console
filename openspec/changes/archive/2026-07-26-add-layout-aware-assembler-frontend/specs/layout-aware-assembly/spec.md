## ADDED Requirements

### Requirement: Portable Semantic Core

The system SHALL provide the layout-aware lexer, parser, layout engine,
expression evaluator, type checker and semantic lowering as a portable core
implemented in a conservative freestanding-friendly C subset. The core SHALL
NOT require Python, a filesystem, process execution, environment variables,
locale services or JSON support.

#### Scenario: Core is built for the host

- **WHEN** the host frontend command is built
- **THEN** it links the same portable core sources intended for a future
  console build rather than a separate host semantic implementation

#### Scenario: Host service is absent

- **WHEN** the core is used without filesystem, subprocess or JSON callbacks
- **THEN** lexical, layout, type and semantic lowering operations remain
  available

#### Scenario: Host-only API leaks into the core

- **WHEN** a core source module directly requires a host path, process,
  environment or JSON API
- **THEN** the portability conformance check fails

### Requirement: Bounded Caller-supplied Storage

The core SHALL use caller-supplied workspaces and declared capacity limits for
tokens, identifiers, structures, fields, locations, expressions, fixups,
diagnostics and nesting. It SHALL NOT call `malloc`, `calloc`, `realloc` or an
equivalent implicit heap allocator. Semantic objects SHALL be referenced across
core tables by bounded integer handles or workspace-relative offsets rather
than persistent host-native pointers.

#### Scenario: Compilation fits the workspace

- **WHEN** valid source requires no more than the caller-declared capacities
- **THEN** the core completes without requesting additional storage

#### Scenario: Symbol capacity is exhausted

- **WHEN** source requires one more symbol than the declared symbol capacity
- **THEN** the core returns a deterministic capacity diagnostic naming the
  symbol table, configured limit and source construct that could not be added

#### Scenario: Workspace is deliberately small

- **WHEN** the conformance suite runs with reduced workspace and table limits
- **THEN** the core either succeeds within those bounds or reports the
  documented capacity error without memory corruption

#### Scenario: Nesting exceeds its limit

- **WHEN** structure or expression nesting exceeds the configured maximum
- **THEN** the core rejects the source before exhausting the platform call
  stack or workspace

### Requirement: Platform-neutral Input, Output and Diagnostics

The core SHALL obtain source bytes through a caller-provided input interface and
publish semantic output and diagnostics through caller-provided sinks. These
interfaces SHALL support a host file adapter and a future in-console editor
buffer without changing the semantic core.

#### Scenario: Source comes from a host file

- **WHEN** the host shell compiles a file
- **THEN** its file adapter supplies the bytes through the core input interface

#### Scenario: Source comes from memory

- **WHEN** the same source is supplied by an in-memory test adapter
- **THEN** the core produces the same semantic events and diagnostics as the
  host file adapter

#### Scenario: Diagnostic is produced without formatting services

- **WHEN** the core detects an error
- **THEN** it reports a stable diagnostic code, source span and bounded
  arguments that the platform shell may format

### Requirement: Host Source-to-customasm Adapter

The host shell SHALL read layout-aware source, run the portable semantic core,
and emit ordinary customasm source plus host source-location metadata. The
frontend SHALL NOT encode machine instructions, place banks, resolve final
symbols or emit machine images in this change; the pinned customasm tool SHALL
perform those host-build responsibilities.

#### Scenario: Valid source is translated

- **WHEN** the host shell receives valid layout-aware source and the
  `console6502` target
- **THEN** it emits customasm source that the repository's pinned customasm
  version accepts

#### Scenario: Raw assembly remains available

- **WHEN** a source line is not a layout declaration, typed-location
  declaration, static assertion or typed field operand owned by the frontend
- **THEN** the frontend preserves that line as raw target assembly without
  interpreting its instruction semantics

#### Scenario: Host adapter is not a machine-code encoder

- **WHEN** valid source is translated in this change
- **THEN** the host adapter output contains target assembly text rather than a
  binary, object file or `readmemh` image

### Requirement: Deterministic Translation

Core semantic output and host translation SHALL be deterministic. The emitted
customasm and source map SHALL depend only on the input source, selected target,
declared capacity configuration and frontend version, and SHALL NOT depend on
host paths, locale, native pointer values, hash iteration order or terminal
settings.

#### Scenario: Identical inputs are rebuilt

- **WHEN** the same source is translated twice with the same target and
  frontend version and capacity configuration
- **THEN** the generated customasm and source-map files compare byte for byte

#### Scenario: Host and memory adapters are compared

- **WHEN** identical source bytes are supplied through host-file and in-memory
  adapters under the same limits
- **THEN** the ordered semantic events and diagnostics compare equal

#### Scenario: Two sufficient capacity profiles are compared

- **WHEN** the same valid source is compiled under two capacity profiles that
  both accommodate it
- **THEN** semantic events and host-generated customasm compare equal, apart
  from separately reported workspace high-water metadata

### Requirement: Fixed-width Primitive Types

The first language slice SHALL define `u8`, `i8`, `u16` and `i16` as portable
fixed-width integer layout types. It SHALL define `ptr T` as a target-sized
pointer to `T`. Type sizes SHALL be measured in target addressable storage
units, and the initial targets SHALL be byte-addressed.

#### Scenario: Primitive sizes on a byte-addressed target

- **WHEN** a byte-addressed target lays out the four fixed-width integer types
- **THEN** `u8` and `i8` occupy one storage unit and `u16` and `i16` occupy two
  storage units

#### Scenario: Pointer size comes from the target

- **WHEN** `ptr CelesteObject` is used with the `console6502` target
- **THEN** it occupies two storage units

#### Scenario: Unsupported primitive is used

- **WHEN** source names a primitive type not defined by the language or target
- **THEN** translation fails at that type name without emitting usable
  customasm

### Requirement: Packed Structure Layouts

The frontend SHALL support nominal packed structures containing named primitive
fields, nested structure fields and fixed-length array fields. Packed fields
SHALL be placed consecutively in declaration order without implicit padding.
Structure names and field names SHALL be unique within their scopes.

#### Scenario: Nested packed layout is calculated

- **WHEN** `CelesteObject` contains a four-byte `Hitbox` after twelve preceding
  bytes
- **THEN** `CelesteObject.hitbox.x.offset` is 12 and
  `CelesteObject.hitbox.w.offset` is 14

#### Scenario: Fixed array contributes its full size

- **WHEN** a packed structure contains `hair : HairNode[5]` and `HairNode.size`
  is four
- **THEN** `hair.size` is 20, `hair.count` is 5 and `hair.stride` is 4

#### Scenario: Duplicate field is rejected

- **WHEN** one structure declares the same field name twice
- **THEN** translation fails at the second declaration and identifies the
  containing structure

#### Scenario: Recursive value layout is rejected

- **WHEN** a structure contains itself directly or through other structures by
  value
- **THEN** translation fails with a diagnostic describing the layout cycle

### Requirement: Explicit Reserved Storage

The frontend SHALL support explicitly named reserved byte arrays in a packed
structure. Reserved storage SHALL contribute to size and offset calculations
exactly like any other `u8` array and SHALL NOT receive implicit runtime
initialisation.

#### Scenario: Celeste record tail is reserved

- **WHEN** `CelesteObject` declares `reserved : u8[7]` after byte 56
- **THEN** `CelesteObject.size` is 64

#### Scenario: Field growth exceeds the intended size

- **WHEN** a new field makes `CelesteObject.size == 64` false
- **THEN** its layout assertion fails instead of silently changing the pool
  stride

### Requirement: Compile-time Layout Properties

The frontend SHALL expose compile-time properties for structure size and
alignment and for field offset, size, type, count and stride where applicable.
Nested field paths SHALL resolve to offsets relative to the outermost named
structure.

#### Scenario: Nested field offset is queried

- **WHEN** source evaluates `CelesteObject.hitbox.w.offset`
- **THEN** it receives the offset of `w` from the beginning of
  `CelesteObject`, not from the beginning of `Hitbox`

#### Scenario: Scalar count is queried

- **WHEN** source requests `.count` on a non-array field
- **THEN** translation fails and identifies the property as inapplicable

#### Scenario: Unknown field is queried

- **WHEN** source evaluates `CelesteObject.velocity.z.offset`
- **THEN** translation fails at `z` and reports the longest valid containing
  field path

### Requirement: Compile-time Assertions

The frontend SHALL support `static_assert` over integer constants, layout
properties, parentheses, arithmetic, comparison and boolean operators.
Assertions SHALL be evaluated before target assembly is emitted.

#### Scenario: Valid layout assertion passes

- **WHEN** source asserts `CelesteObject.hair.offset == 37`
- **THEN** translation continues without emitting runtime code

#### Scenario: Layout assertion fails

- **WHEN** a static assertion evaluates false
- **THEN** translation fails at the assertion and reports its evaluated
  operands

### Requirement: Stable Generated Layout Symbols

The host customasm emitter SHALL emit constants for public layout properties
using a documented collision-free name-mangling scheme. Generated names SHALL
not rely on customasm dot-prefixed local-label syntax and SHALL remain stable
across unchanged host-output format versions. The core semantic model SHALL
represent the properties independently of those generated spellings.

#### Scenario: Nested offset constant is emitted

- **WHEN** `CelesteObject.hitbox.w.offset` is public
- **THEN** host-generated customasm contains a stable non-local symbol whose
  value is 14 while an alternate emitter can consume the numeric property
  without that symbol

#### Scenario: User symbol collides with a generated symbol

- **WHEN** raw source defines a symbol reserved by the frontend's mangling
  prefix
- **THEN** translation fails with a collision diagnostic rather than emitting
  two definitions

### Requirement: Typed Physical Locations

The frontend SHALL allow a source name to be declared as a typed alias for a
target physical location. A typed location SHALL NOT be a virtual register,
SHALL NOT imply storage allocation and SHALL NOT cause its incoming value to be
preserved.

#### Scenario: Zero-page pointer pair receives a type

- **WHEN** source declares `location pObj : ptr CelesteObject`
- **THEN** subsequent field operands based on `pObj` are resolved against
  `CelesteObject`

#### Scenario: Base type disagrees with explicit field type

- **WHEN** a location typed as `ptr NemoObject` is used with a field path
  explicitly rooted at `CelesteObject`
- **THEN** translation fails with a base-type mismatch

#### Scenario: Location declaration emits no storage

- **WHEN** a typed location is declared
- **THEN** the generated customasm contains no allocation or initialisation
  solely because of that declaration

### Requirement: Explicit Typed Field Operands

The frontend SHALL accept the explicit semantic operand form
`[base + Type.field.path]` for target operations registered as typed field
loads or stores. The frontend SHALL resolve the field path and pass the base
location, field type, displacement and operation to the selected target. Field
syntax SHALL NOT imply a getter, setter, null check, bounds check, allocation or
dynamic dispatch.

#### Scenario: Typed byte store is lowered

- **WHEN** `pObj` is a `ptr CelesteObject` and source contains
  `sta [pObj + CelesteObject.hitbox.w]`
- **THEN** the `console6502` target receives a byte store with displacement 14

#### Scenario: Nested field has a non-byte width

- **WHEN** a byte-only target operation is used on a `u16`, `i16`, pointer or
  structure field
- **THEN** translation fails with an access-width diagnostic rather than
  truncating the field

#### Scenario: Target does not register the operation

- **WHEN** typed field syntax is used with an instruction or operand form the
  target does not support
- **THEN** translation fails at the operand and suggests using raw target
  assembly

### Requirement: Target-defined Field Lowering

Target backends SHALL define the physical-location forms, legal semantic field
operations, displacement limits and declared scratch or clobber requirements.
The core SHALL represent a successful lowering as bounded structured target
operations rather than customasm text. A platform emitter SHALL translate those
operations into its output representation. The language frontend SHALL NOT
assume a universal register file, addressing mode or textual assembler.

#### Scenario: Extended 6502 direct displacement is used

- **WHEN** `console6502` lowers a byte load through a zero-page pointer pair at
  displacement 14
- **THEN** it produces a structured extended-6502 byte-load operation whose host
  emitter writes the existing customasm form `lda (pObj), #14`

#### Scenario: Displacement exceeds the target form

- **WHEN** a field displacement is outside the range accepted by the selected
  target operation
- **THEN** translation fails with the required range and actual displacement
  unless that target defines a deterministic compound lowering

#### Scenario: Lowering needs unavailable scratch

- **WHEN** a target lowering requires a scratch resource not declared or
  available in the current language slice
- **THEN** translation fails instead of overwriting an unmodelled live
  location

### Requirement: Native-encoder-ready Backend Boundary

The target and emitter interfaces SHALL permit a future in-console platform
shell to consume the same resolved layouts and structured target operations and
encode them directly into memory. The portable core SHALL NOT require generated
customasm symbols, customasm parsing or host process execution as part of its
semantic model. A native instruction encoder is explicitly deferred from this
change.

#### Scenario: Host customasm emitter consumes a lowered operation

- **WHEN** the core produces a structured `console6502` field-store operation
- **THEN** the host emitter can render it as customasm without asking the core
  to produce assembler-specific text

#### Scenario: Alternate emitter is substituted

- **WHEN** a test emitter consumes the same structured operation
- **THEN** it receives the resolved operation, physical location, displacement
  and source span without parsing generated customasm

#### Scenario: Native encoding is requested in the first slice

- **WHEN** a caller requests direct machine-code emission
- **THEN** the platform reports the feature as deferred rather than invoking an
  incomplete encoder

### Requirement: Canonical ISA Description Seam

The documented backend architecture SHALL identify one future canonical
machine-readable ISA description as the source for both host customasm rules and
compact in-console encoder tables. This change SHALL NOT create that
description, replace the existing `src/isa/*.asm` definitions or maintain a
second handwritten opcode table.

#### Scenario: First-slice target metadata is added

- **WHEN** the `console6502` field-operation lowering is implemented
- **THEN** it reuses existing instruction facts needed for the conformance
  fixture without introducing a purported complete native opcode table

#### Scenario: Full native encoder work is proposed

- **WHEN** a later change adds direct instruction encoding
- **THEN** that change must define how customasm rules and console encoder
  tables are derived from or verified against one canonical ISA description

### Requirement: Source-correlated Diagnostics

The core SHALL report lexical, syntax, layout, type, capacity and lowering
errors as stable codes with original source spans and bounded arguments. The
host shell SHALL format those diagnostics against the original source path,
line and column, emit a deterministic mapping from generated customasm lines to
original source locations, and remap downstream customasm diagnostics when a
generated line has an original source location.

#### Scenario: Frontend error identifies original input

- **WHEN** a field path is invalid
- **THEN** the core reports the invalid-field code, source span, type and
  invalid path component and the host shell formats the original file, line and
  column

#### Scenario: Downstream assembler rejects a translated raw line

- **WHEN** customasm reports an error on a generated line originating from raw
  source
- **THEN** the build wrapper reports the corresponding original source
  location and retains the customasm error text

#### Scenario: Generated declaration causes downstream error

- **WHEN** customasm reports an error in generated layout declarations
- **THEN** the diagnostic identifies both the generated file location and the
  source declaration responsible for it

### Requirement: Celeste Layout Conformance

The conformance suite SHALL declare the existing 64-byte Celeste object record
in layout-aware source and compare every generated offset used by the fixture
against the current `O_*` layout. Representative typed loads and stores SHALL
assemble byte-identically to handwritten customasm using the same extended-6502
instructions.

#### Scenario: All represented offsets match

- **WHEN** the Celeste conformance fixture is translated
- **THEN** its kind, sprite, position, speed, remainder, hitbox, player-state,
  dash, target and hair offsets equal the current layout and its total size is
  64

#### Scenario: Typed field code is byte-identical

- **WHEN** the translated and handwritten versions of representative
  `player_init` field stores are assembled with pinned customasm
- **THEN** their emitted instruction bytes compare equal

#### Scenario: A field is moved accidentally

- **WHEN** the fixture layout changes an established offset
- **THEN** a static assertion or golden-layout comparison fails before the
  translated code is accepted

### Requirement: Production Builds Remain Unchanged

This change SHALL NOT make the existing Breakout, Nemo or Celeste build targets
depend on the new frontend. Generated customasm SHALL be written beneath the
build directory and SHALL NOT be checked in as a second source of truth.

#### Scenario: Existing game builds run

- **WHEN** any existing game assembly target runs after the frontend is added
- **THEN** it follows the same assembler path and consumes the same source files
  as before this change

#### Scenario: Frontend conformance build runs

- **WHEN** the layout-aware conformance target runs
- **THEN** generated customasm and maps are placed under `build/` and may be
  deleted and reproduced without changing tracked source

### Requirement: Deferred Compiler Features Are Rejected

The first frontend slice SHALL reject, rather than partially implement,
native instruction encoding, canonical ISA generation, an in-console editor
shell, procedure declarations, frame allocation, calling-convention
declarations, `invoke`, method-table generation, pool allocation, clobber
analysis and automatic register allocation.

#### Scenario: Deferred procedure syntax is encountered

- **WHEN** first-slice source declares `proc`, `frame`, `naked` or `invoke`
- **THEN** translation fails with a diagnostic naming the feature as deferred

#### Scenario: Native output is requested

- **WHEN** first-slice tooling is asked to emit a machine image without
  customasm
- **THEN** it rejects the request as deferred and leaves existing host outputs
  unchanged

#### Scenario: Raw target procedure remains possible

- **WHEN** a programmer writes an ordinary target label, instructions and
  return instruction without frontend procedure syntax
- **THEN** those lines pass through to customasm
