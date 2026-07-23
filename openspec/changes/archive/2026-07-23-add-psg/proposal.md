## Why

Audio was the last whole dimension the console could not express (docs/
hardware-gaps.md gap #1). PICO-8 principle translated to hardware: sfx()
becomes silicon - the CPU says "play sound N on channel C" in four register
writes and hardware does everything else.

## What Changes

- New `rtl/psg.sv`: 4-channel PSG at $4100-$41FF. Each channel: 24-bit phase
  accumulator, pitch from a generated 64-entry increment table (PICO-8 pitch
  semantics: 65.406 Hz x 2^(p/12)), waveforms tri/saw/square/pulse/noise
  (PICO-8 wave indices; tilted-saw/organ/phaser approximate to saw/tri for
  v1), 3-bit volume, 12-bit mix with clamp to 8-bit PCM.
- **Hardware sequencer**: 512-byte SFX RAM holds notes in PICO-8's native
  16-bit note format ({fx, vol, wave, pitch}) - cart sound data uploads and
  plays without conversion. Channels are started with start/length/speed/
  play registers; notes step on the 60 Hz vsync tick with zero CPU work.
  Effects fields are accepted but not yet interpreted (the cart's sounds
  bake their fades into per-note volumes).
- `chip.sv`/arbiter: $4100 window, PSG readable status, audio[7:0] out
  through both tops. The SDL runner resamples the PCM to 44.1 kHz
  (Bresenham, 735 samples/frame) into an SDL audio queue.
- Breakout plays the cart's actual SFX, extracted from the ROM's sound
  section: wall tick, paddle blip, brick hit, shatter (noise), lose-ball
  sweep, serve, and the max-chain fanfare - uploaded at boot via the
  auto-increment port, triggered with 4 writes per event.

## Impact

- Affected code: rtl/psg.sv (new), memory_arbiter.sv, chip.sv, tops,
  sim/console.cpp, src/main.asm, src/breakout_sfx.asm (generated)
- Hardware cost: 1 EBR (SFX RAM) + phase accumulators/mixer (~small);
  hardware output stage (PWM/delta-sigma pin) is future work for the board
