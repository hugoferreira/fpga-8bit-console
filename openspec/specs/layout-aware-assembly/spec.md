# Layout-aware Assembly

## Purpose

Defines the bounded portable frontend, layout semantics, target lowering and host bootstrap contract.

## Requirements

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

### Requirement: Multi-source Semantic Compilation
The portable frontend SHALL accept module-expanded input whose origin callback
maps flattened lines to stable source ids and original line numbers. Existing
single-stream callers without an origin callback SHALL retain their current
behavior.

#### Scenario: Declaration and use span modules
- **WHEN** one module declares a nominal layout and another module uses it in a
  typed operand
- **THEN** the complete expanded source is resolved as one semantic module
  graph

#### Scenario: Legacy single input is compiled
- **WHEN** a caller supplies the existing streaming input without module
  origins
- **THEN** all events retain the input's single source id as before

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

The frontend SHALL support nominal packed structures containing named
primitive, enum, nested structure, nested union and fixed-length array fields.
A structure with no layout-policy keyword SHALL be packed. An explicit
`packed` keyword SHALL assert the same policy and produce identical layout and
semantic events. A packed field without an offset qualifier SHALL begin at the
current layout cursor.
A field declared `at <constant-expression>` SHALL begin at that explicit
nonnegative storage-unit offset, which SHALL NOT precede the current cursor.
After either form the cursor SHALL equal the end of that field. Packed
structures SHALL add no implicit padding. Structure names and field names SHALL
be unique within their scopes. Leading and internal gaps created by explicit
offsets SHALL be unnamed bytes omitted from that structure view: they SHALL
contribute to the resolved extent but SHALL NOT allocate, reserve, initialise
or expose a field path. A structure SHALL remain a complete nominal layout even
when it intentionally describes only a sparse subset of backing storage.

#### Scenario: Nested packed layout is calculated

- **WHEN** `CelesteObject` contains a four-byte `Hitbox` after twelve preceding
  bytes
- **THEN** `CelesteObject.hitbox.x.offset` is 12 and
  `CelesteObject.hitbox.w.offset` is 14

#### Scenario: Packed policy is omitted

- **WHEN** two otherwise identical structures differ only because one spells
  `packed` and the other omits the policy
- **THEN** their field offsets, size, alignment and semantic events are
  identical

#### Scenario: Layout policies conflict

- **WHEN** one aggregate declares both `packed` and `aligned(4)`
- **THEN** translation fails at the conflicting policy

#### Scenario: Fixed array contributes its full size

- **WHEN** a packed structure contains `hair : HairNode[5]` and `HairNode.size`
  is four
- **THEN** `hair.size` is 20, `hair.count` is 5 and `hair.stride` is 4

#### Scenario: Explicit offset creates a gap

- **WHEN** a one-byte field follows a one-byte field but is declared `at 4`
- **THEN** the second field offset is four and the structure size becomes five
  without emitting or initialising the three-unit gap

#### Scenario: Sparse structure omits unrelated fields

- **WHEN** a structure declares fields at offsets 0 and 17 and no fields for
  offsets 1 through 16
- **THEN** its size is 18, only the two declared paths exist, and the unnamed
  bytes remain available to other views over the same backing region

#### Scenario: Leading bytes are omitted

- **WHEN** the first field of a structure is explicitly placed at offset four
- **THEN** the field offset is four and bytes zero through three have no field
  path through that structure

#### Scenario: Explicit offset moves backwards

- **WHEN** a field's explicit offset is smaller than the current layout cursor
- **THEN** translation fails with the current cursor and requested offset
  rather than overlapping or backfilling storage

#### Scenario: Duplicate field is rejected

- **WHEN** one structure declares the same field name twice
- **THEN** translation fails at the second declaration and identifies the
  containing structure

#### Scenario: Recursive value layout is rejected

- **WHEN** a structure contains itself directly or through structures or
  unions by value
