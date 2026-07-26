## Inlay naming audit

Recorded after implementation on 2026-07-26.

No live source, test or documentation path remains under:

- `tools/laasm/`
- `src/layout/`
- `tests/layout_aware/`
- `build/layout_aware/`

The active implementation, fixtures and user documentation use
`tools/inlay/`, `src/inlay/`, `tests/inlay/`, `build/inlay/`, `inlay` and
`.inlay.asm`.

Remaining old-name occurrences fall into deliberate categories:

- the generated `build/laasm/laasm` compatibility path, its Makefile variable,
  launcher source, black-box tests and the compatibility section in
  `docs/inlay.md`;
- `.la.asm` compatibility fixtures that prove legacy entry and module names
  retain identical semantics;
- this change's proposal, design, delta requirements, baseline and task history,
  which must name the contracts being replaced;
- archived OpenSpec changes, which are immutable historical records;
- the current main OpenSpec capabilities and their stable
  `layout-aware-*` capability identifiers, which remain the pre-change
  source-of-truth until this validated change is archived and its deltas are
  applied;
- the deliberately preserved `la_` portable C API and `__la_` generated
  private-symbol namespace.

The audit found no accidental old product name in the canonical host,
repository-owned Inlay sources, active tests, generated Inlay tree or
user-facing documentation outside the documented compatibility boundary.
