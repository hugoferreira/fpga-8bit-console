# Design: declarable target descriptions

## Context

The intent for Inlay is a target-agnostic frontend engine, not a
portable language: programs are written against one target's physical
contracts, but the engine should accept different ISAs and know what to
do with them. The current implementation mixes three strata under one
mnemonic namespace — real target instructions with typed operands
(`lda [p + T.f]`), custom-ISA instructions surfaced semantically
(`mov`, `addw`), and pure frontend fabrications (`movw`, `decz`,
`tstw`, immediate `stw`, invoke marshalling, frames) — and nothing in
the source or the core distinguishes them. The event stream is a real
semantic boundary for the *emitter*, but everything upstream of it is
coupled:

- parser dispatch hardcodes mnemonic strings (`"lda "`, `"decz "`,
  `"movw "`) gated only by capability booleans;
- `la_slice_is_register` hardcodes `'a'`, `'x'`, `'y'` in the portable
  core;
- clobber contracts are composed as core string literals (`"a,flags"`);
- the frame model *is* the TSX/page-one sequence; invoke scratch *is*
  `t0`-`t7`; the register-field ordering *is* Y-X-A-through-A;
- two operations bake 6502 data strategy into the semantic vocabulary
  itself: `DATA_PROC_LOW`/`DATA_PROC_HIGH` and the low/high pool
  tables.

The repo already demonstrates both halves of the correct division:
customasm ruledefs do parameterized multi-instruction expansion
(counted shifts) with byte-level verification (`pseudo_check.py`
against a reference model), and `LaTarget` already declares
conventions, scratch prefix and units, displacement range, byte order
and capability flags. What is missing is the bridge as *data*.

## Goals / Non-Goals

**Goals:**

- One per-target description owns every target fact the frontend
  consumes: machine facts, registers and roles, conventions, scratch,
  operation spellings, constraints, lowering templates, contracts, the
  frame model, and data strategies.
- The core interprets descriptions and names no register, mnemonic,
  clobber, or instruction sequence itself.
- The semantic operation vocabulary stays fixed and small; strategy
  variation is declared, not encoded as new operation kinds.
- `console6502` becomes the first description; every phase is
  digest-gated against the current Celeste build (byte-neutral by
  construction).
- Descriptions are cross-checked against the canonical ISA description
  so declared spellings cannot drift from real encodings.

**Non-Goals:**

- Program portability. Contracts remain per-target physical facts;
  source written for one target is not expected to assemble for
  another.
- Register allocation, liveness analysis, or virtual values. Members
  remain typed names for physical locations.
- A second production target in this change. The deliverable is the
  engine and the console6502 description; a Z80/RISC-V/m68k
  description is future work that this change makes possible.
- Moving validation into customasm. Customasm owns encodings; it has
  no semantics, so width, range, volatility and contract checking stay
  frontend-side.
- Changing any language surface. Source that assembles today
  assembles identically after every phase.

## Decisions

### D1. Three-layer division of labor

Customasm owns encodings, including pure text-expansion pseudo-ops.
The core owns meaning: layout and path resolution, expressions,
modules, namespaces, coverage checking, the bounded workspace, and the
generic algorithms of D4. The target description is the bridge and
lives frontend-side, because the constraint-and-contract half of every
operation is meaning, not encoding: customasm would happily encode a
wrong-width access or a volatile-unsafe read-modify-write. Where a
lowering is pure text expansion with no layout knowledge, it may
delegate to a customasm ruledef; its constraints and contract still
live in the description.

### D2. The description's contents

A target description declares, as data:

- **Machine facts**: storage unit, byte order, pointer and code-pointer
  units, maximum displacement (signed or unsigned window), maximum
  alignment.
- **Registers and roles**: the register names valid in placements and
  invoke sources, each with a role — `accumulator` (the register
  memory reads pass through), `index`, `stack`. Roles, not names,
  parameterize the algorithms in D4.
- **Conventions**: named conventions with omitted-placement assignment
  order and return placement, replacing the hardcoded A-X-Y walk.
- **Scratch**: the marshalling scratch pool as a naming scheme plus
  unit count and location class.
- **Operations**: for each semantic operation kind the target
  supports — one entry with: the source spelling(s) it claims;
  operand-shape constraints (width, range, stride set, volatility
  rules) drawn from a bounded predicate vocabulary; a lowering
  template with substitution slots and bounded parameter arithmetic
  (`disp+1`, `imm[7:0]`, freshened labels); and a declared contract
  (clobbered registers and flags, meaningless flags, preserved
  registers). An operation kind with no entry is unsupported and
  rejects, exactly as the capability booleans gate today. A spelling
  the description does not claim falls through to raw.
- **Frame model**: prologue, epilogue, member-access and pointer-copy
  templates parameterized by frame size and member offset.
- **Strategies** (D5): dispatch-entry and pool-table emission forms.

### D3. Templates, not code

Lowering templates are the declarable analogue of the current emitter
cases: an ordered list of output lines with slots. The template
language is deliberately small — slots, byte-slicing, add/subtract on
parameters, a per-expansion fresh-label primitive, and per-line
conditionals keyed on declared facts (byte order, addend present).
Anything beyond that (loops over members, strategy selection) is a D4
algorithm calling templates, not a template. This is the discipline
that keeps the description from growing into an unbounded macro
language: the *shape* of every lowering is enumerated by the fixed
operation vocabulary; targets fill in text.