- **THEN** translation fails with a diagnostic describing the layout cycle

### Requirement: Fixed-width Nominal Enums

The frontend SHALL support nominal enums declared with one of the fixed-width
integer primitives `u8`, `i8`, `u16` or `i16` as an explicit underlying type.
Every enum SHALL contain at least one member. Every member SHALL have an
explicit compile-time integer value representable by that type. A member
expression MAY refer to previously declared qualified enum members but SHALL
NOT refer forward or to itself. Enum member names SHALL be unique within the
enum; equal values MAY be represented by more than one member. An enum SHALL
occupy exactly the size of its underlying type and SHALL perform no runtime
range or membership check.

#### Scenario: Byte enum is used as a field

- **WHEN** a packed structure contains a field of an enum whose underlying type
  is `u8`
- **THEN** that field occupies one storage unit and subsequent layout proceeds
  from the following unit

#### Scenario: Qualified enum value is evaluated

- **WHEN** a compile-time expression refers to `ObjectKind.player`
- **THEN** the expression receives the explicitly declared integer value

#### Scenario: Enum value exceeds its representation

- **WHEN** a member value is outside the range of the enum's underlying type
- **THEN** translation fails at that member with the required range and actual
  value

#### Scenario: Enum member values alias

- **WHEN** two differently named members have the same representable value
- **THEN** both qualified names are accepted and denote that value

#### Scenario: Enum value refers forward

- **WHEN** an enum member expression refers to itself or a member declared
  later
- **THEN** translation fails with the unresolved qualified member

#### Scenario: Enum is empty

- **WHEN** an enum reaches `end` without a member
- **THEN** translation fails at the declaration

### Requirement: Deterministic Aligned Aggregate Layout

The frontend SHALL accept `aligned(N)` as an alternative structure or union
layout policy. `N` SHALL be a positive power of two measured in target
addressable storage units and SHALL NOT exceed the selected target's declared
maximum aggregate alignment. This policy SHALL use the documented,
target-independent field-alignment algorithm rather than a host or target ABI.

For a structure, the effective alignment of a fixed-width primitive or enum
field SHALL be the smaller of its storage size and `N`; pointer alignment SHALL
be the smaller of target pointer storage units and `N`; nested aggregate
alignment SHALL be the smaller of its declared alignment and `N`; and array
alignment SHALL be its element alignment. Each implicit field SHALL begin at
the next cursor offset divisible by its effective alignment. An explicit field
offset SHALL additionally be divisible by that alignment. Final structure or
union size SHALL be rounded upward to `N`, and the aggregate alignment property
SHALL be `N`. Automatic field and tail padding SHALL have no name, field path,
allocation or initialisation behavior. A pool, fixed overlay, frame location or
other storage binding of an aligned aggregate SHALL publish the required
alignment to its backend. The backend SHALL verify a resolvable base or reject
a storage class that cannot satisfy the requirement; it SHALL NOT silently
weaken the policy.

#### Scenario: Aligned structure inserts field and tail padding

- **WHEN** `aligned(4)` structure fields are `u8`, `u16` and `u8` in that order
- **THEN** their offsets are 0, 2 and 4, total size is 8 and alignment is 4

#### Scenario: Pointer alignment comes from target width

- **WHEN** an `aligned(4)` structure contains a pointer on a target whose
  pointer occupies two storage units
- **THEN** that pointer's effective field alignment is two

#### Scenario: Explicit aligned offset is invalid

- **WHEN** a `u16` field in an `aligned(4)` structure is explicitly placed at
  offset three
- **THEN** translation fails with effective alignment two and requested offset
  three

#### Scenario: Alignment is not a power of two

- **WHEN** source declares `aligned(3)`
- **THEN** translation fails at the layout policy

#### Scenario: Target cannot represent requested alignment

- **WHEN** `N` exceeds the target's declared maximum aggregate alignment
- **THEN** translation fails without silently reducing `N`

