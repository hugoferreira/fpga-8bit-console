## 1. Public Module API

- [x] 1.1 Add immutable source views, resolver callbacks, origin callbacks and
  stable module diagnostics to the public portable API.
- [x] 1.2 Add explicit capacities and caller-workspace sizing for modules,
  flattened bytes, source lines and include depth.
- [x] 1.3 Preserve source-id behavior for existing single-stream callers.

## 2. Portable Expansion

- [x] 2.1 Parse only the owned `include "logical-name"` directive while
  preserving raw `#include` lines.
- [x] 2.2 Expand modules depth-first with an explicit bounded stack.
- [x] 2.3 Record an original source id and line number for every flattened line.
- [x] 2.4 Reject missing modules, cycles and duplicate completed modules with
  stable source-correlated diagnostics.
- [x] 2.5 Exercise module, byte, line and depth capacities exactly and one past
  their limits under strict C89 and sanitizers.
- [x] 2.6 Compile and assemble the expanded portable core with cc65/ca65.

## 3. Host Adapter and Maps

- [x] 3.1 Add a host filesystem resolver outside the portable core with
  deterministic relative logical names and source ids.
- [x] 3.2 Add deterministic source-map format 2 with a logical sources table and
  per-mapping source ids.
- [x] 3.3 Format frontend and mapped customasm diagnostics against the correct
  included logical source.
- [x] 3.4 Add host tests for nested includes, missing files, cycles, duplicates,
  path normalization and repeatable output.

## 4. Celeste Generated Migration

- [x] 4.1 Generate layout-owned copies of Celeste modules beneath
  `build/layout_aware/modules/` without changing `src/celeste/`.
- [x] 4.2 Convert every eligible direct `pObj` and `pOth` `lda`/`sta` operation
  through a closed `O_*` to field-path mapping.
- [x] 4.3 Map `O_*+1` fixed-point accesses to nested integer components and
  preserve non-equivalent indexed sequences unchanged.
- [x] 4.4 Declare both typed pointer locations and include generated modules
  through frontend-owned module directives.
- [x] 4.5 Require the exact expected converted-operation count and fail on any
  unrecognised eligible direct form.

## 5. Equivalence and Integration

- [x] 5.1 Assemble focused typed references and compare instruction bytes.
- [x] 5.2 Assemble direct and module-aware Celeste entries and compare all
  65,536 ROM bytes.
- [x] 5.3 Run `make GAME=celeste hex`, `make test-celeste`,
  `make test-layout-asm`, `make test-ext` and the existing test aggregate.
- [x] 5.4 Measure and document module/source-line workspace pressure and typed
  operation counts.
- [x] 5.5 Validate the OpenSpec change and audit that no owned Celeste, ISA, RTL,
  memory-map or simulator source changed.
