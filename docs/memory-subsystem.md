# The memory subsystem

Why it is the blocker, what the board actually has, and what the abstraction has
to look like. Opened when `refactor-cpu-core` phase 2 found that the design has
never placed and that the CPU is not the reason.

> **Since 2026-07-25 this is the blocker on *one* of two boards.** The console
> also targets the Sipeed Tang Nano 20K, whose GW2AR-18C has 828 kbit of block
> RAM, and there the 64 KB array simply fits — 32 of 46 blocks, no controller,
> no external memory. That does not retire anything below: the BlackIce still
> needs this, and so does any machine bigger than 64 KB. It does mean the
> abstraction is no longer the only route to a bitstream that can run a game.
> See [`boards.md`](boards.md) and the section at the end of this file.

## The problem, stated once

`rtl/ram_async.sv` models the console's 64 KB main memory as an on-chip array:

```systemverilog
ram_async #(.A(16), .D(8), .FILE("./rtl/ram.hex")) ram(...)   // chip.sv:131
```

An iCE40 HX8K has 32 x 4 kbit BRAM - **16 KB in total** - and the PSG's audio
RAM, wavetable and reverb buffer, the PPU's overlay and map, the text buffer and
the font already want most of it. Roughly 640 kbit asked for against 128 kbit
available.

yosys cannot map it, falls back to logic, and emits **1,727,271 AND gates and
4,954,853 wires**, then never finishes ABC9. That is why `synthesis.log` has
always ended mid-optimisation, and why gates T4 (critical path relocated),
T5 (Fmax) and T8 (area) have no numbers.

Nothing about the CPU makes this better or worse. It is a missing abstraction:
there is no memory interface, no controller, and `rtl/top.pcf` has no memory
pins at all.

## What the board has

