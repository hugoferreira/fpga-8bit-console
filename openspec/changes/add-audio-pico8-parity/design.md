## Context

`rtl/psg.sv` already holds PICO-8's audio RAM verbatim and reproduces the
synthesis core (8 waveforms, 8 note effects, filters, hardware music
sequencer). The gaps found by the manual audit are all *above* the
oscillator: note indirection (SFX/waveform instruments), trigger parameters
(`offset`/`length`/release), readback, and music fades.

Constraints that shape the design:

- The chip targets an iCE40 HX8K (no hard multipliers, 16 KB of EBR). Audio
  RAM (4608 B) and the wave ROM (2 KB) already occupy a large share, so the
  fix must not duplicate audio RAM.
- Audio RAM is a single-read-port memory driven by the sequencer FSM
  (`seq_addr`/`seq_q`); the synthesis datapath currently never touches it.
- The FSM runs at `clk` and has ~29 000 clocks per tick to do ~30 states of
  work, so extra states are free; wide combinational multipliers are not.

## Goals / Non-Goals

- Goals: manual-accurate behaviour for SFX instruments, waveform
  instruments, `sfx()` offset/length/release/stop-by-id, `music()` fade and
  channel reservation.
- Non-Goals: per-channel reverb (still a shared feed-forward echo);
  exhaustive replication of BUZZ's waveform alterations beyond the
  square/pulse/noise cases already implemented; PICO-8's `stat()` surface
  beyond the SFX-id readback needed for `sfx(n, -2)`.

## Decisions

### SFX instruments: a second playhead per channel, one shared effect unit

