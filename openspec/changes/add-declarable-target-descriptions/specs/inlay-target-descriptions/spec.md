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
description claims. The first token of an operation-position line
SHALL lex greedily through dots and SHALL never be rewritten by the
scoped-raw qualifier, so declared spellings MAY contain dots; dots in
operand position remain member separators. A spelling the description
does not claim SHALL fall through to raw passthrough unchanged.
Register names in placements and invoke sources SHALL be the
description's register set.

#### Scenario: Dotted mnemonic lexes as one opcode
- **WHEN** a description claims the spelling `move.w` and source
  contains `move.w Fixed.word1, d0`
- **THEN** the line dispatches to that entry with `Fixed.word1`
  resolved as a qualified operand, and the mnemonic token is not
  qualified-name rewritten

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
specified forms — the enumerated substitution slots (base, aux, aux2,
index, scratch, scoped-raw tail, displacement and successor,
immediate halves, byte-update immediate, signed immediate, mangled
offset symbol, qualified procedure symbol, page-one frame addresses,
provenance) and the three line prefixes (repeat-by-count,
emit-when-count-nonzero, per-line source-map reason) — and a declared
contract naming clobbered and preserved registers and flag validity.
Extending the slot or prefix vocabulary SHALL be a specification
change, not a target-file convenience. Validation SHALL remain
frontend-side; templates MAY delegate pure text expansion to customasm
ruledefs but their constraints and contracts SHALL live in the
description.

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

#### Scenario: Count-driven lines express the frame model
- **WHEN** a procedure with a three-byte frame is emitted under a
  description whose prologue template repeats a push line by count and
  whose epilogue guards its stack-adjust lines on a nonzero count
- **THEN** the prologue emits three pushes, the epilogue emits the
  adjust sequence, and a zero-frame procedure emits neither

### Requirement: Role-parameterized Algorithms
The invoke planner, frame arithmetic and table emission SHALL be
generic algorithms over declared data: each marshalling item SHALL
declare what it reads, what it writes, and whether it passes through
the accumulator role, and emission order SHALL derive from dependency
scheduling over those declarations — reads before their resource is
overwritten, same-binding saves and reads before their assignment,
accumulator readers before accumulator clobbers, the
accumulator-destination item after every clobber — with the legacy
class order used only as the deterministic tie-break between
independent items. A binding set with no safe order SHALL be a
stable-code diagnostic. The frame model SHALL be the description's
templates parameterized by frame size and member offset. For the
console6502 description these SHALL reproduce the current schedules
and sequences exactly.

#### Scenario: Scheduler reproduces the current console6502 order
- **WHEN** an invocation with register-destination field reads is
  marshalled under the console6502 description
- **THEN** the emitted order equals today's register saves, field
  reads, assignments, then index-before-accumulator register reads

#### Scenario: Unorderable bindings are a diagnostic
- **WHEN** an invocation's items admit no order satisfying the
  dependency rules
- **THEN** assembly fails with a stable-code diagnostic instead of
  emitting a schedule that violates parallel-assignment semantics

### Requirement: Declarable Data Strategies
Table emission SHALL be strategies declared by the description, over a
fixed semantic operation vocabulary that targets cannot extend. A
strategy SHALL declare its lanes — one emitted table each — and each
lane SHALL carry the spellings a declaration site may name it by, the
label suffix, the storage a row occupies, and the templates for a
filled and an absent entry; a lane declaring no absent template SHALL
reject an absent entry with a stable-code diagnostic. A declaration
site SHALL select its lane by the spelling the description claims, and
the declared width SHALL be the selected lane's row width. The
console6502 strategies SHALL be split low/high dispatch tables,
word-per-entry dispatch, byte value rows and the symbolic
`(BASE+offset)` pool rows, preserving the current `method_table`,
`pool tables`, `data codeptr` and split `low()`/`high()` surfaces
unchanged.

#### Scenario: Strategy selection changes bytes, not surface
- **WHEN** the same `method_table` declaration is built under a
  description declaring a word-per-entry dispatch strategy
- **THEN** the source is unchanged and the declaration emits one table
  per column with two-unit entries instead of split low/high tables

#### Scenario: Table without a declared strategy rejects
- **WHEN** a declaration emits a table of a kind the active
  description declares no strategy for
- **THEN** assembly fails with a stable-code diagnostic instead of
  emitting core-authored rows

### Requirement: Description Verification
Every target description SHALL be cross-checked against the canonical
ISA description — a template emitting a mnemonic the ISA description
does not define SHALL fail the build — and SHALL carry lowering
references byte-compared in conformance. The console6502 migration
SHALL be accepted only with digest-identical forced Celeste builds at
every phase.

#### Scenario: Every template carries a reference
- **WHEN** conformance compares the templates the description declares
  against the templates the byte-compared fixtures exercise
- **THEN** a template no reference reaches fails the run, naming it,
  unless it is listed as unreachable with its reason

#### Scenario: Undefined mnemonic fails the build
- **WHEN** a description template emits a mnemonic absent from the
  canonical ISA description
- **THEN** the build fails naming the template and the mnemonic

#### Scenario: Migration is byte-neutral
- **WHEN** any migration phase completes and Celeste is force-built
  twice
- **THEN** both builds produce today's ROM digest