#### Scenario: Nested alignment is capped by outer policy

- **WHEN** an aggregate aligned to eight is nested in an `aligned(4)` structure
- **THEN** its effective field alignment in the outer structure is four

#### Scenario: Fixed overlay base is misaligned

- **WHEN** an `aligned(4)` aggregate is overlaid on a fixed address not
  divisible by four
- **THEN** translation or downstream target validation rejects that overlay

#### Scenario: Frame cannot satisfy aggregate alignment

- **WHEN** an aligned aggregate is declared in a frame whose backend cannot
  guarantee its required alignment
- **THEN** frame lowering fails instead of laying it out as packed

### Requirement: Nominal Unions

The frontend SHALL support nominal unions containing the same complete field
types and fixed arrays accepted in structures. Omitted layout policy and the
explicit `packed` policy SHALL both give the union alignment one storage unit
and size equal to its maximum member size. An `aligned(N)` union SHALL have
alignment `N` and size equal to its maximum member extent rounded upward to
`N`. Every union member SHALL begin at offset zero. Every union SHALL contain
at least one member, track no active member and perform no runtime conversion,
tagging, validation or initialisation.

#### Scenario: Differently sized members share storage

- **WHEN** a union contains a `u8` member and a four-byte packed structure
- **THEN** both members have offset zero and the union size is four

#### Scenario: Aligned union rounds its extent

- **WHEN** an `aligned(4)` union has a largest member of five storage units
- **THEN** every member remains at offset zero, union alignment is four and
  union size is eight

#### Scenario: Union is nested in a structure

- **WHEN** a packed structure places a union after two preceding bytes
- **THEN** every path through a union member resolves relative to structure
  offset two

#### Scenario: Explicit union member offset is attempted

- **WHEN** a union member includes an `at` offset qualifier
- **THEN** translation fails because union member offset is always zero

#### Scenario: Recursive union layout is declared

- **WHEN** a by-value structure/union graph contains a cycle
- **THEN** translation fails with the same bounded layout-cycle diagnostic used
  for recursive structures

#### Scenario: Union is empty

- **WHEN** a union reaches `end` without a member
- **THEN** translation fails at the declaration

### Requirement: Non-owning Typed Overlays

The frontend SHALL support a named overlay that interprets an existing target
base symbol as a complete nominal structure or union type. An overlay SHALL
allocate no storage, emit no initialisation and perform no copy or conversion.
Multiple overlays MAY name the same base symbol. Typed field operands through
an overlay SHALL resolve to the base symbol plus the selected nominal field
offset and SHALL use a target operation registered for statically addressed
overlay access. Overlay types sharing a base MAY have different sizes, omit
different offsets and describe fields whose storage overlaps fields in another
overlay. This inter-view overlap SHALL NOT make overlapping fields legal within
an individual packed structure.

#### Scenario: Two views share one storage base

- **WHEN** `header : Header at OBJECT_RAM` and
  `player : PlayerObject at OBJECT_RAM` are declared as overlays
- **THEN** both denote the same target base without either declaration emitting
  bytes

#### Scenario: Sparse views describe different subsets

- **WHEN** a header view declares fields at offsets 0 and 17 while a motion
  view declares fields at offsets 2, 3, 6 and 7 and both are overlaid at
  `OBJECT_RAM`
- **THEN** every declared path resolves against the shared base and neither
  view is required to name, cover or reserve the other offsets

#### Scenario: Fields overlap across views

- **WHEN** two different overlay types declare fields covering some of the same
  backing storage units
- **THEN** both overlays are accepted because each remains an independent
  nominal interpretation of the shared bytes

#### Scenario: Overlay field is loaded

- **WHEN** source loads a byte field through a fixed overlay
- **THEN** lowering receives the overlay base symbol, resolved field
  displacement, access width, nominal owner and source span

#### Scenario: Overlay type is incomplete

