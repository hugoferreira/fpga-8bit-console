# Design: sixteen-voice PSG

## Context

The PSG today has four physical channels. Each is a slot in a set of `[0:3]`
arrays that are **rotated** every sample: the pipeline always works on index 0
and shifts the ring round after each channel (`rtl/psg.sv`, states `pst 0..3`
and the `K_ROT` rotation in the sequencer walk). That structure is why the
per-channel state is cheap to *address* and expensive to *hold*: every bit is a
flip-flop with a rotation mux.

## The hardware deadline

There is one architectural budget: work must finish before the next observable
audio boundary. Simulation throughput is not a second clock domain and is not
an RTL constraint. Verilator lowering, compiler optimisation and host hardware
all change how quickly a model executes; none changes how many hardware clocks
exist between 22 050 Hz samples.

The design has one 112.5 MHz PLL source. `rtl/clocks.sv` derives the chip clocks
and `psgclk` from that source with integer ratios, so the domains remain
phase-locked. The intended PSG domain is the undivided source:

| PSG clock | clocks per 22 050 Hz sample | role |
| --- | ---: | --- |
| 112.5 MHz source | 5102 | architectural target |
| 28.125 MHz (`PSGDIV=4`) | 1275 | current iCE40 fallback while timing is open |

The current eight-slot BRAM pipeline takes about `8 * 19 + 3 = 155` clocks per
sample. It therefore occupies about 12% of even the divided fallback and 3% of
the target. The unused clocks are an area resource: this change deliberately
spends them to replace parallel combinational networks with sequential,
shared arithmetic.

The deadline rules are:

- all eight voice visits and the pairwise mix complete before `sample_en`;
- tick-rate sequencer work completes before the next 183-sample tick;
- no audible state advances merely because a system clock elapsed;
- simulation verifies those boundaries at a declared `CLK_HZ`, but wall-clock
  simulator performance never limits the synthesized schedule.

The current divided clock is not the desired end state. Microcoding shortens
combinational paths as well as reducing LC, so every optimisation stage is
measured both for area and routed Fmax. Once the PSG closes at 112.5 MHz,
`PSGDIV` returns to one and the full 5102-clock sample budget becomes real.

## LC-for-time architecture

The remaining optimisation is ordered by the amount of safe scheduling slack:

1. **Microcode-oriented effect engine.** Pitch, volume, slide, vibrato,
   arpeggio and fade evaluation happen at tick rate. A small controller and
   accumulator replace parallel operand/result muxes and arithmetic.
2. **Reset and register audit.** Only validity and control state reset.
   Working datapath registers that are overwritten before use do not consume
   reset/set routing or reset muxes.
3. **Iterative reciprocal networks.** Exact constant-reciprocal operations,
   including `soft_add`'s `(excess * 52429) >> 18`, execute as sequences of
   shifts and additions through one arithmetic unit.
4. **Shared ALU/DSP synthesis walk.** Phase advance, phaser ratio, noise gain,
   filtering, volume multiplication and mix compression serialize around a
   common width-safe add/subtract/shift datapath. The iCE40 maps this to
   LUT/carry logic; devices with DSP blocks may map the same operation contract
   to a DSP.

Each stage must keep PICO-8 arithmetic widths, signedness, saturation points
and pairwise reduction order exact. Extra latency inside a sample is invisible
provided the sample and tick deadlines above hold.

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

Streaming voice state through 16-bit BRAM ports costs roughly 19 clocks per
slot in the current eight-slot implementation:

| PSG clock | clocks/sample | current 155-clock walk |
| --- | ---: | ---: |
| 28.125 MHz divided fallback | 1275 | 12.2% |
| 112.5 MHz source target | 5102 | 3.0% |

The schedule therefore has room to grow by hundreds of clocks per sample while
still meeting the hardware boundary. That margin is intentionally available to
the microcoded and shared-arithmetic stages; no host simulator cycle count is
part of this calculation.

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

## Clocking: one master-derived tree

The earlier design proposed an independent sound PLL and a register-interface
clock-domain crossing. That design is obsolete. `rtl/top.sv` already
instantiates a 112.5 MHz PLL and `rtl/clocks.sv` derives `masterclk`,
`videoclk`, `cpuclk` and `psgclk` from it at integer ratios. A chip-domain
signal is stable across a known number of PSG edges, so no asynchronous
handshake is introduced by this change.

`PSGDIV=4` exists only because the current combinational PSG closes around
28 MHz rather than at the undivided 112.5 MHz source. It is a timing fallback,
not the architectural source of the audio budget. The microcoded datapath is
expected to reduce both LC and critical-path depth; routed synthesis after each
stage decides when the divider can be reduced and ultimately removed.

