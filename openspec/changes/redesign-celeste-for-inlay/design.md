## Context

Phase A made Celeste readable and semantically described while preserving the
exact 65,536-byte image. That constraint also exposed what it could not fix:
the production program still contains 127 `ldy #O_*` setups, 157 raw object
indirect accesses, global generated constants, a compatibility-symbol tail in
`layout.inlay.asm`, only thirteen declared procedures, and module boundaries
inherited from a mechanical transliteration.

The target is not a stock 6502. It already has custom pointer-displacement,
word, move, carry-normalizing arithmetic and pseudo operations, all described
to customasm. Keeping ca65-compatible game output would prevent the redesign
from using the machine it is meant to exercise. This does not change the
separate requirement that the portable Inlay frontend compile under cc65 for a
future in-console frontend.

## Goals / Non-Goals

**Goals:**

- Make Celeste idiomatic Inlay rather than a byte-preserving transliteration.
- Design general namespaces before using them as cosmetic punctuation.
- Remove source references to generated `__la_*`, `O_*` and `T_*` names.
- Use the custom CPU and existing pseudo operations wherever their contracts
  match the program.
- Give RAM, MMIO, object storage and fixed-point values nominal typed views.
- Organize startup, game state, object management and each object kind around
  explicit responsibilities and procedure contracts.
- Preserve observable game behavior while reducing manual pointer plumbing and
  executable footprint.
- Keep all frontend algorithms bounded, allocation-free and portable to C89
  and cc65.

**Non-Goals:**

- Preserve instruction addresses, symbol spellings or the Phase-A ROM digest.
- Make the redesigned game output assemblable by ca65.
- Hide physical registers, clobbers, indirect dispatch or memory ownership.
- Add automatic register allocation, optimizer passes or implicit heap state.
- Add gameplay content that is absent from the current port merely as part of
  the structural rewrite.
- Add new hardware opcodes; the redesign consumes instructions and
  pseudo-operations already supported by the selected customasm target.

## Decisions

### Separate frontend portability from game-output portability

The Inlay core, module expander and tests remain strict portable C and retain
their cc65 smoke build. The generated Celeste assembly is validated only with
the pinned customasm toolchain because it intentionally contains custom CPU
encodings. The ca65 reference continues to test portable frontend subsets, not
the production game.

Alternative: constrain production output to the intersection of ca65 and
customasm. Rejected because that would preserve exactly the accumulator,
carry and word-operation plumbing this phase exists to remove.

### Add lexical namespaces with explicit exports

Namespace syntax follows existing aggregate syntax:

```asm
namespace Fixed
    export approach

    proc approach using console6502
        value : ptr Fixed8_8 in w0
        target : ptr Fixed8_8 in w1
        amount : ptr Fixed8_8 in w2
    begin
        ...
    end
end
```

A namespace may contain constants, enums, structures, unions, overlays,
locations, pools, nested namespaces and procedures. Names resolve from the
innermost lexical namespace outward, then globally. Qualified references use
dots. There is no wildcard `using`/import mechanism in this phase.

Declarations are private to their source module by default. `export name`
exposes one member under its fully qualified name; `export namespace Child`
exposes a nested namespace without making its unexported children public.
References within the same source module may name private members. Cross-module
references must use exported qualified names.

This default keeps generated tables and helper constants private while making
the public surface reviewable. It is stricter than traditional assembler
global labels, but raw target labels remain available as an explicit escape
hatch.

The backend uses length-prefixed components for collision-free symbols rather
than replacing dots with underscores. Source maps and diagnostics always use
the source-qualified name. Target-local labels remain scoped under the emitted
procedure symbol.

### Make qualified compile-time values usable without compatibility aliases

Qualified enum members, constants, layout properties and procedure addresses
must be valid in semantic operands and data declarations. Source can therefore
express:

