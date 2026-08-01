## Context

Celeste already builds with customasm and defines its object record through a
contiguous `O_*` block in `src/celeste/memmap.asm`. The
`add-layout-aware-assembler-frontend` change adds a bounded C semantic core and
a host customasm emitter, but intentionally stops at an isolated conformance
fixture.

This adoption must prove a real full-game pipeline without rewriting the
Celeste files in place. Generated sources belong under `build/` and may adapt
the old interface at the build boundary.

## Goals / Non-Goals

**Goals:**

- Make the layout declaration the source of truth for all object offsets used
  by the complete Celeste build.
- Route the ordinary Celeste `hex` and functional-test paths through `laasm`.
- Preserve the exact 64 KiB image produced by the pre-adoption customasm path.
- Fail loudly if the old offset block or main-file include structure changes.
- Keep customasm as the single instruction encoder.

**Non-Goals:**

- Rewrite the Celeste modules in place.
- Convert every existing `O_*` operand to typed field syntax in this change.
- Add a native encoder or duplicate opcode metadata.
- Change Celeste behavior, memory layout, ISA rules, assets or hardware.

## Decisions

### Use a generated compatibility boundary

`src/layout/celeste.la.asm` declares `Fixed8_8`, `Hitbox`, `HairNode` and
`CelesteObject`, asserts the established layout, and defines each legacy `O_*`
name as a generated layout property. The complete existing game can therefore
consume the new authoritative layout without a broad source rewrite.

The alternative was to duplicate the game modules under a new tree or edit
`src/celeste/` directly. Both create unnecessary merge risk and obscure whether
machine-code changes came from semantics or source churn.

### Remove only the superseded definitions

A small host preparation script copies `main.asm` and `memmap.asm` into
`build/layout_aware/`. It removes the four ISA includes already supplied by the
layout entry, rewrites local include paths for their generated location, and
removes exactly the contiguous `O_TYPE` through `O_SIZE` assignment block.

The script validates the expected include count and every declaration inside
the removed block. Unexpected syntax is an error rather than an invitation to
silently drop source.

### Require two levels of assembly equivalence

A focused fixture lowers representative direct and nested typed operands and
compares its instruction bytes with a handwritten customasm reference. The
full gate separately assembles `src/celeste/main.asm` and the generated
layout-aware entry, then compares all 65,536 image bytes.

This catches both local lowering errors and global effects involving banks,
symbols, includes, vectors, padding or assets.

### Select the frontend only for Celeste

An append-only conditional Makefile assignment changes `GAME_SRC` to the
generated source only when `GAME=celeste`. The existing customasm recipe,
binary/symbol/readmemh outputs and label conversion remain unchanged.

Rollback is therefore one build-selection removal; no game source needs to be
reverted.

## Risks / Trade-offs

- **Compatibility aliases leave old operand spellings in the corpus** →
  representative typed operands are proven independently, while direct corpus
  syntax migration is reserved for a coordinated follow-up.
- **The preparation script depends on known include structure** → it validates
  exact counts and fails when the source shape changes.
- **Two assemblages add test time** → the full comparison is fast enough to run
  before `test-celeste` and provides stronger evidence than source inspection.
- **Generated include paths depend on output depth** → the Makefile fixes the
  output at `build/layout_aware/`, and conformance uses directories at the same
  depth.
