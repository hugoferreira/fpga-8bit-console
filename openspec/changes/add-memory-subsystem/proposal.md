## Why

**The design has never been placed, and the CPU is not the reason.**

`rtl/chip.sv:131` instantiates the console's 64 KB main memory as an on-chip
array:

```systemverilog
ram_async #(.A(16), .D(8), .FILE("./rtl/ram.hex")) ram(...)
```

An iCE40 HX8K has 32 x 4 kbit BRAM — **16 KB in total** — and the PSG's audio
RAM, wavetable and reverb buffer, the PPU's overlay and map, the text buffer and
the font already claim most of it. Roughly 640 kbit is asked for against 128 kbit
available. yosys cannot map it, falls back to logic, emits **1,727,271 AND gates
and 4,954,853 wires**, and never finishes ABC9. That is why `synthesis.log` has
always ended mid-optimisation.

The consequence is that **no timing, area or utilisation number for this console
exists**. `refactor-cpu-core`'s gates T4 (critical path relocated), T5 (Fmax) and
T8 (area) are all blocked on it, as are its tasks 2.1 and 2.5. Every
microarchitectural decision in that change is being made without whole-chip
evidence, and will keep being made that way until this is fixed.

Nothing about the CPU makes it better or worse. What is missing is an
abstraction: there is no memory interface, no controller, and `rtl/top.pcf` has
no memory pins at all. The board's RAM has never been wired to anything.

### What the board actually has

myStorm BlackIce MX, from `folknology/IceCore`'s `Examples/blackice-mx.pcf`:
**16 Mbit SDRAM, 16 bits wide, rated 143 MHz**, on `A[0..11]`, `DQ[0..15]`,
`udqm`/`ldqm`, `we`/`cas`/`ras`/`mcs`, `cke`/`rclk`. Twelve address lines with no
separate `BA` pin is the signature of a 1M x 16 two-bank part: `A[10:0]` carry
row and column, `A11` selects the bank, 2048 rows x 256 columns. **A row is 512
bytes.** The console needs 64 KB of the available 2 MB, so capacity is a
non-issue; latency and row structure are the whole problem.

### Why the CPU does not have to slow down for it

The board clock is 25 MHz and the part is good for 143, so running the
controller faster than the CPU hides most of the latency inside one CPU cycle.
100 MHz is a clean x4 (`rtl/pll.v` exists, generated for 50, and `rtl/top.sv` has
never instantiated it). Against a 40 ns CPU cycle:

| Access | Cost | Fits one CPU cycle? |
| --- | --- | --- |
| Read, row open | CAS + CL2 ~ 3 clk = 30 ns | **yes** |
| Read, row miss | PRE + ACT + CAS + CL2 ~ 7 clk = 70 ns | no — one wait state |
| Auto-refresh | ~7 clk, once per 31.25 µs | one stall per ~780 CPU cycles, 0.13% |

On a row hit, main memory looks exactly like the BRAM the CPU sees today:
address out, data back next cycle, no stall. The core keeps its
one-access-per-cycle model.

## What Changes

- A memory interface (`req`/`we`/`wdata` → `rdata`/`ack`/`stall`) that the
  arbiter talks to, with the CPU's `RDY` driven from `stall`.
- Backends behind it: `mem_bram` (small maps and simulation), `mem_sdram` (the
  BlackIce MX part), and room for `mem_sram` (BlackIce II and similar).
- **Zero page and the stack (`$0000-$01FF`) get a pinned SDRAM row.** They are
  the hottest 0.8% of the address space — every `(zp),Y`, every push, every
  `JSR` — and a two-bank open-row policy would thrash without special treatment.
  512 bytes is **exactly one SDRAM row**, so pinning bank 0's row to
  `$0000-$01FF` and letting bank 1 rotate for code and data costs no block RAM
  at all and never needs re-activating.

  > This replaces an earlier plan to keep them in BRAM. The yosys netlist shows
  > that **the PPU takes 16 of the 32 block RAMs
  > and the PSG takes the other 16. There is no spare block RAM today.** The
  > pinned-row scheme is better anyway — it is free, and it does not compete
  > with the video and audio paths for a resource that is already exhausted.
- **The 16-bit bus becomes a free two-byte prefetch.** Every read returns a word
  for one 8-bit access; holding the other half satisfies the next sequential
  fetch with no memory traffic. On a corpus averaging 1.9 bytes per instruction
  that is close to halving fetch traffic — `refactor-cpu-core` phase 4's
  prefetch, obtained from the bus width instead of from the core.
- `rtl/top.pcf` gains the memory pins it has never had.
- `sim/console.cpp` keeps its flat 64 KB array behind the same interface, so
  simulation stays instant and never models SDRAM.

## Impact

- **Unblocks `refactor-cpu-core` T4, T5, T8 and tasks 2.1 and 2.5.** The first
  whole-chip Fmax, critical-path attribution and utilisation numbers this project
  has ever had.
- **Makes `RDY` load-bearing.** Row misses and refresh stall the CPU. That
  promotes `refactor-cpu-core` gate T7 (`cpu6502_stall_tb`) from a nicety to a
  prerequisite, and it retires the arbiter's standing workaround at
  `memory_arbiter.sv:76-85` — which exists precisely because the Arlet core
  cannot be stalled mid-write. `refactor-cpu-core` task 6.4 then falls out for
  free.
- **Risk: the part is inferred, not confirmed.** The row/column split is derived
  from the pinout and decides the row-hit strategy. Confirm against the chip on
  the board before the controller is written.
