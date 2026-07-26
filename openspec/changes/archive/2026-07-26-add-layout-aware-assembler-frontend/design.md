## Context

customasm is a good host bootstrap assembler for this project because its
`#ruledef` files make new console instructions data rather than compiler
patches. Its macro-like rules are intentionally local: they match one source
form and emit bits or an instruction expansion. They do not maintain a nominal
type graph, procedure scope, typed-location environment or cross-instruction
semantic state.

The corpus now provides concrete evidence for a layer above that:

- Celeste maintains a 64-byte object shape through independent `O_*` constants
  and performs hundreds of accesses through `pObj`;
- Nemo independently maintains object, class and event-record layouts;
- Breakout uses static records and structure-of-arrays storage even though it
  does not present them as objects.

`docs/layout-aware-assembler-examples.md` explores the eventual language. This
change implements only its foundation: layouts and typed field operands. It
must prove that a new frontend can add semantics without changing emitted code.

The intended destination is a PICO-8-like in-console editor and assembler.
That assembler will not have Python, a host filesystem or a customasm process
available, and it must operate inside a deliberately bounded memory budget.
Therefore the semantic implementation created now must be portable to the
console. customasm text is one host output adapter, not the semantic
representation or permanent backend boundary.

The checkout is concurrently used by the Nemo and Celeste corpus work. The
implementation therefore uses new tool, test and documentation paths and does
not migrate or rewrite either corpus.

## Goals / Non-Goals

**Goals:**

- Establish a bounded portable semantic core shared by host and future console
  shells.
- Use a host shell to emit ordinary customasm during bootstrap.
- Calculate and inspect packed, nested, fixed-array layouts.
- Associate a target physical pointer location with a nominal pointee type.
- Lower explicit byte field loads and stores through a target interface.
- Provide diagnostics in terms of original source constructs.
- Prove Celeste layout and instruction-byte equivalence.
- Preserve the existing raw-customasm game builds.
- Make input, output, diagnostics and workspace storage platform-provided.
- Represent target lowering structurally so a future native encoder does not
  have to parse generated customasm.
- Create architectural seams that later changes can extend with procedures,
  frames, calling conventions, `invoke`, canonical ISA metadata and direct
  encoding.

**Non-Goals:**

- Replacing or forking customasm in the host build.
- Implementing the in-console editor shell or native machine-code encoder.
- Defining or generating the future canonical ISA description.
- Migrating Breakout, Nemo or Celeste to the new source format.
- Supporting native, aligned or explicitly overlaid structure layouts.
- Supporting unions, bitfields, enums, pools, objects or method tables.
- Supporting typed array indexing or general address materialisation.
- Supporting procedure syntax, locals, frames or calling conventions.
- Tracking register or pointer validity across raw instructions.
- Allocating registers, optimising instructions or specialising procedures.
- Supporting non-byte-addressed targets in the first implementation.
- Fixing the final console workspace size before the editor and storage model
  are designed; this change establishes measured capacities instead.

## Decisions

### Decision: build one portable core with host and console platform shells

The bootstrap host pipeline is:

```text
layout-aware source
        |
        v
host CLI + file adapter
        |
        v
bounded portable semantic core
        |
        +-- structured layout and lowering events
        |
        v
host customasm emitter
        |
        +-- generated customasm under build/
        +-- generated source map under build/
        |
        v
pinned customasm
        |
        +-- binary
        +-- symbols
        +-- readmemh
```

The intended console pipeline is:

```text
editor source buffer
        |
        v
console input adapter
        |
        v
the same bounded semantic core
        |
        +-- structured layout and lowering events
        |
        v
future native encoder
        |
        +-- executable RAM or cartridge image
        +-- compact symbols and diagnostics
```

In this change, customasm remains authoritative for host instruction encodings,
banks, final symbols and output formats. The core owns only the constructs it
can understand semantically and passes raw target assembly to the host adapter.
It does not model customasm text as the universal intermediate representation.

Alternatives considered:

- **Implement structures with `#ruledef` and constants.** This can encode an
  already-resolved offset but cannot diagnose nominal type mismatches, nested
  paths or location types.
- **Fork customasm.** This couples the language experiment to instruction
  encoding and output machinery that already works, raises the maintenance
  cost, makes architecture-neutral iteration slower and still produces a host
  binary that cannot run inside this console.
