## 1. The net, before anything moves

- [x] 1.1 Record the "before" outputs that prove this change is additive:
      `make run` (a `make shot` frame per game, committed hash), `make
      ppu-check`, `make test-psg`, `make test-65x02 CASES=100`. These must be
      byte-identical after §2. Without this the guards are justified by reading
      the diff, which is the thing `refactor-ppu-core` §1 exists to stop doing
- [x] 1.2 Record the "before" area of the whole chip as yosys reports it today
      (7,869 LUT4, 48 BRAM per `docs/cpu-baseline.json`), so the sum of the new
      per-target numbers can be reconciled against it rather than asserted

## 2. Parameterise `chip.sv`

- [x] 2.1 Add `HAS_PPU` and `HAS_PSG` parameters, both defaulting to 1
- [x] 2.2 Wrap the `sprite_compositor` + `palette` instantiation in
      `generate if (HAS_PPU)`; in the `else`, tie `sp_do`, `tb_do` to zero and
      `rgb` to zero
- [x] 2.3 Wrap the `psg` instantiation in `generate if (HAS_PSG)`; in the
      `else`, tie `psg_do` and `audio` to zero
- [x] 2.4 Confirm `memory_arbiter.sv` needs no change — with a subsystem
      absent its `*_data_in` reads zero and its decode branch is trimmed. If
      that turns out to be false, record why here rather than editing the
      arbiter silently
- [x] 2.5 `verilator --lint-only` clean at all four parameter combinations
- [x] 2.6 Gate: §1.1 outputs byte-identical. `top.sv` and `top_simulator.sv`
      are **not** edited — the defaults make them correct as written

## 3. The four tops

- [x] 3.1 `rtl/target_cpu.sv` — `chip #(.HAS_PPU(0), .HAS_PSG(0),
      .RAM_ADDR_BITS(11))`. Probe-reduce `rgb`/`audio` to one registered pin
- [x] 3.2 `rtl/target_psg.sv` — AMENDED: instantiates `psg` directly from
      pins, not through `chip.sv`. Through `chip` it either does not place
      (8210 LC with a CPU) or folds (1467 LC without one). `dbg` left
      **unconnected** (design.md D3, A1)
- [x] 3.3 `rtl/target_ppu.sv` — `#(.HAS_PPU(1), .HAS_PSG(0),
      .RAM_ADDR_BITS(11))`
- [x] 3.4 `rtl/target_soc.sv` — `#(.HAS_PPU(1), .HAS_PSG(1),
      .RAM_ADDR_BITS(13))`, matching what `top.sv` builds today
- [x] 3.5 Each top carries a header comment saying what question it answers and
      what it deliberately excludes, in the style of `cpu_fmax_top.sv`
- [x] 3.6 Check the I/O count places on tq144:4k for each, and that no target
      fails placement for pins rather than logic (design.md D3)

## 4. Makefile targets

- [x] 4.1 `synth-<unit>` for `cpu`, `psg`, `ppu`, `soc` — yosys + nextpnr at
      seed 1, reporting logic cells, BRAM, Fmax and the critical path's source
      and sink. One `define`/`eval` rule, not four copies. Named
      `synth-<unit>`, not `<unit>-synth`: see design.md D5
- [x] 4.2 Seed sweep — AMENDED: folded into `SYNTH_SEEDS` on the same target
      rather than a second `<unit>-fmax` family, which would have sat one
      transposition from the existing `cpu-fmax` while meaning something else.
      `SYNTH_SEEDS` is private to this block; the existing `SEEDS ?= 5` belongs
      to `ppu-timing` and was not touched
- [ ] 4.3 `<unit>-check` — `cpu-check` → `test-65x02`, `psg-check` →
      `test-psg`, `ppu-check` unchanged, `soc-check` → `make shot` for each
      game against a committed frame
- [x] 4.4 Nothing renamed or re-pointed, so no aliases were needed:
      `ppu-synth`, `ppu-timing`, `cpu-fmax`, `cpu-timing`, `timing` all keep
      their exact current meanings (design.md D5)
- [x] 4.5 `.PHONY` updated. `ppu-check` and `test-psg` re-run green on the
      final tree; `ppu-synth`/`ppu-timing` untouched. Verified the block
      coexists with `add-tangnano20k-target`'s block, which landed mid-change

## 5. Answer the gates that were recorded as blocked

- [ ] 5.1 `docs/cpu-baseline.json`: fill in `blocked_gates` T4 (critical path
      relocated) and T5, from `cpu-synth` and `soc-synth`. Where `soc-synth`
      still cannot place, say so with the utilisation figure rather than
      leaving the field absent