- **WHEN** an overlay names an unknown or recursively incomplete nominal type
- **THEN** translation fails before any target output is emitted

#### Scenario: Overlay access is unsupported by the target

- **WHEN** the selected target has no registered static-overlay operation for
  the requested access
- **THEN** translation fails without allocating a pointer or inventing a
  scratch location

### Requirement: Bounded Layout Variant Records

Enum, enum-member, union and overlay records SHALL use caller-supplied bounded
tables and integer handles. Their exact and one-past capacities SHALL produce
the same deterministic success/error behavior as existing structure, field and
location tables. The ordered semantic event stream SHALL publish resolved enum
members, union layout properties, explicit field offsets and overlay bases
without host-native pointers or target assembly text.

#### Scenario: Variant tables fit exactly

- **WHEN** source uses exactly the configured number of enums, enum members,
  unions and overlays
- **THEN** compilation succeeds without requesting more workspace

#### Scenario: One variant table overflows

- **WHEN** source requires one more overlay than its configured capacity
- **THEN** translation fails with a stable overlay-capacity diagnostic naming
  the configured limit

#### Scenario: Capacity profiles are both sufficient

- **WHEN** the same valid variant source is compiled under two sufficient
  capacity profiles
- **THEN** semantic events, generated customasm and source maps compare
  deterministically

### Requirement: Stable Enum Member Symbols

The host customasm emitter SHALL publish qualified enum member values using the
existing collision-free generated-name family. The core SHALL publish the
owner, member and numeric value independently of that spelling, and raw target
assembly SHALL NOT be searched or rewritten to substitute enum members.

#### Scenario: Enum member constant is emitted

- **WHEN** `ObjectKind.player` has value one
- **THEN** generated customasm contains one stable non-local constant with
  value one attributable to that member's source declaration

#### Scenario: Enum and layout names would mangle alike

- **WHEN** identifier component boundaries could otherwise produce the same
  flattened spelling
- **THEN** length-prefixed mangling keeps the generated symbols distinct

### Requirement: Layout Variant Assembly Equivalence

Enums, explicit structure offsets, unions and overlays SHALL have focused
handwritten target references for every new console6502 lowering. Layout-only
constructs SHALL emit no instruction or data bytes solely because they are
declared. Existing complete-game equivalence gates SHALL remain unchanged.

#### Scenario: Layout-only declarations are assembled

- **WHEN** equivalent enum, explicit-offset and union declarations are present
  in the frontend fixture but absent from its handwritten target reference
- **THEN** both assembled byte streams remain identical

#### Scenario: Overlay byte access is assembled

- **WHEN** frontend-generated and handwritten console6502 overlay loads and
  stores are assembled
- **THEN** their instruction and data bytes compare exactly

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

### Requirement: Indexed Typed Field Operands
The frontend SHALL accept one physical runtime index on an array component in
a typed field path. It SHALL resolve the array count, element stride, constant
outer displacement and final leaf width before publishing a structured target
operation.

#### Scenario: Nested array byte is indexed
- **WHEN** source uses
  `lda [pObj + CelesteObject.hair[x].x.integer]`
- **THEN** lowering receives physical index `x`, stride 4, the constant hair
  and nested-member displacement, and a one-byte load

#### Scenario: Scalar field is indexed
- **WHEN** source applies `[x]` to a non-array field
- **THEN** translation fails at that component with an indexed-field diagnostic

#### Scenario: Target cannot lower the stride
- **WHEN** the selected target has no legal sequence for the resolved stride
  and declared physical index
- **THEN** translation fails without inventing scratch storage or overwriting
  an unmodelled live location

### Requirement: Fixed Typed Pools
The frontend SHALL support fixed pools with a nominal element type, positive
count, explicit base symbol and explicit backend lowering strategy. A pool
SHALL provide compile-time count, stride and total-size properties but SHALL
NOT imply allocation state, constructors, bounds checks or ownership.

