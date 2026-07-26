## Why

The complete Celeste corpus now has an Inlay source boundary, but its internal
design is still predominantly the former flat customasm program: 160 legacy
object-offset references, one structured procedure, an object record that
misnames overlapping type-specific storage, and generated blank lines where
comments were stripped. The port should demonstrate how Inlay improves
human-authored assembly rather than merely prove that Inlay can pass it
through.

This is Phase A of the Celeste refactor. Its defining constraint is exact
machine-code preservation: it improves names, layouts and source structure
only where the generated 65,536-byte image remains byte-for-byte identical.
Custom-CPU-native instruction selection and architectural redesign belong to a
separate Phase B change.

## What Changes

- Restore the original Celeste commentary and formatting while compacting
  comments only in Inlay's bounded expanded-source workspace.
- Replace the monolithic object tail with a common object core and an explicit
  union of player, spawn, smoke and title payload views.
- Introduce nominal enums for object kinds and lifecycle states while retaining
  stable compatibility symbols where raw target instructions require them.
- Express object lifecycle routines as namespaced procedures with physical
  receiver contracts.
- Describe video and audio MMIO blocks as explicit-offset layouts and typed
  overlays, then migrate eligible direct register accesses.
- Preserve the exact target instruction stream and the established complete-ROM
  equivalence gates.
- Record remaining raw indexed object operations as a concrete language gap
  rather than disguising them as completed migration.
- Establish the byte-identical baseline from which a later customasm-only
  redesign can intentionally change instruction bytes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `layout-aware-modules`: Discard comments while constructing bounded expanded
  source without discarding source lines or original checked-in commentary.
- `layout-aware-assembly`: Accept qualified procedure names and lower them to
  target-valid symbols while retaining procedure-local label scope.
- `celeste-layout-aware-build`: Require semantic object variants, enums,
  lifecycle procedures and typed hardware overlays in the production corpus.

## Impact

The portable Inlay module expander and its tests change, as do Celeste layout,
object, player, draw, room, sound and main modules. Conformance gains semantic
construct-count and readable-source checks. The ROM, ABI, memory map and
customasm encoder remain unchanged.

This change does not remove compatibility `O_*`/`T_*` symbols, introduce
general namespaces, adopt additional custom-CPU instructions, reorganize the
main loop, or redesign whole game modules. Those operations invalidate its
byte-equivalence contract and are intentionally deferred to Phase B.