- **Write a host-only transpiler first.** Faster initially, but validates
  unbounded host data structures and creates a rewrite before self-hosting can
  begin.
- **Write a complete native assembler now.** Duplicates customasm before the
  new semantics have proven useful and requires an ISA metadata design that is
  not ready.

### Decision: implement the core in bounded portable C

The semantic core will use a conservative freestanding-friendly C subset that
can be built by the host toolchain and plausibly cross-compiled for the
extended-6502 console. It will not call a heap allocator or host service.

The host command remains a thin adapter:

```text
laasm --target console6502 \
      --output build/example.asm \
      --map build/example.map.json \
      tests/layout_aware/example.la.asm
```

The core API receives:

```text
workspace memory + per-table capacities
input callback + context
semantic/output callback + context
diagnostic callback + context
target description
```

The core returns stable status and diagnostic codes. The host shell owns file
opening, command-line parsing, JSON source-map serialisation, customasm process
execution and rich diagnostic formatting. A console shell can instead connect
an editor buffer, fixed RAM regions, compact diagnostics and a future native
encoder.

Core semantic objects use bounded integer handles or workspace-relative offsets
across tables. They do not persist host-native pointers. Parsers use explicit
bounded stacks or enforce nesting before consuming platform call stack.

Alternatives considered:

- **Python.** Excellent as a reference oracle and corpus-analysis language, but
  unavailable on the target and encourages data structures that hide memory
  budgets.
- **Rust or Zig.** Attractive host implementations, but neither provides the
  conservative 6502 bootstrap path this project needs.
- **Write the core directly in console assembly.** Maximises control but makes
  early semantic iteration and host diagnostics unnecessarily expensive.
- **Parser generator.** Deferred until the grammar contains enough ambiguity to
  justify one, and any future generator must be able to emit bounded tables for
  the console.

### Decision: use a deliberately small, line-oriented language boundary

The frontend recognises these top-level constructs:

```asm
struct Fixed8_8 packed
    fraction : u8
    integer  : i8
end

struct CelesteObject packed
    ...
    hitbox   : Hitbox
    hair     : HairNode[5]
    reserved : u8[7]
end

static_assert CelesteObject.size == 64
static_assert CelesteObject.hitbox.w.offset == 14

location pObj : ptr CelesteObject
```

All other lines are raw target assembly except when they contain the explicit
typed operand form:

```asm
sta [pObj + CelesteObject.hitbox.w]
```

Using an explicit form rather than initially supporting `[pObj.hitbox.w]`
avoids inference ambiguity and keeps the nominal root visible in generated
diagnostics. Short typed-location sugar is deferred.

The core parser does not attempt to understand arbitrary customasm syntax in
this slice. It scans only frontend declarations and target-registered typed
operand forms. Raw text, blank lines and comments are delivered to the selected
platform emitter unchanged. A future native assembler must add a bounded parser
and encoder for raw target instructions; this change neither implements nor
hides that requirement.

### Decision: v1 supports packed byte-addressed layouts only

`u8`, `i8`, `u16` and `i16` have fixed bit widths. `ptr T` gets its size from
the target; it is two bytes for `console6502`. Structures are nominal, packed
and ordered. Arrays have a constant positive count and use their element size
as stride.

Every structure has alignment one in this slice. Layout quantities are measured
in addressable storage units, which are bytes for all initial targets.

This intentionally postpones the hardest portable-layout questions:

- target-native ABI padding;
- alignment greater than one;
- explicit offsets and overlapping fields;
- unions and bitfields;
- non-byte-addressed machines.

Celeste is the first fixture precisely because its existing object record is
packed and therefore requires none of those unresolved policies.

### Decision: build an explicit bounded semantic model before emission

The core fills caller-sized tables conceptually equivalent to:

```text
Module
  structure handles
  location handles
  assertion handles
  ordered source-node handles

Structure
  interned-name handle
  first-field handle + count
  size
  alignment

Field
  interned-name handle
  declared-type handle
  offset
  size
  optional count and stride

Location
  interned source-name handle
  physical-location handle
  pointer-type handle
```

