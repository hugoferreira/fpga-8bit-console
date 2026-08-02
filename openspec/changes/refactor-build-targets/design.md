# Design

## Measurements

All on ice40 hx8k, package tq144:4k, yosys `synth_ice40` + nextpnr `--freq 50
--seed 1`, measured 2026-07-25. Final table at RTL fingerprint `26545f591961`,
commit `bd502a6`.

| | logic cells | BRAM | Fmax | critical path |
| --- | --- | --- | --- | --- |
| `synth-cpu` | 1535 / 7680 (19%) | 4 / 32 | 44.87 MHz | RAM `RDATA` -> RAM `WDATA` |
| `synth-psg` | 6759 / 7680 (88%) | 16 / 32 | **28.38 MHz** | `prun` -> `n_res` |
| `synth-ppu` | 4329 / 7680 (56%) | 20 / 32 | 31.41 MHz | RAM `RDATA` -> `regs.stage_rep` |
| `synth-soc` | **11058 / 7680 (143%)** | **48 / 32 (150%)** | - | does not place |

`synth-soc` independently corroborates `docs/cpu-baseline.json`'s 10731 LC /
48 BRAM, obtained by a different route.

`--freq 50` is aspirational, so nextpnr prints `FAIL at 50.00 MHz` for three of
these. The real requirements are `clk` = 3.52 MHz (met ~10x over) and
`psgclk` = 112.5 MHz (missed 4x). Only the PSG's is a defect.

### The PSG, standalone — the number that motivates the change

| | |
| --- | --- |
| LUT4 | 4976 |
| Carry | 886 |
| Logic cells | **6772 of 7680 — 88%** |
| Block RAM | 16 of 32 — 50% |
| SB_IO | 21 of 256 |
| **Fmax** | **28.24 MHz** |
| Critical path | `u_psg.prun` → `u_psg.n_res` — the reciprocal / divide path |

Measured through a probe wrapper (`pcm` and `dout` XOR-reduced to one pin,
`dbg` left unconnected — see *Tie-off discipline* below).

**Against a 112.5 MHz requirement.** `rtl/clocks.sv` assigns
`psgclk = clk`, the undivided PLL. The PSG closes at a quarter of that. The
56.25 MHz (/2) fallback named in `refactor-psg-voice-pool` task 2.2a1 also
fails. The first divider that closes is **/4, 28.125 MHz**, which is 1275
clocks per 22050 Hz sample — enough for sixteen BRAM-streamed voices at the
~320 clocks `design.md` §Clocks budgets for them, but it invalidates the
"5102 clocks per sample" arithmetic in `clocks.sv`'s header comment and in
`chip.sv:200-204`.

This is reported, not fixed, here. See *Non-goals* in the proposal.

### Why it could not be seen before

`ram_async.sv` models the 64 KB map as an on-chip array. yosys expands it to
~1.7 M gates and nextpnr never places the design, so no timing report is
produced for anything. Every subsystem's timing question was recorded as
"blocked behind area" when it was in fact blocked behind *the design having one
top*. The PSG owns 64% of whole-chip logic and yet fits alone at 88% — the two
facts are consistent, and only the second is measurable.

## Decisions

### D1. Parameterise `chip.sv`; do not fork it

`chip.sv` gains `HAS_PPU` and `HAS_PSG`; subsystem instantiations move inside
`generate` guards, tie-offs into the `else` branches. Four thin tops set the
parameters.

*Rejected: four hand-written tops that each instantiate the pieces they need.*
That is how `rtl/cpu_fmax_top.sv` was built, and it shows the failure mode
already — it carries a private 2 KB RAM model written to imitate
`ram_async.sv`'s read timing, with a comment saying so. The imitation is
correct today and nothing enforces that it stays correct. Every additional
hand-wired top is another copy of the console's wiring that can rot silently
against the one that ships. With parameters there is one wiring description and
the subsystem targets are literally the shipping design with parts switched
off.

*Rejected: extracting a `soc_bus.sv`.* Cleaner module boundaries, but it means
untangling `chip.sv`'s currently-flat wiring into a new interface. The
parameter approach gets the same four targets for a diff that adds guards
rather than moving signals.

### D2. The arbiter stays in every target

`target_cpu` is the CPU *in its real bus* — arbiter, DMA controller and
`ram_async` — not the bare core. The arbiter's data-in mux sits on the CPU's
critical path in the real chip, and `memory_arbiter.sv:141-146` records that
this path once produced a combinational loop. A CPU number that excludes it is
not a number about the console.

`rtl/cpu_fmax_top.sv` measures the opposite thing on purpose — core only, so a
difference between two runs is a difference between two cores — and
`rtl/cpu6502_sst.sv` is the conformance harness. Both are kept. The three
answer different questions and the change documents which is which, so they
stop looking like three attempts at one thing.

