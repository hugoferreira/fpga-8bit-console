## ADDED Requirements

### Requirement: Target-defined Procedure Conventions
The frontend SHALL allow a procedure to select a target-defined calling
convention with `using <convention>`. The convention SHALL assign omitted
input and return locations deterministically by declaration order and type
class. Explicit placement SHALL override convention assignment.

#### Scenario: Scalar inputs omit locations
- **WHEN** a console6502 procedure using its target convention declares three
  scalar inputs without placement
- **THEN** they resolve in declaration order to `a`, `x` and `y`

#### Scenario: Pointer has no convention location
- **WHEN** a console6502 pointer input omits placement
- **THEN** translation fails because the convention has no
  application-independent zero-page pointer location

#### Scenario: Procedure has no convention
- **WHEN** an input or return omits placement in a procedure without `using`
- **THEN** translation fails and identifies the member requiring placement

### Requirement: Typed Procedure Returns
A procedure SHALL declare a return using
`name : type return [in physical]`. A return name SHALL alias its resolved
physical location and SHALL NOT be a compiler-managed value. Semantic `ret`
SHALL perform frame restoration and the target return operation but SHALL NOT
implicitly calculate, copy or preserve a return value.

#### Scenario: Explicit pointer return is declared
- **WHEN** `result : ptr CelesteObject return in pObj` is declared
- **THEN** `result` aliases `pObj` and no return-storage instruction is emitted
  solely by the declaration

#### Scenario: Convention assigns scalar return
- **WHEN** a console6502 procedure using its target convention declares
  `result : u8 return`
- **THEN** `result` resolves to `a`

#### Scenario: Return qualifier order is invalid
- **WHEN** source places `return` after an `in` placement
- **THEN** translation fails with the canonical
  `name : type return in physical` form

### Requirement: Marshalled Invocation Statement
The frontend SHALL accept a declared callee invocation as one assembly-style
`invoke Callee, name=value` statement. Comma-separated bindings MAY continue
onto following physical lines when the preceding line ends in a comma. The
invocation SHALL require no terminating `end`. The frontend SHALL validate
bindings against the callee signature and SHALL publish deterministic target
call and argument-placement operations. Raw target call instructions SHALL
continue to perform no frontend marshalling.

#### Scenario: Named inputs are invoked
- **WHEN** one invocation statement binds every required callee input exactly
  once
- **THEN** the backend places those values in the resolved input locations and
  emits the target call

#### Scenario: Long invocation is continued
- **WHEN** an invocation line ends in a comma
- **THEN** subsequent indented binding lines belong to that invocation until a
  line does not end in a comma

#### Scenario: Block terminator follows invocation
- **WHEN** source places `end` after a complete invocation solely to terminate
  the call
- **THEN** that `end` is not consumed as part of the invocation

#### Scenario: Binding is missing or repeated
- **WHEN** a required input is absent, named twice or not declared by the
  callee
- **THEN** translation fails before emitting a partial call sequence

#### Scenario: Raw call is used
- **WHEN** source emits a raw `jsr`, `call` or target-equivalent instruction
- **THEN** the frontend preserves it without placing or validating arguments

### Requirement: Parallel Invocation Assignment
All invocation right-hand sides SHALL denote values from the machine state
before marshalling begins. A backend SHALL preserve those values while
resolving overlapping transfers and SHALL report any scratch register, exchange
operation or frame temporary used.

#### Scenario: Two physical arguments are swapped
- **WHEN** the callee expects `left` in one location and `right` in another
  while the invocation supplies those locations in reverse
- **THEN** lowering preserves both original values with parallel-copy
  semantics

#### Scenario: No legal temporary is available
- **WHEN** an overlapping invocation cannot be lowered using a target exchange,
  permitted scratch location or bounded frame temporary
- **THEN** translation fails without destroying either source value

## MODIFIED Requirements

### Requirement: Scoped Procedures and Physical Parameters
The frontend SHALL support named procedures whose default mode is `frame` and
whose explicit alternate mode is `naked`. Every procedure member SHALL begin
with `name : type`. An unqualified member SHALL be an input; `in frame` SHALL
make it a local; and `return` SHALL make it an output. Input and return names
SHALL be scoped aliases for resolved physical target locations and SHALL NOT be
virtual or automatically preserved values.

