## Why

**Classical pipelining would buy almost nothing, because the core is already at
the bus limit.** Measured over Breakout's 1,928 instructions:

| | per instruction |
| --- | --- |
| instruction bytes fetched | 2.020 |
| data accesses | 0.604 |
| **bus accesses — the one-port floor** | **2.623** |
| **CPI today** | **2.755** |

The core sits **0.132 CPI above the floor**, and all of it is one thing: implied
and accumulator instructions take 2 cycles instead of 1 (13.2% of the corpus),
because `refactor-cpu-core` phase 4 moved their execution a cycle later to get
the ALU off the memory output. Overlapping decode and execute across
instructions — the usual meaning of "pipeline it" — can recover that 4.8% and
nothing more, because every remaining cycle is a byte crossing a bus that
carries one byte per cycle.

**The bottleneck is bandwidth.** With that removed:

| Scheme | CPI | vs today |
| --- | --- | --- |
| one 8-bit port (today) | 2.755 | — |
| 16-bit fetch, `ceil(bytes/2) + data` | 1.789 | −35% |
| separate instruction port, `1 + data` | 1.604 | −42% |
| separate instruction port, fully overlapped | 1.102 | −60% |

Instruction fetch is **77% of all bus traffic** (2.020 of 2.623). Taking it off
the data path is the whole game.

## What Changes

- **An instruction prefetch queue**, four bytes deep, filled autonomously from a
  fetch path that does not compete with data accesses. Decode takes its opcode
  and operand bytes from the queue.
- **The fetch path is a backend choice**, behind the interface
  `add-memory-subsystem` introduces:
  - Tang Nano 20K: a genuine second port on the dual-port block RAM holding the
    64 KB map. Fetch becomes free.
  - BlackIce MX: the 16-bit SDRAM word already returns two bytes per access, so
    the queue fills at half the cycle cost even on one port.
- **A pipeline that is worth having once fetch is free**: decode and address
  formation in one stage, the data access in the next, writeback merged into
  decode of the following instruction.
- **The queue is flushed on every control transfer.** Control transfers are
  19.2% of the corpus (branches 10.8%), so the flush penalty is the design's
  main cost — see below.
- **The prefetcher must respect the address decode.** It reads ahead
  speculatively, and `$4000-$41FF`, `$E000-$EA00` and `$F000-$F800` are
  peripherals. Prefetch is confined to RAM; near a window boundary it stops
  rather than reads.

## Impact

Expected CPI, taking the realistic middle case — separate instruction port, a
one-cycle flush penalty, no data/issue overlap:

```
  1.604  +  0.138 (flush)  =  1.742      against 2.755 today
                               -37% cycles, +58% instructions per second
```

**And it should help Fmax, not hurt it.** The critical path today starts at the
memory read data and runs through the decode. With a queue, the opcode reaches
the decoder from a *flop*, so that path stops existing. This is the rare change
that buys IPC and timing together.

Costs and risks:

- **Flush penalty dominates the outcome.** At one cycle it is +0.138 CPI; at
  three it is +0.415 and eats a third of the win. The target address has to be
  issued in the cycle the transfer resolves.
- **Self-modifying code becomes visible.** A write to an address already in the
  queue would execute stale bytes. Snoop the queue against data writes and flush
  on a hit — four comparators — rather than declaring it unsupported.
- **Tier 2 conformance changes meaning.** The access footprint will contain
  prefetch reads past the end of each instruction, which the 65x02 suite does
  not list. The gate has to distinguish them, not be relaxed. See the spec.
- **Depends on `add-memory-subsystem`** for the interface, and on whichever
  backend provides the second port.
