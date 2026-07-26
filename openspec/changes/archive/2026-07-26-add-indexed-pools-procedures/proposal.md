## Why

The frontend can describe byte layouts and direct fields, but real game code
still falls back to handwritten displacement arithmetic for arrays and pools,
and procedure signatures cannot yet describe the physical parameter and frame
contracts discussed in the language design. Implementing these together makes
the layout model useful across object lookup, indexed members and routine
boundaries without introducing hidden register allocation.

## What Changes

- Add typed indexed field operands whose semantic address includes a declared
  array stride and a target-specific physical index location.
- Add fixed pool declarations, compile-time pool properties and explicit typed
  pool-address materialisation.
- Add procedures with physical parameter aliases, default `frame` mode,
  explicit `naked` mode, symbolic memory locals and backend-owned
  prologue/epilogue lowering.
- Add deterministic `console6502` lowerings for the supported indexed, pool and
  procedure subset while diagnosing unavailable scratch, unsupported frames
  and invalid physical locations.
- Migrate Celeste object-pool lookup and its procedure boundary through
  build-only layout modules, and exercise representative Celeste-shaped field
  indexing in a focused equivalence fixture.
- Require focused assembly equivalence and complete 65,536-byte Celeste ROM
  equivalence throughout the migration.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `layout-aware-assembly`: Add indexed operands, pools, typed address
  materialisation, procedure signatures, physical parameters and
  `frame`/`naked` semantics.
- `celeste-layout-aware-build`: Exercise the new constructs through generated
  modules while retaining exact direct-build assembly equivalence.

## Impact

The portable API, parser, layout tables, semantic event stream, target
metadata, host customasm emitter, conformance fixtures and Celeste build-only
migration will change. `src/celeste/`, ISA definitions, RTL, the memory map and
the simulator remain outside the edit scope. No heap, garbage collector,
virtual register allocator or native opcode encoder is introduced.
