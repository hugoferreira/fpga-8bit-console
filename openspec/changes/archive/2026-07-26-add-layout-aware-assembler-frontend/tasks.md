## 1. Portable Core and Host Shell

- [x] 1.1 Add new C core modules and a public API under a tool-owned path for
  source spans, stable diagnostic codes, workspace configuration, semantic
  events, target descriptions and compile status.
- [x] 1.2 Define caller-owned byte arenas and explicit capacities for tokens,
  interned names, structures, fields, locations, expressions, fixups,
  diagnostics and nesting, using bounded handles or workspace-relative offsets
  for persistent cross-table references.
- [x] 1.3 Add input, semantic-output and diagnostic callback interfaces plus
  in-memory adapters that exercise the core without files, JSON or process
  execution.
- [x] 1.4 Add a host `laasm` shell with `--target`, `--output`, `--map` and
  input-path arguments, actionable usage errors and versioned language, target
  and host-output formats.
- [x] 1.5 Add host file, JSON source-map and customasm-process adapters outside
  the core, keeping generated `.asm` and map files beneath `build/`.
- [x] 1.6 Add CLI smoke tests covering help, missing input, unknown target,
  successful output creation and refusal to overwrite an input path.
- [x] 1.7 Add a core portability check that rejects heap allocation and direct
  filesystem, process, environment, locale or JSON dependencies in core
  modules, plus strict host-compiler and sanitizer build modes.
- [x] 1.8 Define and test the `.la.asm` prototype file convention.

## 2. Lexer and Outer Parser

- [x] 2.1 Implement bounded token records with source identifiers, line and
  column spans for identifiers, integer literals, punctuation, operators and
  frontend keywords.
- [x] 2.2 Implement line-aware comment and whitespace handling that preserves
  raw customasm lines byte-for-byte when the frontend does not own them.
- [x] 2.3 Parse packed `struct` blocks, named fields, primitive and nominal
  types, pointer types and fixed positive array counts.
- [x] 2.4 Parse `location`, `static_assert` and the explicit
  `[base + Type.field.path]` operand form without parsing unrelated customasm
  instruction syntax.
- [x] 2.5 Recognise the deferred declaration keywords and emit targeted
  “recognised but deferred” diagnostics while permitting ordinary raw labels
  with similar names.
- [x] 2.6 Add parser tests for valid mixed frontend/customasm files, malformed
  declarations, unterminated structures, invalid arrays and pass-through
  preservation.
- [x] 2.7 Run identical source through the memory and host-file input adapters
  and assert identical ordered semantic events and diagnostic codes.
- [x] 2.8 Fill the token, name and parser-stack capacities exactly and then
  exceed each by one, asserting deterministic capacity diagnostics and clean
  sanitizer runs.

## 3. Type and Layout Semantics

- [x] 3.1 Implement `u8`, `i8`, `u16`, `i16` and target-sized `ptr T` semantic
  types with sizes measured in target storage units.
- [x] 3.2 Build bounded nominal structure and field tables with duplicate
  structure and duplicate field diagnostics.
- [x] 3.3 Resolve forward nominal references as a dependency graph and reject
  unknown types and recursive by-value layout cycles with source-correlated
  paths.
- [x] 3.4 Calculate packed field offsets, structure size and alignment for
  primitive, nested and fixed-array fields without implicit padding.
- [x] 3.5 Resolve nested field paths into outer-relative displacement, leaf
  type, size, count and stride metadata.
- [x] 3.6 Add semantic tests for the complete `Fixed8_8`, `Hitbox`, `HairNode`
  and 64-byte `CelesteObject` layout, including the seven-byte reserved tail.
- [x] 3.7 Add failure tests for duplicate names, zero/negative array counts,
  unknown nested fields, invalid scalar array properties and value-layout
  cycles.
- [x] 3.8 Fill the structure, field, type and resolved-path capacities exactly
  and exceed each by one without truncation or memory corruption.

## 4. Compile-time Expressions and Generated Properties

- [x] 4.1 Implement compile-time expression parsing and evaluation with bounded
  explicit stacks for integer constants, parentheses, arithmetic, comparison
  and boolean operators with documented precedence.
- [x] 4.2 Resolve structure and field `.size`, `.align`, `.offset`, `.count` and
  `.stride` properties and reject properties that do not apply to the selected
  object.
- [x] 4.3 Evaluate `static_assert` before emission and report the failing
  expression with evaluated operands.
- [x] 4.4 Specify and implement collision-free `__la_` name mangling for all
  public layout properties, including identifier escaping and a generated
  format version.
- [x] 4.5 Detect raw-source definitions in the reserved generated namespace
  before emitting customasm.
- [x] 4.6 Add deterministic golden tests for the complete ordered constant block
  emitted from nested Celeste layouts.
- [x] 4.7 Exercise expression-node and nesting capacities at their exact limits
  and require a bounded diagnostic before platform stack or workspace
  exhaustion.

## 5. Typed Locations and Target Lowering

- [x] 5.1 Implement typed physical-location declarations as non-allocating
  aliases and validate that their pointee type agrees with the explicit root
  type in each field operand.
- [x] 5.2 Define the target protocol for storage-unit and pointer widths,
  physical-location validation, recognised typed operations, displacement
  limits, leaf widths, bounded structured lowering operations, scratch
  requirements and diagnostics.
