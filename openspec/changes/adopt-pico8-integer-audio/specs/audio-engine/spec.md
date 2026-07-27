# audio-engine delta — adopt-pico8-integer-audio

## MODIFIED Requirements

### Requirement: Eight PICO-8 Waveforms

The PSG SHALL synthesize the eight PICO-8 instruments as the shipping
binary's exact integer functions of oscillator phase, evaluated per sample
as the sum of a primary term and a half-weight secondary term
(`wave(p) + tz(wave(q)/2)` in each shape's own scaling), where `p` is the
16-bit primary phase, `q0` is the 17-bit secondary phase wrapping at
`0x1ffff`, `q = u16(q0 << m)` with `m` the binary's per-mode shift, and
`tz` is signed division truncated toward zero. The shapes SHALL be the
binary's recovered forms — triangle from `tri_raw(x) = 3x - 49152` /
`147456 - 3x`, tilted saw with threshold 57344, saw `tz((x - 32768)/4)`,
square and pulse as thresholds `0x8000` and `0xb000`, organ per `_inst5`
including `tz(2(x-32768)/3)`, and the custom 64-sample waveform as a
10-fractional-bit linear interpolation — each verified against the
disassembly and against a model reproducing the binary's exports
byte-for-byte before its RTL lands. Pitch k SHALL map to 440 x
2^((k-33)/12) Hz through the binary's static increment table. Deterministic
waveform output SHALL be bit-identical to the model, not
approximation-gated.

#### Scenario: Distinct timbres at equal pitch

- **WHEN** the same pitch and volume play with waveform 0 (triangle) and
  waveform 5 (organ)
- **THEN** the two produce the binary's integer waveform values exactly,
  sample for sample, as reproduced by the reference model

#### Scenario: Approximation-free saw

- **WHEN** waveform 2 plays any pitch at full volume
- **THEN** every emitted sample equals the model's
  `scale(saw(p) + tz(saw(q)/2))` with `saw(x) = tz((x - 32768)/4)` —
  no fitted-gain tolerance applies

### Requirement: Note Effects

The PSG SHALL evaluate the note effect field each tick using the binary's
integer recurrences: 1 slide (the binary's row interpolation including its
fine-pitch path, previous pitch initialised to 24 at trigger), 2 vibrato
(the binary's LFO recurrence), 3 drop (`dp = tz(DX(P0) * (D - t) / D)`,
amplitude held), 4 fade in (`A = tz(A0 * t / D)`, first tick silent), 5
fade out (`A = tz(A0 * (D - t) / D)`), 6/7 arpeggio (cycle the row group's
pitches at the binary's periods, halved when the SFX speed is 8 or less).
Effect arithmetic SHALL be bit-identical to the model per tick; the
per-tick 64-sample crossfade SHALL follow the binary's
`out[i] = tz((i*new[i] + (64-i)*old[i]) / 64)`.

#### Scenario: Drop matches the binary's rounding

- **WHEN** effect 3 plays a row of duration D ticks
- **THEN** each tick's phase increment equals
  `tz(DX(P0) * (D - t) / D)` exactly, including any tick where integer
  division rounds the increment to zero before the row ends

#### Scenario: Fade-in first tick is silent

- **WHEN** effect 4 plays with D = 1
- **THEN** the whole row is silent, matching `tz(A0 * 0 / 1)`

## ADDED Requirements

### Requirement: Binary-Exact Amplitude Stage

The PSG SHALL apply the binary's common amplitude stage to every
non-noise oscillator output: `y = tz(G * z / 3072)` with `G = tz(3a/2)`
and `a` the composed note amplitude on the binary's 0–252 scale; noise
SHALL divide by 2048 instead. Custom-instrument volume composition SHALL
be the binary's `tz(a * iv / 256)`. All truncations SHALL be toward zero.

#### Scenario: Truncation direction is observable

- **WHEN** a negative oscillator value z scales at any G
- **THEN** the output equals `tz(G*z/3072)` (rounded toward zero), not
  `floor(G*z/3072)`

### Requirement: Noise Exactness Boundary

The PSG SHALL implement the binary's noise modes (the `_codo_random`
generator, hold and interpolated modes with their intermediate
truncations) but SHALL NOT be required to reproduce the binary's sample
sequence: the binary's RNG state is shared with unrelated engine
consumers, so sequence-exact noise is unattainable in principle. Noise
verification SHALL remain statistical, and this boundary SHALL be stated
wherever noise gates are defined.

#### Scenario: Statistical gate cites the boundary

- **WHEN** a noise-consuming oracle case is gated
- **THEN** the gate is statistical and its definition references the
  shared-RNG exactness boundary