Each channel gains an instrument playhead (`ins_*`: id, row, tick counter,
speed, loop points, and the current instrument note's pitch/wave/vol/fx).
When the channel's current note has bit 15 set, the playhead advances on
every tick alongside the main row counter and the sounded note becomes:

- waveform  = instrument note's waveform (or the wavetable, see below)
- pitch     = `clamp(note.pitch + ins.pitch - 24, 0, 63)`  ("added relative
              to C-2", C-2 = pitch 24)
- volume    = `note.vol * ins.vol / 7`, computed as `(nv*iv*1317) >> 8` on
              the 0-252 scale the mixer already uses (no divider, no wide
              multiplier: `nv*iv` is 6 bits and 1317 is 5 shifts and adds)
- filters   = channel filter byte OR'd with the instrument SFX's filter byte

Alternative considered: multiplying the two voices' phase increments so the
instrument's pitch effects compose with the note's. Rejected - it needs a
24x16 multiply and a reciprocal of `pinc[24]`, which is expensive without
DSPs, and PICO-8 documents the relationship as an added pitch, not a ratio.

**Effect precedence instead of composition.** The manual says note effects
are "applied on top of the SFX instrument's effects". Evaluating both would
need two effect units and a frequency multiply. Instead the single existing
effect unit takes its inputs (`fcnt`/`sp` for row progress, previous
pitch/volume for slide, tick counter for vibrato/arpeggio, and the record
base for the arpeggio group fetch) from whichever voice owns the effect: the
note's effect wins, and the instrument's effect is used when the note's
effect is 0 or 3. Effect 3 on a custom note is not `drop` - the manual
defines it as "retrigger the instrument", so it never reaches the effect
unit. This covers tremolo/vibrato/arpeggio instruments, which is what the
feature is used for, and is documented as an approximation.

**Retrigger rule.** The playhead restarts only when the new note's pitch
differs from the previous note's pitch, the previous note's volume was 0, or
the new note carries effect 3 - exactly the manual's rule. Otherwise it keeps
running across rows, which is what makes slow instruments (a bell decaying
over several notes) work.

### Waveform instruments: share the audio-RAM read port, do not copy

An SFX whose byte 66 (loop start) has bit 7 set is a 64-sample signed
wavetable in bytes 0-63; byte 65 bit 0 transposes it down an octave. Used as
an instrument, it replaces the wave ROM lookup with an audio-RAM read at
`sfx_base + phase[23:18]`.

Alternative considered: copying the 64 bytes into a per-channel cache at
trigger time. Rejected - 4 x 64 B of extra memory maps to whole EBRs on
iCE40 and the copy adds a burst to the trigger path.

Chosen: the synthesis datapath borrows the sequencer's read port. The
address mux gives the synthesiser priority for the one cycle per voice per
sample it needs. A borrow overwrites the byte the sequencer was waiting on,
so the FSM freezes for that cycle and for one more while the address it
issued last is replayed from a register. Worst case (four wavetable voices
with second voices) that is 16 frozen cycles out of the ~29 000 in a tick.

The read must stay a *single unconditional* `aram[addr]` expression for
yosys to infer a block RAM - an earlier version used two capture registers
(one held through the borrow) and the audio RAM fell out to flip-flops,
taking the module from 3 083 to 42 305 LUT4s. The replay register is what
lets one output register serve both consumers.

### Trigger parameters are latched, not sticky

`$14+c` (start row) and `$18+c` (length) are consumed and cleared when the
channel's trigger is serviced, so an unadorned `sta PSG_CH,y` still means
"row 0, whole record" and no CPU code has to clear them. Length 0 means "to
the end of the record"; a nonzero length overrides the record's loop, which
is how `sfx(n, ch, off, len)` behaves.

### Music fade is a gain on the music channels' volume

`$22` holds the fade length in 16 ms units (2000 ms -> 125), which covers
PICO-8 fades up to ~4 s in one byte. A tick-rate accumulator ramps an 8-bit
gain between 0 and 255; the gain multiplies `eff_vol` only for
`music_owned` channels, reusing the tick-rate FSM slot so the multiply is
8x8 and not in the sample path. Reaching zero on a fade-out stops the music
and silences its channels.

### Two numeric fixes found while touching the volume path

`vol36` computed `{2'b0, vol, 3'b0} + {3'b0, vol, 2'b0}`, which is
`vol*8 + vol*4 = vol*12`, not the `vol*36` its name and the mixer's
`clamp(+/-255) >> 1` were written for. Left as-is, custom-instrument notes
(whose volume goes through the `nv*iv*1317 >> 8` path) would have been three
times louder than plain notes. Corrected to `{vol, 5'b0} + {3'b0, vol, 2'b0}`.

The per-channel tick counter is seeded with `start_row * speed` at trigger
instead of 0, so vibrato and arpeggio in a slice played from an offset keep
the phase they would have had inside the whole record.

### `$21` becomes advisory

PICO-8's `CHANNEL_MASK` reserves channels *for* music; it never restricts
music. Removing the launch gate makes the register pure storage that the CPU
ORs into the playing bits when auto-picking a channel for `sfx()`, which is
where PICO-8 applies it. Reset changes to `$00` (nothing reserved) to match
`music()`'s default.

## Refolding the datapath so the parity work fits

Measured on the real target (`synth_ice40` without `-dsp`, then
`nextpnr-ice40 --hx8k`), the parity features took the module from 5243 to
7546 LCs and dropped Fmax from 25.5 MHz to 19.5 MHz - below the 25 MHz
master clock the chip actually runs at, so it would not have worked on the
board. Ablation builds attributed the area: the effect unit's parallel array
multipliers cost 1468 LUT4, the three asynchronous `pinc` read ports 439,
the asynchronous `recip` ROM 312, and the filter decode's `$div`/`$mod` 61.

The fix is to spend cycles, of which there are ~29 000 per tick and almost
none in use, to buy back area:

- **One shared shift-add multiplier.** Every product the effect unit needs
  is (24-bit magnitude x 8-bit unsigned), so signs are handled outside and
  one 26-bit adder sequenced over 8 iterations replaces every array
  multiplier. `K_FX` became a seven-step micro-sequence: row progress, note
  x instrument volume, the same for the previous row, the effect's frequency
  term, its volume term, the music fade gain, commit.
- **One synchronous port per table.** The three pitch lookups an evaluation
  needs are prefetched into registers by three `K_PF` states, and `recip` is
  read through a registered port, so the tables stop being address-mux logic.
- **A rotating ring for per-channel state.** The 34 sequencer-owned arrays
  (loop points, current and previous note, the instrument playhead, the base
  filters) are only ever accessed at index 0; `K_ROT` rotates them one place
  per channel, four times per pass, so channel k is back at index k whenever
  the sequencer is idle. This removes every 4:1 read mux and 1:4 write
  decoder on that state - at RTL level the module went from 3496 `$mux`
  cells to a fraction of that.

  The ring only works if access is strictly sequential, which forced two
  further changes, both improvements in their own right: triggers are now
  serviced inside the walk (in channel order) rather than out of band, and
  the pattern's timing channel is picked as the walk reaches each launched
  channel instead of by reading all four channels' loop points at once.

- **The same treatment for the synthesis walk.** The oscillator state
  (phase, second-voice phase, noise sample-and-hold, brown integrator,
  dampen one-pole) is a second ring rotated by the sample-rate walk, and the
  mixer's per-channel `sample x volume` runs on its own small shift-add unit
  instead of an array multiplier. The mixer used to run a cycle behind the
  synthesiser, which would have made it read the ring after rotation, so the
  two are now one four-phase walk per channel; the sequencer asks for a
  channel's filter state to be cleared at trigger through a toggle/ack pair
  instead of writing into the ring from outside.

Result: 3649 LUT4 / 5101 LCs and 49.2 MHz - fewer LUTs and fewer LCs than
before the parity work (4192 / 5243), and nearly double the margin on the
25 MHz master clock.

Rejected: adding more effect units. Throughput is not the constraint - an
evaluation runs 480 times a second on a 3.5 MHz clock - so a second unit
would buy nothing, and per-channel units would quadruple the arithmetic to
delete only part of the mux trees the ring removes for free.

Measured and left alone: the phaser's `x85` (27 LUTs - yosys already
reduces a constant multiply to shift-adds) and the fractional clock divider
(4 LUTs). The dampen one-pole is 131 LUTs, which is the feature's own cost.

## Risks / Trade-offs

- Register-map change: `$21` semantics flip and its reset value changes.
  Only `src/main.asm` uses the PSG today and it never wrote `$21`, so the
  practical risk is limited to the new `sfx_play` masking.
- Instrument effect precedence is an approximation of "on top"; a note effect
  and an instrument effect that PICO-8 would stack will only apply the note's.
- The wavetable read shares the audio-RAM port; if a future feature adds
  another audio-RAM consumer the stall logic has to be revisited.
- Logic growth on an already large hx8k design. The instrument playhead is
  mostly registers and reuses the existing effect unit and note-fetch states.

## Open Questions

- PICO-8's exact volume rounding for `note.vol * ins.vol` is undocumented;
  `(nv*iv*1317) >> 8` (i.e. `nv*iv*36/7` on the internal scale) is used so
  that 7x7 maps to full scale.
