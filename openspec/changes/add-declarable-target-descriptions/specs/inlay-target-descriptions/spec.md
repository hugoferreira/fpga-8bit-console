## ADDED Requirements

### Requirement: Target Description Owns Target Knowledge
The frontend SHALL obtain every target-specific fact from a per-target
description: machine facts (storage unit, byte order, pointer and
code-pointer units, displacement window, maximum alignment), the
register set with roles (accumulator, index, stack), named calling
conventions with omitted-placement order, the marshalling scratch
naming scheme and unit count, per-operation spellings, constraints,
lowering templates and contracts, the frame model templates, and the
data-emission strategies. The portable core SHALL contain no target
register name, mnemonic spelling, clobber set, or instruction
sequence.

#### Scenario: Core is target-name-free
- **WHEN** the portable core sources are searched for target register
  names, operation spellings, or lowering instruction text
- **THEN** none appear outside the description loader and its tables

#### Scenario: Unsupported operation rejects
- **WHEN** source uses a semantic operation for which the active
  description declares no entry
- **THEN** assembly fails with the same stable-code diagnostic the
  capability gates raise today

### Requirement: Declared Spellings Drive Typed Parsing
Typed-operation parsing SHALL dispatch on the spellings the active
description claims. A spelling the description does not claim SHALL
fall through to raw passthrough unchanged. Register names in
placements and invoke sources SHALL be the description's register set.

#### Scenario: Unclaimed mnemonic passes through
- **WHEN** a line begins with a mnemonic the description does not
  claim
- **THEN** the line reaches the output as raw target assembly exactly
  as unknown mnemonics do today

#### Scenario: Register vocabulary comes from the description
- **WHEN** a member placement names a register absent from the active
  description's register set
- **THEN** assembly fails with a stable-code diagnostic

### Requirement: Template Lowerings With Declared Contracts
Each declared operation SHALL carry operand constraints drawn from a
bounded predicate vocabulary, a lowering template using only the
specified slot and arithmetic forms (substitution slots, byte slices,
parameter add/subtract, per-expansion fresh labels, per-line
conditionals on declared facts), and a declared contract naming
clobbered and preserved registers and flag validity. Validation SHALL
remain frontend-side; templates MAY delegate pure text expansion to
customasm ruledefs but their constraints and contracts SHALL live in
the description.

#### Scenario: Template emits the declared sequence
- **WHEN** a typed operation matches a declared entry and passes its
  constraints
- **THEN** the emitted text is the template's expansion with resolved
  slots, and the recorded events carry the declared contract

#### Scenario: Constraint failure is a frontend diagnostic
- **WHEN** an operand violates a declared constraint (width, range,
  stride, volatility)
- **THEN** the frontend rejects with a stable-code diagnostic before
  any text reaches customasm

### Requirement: Role-parameterized Algorithms
The invoke planner, frame arithmetic and table emission SHALL be
generic algorithms over declared data: marshalling order SHALL derive
from dependency scheduling over the bindings' declared defs and
clobbers (memory reads clobbering the accumulator role), and the frame
model SHALL be the description's templates parameterized by frame size
and member offset. For the console6502 description these SHALL
reproduce the current schedules and sequences exactly.

#### Scenario: Scheduler reproduces the current console6502 order
- **WHEN** an invocation with register-destination field reads is
  marshalled under the console6502 description
- **THEN** the emitted order equals today's register saves, field
  reads, assignments, then index-before-accumulator register reads

### Requirement: Declarable Data Strategies
Dispatch-entry and pool-table emission SHALL be strategies declared by
the description, selectable per declaration, over a fixed semantic
operation vocabulary that targets cannot extend. The console6502
strategies SHALL be split low/high byte tables and the symbolic
`(BASE+offset)` pool rows, preserving the current `method_table`,
`pool tables`, `data codeptr` and split `low()`/`high()` surfaces
unchanged.

#### Scenario: Strategy selection changes bytes, not surface
- **WHEN** the same `method_table` declaration is built under a
  description declaring a word-per-entry dispatch strategy
- **THEN** the source is unchanged and the emitted table layout
  follows the declared strategy

### Requirement: Description Verification
Every target description SHALL be cross-checked against the canonical
ISA description — a template emitting a mnemonic the ISA description
does not define SHALL fail the build — and SHALL carry lowering
references byte-compared in conformance. The console6502 migration
SHALL be accepted only with digest-identical forced Celeste builds at
every phase.

#### Scenario: Undefined mnemonic fails the build
- **WHEN** a description template emits a mnemonic absent from the
  canonical ISA description
- **THEN** the build fails naming the template and the mnemonic

#### Scenario: Migration is byte-neutral
- **WHEN** any migration phase completes and Celeste is force-built
  twice
- **THEN** both builds produce today's ROM digest