```asm
mov spawn_type, #ObjectKind.smoke
mov y, offset CelesteObject.core.kind
mov count, countof CelesteObject.payload.hair.hair
data u8 low(Player.init), low(Spawn.init)
data u8 high(Player.init), high(Spawn.init)
```

The frontend resolves these values and asks the backend to emit target-valid
forms. Game source never names generated `__la_*` symbols or relies on their
mangling convention.

`offset`, `sizeof`, `alignof`, `countof` and `strideof` are prefix compile-time
query operators. Their prefix spelling makes the selected property explicit
without repeating a long path before a postfix property. A query operand is
self-identifying and therefore does not use the target immediate marker `#`.
`mov y, offset CelesteObject.core.kind` performs no memory access and publishes
the target clobber contract. It is the escape hatch for residual instructions
whose following operation cannot yet consume a typed field operand directly;
ordinary code should use the typed field operation itself.

### Extend typed operations at the semantic boundary

The first implementation covers operations evidenced by Celeste:

- byte load/store through a typed pointer or fixed overlay;
- byte read-modify-write for increment, decrement and mask/update sequences;
- word load/store between a declared physical word location and a typed
  `u16`, `i16` or fixed-point field;
- word add, subtract and compare using declared physical word locations;
- field-offset materialisation;
- indexed byte access through a fixed-overlay array;
- qualified constant and procedure-address data emission.

Each operation exposes access width, signedness, volatility, base, path,
physical operands, scratch needs and clobbers. A backend may select one custom
instruction or a deterministic sequence. It must reject an operation when it
cannot honor those properties.

This is not a general expression compiler. Compound arithmetic remains a
sequence of explicit assembly operations.

### Treat customasm instruction contracts as the optimization authority

The redesign first inventories mechanically expandable instruction sequences
and maps each to an existing custom or pseudo operation. Source uses the
specialized spelling directly when the operation is target-specific, and a
typed Inlay operation when layout resolution or validation adds value.

In particular:

- immediate and table-copy pairs use `mov`;
- carry-normalized scalar arithmetic uses `add`/`sub`;
- eligible tests use the established branch pseudo-operations;
- zero-page word values use `ldab`, `stab`, `addw`, `subw` and `cmpw`;
- object-field byte accesses use pointer displacement;
- object-field word transfers use typed deterministic sequences built from
  pointer displacement and physical word locations.

No optimization pass silently recognizes arbitrary raw instruction sequences.
Adoption is visible in source and measured by conformance.

### Keep layout declarations free of backend compatibility plumbing

`layout.inlay.asm` ends after nominal declarations, locations, pools and static
assertions. ISA rule includes belong to the selected target prelude. Enum and
field values are consumed through qualified language expressions. The
compatibility block currently beginning at line 189 is deleted in its entirety.

### Replace the flat memory map with typed regions

The hardware map is divided into explicit views:

- video control, palette, clipping and sprite-staging registers;
- PSG upload, status, channel and music registers;
- overlay framebuffer and tile-map storage;
- zero-page scratch/word/pointer locations;
- persistent game state;
- procedure-local or subsystem-owned state.

Fixed overlays may share an address when they intentionally present different
views. Indexed register banks use typed overlay arrays. Raw constants remain
only for architectural bank/vector directives or target constructs that cannot
be represented as storage.

### Give each gameplay subsystem a narrow namespace

The intended source architecture is:

- `Platform`: reset entry, target initialization, frame/input services and
  vectors;
- `Game`: title/play state, clock, freeze/restart sequencing and top-level
  tick/draw orchestration;
- `Fixed`: fixed-point primitives and approach/sign helpers;
- `Objects`: pool traversal, allocation, destruction, dispatch and movement;
- `Player`, `Spawn`, `Smoke`, `Title`: lifecycle procedures and private
  helpers/constants;
- `Collision`, `Room`, `Draw`, `Fx`, `Audio`, `Gfx`: scoped subsystem APIs and
  private data.

