## Context

Celeste already declares its stable memory shapes in `layout.inlay.asm`:
`VideoRegisters`, `PsgRegisters`, `TileMap`, `OverlayFramebuffer`,
`RoomTileBuffer`, `OverlayRowPointers`, `ZeroPageWorking`, `GameState` and the
object pool. Nevertheless, `memmap.inlay.asm` repeats the corresponding
addresses as 130-plus global customasm aliases. Those aliases remain necessary
where the frontend only accepts a target symbol: scalar zero-page locations,
non-accumulator MMIO operations, pointer initialization, fixed-overlay RMW,
page-strided framebuffer copies and structure-of-arrays effects access.

The file is also outside the semantic module graph. The host profile currently
reports 65,318 expanded bytes against a 65,534-byte limit even though the
physical handwritten source is about 165 KiB. `memmap.inlay.asm`, rooms and
audio are consequently passed to customasm through raw `#include`. Increasing
the flattened buffer would postpone failure and would not fit the future
in-console frontend model.

This change follows `redesign-celeste-for-inlay`. It assumes declaration-site
exports, target-default procedure conventions, namespaces and `codeptr` are
available before production migration begins.

## Goals / Non-Goals

**Goals:**

- Delete the raw Celeste compatibility memory map.
- Make memory ownership visible through types, overlays, scoped constants and
  typed physical locations.
- Preserve exact addresses, overlaps, storage widths and ROM bytes.
- Remove whole-program flattened-source capacity as a blocker.
- Keep the core allocation-free, bounded, C89-compatible and suitable for an
  in-console implementation.
- Retain raw target assembly as an explicit, measured escape hatch.

**Non-Goals:**

- Allocate or initialize storage when declaring a location or overlay.
- Add register allocation, liveness inference or automatic spilling.
- Turn arbitrary target instructions into a portable expression language.
- Change the console memory map, hardware registers, object representation,
  gameplay or timing.
- Convert generated room/audio payloads into semantic declarations merely to
  eliminate every raw `#include`.
- Modify `src/nemo/` as part of the Celeste migration.

## Decisions

### Replay the module graph instead of flattening it

The module layer first discovers a bounded include graph in deterministic
depth-first order. It stores module identity, logical name, source id,
dependency edges and immutable source views, but does not copy all source text
or construct an expanded line array.

Each semantic compiler phase then replays the graph in the same order:

1. declaration discovery;
2. type/name resolution;
3. layout and constant resolution;
4. assertion and cross-reference validation;
5. semantic emission.

The current core already separates these concerns over one buffer. The new
source cursor changes the traversal unit from a flattened line to
`{source_id, original_line, bytes}` while semantic tables persist across the
passes. Forward references therefore retain whole-graph behavior.

Host adapters may retain file bytes outside the core. An in-console resolver
may expose immutable editor/cartridge buffers. A legacy single-stream caller
is represented as a one-module graph and may use one bounded replay buffer.

Alternative: enlarge `la_u16` source offsets and the host flattened buffer.
Rejected because total-source memory would still scale with cartridge size and
would create a different architecture for the console port.

### Generalize locations as non-owning typed physical views

The accepted family becomes:

```asm
location t0   : u8                at $00
location w0   : u16               at $08
location pFn  : codeptr           at $14
location pObj : ptr CelesteObject at $10
```

`at` accepts a compile-time physical address. Omitting `at` retains the current
backend-bound location form. A declaration emits a target alias when the
backend needs one, but never reserves, clears or initializes bytes.

Locations may be nested in namespaces and procedure placement accepts a
qualified location:

```asm
self : ptr CelesteObject in Machine.object
```

Multiple location declarations may intentionally view the same address with
compatible widths. This is the scalar equivalent of overlapping overlays and
lets a subsystem name the role it owns without claiming storage allocation.
Incompatible overlapping widths are permitted only when explicitly declared;
the compiler does not infer alias safety or value preservation.

Alternative: keep all zero-page names global because they resemble registers.
Rejected because it preserves the ownership and collision problem this change
is meant to remove.

### Materialize overlay addresses semantically

`address` is extended from pools to fixed overlays:

```asm
address destination, tile_map.patterns
address row, overlay_shadow.pixels
```

The frontend resolves the overlay base plus field displacement and publishes
the destination width, address width and target relocation. It does not load
the field. A backend must lower the request deterministically or reject it.

This avoids introducing a general address-expression evaluator or spelling
target-specific low/high operators around typed paths.

### Extend only evidenced fixed-overlay operations

The operation matrix is deliberately finite. This change admits the Celeste
forms required for:

- byte loads and stores through fixed overlay fields;
- physical-register and memory-to-memory `mov` where the target already
  defines the exact pseudo-operation;
- accumulator compare and the established compare/test-and-branch
  pseudo-operations;
- byte `inc`, `dec`, `and` and `ora` read-modify-write;
- one physical index into a unit-stride overlay array;
- explicit page views used by framebuffer/shadow bulk copies.