### D4. Algorithms parameterized by roles

The planner, frame arithmetic, coverage checking and table emission
stay in the core as generic algorithms over declared data:

- The invoke planner's phase structure generalizes: today's
  "register saves, field reads, assignments, then register-destination
  reads Y, X, A" is a hand-scheduled special case of scheduling by
  declared defs and clobbers, where field reads clobber the
  accumulator role. Emission order derives from a dependency ordering
  over the bindings' declared clobber sets; on a machine where any
  register loads memory, the same algorithm produces the natural
  schedule.
- Identity elision and overlap-only snapshotting already operate on
  names and are target-free once register names come from the
  description.
- Frame offsets, bias arithmetic, method-table coverage: already
  target-free; they call frame and strategy templates for text.

### D5. Fixed vocabulary, declarable strategies

The semantic operation vocabulary is fixed: load, store,
read-modify-write, test, branch-on-field, word move, address, call,
tail, frame operations, dispatch entry, table row. Targets cannot add
kinds — that would dissolve the event boundary. The two places 6502
strategy leaked into the vocabulary are re-cut:

- `DATA_PROC_LOW`/`DATA_PROC_HIGH` become one **dispatch-entry**
  operation whose emission strategy (split low/high byte tables versus
  word-per-entry) the description declares, with per-declaration
  override. `method_table` `code` slots and split lifecycle consumers
  keep their console6502 behavior via the split strategy.
- `pool tables` emission likewise selects a declared strategy; the
  console6502 strategy is the current symbolic `(BASE+offset)`
  low/high pair.

The surface syntax of `method_table`, `pool tables`, `data codeptr`
and split `low()`/`high()` data is unchanged; only where their bytes
come from moves.

### D6. Verification per target

A description without a reference rig is the "second handwritten
table" drift the native-encoder plan already warns about. The existing
discipline generalizes:

- **Digest identity** for the migration itself: at every phase the
  console6502 description must reproduce today's Celeste ROM
  byte-for-byte. The refactor's acceptance is that nothing observable
  changes while the knowledge moves.
- **Lowering references** per target: the structured fixture pattern
  (handwritten reference assembled and byte-compared) keyed by
  description entries.
- **Cross-check** against the canonical ISA description: every
  mnemonic a template emits must exist in the ISA description or the
  build fails. This closes the loop the docs already demand for the
  future native encoder.
- Contract tests (reference-model flag/value sweeps, as `asr` and
  `decz` have) remain per-target cost; a new target buys its
  simulator and references as part of its description, not as an
  afterthought.

### D7. What stays fixed and cannot be declared

Stated as boundaries, not defects:

- The **lexical frame** — brackets, `#`, `.` as member separator — is
  language-level. Dotted width suffixes (`move.w`) are permanently
  unspellable; target dialects choose spellings inside Inlay's lexical
  rules (the documented `asr.w` collision generalizes).
- **Contracts are data but not portable**: declaring them per target
  does not make programs port, and is not meant to.
- The **bounded model** is unchanged: descriptions load into the same
  caller-owned workspace with explicit limits and stable diagnostic
  codes; a description is bounded data, not executable configuration.

## Risks / Trade-offs

- [Template language creep toward TableGen] → the vocabulary of slots
  and predicates is enumerated in the spec; a lowering needing more
  than the template language offers is a D4 algorithm by definition,
  and adding a predicate or slot kind is a spec change, not a target
  file convenience.
- [Descriptions drift from encodings] → the D6 cross-check makes an
  undefined mnemonic a build failure; lowering references catch
  wrong-but-encodable output.
- [Planner generalization changes console6502 schedules] → digest
  identity is the gate; the dependency scheduler must reproduce the
  current Y-X-A order for the current corpus before it is trusted with
  anything else.
- [Performance of interpreting descriptions] → the description
  compiles once into the existing bounded tables at startup;
  per-line cost is a table lookup where today it is a strcmp chain.
- [A half-moved core is worse than an unmoved one] → phases are cut so
  each moves one knowledge category completely (registers, then
  spellings, then templates, then frames, then planner, then
  strategies); no category is ever half-data half-code across a
  commit boundary.

## Migration Plan

Each phase: move one knowledge category from core C into the
console6502 description, keep every gate green, and accept only on a
digest-identical forced Celeste build plus full `test-inlay` and
`test-celeste`. Order: (1) description structure and loader with digest
harness; (2) registers, roles, conventions, scratch; (3) operation
spellings and constraints; (4) lowering templates and contracts;
(5) frame model; (6) planner generalization to roles and dependency
scheduling; (7) dispatch and pool strategies; (8) ISA cross-check and
docs. Rollback is per-phase revert; no phase depends forward.

## Open Questions

- Whether the description is authored as a C structure, a checked-in
  declarative file parsed by the bounded core, or generated from the
  canonical ISA description. The cross-check requirement (D6) pulls
  toward generation for spellings and hand-authoring for contracts and
  templates.
- Whether raw-line passthrough should be able to consult the ISA
  description to reject unknown mnemonics early, or stay maximally
  permissive as today.
- Whether the second description worth building first is a real ISA
  (Z80, the nearest poverty-class cousin) or a deliberately hostile
  synthetic target whose only purpose is to keep the core honest.
