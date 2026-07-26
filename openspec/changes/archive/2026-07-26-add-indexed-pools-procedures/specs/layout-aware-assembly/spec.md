## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Deferred Compiler Features Are Rejected
The current frontend slice SHALL reject, rather than partially implement,
native instruction encoding, canonical ISA generation, an in-console editor
shell, calling-convention declarations, `invoke`, method-table generation,
automatic pool allocation, clobber analysis, aggregate or stack parameters,
aggregate locals and automatic register allocation. Implemented procedure,
frame, naked, fixed-pool and indexed-operand syntax SHALL be accepted only in
the documented bounded subset.

#### Scenario: Unsupported procedure feature is encountered
- **WHEN** source declares `invoke`, a stack parameter, aggregate local or
  user-defined calling convention
- **THEN** translation fails with a diagnostic naming the feature as deferred

#### Scenario: Native output is requested
- **WHEN** tooling is asked to emit a machine image without customasm
- **THEN** it rejects the request as deferred and leaves existing host outputs
  unchanged

#### Scenario: Raw target procedure remains possible
- **WHEN** a programmer writes an ordinary target label, instructions and
  return instruction without frontend procedure syntax
- **THEN** those lines pass through to customasm