- [x] 5.3 Implement the `console6502` target with two-byte zero-page pointer
  locations and byte `lda`/`sta` field operations lowered to structured
  `LOAD8_PTR_DISP` and `STORE8_PTR_DISP` operations.
- [x] 5.4 Implement the host customasm emitter for those structured operations,
  producing the existing `(zp), #disp` syntax without embedding that spelling
  in the semantic core.
- [x] 5.5 Reject non-byte leaves, displacements outside `u8`, unsupported typed
  instructions and unavailable scratch requirements without falling back to
  truncation or an unmodelled clobber.
- [x] 5.6 Add target tests for valid loads and stores, pointee-type mismatch,
  invalid physical locations, width mismatch, displacement overflow and
  unsupported operations.
- [x] 5.7 Add a non-text test sink that consumes the same structured operations
  and proves no customasm parsing or generated-symbol knowledge is required.
- [x] 5.8 Exercise target-operation and physical-location capacities at and one
  past their limits.
- [x] 5.9 Confirm that location declarations alone emit no storage,
  initialisation or preservation code.
- [x] 5.10 Document and test that native binary emission and complete native
  opcode tables are deferred; add no second handwritten ISA table.

## 6. Host Emission, Source Maps and Downstream Diagnostics

- [x] 6.1 Implement deterministic customasm emission with a generated header,
  stable layout-constant order, preserved raw lines and inspectable comments
  around typed operand expansions, entirely outside the semantic core.
- [x] 6.2 Implement the versioned deterministic JSON source-map format for
  pass-through lines, generated declarations and typed operand expansions
  without embedding host-specific absolute paths.
- [x] 6.3 Add a wrapper mode that invokes the repository's pinned customasm,
  captures its diagnostics and maps recognised generated locations back to the
  original source while retaining the downstream message.
- [x] 6.4 Fall back honestly to generated file locations when a customasm
  diagnostic cannot be mapped, without guessing an original line.
- [x] 6.5 Add golden diagnostic tests for lexical, parse, layout, type,
  capacity, assertion and lowering codes, their host-formatted messages, plus
  mapped and unmapped customasm failures.
- [x] 6.6 Translate the same fixture twice in isolated build directories and
  assert byte-identical customasm and source maps.
- [x] 6.7 Compare semantic events produced through host and memory adapters
  independently of customasm and JSON output.
- [x] 6.8 Verify that the core links and runs its semantic tests without the host
  customasm, filesystem and JSON adapter modules.

## 7. Celeste Corpus Conformance

- [x] 7.1 Add a new layout-aware conformance fixture outside `src/celeste/`
  declaring `Fixed8_8`, `Hitbox`, `HairNode` and the full 64-byte
  `CelesteObject`.
- [x] 7.2 Add a narrow read-only extractor for the contiguous authoritative
  Celeste `O_*` assignment block that fails loudly on unrecognised declaration
  syntax.
- [x] 7.3 Compare every represented fixture field against its current `O_*`
  offset and assert size 64, hair offset 37 and all nested hitbox offsets.
- [x] 7.4 Add representative typed `player_init` stores covering direct and
  nested fields and a handwritten customasm reference using the same
  `ext_ptr` forms.
- [x] 7.5 Assemble translated and handwritten fixtures with pinned customasm
  and assert instruction-byte identity.
- [x] 7.6 Add negative conformance tests proving that moved fields, a grown
  record and a mistyped pointer base fail before generated code is accepted.

## 8. Integration and Documentation

- [x] 8.1 Add the opt-in `test-layout-asm` target without reformatting or
  reordering either corpus block.
- [x] 8.2 Add the frontend tests to the relevant non-production test aggregate
  while confirming all existing game assembly commands retain their current
  prerequisites and source paths.
- [x] 8.3 Document the portable-core/platform-shell boundary, caller-owned
  workspace contract, supported first-slice grammar, structured target
  operations, host customasm emitter, generated namespace, source maps and
  raw-assembly escape hatch.
- [x] 8.4 Update `docs/layout-aware-assembler-examples.md` to mark syntax that
  the first slice implements, explain the eventual in-console pipeline and mark
  native encoding, canonical ISA generation and other later syntax as deferred.
- [x] 8.5 Document that customasm is the initial host backend rather than the
  permanent semantic IR, and record the requirement for one future canonical
  ISA description to serve host rules and in-console encoder tables.
- [x] 8.6 Measure and record translation time, semantic operation count,
  workspace high-water mark and every bounded table's high-water mark for the
  Celeste fixture and a synthetic large mixed-source file.
- [x] 8.7 Run core unit and capacity tests, sanitizer builds, adapter-equivalence
  tests, diagnostic goldens, deterministic-output checks, Celeste layout
  conformance, customasm byte-identity checks and the existing assembler rule
  tests.
- [x] 8.8 Perform an available 6502 C cross-compiler smoke build of the core, or
  if no suitable compiler is present, run and document the strict portability
  audit without claiming console execution.
- [x] 8.9 Verify with `git diff` that no production game source, RTL, opcode,
  memory-map or simulator file changed as part of this frontend-foundation
  slice.
- [x] 8.10 Record the gate result and stop without migrating a game or adding a
  native encoder; create separate OpenSpec changes for corpus adoption,
  canonical ISA metadata and the in-console shell.
