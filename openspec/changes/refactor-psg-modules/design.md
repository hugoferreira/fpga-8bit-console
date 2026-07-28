# Design: refactor-psg-modules

## Context

`rtl/psg.sv` is one 3.6k-line module: a tick sequencer FSM (~50 states), a
per-sample synthesis walk driven by a control-store ROM, a computed wave
layer, shared multiply/divide services, a scheduled BRAM record store, the
audio RAM with a borrowed read port, and the CPU interface — all in one
namespace. The 2026-07 DRY and warning-zeroing passes established the
verification anchor this change builds on:

- structural: 14,012 cells / 1,583 flops from
  `yosys -p "read_verilog -Irtl -sv rtl/target_psg.sv; synth_ice40 -top
  target_psg -run :map_luts; stat"` — deterministic, the decisive metric;
- placed: 7,224 LC seed-1 (`make synth-psg`, fingerprint `226084c488ae`),
  with a measured ±60 abc9 naming-sensitivity band around any
  cell-identical netlist;
- behavior: 59/59 oracle WAVs byte-identical vs
  `build/psg_oracle/adopt-exact`, `psg_tb` ALL PASS, zero Verilator
  warnings in three configs (psg_tb build, standalone, REALTIME_PREVIEW=1).

Composition context: `rtl/chip.sv` (shared with the other agent) and
`rtl/target_psg.sv` both `` `include "psg.sv" `` — neither may change.
`rtl/psg_tb.sv` holds 46 hierarchical `dut.*` binds over 18 signals.
`sim/psg_wav.cpp` (the oracle harness) is port-only. `synth_ice40`
flattens before mapping, so hierarchy is free at the netlist level.

## Goals / Non-Goals

**Goals:**

- Functional submodules whose boundaries match the design's real seams,
  so reading, linting, censusing and ablating happen per function.
- The shared-resource invariants (one multiply service, one divider, one
  `state_m` port pair, one `aram` read port, the walk-freeze contract)
  expressed as module interfaces instead of comments.
- Census attribution: flattened cells keep instance prefixes
  (`u_wave.*`, `u_walk.*`, ...), so `tools/psg_ff_census.py` rankings
  group by function without changes to the tool.
- Every stage independently landable and pausable, all gates green.

**Non-Goals:**

- No LC reduction and no LC regression: the gate is cell-identity, not
  improvement. Area work stays in `reduce-psg-ice40-area`.
- No behavior change of any kind, preview included.
- No preview/hardware schedule unification, no service redesign, no
  retiming.
- No edits to `rtl/chip.sv`, `rtl/target_psg.sv`, `sim/psg_wav.cpp`,
  the Makefile, or anything the Celeste/NEMO agent touches.

## Decisions

### D1. Module map = process-ownership map

A register moves with the one process that writes it; cross-module reads
become input ports; there are no cross-module writes. The seams, drawn on
the file's actual always-blocks:

| Module (instance) | Owns (state, processes) | Key inputs | Key outputs |
| --- | --- | --- | --- |
| `psg_timing` (`u_timing`) | `divd`, `scnt`, `tick_en(_d)`, `tick_hold`, `pre_tick`, `sample_en` | clk/reset | the five timing strobes, `scnt` |
| `psg_aram` (`u_aram`) | `aram[]`, `wraddr`, upload writes; the borrow/replay port contract (`replay`, `last_addr`, `seq_q` register, `seq_frozen`) | CPU write strobes, `seq_addr`, `syn_rd`/`syn_addr` | `seq_q`, `seq_frozen` |
| `psg_mulsvc` (`u_mul`) | `m_a`, `m_p`, `m_cnt`, `m_mode` | one merged request bundle | `m_res*`, `m_busy` |
| `psg_divsvc` (`u_div`) | `d_p`, `d_d`, `d_cnt` | request from sequencer only | `d_res`, `d_rem`, `d_busy` |
| `psg_state_mem` (`u_state`) | `state_m[]`, `state_q` register; the fixed three-owner priority mux | walk bundle, engine/tick bundle | `state_q` |
| `psg_wave` (`u_wave`) | `wx_r`/`wsel_r`/... pipeline registers, stage-1/2 registers, `org3`/`tab7`/`tab15` and their read registers | phase/wave/flag view of the current evaluation context | `z_eval`, `dq17`, `q16` |
| `psg_walk` (`u_walk`) | `prun`, `pph`, `pc_ch`, `lfsr`, all `s_*`/`old_*`/`last_*` streaming state, `smp_*`, mixer staging, fold engine (`fmc`, `fstk`, ...), `dry16`/`dry_valid`, `clr_ack`, ctrl ROM generate, ring generate, the phase ALU (both its users are walk-side) | `sample_en`, `playing` view, `spar_bank`, `clr_tog`, `seq_q`, `state_q`, `m_res*` | walk `state_m` bundle, walk mul requests, `syn_rd`/`syn_addr`, `prun`, `fold_busy`, `dry16`/`dry_valid` |
| `psg_seq` (`u_seq`) | `sst` FSM, working registers, `playing`, `trig_req`, `sfx_id`, `launched`, `released`, music flow (`mus_*`, `pticks`, fades), `trg_*`, `aud_row`, `clr_tog`, `spar_bank`, `crom[]` + `pinc_addr`/`crom_q`, effect microprogram (`xs`, `vol_r`, slide detour), engine/tick `state_m` bundle, sequencer mul/div requests, `seq_addr` | `seq_q`, `state_q`, `m_res*`, `d_res`, timing strobes, `walk_frozen`, CPU write strobes | `seq_addr`, `playing` (packed view), `spar_bank`, `clr_tog`, `aud_row`, status fields for the CPU read mux |
| `psg` (top) | CPU read mux (`dout`), `dbg` generate, `walk_frozen` aggregation, wiring | — | existing ports, unchanged |

`walk_frozen = seq_frozen | prun | state_replay | fold_busy` is the
cross-module contract itself, so it is formed at the top from the three
owners' exports (`state_replay` stays with `psg_state_mem`'s replay
tracking — it is `prun` delayed one cycle, owned where the displaced read
is re-issued).

### D2. Composition: `` `include `` chain from psg.sv, include guards

