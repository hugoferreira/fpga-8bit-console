## Context

`rtl/cpu6502_arlet.sv` is Arlet Ottens' 6502: 1240 lines, a 50-state microcoded
FSM, 17 `casex(IR)` decoders, one shared 8-bit ALU, one memory access per cycle.
It is a good core. It is also (a) unregistered at both memory boundaries, and (b)
structured so that adding an instruction means amending seventeen pattern-matching
blocks. The ISA programme adds ~40 instructions.

The previous plan in this change was to retrofit pipeline registers into it. The
argument for rebuilding instead is not that the retrofit was impossible — it is
that a per-opcode golden suite makes the rebuild *cheaper and safer* than the
retrofit, while also fixing (b), which the retrofit did not address at all.

## Goals / Non-Goals

**Goals**

- Raise the clock the whole chip can close timing at, by removing the CPU from the
  critical path.
- A decode structure where an ISA slice adds rows to a table, in one file.
- Conformance that is measured over 1.51 M cases, not asserted.
- Correct stalling at every cycle boundary, so DMA is usable.
- Interrupts that actually work, since nothing today proves they do.

**Non-Goals**

- Instructions per second for the current game. On hardware the core gets one bus
  cycle per 25 MHz clock — ~417k cycles per 60 Hz frame — and nothing shows the
  Breakout port near CPU-bound. The payoff is Fmax headroom and an extensible
  decode, in that order.
- NMOS bug-compatibility. Explicitly abandoned; see the corpus evidence in
  `proposal.md`. This core is for this console.
- Undocumented opcodes. Not implemented, not emulated, not tested. The 105
  undefined slots trap.
- Cycle-exact bus traces. Tier 3 is a diagnostic, never a gate.
- Superscalar issue, branch prediction, caches. Wrong machine: memory-operand
  ISA, read-modify-write instructions, single-port RAM shared with PPU and DMA.

## Decisions

### Decision: rebuild rather than retrofit

The retrofit plan had three phases, of which only the last touched the decode
structure — and it addressed it by *registering* the 17 `casex` blocks rather than
replacing them. It would have arrived at a core that closed timing and was still
hostile to the ISA slices.

**Alternatives considered:**

**A. Retrofit Arlet in place** (the previous plan). A cycle-neutral phase 1 — fold
the BCD adjust into the ALU's registered stage, split the 12-arm `AB` mux, flatten
the arbiter read mux — followed by a registered decode. Still the right *fallback*
if the rebuild stalls, and phase 1's three items remain good ideas that the new
core should incorporate by construction. Rejected as the destination: it leaves the
decode unextendable and it is bounded by someone else's structural choices.

**B. Adopt a different existing core** (`T65`, `chipsuite`, a 65C02 core). Some are
better retimed already. Rejected for the same reason as A plus a new one: we would
inherit *their* structural assumptions and their undocumented-opcode baggage, and
we would still have to learn the code well enough to add a prefix decode page. The
evaluation cost approaches the rebuild cost.

**C. Keep Arlet and give the CPU its own slower clock.** `clocks.sv` already
exports `cpuclk` and `chip.sv:10` accepts and ignores it — the plumbing exists and
is dead. This removes the CPU from the chip's critical path in ~30 lines. It is the
correct answer if Fmax is the *only* problem, and it remains the emergency
fallback. Rejected as the destination because it makes every multi-cycle
instruction the ISA slices add (up to 11 cycles for `ADDW zp, zp`) twice as
expensive in wall-clock terms, and because it does nothing for the decode.

**D. Rebuild** (recommended). Costs the most up front and is the only option that
solves both problems. De-risked by 65x02 to a degree that was not available when
this change was first written.

### Decision: three conformance tiers, because the suite promises more than we do

65x02 specifies cycle-by-cycle bus activity. We intend to diverge in timing. Using
the suite naively would either force NMOS timing back on us or discard most of its
value. The tiers resolve that:

| Tier | What is compared | Status |
| --- | --- | --- |
| 1 | `initial` → `final`: `PC`, `S`, `A`, `X`, `Y`, masked `P`, all `ram` entries | **Gate.** Timing-free. |
| 2 | No address accessed that is absent from the case's `ram` list | **Gate.** Timing-free. |
| 3 | The full `cycles` array, in order | Diagnostic only. |

Tier 2 is the one easy to overlook and the one that matters most on this console:
`$4000-$41FF`, `$E000-$EA00` and `$F000-$F800` are memory-mapped peripherals, so a
stray read is a peripheral event, not a wasted cycle. The suite gives it to us for
free through its "must not be accessed" rule. Tier 3 earns its keep during
bring-up: when Tier 1 fails, the cycle array usually says why at a glance.

### Decision: only documented flags are contractual

| Excluded from comparison | Why |
| --- | --- |
| `N`, `V` after `ADC`/`SBC` with `D=1` | Undocumented on NMOS; the corpus consumes only `C` and the result bytes from its BCD chains |
| `P` bits 4–5 outside a pushed `P` | No architectural meaning; only observable through `PHP`/`BRK`/`PLP`, where the conventional values are implemented anyway |

The mask is a table in the harness, not a scatter of special cases, and **every
masked-out mismatch is counted and reported**. An exclusion that starts absorbing
real failures shows up as a rising count instead of as silence. If a category's
count is zero across a full sweep, that exclusion becomes a candidate for deletion.

### Decision: decimal mode stays

Tempting to drop — it is the BCD half-carry in the ALU adder plus the
`ADJH`/`ADJL` adjust, and those sit on two of the four unregistered paths, and
slice 3's proposed `ADD`/`SUB` ignore `D` by design. But the score is 3-byte BCD
and `main.asm:1481-1495` multiplies it by repeated decimal addition. Dropping BCD
breaks scoring. It stays; only its undocumented flag results are dropped.

The Fmax cost is recoverable anyway: the adjust belongs *inside* the ALU's
registered stage, computed from the pre-flop carry and half-carry, rather than as
two 4-bit adders hanging off the flopped result on the way to the register file.
That was retrofit phase 1 item 1, and the new core should do it by construction.

### Decision: undefined opcodes trap

The 105 undefined slots must do *something*. NMOS jams on some and executes
undocumented behaviour on others; neither is useful here. They raise the diagnostic
trap that `add-isa-core-ergonomics` introduces as `TRAP #imm` — the simulator
reports the opcode and `PC`, hardware treats it as inert. This turns a wild jump or
a mis-assembled byte from silent corruption into a named failure, and it costs one
default row in the decode table.

Slots claimed later by an ISA slice stop trapping when that slice lands. The
reservation policy in `docs/opcodes.md` still governs which slots a slice may
claim, unchanged.

### Decision: table-driven decode in its own file

`rtl/cpu6502_decode.sv` holds one row per opcode: addressing mode, operation,
operand source and destination, and the flag write set. The core is then an
addressing-mode sequencer plus an ALU, and an ISA slice is *new rows* plus
occasionally a new addressing mode — in one file, reviewable against
`docs/opcodes.md` line by line.

This mirrors what `add-custom-assembler` does on the software side, where a slice
is a new `#ruledef` in `src/isa/ext_*.asm`. The symmetry is suggestive; it is
raised as an open question below rather than committed to here.

### Decision: harness on Verilator, with a pre-packed fixture

The repo already builds a Verilated model with a C++ driver (`sim/console.cpp`,
`--cc … --exe`), so `tools/65x02/` follows that path: Verilate the core alone
against a flat 64 K memory, expose the architectural registers for forcing, and per
case — load `initial.ram`, force `PC`/`S`/`A`/`X`/`Y`/`P`, run one instruction,
compare.

Two practical points decide whether this is usable day to day:

