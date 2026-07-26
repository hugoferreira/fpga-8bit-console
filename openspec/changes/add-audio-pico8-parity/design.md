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
- The PSG clock is derived from the board master clock and runs at 112.5 MHz on
  the hardware targets used for fidelity and synthesis checks. That provides
  about 5102 hardware clocks per 22.05 kHz sample and about 933 000 per
  sequencer tick. Verilator lowering and host speed affect only how long a test
  takes; they do not define an RTL cycle budget.

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
with second voices) that is 16 frozen cycles out of roughly 933 000 hardware
clocks in a tick.

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

The fix is to spend otherwise idle hardware cycles to buy back area:

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

## PICO-8 WAV oracle

### One assumption per generated cartridge

The reference corpus is generated rather than copied from a game. Each
cartridge contains pattern 0 with a stop flag and only the SFX required for one
claim. This avoids accidental interactions and prevents looped songs from
hitting PICO-8's 32768-music-tick export ceiling. Cases cover:

- each built-in waveform at controlled pitch, volume and duration;
- pitch boundaries and row speeds;
- each note effect, including transitions that expose effect phase;
- two- and four-channel mixes with unequal pitches and volumes;
- pattern chaining, stop and loop flow in dedicated bounded cases;
- filter levels, SFX instruments and waveform instruments.

Noise cases are separate from deterministic cases. PICO-8's exporter preserves
or seeds private PRNG state, so repeated noise exports have stable duration and
distribution but are not byte-identical.

### Capture and render are separate reproducible steps

The reference capture tool launches the installed PICO-8 in a temporary home,
uses physical modifier-key events to select MUSIC mode, exports pattern 0, and
terminates only the process it launched. It never uses a global `pkill` and
never modifies the user's normal PICO-8 configuration.

The RTL renderer consumes the same generated 4608-byte music/SFX image and
runs the PSG at 112.5 MHz, matching the board clock domain. Its execution time
on a particular host is reported only as test cost. No Verilator host-cycle
count is accepted as a design constraint.

### Diagnostics before thresholds

The comparator first validates WAV format and sample count, then aligns the
candidate to the reference over a bounded leading window. For deterministic
cases it reports DC offset, gain fit, correlation, normalised RMS error, peak
error and row-boundary timing. For stochastic cases it compares block RMS,
peak distribution, zero-crossing density and short-lag autocorrelation.

Initial runs are diagnostic: their measured distribution establishes explicit
per-case tolerances. A tolerance may only be committed with the PICO-8
reference measurement that justifies it; the old RTL is never used to bless a
result.

The initial gates are deliberately strict enough to expose a single synthesis
tick transition while allowing sub-sample phase and integer-rounding
differences: deterministic duration must be exact, fitted gain must be within
10%, correlation at least 0.99, and normalised RMS error at most 0.10.
Stochastic cases also require exact duration; block mean RMS and peak must each
be within 10%, while zero-crossing density and every measured autocorrelation
lag may differ by at most 0.15 absolute. Each matrix result carries the
applicable values, so a later threshold change cannot silently reinterpret old
evidence.

### Initial PICO-8 measurement

The first valid MUSIC-mode matrix contains 33 bounded exports. The capture
tool proved MUSIC mode from the export signature (one `%d` WAV, rather than
the 64-file SFX signature) on every case. PICO-8 exported mono signed 16-bit
audio at 22,050 Hz.

- All seven pitch anchors from note 0 through 63 passed. This rejected the
  floating equal-temperament table and validated the integer `_note_dx`
  reconstruction and octave shifts.
- Triangle, tilted saw, square, pulse and organ passed the initial oscillator
  gate. Saw measured correlation 0.9933 / NRMSE 0.1160 and phaser 0.9009 /
  0.4340, isolating waveform implementation differences rather than pitch.
- Two-channel mixing passed (gain 1.0051, correlation 0.9979, NRMSE 0.0652).
  Four-channel mixing did not (gain 0.8824, correlation 0.8703), isolating the
  nonlinear reduction tree at higher occupancy.
