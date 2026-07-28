# Tasks: refactor-psg-modules

Gate battery (referenced by every stage below as "gates"): (1) structural
stat with the FLOP COUNT exactly equal to the previous stage's and the
cell delta measured and accounted for; (2) `make synth-psg` placed LC
measured against the 7,224 anchor, fits, routed Fmax ≥ 28.125 MHz,
fingerprint recorded; (3) oracle 59/59 byte-identical vs
`build/psg_oracle/adopt-exact/rtl`; (4) `psg_tb` ALL PASS with the
header's command (`-Irtl`, no `-Wno` suppressions); (5) zero Verilator
warnings in psg_tb / standalone / REALTIME_PREVIEW=1 configs.
One stage per commit, gates quoted in the message.

REVISED AT STAGE 1, and design.md's ledger carries the evidence: gate 1
was written as cell-IDENTITY. It is not achievable, not even for a pure
verbatim move - stage 1 moved one self-contained process and the census
moved -4 because comparator cones stopped sharing terms across the new
boundary, and an explicit `synth_ice40 -flatten` reproduces it. Gates 3,
4, 5 and the flop count are exact and are what convict a real change;
the cell census and placed LC are recorded, not equated. User decision,
2026-07-28.

## 1. Stage 0 — in-place prep (single module, respellings allowed)

- [x] 1.1 Extract `rtl/psg_common.svh` (include-guarded): `NV`/`VW`/`NCH`,
      record-layout localparams, `is_mus`, the `PSG_REC_*`/`PSG_OSC_*`
      macros; `psg.sv` consumes it via `` `include ``
- [x] 1.2 Respell `aud_sl()` to take an explicit packed `play_bits`
      argument; add the packed `play_bits` export next to `playing`;
      convert the CPU read mux and `dbg` block to the new signature
- [x] 1.3 Respell the multiply-request mux as two request bundles (walk,
      sequencer) merged with today's priority; verify the branches stay
      disjoint (`walk_frozen` subsumes `prun`)
- [x] 1.4 Respell the `state_m` port selection as two owner bundles (walk;
      engine/tick) under the existing fixed priority, keeping the single
      read site and single write site
- [x] 1.5 Run gates; iterate any respelling until cell-identity holds;
      commit stage 0

## 2. Stage 1 — psg_timing

- [x] 2.1 Create include-guarded `rtl/psg_timing.sv`; move the divider /
      `scnt` / `tick_en(_d)` / `tick_hold` / `pre_tick` / `sample_en`
      process verbatim; instantiate as `u_timing`; wire existing names
- [x] 2.2 Confirm psg_tb binds to `sample_en` / `tick_en` / `pre_tick`
      still resolve at top-level interconnect (no re-pointing expected)
- [x] 2.3 Run gates; commit stage 1

## 3. Stage 2 — psg_aram

- [x] 3.1 Create `rtl/psg_aram.sv`: `aram[]`, `wraddr`, upload writes, the
      read register (`seq_q`), borrow/replay (`replay`, `last_addr`,
      `seq_frozen`); inputs `seq_addr`, `syn_rd`/`syn_addr`, CPU strobes
- [x] 3.2 Run gates; commit stage 2

## 4. Stage 3 — psg_mulsvc and psg_divsvc

- [x] 4.1 Create `rtl/psg_mulsvc.sv` around `m_a`/`m_p`/`m_cnt`/`m_mode`
      taking the stage-0 merged request bundle; outputs `m_res*`,
      `m_busy`
- [x] 4.2 Create `rtl/psg_divsvc.sv` around `d_*` taking the sequencer's
      divide request; outputs `d_res`, `d_rem`, `d_busy`
- [x] 4.3 Run gates; commit stage 3

## 5. Stage 4 — psg_state_mem

- [x] 5.1 Create `rtl/psg_state_mem.sv`: `state_m[]`, `state_q`,
      `state_replay`, the two-owner priority mux from stage 0; verify the
      SB_RAM40_4K inference is unchanged in the synth log
- [x] 5.2 Re-point psg_tb's `state_m` binds (incl. `eff_vol_of` /
      `eff_inc_of` peeks and the VSTR stride localparam source) to
      `dut.u_state`
- [x] 5.3 Run gates; commit stage 4

## 6. Stage 5 — psg_wave

- [x] 6.1 Create `rtl/psg_wave.sv`: the `wx`/`wsel`/`wsec` issue pipeline,
      stage-1/stage-2 cones, `org3`/`tab7`/`tab15` and read registers,
      `z_lin`/`z_prim`/`z_eval`, `dq17`, `q16`; parameter
      `REALTIME_PREVIEW` threaded
- [x] 6.2 Run gates; commit stage 5

## 7. Stage 6 — psg_walk

- [x] 7.1 Create `rtl/psg_walk.sv`: `prun`/`pph`/`pc_ch`, `lfsr`, all
      streaming `s_*`/`old_*`/`last_*` state, mixer staging, phase ALU,
      fold engine, `dry16`/`dry_valid`, `clr_ack`, ctrl-ROM generate,
      ring generate (`REVERB`, `REALTIME_PREVIEW` threaded); emits the
      walk `state_m` bundle, walk mul requests, `syn_rd`/`syn_addr`,
      `fold_busy`
- [x] 7.2 Re-point psg_tb's `fmc`, `prun`-adjacent and `dry_valid` binds
      that move (`prun`/`dry_valid` stay top-level; `fmc` moves to
      `dut.u_walk`)
- [x] 7.3 Run gates; commit stage 6

## 8. Stage 7 — psg_seq

- [x] 8.1 Create `rtl/psg_seq.sv`: the sequencer FSM process with its
      tasks, working registers, `playing`/`play_bits`, `trig_req`,
      `sfx_id`, `launched`, `released`, `trg_*`, `aud_row`, music flow
      and fades, `clr_tog`, `spar_bank`, `crom[]` + `pinc_addr` +
      `crom_q`, effect operand tables, slide detour, engine/tick
      `state_m` bundle, sequencer mul/div requests, `seq_addr` muxes,
      CPU control writes
- [x] 8.2 Re-point remaining psg_tb binds (`sst`, `playing`, `trig_req`,
      `sfx_id`, `launched`, `mus_*`, `bank_ready`, `spar_bank`, `crom`)
      to `dut.u_seq`
- [x] 8.3 Run gates; commit stage 7

## 9. Stage 8 — top cleanup and close-out

- [x] 9.1 Reduce `rtl/psg.sv` to header comment, includes, top module
      (ports, `walk_frozen` aggregation, CPU read mux, `dbg`, wiring);
      verify no dead declarations remain
- [x] 9.2 Sweep psg_tb's full bind inventory against the final module map;
      run gates one final time; commit stage 8
- [x] 9.3 Re-run `tools/psg_ff_census.py` on the modular build and record
      the per-instance family/cone ranking in the change's design.md
      ledger (the attribution payoff, and the seed for any second-round
      split decision)
- [x] 9.4 Add the module map + TB bind convention to
      `docs/build-targets.md`; update the PSG memory ledger; ready the
      change for `openspec archive`