#### Scenario: Celeste object pool is declared
- **WHEN** source declares 16 `CelesteObject` records in a pool
- **THEN** its count is 16, stride is 64 and size is 1,024

#### Scenario: Pool element address is requested
- **WHEN** source requests `address pObj, objects[a]`
- **THEN** lowering receives the destination physical pointer, source physical
  index, element stride, pool base and declared strategy

### Requirement: Scoped Procedures and Physical Parameters
The frontend SHALL support named procedures whose default mode is `frame` and
whose explicit alternate mode is `naked`. Procedure parameters SHALL be scoped
typed aliases for declared physical target locations and SHALL NOT be virtual
values or automatically preserved values.

#### Scenario: Pointer receiver aliases a physical pair
- **WHEN** a procedure declares
  `self : ptr CelesteObject in pObj`
- **THEN** typed operands using `self` lower through physical location `pObj`
  only within that procedure

#### Scenario: Frame mode is omitted
- **WHEN** a procedure declaration names neither `frame` nor `naked`
- **THEN** it has `frame` semantics

#### Scenario: Naked procedure is declared
- **WHEN** a procedure is declared `naked`
- **THEN** no automatic frame allocation or restoration is emitted

### Requirement: Explicit Frame Locals
A frame procedure SHALL support explicitly declared scalar memory locals and
semantic local byte loads and stores. The backend SHALL publish or diagnose
the frame size, local offset, generated entry/exit operations and clobbers.
Naked procedures SHALL reject local declarations.

#### Scenario: Byte local is used
- **WHEN** a console6502 frame procedure stores and loads a `u8` local
- **THEN** the generated prologue reserves one hardware-stack byte, local
  operations address that byte, and semantic `ret` restores SP before `rts`

#### Scenario: Frame has no locals
- **WHEN** a frame procedure declares no locals
- **THEN** the backend may elide all frame-management instructions

#### Scenario: Raw stack mutation occurs
- **WHEN** a frame with locals contains an unmodelled stack-mutating raw
  instruction
- **THEN** translation fails instead of silently using an incorrect local
  offset

### Requirement: Assembly-equivalent Structured Lowering
Indexed, pool-address and procedure/frame constructs SHALL have focused
handwritten target references. Adoption into a game build SHALL additionally
retain complete-image equivalence.

#### Scenario: Focused constructs are assembled
- **WHEN** each new console6502 semantic operation and its handwritten
  reference are assembled
- **THEN** their instruction and data bytes compare exactly

### Requirement: Deferred Compiler Features Are Rejected

The current frontend slice SHALL reject, rather than partially implement,
native instruction encoding, canonical ISA generation, an in-console editor
shell, user-defined calling-convention declarations, method-table generation,
automatic pool allocation, clobber analysis, stack parameters,
aggregate-by-value parameters, aggregate-to-aggregate local copies, automatic
register allocation and enum values in unregistered raw target operand forms.
Implemented target conventions, returns, frame locations, invocation, enums,
explicit offsets, unions and overlays SHALL be accepted only in the documented
bounded subset.

#### Scenario: Unsupported procedure feature is encountered

- **WHEN** source declares a stack parameter, aggregate-by-value parameter,
  user-defined calling convention or aggregate-to-aggregate frame copy
- **THEN** translation fails with a diagnostic naming the feature as deferred

#### Scenario: Enum constant appears in an unregistered raw operand

- **WHEN** a raw target instruction uses a qualified enum value in an operand
  form the frontend does not own
- **THEN** the line remains raw target assembly and no hidden textual
  substitution is performed

#### Scenario: Native output is requested

- **WHEN** tooling is asked to emit a machine image without customasm
- **THEN** it rejects the request as deferred and leaves existing host outputs
  unchanged

#### Scenario: Raw target procedure remains possible

- **WHEN** a programmer writes an ordinary target label, instructions and
  return instruction without frontend procedure syntax
- **THEN** those lines pass through to customasm
