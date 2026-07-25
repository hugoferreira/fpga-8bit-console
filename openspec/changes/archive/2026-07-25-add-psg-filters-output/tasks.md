## 1. Filter-byte DSP (psg.sv)

- [x] 1.1 Read the SFX filter byte (record offset 64) at trigger via a new
      T_FL state; decode noiz/buzz/detune/reverb/damp per channel (mixed-radix)
- [x] 1.2 DAMPEN: per-channel one-pole low-pass (Q8 state, shift by damp level)
- [x] 1.3 DETUNE: per-channel second voice on phase-2 (level 1 ~+14 cents,
      level 2 octave), summed; phaser remains the wave-7 preset
- [x] 1.4 NOIZ/BUZZ on noise (wave 6): white / pitched / brown select
- [x] 1.5 BUZZ on square/pulse: shifted-duty combinational alternate path
- [x] 1.6 REVERB: shared feed-forward mix delay at the max requested level,
      behind a REVERB parameter (366/732-sample taps, 732-byte buffer)

## 2. Output stage and clock portability

- [x] 2.1 rtl/dsigma.sv: first-order delta-sigma modulator, 8-bit PCM -> 1-bit
- [x] 2.2 chip.sv: CLK_HZ + REVERB parameters threaded to the PSG
- [x] 2.3 top.sv: BOARD_CLK_HZ passed to the chip, dsigma on chip audio,
      audio_pwm output port
- [x] 2.4 top.pcf: audio_pwm pin assigned (pin 63, flagged for confirmation)

## 3. Verification

- [x] 3.1 TB: DAMPEN low-passes white noise (peak sample step shrinks by >2x)
- [x] 3.2 TB: DETUNE advances the second accumulator (beating second voice)
- [x] 3.3 TB: NOIZ/BUZZ modes differ (white updates faster than pitched;
      brown has smaller steps than white)
- [x] 3.4 TB: REVERB leaves an echo tail after note-off (dry note goes silent)
- [x] 3.5 TB: dsigma 1-bit density rises monotonically with a PCM ramp and is
      proportional (not saturated)
- [x] 3.6 Whole-system Verilator build clean; audio still matches the cart
      pitches after CLK_HZ threading; board top.sv lints clean

## 4. Docs

- [x] 4.1 Update docs/hardware-gaps.md and the psg memory note
