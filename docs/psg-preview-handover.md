# Handover: make the PSG's preview path fit the console's clock

Goal: retire `PSGSIMDIV = 2` from `rtl/top_simulator.sv`, so `make run` gets
correct audio at ~80 fps instead of correct audio at 46 fps.

> **Resolved (2026-07-30).** The claimed ~230-clock correctness threshold and
> the 159-clock amplitude collapse below were build artifacts, not PSG
> behaviour. The clock-specific `psg_wav` targets depended on `rtl/psg.sv` but
> not the nine implementation files it textually includes. Consequently the
> 159- and 1275-clock object directories could contain different revisions of
> the supposedly clock-independent datapath. The original collapsed
> `/tmp/d159.wav` came from such a stale executable; a fresh 159-clock build is
> full-level and passes 40/40 voiced pitch windows. A direct `sample_en` trace
> from `psg_budget_tb` is also sample-for-sample identical to `psg_wav`, ruling
> out renderer sampling phase.
>
> The Make targets now depend on every included PSG source, and
> `PSGSIMDIV = 1` runs the preview PSG on the core clock. A 300-frame Celeste
> headless run measured 58.59 fps with full-range audio. The sequencer-shrinking
> plan below is retained only as historical context and should not be executed.

> **Correction (2026-07-30).** "Correct audio at 46 fps" was not true when this
> was written. The clock split it describes made the CPU run at *half* the PSG's
> rate, and every write consumer in the chip acted on `cs && rw` as a level in
> the PSG's domain - so each store executed **twice**, the upload port advanced
> its address by two per byte, and the cart's audio image landed in alternate
> bytes of `psg_aram`. `make run` played a corrupted image of Celeste's music
> while the source blob was byte-exact, the 59-case oracle was byte-identical,
> and `psg_wav` (one clock domain, one clock per write) rendered perfectly.
> Fixed by strobing the write in `rtl/psg.sv`; the oracle stays 59/59.
>
> Nothing could see it because nothing could hear the console: `psg_wav` has no
> CPU and no game, and the oracle builds `REALTIME_PREVIEW=0`. The console now
> dumps its own audio - `build/obj_dir/console --audio-wav out.wav` - and
> `tools/p8_music_wav.py` records real PICO-8 for a whole track to diff it
> against, via `tools/psg_ref_check.py`. Use those on any audio claim about
> `make run`; the `--audio-trace` distinct-level/effective-bit numbers this doc
> cites as a gate read as HEALTHY throughout the corruption (15.3 bits, 40k
> levels) and cannot be used to tell correct audio from garbage.

Prior work: `c8a2007` (the preview gate), `6f9429b` (five preview bugs, hardware
bit-identical), `64dbc0a` (the clock-split stopgap and the numbers behind it).

## The budget, and why the walk is finished as a target

The console supplies **159** PSG clocks per 22050 Hz sample. Celeste's music needs
**~230** to render correctly — bisected against a swept `-GCLK_HZ` (right at
230/260/290, wrong at 210 and below).

The demand is **not** a per-sample rate. The tick program runs inside the
six-interval pre-run window (`rtl/psg_timing.sv`: `pre_tick` at `scnt == 176`, tick
at `182`), so the real inequality is

```
6 x (159 - walk_cost)  >=  tick_job_clocks
```

With the walk at 85 that supplies `6 x 74 = 444` against Celeste's **~708**.

The walk is no longer where the headroom is:

| variant | slot phases | Celeste walk | free/sample | supplied | need |
| --- | --- | --- | --- | --- | --- |
| today (`6f9429b`) | 24 | 85 | 74 | 444 | 708 |
| + drop 2 dead oscillator words | ~20 | ~73 | 86 | 516 | 708 |
| + per-slot register file | ~9 | ~40 | 119 | 714 | 708 |

Everything still available to the walk lands at ~40 clocks and clears 708 by **six**
— and a cart sounding more voices than Celeste's three misses. That is why the
target is the **sequencer's 708**, not the walk's remaining 45.

## What to attack

`psg_seq` spends ~0.1% of the chip's clocks on ~33% of its LUT4s — exactly backwards
for a simulator, and the reason its microprogram is serial is FPGA area, which
simulation does not pay for. Per-tick occupancy (from `rtl/psg_budget_tb.sv`, written
up in `docs/hardware-gaps.md`):