`rtl/psg.sv` gains `` `include "psg_timing.sv" `` (etc.) above the module,
each new file wrapped in `` `ifndef PSG_TIMING_SV `` guards. Why: chip.sv
and target_psg.sv already compose by including psg.sv, and the psg_tb
header command names files explicitly — the includer-relative resolution
that makes `` `include "psg.sv" `` work today makes the nested includes
work identically, and guards make an explicitly-listed file harmless.
Alternative (list every file in every consumer) rejected: it edits
chip.sv, the Makefile-printed fingerprint flow, and every documented
command for zero benefit.

### D3. Verbatim extraction; respelling only in the prep stage

Extraction commits move whole processes and comb blocks unchanged; port
names are the existing signal names. The two places the monolith's text
cannot be split without respelling are done IN PLACE first (stage 0),
single-module, under the same gates, so every later diff is a pure move:

- the multiply-request mux (walk arms and sequencer arms live in one
  `always_comb` today) becomes two request bundles merged in a spelling
  that preserves today's priority: the branches are already disjoint
  (`prun && !m_busy` vs `!walk_frozen && ...`, and `walk_frozen`
  subsumes `prun`);
- the `state_m` port mux becomes two pre-merged owner bundles (the walk's
  sample addresses/writes; the sequencer's engine/tick selection) under
  the existing fixed priority;
- `aud_sl()` gains an explicit packed `play_bits` argument so the CPU
  read mux and `dbg` can live where `playing` does not;
- shared constants (`NV`, `VW`, `NCH`, record-layout localparams) and the
  pure functions/macros move to `rtl/psg_common.svh`.

### D4. Gate battery, unchanged, per stage

Every stage (including stage 0) lands only with:

1. structural stat **cell-identical** (wire-bit deltas from port nets are
   expected and recorded; any cell-row delta is a stop-and-respell);
2. `make synth-psg` placed LC within 7,224 ± 60, fits, routed Fmax ≥
   28.125 MHz, fingerprint quoted;
3. oracle 59/59 byte-identical vs `build/psg_oracle/adopt-exact/rtl`;
4. `psg_tb` ALL PASS via the header's flag-free Verilator command;
5. zero warnings in all three lint configs.

### D5. Stage order: smallest surface first

`prep → timing → aram → mulsvc+divsvc → state_mem → wave → walk → seq →
top cleanup`. Rationale: port surface and TB-bind exposure grow
monotonically; the first stages prove the pipeline cheaply; `walk` before
`seq` because its interface is services+memories while `seq` drags the
CPU write surface and the largest bind set. Each stage re-points only the
`psg_tb` binds whose registers moved (binds to nets that remain top-level
interconnect — `sample_en`, `prun`, `dry_valid`, `spar_bank`,
`bank_ready`, `pre_tick`, `tick_en` — keep working unchanged).

### D6. Instance names are census names

`u_timing`, `u_aram`, `u_mul`, `u_div`, `u_state`, `u_wave`, `u_walk`,
`u_seq` — short and stable, because after flatten they prefix every cell
name and become the census's family keys.

## Risks / Trade-offs

- [abc9 placed wiggle per stage] → cell-identity is the decisive gate;
  placed is tracked against the 7,224 anchor with the documented ±60
  band; fingerprints quoted in every stage's commit message.
- [Respelled merges (mul, state port) change a mux cone] → confined to
  stage 0 where the diff is small and in place; the struct gate falls on
  exactly that stage; iterate the spelling there, never later.
- [A TB bind silently resolving to a stale top-level alias after a move]
  → per-stage sweep: grep the moved-register list against `psg_tb`'s
  bind inventory; array binds (`state_m`, `crom`) fail compile loudly if
  stale.
- [Preview config has no byte oracle] → preview arms move verbatim only
  (no preview respelling exists in any stage); preview lint config stays
  a gate; residual risk accepted and noted, matching the pre-existing
  preview status (open task 6.2 in reduce-psg-ice40-area).
- [Concurrent agent edits rtl/ during a measurement] → the synth targets
  print `rtl <hash> @ <commit>`; a stage's before/after must share the
  hash modulo its own diff or the measurement is discarded.
- [iverilog use-before-declare count grows] → accepted; the iverilog flow
  was already broken at HEAD and Verilator is the gate of record.
- [Unpacked-array ports (`playing`, memories)] → avoided entirely:
  memories stay owned, `playing` crosses as a packed `play_bits` export
  plus in-module unpacked storage; no unpacked ports exist in the plan.

## Migration Plan

Stages land as ordinary commits on `psg-pico8-parity`, one stage per
commit, gates in the message. Pausing between stages leaves a working,
fully-gated tree at every point. Rollback of any stage is `git revert` of
one commit (no cross-stage entanglement by construction). When all stages
land, `docs/build-targets.md` gains a paragraph on the module map and the
TB bind convention; `openspec archive` closes the change.

## Open Questions

- Whether `psg_seq` (still ~1.2k lines after extraction) should split
  further (effect microprogram / slide detour / music flow as siblings).
  Deferred: decide after the census re-run on the modular build shows
  where the seams pay; a second-round change if warranted.
- Whether `psg_common.svh` should become a proper SystemVerilog package
  (`psg_pkg`). Deferred: `` `include `` matches the repo idiom and yosys
  handles it uniformly; a package buys namespacing this file set does not
  yet need.

