# Build targets: four circuits, not one

Until this change the project had exactly one synthesisable top, and it does not
fit on an HX8K. Everything downstream of that followed: no subsystem had an area
figure, no subsystem had an Fmax, and three separate in-flight changes recorded
their timing questions as *blocked* when what was actually blocking them was the
build having one top.

There are now four, each independently compilable and measurable:

| Target | Contents | `make` |
| --- | --- | --- |
| `rtl/target_cpu.sv` | CPU + arbiter + DMA + RAM | `synth-cpu` |
| `rtl/target_psg.sv` | the PSG alone | `synth-psg` |
| `rtl/target_ppu.sv` | PPU + CPU + bus | `synth-ppu` |
| `rtl/target_soc.sv` | the whole console | `synth-soc` |

```
make synth-cpu                 area + Fmax at seed 1
make synth-psg SYNTH_SEEDS=5   plus min/median/max over 5 placements
make synth-all                 all four, as one table
```

## Measured

iCE40 HX8K, tq144:4k, seed 1, RTL fingerprint `26545f591961` at `bd502a6`.
**Quote the fingerprint whenever you record a number from these** so results
remain attributable as the RTL changes. Every target prints it.

| | logic cells | BRAM | Fmax | critical path |
| --- | --- | --- | --- | --- |
| cpu | 1535 / 7680 (19%) | 4 / 32 | 44.87 MHz | RAM `RDATA` → RAM `WDATA` |
| psg | 6759 / 7680 (88%) | 16 / 32 | **28.38 MHz** | `prun` → `n_res` |
| ppu | 4329 / 7680 (56%) | 20 / 32 | 31.41 MHz | RAM `RDATA` → `regs.stage_rep` |
| soc | **11058 / 7680 (143%)** | **48 / 32 (150%)** | — | does not place |

### Reading the Fmax column

nextpnr is invoked with `--freq 50`, so it prints `FAIL at 50.00 MHz` for three
of these. **That is not the requirement**, and 50 MHz is aspirational — see
`target_freq_status` in `docs/cpu-baseline.json`. The real requirements come
from `rtl/clocks.sv`:

| domain | requirement | measured | verdict |
| --- | --- | --- | --- |
| `clk` (CPU, PPU, arbiter, DMA) | 3.52 MHz (112.5/32) | 31–45 MHz | met, ~10x over |
| `psgclk` (PSG) | **112.5 MHz** (undivided PLL) | **28.38 MHz** | **missed, 4x** |

The one real timing defect is the PSG's, and it is written up in
`docs/hardware-gaps.md`. `synth-soc` failing to place is expected and owned by
`add-memory-subsystem`.

## Why the targets are the shipping design, switched off

`rtl/chip.sv` takes `HAS_PPU` and `HAS_PSG`, both defaulting to 1.
`rtl/target_harness.sv` instantiates that same `chip` — the one `rtl/top.sv`,
`rtl/top_simulator.sv` and `rtl/top_tangnano20k.sv` instantiate — and switches
subsystems off. So a change to how the console is wired appears in every target
with no separate edit, and a subsystem measurement cannot drift from what the
full chip builds.

Compare `rtl/cpu_fmax_top.sv`, which carries a private 2 KB RAM written to
imitate `ram_async.sv`'s read timing. That imitation is correct today and
nothing enforces that it stays correct.

The defaults are what make this safe: `top.sv` and `top_simulator.sv` were not
edited, and `make shot` output is byte-identical across the change.

## Three harnesses for the CPU, and why none is redundant

| | question | includes |
| --- | --- | --- |
| `make cpu-fmax` (`cpu_fmax_top.sv`) | is core A faster than core B? | one core, **no arbiter** |
| `make synth-cpu` (`target_cpu.sv`) | what does the CPU cost the console? | core + arbiter + DMA + RAM |
| `make test-65x02` (`cpu6502_sst.sv`) | is it a correct 6502? | one core + a test fixture |

`cpu-fmax` deliberately excludes the arbiter so a difference between two runs is
a difference between two *cores*. `synth-cpu` deliberately includes it, because
the arbiter's data-in mux sits on the CPU's critical path in the real chip.

Similarly, `ppu-synth` and `synth-ppu` are different measurements with
confusingly similar names: `ppu-synth` is `sprite_compositor` alone and is the
right tool for judging a change *inside* the compositor (its baselines are
committed in `refactor-ppu-core/design.md`); `synth-ppu` adds the bus and is the
right tool for judging whether the console fits. `ppu-synth` was deliberately
not re-pointed — that would have left every command working while silently
changing what the numbers mean.

## The rule that keeps these honest: never measure a folded design

A subsystem whose outputs all reduce to constants is trimmed away, and the
target still reports success with a spectacular Fmax. It is measuring the empty
space where the design used to be. This happened **three times** while building
these targets:

1. **193 MHz, critical path inside the video timing generator.** With no PPU and
   no PSG, `rgb` and `audio` were constant zero, so the probe was constant and
   the CPU, arbiter and RAM were all trimmed.
2. **103 logic cells**, after "fixing" that with an observability tie-off that
   replicated one bit across all 16 lines of `rgb`. A probe pin XOR-reduces its
   inputs, and the XOR of 16 identical bits is constant 0 — the fix folded the
   design harder than the bug.
