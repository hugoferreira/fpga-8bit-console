## Context

`refactor-cpu-core` phase 2 tried to measure the console and could not: the
design does not place. The cause is `rtl/ram_async.sv` holding 64 KB in fabric on
a part with 16 KB of BRAM. This change puts main memory where it was always meant
to live and, in doing so, produces the first whole-chip timing and area numbers
this project has had.

## Goals / Non-Goals

**Goals**

- The design places, and `make timing` reports something.
- One interface, several backends, so the console stops caring what is underneath.
- Main memory that looks like a one-cycle memory on the common path.
- A stall that is correct, because it is now on the critical functional path
  rather than a theoretical concern.

**Non-Goals**

- A cache. The split map plus the free 16-bit pairing is the first answer; a
  cache is only justified by a measured row-miss rate that the split does not fix.
- Using more than 64 KB of the 2 MB. The 6502 address space is 64 KB and no
  banking scheme is proposed here.
- Burst transfers. The CPU issues one byte at a time; bursts only pay off with a
  cache line to fill.

## Decisions

### Decision: run the controller faster than the CPU

The board clock is 25 MHz; the part is rated 143. At 100 MHz a row-hit read is
~30 ns against a 40 ns CPU cycle, so it completes within one CPU cycle and the
CPU never learns that memory is external. Only row misses (~70 ns) and refresh
stall.

**Alternatives considered.** Running both at 25 MHz makes every access a
multi-cycle handshake and roughly doubles effective CPI. Running the CPU at
50 MHz halves the SDRAM clocks available per CPU cycle and turns row hits into
wait states too; it is only worth it once the row-miss rate is measured.

### Decision: pin a row rather than cache, and rather than spend BRAM

A row is 512 bytes and only two can be open. A 6502 working set — zero page,
stack, code, data — would thrash that.

`$0000-$01FF` is 512 bytes: **exactly one row**. Pinning bank 0's open row there
gives zero page and the stack a permanent home that never pays an activate,
while bank 1 rotates for code and data, where sequential fetch holds a row for
long stretches.

An earlier draft put those 512 bytes in BRAM instead. That was wrong on the
facts: the PPU holds 16 of the device's 32 block RAMs and the PSG the other 16,
measured off the netlist rather than estimated, so there is none spare. The
pinned row is the better answer regardless — it costs nothing and does not
compete with video and audio for an exhausted resource.

Measurable before it is committed to: task 3.1 requires the row-miss rate with
and without.

### Decision: the unused half of each 16-bit read is held, not discarded

The bus returns two bytes per 8-bit access. Holding the other half and serving
the next sequential fetch from it costs one register and one comparator, and it
is `refactor-cpu-core` phase 4's prefetch obtained from the bus width rather than
from the core. Task 4.7 measures the hit rate before the claim is made.

### Decision: the stall is the CPU's problem to survive, and must be proven

`refactor-cpu-core` gate T7 already requires that `RDY` low suspends the core at
any cycle boundary including a write, with every access performed exactly once on
release. That gate exists because `memory_arbiter.sv:76-85` records that the
Arlet core cannot do it — a vsync-paced program streaming register writes had the
stall land mid-write and derailed the PC. With external memory that stall is no
longer optional or rare, so T7 is a prerequisite of this change rather than a
parallel concern.

## Risks / Trade-offs

- **The part geometry is inferred from a pinout.** Everything about the row-hit
  strategy follows from the row/column split. Task 1.1 confirms it first.
- **The clock-domain crossing is new.** The console has been single-domain
  throughout; `clocks.sv` currently ties `masterclk`, `videoclk` and `cpuclk`
  together. Task 4.5 makes the rule explicit rather than discovering it.
- **`rtl/top.sv` has never instantiated a PLL.** The board runs the raw 25 MHz
  pin, so the PLL path is untested on hardware.
- **Simulation will stop being the whole truth.** `sim/console.cpp` keeps a flat
  array, so row misses and refresh will exist only on hardware unless the
  simulator models them. Task 6.5 measures the difference rather than assuming
  it is small.
