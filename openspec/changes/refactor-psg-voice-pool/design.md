# Design: sixteen-voice PSG

## Context

The PSG today has four physical channels. Each is a slot in a set of `[0:3]`
arrays that are **rotated** every sample: the pipeline always works on index 0
and shifts the ring round after each channel (`rtl/psg.sv`, states `pst 0..3`
and the `K_ROT` rotation in the sequencer walk). That structure is why the
per-channel state is cheap to *address* and expensive to *hold*: every bit is a
flip-flop with a rotation mux.

## The two budgets

**Cycles.** There are two clocks here and they differ by 7x, which is easy to
get wrong: `psg.sv`/`chip.sv` default `CLK_HZ` to 3 506 580, but that default is
only what the *simulator* uses (`rtl/top_simulator.sv` instantiates `chip`
without the parameter). On hardware `rtl/top.sv` passes
`BOARD_CLK_HZ = 25_000_000` and `masterclk` is the board pin straight through,
so the real PSG runs at 25 MHz.

Per voice today: 1 clock each for phase advance, main-voice fetch and
second-voice fetch, then 9 waiting on the 8-cycle shift-add sample x volume
unit and accumulating - about 12 clocks.

| | clocks/sample | 4 voices (48) | 16 voices (192) |
| --- | ---: | ---: | ---: |
| hardware, 25 MHz | 1134 | 4.2% | **16.9%** |
| simulator, 3.51 MHz | 159 | 30.2% | **120.7%** |

So **sixteen voices already fit on hardware** with the serial multiply exactly
as it is - the cycles were never the obstacle there. What does not fit is the
simulator, whose console runs about 7x slower than the board because it ties
the video and master clocks together (`rtl/top_simulator.sv` derives the pixel
clock by dividing the one clock it has, where hardware has a separate
`videoclk`). `CLK_HZ` cannot simply be raised to compensate: it is what divides
down to 22 050 Hz, so a wrong value detunes the audio.

That leaves two ways to make the simulator keep up, and the cheap one is worth
doing anyway: replace the 8-cycle serial multiply with a single-cycle 8x8
multiply (~60 LCs on iCE40, or a DSP block on UP5K). A voice then costs about
5 clocks, 16 voices cost 80, and the pool fits in both budgets - 7.1% on
hardware, 50.3% in simulation. The alternative, giving the simulator its own
video clock so its master clock can run at hardware speed, is a larger change
to the simulator and out of scope here.

**Headroom in reserve.** The iCE40HX8K has two PLLs and this design currently
uses neither: `rtl/pll.v` (25 -> 50 MHz) exists but is not instantiated
anywhere. If the pool ever does run short of clocks, or if the fractional
sample-rate accumulator's jitter becomes audible, a PLL can give the PSG its
own faster - or exactly divisible - audio clock. That would cost a clock-domain
crossing on the CPU register interface and the audio-RAM upload port, which is
why it is held in reserve rather than taken now: nothing in this change needs
it.

**State.** 336 bits per voice today:

| voices | flip-flops | share of an HX8K's 7680 LCs |
| ---: | ---: | ---: |
| 4 (today) | 1 344 | 17.5% |
| 8 | 2 688 | 35% |
| 16 | 5 376 | **70%** |

70% for the PSG alone is not viable alongside the PPU, the sprite compositor
and the CPU. This — not the cycle count — is the actual obstacle.

## Anything clocked by the system clock is a hazard

Found while shortening the multiply: the noise LFSR advanced once per *system
clock*, so its rate was whatever the per-voice pipeline happened to cost. Take
7 clocks out of a voice and the noise changes; go from four voices to sixteen
and it changes again. Nothing said so - the tests passed and only a
render-to-render comparison showed it.

It now steps once per voice per sample. The general rule for the rest of this
change: **no audible state may be clocked by the system clock.** Everything
must be driven by the sample tick or the voice walk, or it will not survive the
voice count changing. `brown` (the brown-noise integrator) and the `rev_ttl`
echo counter are the other things to check against this rule before section 3.

## Key decision: partition voice state by rate

The 336 bits are not all touched at the same rate.

Measured exactly (task 2.1), not estimated:

**Per-sample state - 147 bits/voice.** Touched by the synthesis pipeline every
one of the 22 050 samples per second: `phase`(24), `phase2`(24), `eff_inc`(24),
`lp`(16), `brown`(13), `snd_wtb`(13), `eff_vol`(8), `nz_hold`(8), `nz_ph`(4),
`snd_wave`(3), and the single bits `playing`, `snd_wt`, `ch_noiz`, `ch_buzz`
plus `ch_det`/`ch_rev`/`ch_damp`(2 each). 16 x 147 = 2352 flops, 31% of an
HX8K. This stays in registers - streaming it from BRAM would need ~10 word
reads and 10 writes per voice per sample, which does not fit the 4-clock
per-voice budget.

