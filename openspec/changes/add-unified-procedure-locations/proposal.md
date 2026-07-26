## Why

Procedure parameters and frame locals currently use different declaration
forms even though both are typed names bound to physical storage. Calls and
returns need to extend the same layout-oriented grammar established by
structures, rather than introducing unrelated declaration prefixes or
multi-line call blocks.

## What Changes

- Define one procedure-member grammar based on `name : type` plus placement
  and role qualifiers.
- Treat `in <physical-location>`, `in frame`, and `return` as explicit
  descriptions of where a typed procedure name resides.
- Add target-defined calling conventions that fill in omitted parameter and
  return locations without creating virtual values.
- Add concise assembly-style marshalled invocation using comma-separated
  `name=value` bindings and pre-invocation parallel-assignment semantics.
- Extend frame storage to pointer and fixed-size aggregate locals with
  explicit typed transfers.
- Preserve raw target calls and manual argument placement as the ordinary
  machine-level escape hatch.
- Require focused handwritten assembly equivalence and complete Celeste ROM
  equivalence for every migrated construct.
- **BREAKING**: Replace the provisional `local name : type` spelling with the
  unified `name : type in frame` spelling.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `layout-aware-assembly`: Unify procedure-member declarations and add
  convention-assigned locations, typed returns, aggregate frame locations and
  single-statement invocation.
- `celeste-layout-aware-build`: Exercise the unified declarations and call
  lowering through build-only Celeste modules while retaining exact ROM bytes.

## Impact

The portable parser, bounded procedure/location records, semantic event stream,
target calling-convention metadata, console6502 lowering, host emitter,
conformance fixtures, Celeste build-only adapter and language documentation
will change. Existing raw assembly remains valid. No register allocator,
automatic lifetime management, hidden receiver preservation, native encoder,
heap, garbage collector, or edit beneath `src/celeste/` is introduced.