This is an ownership model, not a runtime object system. Procedures still name
physical parameters and storage explicitly.

`main.inlay.asm` becomes a small composition root: target/bank selection,
module imports, reset/vector binding and entry into `Game.run`. It no longer
owns unrelated upload, title, input and update routines.

### Redesign objects before player code

`Objects` provides typed pool address, iteration, allocation, destruction,
movement and lifecycle dispatch. Dispatch metadata is declared semantically
from qualified procedure addresses rather than parallel tables containing
backend symbol spellings.

The player rewrite follows only after this API is stable. `Player.update` is
split into named physical procedures for input sampling, environment state,
horizontal motion, jump/dash transitions, vertical motion and animation where
the split does not force hidden value preservation. Constants become private
`Player.*` members and temporary state becomes declared frame or
subsystem-owned storage.

### Replace byte equality with layered behavioral gates

Before rewriting, the implementation records the Phase-A image, symbols,
instruction metrics, key CPU-state milestones, framebuffer hashes and PSG
command traces.

Every migration stage must pass:

- Inlay core/module/conformance tests;
- strict C89/C99/C++11 and cc65 frontend portability;
- customasm production assembly;
- the complete headless Celeste functional suite;
- deterministic title, playfield and HUD framebuffer checkpoints;
- music/SFX command-trace checkpoints;
- memory-map and object-layout assertions.

The final image must fit the existing ROM and RAM maps, reduce executable
instruction count and manual pointer-offset setup from the recorded baseline,
and contain no missed source sequence that an adopted custom/pseudo operation
is specified to replace.

## Risks / Trade-offs

- [Namespace and visibility rules are too ambitious for the bounded parser] →
  Implement a single lexical stack, bounded qualified-name storage and no
  wildcard imports or aliases.
- [Length-prefixed target names disrupt raw tables or vectors] → Add semantic
  procedure-address data emission before migrating any table.
- [Typed compound operations become an optimizer] → Admit only explicit
  operation forms with documented physical operands and deterministic lowering.
- [Reorganizing player logic changes timing-sensitive behavior] → Migrate one
  responsibility at a time and compare CPU/frame/audio checkpoints after each.
- [Custom operations change flags or clobbers] → Treat the documented weakest
  instruction/pseudo contract as normative and add focused reference tests.
- [Default-private symbols complicate generated modules] → Update generators
  to emit explicit exports and test their public manifests.
- [Concurrent Nemo work touches shared files] → Restrict implementation to
  Celeste/Inlay-owned paths and follow `docs/agent-coordination.md` for shared
  metrics or Makefile changes.

## Migration Plan

1. Record the Phase-A behavioral, visual, audio and resource baseline.
2. Implement namespaces, visibility and collision-free target symbols with
   focused frontend fixtures.
3. Implement qualified values/data emission, typed offset materialisation,
   word/RMW operations and indexed overlays.
4. Move ISA rule inclusion into the target prelude and delete the compatibility
   tail from `layout.inlay.asm`.
5. Redesign memory/state overlays and namespace generated `Gfx`/`Fx` assets.
6. Establish `Fixed`, `Platform` and `Game`; reduce `main.inlay.asm` to the
   composition root.
7. Redesign `Objects` and its typed lifecycle dispatch.
8. Restructure player and the remaining object-kind modules.
9. Namespace collision, room, draw and audio subsystems and remove residual
   globally scoped implementation names.
10. Enforce final behavior/resource/custom-op gates and document measurements.

Each stage remains independently buildable. Rollback restores the last passing
module migration; the immutable Phase-A image and direct-customasm oracle
remain available for diagnosis.

## Open Questions

- Whether frame locals are preferable to fixed subsystem scratch for each
  player sub-procedure must be decided from emitted size and clobber evidence,
  not stylistic preference.
- A later native Inlay encoder may consume the same backend operations, but
  native encoding itself is outside this change.
