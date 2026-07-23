## Context

The v1 PSG (`rtl/psg.sv`) proved the shape of the design: PICO-8's 16-bit
note format in chip RAM, a hardware sequencer stepping notes, register-write
triggers. This change grows it into a faithful PICO-8 audio chip: the full
memory model, the full synthesis model (waves + effects), and the music
layer. Reference behaviour is the PICO-8 manual plus the reverse-engineered
constants collected in the project's PICO-8 audio notes (22 050 Hz native
rate, 183 samples/tick, waveform formulas, effect semantics).

Constraints: iCE40-class BRAM budget (no DSP blocks — multipliers are LUTs,
so share one), Verilator-first simulation at a 3.5 MHz system clock, and the
existing 8-bit unsigned PCM interface `psg.pcm -> top -> SDL runner`.

## Goals / Non-Goals

- Goals: cart audio bytes upload verbatim and sound recognizably like
  PICO-8; sfx() and music() are one register write; all timing derived
  in-chip from the system clock; clock-portable (tables depend only on the
  22 050 Hz virtual rate, not the system clock).
- Non-Goals: bit-exactness against PICO-8 WAV exports; filter byte (NOIZ /
  BUZZ / DETUNE / REVERB / DAMPEN); custom/wavetable instruments; automatic
  channel stealing; music fades. These layer on later without reshaping the
  architecture.

## Decisions

- **Decision: virtual 22 050 Hz sample clock via fractional divider.**
  An accumulator adds 22 050 per system clock and subtracts CLK_HZ on
  overflow, yielding a `sample_en` strobe; a /183 counter on `sample_en`
  yields `tick_en` (120.49 Hz). Phase accumulators, noise, and the output
  register advance only on `sample_en`, so `psg_pitch.hex` is generated once
  for 22 050 Hz and works on any board clock (CLK_HZ is a parameter).
  PICO-8's aliasing character comes free. The vsync tick input is dropped.
  - Alternatives: keep per-system-clock phase stepping (v1) — ties the pitch
    table to each clock and makes 183-sample tick timing awkward; 60 Hz
    frame tick — halves effect resolution and breaks speed semantics.

- **Decision: audio RAM is a byte-addressed 4608-byte buffer holding the
  PICO-8 image; the upload port takes PICO-8 addresses.** Internally
  `addr - $3100` indexes the buffer ($3100–$31FF music, $3200–$42FF SFX).
  A SFX record is at `$3200 + n*68`; byte offsets 64..67 are filter (parsed,
  ignored in v2), speed, loop start, loop end. The extractor repacks .p8
  text lines into this exact image, so upload is `lda / sta` in a loop.
  - Alternative: keep v1's flat note pool + register-side start/len/speed —
    requires a bespoke extraction step per cart and cannot express loops,
    music, or per-SFX speed without CPU help.

- **Decision: one time-multiplexed synthesis datapath.** Between two
  `sample_en` strobes there are >150 system clocks even in sim; a small FSM
  walks channels 0..3 computing phase step, wave lookup, and the
  volume multiply with one shared multiplier, accumulating into the mix.
  Per-tick effect evaluation reuses the same multiplier (slide lerp, drop,
  fades, vibrato depth are all one 8/9-bit multiply each).
  - Alternative: v1's four parallel combinational paths — 4x the multiplier
    area for no benefit at these rates.

- **Decision: waveforms from a generated 2 KB wave ROM (8 waves x 256 x
  8-bit signed)** for the six periodic shapes, exact PICO-8 formulas and
  relative amplitudes baked in by `tools` generator; noise is a 15-bit LFSR
  sampled-and-held on phase subdivision crossings (pitch-tracked); phaser
  sums the triangle row read at phase A and phase B where
  `inc_B = inc - inc/128 - inc/512` (~109/110). One BRAM read per channel
  slot fits the serial datapath.
  - Alternative: combinational piecewise shapes (v1) — cheap for tri/saw
    but organ/tilted-saw get approximated away, which is audibly the point
    of this change.

- **Decision: effects computed once per tick, applied as an effective
  phase increment + effective volume.** Row progress `u` (Q8) comes from
  `fcnt * recip[speed] >> 8` with a 256-entry reciprocal ROM. Slide lerps
  phase increments linearly (matches the "linear frequency interpolation"
  reference behaviour) from the previous row's increment, with prev pitch
  initialised to 24 on trigger. Drop multiplies inc by (1-u). Vibrato adds
  `±(inc>>6)` on a 16-tick triangle LFO (~7.5 Hz, ~±1.5% ≈ ±25 cents).
  Fades scale an internal 8-bit volume (vol3 x 36) by u or 1-u. Arpeggios
  re-fetch the note from row `(row & ~3) | idx`, idx stepping every 4/8
  ticks (2/4 when speed <= 8). 120 Hz update granularity is accepted
  (zipper is inaudible at these depths and is period-authentic).

- **Decision: music sequencer as a small FSM layered on the SFX engine.**
  `music(m)`: fetch 4 pattern bytes, launch each enabled channel's SFX
  (bit6 clear), record the left-most enabled non-looping channel as the
  timing channel. When the timing channel's playback ends, apply flow
  control: stop flag (byte2 bit7) stops music; loop-back (byte1 bit7) scans
  backward for loop-start (byte0 bit7) else pattern 0; otherwise next
  pattern. If every launched channel loops, the pattern ends after 32 rows
  at channel-slot-0's speed (fallback). A manual sfx() write to a channel
  simply overrides it; music reclaims it at the next pattern boundary.

- **Decision: register map v2** (window $4100, offsets):
  - $00/$01 upload address lo/hi (PICO-8 address), $02 data write +
    auto-increment, $03 read = channel playing bits [3:0], music playing
    bit 7.
  - $10+c: write n (0–63) plays SFX n on channel c from row 0; write $80
    stops the channel. Read = current row (playing) for debug.
  - $20: write m (0–63) starts music at pattern m; write $80 stops music.
    Read = current pattern.
  - $21: music channel mask (bit c set = music may use channel c;
    default $0F).

## Risks / Trade-offs

- BRAM budget (~7.3 KB total ROM+RAM) is fine for Verilator and UP5K-class
  parts but tight on an HX1K → acceptable; the board target already assumes
  a larger part (sprite compositor precedent).
- Effect maths in fixed point may drift audibly from PICO-8 → mitigate with
  a testbench that plays constructed SFX (slide across an octave, drop,
  arpeggio) and checks pitch/volume trajectories against computed
  references; exactness is explicitly a non-goal.
- The breaking register map orphans v1 callers in one commit → main.asm and
  breakout_sfx.asm are regenerated in the same change; no other callers
  exist.
- Fractional divider jitter (±1 system clock per sample) is far below
  audibility at 22 050 Hz.

## Migration Plan

1. Land tools (wave ROM, pitch table, reciprocal table, cart extractor).
2. Rewrite psg.sv behind the same module port list minus `tick`; update
   chip.sv/tops in the same commit.
3. Regenerate breakout_sfx.asm as a RAM image; rewrite the upload loop and
   the (now one-write) trigger sites in main.asm.
4. Runner: switch resampling from 735-samples/frame Bresenham to 22 050 →
   44 100 doubling.
Rollback: revert the commit; v1 data files remain in git history.

## Open Questions

- Pulse duty: PICO-8 measures ~31.6%; wave ROM uses 81/256 — verify by ear
  against reference recordings during 5.x.
- Whether music-launch should also honour a per-pattern shortened length on
  looping-only patterns other than the 32-row fallback (rare in real carts).
