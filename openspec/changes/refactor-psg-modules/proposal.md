# Refactor: break rtl/psg.sv into functional submodules

## Why

`rtl/psg.sv` is a 3.6k-line single module. At that size the structure that
matters — which cones belong to which function, what is duplicated between
the preview and hardware schedules, where the shared services' contracts
begin and end — is invisible in the text and invisible in the tools: the
area campaign's census ranks LUT cones by net name, so a monolith's ranking
is one undifferentiated pile. The invariants the design actually rests on
(one multiply service, one divider, one phase ALU, one `state_m` port pair,
one `aram` read port) live in comments instead of interfaces. Breaking the
file along its functional seams makes patterns, duplication and
optimization targets findable — by people and by the census — without
changing the netlist at all.

## What Changes

- `rtl/psg.sv` becomes a top-level composition (CPU read mux, `dbg` port,
  wiring) that `` `include ``s new functional submodules. Its port list,
  parameters and external behavior are untouched.
- New files, extracted verbatim along existing seams:
  - `rtl/psg_timing.sv` — fractional sample divider, `sample_en` /
    `tick_en` / `pre_tick` generation.
  - `rtl/psg_aram.sv` — audio RAM, upload port, the single shared read
    port.
  - `rtl/psg_mulsvc.sv`, `rtl/psg_divsvc.sv` — the shared multiply and
    divide services (request selection stays with the requesters).
  - `rtl/psg_state_mem.sv` — the 256x16 scheduled record store and its
    three-owner port priority mux.
  - `rtl/psg_wave.sv` — the computed wave layer: `wx` pipeline,
    split-identity tables, `z_eval`, `dq17`, `q16`.
  - `rtl/psg_walk.sv` — the per-sample synthesis walk: control-store
    decode, noise processes, blend/comb/dampen, soft_add fold, reverb
    rings.
  - `rtl/psg_seq.sv` — the tick sequencer: FSM, tick engine, music flow,
    CPU control writes, effect microprogram including the slide detour.
- `rtl/psg_tb.sv`'s 46 hierarchical `dut.*` binds (18 signals) are
  re-pointed to the new paths, stage by stage.
- Every stage lands with the full gate battery green; the change is
  explicitly pausable between stages.

Not changing (non-goals): no logic rewrites, no LC reduction claims (yosys
flattens before mapping, so the split is netlist-neutral by construction
and by gate), no preview/hardware schedule unification, no `audio-engine`
requirement changes, no edits to `rtl/chip.sv` or `rtl/target_psg.sv`
(both keep their existing `` `include "psg.sv" ``).

## Capabilities

### New Capabilities

- `psg-module-structure`: the functional decomposition of the PSG — which
  submodule owns which state and processes, the interface contracts of the
  shared services and memories, the composition mechanism, and the
  netlist-neutrality gates every structural change must pass.

### Modified Capabilities

<!-- none: audio-engine requirements are deliberately unchanged; the
     byte-exact oracle is the proof -->

## Impact

- **RTL**: `rtl/psg.sv` shrinks to a composition top; seven new
  `rtl/psg_*.sv` files. Include guards prevent double definition however
  the files are listed.
- **Testbench**: `rtl/psg_tb.sv` hierarchical binds re-pointed (Verilator
  errors loudly on a broken ref, so drift cannot land silently).
- **Unaffected by design**: `sim/psg_wav.cpp` (port-only), `rtl/chip.sv`,
  `rtl/target_psg.sv`, `top_simulator.sv` (`dbg` is a port), the Makefile
  (`SYNTH_DEPS` wildcards `rtl/*.sv`), `tools/psg_oracle_matrix.py`.
- **Tooling upside**: `tools/psg_ff_census.py` cone/family rankings gain
  functional attribution from flattened instance name prefixes
  (`u_wave.*`, `u_walk.*`, ...).
- **Coordination**: all touched files are PSG-domain; nothing shared with
  the Celeste/NEMO agent changes.
