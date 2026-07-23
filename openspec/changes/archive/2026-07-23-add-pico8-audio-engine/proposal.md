## Why

The v1 PSG (add-psg) plays PICO-8 notes but not PICO-8 *sound*: effects are
ignored, three of the eight waveforms are approximated as triangles, timing is
the 60 Hz frame instead of PICO-8's 120.49 Hz tick, and there is no music
layer at all — the cart's SFX had to be re-cut into a flat note pool with
sidecar tables. The console should be programmable the way PICO-8 is: copy
the cart's audio bytes in unchanged, then `sfx(n, ch)` and `music(m)` are one
register write each and hardware does the rest.

## What Changes

- **PICO-8-native audio RAM** (4608 bytes) inside the PSG, addressed with
  PICO-8's own addresses via a 16-bit auto-increment upload port: music
  patterns at $3100–$31FF, SFX records at $3200–$42FF (64 SFX x 68 bytes:
  32 notes, filter byte, speed, loop start, loop end). Cart bytes upload
  verbatim — no repacking, no sidecar tables.
- **PICO-8 timing model**: internal 22 050 Hz sample enable (fractional
  divider from the system clock) and a 120.49 Hz sequencer tick (183 samples
  per tick). SFX `speed` means ticks-per-row natively. The PSG no longer
  consumes the 60 Hz vsync tick.
- **All eight waveforms** with PICO-8's shapes and relative amplitudes:
  triangle, tilted saw, saw, square, pulse (~31.6% duty), organ from a
  script-generated wave ROM; pitched sample-and-hold LFSR noise; phaser as a
  dual phase accumulator (109/110 ratio) summing two triangle reads.
- **All eight note effects** in hardware, evaluated per tick: slide (linear
  phase-increment interpolation from the previous row, initial prev pitch 24),
  vibrato (~7.5 Hz triangle LFO, ~±1.5% frequency), drop, fade in, fade out,
  fast/slow arpeggio (group-of-four rows, halved period when speed <= 8).
- **PICO-8 loop semantics** from the SFX record: loop when start < end,
  length-only convention when start > 0 and end = 0, else 32 rows.
- **Hardware music sequencer**: `music(m)` as one register write. Fetches the
  4-byte pattern, launches up to four SFX, ends the pattern by the left-most
  non-looping channel rule, honours loop-start / loop-back / stop-at-end flag
  bits, and chains patterns with zero CPU work.
- **BREAKING — register map v2 at $4100**: upload port becomes a full 16-bit
  address; per-channel start/len/speed/ctrl registers are replaced by
  one-write triggers (play SFX n on channel c; play/stop music). The
  breakout cart's SFX asm is regenerated in native format and its trigger
  code shrinks to single writes.
- Extraction tool emits the cart's `__sfx__`/`__music__` sections as a
  verbatim RAM image (.p8 text fields repacked to the 16-bit in-RAM note
  form).
- Runner consumes PCM at the native 22 050 Hz rate and doubles it to the
  44.1 kHz SDL queue.

Out of scope (future changes): filter byte interpretation (NOIZ / BUZZ /
DETUNE / REVERB / DAMPEN), custom SFX instruments and 64-sample wavetables,
automatic channel selection (sfx -1/-2), music fade in/out.

## Impact

- Affected specs: audio-engine (new capability spec)
- Affected code: `rtl/psg.sv` (rewrite), `rtl/psg_pitch.hex` (regenerated for
  22 050 Hz), new wave-ROM + reciprocal-table hex files and generator script,
  `rtl/chip.sv` / tops (tick wiring removed), `sim/console.cpp` (audio
  resample path), `tools/` extractor (native SFX + music emission),
  `src/main.asm` + `src/breakout_sfx.asm` (new register map, regenerated
  data), `docs/hardware-gaps.md`
- Hardware cost: ~4.6 KB audio RAM + 2 KB wave ROM + ~0.7 KB tables (BRAM),
  one shared 8x9 multiplier datapath time-multiplexed across channels; PWM
  output stage for the physical board remains future work
