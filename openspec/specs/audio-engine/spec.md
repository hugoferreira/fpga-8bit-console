# audio-engine Specification

## Purpose
TBD - created by archiving change add-pico8-audio-engine. Update Purpose after archive.
## Requirements
### Requirement: PICO-8-Native Audio RAM Upload

The PSG SHALL contain a 4608-byte audio RAM holding music patterns and SFX
records in PICO-8's in-memory layout (music at PICO-8 addresses
$3100–$31FF as 64 patterns x 4 bytes; SFX at $3200–$42FF as 64 records x
68 bytes: 32 two-byte notes, filter byte, speed, loop start, loop end), and
SHALL expose an upload port (address lo/hi registers plus an
auto-incrementing data register) that accepts PICO-8 addresses so cart audio
bytes upload verbatim.

#### Scenario: Verbatim cart upload

- **WHEN** the CPU sets the upload address to $3200 and streams a cart's SFX
  section bytes through the data register
- **THEN** SFX record n is playable from audio RAM at offset n*68 with its
  own speed and loop metadata, with no repacking by the CPU

### Requirement: One-Write SFX Trigger

The PSG SHALL play SFX n (0–63) on channel c (0–3) from row 0 in response to
a single write of n to the channel-c trigger register, and SHALL stop the
channel when $80 is written.

#### Scenario: Trigger and stop

- **WHEN** the CPU writes 5 to channel 2's trigger register
- **THEN** SFX 5 begins playing on channel 2 using the speed and loop
  metadata stored in its record, and a subsequent write of $80 silences the
  channel

### Requirement: PICO-8 Timing Model

The PSG SHALL derive a 22 050 Hz virtual sample rate from the system clock
via a fractional divider and a sequencer tick every 183 samples
(~120.49 Hz), and SHALL advance one tracker row every `speed` ticks as given
by the playing SFX record (speed 0 treated as 1).

#### Scenario: Speed governs row duration

- **WHEN** an SFX with speed 4 plays
- **THEN** each row lasts 4 ticks (~33.2 ms) and a full 32-row SFX lasts
  ~1.06 s

### Requirement: Eight PICO-8 Waveforms

The PSG SHALL synthesize the eight PICO-8 instruments with PICO-8's shapes
and relative amplitudes: triangle, tilted saw, saw, square (50% duty), pulse
(~31.6% duty), organ, pitched noise (sample-and-hold LFSR whose update rate
tracks pitch), and phaser (two detuned oscillators at ~109/110 frequency
ratio, summed). Pitch k SHALL map to 440 x 2^((k-33)/12) Hz; note volume
0–7 SHALL scale amplitude linearly with volume 0 silent.

#### Scenario: Distinct timbres at equal pitch

- **WHEN** the same pitch and volume play with waveform 0 (triangle) and
  waveform 5 (organ)
- **THEN** the two produce different waveform shapes matching their PICO-8
  formulas, not a shared approximation

### Requirement: Note Effects

The PSG SHALL evaluate the note effect field each tick: 1 slide (interpolate
phase increment and volume linearly across the row from the previous row's
values, previous pitch initialised to 24 at trigger), 2 vibrato (~7.5 Hz
triangle LFO, ~quarter-tone depth), 3 drop (frequency scaled by 1-u across
the row), 4 fade in (volume x u), 5 fade out (volume x (1-u)), 6/7
arpeggio (cycle pitches of the row's group of four at 4- or 8-tick periods,
halved to 2/4 when the SFX speed is 8 or less).

#### Scenario: Slide spans an octave

- **WHEN** a row with pitch 33 and effect 1 follows a row with pitch 21
- **THEN** the emitted frequency rises continuously from ~220 Hz to ~440 Hz
  across the row instead of stepping

#### Scenario: Arpeggio reads its row group

- **WHEN** effect 6 plays on row 5 of an SFX with speed 16
- **THEN** the sounded pitch cycles through the pitches of rows 4,5,6,7,
  advancing every 4 ticks

### Requirement: SFX Loop Semantics

The PSG SHALL loop rows [loop_start, loop_end) while a channel plays when
loop_start < loop_end; SHALL treat loop_start as the SFX length in rows when
loop_start > 0 and loop_end = 0; and SHALL otherwise play 32 rows and stop.

#### Scenario: Length-only convention

- **WHEN** an SFX record has loop_start 24 and loop_end 0
- **THEN** the SFX plays rows 0–23 and the channel stops

### Requirement: Hardware Music Sequencer

The PSG SHALL start music at pattern m (0–63) on a single register write,
launching each pattern channel whose disable bit (bit 6) is clear on its
audio channel (subject to the music channel mask register), and SHALL
advance patterns with zero CPU involvement: a pattern ends when its
left-most enabled non-looping channel's SFX finishes (or after 32 rows of
the first launched channel's speed if all launched channels loop); on end,
bit 7 of pattern byte 2 stops music, bit 7 of byte 1 jumps back to the
nearest preceding pattern with byte-0 bit 7 set (else pattern 0), otherwise
the next pattern plays. Writing $80 to the music register SHALL stop music.

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

### Requirement: Status Readback

The PSG SHALL expose readable status: per-channel playing bits and a
music-playing bit, plus the current music pattern number.

#### Scenario: Poll for completion

- **WHEN** the CPU reads the status register after a one-shot SFX ends
- **THEN** that channel's playing bit is 0

### Requirement: Four-Channel Mix Output

The PSG SHALL mix the four channels at the 22 050 Hz virtual sample rate
into the existing 8-bit unsigned PCM output with saturation (no wrap), and
volume/amplitude products SHALL keep sufficient width that full-scale
notes are not truncated.

#### Scenario: Mix saturates instead of wrapping

- **WHEN** four channels play full volume simultaneously
- **THEN** the PCM output clamps at full scale rather than wrapping around

