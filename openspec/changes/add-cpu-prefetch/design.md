## Context

`refactor-cpu-core` produced a core at 2.755 static CPI that is within 5% of
what a single-byte-per-cycle bus allows. This change is about the bus, not the
core: instruction fetch is 77% of bus traffic, and moving it off the data path
is worth ~37% of cycles.

## Goals / Non-Goals

**Goals**

- Decouple instruction fetch from data access.
- Keep the decode table as the only place an ISA slice edits.
- Keep every existing gate: 1.51 M conformance cases, stall injection, Dormann.

**Non-Goals**

- Branch prediction. At 10.8% branches and a one-cycle penalty the whole
  mispredict budget is 0.138 CPI; a predictor cannot return more than that and
  costs area on a device that has none spare.
- Superscalar issue, out-of-order, register renaming. Wrong machine.
- Speculative execution past a control transfer. The queue is flushed; nothing
  executes from the wrong path.
- Caching. The 64 KB map either fits in fabric (Tang Nano) or sits behind
  SDRAM with an open-row policy (BlackIce). Neither wants a cache first.

## Decisions

### Decision: a queue, not a wider single port

A 16-bit port helps (1.789 CPI) but a second port helps much more (1.604, or
1.102 with overlap) and is free on a device with dual-port block RAM. The queue
is the part that makes either work, so it is built once and the port is a
backend detail.

### Decision: four bytes deep

The longest instruction is three bytes. Four means decode never waits on the
queue for a complete instruction while a fifth byte is being fetched. Deeper
costs flush latency and comparators for the store snoop, and buys nothing: the
fill rate, not the depth, sets the refill time after a flush.

### Decision: the prefetcher is address-decode aware

This is not an optimisation, it is a correctness requirement. Prefetching is
speculative reading, and three address windows on this machine are peripherals.
The prefetcher stops at a window boundary instead of reading across it. That
also keeps the Tier 2 property the console actually cares about: the CPU never
touches a peripheral it was not told to.

### Decision: snoop stores against the queue

A write whose address is in the queue invalidates it. Four comparators against
the queue's tags. The alternative — declaring self-modifying code unsupported —
is cheaper in gates and worse in every other way: it fails silently, at a
distance, on a machine where writing code to RAM is normal practice.

### Decision: Tier 2 gains a category rather than a relaxation

The conformance harness currently fails any access to an address the case does
not list. A prefetching core reads past the end of every instruction, so that
rule would fail everywhere. The gate is split:

- accesses the instruction actually made — checked exactly as now;
- prefetch reads — permitted only within `[final.pc, final.pc + depth)` and only
  in RAM, counted and reported on every run.

A prefetch read anywhere else is still a failure. This keeps the property worth
having instead of turning the tier off.

### Decision: the writeback of an implied instruction merges into the next decode

The 0.132 CPI that implied instructions cost today comes back for free here:
with the opcode arriving from a flop, decode no longer sits behind the memory
output, so executing in the decode cycle is affordable again. The hazard
analysed in `refactor-cpu-core` phase 4 — a stack instruction reading `S` or `A`
in the same cycle an implied instruction writes it — still applies and needs
either forwarding or a one-cycle interlock. Measure which is cheaper.

## Risks / Trade-offs

- **The flush penalty decides whether this is worth doing.** One cycle:
  +0.138 CPI, net −37%. Three cycles: +0.415, net −25%. The target address must
  be issued in the cycle the transfer resolves, which puts the branch adder on
  the fetch path — the same place the current critical path already ends.
- **It depends on a change that has not started.** `add-memory-subsystem` owns
  the interface and the backends. Building the queue against today's single port
  would demonstrate the mechanism and none of the benefit.
- **Two backends, two behaviours.** Fetch is free on the Tang Nano and
  half-price on the BlackIce, so CPI differs by board. The cycle table stops
  being one number, and `docs/cpu-timing-*.json` has to say which backend it was
  measured on.
- **The verification net does not yet cover a prefetching core.** The 65x02
  suite is per-instruction; a queue spans instructions. Dormann and the stall
  injection do cover it, and the store snoop needs a directed test of its own.