## Measured ledger (2026-07-28/29, as landed)

Anchor: 14,012 cells / 1,583 flops, 7,224 placed LC, fingerprint
`226084c488ae`, oracle 59/59, psg_tb ALL PASS, 0 lint warnings x3
(commit `ff6c214`).

| Stage | Cells | Flops | Placed LC | Fmax | Oracle | psg_tb |
| --- | --- | --- | --- | --- | --- | --- |
| 0 prep respellings | 14,004 (-8) | 1,580 (-3) | 7,224 | 35.54 | 59/59 | PASS |
| 1 psg_timing | 14,000 (-4) | 1,580 | 7,208 | 36.65 | 59/59 | PASS |
| 2 psg_aram | 14,001 (+1) | 1,580 | 7,190 | 37.91 | 59/59 | PASS |
| 3 psg_mulsvc + psg_divsvc | 14,003 (+2) | 1,580 | 7,234 | 38.78 | 59/59 | PASS |
| 4 psg_state_mem | 14,004 (+1) | 1,580 | 7,224 | 38.18 | 59/59 | PASS |
| 5 psg_wave | 14,066 (+62) | 1,580 | 7,249 | 38.78 | 59/59 | PASS |
| 6 psg_walk | 14,086 (+20) | 1,580 | 7,268 | 38.10 | 59/59 | PASS |
| 7 psg_seq | 14,149 (+63) | 1,580 | 7,307 | 36.61 | 59/59 | PASS |

