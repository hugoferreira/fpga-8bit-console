## Context

`rtl/sprite_compositor.sv`, 620 lines, one module, one ten-state FSM. It
composites line *N+1* into the back bank of a line buffer while line *N* is
displayed: clear, then a tile pass, then the sprite list, with a behind-split
partition that runs part of the list before the tiles.

Measured on the hx8k, compositor alone (`yosys -top sprite_compositor`,
`nextpnr-ice40 --hx8k`):

| | |
| --- | --- |
| Logic cells | 2623 / 7680 (34%) |
| LUT4 / carry / FF | 1846 / 340 / 678 |
| Block RAM | **16 / 32 (50%)** |
| Fmax | 62.6 MHz |
| Critical path | `entry_q` → `bmask` → per-pixel palette → 64-bit shift → merge → `linebuf` write data |

Per-line cycle budget, from the FSM (161 pixel-times x 3 clocks = 483 clocks):

| | clocks |
| --- | --- |
| clear (`E_CLEAR`, one per lane) | 20 |
| tile pass, ~13 non-empty cells of 21 at 2bpp | ~133 |
| scan, per entry in the list | 1 |
| a composited entry | bpp + 7, plus display-slot stalls |
| left for sprites | ~330, i.e. **25-37 one-bpp sprites on one line** |

## Goals / Non-Goals

**Goals**

- A regression net that makes restructuring verifiable rather than argued.
- Module boundaries that let a display-path feature be added without editing
  the engine FSM.
- A pipelined blit, so the longest path stops being "everything at once".
- An honest block-RAM account, because the PPU owns half the device's supply
  and the next two features both want storage.
- Measured answers on prefetch and caching — including "no".

**Non-Goals**

- Any behaviour change. Bit-identical output is the acceptance test.
- Any new register or capability. Entries 8 and 9 of `hardware-gaps.md` are
  unblocked by this work, not delivered by it.
- Chasing Fmax for its own sake. See the sequencing decision below.
- Touching `chip.sv`'s instantiation or the `$4000-$403F` map.

## Decisions

### Decision: the net comes first, and nothing lands before it is green

This is the lesson `refactor-cpu-core` records: the previous plan for the CPU
was expensive mainly because `make test` asserted nothing, so every step had to
be justified by fear. The compositor is in the same position today — its
testbench renders 96 frames and dumps PPMs that nobody compares.

The net is two assertions, both already prototyped:

1. **Golden frames.** The repeat field was accepted because one entry with
   rep=8 rendered pixel-identically to the eight entries it replaced, over all
   19200 pixels, checked inside the testbench against a captured `frame_pix`.
   That is exactly the mechanism, generalised: render a fixed scene, compare
   against committed references.
2. **Cycle accounting.** An overrun today is silent — the engine restarts at
   `line_start` and the tail of the list simply does not composite. A test that
   only looks at pixels can pass while the design has lost its margin, so the
   harness must also assert that the engine reached idle before the line ended.

The end-to-end net is already there and costs nothing to keep: the three ports
render real scenes, and `celeste`'s tile layer is checked against pixels
rendered from the cart ROM (99.5%). If a refactor breaks something the golden
frames miss, a port screenshot will show it.

### Decision: split along the pipeline, not along the file

The tempting split is by feature (tiles, sprites, overlay). The right split is
by *stage*, because that is where the interfaces are narrow and it is what
makes the pipelining step possible afterwards:

| Module | Owns | Interface |
| --- | --- | --- |
| `ppu_regs` | `$00-$3F`, staging registers, DMA port, readback | register writes out to everyone; no datapath |
| `ppu_map` | `map_lo`/`map_hi`, the per-line column walk | cell → synthesized entry |
| `ppu_scan` | the sprite list, `bsplit`, hit test | entry stream, in composite order |
| `ppu_fetch` | the sheet, plane reads, the repeat counter | entry → pattern rows + cell position |
| `ppu_blit` | pixel decode, draw palette, shift, mask, merge | rows + position → line-buffer write |
| `ppu_line` | the double-banked line buffer, bank swap | write port in, display read out |
| `ppu_display` | line-buffer read, overlay mix, screen palette | pixel out |

`ppu_map` and `ppu_scan` both produce entries and `ppu_fetch` consumes them,
which is exactly the structure the FSM already has — the tile pass synthesizes
a sprite entry and pushes it through the same fetch and blit path. Making that
an interface rather than a shared register is most of the work.

### Decision: pipeline the blit, and measure throughput as well as Fmax

nextpnr names the critical path and it is one chain, in one clock: entry
register → `bmask` → 8 parallel `dpal[e_pal + pix]` lookups → 64-bit barrel
shift by `off` → merge under two masks → line-buffer write data.

Cut it into stages: (1) decode planes to pixel values, (2) palette lookup, (3)
align and mask, (4) merge and write. Each stage is short and the fetch already
takes several clocks, so the added latency hides behind it.

The risk is that latency becomes throughput: a deeper pipeline that stalls per
entry would spend the line budget it was meant to protect. Hence the
requirement that per-line clock accounting must not regress — the spec asserts
both numbers, not just Fmax.

