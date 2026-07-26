## Why

The frontend can describe only consecutively packed structures, which leaves
common game and hardware layouts dependent on unrelated constants, manual
padding, or raw assembler aliases. Enums, explicit offsets, unions and
non-owning overlays complete the compile-time layout vocabulary without
introducing allocation, lifetime, dispatch or other runtime semantics.

## What Changes

- Add fixed-width nominal enums with explicit integer values and qualified
  compile-time constants.
- Allow packed structure fields to declare explicit offsets while retaining
  declaration-order placement for unqualified fields. Explicit gaps allow a
  structure to describe only the fields relevant to one sparse view.
- Make packed layout the implicit default for structures and unions while
  retaining `packed` as an optional explicit assertion.
- Add deterministic `aligned(N)` structure and union layout, where `N` is a
  power-of-two count of target addressable storage units.
- Add nominal unions whose members all begin at offset zero and whose size is
  the maximum member extent.
- Add named overlays that assign a nominal type to an existing fixed target
  storage symbol without allocating bytes or converting data. Multiple sparse
  structure views may deliberately cover different, overlapping subsets of
  the same backing region.
- Extend layout properties, typed field operands, capacity accounting,
  diagnostics, deterministic host output and assembly-equivalence fixtures for
  all four constructs.
- Keep overlapping structure fields illegal; intentional overlap belongs in a
  union or in distinct overlays. Unnamed gaps omit bytes from that view; they
  do not allocate, reserve, initialise or hide storage from another overlay.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `layout-aware-assembly`: Extend the existing nominal layout and typed-location
  model with enums, explicit field offsets, unions and non-owning overlays.

## Impact

The bounded portable API and workspace gain enum, enum-member, union and
overlay records, target alignment limits, stable capacity diagnostics and
semantic events. The parser, layout resolver, expression evaluator, typed
operand resolver, console6502 host emitter, source maps, focused fixtures and
language documentation are extended. Existing explicitly packed structures
retain their layouts and generated Celeste bytes, and no game, ISA, RTL,
simulator or memory-map source requires migration.
