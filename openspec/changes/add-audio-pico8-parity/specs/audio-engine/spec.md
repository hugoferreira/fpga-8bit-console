## ADDED Requirements

### Requirement: SFX Instruments

The PSG SHALL treat a note whose custom-instrument bit (bit 15) is set as a
note played through SFX 0–7 selected by the note's waveform field, running
that SFX as a second playhead on the channel: the instrument's current row
supplies the waveform, its pitch is added to the note's pitch relative to
pitch 24 (C-2), its volume multiplies the note's volume, and its filter byte
is OR'd into the channel's filter state. The instrument playhead SHALL be
retriggered only when the note's pitch differs from the previous note's
pitch, when the previous note's volume was 0, or when the note carries
effect 3; effect 3 on such a note SHALL mean "retrigger" and SHALL NOT apply
the `drop` effect.

#### Scenario: Instrument volume envelope shapes the note

- **WHEN** SFX 0 alternates volume 5 and 2 every row at speed 1 and a note
  with the custom bit, instrument 0 and volume 7 is held for 16 ticks
- **THEN** the channel's effective volume alternates between the two
  instrument levels instead of staying at a constant volume 7

#### Scenario: Instrument pitch is relative to C-2

- **WHEN** a custom-instrument note of pitch 33 plays through an instrument
  whose current row has pitch 24
- **THEN** the sounded pitch is 33; and when that row's pitch is 36 the
  sounded pitch is 45

#### Scenario: Held instrument is not retriggered

- **WHEN** two consecutive rows carry the same custom-instrument note pitch
  with nonzero volume
- **THEN** the instrument playhead keeps advancing across the row boundary
  rather than restarting at instrument row 0

### Requirement: Waveform Instruments

The PSG SHALL treat SFX 0–7 whose loop-start byte (record offset 66) has bit
7 set as a 64-sample signed wavetable held in the record's first 64 bytes,
and SHALL sound a custom-instrument note that selects such an SFX by reading
that wavetable as the oscillator instead of a built-in waveform, one octave
lower when the record's speed byte (offset 65) has bit 0 set. Reading the
wavetable SHALL NOT require a second copy of audio RAM.

#### Scenario: Wavetable replaces the built-in waveform

- **WHEN** SFX 1 has loop-start byte $80 and its first 64 bytes hold a signed
  ramp, and a custom-instrument note selecting instrument 1 plays
- **THEN** the channel outputs that ramp repeated at the note's frequency
  rather than any of the eight built-in shapes

#### Scenario: Bass flag drops an octave

- **WHEN** the same wavetable SFX has bit 0 of its speed byte set
- **THEN** the wavetable repeats at half the note's frequency

### Requirement: SFX Play Offset And Length

The PSG SHALL provide per-channel start-row and length registers that apply
to the next trigger on that channel and are cleared once that trigger is
serviced, so that a trigger write with neither register set plays the whole
record from row 0. A nonzero length SHALL play exactly that many rows from
the start row and then stop the channel, overriding the record's loop points.

#### Scenario: Play a slice of a record

- **WHEN** the CPU writes start row 8 and length 4 for channel 1 and then
  triggers SFX 3 on channel 1
- **THEN** rows 8–11 of SFX 3 play once and the channel stops

#### Scenario: Parameters do not persist

- **WHEN** a channel is triggered again with no start row or length written
- **THEN** the SFX plays from row 0 with its own loop and length metadata

### Requirement: Release From Looping

The PSG SHALL provide a channel command that releases a playing channel from
looping: the channel SHALL continue from its current row, ignore its loop
points from then on, and stop at the end of the record.

#### Scenario: Looping SFX finishes instead of repeating

- **WHEN** a channel is playing an SFX that loops rows 4–8 and the release
  command is written to that channel
- **THEN** playback continues past row 8 to the end of the record and the
  channel then stops

### Requirement: Channel SFX Readback

The PSG SHALL expose, per channel, the number of the SFX the channel is
playing together with its playing bit, so the CPU can stop a given sound
wherever it is playing.

#### Scenario: Locate a sound

- **WHEN** SFX 44 was auto-assigned to channel 2 and the CPU reads channel
  2's SFX register
- **THEN** it reads back 44 with the playing bit set

### Requirement: Music Fade

The PSG SHALL provide a music fade-length register expressed in 16 ms units
that applies to the next music start and to the next music stop: a start
SHALL ramp the music channels' volume from silence to full over that time,
and a stop SHALL ramp it down to silence over that time and then stop the
music and silence its channels. A fade length of 0 SHALL start and stop the
music instantly.

#### Scenario: Fade out over two seconds

- **WHEN** the CPU writes 125 to the fade register and then writes the stop
  command to the music register
- **THEN** the music keeps playing while its volume falls to silence over
  about two seconds, and the music-playing status bit clears at the end of
  the fade

#### Scenario: Fade in

- **WHEN** the CPU writes a nonzero fade length and then starts a pattern
- **THEN** the music becomes audible progressively from silence rather than
  at full volume on the first tick

## MODIFIED Requirements

### Requirement: Hardware Music Sequencer

The PSG SHALL start music at pattern m (0–63) on a single register write,
launching each pattern channel whose disable bit (bit 6) is clear on its
audio channel, and SHALL advance patterns with zero CPU involvement: a
pattern ends when its left-most enabled non-looping channel's SFX finishes
(or after 32 rows of the first launched channel's speed if all launched
channels loop); on end, bit 7 of pattern byte 2 stops music, bit 7 of byte 1
jumps back to the nearest preceding pattern with byte-0 bit 7 set (else
pattern 0), otherwise the next pattern plays. Writing $80 to the music
register SHALL stop music. The music channel mask register SHALL NOT gate
which channels music launches on: it records which channels are reserved for
music, for the CPU to consult when auto-picking a channel for an SFX, and
SHALL reset to "none reserved".

#### Scenario: Looping song

- **WHEN** the CPU writes 0 to the music register for a 3-pattern song whose
  pattern 2 has the loop-back flag and pattern 0 the loop-start flag
- **THEN** patterns 0,1,2,0,1,2,... play indefinitely with no further CPU
  writes

#### Scenario: Stop flag

- **WHEN** the current pattern has the stop flag set and its timing channel
  finishes
- **THEN** all music channels go silent and the music-playing status bit
  clears

#### Scenario: Reserving channels does not silence music

- **WHEN** the CPU reserves channels 0–2 by writing 7 to the music channel
  mask and then starts a pattern whose four channels are all enabled
- **THEN** all four pattern channels sound, and the CPU's auto-picked SFX
  channel avoids channels 0–2 while they are reserved

### Requirement: SFX Filter Byte Interpretation

The PSG SHALL decode each SFX record's filter byte (offset 64) into
per-channel filter state when the SFX is triggered: `noiz` from bit 1,
`buzz` from bit 2, `detune = (byte/8) mod 3`, `reverb = (byte/24) mod 3`,
and `damp = (byte/72) mod 3`, each field taken modulo 3 over the whole byte
range so that no byte value decodes to a level PICO-8 would not produce.

#### Scenario: Filter fields decoded at trigger

- **WHEN** an SFX whose filter byte encodes damp level 2 is triggered on a
  channel
- **THEN** that channel plays through the level-2 low-pass until it stops or
  another SFX retriggers the channel

#### Scenario: Out-of-range byte wraps rather than clamps

- **WHEN** an SFX's filter byte is 224
- **THEN** the decoded damp level is 0, matching `(224/72) mod 3`