Layout resolution occurs as a dependency graph. Forward structure references
are allowed; duplicate names, unknown names and recursive by-value cycles are
errors. Pointer references do not create a value-layout dependency.

Every table has an explicit capacity. Names live in a caller-provided byte
arena and are referred to by offsets or handles. Graph walks and expression
evaluation use bounded explicit stacks. Capacity exhaustion is a normal
diagnostic path, never a failed allocation or truncated object.

Nested field paths are resolved into a `ResolvedField` carrying:

- root nominal type;
- component path;
- total outer-relative displacement;
- leaf type;
- size;
- array metadata when applicable;
- original source span.

Platform emitters consume resolved handles and structured operations rather
than recalculating offsets. Test adapters can inspect the same semantic events
without generating text.

### Decision: reserve a frontend namespace and emit stable mangled constants

The host customasm emitter generates symbols using a prefix that ordinary input
is forbidden to define:

```text
__la_<type>__size
__la_<type>__align
__la_<type>__<field-path>__offset
__la_<type>__<field-path>__size
__la_<type>__<array-path>__count
__la_<type>__<array-path>__stride
```

Identifiers are escaped component by component so two legal source identifiers
cannot map to the same output symbol. The exact escaping algorithm and frontend
format version are documented and golden-tested.

The leading prefix avoids customasm's dot-local label semantics. Constants are
emitted in stable declaration/path order, never map iteration order.

Typed operand lowerings refer to generated constants rather than repeating
numeric offsets:

```asm
sta (pObj), #__la_CelesteObject__hitbox__w__offset
```

This keeps host-generated assembly inspectable while allowing customasm to
perform its normal expression and operand-range checks. These symbol spellings
do not exist in the core semantic model and are not required by a future native
encoder.

### Decision: targets lower to bounded structured operations

The language layer must not contain 6502 register names or instruction forms. A
target description and lowering callback declare:

- target name and format version;
- storage-unit width and pointer width;
- legal physical-location classes;
- recognised typed operand patterns;
- accepted leaf types and widths;
- displacement range;
- deterministic lowering function producing structured operations;
- scratch and clobber metadata;
- target-specific diagnostic notes.

Conceptually:

```text
lower_field_access(
    operation,
    base_location,
    resolved_field,
    source_span
) -> TargetOperation | LoweringError
```

The first `console6502` target recognises:

```asm
lda [base + Type.path]
sta [base + Type.path]
```

where `base` is a declared two-byte zero-page pointer location, the leaf is one
byte, and the displacement fits `u8`. It produces a bounded operation record
such as:

```text
LOAD8_PTR_DISP  base-handle, displacement, source-span
STORE8_PTR_DISP base-handle, displacement, source-span
```

The host customasm emitter renders those records as:

```asm
lda (base), #offset
sta (base), #offset
```

These forms map directly to the existing `ext_ptr` rules and require no
frontend-selected scratch register. A future native encoder will consume the
same operation records without parsing those strings.

An NMOS sequence using `Y` is not part of this change. Adding it later should
be a new lowering policy because it has a different clobber contract.

Alternatives considered:

- **Declarative host JSON target files.** Unavailable in-console and too weak
  once address materialisation and parallel moves become real.
- **Let customasm macros see the field model.** customasm has no channel for
  receiving the nominal type graph or returning semantic diagnostics.

### Decision: customasm rules are transitional, and native encoding needs one ISA source

The project must not eventually maintain:

```text
src/isa/*.asm          -- host encodings
console encoder tables -- independently handwritten encodings
```

That would allow the host and in-console assemblers to disagree. Before direct
encoding is implemented, a later change must define one canonical
machine-readable ISA description capable of producing or mechanically
verifying:

- host customasm `#ruledef` files;
- compact in-console encoder tables;
- operand ranges and addressing-mode metadata;
- optionally disassembler and editor completion metadata.

This first slice does not choose that format and does not duplicate the full
opcode table. Its `console6502` target describes only the structured field
operations required for conformance and delegates actual byte encoding to the
existing host customasm rules.

### Decision: typed locations are aliases, not values

The declaration:

```asm
location pObj : ptr CelesteObject
```

associates the source name and target physical spelling `pObj` with a pointer
type. It allocates nothing and preserves nothing.

