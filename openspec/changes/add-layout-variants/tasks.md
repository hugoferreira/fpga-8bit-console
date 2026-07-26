## 1. Bounded Variant Model

- [x] 1.1 Add public enum, enum-member, aggregate-kind, layout-policy,
  explicit-offset and overlay semantic records without embedding host or
  customasm details.
- [x] 1.2 Add independent enum, enum-member, union and overlay limits,
  statistics, workspace partitions and stable capacity diagnostics.
- [x] 1.3 Publish ordered semantic events for resolved enum members, union
  properties, explicit field offsets and overlay bases.
- [x] 1.4 Test exact and one-past capacities plus deterministic event streams
  under multiple sufficient profiles in strict C89.

## 2. Nominal Enums

- [x] 2.1 Parse canonical `enum Name : primitive` declarations with explicitly
  valued, uniquely named members and a terminating `end`.
- [x] 2.2 Resolve signed and unsigned `u8`, `i8`, `u16` and `i16` member values,
  qualified enum expressions and permitted equal-value aliases.
- [x] 2.3 Admit complete enum types in structure, union and array fields with
  the exact underlying size while retaining nominal type identity.
- [x] 2.4 Emit stable collision-free host constants for enum members without
  rewriting raw target instruction text.
- [x] 2.5 Test duplicate names, invalid underlying types, signed/unsigned range
  edges, overflow, qualified lookup, aliases, incomplete references and
  declaration-order resolution.

## 3. Explicit Structure Offsets

- [x] 3.1 Make omitted aggregate policy mean packed, retain optional `packed`,
  and parse mutually exclusive `aligned(N)` for structures and unions.
- [x] 3.2 Validate positive power-of-two alignment against target metadata and
  publish the selected policy and resolved aggregate alignment.
- [x] 3.3 Extend field grammar with `at <constant-expression>` while preserving
  existing unqualified field syntax.
- [x] 3.4 Resolve packed offsets against a monotonic storage-unit cursor,
  include unnamed omitted regions in total extent and publish the resolved
  offset without manufacturing fields for gaps.
- [x] 3.5 Resolve aligned primitive, enum, pointer, array and nested-aggregate
  field alignment, automatic padding and rounded total size deterministically.
- [x] 3.6 Require explicit offsets in aligned structures to satisfy both
  monotonic cursor and effective field-alignment constraints.
- [x] 3.7 Reject negative, overflowing, backward, overlapping, misaligned and
  conflicting-policy placements without implicit fields or initialisation.
- [x] 3.8 Verify nested paths, arrays, enums and unions retain correct offset,
  size, alignment, count and stride properties after automatic and explicit
  gaps.
- [x] 3.9 Prove omitted and explicit `packed` spellings have identical events,
  properties and output across existing fixtures.
- [x] 3.10 Prove every existing structure fixture and complete Celeste layout
  retains its prior generated properties and bytes.
- [x] 3.11 Propagate aligned aggregate requirements into pools, overlays and
  frame locations and reject storage classes or resolved bases that cannot
  satisfy them.

## 4. Nominal Unions

- [x] 4.1 Parse canonical `union Name`, optional `packed` and `aligned(N)`
  declarations using the existing field grammar but rejecting member `at`.
- [x] 4.2 Resolve every union member at offset zero and compute packed or
  aligned maximum extent, tail rounding and alignment properties.
- [x] 4.3 Extend the bounded aggregate dependency resolver and path traversal
  across structure/union nesting without recursive host-stack traversal.
- [x] 4.4 Diagnose duplicate members, unknown or incomplete member types,
  zero-member policy violations and direct or mixed structure/union cycles.
- [x] 4.5 Test primitive, enum, pointer, fixed-array and aggregate union members
  plus nested byte-leaf loads and stores.

## 5. Non-owning Overlays

- [x] 5.1 Parse `overlay name : Type at BASE` for a complete structure or union
  and permit multiple overlays over the same target symbol.
- [x] 5.2 Keep overlay declarations allocation-free and reject arrays,
  primitives, pointers, unknown types and malformed bases in the initial form.
- [x] 5.3 Resolve explicit type-qualified overlay field operands to nominal
  owner, target base, displacement and width without manufacturing a pointer.
- [x] 5.4 Add structured console6502 static-overlay byte load/store operations,
  host customasm lowering, source-map entries and declared clobbers.
- [x] 5.5 Reject unsupported widths, indexed overlay forms and targets without
  a registered static-overlay operation.
- [x] 5.6 Test two nominal views over one base, nested union fields, no emitted
  declaration bytes and stable downstream diagnostics.
- [x] 5.7 Test differently sized sparse views over one base, including
  deliberately omitted offsets and fields that overlap only across overlays.
- [x] 5.8 Test aligned overlay base validation and source-correlated failure
  when a resolvable fixed address violates the required alignment.

## 6. Equivalence, Portability and Documentation

- [x] 6.1 Add a focused source fixture covering enums, explicit gaps, unions,
  packed-default compatibility, aligned layouts and overlays plus a handwritten
  customasm reference.
- [x] 6.2 Compare all focused instruction and data bytes exactly and compare
  generated customasm and source maps across repeated builds and capacities.
- [x] 6.3 Run strict C89 and UBSan core/module tests and compile/assemble the
  expanded portable implementation with cc65/ca65.
- [x] 6.4 Run full Celeste frontend/direct 65,536-byte equivalence, Celeste
  functional tests, layout-aware tests, extended ISA tests and repository
  tests.
- [x] 6.5 Update the language and game-corpus documentation with canonical
  grammar, packed defaults, deterministic alignment, non-runtime semantics,
  properties, diagnostics, workspace cost and raw-enum-operand boundary,
  including sparse partial views over shared memory.
- [x] 6.6 Strictly validate the OpenSpec change and audit that no owned game,
  ISA, RTL, memory-map or simulator source changed.
