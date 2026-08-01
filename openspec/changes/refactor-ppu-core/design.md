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

16 BRAMs, and the four that the declared arrays did not obviously account for
are the interesting number: storage forced by *port width*, not by capacity, is
the only kind a restructuring can recover. Identifying which is worth more than
shaving bytes off the overlay, because `hardware-gaps.md` entry 9 wants a second
overlay plane.

**Measured — see §Measurements below.** The four turned out not to be overhead
at all: the sprite list is a 34-bit array that was missing from the estimate
entirely, and the line buffer is two blocks rather than one for the same reason.
Both are width-forced and neither is recoverable without a behaviour change.

## Measurements

Everything in this section is a number the tooling produces, not an estimate.
`make ppu-synth` prints the resource and timing block; `make ppu-probe
GAME=<g>` prints the per-line accounting; `make ppu-check` asserts the frames
and the budget. They were taken before any restructuring, and the split is
measured against them step by step.

### Baseline (task 1.6)

`yosys synth_ice40 -top sprite_compositor` then `nextpnr-ice40 --hx8k
--package tq144:4k --freq 50 --seed 1`, on `rtl/sprite_compositor.sv` alone:

| | |
| --- | --- |
| SB_LUT4 | 1846 |
| SB_CARRY | 340 |
| Flip-flops | 678 |
| Logic cells | 2623 / 7680 (34%) |
| Block RAM | 16 / 32 (50%) |
| Fmax | 64.73 MHz (PASS at 50 MHz) |
| Critical path | `entry_q` → … → `linebuf` write data |

The proposal's 62.6 MHz and this 64.73 MHz are the same measurement with a
different placement seed; nextpnr moves ~3 MHz run to run, so only differences
larger than that mean anything.

**A noise floor worth knowing before reading any delta:** yosys's abc9 LUT
mapping is reproducible for a given *file list*, but not across file lists.
Adding `ppu_regs.sv` to the yosys command line moved the total from 1846 to
1840 LUT4 even though `hierarchy` removed it again as unused. Treat anything
under ~10 LUT4 as noise, and compare runs made with the same `PPU_RTL`.

### Block RAM by consumer (task 2.1)

From the yosys netlist, via `tools/ppu_bram.py`. An `SB_RAM40_4K` is 4096 bits
and at most 16 bits wide, so an array wider than 16 bits is split across blocks
by width and each block is only as deep as the array — the rest is unreachable.

| Consumer | Shape | Data bits | Blocks | Block bits | Used | Forced by |
| --- | --- | --- | --- | --- | --- | --- |
| `sheet` | 2048 x 8 | 16384 | 4 | 16384 | 100% | capacity |
| `ovl` | 2560 x 8 | 20480 | 5 | 20480 | 100% | capacity |
| `map_lo` | 512 x 8 | 4096 | 1 | 4096 | 100% | capacity |
| `map_hi` | 512 x 8 | 4096 | 1 | 4096 | 100% | capacity |
| `list` | 128 x 34 | 4352 | **3** | 12288 | 35% | **port width** |
| `linebuf` | 64 x 32 | 2048 | **2** | 8192 | 25% | **port width** |
| | | 51456 | 16 | 65536 | 78% | |

So the "four unaccounted blocks" were not overhead: the sprite list is three
blocks that the estimate omitted entirely, and the line buffer is two rather
than one. Eleven of the sixteen are capacity — they hold exactly the bits they
declare — and five are width-forced, holding 6400 bits in 20480.

Neither width-forced consumer is recoverable by restructuring:

- **`list`, 3 → 2** needs the entry to fit in 32 bits. It is 34: `{rep[3],
  pal[4], bppm1[2], yflip, xflip, base[8], y[7], x[8]}`, and every field is
  load-bearing, so shrinking it is a behaviour change rather than a
  reorganisation. The alternative — 32 bits in BRAM and the other 2 bits x 128
  entries in fabric — costs 256 flip-flops, about 3.3% of the device's logic
  cells, to recover one block, 3.1% of its BRAM. That is a wash, and it trades
  the scarcer resource for the less scarce one in the wrong direction.
- **`linebuf`, 2 → 1** needs a 16-bit line-buffer word, which turns an 8-pixel
  row's two-word read-modify-write into three: +2 clocks per composited cell.
  Measured against the probe below, that is +40 clocks a line for nemo (20.03
  fetched cells) and +26 for celeste (12.89), and celeste's worst line is
  already at 86.7% of budget. One block is not worth it.

**16 is the floor without a behaviour change.** A second overlay plane
(`hardware-gaps.md` entry 9) is +5, putting the PPU at 21 of 32.

And the PPU is not the only claimant. Measured the same way, `rtl/psg.sv` takes
**16 blocks** (`aram` 9, `wrom` 4, the reverb delay line 2, `recip` 1).
PPU + PSG is already 32 of 32, before the CPU's memory. Which leads to:

