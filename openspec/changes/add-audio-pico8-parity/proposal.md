## Why

The PSG was audited line-by-line against the PICO-8 manual's sound chapters
(2.4 SFX editor, 2.5 music editor, 6.5 `sfx()`/`music()`). The synthesis core
matches, but seven documented behaviours are missing or wrong, so a cart's
audio image does not always sound the way PICO-8 plays it:

1. **SFX instruments are ignored.** Bit 15 of a note selects SFX 0-7 as the
   instrument instead of a built-in waveform. `rtl/psg.sv` drops the bit, so
   such a note plays as built-in wave 0-7 at the wrong pitch, volume and
   texture. Any 0.2.0+ cart that uses custom instruments is wrong today.
2. **Waveform instruments are ignored** (SFX 0-7 whose byte 66 has bit 7 set
   are a 64-sample wavetable, with byte 65 bit 0 transposing down an octave).
3. **`sfx(n, ch, offset, length)` offset/length cannot be expressed** - the
   trigger register always starts at row 0 and runs to the record's end.
4. **`sfx(-2, ch)` (release from looping) has no encoding.**
5. **`sfx(n, -2)` (stop sound n on any channel) is impossible** - the CPU
   cannot read back which SFX a channel is playing (PICO-8 exposes this as
   `stat(16..19)`).
6. **`music(n, fade_len)` fades are missing.** The Breakout cart calls
   `music(-1, 2000)`; the port stops the title music instantly instead of
   fading it over two seconds.
7. **`CHANNEL_MASK` has inverted meaning.** PICO-8 reserves the masked
   channels *for* music (auto-selected `sfx()` avoids them); the PSG instead
   uses the mask to gate which channels music may launch on, so
   `music(0, 0, 7)` silences the pattern's channel 3 entirely.

Two numeric deviations are also fixed. The filter byte's dampen field is
clamped rather than taken mod 3, so filter bytes >= 216 decode as dampen 2
where PICO-8 decodes 0. And the note-volume scale named `vol36` in
`rtl/psg.sv` actually computes `vol * 12`, not `vol * 36`: every note has
been mixed at a third of its level, so a full-volume triangle reaches a
sixth of full scale instead of the half scale the mixer's clamp and shift
are sized for.

The manual audit and the previous RTL are useful evidence, but neither is the
fidelity oracle. PICO-8's own MUSIC-mode WAV exporter synthesises complete
patterns, including channel mixing and pattern flow, and is therefore the
reference implementation for the remaining acoustic work. The parity change
adds a generated probe corpus and comparison harness so each assumption can be
tested independently against WAVs exported by PICO-8.

## What Changes

- **SFX instruments**: a note with bit 15 set runs SFX 0-7 as a per-channel
  instrument voice - its row supplies the waveform, its pitch is added
  relative to C-2, its volume multiplies the note's, and its filter byte is
  OR'd into the channel's filters. The instrument voice is only retriggered
  when the note's pitch changes or the previous note had zero volume; effect
  3 on the note forces a retrigger instead of acting as `drop`.
- **Waveform instruments**: SFX 0-7 with byte 66 bit 7 set are read as a
  64-sample signed wavetable straight from audio RAM, transposed down an
  octave when byte 65 bit 0 is set.
- **New registers** `$14+c` (start row) and `$18+c` (length in rows), latched
  for the next trigger on that channel and cleared when it is serviced, so a
  plain trigger write still means "row 0, whole record".
- **New channel command** `$81` = release from looping.
- **New readback** `$14+c` = `{playing, sfx_id[5:0]}`.
- **New register** `$22` = music fade length in 16 ms units, applied to the
  next music start (fade in) or stop (fade out); a fade-out stops the music
  when it reaches zero.
- **BREAKING (register semantics)**: `$21` no longer gates which channels
  music launches on. It is now the "reserved for music" mask that the CPU
  reads when auto-picking a channel for `sfx()`. Music always launches every
  enabled pattern channel. Reset value changes from `$0F` to `$00`.
- The note-volume scale is corrected to `vol * 36`, restoring the mix level
  the clamp and shift in the mixer were written for.
- The per-channel tick counter that drives vibrato and arpeggio starts at
  `start_row * speed`, so a slice played from an offset keeps the phase it
  would have had inside the whole record.
- `src/main.asm` uses the fade register for the cart's `music(-1, 2000)` and
  honours the reserved mask in `sfx_play`.
- A generated oracle corpus covers the built-in waveforms, pitch and row
  timing, note effects, multi-channel mixing, pattern flow, filters and custom
  instruments with one assumption per cartridge.
- A macOS capture command drives PICO-8 into MUSIC mode and invokes its offline
  WAV exporter in an isolated home. A separate command renders the same
  4608-byte audio image through the Verilated PSG at the board's derived clock.
- A comparator aligns the streams and reports sample, row, envelope and
  stochastic-noise metrics. Deterministic cases are strict regression gates;
  noise is assessed statistically because PICO-8 does not expose or reset the
  exporter's noise PRNG state.
- Verilator host throughput and the old 159-clocks-per-sample console lowering
  are explicitly not architectural constraints. Hardware scheduling is checked
  against the >=100 MHz derived PSG clock used by the board.

## Impact

- Affected specs: `audio-engine`
- Affected code: `rtl/psg.sv`, `rtl/psg_tb.sv`, `src/main.asm`,
  `sim/psg_wav.cpp`, PSG oracle tools and generated test fixtures