Every event retains access width, volatility, base, displacement, index,
scratch and clobber metadata. No optimizer recognizes raw instruction
sequences. A raw operation remains when the semantic form would change flags,
atomicity, volatility, instruction count or live physical state.

### Model page-strided and structure-of-arrays memory honestly

Effects storage becomes a fixed overlay whose fields are the existing
unit-stride arrays at explicit offsets. Framebuffer and shadow storage gain an
additional page view with explicit 256-byte page fields, including the shorter
final page. These are alternative views over existing addresses, not copied
or newly allocated storage.

The byte-linear views remain for size and row calculations. The page views
exist because the target's indexed absolute operations consume page bases
directly; forcing a fabricated array-of-records layout would misdescribe the
machine access pattern.

### Put names with their semantic owners

The migration uses these ownership rules:

- video and PSG addresses are consumed through their exported overlays;
- persistent state is consumed through `GameState`;
- room geometry and tile identifiers belong to `Room`;
- input masks belong to `Platform.Input`;
- music identifiers and fade units belong to `Audio`;
- object capacities and flags belong to `Objects`;
- collision scratch belongs to `Collision`;
- draw/hair scratch and framebuffer views belong to `Draw`;
- effect arrays belong to `Fx`;
- fixed-point word locations belong to `Fixed`;
- truly shared calling-convention locations live in a small `Machine`
  namespace rather than an application memory-map file.

Constants derivable from layouts use `sizeof`, `countof` or `strideof`.
Subsystem-specific constants are declared privately unless another module
actually consumes them.

Alternative: move the current aliases unchanged beneath a `Memory` namespace.
Rejected because it improves spelling without removing duplicated facts or
mixed ownership.

### Delete the compatibility file as an acceptance condition

The end state has no `src/celeste/memmap.inlay.asm` and no raw include of it.
Conformance maintains an explicit deny-list of its legacy global aliases and
rejects handwritten raw numeric addresses for regions represented by typed
overlays, except reviewed target-bound cases.

`layout.inlay.asm` remains the home of shared nominal shapes, overlays, pools
and address assertions. Subsystem-only physical views and constants live with
their owners; this change does not rename the layout module merely to move the
same mixture elsewhere.

### Preserve bytes during staged migration

This is a representation refactor, unlike the earlier Phase-B redesign. Each
stage captures the pre-stage ROM and requires a complete 65,536-byte comparison
after migration. Focused lowering fixtures also compare exact customasm and
machine bytes. The established functional, framebuffer, PSG, resource,
portability and strict OpenSpec suites remain mandatory.

## Risks / Trade-offs

- [Repeated module passes increase input reads] → Require immutable/replayable
  source views and bound passes by the fixed semantic phase count.
- [Cross-module diagnostics drift after removing flattened lines] → Carry the
  source id and original line directly on every cursor and event; compare maps
  before and after the module rewrite.
- [Qualified physical aliases make source noisy] → Use lexical ownership so
  most references are unqualified inside their subsystem; reserve `Machine.*`
  for genuinely shared convention locations.
- [Typed pseudo-operations accidentally change flags] → Add exact lowering
  fixtures and retain raw assembly whenever the target contract is weaker than
  the existing sequence.
- [Overlapping location views imply safety that does not exist] → Specify them
  as non-owning aliases with no liveness, exclusivity or preservation claims.
- [The predecessor change is still active] → Begin implementation only after
  its namespace/export/default-convention/code-pointer work is integrated;
  keep this change in a separate directory meanwhile.
- [Other corpora depend on module behavior] → Retain single-source behavior and
  run all Inlay module/core portability tests; do not edit Nemo production
  source.

## Migration Plan

1. Freeze the current Phase-B ROM, source map, alias inventory and expanded
   source high-water.
2. Replace flattening with replayable module-graph passes without changing
   emitted assembly.
3. Add scalar/pointer/code-pointer fixed locations, qualified placement and
   overlapping-view tests.
4. Add overlay address materialization and the evidenced fixed-overlay
   operation matrix with exact target references.
5. Add effects and framebuffer page views plus all established address
   assertions.
6. Migrate MMIO and game state, then room/audio/object constants.
7. Migrate shared and subsystem scratch locations one owner at a time.
8. Migrate effects, framebuffer, row pointers and remaining fixed storage.
9. Change the root to semantic inclusion, delete `memmap.inlay.asm`, and enable
   the legacy-alias/raw-address deny-list.
10. Run exact-ROM and complete behavioral/resource/portability validation.

Rollback at any stage restores the last byte-identical module migration. The
pre-change Phase-B image remains the oracle until the file is deleted and all
gates pass.

## Open Questions

- Whether raw generated rooms and audio should later become streamed semantic
  data modules is intentionally deferred; it is not required to eliminate the
  handwritten compatibility memory map.
