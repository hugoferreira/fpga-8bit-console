# Handover: close the noise fidelity gap

Goal: make wave-6 noise match real PICO-8 statistically. It is close and it is
not there. The gap is audible — a listener described it as "the high pitch noise
is higher in our implementation", and as vertical lines in a spectrogram that
PICO-8 does not have.

Prior work: `a09d8a6` (the bounded random walk, derived), `9de52e9` (four derived
corrections), `c9efd38` (the fidelity gate), `dec5b8c` (metrics that withhold
themselves on unpitched material).

## Where it stands

`make test-psg-fidelity` PASSES with a recorded KNOWN GAP. Also green: the
regression gate at 59/59, the preview gate at 40/40, zero lint warnings in both
flavours.

Celeste's track 30 is the audible case — one noise voice whose pitch sweeps
50 → 12 → 52, so the sweep IS the sound:

| | level | held-note wander | contour (loud/timbre) |
| --- | --- | --- | --- |
| unpitched noise (the original bug) | 0.49x | 4.33x | 0.619 / 0.116 |
| fitted one-pole | 0.83x | 3.26x | 0.909 / 0.948 |
| derived walk | 1.00x | 2.30x | 0.995 / 0.983 |
| + the four corrections (HEAD) | 1.00x | 2.15x | 0.995 / 0.983 |

## What is established

Noise is a **jittered, bounded random walk** (the vendor's PSG notes in the
PICO-8 app bundle call it the legacy mode, and the disassembly they cite
confirms a plain wave-6 note with no filter bits takes it — the mode field is
the OR of two bits, and only a non-zero mode plus a global counter at 12
promotes it to the interpolated mode):

- the step is taken on ALTERNATING samples, gated by a toggle in the state
- its magnitude tracks the phase increment, `J = 8*dp + 1120` for the playable
  range, with `dp = einc >> 8`
- a full-range kick is added when a phase-derived test passes, at a rate rising
  with the increment (~3% of samples at pitch 4, ~27% at pitch 60)
- the accumulator is clamped to +-6143 **in the state**
- the OUTPUT is taken from the accumulator BEFORE that clamp, then scaled by
  `G * k / 2048` with `k = 80` below pitch 48 and falling above it

That last line is the one that unlocks the whole thing. Clamping first caps the
output near 9975 where PICO-8 measurably reaches 24641, and it explains what
looks contradictory for as long as you assume otherwise: PICO-8 is
simultaneously LOUDER and LESS SATURATED than any clamped model, because the
bound holds the stored state while a kick landing on an already-large
accumulator escapes through the output on that sample.

Sample-exactness is **not reachable** and is not the target: PICO-8's RNG is
shared across voices, so even a muted noise voice perturbs what the others
produce. The gate measures statistics and their pitch dependence instead.

## The residual, characterised

Our walk's spectrum is **too white**. Three measurements say it:

- PICO-8 repeats a consecutive output sample 10..29% of the time; we repeat
  0.4..2.8%. Its walk HOLDS between steps; ours changes almost every sample.
- Rail occupancy runs 0.1% → 13.3% across the pitch sweep for PICO-8 and only
  1.5% → 2.9% for us. Its step has a far steeper pitch slope than `8*dp + 1120`
  produces here.
- Energy above 4 kHz is 2.0..2.3x PICO-8's share, below 200 Hz it is 0.89x.
  Held-note wander reads 1.55x against a calibrated target of 1.35x.

Separately, our noise carries ~102 narrow spectral peaks against PICO-8's 30,
the shared ones 2-4x stronger. The 15-bit LFSR is too short and too structured
to sound like noise; PICO-8 draws from 64 bits of state.

## The map: every lever trades one metric for another

This is why the obvious fixes are not in the tree. Each was built, measured, and
reverted.