**Per-tick state - 189 bits/voice.** Touched only by the sequencer walk, once
per tick, and a tick is 183 samples (~29 000 clocks). This splits again, and
the split matters:

- **Bulk note and instrument state, ~154 bits** - `sp`, `lps`, `lpe`, `fcnt`,
  `tcnt`, `play_len`, `cur_pitch`, `prev_pitch`, `cur_wave`, `cur_vol`,
  `cur_fx`, `prev_vol`, the `bf_*` filter bits and the whole `ins_*` block.
  Every one of these is only ever reached through the ring's index 0, i.e.
  only for the voice currently being walked. 16 x 154 = 2464 bits: **one
  `SB_RAM40_4K`**, read at the start of a voice's visit and written back at the
  end.
- **Control state, ~35 bits** - `playing`, `music_owned`, `launched`,
  `trig_req`, `sfx_id`, `row`, `trg_row`, `trg_len`, `released`, `sav_*`.
  These are addressed *randomly*: the CPU writes them by channel number, and
  the music FSM loops over all of them at once (`trig_req != 0`, `ML_LD`,
  `W_MUS`). They cannot come from a single working copy and stay in flops -
  16 x 35 = 560, which is cheap.

So sixteen voices cost about **2900 flops plus one BRAM** (38% of an HX8K),
against 1344 flops for four voices today. More than the 2100 first estimated,
because the randomly-addressed control state cannot go to BRAM, but still four
times the polyphony for roughly twice the silicon.

The refactor falls out of the existing structure. The rotated arrays are
already a working copy - index 0 *is* the voice being walked, and the rotation
is how the next voice is brought into it. So `name[0]` becomes a plain working
register `w_name`, and the rotation becomes a BRAM read and write-back. The
`[0:3]` rings disappear in favour of an explicit voice index.

**Order of work.** Do the de-rotation first and keep the backing store in flops
(behaviour-preserving, testable at four voices), then scale the pool and prove
allocation, then swap the backing store for BRAM. That way the audible change
lands and is verifiable before the storage rework, and if the BRAM port turns
out tighter than estimated the fallback is 8 voices in flops with nothing else
rewritten.

### Alternative considered: 8 voices

8 voices fit in flops today (2 688, 35%) with no BRAM rework and no multiplier
change. Four music voices plus four layered sound effects is very likely
indistinguishable from PICO-8 for real carts, since a cart can only *address*
four channels and the pool exists only so auto-picked sounds layer.

Rejected as the target because the state partition is worth doing regardless —
it is what makes the design fit — and once it is done sixteen is nearly free
and exactly matches the reference. 8 voices remains the fallback if the
multiply or the BRAM port turns out to be tighter than estimated.

## Voice allocation

PICO-8's rules, from the disassembly:

- `sfx(n, -1)` takes a **free voice** from the pool and tags it. It never stops
  anything.
- `sfx(n, c)` for an explicit channel "can replace or stop a voice carrying the
  same logical tag".
- `music(m)` schedules up to four voices with tags 0–3.

So allocation in hardware is: scan for a voice with nothing playing; if one
exists, claim it and tag it; if none exists, drop the request. Music-owned
voices are simply never idle, so they are never candidates — no mask, no
ownership test, no borrow.

The reservation mask register (`$21`) stays for compatibility but stops being
load-bearing: nothing needs protecting any more.

## Mixing

Sixteen voices reduce through PICO-8's binary tree, and every pair goes through
`soft_add`, which compresses 5:1 above ±24576 rather than clipping:

```
soft_add(a,b): s = a+b
  s >=  24576 ->  24576 + (s - 24576)/5
  s <= -24576 -> -24576 - (-24576 - s)/5
  else        ->  s
```

The division by 5 is `(excess * 52429) >> 18` in the binary. Because `soft_add`
is not associative the tree order is part of the behaviour, so the reduction is
specified as pairs in voice order, not as a sum.

This replaces `mixacc`'s flat sum and its hard clamp at ±131068. It is a
pre-existing gap (`docs/hardware-gaps.md`) that this change is the natural
moment to close, because a flat sum of sixteen voices would clip constantly.

## Migration

The CPU-facing register map keeps channel semantics: `$10-$13` still mean
"channel 0..3". Only the auto-pick is new, so a game that names its channel
explicitly needs no change at all. `src/nemo/sound.asm`'s `sfx_play` and its
counterpart in `src/main.asm` collapse to one store to the new register.

`--psg-trace` currently prints four channels; it grows to report voices with
their tags, and `tools/p8_music_trace.py` comparisons keep working because the
music still occupies tags 0–3.