myStorm BlackIce MX, from
[`folknology/IceCore` `Examples/blackice-mx.pcf`](https://raw.githubusercontent.com/folknology/IceCore/refs/heads/master/Examples/blackice-mx.pcf):

| Signal | Pins |
| --- | --- |
| `A[0..11]` | 117 119 121 124 130 125 122 120 118 116 115 114 |
| `DQ[0..15]` | 78-85, 87 88 90 91, 95-98 |
| `udqm` / `ldqm` | 94 / 93 |
| `we` / `cas` / `ras` / `mcs` | 107 / 110 / 112 / 113 |
| `cke` / `rclk` | 128 / 129 |
| `clk` | 60 |

**16 Mbit, 16 bits wide, rated 143 MHz.** There is no separate `BA` pin, and
there are twelve address lines, which is the signature of a 1M x 16 two-bank
part: `A[10:0]` carry the row and column address, `A11` is the bank select.
2048 rows x 256 columns x 2 banks x 16 bits = 16 Mbit. **A row is 512 bytes.**

> Derived from the pinout, not from a part marking. Worth confirming against the
> chip on the board before the controller is written, because the row/column
> split decides the row-hit strategy below.

The console needs 64 KB of the 2 MB available, so capacity is a non-issue. What
matters is latency and the row structure.

## The key consequence: the CPU does not have to slow down

The board clock is 25 MHz and the SDRAM is good for 143. Running the controller
faster than the CPU makes most of the latency disappear inside a single CPU
cycle. 100 MHz is a clean x4 from the 25 MHz pin (`rtl/pll.v` already exists,
generated for 50; it needs regenerating and, unlike today, actually
instantiating).

At 100 MHz (10 ns) against a 40 ns CPU cycle:

| Access | Cost | Fits in one CPU cycle? |
| --- | --- | --- |
| Read, row already open | CAS + CL2 ≈ 3 clk = 30 ns | **yes** |
| Read, row miss | PRE + ACT + CAS + CL2 ≈ 7 clk = 70 ns | no - one wait state |
| Auto-refresh | ~7 clk, once per 31.25 µs | one stall per ~780 CPU cycles (0.13%) |

So a row hit looks exactly like today's BRAM: address out, data back next cycle,
no stall. **The CPU keeps its one-access-per-cycle model** and the combinational
address path measured in `docs/cpu-baseline.json` stays viable.

Two things follow, and they are the whole design:

1. **Row misses and refresh must stall the CPU.** `RDY` stops being decorative.
   That makes gate T7 (`cpu6502_stall_tb`) load-bearing rather than a nicety, and
   it retires the memory arbiter's standing workaround at
   `memory_arbiter.sv:76-85` - which exists precisely because the old core
   cannot be stalled mid-write.
2. **Row hits should be the common case, by construction** - see below.

## Keeping the row-hit rate high

A row is 512 bytes and there are two banks, so at most two rows are open at
once. A 6502 working set scatters across zero page, the stack, code and data,
which would thrash two banks badly if all of it lived in SDRAM.

The fix is a split, not a cache:

- **Zero page and the stack (`$0000-$01FF`) stay in BRAM.** 512 bytes, one BRAM,
  and they are the hottest 0.8% of the address space by a wide margin - every
  `(zp),Y`, every push, every JSR. Keeping them on-chip removes most of the
  interleaving that would cause misses.
- **Code and data go to SDRAM** with an open-row policy per bank. Instruction
  fetch is sequential, so it stays inside a 512-byte row for long stretches.
- The MMIO windows (`$4000-$41FF`, `$E000-$EA00`, `$F000-$F800`) already bypass
  main memory in `memory_arbiter.sv` and are unaffected.

**The 16-bit bus is a free two-byte prefetch.** Every SDRAM read returns a
16-bit word for one 8-bit CPU access. Holding the other half satisfies the next
sequential fetch with no memory traffic at all - which is `refactor-cpu-core`
phase 4's prefetch, obtained from the bus width rather than from the core. On a
corpus where the mean instruction is 1.9 bytes, that is close to halving fetch
traffic.

## The abstraction

One interface, several backends, so the console stops caring what is underneath:

```systemverilog
// Request: valid for one cycle when `req` is high.
input  logic [15:0] addr;
input  logic        req;      // asserted for one access
input  logic        we;
input  logic [7:0]  wdata;
// Response
output logic [7:0]  rdata;
output logic        ack;      // rdata valid; a 1-cycle backend ties this high
output logic        stall;    // drives the CPU's RDY
```

Backends:

| Backend | Use |
| --- | --- |
| `mem_bram` | simulation and small maps; what `ram_async` is today, minus the 64 KB |
| `mem_sdram` | the BlackIce MX part, at 100 MHz with a 25 MHz CPU |
| `mem_sram` | BlackIce II and boards with asynchronous SRAM |

`sim/console.cpp` keeps a flat 64 KB array behind the same interface, so
simulation stays instant and does not have to model SDRAM at all.

## What this unblocks

Once the 64 KB array is out of the fabric, the design places, and with it:

- **T4, T5, T8** get their first real numbers, and `refactor-cpu-core` task 2.5 -
  "is the critical path inside `cpu`?" - becomes answerable for the whole chip
  rather than for a core in isolation.
- `make timing` starts working. It is already written for this
  (`refactor-cpu-core` task 2.2).
- The arbiter's write-stall workaround can be removed and DMA can assert freely
  (`refactor-cpu-core` task 6.4), because a core that survives a row-miss stall
  survives a DMA stall by the same mechanism.

## What is not decided here

- The exact part, and therefore the row/column split. Confirm against the board.
- Whether the CPU stays at 25 MHz or moves to 50 with the SDRAM at 100+. Higher
  CPU clock means fewer SDRAM clocks per CPU cycle and so more wait states; the
  trade depends on the measured row-hit rate.
- Whether a small instruction line buffer is worth it beyond the free 16-bit
  pairing. Measure before building.

## The other answer: a device with the block RAM (2026-07-25)

Everything above is about making 64 KB reachable when the fabric does not hold
it. The Tang Nano 20K target takes the other route — hold it.

| | iCE40 HX8K | Gowin GW2AR-18C |
| --- | --- | --- |
| Block RAM | 32 x 4 kbit = 128 kbit | 46 x 18 kbit = 828 kbit |
| 64 KB main memory | 4x the whole device | 32 blocks |
| What the top can pass | `RAM_ADDR_BITS(13)` — 8 KB, aliases `$FFFC` | `RAM_ADDR_BITS(16)` — the real machine |

Measured: the full console synthesises at 45 of 46 block RAMs and 50% of the
logic, with the 64 KB array intact. `make tangnano20k-synth`; numbers and the
per-consumer split are in [`boards.md`](boards.md).

**What this changes here.** Only the urgency, and only for one board:

- The *capacity* half of the problem has an answer that costs no RTL.
- The *latency* analysis above — row hits, the 16-bit free prefetch, RDY
  becoming load-bearing, the zero-page/stack split staying on-chip — is
  untouched and still the design for any external memory, on either board.
- Gate T4/T5/T8 ("the design cannot be placed") were hx8k facts. A device this
  design fits on can answer them, once place-and-route has actually been run on
  it — which, as of writing, it has not been. See the verification section of
  [`boards.md`](boards.md).

**What it does not change.** The BlackIce MX still cannot run a game without
this work, and its 16 Mbit SDRAM is still the cheapest 2 MB in the project. The
GW2AR's own 64 Mbit of in-package SDRAM is unused by the Tang Nano target for
exactly the reason above: at 64 KB there is nothing to spend it on yet.