No surgery is needed on `memory_arbiter.sv`: with a subsystem absent, its
`*_data_in` port ties to zero and yosys trims the corresponding decode branch.

### D3. Tie-off discipline for verification-only ports

**A synthesis top MUST leave verification-only ports unconnected exactly as
`rtl/top.sv` does.** `rtl/top.sv:52-55` leaves `.psg_dbg()` open and yosys
trims the 64-bit bus; anything that connects it instead measures logic the
console does not contain.

This is written down because it was got wrong immediately. The PSG does not
place as `-top psg`, and the reason is not area:

```
Info:  ICESTORM_LC: 6791/7680  88%     <- fits
ERROR: Unable to find a placement location for cell 'dbg[22]$sb_io'
```

108 of tq144:4k's pins, for a debug bus. The reflex fix — XOR `dbg` into a
probe pin, as `cpu_fmax_top.sv` does for its real outputs — makes it place and
makes the measurement wrong, because it pins logic that is otherwise trimmed.
The correct wrapper leaves `dbg` open and reduces only `pcm` and `dout`.

So each `target_*.sv` carries a probe reduction over its **real** outputs
(`rgb`, `audio`), and leaves `psg_dbg` open. The delta is small here (4998 →
4976 LUT4) but the principle is not: the rule is "match the shipping top", and
its cost when violated scales with however much debug logic a subsystem grows.

### D4. RAM size per target is chosen so the subsystem's own BRAM is visible

BRAM is the binding constraint on this device — 32 blocks total, and the PSG
and PPU take 16 each. At `RAM_ADDR_BITS=13` (the 8 KB `top.sv` currently uses)
main RAM takes another 16, so `target_psg` would sit at exactly 32/32 and
`target_ppu` likewise, with any subsystem growth reported as an unplaceable
design rather than as a number.

Each target therefore sets `RAM_ADDR_BITS` to the smallest value that still
exercises the bus — **11 bits, 2 KB, 4 blocks** — matching what
`cpu_fmax_top.sv` already chose for the same reason. `target_soc` keeps
`RAM_ADDR_BITS=13` so it stays comparable to today's `bin/toplevel.json`.

The truncation makes these targets non-functional for running a program (`$FFFC`
aliases into the program image, as `top.sv:64-67` already warns). They are
measurement and timing targets; the functional gates are the simulator ones.

### D5. Naming: `synth-<unit>`, not `<unit>-synth`

```
make synth-cpu              area + Fmax at seed 1
make synth-psg SEEDS=5      ... plus min/median/max over 5 placements
make synth-ppu
make synth-soc
make synth-all              all four, as one table
```

**The obvious scheme — `<unit>-synth` — cannot be used, and the reason is worth
recording.** `ppu-synth` already exists and means *the compositor alone*
(`-top sprite_compositor`), and `refactor-ppu-core/design.md` has committed
baselines taken from it: 1846 LUT4, 2623 logic cells, 16 BRAM, 62.6 MHz, plus a
stated ±6 LUT4 noise floor that small deltas are judged against. Re-pointing
that name at `target_ppu` would keep every command working while quietly
changing what the numbers mean, and a mid-refactor comparison could mistake a
compositor-only baseline for a compositor-plus-bus measurement and read the
difference as a regression.

`synth-<unit>` collides with nothing: not `ppu-synth`, not `ppu-timing`, not
`cpu-fmax` (core-only Fmax), not `cpu-timing` (which is instruction *cycle
counts*, not frequency, and would have been a genuinely misleading collision).

**One target, not two.** The seed sweep folds into `SEEDS` rather than becoming
a second target family. A separate `fmax-<unit>` would sit one transposition
away from the existing `cpu-fmax` while meaning something different — the kind
of near-collision that gets mistyped once and produces a plausible wrong number.
`SEEDS=1` (default) is the quick answer; `SEEDS=5` gives the range.

Reporting a range matters because nextpnr's placement is seed-dependent with
about a 5 MHz spread on this design — wider than most deltas anyone is chasing.
`ppu-timing` already does this and keeps its name.

Nothing that exists is renamed or re-pointed:

| Target | Status after this change |
| --- | --- |
| `ppu-synth`, `ppu-timing`, `ppu-check`, `ppu-lint`, `ppu-probe` | **untouched** — compositor-only, still the right tool inside the PPU |
| `cpu-fmax` | **untouched** — core-only, no arbiter |
| `cpu-timing` | **untouched** — instruction cycle table |
| `test-65x02`, `test-psg`, `psg-wav`, `psg-analyze` | **untouched** |
| `timing` | **untouched** — whole chip via `top.sv`; still cannot place |
| `synth-cpu/psg/ppu/soc`, `synth-all` | new |

The cost of this choice is that `synth-ppu` and `ppu-synth` are different
measurements with confusingly similar names. They are distinguished in
`docs/build-targets.md` and in each file's header: `ppu-synth` is the
compositor, `synth-ppu` is the compositor plus the bus it hangs off.