- **JSON parsing dominates, not simulation.** 1.51 M cases at ~6 cycles is ~9 M
  simulated cycles — seconds. Parsing 1,082 MB of JSON is not. A one-time converter
  packs the suite into a compact binary fixture, cached outside the repo; routine
  runs read that.
- **Two speeds.** A fast subset (N cases per opcode) for every build, the full sweep
  as a per-phase gate. The subset size is recorded with the result, so "passes"
  always states how much was actually run.

Forcing internal registers is a deliberate testability requirement on the new core,
not a hack bolted on afterwards. The alternative — a preamble of
`LDX`/`TXS`/`PHA`/`PLP`/`JMP` establishing state through the public interface —
perturbs the flags it is trying to set and costs cycles per case.

### Decision: the cycle model is chosen, then frozen

The retrofit plan was cornered: registering the decode cost +1 cycle per
instruction, static mean CPI was 3.08 over `src/main.asm`'s 1919 instructions, so
it needed a **1.324×** Fmax gain merely to break even. A from-scratch core is not
cornered — it can pipeline the fetch and register the decode together, and it can
delete NMOS's wasted cycles (the RMW dummy write, the indexed and branch page-cross
penalties).

The honest size of the cycle prize is small: 38 RMW sites in the corpus, ~0.6% of
static cycles, plus data-dependent page-cross savings. **The declared target is
therefore CPI no worse than 3.08 at a strictly higher Fmax**, and the moment the
core passes Tier 1 the resulting table is frozen into `docs/cpu-timing.json` as the
baseline every ISA slice budgets against.

## The gates

| Gate | Statement | Check |
| --- | --- | --- |
| **T1 Documented-subset conformance** | All 151 documented opcodes pass 65x02 Tiers 1 and 2 over the full 10,000 cases each (1.51 M), under the declared flag mask, with masked-mismatch counts reported. | `make test-65x02` |
| **T2 The console still works** | Dormann's `6502_functional_test` passes, and Breakout runs and plays with the unmodified `rtl/ram.hex`. | `make test`, `make run` |
| **T3 Interrupts proven** | Directed tests cover `IRQ`/`NMI` entry, priority, `I`-flag masking, vector fetch, the `BRK`-vs-hardware-IRQ `B`-flag distinction, and `RTI`. 65x02 covers none of this. | `cpu6502_irq_tb` |
| **T4 Critical path relocated** | The design's longest path does not originate in, terminate in, or traverse the `cpu` hierarchy. | `make timing` |
| **T5 Fmax** | Achieved Fmax on `hx8k` beats the recorded Arlet baseline by the declared target and meets the `TARGET_FREQ` constraint rather than merely being reported against it. | `make timing` |
| **T6 Wall-clock non-regression** | Per opcode, `cycles_new / Fmax_new ≤ cycles_old / Fmax_old`; static mean CPI ≤ 3.08; frame-work time non-increasing in microseconds. | `make timing` + `make metrics` |
| **T7 Stall correctness** | `RDY` low suspends the core at any cycle boundary including a write; on release every access happens exactly once, in order. Verified per state, and by DMA running with the arbiter workaround removed. | `cpu6502_stall_tb` |
| **T8 Area** | LUT and DFF usage stays within the declared budget with stated headroom for the remaining ISA slices. | `make stat` |

T4 is falsifiable and cuts both ways: if the Arlet baseline shows the critical path
already outside `cpu`, the Fmax half of this change's motivation evaporates and only
the decode-extensibility half remains. That is still worth doing, but at a much
lower priority — and the separate-`cpuclk` alternative becomes attractive.

## Bring-up plan

1. **Harness first, against Arlet.** Build `tools/65x02/` and run it on the
   *existing* core. This validates the harness against a known-good
   implementation, produces the Arlet baseline cycle table, and — usefully — says
   where Arlet itself diverges from the suite, before we start comparing the new
   core to anything.
2. **Baseline timing.** A completed `yosys` → `nextpnr` → `icetime` run for `hx8k`;
   `make timing` with module attribution; record Fmax, paths and area in
   `docs/cpu-baseline.json`.
