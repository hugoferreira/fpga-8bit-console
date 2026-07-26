## ADDED Requirements

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

## MODIFIED Requirements

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
