# Handoff: the CPU→PSG write has no handshake

Written 2026-08-07, at the end of the session that took the Tang Primer 20K from
15.2 to 60.6 fps and the simulator from 42 to 58. Both platforms now have the
same single open defect, and it is the thing standing between the simulator and
correct live audio.

Everything else this session touched is closed and on the branch. Read
"What is NOT the problem" before starting — most of a session went into
eliminating candidates, and re-eliminating them is the expensive way to begin.

## The defect, exactly

An ordinary PSG register write is **not handshaken at all**.

`rtl/psg.sv` converts a level-style bus write into one pulse in the PSG's own
clock domain:

```systemverilog
logic cs_wr_q;
wire  cpu_stall;
always_ff @(posedge clk) cs_wr_q <= cs && rw && (cs_wr_q || !cpu_stall);
wire  cs_wr = (cs && rw) && !cs_wr_q && !cpu_stall;
assign rdy = !cpu_stall;
```

`cpu_stall` comes from the sequencer's CPU state-memory lane and is asserted
**only for migrated-register accesses**. For every other write it is 0, so `rdy`
never drops, the CPU does not wait, and the write is a one-CPU-clock level that
lands only if a `psgclk` edge happens to fall inside it.

That is safe exactly while `psgclk` is at least as fast as the CPU clock. It has
never been documented as a requirement, and both platforms have now violated it.

## The evidence, on both platforms

**Board** (`24dd7b3`). `DYN_SDIV_SEL` 32 → 8 put the chip clock at 14.0625 MHz
against `psgclk`'s 18.75 — 0.75 PSG clocks per chip clock. The picture was
correct at 60.6 fps, synthesis and place-and-route were clean, timing closed
with 2.3x of margin, every bench passed, and **the music stopped**. `/12`
(9.375 MHz, exactly 2:1) restored it. `make sdc-check` now fails below 2
complete PSG clocks per chip clock, so the constraint is enforced rather than
remembered — but the interface is unchanged and 2 is the floor, against the 5
the design was originally built around.

**Simulator** (this session, reverted). `psgclk` at half the core clock:

| | fps | audio |
| --- | --- | --- |
| `psgclk = coreclk` | 58.07 | 18,727 distinct levels, RMS 4127 |
| `psgclk = coreclk/2` | **71.7** | **1 distinct level, RMS 0 — silence** |

`psg_wav` cannot see this. It has no CPU, so it never exercises the crossing —
which is why the preview gate passes while the console is silent.

## Why it matters more than it looks

The simulator's live audio is correct only at **≥ 60.0 emulated fps exactly**:
the console emits `fps × 735` samples/s into a device draining 44100, and
`sim/console.cpp` discards a frame's samples when the queue is ≥ 66 ms deep. It
is at 58.4 (97.3%) after `85f5fb8`, so it still starves.

Halving `psgclk` measures **71.7 fps** and clears the threshold with room. The
PSG is **51% of simulator runtime** (ablation: PPU 14%, reverb not measurable at
all), and the preview renders *identically* at half the clock — 25/27 voiced
windows at both 159 and 79.5 clocks/sample, falling off a cliff to 1/27 at 53.
So the speed is available and the fidelity is free. Only this defect is in the
way.

The same fix would remove the board's `≥ 2 psgclk per chip clock` constraint,
which is today the only thing coupling its frame rate to its audio.

## Reproduce in about two minutes

```sh
# the working baseline: 18,727 distinct levels
make shot GAME=celeste FRAMES=1
build/obj_dir/console --sym build/celeste.sym --headless --frames 300 \
  --audio-wav /tmp/ok.wav

# the failure: add `parameter int PSG_CLK_DIV = 1` to rtl/top_simulator.sv,
# divide psgclk by it, scale CLK_HZ by it, build with -GPSG_CLK_DIV=2.
# Then the same run gives 1 distinct level.
python3 - <<'PY'
import struct, wave, statistics
w = wave.open('/tmp/ok.wav'); n = w.getnframes()
d = struct.unpack('<%dh' % n, w.readframes(n))
print(len(set(d)), 'distinct, RMS', round(statistics.pstdev(d)))
PY
```

## Two fixes that do NOT work

Both were implemented, measured and reverted. Do not spend the session
rediscovering them.

**1. CPU wait-states on a PSG access.** Hold the core for N extra clocks so the
access spans a `psgclk` edge. It cannot work as written, and the reason is
already documented in `psg.sv` for a different signal: **the 65C02 gates WE with
RDY**. A stalled write drives WE low, so `cs && rw` is false for the entire
window the stall creates. Stalling to make the write land is precisely what
stops it landing.

