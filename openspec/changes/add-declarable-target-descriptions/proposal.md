## Why

Inlay is not meant to be a portable surface; it is meant to accept
different ISAs and know what to do with them. Today the target-specific
knowledge is split incorrectly: customasm owns encodings, the core owns
the genuinely target-free machinery (layouts, paths, expressions,
modules, bounded workspace), but the bridge between them — operation
spellings, register names, clobber contracts, lowering sequences, the
frame model, invoke scratch and scheduling, dispatch-data strategies —
is hardcoded C in the portable core, gated by `LaTarget` booleans that
say *whether* an operation exists without saying *what it is*. A second
target currently means editing the core, which is exactly the coupling
the event-stream boundary was supposed to prevent.

## What Changes

- A per-target **description** becomes the single home of target
  knowledge the frontend needs: machine facts, a register set with
  roles, calling conventions, scratch naming, operation spellings with
  constraints, lowering templates, declared contracts, the frame model,
  and data-emission strategies. The core interprets descriptions; it
  stops naming any register, mnemonic, clobber, or sequence itself.
- Typed-operation parsing dispatches on target-declared spellings; a
  spelling the target does not declare falls through to raw exactly as
  unknown mnemonics do today. Collisions with real target mnemonics
  become a per-target decision made in the description.
- Lowerings become templates: substitution slots, bounded parameter
  arithmetic, declared clobber/flag contracts. Validation (width,
  range, volatility, stride) stays frontend-side as template
  constraints — customasm continues to own encodings only.
- The invoke planner and frame machinery generalize from 6502 constants
  to declared register roles and per-template clobber sets; emission
  order derives from dependency scheduling over declared defs and
  clobbers instead of the fixed Y-X-A special case.
- The semantic operation vocabulary stays **fixed and small**; the two
  places 6502 strategy leaked into it (split low/high procedure-address
  entries, low/high pool tables) become declarable **strategies**
  selected by the target with per-declaration override.
- `console6502` becomes the first description and the regression
  baseline: every phase is accepted only with a digest-identical Celeste
  build, so the refactor is byte-neutral by construction.
- The canonical-ISA-description seam cross-checks descriptions: a
  template referencing a mnemonic the ISA description does not define
  fails the build.

## Capabilities

### New Capabilities

- `inlay-target-descriptions`: the declarable target description — its
  contents, interpretation, validation, and cross-checking.

### Modified Capabilities

- `layout-aware-assembly`: typed operations, conventions, frames,
  invoke, and generated data resolve through the target description;
  the core carries no target-named knowledge. Existing language
  behavior for `console6502` is unchanged and digest-gated.

## Impact

- `tools/inlay/inlay_core.c`: parser dispatch, planner, frame and
  invoke emission become description-driven; the hardcoded mnemonics,
  register names, clobber strings, scratch naming, and sequences move
  out.
- `tools/inlay/inlay.h`: `LaTarget` grows from capability booleans to
  the full description structure (or a loader for a description file).
- `tools/inlay/inlay_host.c`: emitters become template interpretation.
- `tests/inlay/`: per-target lowering references; the conformance and
  pseudo-op verification patterns extend to declared templates.
- `src/isa/`, canonical ISA seam: description/ruleset cross-validation.
- Acceptance throughout: `make test-inlay`, `make test-celeste`,
  digest-identical forced builds of Celeste at every phase.
