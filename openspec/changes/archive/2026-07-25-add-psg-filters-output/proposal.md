## Why

Two audio items remain from the add-pico8-audio-engine follow-ups: the SFX
filter byte (the NOIZ/BUZZ/DETUNE/REVERB/DAMPEN tier) is parsed but not
interpreted, and there is no output stage that turns the chip's 8-bit PCM
into a signal a physical board can drive. This change closes both so the
PSG both sounds like PICO-8's filtered instruments and can reach a speaker
pin on real hardware.

## What Changes

- **Filter byte interpretation** (SFX record offset 64, decoded mixed-radix
  as in the PICO-8 references): `noiz` (bit 1), `buzz` (bit 2),
  `detune = (b/8)%3`, `reverb = (b/24)%3`, `damp = (b/72)%3`. Read into
  per-channel state at trigger.
  - **DAMPEN**: per-channel one-pole low-pass, shift-based (level 1 ≈ 2.4 kHz,
    level 2 ≈ 1 kHz at the 22 050 Hz rate).
  - **DETUNE**: per-channel second voice on the existing phase-2 accumulator
    (level 1 ≈ +14 cents, level 2 ≈ +1 octave), summed with the main voice;
    the phaser stays a fixed detune preset on waveform 7.
  - **NOIZ / BUZZ** on the noise instrument (6): pitched sample-and-hold when
    both clear (today's behaviour), white when `noiz`, brown (integrated)
    when `buzz && !noiz`.
  - **BUZZ** on square/pulse: a shifted duty cycle via a combinational
    alternate path (no wave-ROM growth).
  - **REVERB**: a single shared feed-forward delay on the final mix at the
    strongest level any active channel requests (2 ticks = 366 samples,
    4 ticks = 732 samples). A documented hardware simplification of PICO-8's
    per-channel reverb; gated by a `REVERB` parameter so an EBR-tight board
    build can drop it.
- **Board output stage**: a first-order delta-sigma modulator converts the
  8-bit unsigned PCM to a 1-bit pin at the master clock (density-coded;
  an RC low-pass off-board reconstructs the analogue signal). Wired into
  `top.sv` on a dedicated pin.
- **Clock-portable timing**: `chip.sv` gains a `CLK_HZ` parameter threaded
  to the PSG so the 22 050 Hz virtual rate is derived correctly on any
  board clock; `top_simulator` keeps the simulator's clock, `top.sv`
  passes the board master-clock frequency. The pitch/wave/reciprocal
  tables are already 22 050-relative, so no regeneration is needed.

Out of scope: custom SFX/wavetable instruments, automatic channel
selection (sfx -1/-2), music fades, and per-channel (rather than shared)
reverb.

## Impact

- Affected specs: audio-engine (filter and output requirements added)
- Affected code: `rtl/psg.sv` (filter state + DSP), `rtl/dsigma.sv` (new),
  `rtl/chip.sv` (CLK_HZ param), `rtl/top.sv` + `rtl/top.pcf` (audio pin),
  `rtl/psg_tb.sv` (filter/DSP coverage), `docs/hardware-gaps.md`
- Hardware cost: reverb delay ~732 B BRAM (optional); per-channel LPF/detune
  state in registers; the delta-sigma modulator is a single accumulator.
  The board audio pin number and the board master-clock frequency are
  config values the operator must confirm for their wiring.
