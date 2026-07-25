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

**Per-sample state (~133 bits/voice)** — read and written every one of the
22 050 samples per second: `phase`, `phase2`, `eff_inc`, `eff_vol`, `lp`,
`brown`, `nz_hold`, `nz_ph`, `snd_wave`, `snd_wt`, `snd_wtb`, and the `ch_*`
filter bits. 16 × 133 = ~2 100 flops, 28% of an HX8K. Keep this as the rotating
ring it already is.

**Per-tick state (~200 bits/voice)** — touched once per *tick*, and a tick is
183 samples, i.e. ~29 000 clocks: `row`, `fcnt`, `tcnt`, `sp`, `lps`, `lpe`,
`cur_pitch`, `prev_pitch`, `cur_wave`, `cur_vol`, `cur_fx`, `prev_vol`,
`sfx_id`, `trg_row`, `trg_len`, `play_len`, `released`, and the whole `ins_*`
custom-instrument block. 16 × 200 = 3 200 bits — **one `SB_RAM40_4K`**, with
four orders of magnitude more clocks available than the walk needs.

That split is the whole trick: it turns the expensive half of the state into
one block RAM and leaves the cheap half where it is. Sixteen voices then cost
about 2 100 flops plus 1 BRAM, against 1 344 flops for four voices today —
roughly the same silicon for four times the polyphony.

The sequencer walk already visits channels one at a time in a fixed order, so
it maps onto a BRAM register file almost directly: read voice *v*'s record,
run the existing per-tick states against a single working copy, write it back.
The `[0:3]` rotation disappears in favour of an explicit voice index.

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