Simulation is parameterized by the same logical `CLK_HZ` needed to derive the
22 050 Hz sample strobe. A standalone or console model may schedule clocks in
whatever host-efficient way is appropriate, but this is tooling behaviour:
simulation wall time and host step count do not alter the hardware schedule or
the audio contract.

## Superseded: partition voice state by rate

The 336 bits are not all touched at the same rate.

Measured exactly (task 2.1), not estimated:

**Per-sample state - 147 bits/voice.** Touched by the synthesis pipeline every
one of the 22 050 samples per second: `phase`(24), `phase2`(24), `eff_inc`(24),
`lp`(16), `brown`(13), `snd_wtb`(13), `eff_vol`(8), `nz_hold`(8), `nz_ph`(4),
`snd_wave`(3), and the single bits `playing`, `snd_wt`, `ch_noiz`, `ch_buzz`
plus `ch_det`/`ch_rev`/`ch_damp`(2 each). 16 x 147 = 2352 flops, 31% of an
HX8K. This stays in registers - streaming it from BRAM would need ~10 word
reads and 10 writes per voice per sample. The earlier claim that this could not
fit a four-clock voice budget came from the discarded simulator constraint;
the implemented design subsequently moved this state to BRAM and spends the
hardware clock headroom to stream it.

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

Rejected as the target in the original plan because the state partition was
worth doing regardless. Later reverse engineering established that the classic
compatibility boundary is the eight-slot foreground/music model; this is now
the implemented target rather than a clock-budget fallback.

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

## Implemented microcode and reset audit

The tick/effect path already has a compact six-operation micro-PC (`xs`) around
one eight-cycle shift/add multiplier. Its contract is now explicit in
`rtl/psg.sv`: row fraction, current volume, previous volume, pitch effect,
volume effect, music gain, then atomic publish. Pitch-effect products retain
the `[31:8]` truncation, volume products retain `[15:8]`, and pitch composition
keeps its signed nine-bit clamp.

Three more aggressive variants were synthesized and rejected:

| Variant | LC | Result |
|---|---:|---|
| General shared 25-bit ALU | 5632 | wide operand mux cost more than the removed adders |
| Split 25/9/9-bit ALUs | 5646 | narrower muxes still lost to iCE40 packing |
| Serialize both 3x3 volume products | 5446 | area win, but 128 added walk clocks changed both byte-exact renders |
| Serialize one 3x3 volume product | 5526 | area loss and still changed scheduling |

The general-ALU direction therefore needs a fixed tick-commit boundary before
more arithmetic is migrated. Evaluation may finish early or late within the
large hardware deadline, but all voices must publish at the same defined point
if renders are to remain byte-exact.

The reset audit classifies the remaining reset state as follows:

- Timing accumulators and event strobes, sequencer state, pending/playing
  validity, CPU-visible registers, RAM-port replay control, noise seed,
  synthesis/reverb control, and output registers retain reset hardware.
- Effect multiplier operands/results and pitch/volume scratch are datapath
  hidden by reset `m_cnt` and `xs`; their resets were removed.
- The sequencer's BRAM record working copy is completely replaced by `V_LD`
  before `K_ADV`. Sound-parameter scratch is gated by reset `playing` and
  `trig_req` until trigger/effect states produce it. Those resets were removed.
- Per-sample synthesis datapath is also validity-gated and was functionally
  eligible, but removing its resets worsened packing from 5456 to 5485 LC, so
  those resets remain.

The retained reset changes preserve the six-op schedule and reduce the routed
design from 5489 to 5456 LC while improving Fmax from 29.62 to 32.10 MHz.

The reciprocal inventory found no remaining general divider in the tick path:
`1/speed` is a synchronous BRAM lookup and the volume products already use the
serial multiplier. The remaining candidate is `soft_add`'s exact
`(excess * 52429) >> 18`, currently factored into four carry-chain additions.
An exact 18-step restoring divide by five was implemented with the pairwise
tree order unchanged. Separate dividend/quotient registers routed at 5465 LC
and 44.78 MHz; a packed `{remainder, quotient}` register routed at 5468 LC and
44.27 MHz. Both were reverted because the goal is LC reduction. The experiment
does show a documented Fmax trade if the undivided clock later becomes more
important than the last twelve cells.

The first synthesis-walk sharing experiment serialized only the phaser/detune
increment directly into `s_phase2`: base add followed by up to three shifted
corrections, increasing a slot visit from 19 to 22 clocks. It routed at 5652 LC
and 31.80 MHz. Although the arithmetic sequence was exact, multiple
state-conditioned writes built a large input mux on every phase bit instead of
one shared adder. It was reverted. Any later shared ALU must keep one physical
write site per working register and place the micro-op selection before that
site; merely spelling repeated nonblocking assignments across states does not
make iCE40 share their carry chains.
