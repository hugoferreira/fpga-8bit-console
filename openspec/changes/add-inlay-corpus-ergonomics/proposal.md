## Why

The completed Celeste port is a measured corpus of what Inlay's current slice
cannot express. Production source contains zero `invoke` statements, 60
split-immediate pairs feeding word locations, 57 `Fixed.*` call rituals, 21
frozen `inlay-exception` sites and 129 residual raw `(pObj|pOth),y` accesses.
Each is a place where the raw escape hatch was cheaper than the semantic form,
or where no semantic form exists. This change adds the language features those
counts identify, so the frontend absorbs the game's actual idioms instead of
annotating them as exceptions.

## What Changes

- Compile-time expressions gain bitwise operators `~`, `&`, `^`, `|`, `<<`,
  `>>`, making complemented and composed mask constants expressible in typed
  operands (`and [p + T.flags], #~bit_jump`).
- Two typed observation forms: the branch op `decz [p + T.field], label`
  (branch if zero, else decrement and fall through) and `tstw` over a word
  field or word location (Z from low|high).
- Word-immediate and word-move forms: `movw wordloc, #imm16`,
  `movw wordloc, wordloc` and `stw [p + T.field], #imm16`.
- `inline proc`: a procedure expanded at each call site with freshened local
  labels, checked clobber contract, no frame, and no `ret` — the zero-cost
  library primitive.
- `invoke` extensions: an explicit marshalling-order contract with
  identity-binding elision and overlap-only scratch, 16-bit immediates
  binding to `u16` members, typed object-field sources with optional
  constant displacement, and `invoke tail` emitting `jmp`.
- `method_table`: enum-value-keyed dispatch tables over a declared domain,
  generated from qualified procedure identities with total coverage
  validation and a published index bias, replacing hand-maintained parallel
  lo/hi tables.
- `pool` declarations may emit their own low/high address tables under
  qualified names, retiring the last documented global-label exception.
- Namespace-level defaults: `namespace X using console6502` and `export` as a
  declaration qualifier.
- The Celeste source migrates to each feature as it lands; conformance
  exception counts re-freeze downward.

## Capabilities

### New Capabilities

- `inlay-inline-procs`: inline procedure declaration, expansion semantics,
  label freshening, contract checking and metrics registration.
- `inlay-method-tables`: enum-value-keyed generated dispatch tables with
  domain, coverage and absence rules.

### Modified Capabilities

- `layout-aware-assembly`: compile-time expression grammar gains bitwise
  operators; new typed operations `decz`/`tstw` and word-immediate forms;
  `invoke` ordering contract, elision, source kinds and tail; pool table
  emission; namespace-level `using` default and `export` qualifier;
  pinned `inc`/`dec` contract.
- `celeste-layout-aware-build`: production source adopts the new forms;
  the conformance inventory and exception counts move per the design's
  per-stage table.

## Impact

- `tools/inlay/inlay_core.c`, `tools/inlay/inlay_modules.c`,
  `tools/inlay/inlay_host.c`: parser, semantics, events, lowering.
- `tools/inlay/test_inlay.c`, `tests/inlay/`: unit and lowering references.
- `tools/inlay/celeste_redesign_metrics.py`, `tools/inlay/test_conformance.py`:
  new operations registered; frozen counts updated per stage.
- `src/celeste/*.inlay.asm`: migration of eligible sites.
- `docs/inlay.md`: language documentation.
- Acceptance per stage: `make test-inlay`, `make test-celeste`, forced-build
  artifact determinism, framebuffer/PSG/boot checkpoints.