| stage | clocks/tick | note |
| --- | --- | --- |
| record streaming `V_LD`/`V_ST`/`K_ROT` | **125** | largest single consumer — start here |
| effect microprogram `K_PF0`/`K_FX` | 58 | |
| slide detour `K_SL0..8` | 38 | includes exact divides |
| publication `P_W*`/`PC*` | 36 | |
| note fetch `T_*`/`K_*` | 17 | |
| tick engine `EA*`/`ES*` | 12 | |
| music flow / instrument | 1.7 | |

Record streaming alone is ~18% of the job. It is a word-at-a-time walk over a slot's
record through one memory port; in preview the same words can be moved in parallel,
or the streaming collapsed where the destination is a register the sim can just
write.

## The pattern that has worked twice

Both wins in `6f9429b` were the same move — un-serialise what area forced serial,
behind `if (REALTIME_PREVIEW)`, then *prove* equivalence:

1. Put the change behind the parameter so the hardware lowering is dead-code
   eliminated. `REALTIME_PREVIEW` is 0 for every synthesised top and for the oracle.
2. **Prove the arithmetic byte-identical**, do not eyeball it. The combinational fold
   was validated by rendering with the slot skip disabled — a configuration where the
   serial engine cannot be aborted — and byte-comparing 88,200 samples against the
   serial engine. Find the analogous "no behavioural difference possible" setup for
   whatever you serialise, and diff.
3. Re-run the gates below after **each** step, not at the end.

## Gates (all of them, every step)

```sh
# 1. hardware untouched - the one that matters most
python3 tools/psg_oracle_bytecheck.py          # see "tooling debt" below
#    must print: byte-identical 59/59

# 2. the preview plays the right tune (correctness, generous clock)
make test-psg-preview CART=~/Stuff/carts/celeste-15133.p8.png
#    must stay >= ~95% window agreement

# 3. does it FIT yet - the actual objective
make -s build/obj_psg_pv_3506580/psg_wav PSG_PV_CLK=3506580
python3 tools/psg_preview_check.py --cart <cart> --music 40 --mask 7 \
  --preview build/obj_psg_pv_3506580/psg_wav --preview-clk 3506580
#    today 2%; this reaching ~95% is the finish line

# 4. lint, both flavours, zero warnings
verilator --lint-only rtl/psg.sv --top-module psg -Irtl -Wno-DEFOVERRIDE
verilator --lint-only rtl/psg.sv --top-module psg -Irtl -Wno-DEFOVERRIDE -GREALTIME_PREVIEW=1
#    rtl/top.sv reports 43 warnings at HEAD - that is a pre-existing baseline

# 5. the console itself
make run GAME=celeste                 # or --headless --frames 300 for fps + audio stats
#    silent = 1 distinct level; scrambled phase = ~12k; correct = ~33k / 15.0 bits
```

Instrument with `rtl/psg_budget_tb.sv` — it already computes `max_tick_job_clocks`,
`tick_window`, `late_flips` and `walk_own/samples`, and takes `-GCLKHZ_P=`. Build it
at `REALTIME_PREVIEW=1` and read Celeste's `max_tick_job_clocks` directly rather than
inferring 708 from the clock sweep. Add two counters worth having: dropped samples
(`sample_en && (prun || fold_busy)`) and coalesced ticks (`pre_tick && tickpend`).

## Invariants you must not break

- **`psg_state_mem` is 1R1W with the walk at absolute priority**
  (`state_ra = wlk_rd ? wlk_ra : etk_ra`, and `state_we` is the OR while address/data
  mux to the walk). An etk write coincident with a walk write is **lost, not
  stalled** — which is safe only because every sequencer request is gated on
  `!walk_frozen`. Do not add a sequencer access that can race a walk write.
- **`walk_frozen = seq_frozen | prun | state_replay | fold_busy`** (`rtl/psg.sv`),
  and `state_replay <= prun` unconditionally. The freeze is a function of `prun`, not
  of the read/write window — so vacating the memory port buys the sequencer
  **nothing**; only shortening `prun` or shortening the tick job does.
- **Word ownership is clean and worth preserving.** Oscillator words 10..23: walk
  reads and writes, sequencer never touches them (`etk_wa`/`etk_ra` only ever reach
  {0..9} ∪ {24..31} ∪ {32}). Parameter banks 24..31: sequencer writes, walk reads,
  double-buffered via `spar_bank`. Tick words 0..9 and word 32: sequencer only.
