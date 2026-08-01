## Why

Three subsystems are being rebuilt at once — `refactor-cpu-core`,
`refactor-ppu-core`, `refactor-psg-voice-pool` — and all three independently
hit the same wall, wrote it down, and stopped:

> `docs/cpu-baseline.json`: *"The whole-chip numbers T4/T5/T8 ask for do NOT
> exist: the design cannot be placed."* — gates `T4 critical path relocated`
> and `T5 whole-chip Fmax` are recorded as **blocked**.

> `refactor-psg-voice-pool/design.md`: *"Fmax needs nextpnr to report a
> critical path, and nextpnr cannot place a design that is 139% over.
> Per-domain Fmax is therefore blocked behind area, not behind clocking — and
> 112.5 MHz for the PSG stays a target rather than a measurement."*

That reasoning is wrong, and this change is mostly about how cheaply it can be
shown to be wrong. **Per-subsystem Fmax was never blocked behind area. It was
blocked behind the build having exactly one top.** Synthesising the PSG on its
own takes one yosys invocation, and it places:

| PSG alone, hx8k tq144:4k, seed 1 | |
| --- | --- |
| LUT4 | 4976 |
| Carry | 886 |
| **Logic cells** | **6772 of 7680 — 88%** |
| Block RAM | 16 of 32 |
| **Fmax** | **28.24 MHz** |
| Critical path | `prun` → `n_res` (the reciprocal/divide path) |

The last row is the point. `rtl/clocks.sv` drives the PSG from the undivided
PLL at **112.5 MHz**, and task 2.2a1 of the voice-pool change is still open
precisely because that number was thought to be unmeasurable. It is a **4×
miss** — and the 56.25 MHz fallback that task names as the safe option misses
by 2×. The PSG has been clocked at four times its closing frequency since
`f6fd3ab`, and no target in this repo could have reported it.

**This is what one top costs.** Not tidiness — a live timing bug, sitting in
committed RTL, invisible because the only thing the build knows how to
assemble is a design that does not fit and therefore never gets as far as a
timing report.

**The separation already exists, three times, by accident.** `ppu-synth` /
`ppu-timing` / `ppu-check` / `ppu-lint` for the PPU; `cpu-fmax` plus
`rtl/cpu_fmax_top.sv` for the CPU; `test-65x02` plus `rtl/cpu6502_sst.sv` for
the CPU again; `psg-wav` plus `sim/psg_wav.cpp` for the PSG. Four naming
schemes, and — the part that will eventually cost real debugging time — two
hand-written CPU harnesses and one PSG harness that instantiate the cores
*next to* `chip.sv` rather than *through* it. Nothing keeps them in step with
the design they claim to measure. `rtl/cpu_fmax_top.sv` already carries its own
2 KB RAM model written to imitate `ram_async.sv`'s timing; when `ram_async.sv`
changes, that imitation silently becomes fiction.

## What Changes

- **`rtl/chip.sv` gains `HAS_PPU` / `HAS_PSG` parameters.** The subsystem
  instantiations move inside `generate` guards and their tie-offs into the
  `else` branches. This is the whole mechanism: there is still exactly one
  description of how the console is wired, and every target below is that
  description with parts switched off, so a subsystem measurement cannot drift
  from what the full chip actually builds.

- **Four synthesis tops**, each a thin instantiation of `chip`:

  | Top | `HAS_PPU` | `HAS_PSG` | What it is for |
  | --- | --- | --- | --- |
  | `rtl/target_cpu.sv` | 0 | 0 | CPU in its real bus — arbiter, DMA, RAM |
  | `rtl/target_psg.sv` | 0 | 1 | the PSG, and a CPU that can drive it |
  | `rtl/target_ppu.sv` | 1 | 0 | the PPU, and a CPU that can drive it |
  | `rtl/target_soc.sv` | 1 | 1 | the full console |

- **One naming scheme across all four**, replacing the four that exist:

  ```
  make <unit>-synth     area + Fmax at seed 1
  make <unit>-fmax      Fmax across SEEDS placements
  make <unit>-check     that unit's regression gate
  ```

  for `<unit>` in `cpu`, `psg`, `ppu`, `soc`. Existing target names are kept as
  aliases because they already appear in documentation.

- **A tie-off discipline, written down and applied.** Verification-only ports
  are left unconnected in synthesis tops exactly as `rtl/top.sv` leaves
  `.psg_dbg()` unconnected. Getting this wrong is not theoretical: the first
  attempt at the measurement above XOR-reduced `dbg` into a probe pin to keep
  the I/O count inside tq144:4k, which pins 64 bits of debug bus that the real
  chip trims — measuring a circuit that does not ship.

- **The blocked gates get answered, not inherited.** `T4`/`T5` in
  `docs/cpu-baseline.json` and `2.2a1` in the voice-pool change are closed with
  numbers from the new targets, and `28.24 MHz` is written up as the defect it
  is.

## Non-goals

- **Not fixing the PSG's Fmax.** This change measures it and files it. The fix
  is pipelining the reciprocal path, which belongs to `refactor-psg-voice-pool`
  and needs its golden-render gate.
- **Not fixing the memory abstraction.** `soc-synth` will still not place while
  the 64 KB map is an on-chip array; `add-memory-subsystem` owns that. The
  difference is that after this change three of the four targets place, so it
  stops being a total blackout.
- **Not touching subsystem internals.** No change to `psg.sv`,
  `sprite_compositor.sv` or any `cpu6502_*.sv` datapath.
- **Not retiring `cpu_fmax_top.sv` or `cpu6502_sst.sv`.** They isolate the core
  *without* the arbiter, which `target_cpu` deliberately includes; both
  questions are worth asking. They are documented as such rather than left to
  look redundant.