### D6. Simulation tops are not split

`rtl/top_simulator.sv` stays one Verilator top. Splitting it buys nothing:
`make run` needs the whole console, and the two subsystem simulation paths that
matter — `sim/psg_wav.cpp` (PSG alone, fast clock) and `rtl/ppu_golden_tb.sv`
(PPU alone, golden frames) — already bypass it and already work. The
`HAS_PPU`/`HAS_PSG` parameters default to 1, so `top_simulator.sv` needs no
edit at all.

## Amendments made during implementation

The decisions above are as proposed. Four survived contact; these did not, and
the reasons are the useful part.

### A1. `target_psg` does not go through `chip.sv` (amends D1, D2, D4)

D1 says every target is the shipping design with parts switched off, and D2 says
the arbiter stays in all of them. **Both are true for `cpu`, `ppu` and `soc`, and
neither is true for `psg`.** Both ways of honouring them were built and measured:

| `target_psg` as | logic cells | outcome |
| --- | --- | --- |
| PSG + CPU + bus | 8210 (106%) | **does not place** — and no placement means no timing report, which is the one thing this target exists to produce |
| PSG + bus, no CPU | 1467 | **folded** — no bus master means `cpu_addr` is constant, `psg_cs` never asserts, and 78% of the PSG constant-folds |
| PSG alone, pins | 6759 (88%) | correct, and closes the open task |

So the PSG's register interface is driven from pins. The drift risk D1 warns
about is genuinely lower here than for the CPU: `target_psg.sv` instantiates
`psg` with its own port list and models nothing, unlike `cpu_fmax_top.sv`, whose
private RAM imitates `ram_async.sv` and can silently stop imitating it. The
CPU-drives-the-PSG configuration is still covered — by `make run` and
`make psg-wav`, not by synthesis.

### A2. `HAS_CPU` was added and then removed

A third parameter looked like the orthogonal answer to A1. It is not: removing
the bus master is exactly what folds the design. `chip.sv` carries a comment
recording the measurement so the next person does not re-derive it.

### A3. Observability lives in the no-PPU tie-off, not in a new `chip` port
(amends D3)

D3 covers ports that must be left *unconnected*. The opposite problem also
exists: with `HAS_PPU=0` and `HAS_PSG=0`, `rgb` and `audio` are constant zero,
the probe is constant, and the CPU, arbiter and RAM are all trimmed — the first
`make synth-cpu` reported **193 MHz with its critical path inside the video
timing generator**.

The fix was going to be a `cpu_probe` output on `chip`. **That breaks the
build**: Verilator escalates `PINMISSING` to an error, so `top_simulator.sv`
fails to compile the moment `chip` gains a port it does not connect. Adding an
output port to a shared module is not additive here, which is worth knowing
before someone tries it for another reason.

Instead the `g_no_ppu` branch drives `srgb` from a registered reduction of the
CPU bus. Note it is **one bit, not `{RGB{bus_obs}}`** — a probe XOR-reduces its
inputs and RGB is 16, so replicating the bit made it constant again and folded
the design harder than the original bug: 103 logic cells.

### A4. A floor on logic cells, because this class of bug is silent (new)

Three separate folded measurements, each of which reported success. `make
synth-*` now fails below `SYNTH_MIN_LC_<unit>`. Provable:
`make synth-cpu SYNTH_MIN_LC_cpu=99999` exits 1.

### A5. Every measurement is fingerprinted (new)

During this work the CPU core was replaced under the targets (`3c0f2f8`, "the
console runs on the new core, and Arlet is gone"), and two runs of `synth-ppu`
minutes apart legitimately reported 3790 and 4321 logic cells. An A/B of
`chip.sv` also has to be run in an isolated
copy of the tree, with a guard asserting the non-`chip.sv` RTL did not move, or
the result is noise — the first three attempts at the byte-identical gate were
invalid for this reason.

Every target now prints `rtl <hash> @ <commit>`.

## Risks

The guards are additive and both parameters default to 1, so `top.sv`,
`top_simulator.sv` and every existing target behave identically without being
touched. The gate for "additive" is that `make run`, `make ppu-check` and
`make test-psg` produce byte-identical output before and after (task 1.1).

**`cpuclk` is dead.** `chip.sv` takes a `cpuclk` port and never uses it — the
CPU runs on `clk`. Tempting to remove while in the file; deliberately left
alone, because it is a port-list change to a shared module for no measurement
benefit. Noted for whoever lands the memory abstraction.

**Reporting 28.24 MHz may look like this change broke something.** It did not;
the clock tree has been wrong since `f6fd3ab` and this is the first target able
to say so. The write-up in `docs/hardware-gaps.md` states the measurement, the
commit that introduced the requirement, and that no behaviour changed here.
