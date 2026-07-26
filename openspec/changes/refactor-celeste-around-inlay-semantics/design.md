## Context

The source-port change established a complete `.inlay.asm` production corpus
and an exact customasm oracle. It intentionally preserved the existing program
shape. Final measurements show the remaining Phase-A boundary: 66 typed object
operands, 42 typed MMIO operations, 127 legacy `ldy #O_*` setups and 157 raw
object-indirect accesses. Thirteen routines are structured procedures while
the remaining helpers and about 180 constants retain their target-facing form.

The portable frontend expands semantic modules into a 16-bit source buffer.
The final compacted production input uses 54,903 of 65,534 bytes. Before this
change its generated-looking modules discarded comments while preserving blank
lines; restoring the commentary without comment-aware expansion would have
overflowed the console-compatible model.

This design is the byte-preserving Phase A. It intentionally retains
target-facing compatibility names and the existing instruction/control-flow
shape whenever replacing them would change the assembled image. Its residual
inventory is input to a separate customasm-only Phase B, not unfinished work
hidden inside this change.

## Goals / Non-Goals

**Goals:**

- Make checked-in Celeste source readable again.
- Model the actual overlapping object variants.
- Use nominal types for object identity and lifecycle state.
- Give object lifecycle entry points explicit receiver contracts and
  namespaces.
- Replace eligible raw hardware-register constants with typed overlays.
- Keep the emitted 64 KiB image byte-for-byte unchanged.
- Quantify the remaining language gaps honestly.
- Preserve a reproducible pre-redesign ROM and structural baseline.

**Non-Goals:**

- Rewrite every routine as a procedure in one pass.
- Rewrite raw target assembly text to substitute arbitrary layout properties.
- Hide 6502 register use, calling convention or indirect dispatch.
- Change object storage, table representation, memory addresses or game logic.
- Add general register allocation or native instruction encoding.
- Remove the generated `O_*` and `T_*` compatibility bridge.
- Introduce general namespaces or module visibility rules.
- Select additional custom-CPU word, pointer, move or pseudo operations.
- Reorganize the main loop, object subsystem, player subsystem or math library
  when doing so changes instruction bytes.

## Decisions

### Compact comments in the module expander

Checked-in source retains comments and normal spacing. During module expansion,
Inlay removes semicolon comments outside quoted strings and trims their
trailing whitespace while retaining one newline and source origin per input
line. The compiler already treats comments as non-semantic; doing this before
the bounded buffer preserves source maps and the 16-bit model.

Comment compaction belongs in the architecture-neutral module layer rather than
the Celeste build. A game-specific preparer would recreate the mistake this
change is correcting.

### Model common storage plus a payload union

The 64-byte record becomes:

```text
ObjectCore       bytes 0..17
ObjectPayload    bytes 18..63
```

`ObjectPayload` contains explicit player, spawn, smoke and title views plus a
46-byte raw member. Variant structures use explicit offsets and reserved gaps
where a type does not own intervening bytes. Static assertions pin every
existing offset and total size.

The pool and `pObj`/`pOth` remain typed as `CelesteObject`; typed paths name the
relevant union member. This changes no runtime tag checking or representation.

### Introduce nominal identity without pretending flags are enums

`ObjectKind` and spawn lifecycle state become fixed-width enums. Bit sets such
as object flags, buttons and player edge-state remain bytes until Inlay has a
dedicated flags type; calling them enums would misrepresent valid combinations.
Compatibility constants may derive from enum-generated values where raw
assembly cannot yet spell a qualified enum member.

### Convert the lifecycle surface, not every helper

The twelve object dispatch targets become:

```text
Player.init/update/draw
Spawn.init/update/draw
Smoke.init/update/draw
Title.init/update/draw
```

Each is a `console6502` procedure with `self : ptr CelesteObject in pObj`.
Dispatch tables retain the same low/high-byte representation. Internal branch
labels and arithmetic helpers remain raw target assembly.

Qualified procedure names are frontend names. The customasm host maps their
dots to underscores (`Player.update` to `Player_update`) because dots do not
form target-global labels in customasm. This deterministic mapping also makes
each emitted procedure a new parent scope for its existing `.local` labels.
Raw low/high dispatch tables name those target symbols explicitly; a future
semantic procedure-address expression can remove that backend-facing detail.

### Type hardware blocks at their real addresses

Explicit-offset structures describe the video register window at `$4000` and
the PSG control window at `$4100`; fixed overlays bind them to those bases.
Eligible direct byte `lda`/`sta` operations use overlay field paths. Indexed
register-bank operations and target directives remain explicit.

### Preserve raw indexed accesses and measure them

The remaining `ldy #O_*` plus `(pObj),y` patterns often feed `adc`, `ora`,
read-modify-write sequences or two-byte helpers. Existing Inlay typed operands
do not describe those exact register/clobber consequences. This change records
their count and keeps the compatibility offsets rather than inventing a
compiler-like lowering.

## Risks / Trade-offs

- [Comment stripping mistakes a semicolon inside a string for a comment] →
  Track quoted strings and escapes, with focused module tests.
- [Union paths make source longer] → Early comment compaction creates bounded
  headroom and conformance measures workspace use.
- [Namespaced symbols alter addresses] → Symbol spelling changes only;
  full-ROM equivalence verifies all emitted bytes.
- [Procedure wrappers accidentally emit frame code] → Use frame-elided
  parameter-only procedures and compare their exact target output.
- [MMIO conversion changes volatile behavior] → Overlay operations lower to
  one direct byte access and have focused assembly references.

## Migration Plan

1. Add and test comment-aware module compaction.
2. Restore original comments and formatting in the five generated-looking
   Celeste modules.
3. Introduce enums, object core, payload views and union with offset assertions.
4. Rewrite typed paths to the honest variant views.
5. Convert lifecycle dispatch targets to namespaced receiver procedures.
6. Add hardware layouts/overlays and migrate eligible direct accesses.
7. Add semantic metrics and run complete equivalence and functional suites.

Each stage must retain the golden ROM digest. Rollback can restore the prior
layout/module source because the test-only oracle remains untouched.

After this change, Phase B starts from this verified result and replaces byte
equality with behavioral, visual, audio and performance gates. The direct
customasm corpus remains historical evidence but is not the required output of
that later redesign.

## Open Questions

The syntax and lowering for a future typed offset materialisation operation is
deliberately deferred. Celeste's residual indexed-access inventory will inform
that design after this refactor.