| change | what it fixes | what it breaks |
| --- | --- | --- |
| second co-prime generator | peaks 102 → 17 | centroid 1.29 → 1.67, wander 2.25x |
| clamp widened 2x | centroid 0.98..1.08 | rms trend collapses to 0.66 |
| step every 4th sample | centroid 1.01..1.06 | wander 2.72x at volume 7 |
| step x 11/16 | — | volume-1 wander 2.27x |
| `dp` scale doubled | centroid 1.02 at high pitch | per-pitch rms fails widely |

**The trap in row one.** A PERIODIC noise scores BETTER on held-note wander,
because repeating content varies less between windows. Part of HEAD's 1.55x is
tonality, not stability, so that metric alone would prefer the worse-sounding
build. Do not optimise wander in isolation.

## Refuted — do not re-run

- kick gated on the phase, slice XOR and xorshift-mixed: both WORSE (2.19x,
  3.10x). A slowly advancing phase makes a weak hash LATCH.
- kick magnitude scaled by amplitude: no change to the centroid excess.
- kick disabled entirely: changes the band ratios by 0.02 and wander by 0.04.
  The kick is not involved in any of this.
- decorrelated step draws alone: worse (the walk advances the LFSR once per
  SLOT, and skipped slots advance it too, so draws were already ~8 apart).
- 12-bit draw resolution: worse than 8.
- step magnitude halved: overshoots (low band 1.43x, HF 0.68x).
- two `noise_filt_step` call sites firing per sample: they are in different
  schedule arms, only one is live.

**A Python model of the walk MISPREDICTS.** It said the deterministic toggle and
the `+1120` floor would improve wander; in RTL they did the opposite at first,
because the model assumed one LFSR advance per sample. Measure the RTL.

## What I would do next

Establish how PICO-8's walk produces its HOLDS, by reading the noise output path
in the disassembly rather than inferring it from the notes. Everything above says
the missing ingredient is qualitative — no single scalar reproduces both the
holds and the level rise — and the holds are the one behaviour whose mechanism I
took from the prose instead of the listings.

The rail-occupancy slope is the sharpest clue: whatever sets the step must grow
much faster with pitch than `8*dp` does, while staying SMALLER than ours at the
bottom of the range.

## Gates

```sh
make test-psg-fidelity          # statistics + their pitch dependence, vs PICO-8
make test-psg-fidelity RECORD=1 # re-capture the reference (needs PICO-8, real time)
python3 tools/psg_oracle_bytecheck.py   # REGRESSION only - we vs our frozen renders
make test-psg-preview CART=~/Stuff/carts/celeste-15133.p8.png
verilator --lint-only rtl/psg.sv --top-module psg -Irtl -Wno-DEFOVERRIDE
verilator --lint-only rtl/psg.sv --top-module psg -Irtl -Wno-DEFOVERRIDE -GREALTIME_PREVIEW=1
```

`psg_oracle_bytecheck` compares us against frozen renders of OUR OWN RTL. Green
means "nothing changed", never "matches PICO-8" — that is how unpitched noise
survived every change. A deliberate noise change makes `wave-6-noise` differ;
re-freeze it only after `test-psg-fidelity` says the change is right.

The fidelity gate carries two thresholds. Above 1.35x it prints KNOWN GAP and
does not fail, because a permanently red suite gets muted and then ignored.
Above 1.70x it FAILS. **Do not raise the guard to make a change pass** — lower it
when a change earns it.

## Tooling

- `tools/psg_ref_check.py ref.wav cand.wav [--spectrogram]` — a whole track
  against a PICO-8 recording. On unpitched material it WITHHOLDS pitch and lock
  (neither can succeed without PICO-8's RNG) and reports contour instead.
- `tools/p8_music_wav.py --image <4608-byte image>` — record a CONSTRUCTED probe
  from real PICO-8, one assumption at a time.
- `build/obj_dir/console --audio-wav out.wav` — what `make run` actually plays.
  `--audio-trace`'s distinct-level and effective-bit numbers cannot tell a tune
  from garbage; they read healthy through total corruption.
