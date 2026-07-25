## ADDED Requirements

### Requirement: SFX Filter Byte Interpretation

The PSG SHALL decode each SFX record's filter byte (offset 64) into
per-channel filter state when the SFX is triggered: `noiz` from bit 1,
`buzz` from bit 2, `detune = (byte/8) mod 3`, `reverb = (byte/24) mod 3`,
and `damp = (byte/72) mod 3`.

#### Scenario: Filter fields decoded at trigger

- **WHEN** an SFX whose filter byte encodes damp level 2 is triggered on a
  channel
- **THEN** that channel plays through the level-2 low-pass until it stops or
  another SFX retriggers the channel

### Requirement: Dampen Low-Pass

The PSG SHALL apply a per-channel low-pass filter when the channel's damp
level is nonzero, attenuating high-frequency content more strongly at
higher levels, and SHALL bypass it at level 0.

#### Scenario: Bright wave is dulled

- **WHEN** a sawtooth note plays with damp level 2
- **THEN** the output's high-frequency energy is reduced relative to the same
  note with damp level 0

### Requirement: Detune Second Voice

The PSG SHALL add a second oscillator voice at a nearby frequency when a
channel's detune level is nonzero (a small offset at level 1, about an
octave at level 2), summed with the main voice, producing beating or a
doubled timbre.

#### Scenario: Detuned note beats

- **WHEN** a note plays with detune level 1
- **THEN** the output amplitude envelope varies over time (two close voices
  beating) rather than being strictly periodic at the single-voice period

### Requirement: Noise Filter Modes

The PSG SHALL vary the noise instrument (waveform 6) by the noiz/buzz bits:
pitched sample-and-hold noise when both are clear, white noise when noiz is
set, and a browner (integrated) noise when buzz is set and noiz is clear.

#### Scenario: Noise character changes

- **WHEN** the same noise note plays once with noiz set and once with buzz
  set and noiz clear
- **THEN** the two outputs have different spectral character (brighter vs
  browner)

### Requirement: Reverb Echo

The PSG SHALL provide a reverb echo on the mixed output when any active
channel requests a nonzero reverb level, delaying by 366 samples (level 1)
or 732 samples (level 2) at the strongest requested level, and SHALL be
compile-time removable for board builds with constrained block RAM.

#### Scenario: Short note leaves a tail

- **WHEN** a short note plays on a channel whose reverb level is 2 and then
  stops
- **THEN** a delayed, quieter copy of the note is still present in the output
  after the note's own samples have ended

### Requirement: Delta-Sigma Audio Output

The console SHALL provide a single-bit audio output derived from the 8-bit
PCM by a first-order delta-sigma modulator clocked at the master clock, such
that the modulator output's local average tracks the PCM value (density
coding suitable for an off-board RC reconstruction filter).

#### Scenario: Bit stream tracks the level

- **WHEN** the PCM input ramps from minimum to maximum
- **THEN** the fraction of high bits in the modulator output rises
  monotonically from near 0 to near 1

### Requirement: Clock-Portable Sample Rate

The PSG's 22 050 Hz virtual sample rate SHALL be derived from a `CLK_HZ`
parameter supplied by the enclosing chip, so the audio timing is correct on
any master-clock frequency without regenerating the pitch, wave, or
reciprocal tables.

#### Scenario: Same tables on a different clock

- **WHEN** the chip is instantiated with a `CLK_HZ` matching a board master
  clock different from the simulator's
- **THEN** notes sound at the same pitches as in simulation, using the same
  table files