#### Scenario: Pointer receiver aliases a physical pair
- **WHEN** a procedure declares
  `self : ptr CelesteObject in pObj`
- **THEN** typed operands using `self` lower through physical location `pObj`
  only within that procedure

#### Scenario: Local uses the common declaration form
- **WHEN** a procedure declares
  `saved_self : ptr CelesteObject in frame`
- **THEN** the name is a frame local using the same `name : type` grammar as
  parameters and structure fields

#### Scenario: Frame mode is omitted
- **WHEN** a procedure declaration names neither `frame` nor `naked`
- **THEN** it has `frame` semantics

#### Scenario: Naked procedure is declared
- **WHEN** a procedure is declared `naked`
- **THEN** no automatic frame allocation or restoration is emitted

#### Scenario: Provisional local spelling is used
- **WHEN** source declares `local saved : u8`
- **THEN** translation rejects it with a migration diagnostic naming
  `saved : u8 in frame`

### Requirement: Explicit Frame Locals
A frame procedure SHALL support `name : type in frame` declarations for
scalars, pointers and fixed-size packed aggregates whose layouts are complete.
The backend SHALL publish or diagnose frame size, alignment, local offset,
generated entry/exit operations and clobbers. Naked procedures SHALL reject
frame locations.

#### Scenario: Byte local is used
- **WHEN** a console6502 frame procedure stores and loads a `u8` local
- **THEN** the generated frame reserves one hardware-stack byte, local
  operations address that byte, and semantic `ret` restores SP before `rts`

#### Scenario: Pointer local is copied
- **WHEN** source moves a target-sized pointer between a physical location and
  a frame local
- **THEN** lowering copies every pointer storage unit in documented order
  without changing the pointer's nominal type

#### Scenario: Packed aggregate field is addressed
- **WHEN** source accesses a byte field through a packed aggregate frame local
- **THEN** lowering combines the local frame offset and qualified field offset
  without copying the complete aggregate

#### Scenario: Frame has no locals or temporaries
- **WHEN** a frame procedure needs neither declared locals nor invocation
  temporaries
- **THEN** the backend may elide all frame-management instructions

#### Scenario: Raw stack mutation occurs
- **WHEN** a frame with locals or invocation temporaries contains an
  unmodelled stack-mutating raw instruction
- **THEN** translation fails instead of silently using an incorrect offset

### Requirement: Assembly-equivalent Structured Lowering
Indexed operands, pool addresses, procedure frames, convention assignment,
typed frame copies and invocation SHALL have focused handwritten target
references. Adoption into a game build SHALL additionally retain
complete-image equivalence.

#### Scenario: Focused constructs are assembled
- **WHEN** each new console6502 semantic operation and its handwritten
  reference are assembled
- **THEN** their instruction and data bytes compare exactly

#### Scenario: Invocation uses a temporary
- **WHEN** an invocation requires an exchange, scratch location or frame
  temporary
- **THEN** the focused reference includes the same resource use and exact
  instruction sequence

### Requirement: Deferred Compiler Features Are Rejected
The current frontend slice SHALL reject, rather than partially implement,
native instruction encoding, canonical ISA generation, an in-console editor
shell, user-defined calling-convention declarations, method-table generation,
automatic pool allocation, clobber analysis, stack parameters,
aggregate-by-value parameters, aggregate-to-aggregate local copies and
automatic register allocation. Implemented target conventions, returns,
frame locations and invocation SHALL be accepted only in the documented
bounded subset.

#### Scenario: Unsupported procedure feature is encountered
- **WHEN** source declares a stack parameter, aggregate-by-value parameter,
  user-defined calling convention or aggregate-to-aggregate frame copy
- **THEN** translation fails with a diagnostic naming the feature as deferred

#### Scenario: Native output is requested
- **WHEN** tooling is asked to emit a machine image without customasm
- **THEN** it rejects the request as deferred and leaves existing host outputs
  unchanged

#### Scenario: Raw target procedure remains possible
- **WHEN** a programmer writes an ordinary target label, instructions and
  return instruction without frontend procedure syntax
- **THEN** those lines pass through to customasm