This slice does not analyse raw instructions, calls or control flow, so it
cannot diagnose that raw assembly overwrote `pObj`. That diagnostic belongs to
a later procedure/clobber slice. It can and will diagnose a mismatch between
the declared pointee type and the explicit root type in a field operand.

### Decision: diagnostics are core events; source maps are a host output

The core reports a stable diagnostic code, source span and bounded argument
handles or values. It does not format paths, allocate messages or know JSON.

The host emitter writes deterministic JSON containing:

- frontend format version;
- original source identity expressed without host-specific absolute paths;
- generated file identity;
- each generated line range;
- original line and column range;
- whether the line is pass-through or frontend-generated;
- the originating declaration or operand kind.

The host-generated customasm also contains human-readable comments before
generated blocks and semantic expansions.

The host wrapper captures customasm stderr, recognises its pinned-version
location format and prints the original location followed by the unchanged
downstream message. If a diagnostic cannot be mapped, it reports the generated
location without guessing. A console shell may instead render a compact error
directly in the editor from the same core diagnostic event.

Alternatives considered:

- **Only `#line` directives.** customasm does not provide a documented source
  remapping directive in the pinned workflow.
- **Only generated comments.** Useful for inspection but insufficient for
  automated diagnostics.

### Decision: validate semantics and byte identity separately

The test layers are:

1. host and in-memory input-adapter equivalence tests;
2. lexer and expression unit tests;
3. layout graph and property unit tests;
4. typed-location and structured target-lowering unit tests;
5. workspace and every-table capacity-boundary tests;
6. diagnostic-code and host-format golden tests;
7. deterministic semantic-event, emitted-source and map golden tests;
8. pinned-customasm acceptance tests;
9. Celeste conformance tests comparing every represented offset;
10. instruction byte-identity tests comparing translated and handwritten
   extended-6502 field accesses.

The Celeste fixture lives in a new test path and is derived from the current
layout without editing `src/celeste/`. It includes enough representative
`player_init` stores to exercise nested and scalar fields.

No generated customasm is committed. Expected semantic properties and compact
golden diagnostics may be committed; build products remain under `build/`.

Tests run the same semantic core under both generous host capacities and
deliberately small workspaces. Boundary cases fill each table exactly, then add
one item and require the documented capacity diagnostic. Sanitizer-enabled host
tests guard the failure paths against out-of-bounds access.

### Decision: reject future syntax explicitly

The lexer reserves the eventual keywords `proc`, `frame`, `naked`, `callconv`,
`invoke`, `pool`, `object`, `interface` and `method_table`. Encountering them
as frontend declarations produces a “recognised but deferred” diagnostic. The
host CLI likewise rejects requests for native binary output or an in-console
shell as deferred.

This avoids accidentally passing a misspelled or premature high-level construct
through as raw customasm and makes the first implementation boundary testable.

It does not reserve ordinary target labels with those names when followed by
the target's label punctuation.

## Risks / Trade-offs

- **[Risk] The pass-through boundary misclassifies customasm text.** →
  Frontend constructs begin with a small reserved grammar, typed operands use
  explicit brackets and target modules only claim exact registered forms.
  Unknown lines are preserved byte-for-byte.
- **[Risk] A line-oriented parser becomes a dead end.** → Keep the lexer,
  semantic model and target protocol independent from the outer parser. Replace
  the parser later without changing layout or backend APIs.
- **[Risk] Conservative C slows early implementation and increases manual
  bookkeeping.** → Keep the first grammar narrow, centralise table/arena access,
  run sanitizer builds on the host and treat explicit capacity behaviour as a
  product requirement rather than incidental overhead.
- **[Risk] A host build accidentally validates a wider C/runtime subset than
  the console can support.** → Add a portability check forbidding heap and host
  APIs in core modules, isolate all libc-heavy functionality in the shell and
  add an early cross-compiler smoke build before production migration.
- **[Risk] Fixed capacities reject legitimate programs.** → Make every limit
  caller-configurable, measure real corpus fixtures, report the exact exhausted
  table and defer the final console profile until editor/storage budgets exist.
- **[Risk] Native pointers or recursion leak into persistent state.** → Store
  inter-table references as integer handles, use bounded explicit stacks and
  test at the configured nesting boundary.
- **[Risk] Generated symbols collide with user assembly.** → Reserve and
  validate the `__la_` namespace before emission.