**Total: +137 cells (+0.98%), -3 flops, +83 placed LC (+1.1%). Fit
unchanged (21/32 EBR, 95% LC), routed Fmax 36.61 vs 37.90 MHz, both far
above the required 28.125. Every rendered sample byte-identical at every
stage.**

### D4 was wrong, and stage 1 is the proof

D4 assumed the pre-mapping cell census is invariant under a pure move
because `synth_ice40` flattens before mapping. It is not. Stage 1 moved
one self-contained process verbatim and the census moved by -4 (-5
`$_OR_`, +1 `$scopeinfo`): the timing block tests `scnt == 182` and
`scnt == 176` while the sequencer tests `scnt == 3`, and after the split
yosys shares five fewer terms between those comparator cones. Re-measured
with an explicit `synth_ice40 -flatten`: same numbers, so this is not
hierarchy retention - flattening restores the netlist but not the
optimiser's sharing ORDER.

The gate was re-stated (user decision, 2026-07-28): **flop count exact,
cell census banded, behaviour EXACT**. Flops exact is the gate that
actually convicts duplication, and it held at 1,580 through all eight
stages. The behavioural gates - 59/59 byte-identical WAVs and psg_tb -
never moved.

### What a boundary costs, by width

The two wide combinational boundaries account for essentially the whole
cost: `psg_wave` +62 and `psg_seq` +63, against -4/+1/+2/+1/+20 for the
other five. Both show the same signature - `$_XOR_` and `$_AND_` up,
`$__ICE40_CARRY_WRAPPER` down (-3 and -14) - which is a carry chain that
used to span what is now a port becoming gates. Narrowing `psg_wave`'s
ports to only the slices the cone reads (`s_phase[23:8]`,
`s_eff_inc[20:8]`, `old_q0[15:0]`) was measured and did NOT move the
census; the cost is the boundary, not the bit count.

The mul-merge spelling, measured three ways in stage 0 (the same
question, in-place): 40-bit selecting mux **+34**, if/else-if on the
bundles **+73**, bitwise OR **-8**. The OR is exact because the bundles
are disjoint (`walk_frozen` subsumes `prun`) and every arm writes its
operands with its start bit; a simulation assertion guards both halves of
that argument.

### Census attribution, the tooling payoff (task 9.3)

Grouping the flattened netlist by instance prefix, which is what the
split bought and what the monolith could not answer at all:

| instance | LUT4 | CARRY | FF | EBR |
| --- | --- | --- | --- | --- |
| `u_walk` | 2,172 | 498 | 658 | 2 |
| `u_seq` | 2,088 | 324 | 559 | 1 |
| `u_mul` | 651 | 156 | 61 | 0 |
| `u_wave` | 644 | 266 | 90 | 7 |
| `u_aram` | 334 | 78 | 65 | 9 |
| `u_state` | 202 | 0 | 37 | 2 |
| `u_div` | 110 | 42 | 45 | 0 |
| `u_timing` | 102 | 56 | 40 | 0 |
| `psg` (top) | 74 | 0 | 24 | 0 |
| harness | 18 | 0 | 1 | 0 |
| **total** | **6,395** | **1,420** | **1,580** | **21** |

Three things this says that the monolith's ranking could not:

- **the two walks are the design** - 4,260 of 6,395 LUT4 (67%) and 1,217
  of 1,580 flops. Area work that is not in `u_walk` or `u_seq` is
  rounding.
- **`u_mul` is 651 LUT4 for one 21x12 shift-add engine**, more than
  `u_wave`'s entire computed wave layer. The census ranked `m_a` and
  `m_p` first before the split too, but only now is it visible that the
  cost is the SERVICE rather than the arms its requesters build.
- **`u_wave` holds 7 of the 21 EBRs** for the three split-identity
  tables - a third of the block RAM budget for one third of the wave
  shapes. If the 15-EBR ceiling ever returns, this is where it binds.

### Open question resolved: no second-round split of psg_seq

Deferred in the original text pending this census. `u_seq` is 2,088 LUT4
/ 559 FF in one module - large, but splitting it further would add two
more wide combinational boundaries, and the two the change already paid
for cost +62 and +63 apiece. The effect microprogram, the slide detour
and the music flow all read the same working registers, so the seam is
not narrow anywhere. Not worth a second round at this price.