### Does the full chip place? (task 2.4)

**No, and not for a reason this change can fix.** `rtl/chip.sv:131` instantiates
`ram_async #(.A(16), .D(8))`: a 64 KB array, 512 kbit, against the hx8k's total
of 128 kbit of block RAM. Even mapped perfectly it is 4x the device, and yosys
does not map it at all — `synth_ice40 -top top` was still in abc9 after twenty
minutes, having extracted **1,727,297 AND gates** from a design whose target has
7680 logic cells. `rtl/top.pcf` assigns 9 pins and none of them is an external
memory bus, and no bitstream has ever been committed.

So the FPGA build is not currently reachable, the model is simulation-only, and
**"decrease FPGA block counts" has no denominator**. Per-module figures are the
only meaningful ones, which is what `make ppu-synth` reports and what every step
of this change is measured with.

**Followed up after the change, at the user's request** (shrink the RAM for
synthesis while the external-memory abstraction is built elsewhere). Two things
turned out to be wrong with the paragraph above, and both are worth recording:

- **The 64 KB was not why yosys exploded.** `ram_async`'s `initial` block
  printed three startup dumps, and a `$display` that reads `mem[...]` is an
  *asynchronous read port*: a memory with one cannot be a block RAM, so the
  whole array went to fabric. With the dumps behind `` `ifdef VERILATOR ``,
  yosys goes from 7 minutes and 66,395 LUT4 to **70 seconds and 12,229**, and
  the RAM maps to block RAM. Capacity was the obvious explanation and it was
  not the operative one.
- **The chip still does not fit, and memory is no longer the reason.** At 8 KB
  (`rtl/top.sv` passes `RAM_ADDR_BITS(13)`; the simulator keeps 64 KB and every
  game still renders byte-identically), nextpnr reports **18,709 / 7,680 logic
  cells — 243%** and 48/32 block RAM. No RAM size changes the logic figure: the
  RAM is 24 LUT4 once it is block RAM. The PSG is **9,323 LUT4 and 5,804 FF,
  76% of the logic**; the PPU is 1,776 / 823, matching its standalone
  measurement, which is a useful confirmation that the numbers in this document
  hold in context.

The PPU's 16 blocks are still not the binding constraint on a board build. But
neither is the RAM — external memory removes 16 of the 48 blocks and none of
the 243% logic.

### Where a scanline actually goes (tasks 2.2, 2.3)

`make ppu-probe` runs a game headless and watches the engine's own state
register, so these are the engine's real scenes rather than a model of them.
Budget is 483 clocks (161 pixels x 3). Windows chosen to be gameplay, not title
screens — celeste's title screen is nearly empty and measuring it says the
engine is idle when gameplay runs at 87% of budget.

| | breakout | nemo | celeste |
| --- | --- | --- | --- |
| frames measured | 340 | 340 | 250 |
| engine busy, mean | 179.4 | 207.2 | 227.2 |
| engine busy, worst line | 338 (70.0%) | 215 (44.5%) | **419 (86.7%)** |
| lines that overran | 0 | 0 | 0 |
| clear | 20.00 | 20.00 | 20.00 |
| tile walk | 43.00 | 43.00 | 43.00 |
| list scan | 36.00 | 2.97 | 46.45 |
| pattern fetch | 41.96 | 60.10 | 42.89 |
| line-buffer read | 21.04 | 41.06 | 41.45 |
| line-buffer write | 17.38 | 40.06 | 33.41 |
| pattern fetches / line | 8.69 | 20.03 | 12.89 |

Three things follow, and two of them are "no":

**Pattern reuse between consecutive entries (task 2.2) is real but wildly
uneven.** Consecutive fetches with the same `(base, row, bpp)`:

| | breakout | nemo | celeste |
| --- | --- | --- | --- |
| reuse rate | 41.7% | **94.8%** | 21.1% |
| fetch clocks / line | 41.96 | 60.10 | 42.89 |
| **saving available** | 17.5 | **57.0** | 9.0 |
| as % of that game's worst line | 5.2% | 26.5% | 2.2% |

nemo's 94.8% is the tile pass: a nonogram grid is long runs of the same cell,
and each one re-reads the same plane rows. celeste's 21.1% is a scene of
distinct sprites, where the cache would idle. The saving is worth having and it
is cheap — one registered comparison — but it is worth stating that the game
under the most line pressure is the one it helps least.

**Display-slot stalls (task 2.3) are not worth a block RAM.** Clocks per line
lost to line-buffer port contention in `E_RD0`/`E_RD1`:

| | breakout | nemo | celeste |
| --- | --- | --- | --- |
| stall clocks / line | 3.66 | 1.00 | 8.04 |
| % of the 483-clock budget | 0.8% | 0.2% | **1.7%** |
| % of the read clocks | 17.4% | 2.4% | 19.4% |

The worst case across all three ports is 8 clocks in 483. Removing it costs the
resource the PPU has least of, to buy back 1.7% of a line. **Task 4.4 is
answered "no" before it is started**, and the number is the answer.

**The tile walk is a flat 43 clocks a line in every game**, because `E_TMAP0`
and `E_TMAP1` cost two clocks per column whether the cell is empty or not: 21
columns x 2, plus the final `E_TMAP0` that finds `tk >= TILE_COLS`. That is
18.9% of celeste's engine time and 24.0% of breakout's, and unlike the fetch
cache it does not depend on the scene. It is the largest single fixed cost in
the engine.

## Result

### Resources and timing

`make ppu-synth` and `make ppu-timing SEEDS=9`, against the baseline recorded
above. Fmax is quoted over nine placement seeds because the spread is ~5 MHz,
wider than most of the deltas here — a single number could be made to say
anything.

| | before | after | |
| --- | --- | --- | --- |
| SB_LUT4 | 1846 | **1814** | -32, -1.7% |
| SB_CARRY | 340 | 347 | +7 |
| Flip-flops | 678 | 837 | +159, the blit pipeline and the second entry register |
| Logic cells | 2623 | **2711** | +88, +3.4% |
| Block RAM | 16 / 32 | **16 / 32** | unchanged |
| Fmax, median | 62.66 | 60.51 | -2.15 MHz |
| Fmax, min / max | 60.61 / 65.98 | 59.13 / 64.52 | |
| Critical path | `entry_q` -> line-buffer write | `ovl` read -> `color` | it moved off the blit |
| Lines of RTL | 620, one module | 1179, eight modules | |

### Per-line clocks, on the three ports

`make ppu-probe`, same windows and key scripts as the baseline measurement.
Budget 483.

| | breakout | nemo | celeste |
| --- | --- | --- | --- |
| worst line, before | 338 (70.0%) | 215 (44.5%) | 419 (86.7%) |
| worst line, after | **307 (63.6%)** | **158 (32.7%)** | **383 (79.3%)** |
| mean, before | 179.4 | 207.2 | 227.2 |
| mean, after | **143.3** | **149.2** | **200.8** |
| tile walk | 43 -> 22 | 43 -> 22 | 43 -> 22 |
| pattern fetch | 41.96 -> 25.43 | 60.10 -> 22.10 | 42.89 -> 36.68 |

celeste is the one that matters: it was the closest to the budget at 86.7%, and
it has 100 clocks of headroom now instead of 64.

### What is bit-identical

- Ten golden scenes, every pixel, at every step of the change.
- `breakout`, `nemo` and `celeste`: the full 160x120 frame, **byte-identical**
  to `git show HEAD:rtl/sprite_compositor.sv` under the same key scripts.
- The register map, including the two readback bugs it turns out to have (see
  `docs/hardware-gaps.md`) — asserted as they are, because this change is
  behaviour-preserving and fixing them here would hide a real change inside a
  refactor.

### Is the PPU the chip's critical path now?

No, and it was not before either. Three separate reasons, in increasing order
of how much they settle the question:

1. The PPU closes at 60.5 MHz median against a 50 MHz board target and a
   3.5 MHz simulator clock.
2. `refactor-cpu-core` documents the CPU's unregistered memory path — `AB =
   {ZEROPAGE, DIMUX}` routes a byte out of a block RAM, through three muxes and
   back into a block RAM address port inside one clock — and that is a longer
   path than anything here.
3. **The chip does not place at all** (task 2.4). Until `ram_async`'s 64 KB
   array is dealt with there is no chip-level critical path to be on.

So the blit pipelining bought no throughput, and this section says so rather
than implying otherwise. What it bought is structural, and the structure is the
thing the next two features need.

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

Four were opened with this change. Three are now answered by §Measurements; the
answers are kept here in one line each so the question and its resolution stay
together.

- **Does the full chip even place today?** **Answered: no**, and the PPU is not
  why. `ram_async` is 64 KB against 128 kbit of device BRAM — 4x over on its
  own — and `top.pcf` has no external memory bus. Per-module numbers are the
  only meaningful ones.
- **How much pattern reuse is there between consecutive entries?** **Answered:
  94.8% (nemo), 41.7% (breakout), 21.1% (celeste)**, worth up to 57 / 17.5 / 9.0
  clocks a line. Worth building, with the caveat that it helps the
  most-pressured game least.
- **Is the line buffer's port contention worth a BRAM?** **Answered: no.** The
  worst case across three ports is 8.04 clocks of 483, 1.7%.
- **Should the tile pass and the sprite scan stay one FSM?** Still open, and now
  better posed: the tile walk is a flat 43 clocks a line in every game, the
  largest fixed cost in the engine and 18.9-24.0% of its time. Whether that is
  recovered by a prefetch inside one FSM or by splitting the two is a task 4.3
  decision, taken after the split makes the interface visible.
