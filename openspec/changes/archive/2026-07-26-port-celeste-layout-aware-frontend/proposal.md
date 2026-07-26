## Why

The layout-aware frontend is only proven useful when a real game can pass
through it without changing machine code. Celeste is the strongest first
adopter because its 64-byte object record already concentrates the repository's
largest body of manually maintained field offsets and pointer accesses.

## What Changes

- Add a layout-aware Celeste entry point that declares the complete packed
  `CelesteObject` shape and derives the existing `O_*` compatibility symbols
  from generated properties.
- Generate build-only Celeste body and memory-map adapters without modifying
  the concurrently owned `src/celeste/` corpus sources.
- Route `make GAME=celeste hex` through the portable frontend and then the
  existing pinned customasm encoder.
- Gate the port on exact instruction bytes for representative typed operands
  and byte-for-byte equality of the complete 64 KiB Celeste ROM.
- Run the existing reset-vector Celeste functional suite against the frontend
  output.
- Retain customasm as the host instruction encoder; native encoding and direct
  conversion of every field operand remain separate work.

## Capabilities

### New Capabilities

- `celeste-layout-aware-build`: Defines the authoritative layout, compatibility
  boundary, full build pipeline and assembly-equivalence gates for the Celeste
  frontend adoption.

### Modified Capabilities

None.

## Impact

The change adds a new source entry under `src/layout/`, new host preparation
and conformance tools under `tools/laasm/`, build-only generated files under
`build/layout_aware/`, and append-only Makefile integration. Existing Celeste
game modules, memory-map source, ISA rules, RTL, simulator code and binary
format remain unchanged.
