## Context

Entries already carry a per-sprite depth (1-4 bpp). Introducing many patterns raises the central question: how is a variable-depth sprite sheet laid out in memory so that it is *flexible* (a 1bpp pattern should cost a quarter of a 4bpp one - capacity is the scarcest resource at 2KB) and *predictable* (the PPU must turn an entry into pattern-row fetches with fixed, simple, bounded addressing - no lookups, no multiplies, no variable latency surprises)?

## Goals / Non-Goals

- Goals: distinct pattern per sprite; mixed-depth sheet with proportional cost; deterministic fetch addressing and bounded blit latency; CPU-friendly upload port.
- Non-Goals: tilemap/camera layer (step 2), pal/palt/clip draw state (step 3), pattern sizes other than 8x8, hardware allocation/compaction.

## Decisions

### Memory layout strategy: plane-slot base addressing

Three strategies were considered for laying out variable-bpp patterns:

1. **Uniform 4bpp slots** (index * 32 bytes). Perfectly predictable - address is a shift - but rigid: a 1bpp pattern wastes 75% of its slot. At 2KB that caps the sheet at 64 patterns regardless of depth. Rejected: pays for flexibility we already implemented per-entry.

2. **Depth-banked regions**. The sheet is split into regions with per-region configured bpp (e.g. four quadrants, each with a 2-bit depth register); an index's high bits select the region. Proportional cost, and addressing stays shift-based within a region - but it adds mode registers the PPU must consult per fetch, entry depth and region depth can disagree (a hidden invariant), and repartitioning the sheet means rewriting config and reshuffling content. Rejected: global state makes fetches contextual, not self-contained.

3. **Plane-slot base addressing** (chosen). The sheet is an array of 256 uniform 8-byte *plane slots* (one 8x8 bitplane each). An entry stores a plane-slot **base address** instead of a pattern number, and its existing bpp field doubles as the pattern's footprint: the pattern is `bpp` consecutive slots. Plane `p`, row `r` lives at byte `{base + p, r}` - the fetch is a small add and a concatenation, identical for every entry.

The chosen layout is flexible because any mix of depths packs with zero waste and no partitioning: allocation is a CPU-side bump allocator (or any policy the game prefers - the hardware has no opinion). It is predictable because every fetch is self-contained in the entry: no tables, no region registers, no multiply (the only arithmetic is `base + p` with p < 4), and blit latency is exactly `bpp + 1` fetch cycles plus the fixed 4-cycle line-buffer read-modify-write - knowable per entry at list-build time, which is what a scanline budget needs. The trade-off accepted: the CPU can construct a base that overlaps two patterns or dangles off a mixed boundary; that is treated as a feature (cheap pattern variants by offsetting into a neighbor's planes) rather than a fault to detect.

### Fetch pipeline

On a scanline hit the engine clears its 4 plane-row registers and issues one sheet read per plane (`bpp` reads, pipelined issue/capture, +1 drain cycle), then runs the existing RD0/RD1/WR0/WR1 line-buffer sequence. The sheet has a dedicated read port, so plane fetches never contend with the line buffer or the display; worst-case line cost is 20 (clear) + 128 (scan) + hits x (bpp+5) cycles against the 644-cycle line budget - about 70 fully-4bpp sprites *per scanline*. A future optimization can overlap plane fetches with the line-buffer reads (different memories), but sequential is kept for v1 of the sheet: determinism is the selling point.

### Register map

$4000-$4007 (old pattern rows) and $400E (plane select) are obsolete. New: $4000 sheet address low, $4001 sheet address high (3 bits), $4002 sheet data - each write stores and auto-increments, so an upload is one address setup plus N data writes. $400E becomes the staged pattern base, committed with X/Y by the $400B flags write (4 register writes per streamed sprite). Entry packs to 31 bits: {pal[3:0], bppm1[1:0], yflip, xflip, base[7:0], y[6:0], x[7:0]} - still two 16-bit BRAM words.

## Risks / Trade-offs

- Blit latency grows by bpp+1 cycles -> per-line sprite ceiling drops from ~100 to ~70 worst-case; still far above practical use. Mitigation documented (fetch/RMW overlap).
- No hardware bounds check on base+p past the sheet end (wraps). CPU convention, like everything else in the map.
- Breaking register-map change; main.asm and testbench updated in the same change.

## Migration Plan

Single change: RTL, sheet image, testbench, golden model, and main.asm land together. The default sheet image keeps the arrow at base 0, so old visuals are reproducible by streaming base=0 entries.

## Open Questions

- Sheet size: 2KB (256 slots) chosen for hx8k headroom; parameterized so a UP5K target can grow it.
