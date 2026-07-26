## Why

Celeste currently enters Inlay through a wrapper while most production files
remain `.asm` customasm sources, and four modules exist in both forms. That is
a compatibility build, not a comprehensible source port: `src/celeste/` does
not tell a developer which files are authoritative and the Inlay entry still
reaches back into the legacy corpus.

## What Changes

- Replace the mixed `src/celeste/` tree with one flat, complete production
  corpus whose files all use the `.inlay.asm` suffix.
- Express every handwritten code dependency with Inlay `include`; permit an
  explicit bounded-core exception for opaque memory and generated data modules,
  all still named `.inlay.asm`.
- Include handwritten code, memory declarations, graphics, rooms, and audio in
  that naming and dependency boundary.
- Update Celeste asset generators to emit `.inlay.asm` outputs.
- Move the former direct customasm corpus beneath
  `tests/inlay/reference/celeste-customasm/` as a test-only equivalence oracle.
- Continue to require exact equality for all 65,536 ROM bytes and the
  established golden SHA-256 digest.
- Keep architecture-specific 6502 instructions in Inlay source: this is an
  assembler-source port, not a portable pseudo-ISA rewrite.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `celeste-layout-aware-build`: Require a complete, exclusively Inlay-named
  production corpus with no legacy Celeste source dependencies, while retaining
  exact full-ROM assembly equivalence against a test-only oracle.

## Impact

The change replaces the contents and naming of `src/celeste/`, relocates the
legacy oracle under `tests/inlay/reference/`, updates the Celeste build,
metrics, tests, asset generator documentation/output names, and strengthens
Inlay conformance. Customasm remains the downstream instruction encoder.