3. **New core, non-pipelined first.** Registered interfaces and the decode table,
   but a straightforward sequencer. Pass Tiers 1 and 2 on the fast subset, then the
   full sweep. Tier 3 available as a debugging aid.
4. **Pipeline it.** Registered decode and a correct global stall. Re-run T1
   unchanged — this is the payoff of having built the net first: a structural change
   to the core is one command away from 1.51 M cases of evidence.
5. **Integrate.** Swap the wrapper, run T2, remove the arbiter's write-stall
   workaround, run T3 and T7.
6. **Measure and freeze.** T4–T6 and T8; freeze `docs/cpu-timing.json`; delete the
   Arlet files.

## Risks / Trade-offs

- **A rebuild is the largest single change in the programme.** Mitigation: the order
  above means the net exists before the core does, and step 3 is a conventional
  non-pipelined core — the hard part (step 4) is attempted only once 1.51 M cases
  already pass.
- **Forcing internal registers couples the harness to the core's internals.**
  Mitigation: name the architectural registers as an explicit, documented
  testability interface, so the coupling is a contract rather than an accident.
- **65x02 does not test interrupts, and the console's interrupt path has never been
  exercised** — vectors point at `$0000`, handlers are a bare `rti`, `IRQ` and `NMI`
  are tied low. So the new core's interrupt logic will be newly written *and* newly
  tested, with no working reference to diff against. Gate T3 exists because of this;
  it is the weakest-evidence part of the change.
- **"Documented" needs a definition.** Mitigation: the 151 opcodes named in
  `docs/opcodes.md`, which `add-isa-ergonomic-gates` already establishes as the
  registry. Disagreements about a specific instruction's documented flag effects are
  resolved by the suite, then recorded in the mask table with a reason.
- **The suite is 1,082 MB and not vendored**, so a network fetch sits between a
  fresh clone and a passing test. Mitigation: cache outside the tree, pin the
  commit, and make the fast subset runnable from a much smaller packed fixture that
  *can* be cached in CI.
- **Deleting Arlet loses fixes found the hard way** (`1c6f5e3`'s indirect
  addressing, reset-vector handling, the flag initialisation that keeps `X` out of
  simulation). Mitigation: those are precisely what Tier 1 catches, and step 1 runs
  the harness against Arlet first, so any divergence it already has is documented
  before removal rather than rediscovered after.
- **Area could crowd out later slices.** A decode table is BRAM- or LUT-hungry
  depending on how it is inferred, and `add-isa-frame-pointer`'s prefix page adds a
  second one. T8 makes the budget explicit at the start rather than at slice 7.

## Open Questions

- **Should `docs/opcodes.md` generate both the customasm `#ruledef` and the RTL
  decode rows?** It is already declared the single authoritative registry; making it
  executable would remove the possibility of assembler and hardware disagreeing
  about an encoding. Attractive, and a scope expansion touching
  `add-custom-assembler` — raised here, not assumed.
- **Is `TARGET_FREQ = 50` a goal or a stale constraint?** `rtl/pll.v` is generated
  for 50 MHz and `rtl/top.sv` never instantiates it, so the board runs the raw
  25 MHz pin. T5's target depends on the answer.
- **Does anything besides the CPU want a faster clock?** The LCD serialiser and the
  PSG's 22050 Hz derivation are both clock-portable by parameter. If nothing else
  benefits, the Fmax motivation weakens and extensibility carries the change alone.
- **How many cases in the fast subset?** Needs the harness's measured throughput.
  Whatever it is, it must be recorded with every result.
- **Do PSG register reads have side effects?** `sta PSG_CH,y` at `main.asm:2479` is
  the corpus's only indexed MMIO access, and on NMOS it implies a dummy read of
  `$4110+y`. If PSG reads are side-effect-free, Tier 2 divergence there is harmless;
  if not, the new core's access footprint at that site matters.
