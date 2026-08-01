## Context

The archived frontend accepts one byte stream and assigns one source id to all
events. Celeste's layout-aware entry can therefore define authoritative
compatibility constants, but its included game modules are parsed later by
customasm and cannot contain frontend-owned typed operands.

The module system must work in two environments: a host filesystem today and
an in-console editor buffer later. It must not add filesystem calls, allocation
or unbounded recursion to the portable semantic layer.

## Goals / Non-Goals

**Goals:**

- Resolve frontend `include "logical-name"` directives through a callback.
- Expand immutable source views with bounded caller-owned storage.
- Preserve source id and original line for every expanded line.
- Diagnose missing modules, cycles, duplicates and capacity exhaustion.
- Let the host use files while a future console uses editor buffers.
- Convert byte-equivalent Celeste pointer operations in generated modules and
  retain exact full-ROM output.

**Non-Goals:**

- Interpret or replace raw customasm `#include`.
- Add a package manager, search-path language or conditional compilation.
- Edit `src/celeste/` files.
- Convert `(zp),Y` sequences whose replacement would change instruction bytes.
- Add native instruction encoding.

## Decisions

### Expand source views before semantic parsing

A new portable module layer accepts a root `LaSourceView`, a resolver callback,
explicit limits and a caller workspace. A source view is immutable bytes plus a
stable source id and logical name. The resolver returns another view; it does
not expose paths or perform I/O in the core.

The layer emits one flattened byte stream and parallel per-line origin records.
It then presents that stream through the existing `LaInput` interface. An
optional input-origin callback lets the semantic core translate flattened line
numbers back to module source ids and lines.

This reuses the existing parser and keeps module mechanics independent of type
semantics. Parsing files directly inside every semantic pass was rejected
because it would duplicate traversal logic and make forward nominal references
across modules harder to reason about.

### Use explicit bounded stacks

Expansion uses caller-sized module records, line-origin records and an explicit
include stack. A module is rejected if it is already active (cycle) or already
completed (duplicate include). Source bytes, source lines, module count and
include depth each have distinct capacity diagnostics.

### Keep frontend and customasm include syntaxes distinct

The owned directive is:

```asm
include "physics.la.asm"
```

It is removed and replaced by the module's expanded contents. A line beginning
with `#include` remains raw customasm and reaches the downstream assembler
unchanged. This prevents the frontend from unexpectedly opening ISA rule files
or assets.

### Put filesystem behavior in the host shell

The host resolver canonicalizes paths relative to the including module,
restricts resolution to the root source tree, loads each file into host-owned
memory and assigns deterministic depth-first source ids. The JSON map gains a
versioned `sources` table and every mapping records its source id.

The console resolver can instead map logical names to editor-buffer slots with
no semantic-core changes.

### Migrate only already-equivalent Celeste operations

The build preparation step creates layout-owned module copies under
`build/layout_aware/modules/`. It converts direct extended-pointer operations
such as:

```asm
lda (pObj), #O_X
sta (pOth), #O_HBW
```

to explicit typed operands. `O_FIELD+1` forms map to the appropriate nested
fixed-point component. Indexed `(pointer),y` sequences remain raw because
changing those to the direct-displacement opcode would violate the mandatory
assembly-equivalence gate.

## Risks / Trade-offs

- **Flattening reserves source and origin storage** → both are explicit limits
  with exact/one-past tests and measured Celeste usage.
- **Host paths could leak into deterministic output** → maps contain logical
  normalized module names, never absolute paths.
- **Generated migration could rewrite an unintended operand** → conversion
  accepts a closed mapping of `O_*` names and exact `lda`/`sta` operand shapes,
  reports counts, and full-ROM comparison gates acceptance.
- **Duplicate include rejection is stricter than textual assemblers** → the
  first slice favors deterministic nominal declarations; include guards and
  repeated raw fragments remain future work.

## Migration Plan

1. Add and test the portable module expansion API.
2. Add the host filesystem resolver and source-map v2.
3. Generate Celeste module copies and convert only direct byte-equivalent
   accesses.
4. Point the layout entry at frontend module includes.
5. Require typed-operation count, complete-ROM equality and the existing
   Celeste functional suite.

Rollback restores the archived single-file compatibility entry and preparation
rules; the original Celeste source remains untouched throughout.
