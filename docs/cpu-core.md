# The 6502 core and its conformance net

Working notes for `openspec/changes/refactor-cpu-core`. Written during phase 1,
which builds the golden-suite harness and runs it against the *existing* Arlet
core before any new core exists.

## Why a net first

`make test` checked that `AB == $0300` after reset, printed some trace lines,
and exited 0 whether it passed or failed. Everything else about the CPU was
unmeasured. That is why the previous plan here was a cautious in-place retrofit:
there was no way to tell a correct change from an incorrect one.

`tools/65x02/` replaces that with 1.51 M per-opcode cases from
[SingleStepTests/65x02](https://github.com/SingleStepTests/65x02), pinned at
commit `2f6980a2`. The full sweep runs in **17 seconds**.

```
make test-65x02                 # fast subset, CASES per opcode (default 100)
make test-65x02 CASES=0         # the full 1.51 M sweep
make test-65x02 OPCODE=91       # one opcode
make test-65x02 TIER3=1         # report cycle activity as well
make test-65x02 SST_CORE=v2     # run it against the new core
make cpu-timing                 # rewrite docs/cpu-timing-<core>.json
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
forcing interface. The new core will still expose `PC`/`S`/`A`/`X`/`Y`/`P` as a
documented test interface (task 3.5), but the harness will not depend on it.

**Knowing when the instruction ended.** `rtl/cpu6502_sst.sv` exposes `o_decode`,
high during the cycle in which a fetched opcode is decoded. The *second* such
cycle after a case starts belongs to the next instruction, so that is where the
instruction retires. That cycle is still clocked - its edge is where Arlet lands
the register and flag writes of the instruction under test - but its bus
activity is not recorded.

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
