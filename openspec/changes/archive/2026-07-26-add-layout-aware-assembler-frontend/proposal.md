## Why

The game corpus already contains object records, nested data layouts, fixed
pools and pointer-relative field access, but expresses them as independently
maintained offset constants. customasm can encode a resolved operand or expand a
local pseudo-instruction, but it cannot model nominal layouts, typed physical
locations or target-dependent field lowering; a semantic frontend is needed,
and its core must be suitable for the eventual PICO-8-like in-console editor and
assembler rather than tied to a host scripting runtime.

## What Changes

- Add an architecture-neutral layout-aware assembly frontend split into a
  bounded-memory portable core and platform shells.
- Implement the core in a conservative freestanding-friendly C subset using
  caller-supplied storage, integer handles, bounded tables and callback-based
  input, output and diagnostics.
- Add a host command that connects the core to files and emits ordinary
  customasm source for the existing build and conformance workflow.
- Add a first language slice covering fixed-width primitive types, packed
  structures, nested structures, fixed arrays, explicit padding, compile-time
  layout properties and static assertions.
- Add typed physical-location declarations and typed field operands, with
  target-defined lowering rather than a universal instruction syntax.
- Add an initial extended-6502 target that lowers typed loads and stores through
  a named zero-page pointer pair to the existing `(zp), #disp` customasm forms.
- Preserve raw customasm as the initial host assembler, ISA encoder, bank placer
  and binary/symbol/hex emitter.
- Define the backend boundary so a future in-console shell can connect the same
  semantic core to an editor buffer and a native instruction encoder without
  routing through customasm text or host files.
- Treat one canonical machine-readable ISA description capable of producing
  host customasm rules and compact in-console encoder tables as a required
  follow-on architecture, while deferring that description and native encoder
  from this first slice.
- Emit deterministic generated customasm and source-location information on the
  host while keeping JSON, filesystem and process execution outside the core.
- Exercise the core under deliberately constrained workspaces and require
  explicit capacity errors rather than allocation failure or unbounded growth.
- Validate the frontend against the corpus by reproducing the Celeste object
  layout and proving representative typed field accesses emit byte-identical
  code to their handwritten customasm equivalents.
- Establish an explicit boundary for this first slice: native instruction
  encoding, canonical ISA generation, the in-console shell, procedures, frames,
  calling conventions, `invoke`, clobber tracking, automatic register
  allocation, pools, method tables and runtime object semantics are deferred.
- Leave all existing game build paths unchanged until a later migration change
  adopts the new source format.

## Capabilities

### New Capabilities

- `layout-aware-assembly`: Defines the bounded portable frontend core, language
  slice, layout calculation, typed field operands, backend interface, initial
  host customasm emission, diagnostics, capacity behaviour and corpus
  equivalence gates.

### Modified Capabilities

None. The existing `assembler-toolchain` remains the production raw-customasm
pipeline; this change adds a frontend and conformance fixtures without migrating
the game builds.

## Impact

- New portable C frontend core and host command under `tools/`.
- New target definition for this console's extended 6502.
- New frontend parser, layout, diagnostic, capacity and golden-output tests,
  including builds with constrained workspaces.
- New representative layout-aware source fixture derived from
  `CelesteObject`, plus byte-identity comparison against existing assembly.
- New documentation for the language boundary and frontend-to-customasm
  host pipeline plus the future editor-to-native-encoder pipeline.
- customasm remains pinned at the existing version and is the only component
  that emits final machine images in this change, but is no longer described as
  the permanent backend architecture.
- A later change must define a canonical ISA description and native encoder
  before the frontend can assemble inside the console.
- No RTL, opcode, memory-map, simulator or game-source behaviour changes are
  included.
