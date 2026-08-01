## Why

Celeste's `memmap.inlay.asm` is still a 238-line raw customasm compatibility
surface: it duplicates typed layouts as global numeric aliases and mixes MMIO,
game state, scratch registers, subsystem constants and fixed storage in one
unscoped file. It also remains an opaque `#include` because the frontend
currently flattens semantic modules into 65,318 of its 65,534-byte host source
capacity, so cleaning the file cosmetically would preserve both root problems.

## What Changes

- Generalize physical `location` declarations to scalar, pointer and
  `codeptr` types with explicit fixed addresses and qualified names.
- Permit qualified physical locations in procedure placement, semantic
  operands and invocation while preserving their declared storage widths.
- Add semantic address materialization for fixed overlays and their fields.
- Extend fixed-overlay lowering to the move, compare, branch,
  read-modify-write, indexed and page-view forms evidenced by Celeste.
- Replace whole-program source flattening with bounded module-at-a-time
  translation that retains persistent semantic state and exact source
  correlation.
- Make every handwritten Celeste module a semantic `include`; reserve raw
  `#include` for target ISA rules and genuinely opaque generated data.
- Move game-state access to the `GameState` overlay, MMIO access to the video
  and PSG overlays, and effect/framebuffer storage to typed indexed views.
- Move scratch locations and constants into their owning namespaces, including
  `Game`, `Objects`, `Collision`, `Draw`, `Fx`, `Fixed`, `Room`, `Audio` and
  `Platform`.
- Replace duplicated capacities and offsets with `countof`, `sizeof`,
  `strideof`, typed pool properties and overlay address materialization.
- Delete `src/celeste/memmap.inlay.asm` once no production source references
  its legacy global aliases.
- Preserve the final Celeste ROM bytes and all functional, visual, audio,
  resource and portability regressions throughout this representation-only
  migration.

## Capabilities

### New Capabilities

- `celeste-semantic-memory-map`: Defines the ownership, typed-memory usage,
  raw-alias elimination and deletion criteria for Celeste's compatibility
  memory-map module.

### Modified Capabilities

- `layout-aware-assembly`: Adds typed fixed-address physical locations,
  qualified placement, overlay address materialization and the required
  fixed-overlay operation families.
- `layout-aware-modules`: Replaces bounded whole-program flattening with
  bounded module-at-a-time semantic translation and persistent cross-module
  state.
- `celeste-layout-aware-build`: Requires all handwritten Celeste modules to be
  semantically translated and preserves exact ROM equivalence during the
  memory-map migration.

## Impact

The portable Inlay core, module adapter, workspace limits, semantic events,
console6502 lowering, host source maps and conformance fixtures change.
`layout.inlay.asm` gains physical storage views or supporting layouts, while
the owning Celeste subsystem modules gain scoped locations, constants and
typed operands. `main.inlay.asm` stops raw-including the compatibility memory
map, and `src/celeste/memmap.inlay.asm` is removed at completion.

The change depends on the namespace/export, target-default convention and
`codeptr` work in `redesign-celeste-for-inlay`. It does not change hardware,
the ISA, allocation policy, register allocation, runtime ownership or the
checked-in Nemo sources.