**2. Building `cs_wr` from `rw_pend`.** `rw_pend` is the core's ungated write
intent, already routed to the PSG for `rd_lvl`'s version of this same trap
(`4620a5b`), and it survives the stall. `cs_wr` is edge-detected, so the "never
drive a write enable from `rw_pend`" warning does not apply. Measured: inert at
`div=1` — audio byte-identical, so it is not a regression — and **still silent**
at `div=2`. Something further is dropping the access.

## Where to look next

Instrument the **`$4102` audio-image upload** before anything else. It is the
highest-traffic write in the system, a corrupt image is exactly silence, and it
distinguishes the two hypotheses that remain: *every* write drops, or the image
never arrives. That decides whether the fix belongs in the strobe, in
`memory_arbiter`, or in the DMA path.

`psg_wav --wr-hold 2` reproduces the mirror-image corruption standalone (the
2026-07-30 double-write bug) and is worth keeping in mind as the opposite
failure mode.

## What is NOT the problem

Each of these was measured this session and is a dead end:

- **Preview fidelity.** `tools/psg_preview_check.py` on Celeste music 0 passes
  at 25/27 voiced windows (93%, needs 85%), RMS 88.7%, activity 99.6%. The
  "today 2%" finish-line figure in `psg-preview-handover.md`'s gate list is
  stale.
- **The sequencer-shrinking plan** in that same document. Retired at the top of
  the file by its own author, and its budget arithmetic predates the fixes — it
  says the preview cannot render at 159 clocks/sample, and the gate passes.
- **Verilator threading.** `--threads 2` is **14x slower**, `--threads 4` is
  **51x slower**. The model is fine-grained and thread synchronisation swamps
  it.
- **C++ optimisation flags.** `-O3 -march=native` over `-O2`: no change.
- **`eval_step`/`eval_end_step` splitting** to amortise Verilator's end-of-eval
  bookkeeping: no change. That bookkeeping appeared in a profile because it was
  the *idle worker thread*, not the model — beware, `sample` aggregates threads
  and will mislead you the same way.
- **The reverb ring.** `REVERB(0)` is not measurably faster in simulation.

## Gates that must pass

```sh
python3 tools/psg_oracle_bytecheck.py     # must print byte-identical 59/59
make test-celeste GAME=celeste            # incl. its PSG command-trace hash
make test-lcd                             # RGB444 + RGB565 at three dividers
make test-palette
make sdc-check                            # the board's psgclk:cpuclk floor
```

`make test-psg` is recorded as having been dead since the PSG module split
(iverilog rejects `psg.sv`'s declare-after-use, and `|| true` lets a stale
`.vvp` print verdicts belonging to neither HEAD nor the tree). **That has not
been re-verified this session** — check it before trusting its output.

## Other loose ends on this branch

- **The Primer's two keys are unverified.** `key1` (T10, `btn_n0`) is `$4007`
  bit 5 (X) and `key2` (T3, `btn_n1`) is bit 4 (O / PICO-8's C). Which
  silkscreen legend sits above which ball is not something the RTL can know, and
  this board already disagrees with itself elsewhere — its LEDs are silkscreened
  LED4/LED5 where litex calls the same two led0/led1. If they read backwards,
  swap them in `top_tangprimer20k.sv` and nowhere else.
- **The Tang Nano is untested on hardware** and shares `pll_gowin.v`, so it took
  the 32 → 12 divider change too. It stays at `SPI_HALF=3` and RGB565, which are
  valid at 12:1, but nothing has been loaded onto it.
- **`CLAUDE.md` is untracked** and was so before this session.

## The branch

`boards-tangprimer20k`, seven commits ahead of the session start:

| | |
| --- | --- |
| `c8a83e5` | palette: white was red — `chip` loaded a 24-bit ROM into RGB565 |
| `5c87a70` | 15.2 → 60.6 fps; the compositor was never the constraint |
| `24dd7b3` | the chip clock has an upper bound too, and the PSG sets it |
| `bf3a4ba` | the Primer's two keys swapped |
| `2019fbc` | board targets never ran Celeste's Inlay frontend |
| `85f5fb8` | the model's input clock was a divider nothing needed — 42 → 58 fps |
| `d1589a7` | the preview's problem is starvation, not fidelity |

Verified on hardware: 60.6 fps, correct geometry and colour, Celeste running
with music.
