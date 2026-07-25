## ADDED Requirements

### Requirement: Sixteen-Voice Pool

The PSG SHALL synthesise from a pool of sixteen voices, each carrying a
two-bit logical channel tag, rather than from four fixed channels. Voices
SHALL be allocated to sounds and released when the sound ends; a voice's tag
SHALL identify which of the four cart-visible channels it belongs to. The
cart-facing register map SHALL continue to address channels 0-3, not voices.

#### Scenario: Sounds layer instead of cutting each other off

- **WHEN** five auto-allocated sound effects are triggered while four voices
  are already playing music
- **THEN** all five sound, on five further voices, and none of the music
  voices is disturbed

#### Scenario: A voice returns to the pool

- **WHEN** a sound effect on an auto-allocated voice reaches the end of its
  record
- **THEN** that voice stops and becomes available for the next allocation

### Requirement: Hardware Auto-Channel Allocation

The PSG SHALL implement PICO-8's `sfx(n, -1)` in hardware: a single register
write SHALL start SFX n on a voice that is not playing, with no CPU search.
A voice that the music sequencer owns SHALL never be selected. When no voice
is free the request SHALL be dropped, leaving every playing voice untouched.

#### Scenario: Auto-allocation never takes a music voice

- **WHEN** music is playing on four voices and the CPU issues an
  auto-allocated SFX
- **THEN** the SFX starts on a voice outside those four and the music
  continues without interruption

#### Scenario: Auto-allocation with a full pool

- **WHEN** all sixteen voices are playing and the CPU issues an
  auto-allocated SFX
- **THEN** the request is dropped and no playing voice is stopped or
  restarted

#### Scenario: Explicit channel still replaces

- **WHEN** the CPU triggers an SFX on an explicitly named channel that
  already has a voice carrying that tag
- **THEN** that voice is replaced by the new SFX

## MODIFIED Requirements

### Requirement: Hardware Music Sequencer

The PSG SHALL start music at pattern m (0–63) on a single register write,
launching each pattern channel whose disable bit (bit 6) is clear on a voice
tagged with that channel index, and SHALL advance patterns with zero CPU
involvement. A pattern's length in ticks SHALL be fixed when the pattern
launches — taken from the left-most launched non-looping channel's speed and
row count, or 32 rows of the first launched channel's speed if all launched
channels loop — and the pattern SHALL end when a free-running tick counter
reaches that length. The end of a pattern SHALL NOT depend on the state of any
individual voice. On end, bit 7 of pattern byte 2 stops music, bit 7 of byte 1
jumps back to the nearest preceding pattern with byte-0 bit 7 set (else pattern
0), otherwise the next pattern plays. Writing $80 to the music register SHALL
stop music.

#### Scenario: Looping song

- **WHEN** the CPU writes 0 to the music register for a 3-pattern song whose
  pattern 2 has the loop-back flag and pattern 0 the loop-start flag
- **THEN** patterns 0,1,2,0,1,2,... play indefinitely with no further CPU
  writes

#### Scenario: Stop flag

- **WHEN** the current pattern has the stop flag set and its tick counter
  reaches the pattern length
- **THEN** all music voices go silent and the music-playing status bit clears

#### Scenario: A sound effect cannot move the pattern boundary

- **WHEN** sound effects are triggered repeatedly throughout a pattern
- **THEN** the pattern ends at exactly the same tick as it would have with no
  sound effects at all

### Requirement: Four-Channel Mix Output

The PSG SHALL reduce its voices to one 22 050 Hz sample through a binary tree
of pairwise soft additions in voice order, matching PICO-8: each pair is summed
and, where the sum exceeds ±24576 of full scale, the excess SHALL be compressed
5:1 rather than clipped. Volume and amplitude products SHALL keep sufficient
width that full-scale notes are not truncated. The reduction order SHALL be
part of the specified behaviour, because soft addition is not associative.

#### Scenario: Loud mixes compress rather than clip

- **WHEN** several voices play full-volume notes simultaneously
- **THEN** the summed output is compressed above the soft-add threshold and
  never wraps, and quiet material below the threshold is summed unchanged

#### Scenario: Reduction is pairwise

- **WHEN** four voices carry samples a, b, c and d
- **THEN** the result is `soft_add(soft_add(a,b), soft_add(c,d))`, not a flat
  sum passed through one limiter

### Requirement: Status Readback

The PSG SHALL report, on readable registers, which channels are playing, which
SFX and row each channel is on, whether music is playing, the current pattern,
the music channel mask, and which channels the music currently occupies. A
trigger written but not yet serviced SHALL already read as playing, so that
back-to-back triggers cannot collide.

#### Scenario: Music-occupied channels are readable

- **WHEN** the CPU reads the music channel mask register while a pattern is
  playing on two channels
- **THEN** the reply names those two channels as occupied by the music,
  independently of the reservation mask

#### Scenario: Poll for completion

- **WHEN** the CPU reads the status register after a one-shot SFX ends
- **THEN** that channel's playing bit is 0

#### Scenario: Pending trigger reads as busy

- **WHEN** the CPU triggers an SFX and immediately reads the status register
- **THEN** that channel already reads as playing
