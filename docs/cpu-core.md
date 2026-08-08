# The 6502 core and its conformance net

Working notes for `openspec/changes/refactor-cpu-core`. Phases 1 and 3 are done:
the golden-suite harness exists and was validated against the *existing* Arlet
core before the new core was written, and the new core now passes the full
sweep. Phase 2 (the Fmax baseline) and phase 4 (pipelining) are not.

## Why a net first

`make test` checked that `AB == $0300` after reset, printed some trace lines,
and exited 0 whether it passed or failed. Everything else about the CPU was
unmeasured. That is why the previous plan here was a cautious in-place retrofit:
there was no way to tell a correct change from an incorrect one.

`tools/65x02/` replaces that with 1.51 M per-opcode cases from
[SingleStepTests/65x02](https://github.com/SingleStepTests/65x02), pinned at
commit `2f6980a2`. The full sweep runs in 17 s against the old core and
3.5 s against the new one.

```
make test-65x02                 # fast subset, CASES per opcode (default 100)
make test-65x02 CASES=0         # the full 1.51 M sweep
make test-65x02 OPCODE=91       # one opcode
make test-65x02 TIER3=1         # report cycle activity as well
make test-65x02 SST_CORE=v2     # run it against the new core
make cpu-timing                 # rewrite docs/cpu-timing-<core>.json
make check-decode               # decode table vs the opcode registry
make cpu-static-cpi             # static mean CPI over a corpus
```

The suite is 1,082 MB of JSON and is never vendored. `make` clones it sparsely
at the pinned commit into `~/.cache/65x02`, then packs it once into a 162 MB
binary fixture (`tools/65x02/pack.py`) that the harness mmaps. Both live outside
the tree. Packing takes 22 s and is entirely dominated by JSON parsing, which is
the whole reason the fixture exists.

## What gates and what does not

| Tier | What is compared | Status |
| --- | --- | --- |
| 1 | `initial` → `final`: `PC`, `S`, `A`, `X`, `Y`, masked `P`, every address in `final.ram` | **Gate.** Timing-free. |
| 2 | No address accessed that the case does not list in either `ram` list | **Gate.** Timing-free. |
| 3 | The `cycles` array, in order | **Record only.** Never affects the exit code. |

Tier 2 is the one that matters most on this console. `$4000-$41FF`,
`$E000-$EA00` and `$F000-$F800` are memory-mapped peripherals, so a stray read
is a peripheral event rather than a wasted cycle, and the suite's own rule -
*"any memory address not included in a test's `ram` lists must not be accessed"* -
gives us that check for free.

Tier 3 is deliberately **not** a target. The new core is expected to use *fewer*
cycles than NMOS and fewer internal states; matching the NMOS cycle array is not
a goal and a divergence there is not a defect. The tier exists because when
Tier 1 fails, the cycle array usually says why at a glance.

## Accepted divergences

Only documented behaviour is contractual. Every suppression is **counted and
printed on every run**, so an exclusion that starts absorbing real failures
shows up as a rising number instead of as silence.

| Rule | Reason |
| --- | --- |
| `P` bits 4-5 | No architectural meaning outside a pushed `P`, and a pushed `P` is compared as a RAM byte anyway |
| `N`, `V` after `ADC`/`SBC` with `D=1` | Undocumented on NMOS. The corpus consumes only `C` and the result bytes from its BCD chains |
| `JMP ($xxFF)` | NMOS fetches the high byte from `$xx00` instead of crossing the page. A documented NMOS bug we do not implement - so the case is checked **against the crossed-page result**, not skipped |

The third is worth the distinction: the case still runs and still asserts an
exact PC and an exact access footprint, just against the corrected expectation.
Nothing is waved through.

The 105 undefined opcodes are skipped by default and the harness reports that it
skipped them. `tools/65x02/opcodes.txt` is the documented-151 registry until
`docs/opcodes.md` lands, at which point it becomes derived from it.

## How a case is driven

Two problems have to be solved to run one instruction in isolation.

**Setting up `PC`/`S`/`A`/`X`/`Y`/`P`.** A 6502 has no bus-level way to load
these. Rather than reach into the core - which would only work on a core built
to allow it, and does not work on Arlet at all - the harness assembles a
16-byte preamble into a scratch window of the case's own memory:

```
LDX #s / TXS / LDA #p / PHA / LDA #a / LDX #x / LDY #y / PLP / JMP pc
```

`PLP` is last, so nothing after it disturbs a flag; `PHA`/`PLP` net the stack
pointer back to `s`; `JMP` is flag-neutral. The window is placed to avoid every
address the case names, and outside page 1 so the reset sequence's stack traffic
cannot land on it. The case's initial RAM is re-applied at the instant the case
starts, which undoes the byte `PHA` pushed through and the reset vector the
harness borrowed. Cost: ~25 cycles per case, which at 90 k cases/s is invisible.

The payoff is that the harness works on **any** 6502 core, with or without a
forcing interface. The new core does expose `PC`/`S`/`A`/`X`/`Y`/`P` as a documented test
interface, but the harness does not depend on it - it only reads state out, and
sets it the same way on both cores.

**Knowing when the instruction ended.** `rtl/cpu6502_sst.sv` exposes `o_decode`,
high during the cycle in which a fetched opcode is decoded. The *second* such
cycle after a case starts belongs to the next instruction, so that is where the
instruction retires. Its bus activity is not recorded.

Where the state is *sampled* differs between the two cores, and the shim says
which through `o_late_writeback` rather than the harness special-casing them:
Arlet retires the previous instruction's register and flag writes at the END of
the decode cycle, so that edge is clocked before sampling; the new core has
everything final before the decode cycle begins, and must be sampled before it -
its implied instructions execute entirely within that cycle.

`o_pc` is defined as *the address the opcode being decoded was fetched from*,
valid only while `o_decode` is high. Stating it that way rather than "the PC
register" is what makes `PHA`/`PHP`/`PLA`/`PLP` come out right: those hold a
prefetched opcode in `IRHOLD` without advancing `PC` further.

### The memory model is registered, and it matters

`rtl/ram_async.sv` has a **registered** read port: `DI` during cycle *N* is the
byte addressed in cycle *N-1*. This is not a detail to gloss over. Arlet's
`AB = {DIMUX, ADD}` forms the address from `DI` in the same cycle, so feeding
`DI` combinationally from the current address closes a loop that does not exist
in the hardware and desynchronises the whole core - the first version of the
harness did exactly that and every case failed. It is also, of course, precisely
the unregistered read-data → address path this change exists to remove.

## Baseline: the Arlet core, full sweep

`make test-65x02 CASES=0`, 1,510,000 cases over the 151 documented opcodes:

```
cases        : 1510000 run, 1509471 passed, 529 failed
failing      : 1 opcode
  00 BRK imp     529
```

**Everything passes except `BRK`.** 150 of 151 opcodes are clean on Tiers 1 and
2 over 10,000 cases each. The indirect-addressing regression fixed in `1c6f5e3`
would not survive a hundred cases of `91.json`; it is now permanently pinned.

`BRK` is listed in `SST_KNOWN`, so the target reports it on every run but exits
0 on it. The alternative - a gate that is red no matter what you do - is a gate
people stop reading, and it would hide the next real failure. `SST_KNOWN` is
empty for `SST_CORE=v2`, and the new core is expected to keep it empty:

```
failing      : 0 cases new, 529 known
  00 BRK imp     (known, see docs/cpu-core.md)   529
PASS
```

### The `BRK` defect

`cpu6502_arlet.sv:1095-1102` re-evaluates `adc_sbc` at `state == DECODE ||
state == BRK0`. During `BRK0` the instruction register still shows whatever byte
followed the `BRK` opcode - the signature byte, which is data. When that byte
happens to match `8'bx11x_xx01`, `adc_sbc` latches high and survives to the next
`DECODE`, where `C <= CO` and `V <= AV` overwrite the flags `BRK` was supposed to
preserve. `adc_bcd <= D` has the same window and corrupts `S` through the BCD
adjust in four of the cases seen.

Measured, not inferred:

- 631 of the 10,000 `BRK` cases have a signature byte matching `x11x_xx01`.
- 529 fail.
- **Every failing case is in that set; no failure is outside it.** The other 102
  pass because the ALU's carry and overflow happen to equal the flags coming in.

The console never executes `BRK` today (`brk`, `sei` and `cli` appear zero times
across `src/*.asm`), so this is latent rather than live. It is recorded here
because the Arlet files are deleted at the end of this change and this is the
kind of thing that would otherwise be rediscovered from scratch.

### `JMP ($xxFF)`

Exactly 49 of the 10,000 `6C` cases have a pointer low byte of `$FF`, and Arlet
crosses the page on all 49 where NMOS wraps within it. That is the behaviour we
want; it is in the accepted-divergence table above and the new core should do the
same.

### Cycle activity

`docs/cpu-timing-arlet.json` holds the per-opcode cycle table, measured
decode-to-decode over the full sweep. **Arlet's cycle counts are identical to
NMOS on all 151 documented opcodes** - mean 4.010 - so the baseline the new core
is measured against is simply the NMOS table.

Fifty opcodes nonetheless differ in *which* accesses they make within those
cycles, in three families:

| Family | NMOS | Arlet |
| --- | --- | --- |
| RMW (`ASL`/`ROL`/`LSR`/`ROR`/`INC`/`DEC`) | read, **dummy write of the old value**, write | read, **dummy read**, write |
| Zero-page indexed, `(zp,X)`, `(zp),Y` | dummy read at the *un-indexed* zero-page address | no such read; an extra prefetch at `PC+2` instead |
| Push/pull, `JSR`, `RTS` | a dummy stack access | no such access; an extra prefetch at `PC+2` instead |

Two of those three are improvements for this console: Arlet never performs
NMOS's spurious write during a read-modify-write, and never performs its
spurious zero-page read. What it does instead is fetch one byte further ahead
in the instruction stream, which is program RAM and harmless. Tier 2 passes on
all of it.

The new core is free to drop more: fewer cycles per opcode is a win, not a
regression, and the same is true of internal states. The table is a record of
what a core does, never a shape it has to reproduce.

## The new core

`rtl/cpu6502_core.sv` plus `rtl/cpu6502_decode.sv`. Selected with
`make test-65x02 SST_CORE=v2`; nothing in `rtl/top.sv` reaches it yet.

```
cases        : 1510000 run, 1510000 passed, 0 failed
opcodes      : 151 run, 105 skipped (of 256)
PASS
```

**All 1.51 M cases pass Tiers 1 and 2**, including the 529 `BRK` cases the
previous core failed. The full sweep takes 3.5 s.

### Shape

The decode is one file, one row per opcode:

```
8'h15: d = row(AM_ZPX,  OP_ORA,  R_A,    D_A);      // ORA zp,X
8'h16: d = row(AM_ZPX,  OP_ASL,  R_NONE, D_MEM);    // ASL zp,X
```

Four fields - addressing mode, operation, register operand, destination - and
the flag-write set derived from the operation by `fwset`, because it is a
property of the operation and writing it 151 times is 151 chances to write it
wrong. `make check-decode` fails if the table and the opcode registry disagree
about any opcode's presence, mnemonic or mode; `make test-65x02` runs it first.

Adding an instruction is adding a row. Nothing outside `cpu6502_decode.sv`
pattern-matches on instruction bits except the branch condition, which is three
opcode bits by construction. The 105 unclaimed slots decode to `AM_TRAP`: the
core stops and names the opcode and the PC on `dbg_trap_ir` / `dbg_trap_pc`
rather than executing undocumented behaviour.

The sequencer has a state per *addressing-mode step*, not per T-state, and the
effective-address access is issued from one shared block - so a new addressing
mode produces an `ea` and inherits load, store and read-modify-write for free.

### The address is combinational, deliberately

`ram_async.sv` answers the address presented in cycle N on DI in cycle N+1. A
core that registers its address therefore pays a *second* cycle on every
data-dependent address - compute, present, receive - and can only get it back by
overlapping instructions, which is phase 4 of this change. Measured on the
sequences here that would have cost roughly 2x the cycles (`LDA zp` 5 instead of
3, `LDA (zp),Y` 9 instead of 5).

So this core keeps one access per cycle and attacks the critical path by making
the DI -> AB route *narrow* instead: at most an 8-bit adder and a small mux,
against the 12-arm `AB` mux plus `DIMUX` plus arbiter mux a byte used to travel
through. Every address that does not depend on DI comes straight from a
register. Whether that is enough is a question for the phase 2 measurement,
which has not been run; registering the address stays available if it is not.

### Cycles

There are no dummy cycles at all: no read-modify-write dummy write, no
un-indexed zero-page read, no page-cross penalty, no dummy stack access.

| | NMOS | here |
| --- | --- | --- |
| implied (`INX`, `CLC`, `TAX`, `NOP`) | 2 | **1** |
| `PLA` / `PLP` | 4 | **2** |
| `PHA` / `PHP` | 3 | **2** |
| branch, taken / not taken | 3 (4 across a page) / 2 | **2 / 2** |
| `RTS` | 6 | **3** |
| `RTI` | 6 | **4** |
| `JSR` | 6 | **5** |
| `INC zp` | 5 | **4** |
| `LDA abs,X` | 4, 5 across a page | **4** |
| `LDA zp` / `LDA abs` / `LDA (zp),Y` | 3 / 4 / 5 | 3 / 4 / 5 |

Over the 151 documented opcodes: **mean CPI 3.278 against NMOS's 4.010, 18.2%
fewer cycles, 108 opcodes faster, 43 equal and none slower.** Weighted by the
instructions Breakout actually contains (1,928 of them, `make cpu-static-cpi`),
static mean CPI is **2.6234 against the old core's 3.0334** - comfortably inside
the 3.08 the ISA slices were budgeted against, with 13.5% of headroom to spare
before any Fmax gain is counted.

`docs/cpu-timing-v2.json` records it per opcode. It is a record, not a target:
the tiers that gate are timing-free, and an ISA slice that makes an instruction
shorter is not breaking anything.

### Phase 4: registering the decode

Phase 2 measured that the new core's critical path started at the memory read
data and ran through the combinational decode into the ALU. Phase 4 split the
decode in two:

- `dec_c` — combinational, used **only** in `S_DECODE`, and only to pick the
  next state and the register a push reads. `DI -> table -> state mux`.
- `dec_r` — the same row, registered. Everything reaching the ALU, the flags or
  a store reads this, so those paths start at a flop.

The price is that an implied instruction can no longer execute in the cycle its
opcode arrives: it gets `S_IMP` and costs 2 cycles instead of 1, the same as
NMOS. That is 13.2% of the corpus and 0.13 of static CPI.

**Fmax 37.94 → 50.18 MHz, +32%** (mean of three placement seeds). The remaining
path is `memory -> decode table -> next state`; going further would mean
deriving the addressing mode from opcode bits rather than the table, which is
the extensibility this core exists to have. Not worth 8% against a board that
runs at 25 MHz.

### The stall found a real defect

Gate T7 is `make test-65x02 STALL=N`: drop `RDY` for 1..3 cycles at a
pseudo-random rate across the whole sweep, and require every case to come out
identical. `WE` asserted while `RDY` is low is itself a failure.

The first run failed **22,537 of 30,200 cases**. The RAM's read port keeps
clocking while the CPU is held, so the byte answering the pending request is on
`DI` for exactly one cycle and is then overwritten by the answer to the address
the stalled core is still presenting. `RDY` silently corrupted the instruction
in flight.

`di_hold`/`di_held` latch `DI` on the first stalled cycle, when it is still
valid, and serve it for the rest of the stall and the cycle that resumes. This
is what Arlet's `DIHOLD`/`DIMUX` is for; the shape of the bug is a property of a
registered-read memory, not of either core.

**1,510,000 / 1,510,000 pass with 5,470,098 stall cycles injected.** A directed
testbench over 50 states would not have covered as much, and would have been
unlikely to find this at all.

This matters more than it looks: `add-memory-subsystem` makes stalls routine
(row misses and refresh), so T7 stops being a formality. It also retires the
arbiter's workaround at `memory_arbiter.sv:76-85`, which exists precisely
because the old core cannot be stalled mid-write.

### Where the two cores stand

| | old core | new core |
| --- | --- | --- |
| Fmax, mean of 3 seeds | 53.01 MHz | 50.18 MHz |
| logic cells | 818 | 1378 |
| static mean CPI (Breakout) | 3.0334 | 2.7552 |
| instructions/s at own Fmax | 17.48 M | **18.21 M** (+4.2%) |
| instructions/s at the board's 25 MHz | 8.24 M | **9.07 M** (+10.1%) |
| 65x02 full sweep | 1,509,471 / 1.51 M | **1,510,000 / 1.51 M** |
| under injected stalls | not attempted | **1,510,000 / 1.51 M** |

Area is the remaining regression, +68%. The decode table is 256 x 22 bits =
5,632 bits, so inferring it as a BRAM ROM would return most of it — at the cost
of a cycle, because a BRAM read is registered. Worth doing only if T8 binds.

### The console runs on it

`rtl/cpu6502_wrapper.sv` instantiates `cpu6502_core`. `cpu6502_arlet.sv` and
`cpu6502_alu.sv` are gone, along with `cpu6502_defs.sv`, `cpu_reset_tb.sv`,
`debug_test.sv` and the two `run_test*.sh` scripts that drove them. They are at
commit `ae37bbc` if ever wanted.

| Gate | State |
| --- | --- |
| T1 documented-subset conformance | **met** — 1,510,000 / 1,510,000 |
| T2 the console still works | **met** — Dormann to `$3469`, Breakout renders |
| T3 interrupts proven | **met** — `make test-irq`, 10 directed cases |
| T4 critical path relocated | blocked — the design does not place |
| T5 Fmax | blocked — same |
| T6 wall-clock non-regression | **met** — +10.1% at the board clock |
| T7 stall correctness | **met** — 5,470,098 stall cycles injected |
| T8 area | **answered** — the CPU is 9% of the design |

**Dormann's `6502_functional_test`** trapped at `$3469`, the success address,
after 30,646,179 instructions. That is ~30 M instructions of self-checking
coverage of every documented behaviour, decimal mode included, and unlike a
screenshot it does not care how fast the core is. `make test-functional`.

**Breakout renders identically except for the dust.** 30 of 19,200 pixels differ
from the old core, and they are the drifting dust particles:
`src/main.asm:153` says *"seed the dust from the hardware LFSR"* and reads
`SPR_RND`, which free-runs. Any core with different timing reads it at a
different point and seeds the dust differently — permanently, which is why the
same 30 pixels differ at frames 18, 19, 20, 21 and 22 rather than drifting. All
30 are 2x2 blocks in exactly two colours. Nothing else on screen moves.

### Three pre-existing defects the swap uncovered

None were caused by the new core; all were found because something finally
exercised these paths.

1. **`rtl/test_ram.hex` never described its own contents.** It laid out a memory
   map in comments — "Address 0x0300-0x030F: Program code", "repeated lines of
   zeros omitted" — while `$readmemh` loads sequentially. The program claimed to
   be at `$0300` loaded at `$0030`, and the reset vector never reached `$FFFC`.
   Rewritten with `@` directives.
2. **`cpu6502_tb.sv` could not fail, three ways over.** It wired `rw` inverted
   against `chip.sv`, so the RAM never drove a read and the bus stayed X; it
   compared with `!=` rather than `!==`, and `X != 16'h0300` is X, which `if`
   treats as false — so an all-X bus printed `TEST PASSED`; and it asserted
   where the PC was at a fixed cycle count, which measures speed, not
   correctness. It now latches whether `$0300` was ever fetched and whether the
   program reached its loop.
3. **`ram_async.sv` declared its parameters after the ports that use them.**
   Legal to Verilator and yosys, unbindable by iverilog. `make test` elaborates
   and passes for the first time in this repo's history.

### Optimisation pass, measured step by step

`tools/cpu_measure.sh` — yosys plus six placement seeds plus a per-function LUT
attribution. Placement varies by 2-3 MHz between seeds, so a single number
proves nothing and both arms of every comparison were run in one session.

| | Fmax (6 seeds) | ICESTORM_LC | LUT4 |
| --- | --- | --- | --- |
| baseline | 45.37 MHz | 1360 | 1241 |
| 1. `PC = ab_c + 1` | 47.69 | 1318 | 1194 |
| 2. one adder for ADC/SBC/CMP | 48.82 | 1295 | 1188 |
| ~~3. entry state as a `dec_t` field~~ | ~~46.86~~ | ~~1287~~ | ~~1173~~ |
| 3b. entry state as its own output | 48.60 | **1232** | **1125** |
| | **+7.1%** | **−9.4%** | **−9.3%** |

Three things worth keeping from how it went.

**Counting LUTs would have missed step 2.** Six LUT4 moved, and Fmax rose 3.5%.
Two 9-bit carry chains cost almost nothing in `SB_LUT4` on this device because
they use the dedicated carry logic — but removing them still bought timing.

**Step 3 failed the first time, informatively.** Putting the entry state in
`dec_t` did move the critical path off the decode, exactly as intended, and cost
4% of Fmax anyway: `dec_t` is registered into `dec_r`, and six more flops of
registered fanout are not free. Emitting it as a separate output keeps the
shallow path without the storage.

**The evidence that behaviour did not change is not the screenshot.** Dormann
trapped at `$3469` after *exactly* 30,646,179 instructions and 76,948,720 cycles
before and after all three steps. Cycle-identical over 77 M cycles says more than
any frame comparison can.

The core is now near a floor: the critical path is
`memory data -> 8-bit carry chain -> flag register`, and **12.9 ns of the ~21 ns
is routing, not logic**. Trimming gates will not move it; restructuring the adder
might.

### What is not done yet

- **Interrupts.** Done — see below.
- **Stalling.** Done and proven — see above.

### Interrupts

`IRQ` and `NMI` both vector. The entry is tested at an instruction boundary
only: `S_DECODE` is the single place `int_take` is read, so every
addressing-mode sequence has either not started or already retired. The entry
discards the opcode `S_DECODE` fetched and returns to it, and reuses
`S_BRK0..S_BRK4` — the three places a hardware entry differs from `BRK` are the
pushed `PCL`, the `B` bit of the pushed `P`, and the vector.

**65x02 is not evidence here.** It runs every case with both lines low.
`make test-irq` (`rtl/cpu6502_irq_tb.sv`) is the only evidence for this path,
and it is verified to be able to fail: setting `B` in the hardware push trips
six of its checks and exits nonzero. Ten cases: entry with `I` clear, deferral
while `I` is set, `NMI` through `$FFFA` with `I` set, `NMI` edge-triggering,
`NMI`-over-`IRQ` priority, the `BRK`-versus-hardware `B` distinction, register
preservation, entry across an `RDY` stall, and both `WAI` idioms.

Three things depart from NMOS, all deliberate:

- **`IRQ` is pulse-latched, not level-sensitive.** The console's only source is
  the one-clock vsync pulse in `rtl/chip.sv`, and the latch sits outside the
  `RDY` gate so a pulse that lands during a DMA stall is not lost. A level
  source still works — a held line re-arms the latch every cycle. What does not
  carry over is the NMOS habit of dropping the line inside the handler to
  withdraw a request: once latched, the request is taken.
- **`WAI` with `I` set retires the pending `IRQ`.** The `SEI`+`WAI` idiom uses
  the interrupt as a frame tick and wants no vector, so the sleep is the
  service. Without this a later `CLI` would vector immediately, on a frame that
  had already been waited for. With `I` clear, `WAI` wakes and the vector is
  taken at the very next cycle, which is the 65C02's behaviour.
- **`dbg_sync` excludes an entry cycle.** An entry occupies an `S_DECODE` cycle
  but does not decode the byte it fetched, so counting it as a retire would
  make `dbg_pc` name an instruction that never ran.

**An entry saves PC and P and nothing else**, as the 6502's does, so both
halves of the 16-bit accumulator are the handler's to preserve. `A` goes
through `PHA`/`PLA`; `B` is reached with **`XBA`** (`$EB`, `add-isa-xba`),
which exchanges the halves and sets N and Z from the new `A`:

```
    pha / xba / pha        ; at entry
    pla / xba / pla        ; before rti
```

`$EB` is the 65C816's own `XBA` encoding, adopted with its meaning — the same
kind of claim as `WAI` at `$CB`, one that preserves a WDC encoding instead of
burning it. A `PHB`/`PLB` pair would have cost two encodings *and* taken two
mnemonics that mean the data bank register on a real '816.

Nothing in the repo needs any of this yet: both corpora keep `I` set from reset
and use `wai` as a frame tick, so neither takes a vector at all. Their
`$FFFA`/`$FFFE` entries point at their reset paths, which is only harmless for
as long as that stays true.

Cost, on `make synth-cpu` over 5 nextpnr seeds: **1786 → 1862 logic cells**,
Fmax median 41.21 → 41.60 MHz against a 4 MHz seed spread, with the critical
path inside the RAM in both trees. `NMI` has no source on this chip —
`chip.sv` ties it low, so synthesis trims that half in the console build.

## Phase 2: what the FPGA flow actually says

### The design does not place, and the CPU is not why

`make bin/toplevel.json` has never completed. It is not slow - yosys emits
**1,727,271 AND gates and 4,954,853 wires** and then sits in ABC9 indefinitely.

The cause is `rtl/ram_async.sv`, which models the console's 64 KB main memory as
an on-chip array. An hx8k has 32 x 4 kbit BRAM, **16 KB in total**, and the rest
of the design (PSG audio RAM, wavetable, reverb buffer, PPU overlay and map,
text buffer, font) already wants most of that. Roughly 640 kbit asked for
against 128 kbit available. Yosys cannot map it, falls back to logic, and the
netlist explodes.

That memory was never meant to be on-chip: the BlackIce MX carries a 16 Mbit,
16-bit-wide SDRAM rated at 143 MHz. What is missing is the abstraction - a
memory interface the CPU and the arbiter talk to, with the board's SDRAM behind
the 64 KB map. `rtl/top.pcf` has no memory pins at all, so nothing has ever been
wired to a real chip. Written up in
[`docs/memory-subsystem.md`](memory-subsystem.md), including why the CPU need
not slow down for it: at 100 MHz against a 40 ns CPU cycle a row-hit read fits
inside one CPU cycle, so main memory keeps looking the way this core already
assumes.

Until that exists:

- **T4 (critical path relocated), T5 (Fmax) and T8 (area) cannot be measured**,
  and tasks 2.1, 2.5 and the whole-chip half of 2.3 are blocked.
- The blocker is a memory-subsystem problem, not a CPU one. Nothing about the
  CPU rebuild makes it better or worse.

### Core-only Fmax, and it is not the answer that was expected

`rtl/cpu_fmax_top.sv` puts one core against a 2 KB synchronous-read RAM with
`ram_async`'s timing and no arbiter, so a difference between runs is a
difference between cores. `make cpu-fmax SST_CORE=arlet|v2`:

| | old core | new core |
| --- | --- | --- |
| Fmax (hx8k, `--freq 50`) | **50.97 MHz** | **37.94 MHz** |
| Logic cells | 818 | 1323 (+62%) |
| static mean CPI (Breakout) | 3.0334 | 2.6234 |
| 65x02, full sweep | 1,509,471 / 1,510,000 | **1,510,000 / 1,510,000** |

**The new core is 26% slower in Fmax and 62% larger.** That is the opposite of
what the combinational-address decision was betting on, and the placement says
exactly why.

The new core's critical path **starts at the BRAM read data**:

```
RDATA -> di -> combinational decode (ir) -> flag/ALU select
      -> store data -> carry chain -> C flag          14.12 ns logic
```

The old core's does not. Its decode signals are *flops*, loaded at DECODE, so
its path starts at a register:

```
V -> store -> write_back -> inc -> index_y -> dst_reg
  -> regfile -> ALU half-carry -> PC                  11.75 ns logic
```

So the thing that costs is not the address mux the design notes worried about -
it is that the new core decodes *and executes* in the same cycle as the fetched
byte arrives. That is precisely what buys implied instructions their 1 cycle,
and it is being paid for in Fmax. The narrow-address-mux argument was right
about the address and wrong about what would bind.

### Which core is faster today

The board runs the raw 25 MHz pin: `rtl/pll.v` is generated for 50 MHz and
`rtl/top.sv` never instantiates it. So `TARGET_FREQ = 50` is **aspirational, not
a constraint the hardware meets** (task 2.4).

At 25 MHz both cores close timing, and the new core's 15.6% lower CPI is a
straight 15.6% more instructions per second. At each core's *own* Fmax the
ranking inverts: 16.8 vs 14.5 M instructions/s, a 14% win for the old core. So
the answer depends entirely on whether 50 MHz is ever pursued, and today it is
not.

### What this says about phase 4

Registering the decode - phase 4's task 4.2 - is now measured, not assumed: it
is the single change that moves the critical path off the memory output. It
costs a cycle on implied instructions, which prefetching can win back, and it
has a second payoff: a 256-row table of 22 bits is 5,632 bits, which fits in two
BRAMs. Inferring it as a ROM would register it *and* return most of the 505
extra logic cells.

### Other clock consumers (task 2.6)

The PSG derives its rate from `CLK_HZ` and `uart_tx` from `MAIN_CLK`; both are
clock-portable and gain nothing. The LCD serialiser runs at the system clock, so
a faster clock is a shorter frame push - it is the only part that benefits, and
the compositor's per-line budget scales with it.

### PSG register reads (task 2.7)

No side effects: the CPU-interface block in `rtl/psg.sv` only assigns `dout`, and
no read alters sequencer or channel state. The corpus's single indexed MMIO site,
`sta PSG_CH,y` at `src/main.asm:2479`, is therefore safe against a spurious read
- which also means Tier 2 divergence at that address would be harmless.

## `make test`

`rtl/cpu6502_tb.sv` now calls `$fatal` on a failed check instead of printing
`TEST FAILED` and exiting 0, so the check is a check (task 1.1).

The target still does not elaborate under iverilog, for two reasons that predate
this change: `ram_async.sv` declares its parameters after the port list that
uses them, and `cpu6502_arlet.sv` has ~14 enum assignments iverilog wants
explicit casts for. Verilator accepts both. Neither is fixed here - the Arlet
files are deleted at the end of this change, and `make test-65x02` is a far
stronger net than a single reset-vector check. Recorded rather than silently
left.
