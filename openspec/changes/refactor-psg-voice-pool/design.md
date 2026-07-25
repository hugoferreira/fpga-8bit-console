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

## Key decision: share the datapath, keep state in RAM

The first version of this design partitioned voice state *by rate* and kept the
per-sample half in registers. Synthesis says that is the wrong axis. Measured
standalone with `yosys`/`synth_ice40`:

| voices | LUT4 | flops | BRAM |
| ---: | ---: | ---: | ---: |
| 4 (today) | 4991 | 2023 | 16 |
| 8 | 6285 | 3287 | 16 |
| 16 | 9378 | 5811 | 16 |

An HX8K has 7680 LCs, and it also has to hold a CPU, a PPU and a sprite
compositor. Sixteen voices in flip-flops does not fit, and the reason is not
the arithmetic: **the marginal cost of a voice is 366 LUT4 and 316 flops**, and
336 bits is exactly one voice's state. Every extra LUT is a wider mux to reach
that state; every extra flop is the state itself. The datapath does not grow at
all - it is already time-shared across voices, one `pst` walk per sample.

So the rule is: **share the hardware, store the state.** Anything that is
per-voice belongs in RAM, not in registers, and the split by rate matters only
for deciding how often it is streamed - not for deciding what stays in flops.

Putting every per-voice bit in BRAM drives the marginal cost per voice to
roughly zero, so sixteen voices cost about what one does:

| | LUT4 | flops | BRAM |
| --- | ---: | ---: | ---: |
| today, 4 voices | 4991 | 2023 | 16 |
| 16 voices, state in BRAM | ~3900 | ~1100 | ~18 |

That is **sixteen voices for less silicon than today's four**, which is the
outcome worth having. 5376 bits of voice state is 1.3 `SB_RAM40_4K`, and an
HX8K has 32 of them against 7680 LCs - block RAM is the resource this design
has spare.

### What it costs: clocks

Streaming ~336 bits per voice through a 16-bit BRAM port is roughly 20
accesses per voice per sample:

| | clocks/sample | 16 voices x 20 |
| --- | ---: | ---: |
| board today, 25 MHz | 1134 | 28% |
| board on the spare PLL, 50 MHz | 2268 | 14% |
| simulator, 3.51 MHz | 159 | **201%** |

The board affords it twice over, and one of the two unused PLLs buys a further
2x if the streaming turns out wider than estimated. The simulator does not, and
this is no longer a detail that can be deferred: its console ties the video and
master clocks together and runs ~7x slower than the board, so **fixing the
simulator's clock model becomes part of this change**, not an aside. Without it
there is no way to test sixteen voices before hardware.

## What the BRAM move is actually worth

Measured across four voice counts (`yosys`/`synth_ice40`, PSG standalone):

| NV | LUT4 | flops |
| ---: | ---: | ---: |
| 2 | 3962 | 2706 |
| 4 (today) | 4998 | 2023 |
| 8 | 6285 | 3287 |
| 16 | 9378 | 5811 |

Least squares: **LUT4 ~ 3314 fixed + 379 per voice.** The 379 is per-voice
state and the muxes reaching it - that is what moving to block RAM removes,
and it removes it at *any* voice count. The 3314 is combinational logic: the
sample x volume multiply, wave ROM addressing, the effect and filter datapaths,
the two FSMs. Block RAM does nothing for it.

So the move is worth:

| | LUT4 | share of an hx8k |
| --- | ---: | ---: |
| today, 4 voices in flops | 4998 | 65% |
| 16 voices in flops | 9378 | 122% |
| **any voice count, state in BRAM** | **~3314** | **43%** |

A 34% cut to what ae37bbc measured as the largest block on the chip, and
sixteen voices become free rather than impossible. It costs about 2 more
`SB_RAM40_4K` (5376 bits of voice state).

**It is not sufficient on its own.** ae37bbc puts the whole design at 10731 LC
against 7680. Taking 1700 off the PSG leaves it around 9000, still ~117% over.
The rest has to come from elsewhere - `add-memory-subsystem` for the main RAM's
16 BRAM, and the compositor at 1789 LUT4 (23%). Worth saying plainly so this
change is not mistaken for the thing that makes the design fit.

**Consequence for clock optimisation.** Tuning each domain's clock to its own
Fmax needs nextpnr to report a critical path, and nextpnr cannot place a design
that is 139% over. Per-domain Fmax is therefore blocked behind area, not behind
clocking - and 112.5 MHz for the PSG stays a target rather than a measurement
until then.

## The BRAM register file: layout and state flow

Concrete plan, so the conversion is mechanical rather than exploratory.

**Storage.** One memory, 16-bit words, addressed `{voice, word}`:

    logic [15:0] vmem [0:NV*W-1];
    always_ff @(posedge clk) begin
      if (vwe) vmem[vaddr] <= vwdata;
      vq <= vmem[vaddr];            // synchronous read - required for
    end                             // SB_RAM40_4K inference

Synchronous read is the part that matters: an asynchronous read forces yosys
into LUTs, which is exactly what these arrays are today.

**Record layout**, 336 bits = 21 words per voice. The `ins_*` group is 76 bits
and converts first because it is cleanly separable - every name starts `ins_`,
nothing outside the walk touches it:

| word | contents |
| ---: | --- |
| 0 | `ins_sp[8]`, `ins_lps[8]` |
| 1 | `ins_lpe[8]`, `ins_fcnt[8]` |
| 2 | `ins_tcnt[8]`, `ins_pitch[6]`, `ins_on`, `ins_wt` |
| 3 | `ins_prev_pitch[6]`, `ins_row[5]`, `ins_id[3]`, `ins_bass`, `ins_done` |
| 4 | `ins_wave[3]`, `ins_vol[3]`, `ins_fx[3]`, `ins_prev_vol[3]`, 4 spare |