- [x] 5.2 `refactor-psg-voice-pool` task 2.2a1 — closed by `make synth-psg`:
      **28.38 MHz at seed 1** (28.24 on an earlier fingerprint), against the
      112.5 MHz `clocks.sv` drives. Written up in `docs/hardware-gaps.md`
- [ ] 5.3 Re-measure the per-voice area law (3314 fixed + 379/voice) through
      `psg-synth`, so the voice-pool change has a repeatable command instead of
      a number in a memory file
- [ ] 5.4 `docs/cpu-core.md` — the paragraph asserting whole-chip timing is
      unobtainable is now false for three of four targets. Correct it

## 6. The PSG clock defect

Reporting only. The fix belongs to `refactor-psg-voice-pool`.

- [x] 6.1 New entry in `docs/hardware-gaps.md`: the PSG closes at 28.38 MHz and `clocks.sv`
      drives it at 112.5; introduced by `f6fd3ab`; /4 (28.125 MHz) is the first
      divider that closes; the critical path is `prun` → `n_res`
- [x] 6.2 State the consequence explicitly: the "5102 clocks per sample"
      arithmetic in `clocks.sv`'s header and `chip.sv:200-204` is wrong at any
      closing divider. At /4 it is 1275, still enough for sixteen
      BRAM-streamed voices at ~320 clocks
- [ ] 6.3 Open a task under `refactor-psg-voice-pool` for the pipelining fix,
      gated on its render comparison. Do **not** change `clocks.sv` here —
      dropping to /4 changes every PSG rate and needs that gate

## 7. Documentation

- [x] 7.1 `docs/build-targets.md` — the four targets, the one naming scheme,
      what each answers, and the tie-off discipline with the `dbg` incident as
      the worked example
- [x] 7.2 Say plainly why `cpu_fmax_top.sv`, `cpu6502_sst.sv` and `target_cpu`
      all exist: core-only Fmax, conformance, CPU-in-its-bus. They look
      redundant and are not

## 8. Added during implementation (see design.md, Amendments)

- [x] 8.1 `target_psg` driven from pins rather than through `chip.sv`, with both
      rejected alternatives measured and recorded (8210 LC does not place; 1467
      LC is folded)
- [x] 8.2 Observability tie-off in `chip.sv`'s `g_no_ppu` branch, after a `chip`
      output port turned out to break `top_simulator.sv` (Verilator escalates
      PINMISSING to an error)
- [x] 8.3 `SYNTH_MIN_LC_<unit>` floor so a folded design fails instead of
      reporting a spectacular Fmax. Proved to bite:
      `make synth-cpu SYNTH_MIN_LC_cpu=99999` exits 1
- [x] 8.4 `rtl <hash> @ <commit>` fingerprint on every measurement, and the
      byte-identical gate re-run in an isolated tree copy with a guard on the
      non-`chip.sv` RTL
- [x] 8.5a `sim/ppu_probe.cpp` — the generate block gave the compositor an
      extra hierarchy level, so its four `top__DOT__chip__DOT__s0__DOT__*`
      accessors stopped compiling and `make ppu-probe` failed to build.
      Rewritten to `...chip__DOT__g_ppu__DOT__s0__DOT__*` and verified. The
      byte-identical gate did not catch this: it covers rendering, and this is
      a probe tool that reaches into the hierarchy
- [ ] 8.5 Re-measure on the Tang Nano 20K. `add-tangnano20k-target` landed
      during this change and the GW2AR-18C has 46 BRAM against the HX8K's 32, so
      `synth-soc`'s 150% BRAM result is device-specific. The `synth-*` rules are
      nextpnr/iCE40-only today

## 9. Not done, and why

- [ ] 9.1 `4.3 <unit>-check` aliases — not added. `cpu-check`/`psg-check` would
      be pure aliases for `test-65x02`/`test-psg`, and the Makefile already
      carries two naming schemes plus a third from `add-tangnano20k-target`. A
      third alias family is churn, not clarity
- [ ] 9.2 `5.1` T4/T5 in `docs/cpu-baseline.json` — `synth-soc` corroborates the
      area figures (11058 LC / 48 BRAM against the recorded 10731 / 48) but the
      whole chip still does not place, so whole-chip Fmax remains genuinely
      unavailable. The per-subsystem numbers that *are* now available are in
      `docs/build-targets.md`; the CPU JSON remained pending while the core was
      being rewritten
- [ ] 9.3 `5.3` per-voice area law — needs `NV` sweeps that belong to
      `refactor-psg-voice-pool`
- [ ] 9.4 `5.4` `docs/cpu-core.md` correction — same reason as 9.2
- [ ] 9.5 `6.3` voice-pool task for the pipelining fix — the defect is already
      written up in `docs/hardware-gaps.md`