- **[Risk] Source-map remapping depends on customasm diagnostic formatting.** →
  Pin the existing customasm version, fixture its error format and fall back to
  the generated location when a message is not recognised.
- **[Risk] Byte identity proves only encoding, not that the abstraction is
  pleasant.** → Keep the first migration separate; after the frontend works,
  evaluate representative source ergonomics before adopting it.
- **[Risk] The target interface is overdesigned from one backend.** → Expose
  only operations required by the first fixture and require a second
  architecture spike before claiming the interface stable.
- **[Risk] Host customasm output becomes an accidental permanent IR.** → Keep
  customasm naming and JSON maps in the host emitter; test the core through an
  alternate semantic-event sink.
- **[Risk] Host and future console opcode tables drift.** → Do not create a
  second full table in this change; require a canonical ISA-description change
  before native encoding.
- **[Risk] The portable core is too slow or large in-console.** → Record host
  operation counts, table high-water marks and workspace size now; require an
  actual console-profile measurement before claiming the port is viable.
- **[Risk] Layout declarations become a second source of truth.** → Keep them
  in conformance fixtures for this change and compare against current constants.
  A later migration must replace, not duplicate, production declarations.
- **[Risk] Concurrent corpus work changes Celeste offsets.** → The fixture
  comparison reads the authoritative current layout at test time or uses an
  explicitly reviewed baseline; implementation does not edit Celeste-owned
  paths.

## Migration Plan

1. Add the bounded portable core, in-memory adapters and structured target
   protocol without changing any existing build rule.
2. Add the host CLI, file adapters, customasm emitter and JSON source-map
   adapter around that core.
3. Add unit, capacity-boundary, sanitizer and golden tests for layouts,
   expressions, diagnostics, structured lowering and deterministic emission.
4. Add the Celeste-derived conformance fixture and compare its properties
   against the authoritative current object layout.
5. Assemble translated and handwritten field-access fixtures with pinned
   customasm and require byte identity.
6. Add an opt-in `make test-layout-asm` conformance target.
7. Measure translation time, operation counts, workspace high-water marks and
   every table's high-water mark; record the language and target format
   versions.
8. Perform a portability audit or available cross-compiler smoke build proving
   that core modules do not require the host shell or heap.
9. Stop at the gate: production adoption, canonical ISA metadata, native
   encoding and the in-console shell each require later OpenSpec work with
   their own memory and equivalence evidence.

Rollback consists of removing the new core, host shell, target, fixtures and
opt-in test target. Existing game builds are unaffected throughout this change.

## Open Questions

- Should the frontend source extension be `.la.asm`, `.lasm` or another name?
  Proposed for the prototype: `.la.asm`, preserving editor recognition as
  assembly.
- Which exact C subset and cross-compiler define the portability gate?
  Proposed: keep the core freestanding-friendly and compiler-neutral in this
  change, run the host compiler in strict mode, and select the console compiler
  only when the first console-shell spike is proposed.
- What default host capacities should ship? Proposed: derive generous defaults
  from the Celeste fixture plus a synthetic stress fixture, while tests always
  exercise caller-selected smaller profiles.
- What final workspace can the in-console assembler consume alongside the
  editor, source buffer, program image and runtime? Deferred until those four
  regions are designed together; this change records high-water marks rather
  than guessing a number.
- Should generated property symbols include `.type` metadata in v1 even though
  customasm cannot consume a nominal type value? Proposed: no; keep type
  metadata in the source map and semantic model.
- Should public constant emission include every nested path or only properties
  referenced by source? Proposed: every path, because complete layout
  inspection is useful and deterministic for these small structures.
- How should the conformance test consume the current Celeste offsets without
  creating a fragile parser for arbitrary assembly? Proposed: a narrow
  assignment extractor over the contiguous `O_*` declaration block, failing
  loudly on syntax it does not recognise.
- What is the canonical ISA-description format that can produce both customasm
  rules and compact native encoder tables? Deferred to the native-encoder
  change; this slice deliberately creates no duplicate complete opcode table.
- Which materially different architecture should validate the target protocol
  next? ARMv7 is the strongest candidate because its address materialisation
  and register conventions differ substantially from this 6502, but that spike
  is outside this change.