- Basic noise differed in level (mean RMS 4,364 versus PICO-8's 6,926) and
  correlation shape, while the NOIZ-filter probe matched its zero-crossing and
  autocorrelation shape. Noise is therefore judged statistically, never by
  PRNG sequence identity.
- Every note-effect probe initially failed. Exact recovery of PICO-8's
  two-tick vibrato sequence improved its NRMSE from 0.2982 to 0.2562; fixing
  the drop complement improved correlation from 0.0566 to 0.9118. The
  remaining common error is consistent with PICO-8's 64-of-183-sample
  old-state crossfade, which the RTL does not yet implement.
- Offline export established that SFX length metadata is authoritative:
  two length-eight chained patterns export 16 ticks, and a length-16 SFX at
  speed two exports 32 ticks. After correcting the corpus expectation, the RTL
  durations are exact. A separate RTL off-by-one inserted one silent tick
  between chained patterns; advancing after zero-based tick `length-1`
  removes it.

### Failure-driven RTL work

Failures are fixed in the smallest layer that explains them: clock/tick
generation, sequencing, oscillator, effect, filter, or mixer. Every fix adds
or tightens the corresponding oracle case and keeps the structural
`rtl/psg_tb.sv` regression. Area and timing are measured on iCE40 after each
cluster; fidelity thresholds are not weakened to recover LCs.

### Verification after the first correction pass

The complete bounded matrix was rerun after the pitch table, mixer scale,
waveform polarity, effect-formula and pattern-boundary corrections. Sixteen of
33 cases clear the initial gate: five basic deterministic waveforms, all seven
pitch anchors, two- and four-channel mixing, NOIZ-filter shape and
explicit-length playback. Seventeen remain diagnostic failures: saw and phaser
oscillator shape; basic noise level/shape; seven note effects; four other
filter modes; both custom-instrument paths; and the pattern-transition
crossfade. Durations are exact in every bounded case.

`make test-psg` completes with all testbench checks passing. The iCE40 HX8K
subsystem build at RTL fingerprint `348e80c6e7d1` uses 5,391/7,680 logic cells
(70%) and 19/32 EBRs (59%). Routed Fmax is 31.36 MHz against that target's
50 MHz constraint; the critical path is the mixer leaf into the first
soft-add level. The design therefore fits, but does not yet close timing at
either 50 MHz or the 112.5 MHz master-derived PSG clock. This routed result,
not Verilator host execution time or a fixed simulator-cycle budget, is the
timing constraint for the next refold.

The next fidelity layer is PICO-8's old-state transition renderer. It should
reuse the existing single waveform port and multipliers over time: retain the
previous oscillator state in the unused words of each synthesis record,
serialize a second 64-sample continuation, and crossfade old/new products
before the soft-add tree. That addresses the common effect and pattern-start
signature without adding parallel oscillators or arithmetic. The remaining
independent work is the exact phaser history comb, PICO-8's stateful noise
generator, raw-16.16 slide interpolation, filter transfer functions and
custom-wave interpolation.

### Verification after the serialized transition/noise pass

The old-state renderer now occupies the padding in each 16-word oscillator
record and uses the existing waveform port and shift-add arithmetic over time.
Each parameter transition renders the copied phase/increment/wave/volume
continuation and blends it over 64 samples. The same pass added the recovered
stateful noise distribution, integer-domain effect truncation, zero-amplitude
phase reset, exact BUZZ thresholds and DETUNE level-1 ratio.

The resulting bounded PICO-8 matrix has 25/33 cases clean. All eight built-in
waveforms, seven pitch anchors, both mixer probes, stochastic noise, NOIZ and
BUZZ filters, vibrato, fade-in/out, both arpeggios, explicit length and basic
pattern timing pass. The remaining deterministic boundary is explicit:

- slide: gain 1.0008, correlation 0.9923, NRMSE 0.1242;
- drop: gain 0.9990, correlation 0.9917, NRMSE 0.1283;
- DETUNE-1: gain 0.9905, correlation 0.9883, NRMSE 0.1523;
- REVERB-1: gain 0.9413, correlation 0.9740, NRMSE 0.2267;
- DAMPEN-1: gain 0.8937, correlation 0.9571, NRMSE 0.2898;
- SFX instrument: gain 1.0038, correlation 0.9950, NRMSE 0.1002;
- waveform instrument: gain 1.0171, correlation 0.9840, NRMSE 0.1779;
- chained-pattern transition: gain 1.0070, correlation 0.9947,
  NRMSE 0.1033.

The effect fixes are binary-derived rather than fitted to the old RTL.
Vibrato/drop now multiply PICO-8's integer `dp` before appending the FPGA's
eight phase-fraction bits; slide consumes the just-completed row fraction
instead of the preceding microprogram's value; and a zero-amplitude oscillator
freezes and resets phase as exposed by repeated fade-in rows. Vibrato improved
from correlation 0.9748 / NRMSE 0.2229 to 0.9999 / 0.0163, and fade-in from
effectively uncorrelated to 0.9999 / 0.0160. DETUNE's recovered
`floor(dp*255/256)` secondary improved correlation from 0.7987 to 0.9883; a
shift-only 13/16 normalization corrected fitted gain from 0.7579 to 0.9905.

A serialized adjacent-read wavetable interpolation was implemented and
measured, then rejected. It increased the subsystem to 6,641 LCs while the
PICO-8 waveform-instrument case still failed (correlation 0.9830, NRMSE
0.1835), slightly worse than the smaller nearest-sample path. The oracle and
area report therefore vetoed the implementation rather than allowing an
unverified formula to become architecture.

Three one-boundary exports now separate transition blending from oscillator
state. A volume-only change is clean (correlation 0.9999, NRMSE 0.0164), as is
a triangle-to-square change (correlation 0.9999, NRMSE 0.0149). An otherwise
identical C-2 to C-3 pitch boundary reproduces the failure (correlation 0.9946,
NRMSE 0.1034). This rejects a generic ramp rewrite: the 64-sample blend works
for amplitude and waveform changes, while pitch continuation does not.

The binary initially suggested the two phase accumulators (`p` and `q`) as the
cause, but the complete state calculation rejects that larger rewrite for an
ordinary unfiltered voice: it publishes `dq = dp`, so the precombined waveform
ROM remains valid. The focused WAV instead exposes a persistent one-sample
phase lead beginning exactly at a direct note-pitch boundary. PICO-8 emits the
first changed-pitch sample at the preceding phase before consuming the new
increment.

The accepted correction publishes one `direct basic pitch` bit with the
sequencer's parameter record and retains the preceding base pitch in six spare
bits of the oscillator record. A non-silent direct note whose base pitch and
increment both change holds the new phase for its first transition sample.
Effect-driven increment changes and custom instruments do not take this path.
The pitch-only probe improves from correlation 0.9946 / NRMSE 0.1034 to
0.9998 / 0.0177, while the volume and waveform controls remain at 0.9999 /
0.0164 and 0.9999 / 0.0149. The complete matrix is required because a broader
increment-change hold made arpeggios and SFX instruments regress, and was
rejected before this explicit qualifier was added.
Those three focused cases now carry a tighter correlation floor of 0.999 and
NRMSE ceiling of 0.03 instead of the corpus-wide 0.99 / 0.10 gate.

With the three controls added, the complete bounded matrix is now 28/36
clean. That is the previous 25/33 clean set plus all three isolated transition
cases; no pre-existing pass regressed. The remaining eight failures are still
slide, drop, DETUNE-1, REVERB-1, DAMPEN-1, both custom-instrument paths and
the chained-pattern boundary. The structural Verilator PSG testbench remains
fully green.

The accepted state costs 6,120/7,680 HX8K logic cells and 19/32 EBRs at seed
1. Routed Fmax is 31.47 MHz against the subsystem's 50 MHz constraint, with
the soft-add tree still critical. Relative to the preceding 6,097-cell
measurement, the direct-pitch qualifier and retained pitch consume 23 cells;
they do not add memory or create a new critical-path class.

The Verilator timing testbench completes with all structural checks passing at
an exact clocks-per-sample relationship; its wall time is not a requirement.
The final HX8K subsystem build uses 6,134/7,680 LCs (79%) and 19/32 EBRs (59%).
Routed Fmax is 31.68 MHz against the subsystem target's 50 MHz constraint, with
the soft-add tree still critical. It fits but does not close the target or the
112.5 MHz board-derived PSG clock, so timing closure and the eight oracle
failures remain open work rather than being hidden by a simulator-cycle
budget.

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