### Decision: Fmax is not currently the chip's problem, and the plan says so

The compositor closes at 62.6 MHz standalone. The board runs at 25 MHz and the
simulator's chip clock is 3.5 MHz. `refactor-cpu-core` documents why: the CPU
has no pipeline register between itself and memory, and `AB = {ZEROPAGE, DIMUX}`
routes a byte out of a BRAM, through three muxes and back into a BRAM address
port inside one clock. **The PPU is not the limiter today.**

So pipelining the blit buys nothing measurable *yet*. It is still in scope, for
two reasons worth stating rather than assuming:

- After the CPU refactor the PPU becomes the next candidate, and the blit is a
  single-cycle path that only gets longer as pixel formats widen.
- The pipeline stages are what make the module split hold together; doing them
  in the other order means splitting, then re-cutting the same seams.

If the measurement after the split shows the pipelining step buying nothing on
any plausible clock, that is a legitimate outcome and the tasks say so.

### Decision: prefetch and caching are assessed against the budget, not assumed

Three candidates, all measurable against the ~330 sprite clocks per line:

1. **Pattern reuse across entries.** The engine fetches `bpp` plane rows per
   entry even when consecutive entries share a pattern base and row. A single
   registered "last (base,row)" comparison would skip the fetch. The repeat
   field already exploits exactly this within one entry; the question is how
   often it holds *between* entries. Measurable from the three ports: count
   consecutive-entry pattern repeats per line in a trace.
2. **Display-slot stalls.** `E_RD0` and `E_RD1` each wait for `!disp_slot`, so
   every cell pays up to two stall clocks for line-buffer port contention. A
   wider line-buffer word or a second port removes them — at a BRAM cost, which
   is the resource the PPU has least of.
3. **Tile-pass prefetch.** The map read for column *k+1* could be issued while
   column *k* blits, collapsing `E_TMAP0`/`E_TMAP1` into the blit's shadow —
   ~21 clocks a line, ~6% of the sprite budget.

Each is a measurement first. The precedent is the hardware multiplier in
`hardware-gaps.md`: the naive reading said it was needed, and writing the code
idiomatically made the demand disappear. Any of these may end the same way.

### Decision: block RAM is counted by consumer before anything is optimised

16 BRAMs, and the declared arrays account for 12:

| Consumer | Bytes | Bits | BRAMs at 4 kbit |
| --- | --- | --- | --- |
| `sheet[0:2047]` | 2048 | 16 k | 4 |
| `ovl[0:2559]` | 2560 | 20 k | 5 |
| `map_lo` + `map_hi` | 1024 | 8 k | 2 |
| `linebuf[0:63]` (32-bit) | 256 | 2 k | 1 |
| **declared total** | | **46 k** | **12** |
| **actually placed** | | | **16** |

The four-BRAM gap is the interesting number: it is storage forced by *port
width or simultaneous access*, not by capacity — a memory that needs a CPU write
port and an engine read port in the same cycle gets duplicated. Identifying
which of the four are recoverable is worth more than shaving bytes off the
overlay, because `hardware-gaps.md` entry 9 wants a second overlay plane (+5)
and there are 16 BRAMs left on the device for everything else including the PSG
(which takes 9 more).

## Risks / Trade-offs

- **A behaviour-preserving refactor that is not.** The whole plan rests on the
  golden frames being comprehensive. Mitigation: the scene list is a spec
  requirement, not a test detail, and the three ports are a second net.
- **Pipelining costs throughput.** Mitigation: per-line clock accounting is
  asserted alongside the frames; a stall shows up as a failure, not as flicker.
- **The split adds LUTs.** Module boundaries can cost logic where a shared
  register was free. Mitigation: resource figures are reported per step, and a
  regression that is not paid for by clarity gets reverted.
- **Two refactors on one clock.** `refactor-cpu-core` is in flight. They touch
  different modules, but both change chip-level timing. Mitigation: the PPU is
  measured standalone, so its numbers are independent of the CPU's state.
- **Doing this instead of features.** The counter-argument is that entries 8, 9
  and any future format change all land in the display path and the FSM, which
  are the two most entangled parts. The PSG made the same trade and came out
  able to absorb a mixer rewrite.

## Open Questions

- **Does the full chip even place today?** `synth_ice40` on `rtl/top.sv` expands
  to 1.7 M AND gates because `ram_async.sv` is a 64 KB array — 512 kbit against
  the device's 128 kbit of BRAM. Either the board build uses external SRAM and
  the model is simulation-only, or `make bin/toplevel.bin` has not been run
  recently. Until that is answered there is no chip-level resource or timing
  number, only per-module ones, and "decrease FPGA block counts" has no
  denominator.
- **How much pattern reuse is there between consecutive entries?** Decides
  whether the fetch cache is worth building. Measurable from the existing
  ports before any RTL is written.
- **Is the line buffer's port contention worth a BRAM?** Removing the
  `disp_slot` stalls costs storage the PPU does not have spare.
- **Should the tile pass and the sprite scan stay one FSM?** They already share
  the fetch and blit path. Splitting them fully would allow a tile prefetch to
  overlap a sprite blit, at the cost of arbitration.
