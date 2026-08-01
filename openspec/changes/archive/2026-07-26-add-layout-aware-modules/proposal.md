## Why

The frontend currently sees only one physical source buffer, so declarations
and typed operands in included game modules remain opaque raw customasm.
Bounded, platform-provided module resolution is required both for a genuine
multi-file Celeste migration and for the eventual in-console editor.

## What Changes

- Add a portable module-expansion layer using caller-provided immutable source
  views, resolver callbacks, explicit module/line capacities and source IDs.
- Add an owned `include "logical-name"` directive distinct from raw customasm
  `#include`.
- Preserve original module source IDs and line numbers through semantic events,
  diagnostics and host JSON mappings.
- Add a host filesystem resolver outside the core while permitting an
  in-console resolver over editor buffers.
- Detect missing modules, duplicate/cyclic inclusion and capacity exhaustion
  deterministically.
- Generate layout-owned Celeste module copies beneath `build/`, converting
  byte-equivalent direct `pObj`/`pOth` field operations to typed paths without
  editing corpus files.
- Retain the focused and complete-ROM byte-equivalence gates.

## Capabilities

### New Capabilities

- `layout-aware-modules`: Bounded source-view resolution, expansion, source
  correlation and host module adapters.

### Modified Capabilities

- `layout-aware-assembly`: Adds portable multi-source compilation and
  module-correlated semantic output to the existing frontend contract.
- `celeste-layout-aware-build`: Replaces eligible compatibility-only field
  accesses with typed operands in generated layout-owned modules while
  preserving the complete ROM.

## Impact

The public frontend API, portable C modules, host shell, source-map schema,
Celeste build preparation, tests, Makefile and layout-aware documentation are
affected. Existing `src/celeste/`, ISA, RTL and simulator files remain
unchanged.