**State flow.** A voice visit becomes load, work, store. The walk already has
exactly one entry and one exit per voice, so there are only two places to
splice: `S_IDLE`/`K_ROT` both jump to `K_ADV`, and `K_ROT` advances `c`.

    S_IDLE / K_ROT  ->  V_LD (W+1 cycles)  ->  K_ADV ... (unchanged)
                    ->  K_ROT  ->  V_ST (W cycles)  ->  next voice

`ins_X[c]` becomes a working register `w_ins_X` throughout - 104 references,
all inside the walk, including the module-level wires at psg.sv:265-277 and the
`seq_addr` cases at 312-316 which are walk-context too.

**Two things to get right, both of which will pass tests if got wrong:**

1. *Reset.* A BRAM cannot be reset the way an array of flops can. `ins_on`
   decides whether the instrument path runs at all, so garbage there before the
   first trigger would matter. It is safe only because `playing[c]` is 0 after
   reset and `K_ADV` skips the note path entirely when a voice is not playing -
   verify that, do not assume it.
2. *Cost before benefit.* At NV=4 the record is 20 words. Yosys will not spend
   a 4096-bit BRAM on 320 bits, so it stays in LUTs and the added address logic
   and states make area slightly **worse**. The win only appears once every
   group is converted and NV is 16. Intermediate measurements will look like
   regressions and should not be treated as failures.

**Verification at each step** is the render comparison, not the tests: the
testbench passes with a good deal of this wrong, whereas NEMO and Celeste
rendering bit-identically through a pure restructuring is a real check. That is
what caught nothing so far and would catch this.

## Clocking: the PSG gets its own PLL

Sixteen voices streamed from BRAM need ~320 clocks per sample. The board has
them; the way it is wired today does not hand them to the PSG.

`icepll -i 25` reaches 50, 100, 150 and 200 MHz exactly from the board's
crystal, and **both** of the HX8K's PLLs are unused - `rtl/pll.v` (25 -> 50)
exists but is instantiated nowhere. So the clocks are there for the taking.

Two ways to take them, and the second is what this change does:

1. **One high common clock, everything derived from it by enables.** Clean, no
   clock-domain crossing, and it is the textbook answer. Rejected here for a
   coordination reason, not a technical one: it means turning every
   `always_ff @(posedge clk)` in the PPU into `if (en)`, and `refactor-ppu-core`
   is in flight in this same checkout with a spec requirement that per-line
   clock accounting must not regress. Two agents rewriting the PPU's clocking
   at once is not a trade worth making.

2. **An independent PLL for sound.** The PSG becomes its own clock domain at
   50-100 MHz while the CPU and PPU keep the 25 MHz board clock untouched. The
   cost is a clock-domain crossing on the PSG's register interface - and that
   interface is tiny and slow: a handful of writes per frame plus the 4608-byte
   audio upload, no read-modify-write, no burst. A toggle handshake covers it.

The second is also what PICO-8 does. Its audio is pull-driven by the SDL
callback thread, which runs completely independently of the video loop;
`sfx()` and `music()` only mutate state, under `SDL_LockAudio`. The engine has
no notion of audio and video sharing a clock, and the handshake here is the
hardware equivalent of that lock.

At 100 MHz the PSG gets **4535 clocks per sample**, so sixteen voices streamed
from BRAM cost 7% of budget. That is the headroom that lets voice state live in
RAM instead of registers, which is the whole point.

## Superseded: partition voice state by rate

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
- **Control state, ~12 bits** - `playing`, `music_owned`, `launched`,
  `trig_req` and the voice's channel tag. **The CPU never addresses a voice.**
  Its register map is four channels (`addr[1:0]`), and voices are entirely
  internal, so nothing outside needs to index sixteen of anything. What is left
  is genuinely small:

  - The four one-bit-per-voice sets are just 16-bit vectors. Allocation is
    "find a clear bit in `playing`"; the music FSM's `trig_req != 0` and its
    loops over owned voices are vector operations. 16 x 4 = **64 flops**.
  - The channel tag is 16 x 2 = **32 flops**. An explicit `sfx(n, c)` has to
    find the voice carrying tag c, but that happens once per CPU write with
    thousands of clocks in hand, not once per sample.
  - `trg_row` and `trg_len` are not per-voice at all. They are parameters of a
    *pending request*, which the CPU addresses by channel, so four sets suffice
    however many voices exist: 4 x 11 = **44 flops**.
  - `sfx_id`, `row` and `released` go in the BRAM record with everything else.
    They are read back through `$14-$17` for a channel, which is a single
    indexed read, not a scan.
  - `sav_sfx`/`sav_row`/`sav_valid` are deleted outright by section 5.

So the corrected budget:

| | flops |
| --- | ---: |
| per-sample state, 16 x 147 | 2352 |
| voice set bits, 16 x 4 | 64 |
| voice channel tags, 16 x 2 | 32 |
| pending trigger params, 4 channels x 11 | 44 |
| **total** | **2492 (32% of an HX8K)** |

plus a BRAM record of 166 bits x 16 voices = 2656 bits, comfortably inside one
`SB_RAM40_4K`. Against 1344 flops for four voices today, that is four times the
polyphony for well under twice the silicon.

An earlier draft of this section put the total at ~2900 flops by assuming the
control state had to be randomly addressable at voice granularity. It does not:
that only looked necessary while thinking of voices as channels. Keeping the
distinction sharp - **the CPU addresses channels, the PSG addresses voices** -
is what makes the pool cheap, and it is the same distinction that makes
`sfx(n,-1)` safe.

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