3. **1467 logic cells for the PSG** (against a true 6759), from removing the CPU
   to save area: with no bus master `cpu_addr` is constant, `psg_cs` never
   asserts, and 78% of the PSG constant-folds.

`make synth-*` now enforces a floor on logic cells per target
(`SYNTH_MIN_LC_<unit>`) and exits non-zero below it. The floors are set well
under the real figures; they catch collapse, not drift. To prove the guard still
bites:

```
make synth-cpu SYNTH_MIN_LC_cpu=99999     # expect: *** TRIMMED, exit 1
```

Two related rules, both learned the same way:

- **Leave verification-only ports unconnected, exactly as the board top does.**
  `rtl/top.sv` leaves `.psg_dbg()` open and yosys trims the 64-bit bus.
  Connecting it measures logic the console does not contain. It is also why
  `yosys -top psg` does not place at all — `dbg` pins 108 of tq144:4k's I/O, and
  the failure reads as an area problem when it is a pin-budget one.
- **Reduce real outputs to a registered probe** so their datapath is not
  optimised away for having nowhere to go, and so targets are not distorted by
  differing I/O counts.

## Scope

These targets are iCE40/nextpnr. The Tang Nano 20K path
(`make tangnano20k-synth`, Gowin GW2AR-18C) is a separate flow with its own
resource budget — 46 BRAM against the HX8K's 32 — so the `soc` result above is a
fact about the HX8K, not about the console. See `docs/boards.md`.

## The PSG's module map

`rtl/psg.sv` is a composition, not a design file: it holds ports, the
`` `include `` chain, the wiring between eight instances, the `walk_frozen`
aggregation, the multiply merge, the PCM register, the CPU read mux and `dbg`.
Everything else lives in a functional submodule
(`openspec/changes/refactor-psg-modules`).

| file | instance | owns |
| --- | --- | --- |
| `rtl/psg_timing.sv` | `u_timing` | the fractional divider, `scnt`, the five strobes |
| `rtl/psg_aram.sv` | `u_aram` | the PICO-8 audio image, the upload port, the ONE shared read port and its borrow/replay contract |
| `rtl/psg_mulsvc.sv` | `u_mul` | the one shift-add multiplier |
| `rtl/psg_divsvc.sv` | `u_div` | the one restoring divider (the sequencer is its only requester) |
| `rtl/psg_state_mem.sv` | `u_state` | the scheduled record store and its two-owner port priority |
| `rtl/psg_wave.sv` | `u_wave` | the computed wave layer: `z_eval`, `dq17`, `q16` |
| `rtl/psg_walk.sv` | `u_walk` | the per-sample synthesis walk; owns `prun` and `pph` |
| `rtl/psg_seq.sv` | `u_seq` | the per-tick sequencer: FSM, records, effects, music flow, control writes |
| `rtl/psg_common.svh` | — | `$unit`-scope slot counts, record layout, `is_mus`/`aud_sl`/`rec_base`/`tzs`, the mirrored field-list macros |

Every register is written by exactly one submodule; cross-module reads travel
on ports and there are no cross-module writes. `psg_common.svh` is included
ONCE, from `psg.sv`, above the module set — the constants carry a `PSG_`
prefix because `$unit` is global and `NV`/`VW`/`NCH` are exactly the names
another module in `chip.sv`'s compilation unit could shadow.

**Composition is unchanged for consumers.** `rtl/chip.sv` and
`rtl/target_psg.sv` still say `` `include "psg.sv" `` and nothing else; every
new file carries an include guard, so naming one explicitly alongside `psg.sv`
is harmless. Verilator needs `-Irtl`, because the including file's own
directory is not on the default search path — the `psg_tb` header command
carries it.

**Testbench bind convention.** `rtl/psg_tb.sv` reads a signal where its OWNER
lives: `dut.u_seq.playing`, `dut.u_state.state_m`, `dut.u_walk.fmc`. Signals
that remain top-level interconnect — `sample_en`, `prun`, `dry_valid`,
`spar_bank`, `bank_ready`, `pre_tick`, `tick_en`, `mus_pat`, `mus_playing`,
`trig_req` — are read off `dut` directly. A stale bind fails compilation
loudly, so drift cannot land silently.

**What the split cost, measured:** +137 pre-mapping cells (+0.98%), −3 flops,
+83 placed LC (+1.1%), 21/32 EBR and routed Fmax unchanged in kind, and all 59
oracle WAVs byte-identical. Two wide combinational boundaries account for
essentially all of it (`psg_wave` +62, `psg_seq` +63): a carry chain that used
to span what is now a port becomes gates. **A pure verbatim move is NOT
cell-identical** — flattening restores the netlist but not the optimiser's
sharing order — so judge a PSG restructuring on the flop count (exact), the
oracle byte-compare (exact) and `psg_tb` (exact), and treat the cell census and
placed LC as measurements to record rather than equalities to hit.

**Census attribution is the payoff.** Grouping the flattened netlist by
instance prefix answers questions the monolith could not: `u_walk` and `u_seq`
are 4,260 of 6,395 LUT4 (67%) and 1,217 of 1,580 flops, so area work outside
them is rounding; `u_mul` is 651 LUT4 for one 21×12 engine, more than the whole
computed wave layer; and `u_wave` holds 7 of the 21 EBRs for its
split-identity tables.