- **`tickpend` is a single bit.** A tick program that overruns into the next tick's
  window causes ticks to be **coalesced** — rows silently dropped. That is the cliff
  behind the 210/230 boundary, and it is what "the music renders wrong" looks like.
- **`soft_add` is not associative.** PICO-8's pairing order — `(0+1)(2+3)(4+5)(6+7)`,
  then `(0+2)(4+6)`, then `(0+4)` — is behaviour. Zero leaves must be fed in.

## Traps that have already cost time here

- **A model must be driven at the clock it was compiled for.** `sim/psg_wav.cpp`
  mirrors the divider in C++; `--clk` disagreeing with `-GCLK_HZ` detunes it into
  silence, which looks exactly like a synthesis bug.
- **Correct and fits are different questions.** Rendering preview at 159 conflates
  them; a bisect was wasted before separating them. Always check the generous clock
  first.
- **`pre_tick` widening does not work, despite the file's own comment.** Swept
  176/150/120/90/60/30 (up to ~153 intervals, far past 708 clocks): the render changed
  in detail at every value and stayed wrong. Do not spend the CPU-write-latency cost
  on it without a `tickpend` coalescing count proving it is the constraint.
- **Registers replacing memory need explicit init.** `rtl/psg_walk.sv` says streamed
  fields deliberately have no reset mux *because `state_m` supplies them*, and
  `psg_state_mem.sv` has an `initial` loop so X cannot leak into `psg_wave`.
  `--x-initial fast` hides a violation; iverilog would not.
- **Deleting a register is not the same as deleting its memory traffic.** `old_q0` is
  an output port to `psg_wave`; dropping its load leaves it undriven and breaks the
  zero-warning gate.

## Tooling debt worth clearing first

- **`make test-psg` has not run since the module split.** `iverilog` fails on
  `rtl/psg.sv:192` (`state_sample_read` used at 192, declared at 226 —
  declare-after-use, which Verilator tolerates), the rule lacks `-I rtl`, and its
  trailing `|| true` swallows the failure so `vvp` runs a **stale `build/psg_tb.vvp`
  dated 27 Jul** and prints a verdict belonging to neither HEAD nor the tree. It
  reported "8 TEST(S) FAILED" during this work and that meant nothing. Fix: move the
  declarations above the instantiation, add `-I rtl`, drop the `|| true`.
- **The oracle byte-check is not in the repo yet.** `tools/psg_oracle_matrix.py`
  re-exports the PICO-8 reference unless the file already exists, so it cannot run
  headless (`TimeoutError: PICO-8 produced no WAV`). What gates hardware is a plain
  render-and-byte-compare against the frozen `build/psg_oracle/adopt-exact/rtl` set,
  which needs no PICO-8. Promote it to `tools/psg_oracle_bytecheck.py`.

## Still open

**Bug 5: the secondary/detune voice never reaches the mixer on the computed-wave
path.** Preview captures `smp_a`/`smp_b` at `PWORK+1`/`+2`, both the MAIN context,
while `iss_sec` fires at `PWORK+1` and `psg_wave`'s 2-stage cone makes its result
valid at `PWORK+3`. The wavetable path is correctly timed (aram is issue→+1, the cone
is issue→+2), so **moving the captures would desynchronise it** — move `iss_sec` to
`PWORK` and the `s_phase2` advance with it instead, which aligns both at +1/+2. Tie
`iss_om`/`iss_os` to 0 for preview; nothing reads `z_eval` at `PWORK+3/+4` there.
This is the one change whose preview diff is *intended* to be non-zero, so do it once
the phase layout has stopped moving.

## If the sequencer route stalls

Fall back to the walk's register file (~40 clocks, clears 708 by six, no margin for
heavier carts), or simply keep `PSGSIMDIV = 2` and accept 46 fps with correct audio.
Do not delete the clock-split path either way — it is a one-line knob and the honest
fallback for content the compact schedule cannot serve.

The oscillator **word repack** (7 → 5 words; `s_lp` is stored and never loaded,
`s_nz_hold` is loaded and stored but never read by any datapath in either schedule)
buys only ~2 clocks per slot and requires renumbering a non-contiguous set
(words 0, 2, 3, 4, 6) across both the store map and the load arms — the exact class
of pack/unpack drift that scrambled the phase in `5bdead3`. If you do it, give
preview its own mirrored macro pair in `rtl/psg_common.svh` beside
`PSG_OSC_W14/17/22` so pack and unpack cannot drift. Worst risk-per-clock item
available; do it last or not at all.
