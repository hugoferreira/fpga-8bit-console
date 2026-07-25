## 1. Trigger parameters and readback

- [x] 1.1 Add per-channel start-row (`$14+c` write) and length (`$18+c`
      write) latches, consumed and cleared when the trigger is serviced
- [x] 1.2 Start playback at the latched row; stop after the latched number of
      rows, overriding the record's loop points
- [x] 1.3 Add the release-from-looping command (`$81` to `$10+c`) and make
      the loop check honour it
- [x] 1.4 Add the `{playing, sfx_id}` readback on `$14+c`

## 2. Music fade and channel reservation

- [x] 2.1 Add the fade-length register (`$22`, 16 ms units) and a tick-rate
      gain ramp applied to `music_owned` channels' effective volume
- [x] 2.2 Fade in on music start, fade out on music stop, stopping the music
      and silencing its channels when the fade-out reaches zero
- [x] 2.3 Remove the `$21` gate on music launch, reset `$21` to `$00`

## 3. SFX instruments

- [x] 3.1 Add the per-channel instrument playhead state (id, row, tick
      counter, speed, loop points, current instrument note)
- [x] 3.2 Fetch the instrument record's metadata and filter byte on
      retrigger; OR the filter byte into the channel's filter state
- [x] 3.3 Advance the playhead per tick and fetch its note; apply the
      retrigger rule (pitch change, previous volume 0, or note effect 3)
- [x] 3.4 Combine voices: waveform from the instrument, pitch added relative
      to 24 with clamping, volume `(nv*iv*1317) >> 8`
- [x] 3.5 Route the effect unit's inputs from the voice that owns the effect
      (note effect wins; instrument effect when the note's is 0 or 3)

## 4. Waveform instruments

- [x] 4.1 Detect the wavetable flag (record byte 66 bit 7) on instrument
      retrigger and latch the bass flag (byte 65 bit 0)
- [x] 4.2 Share the audio-RAM read port with the synthesis datapath, stalling
      the sequencer FSM on the borrowed cycles
- [x] 4.3 Sound the wavetable at `phase[23:18]`, halving the increment when
      the bass flag is set

## 5. Numeric fixes

- [x] 5.1 Take the dampen field modulo 3 instead of clamping it
- [x] 5.2 Correct `vol36` from `vol*12` to `vol*36` so the mix level matches
      the clamp and shift the mixer was written for
- [x] 5.3 Seed the per-channel tick counter with `start_row * speed`

## 6. Verification and integration

- [x] 6.1 Extend `rtl/psg_tb.sv`: offset/length, release, SFX-id readback,
      music fade in/out, reservation not gating launch, instrument volume
      multiply and pitch offset, retrigger rule, wavetable oscillator, damp
      modulo
- [x] 6.2 Run the full PSG testbench and confirm every case passes
- [x] 6.3 `src/main.asm`: fade the title music out over 2 s to match the
      cart's `music(-1, 2000)`, and OR the reserved mask into the playing
      bits in `sfx_play`
- [x] 6.4 Build the ROM and run the simulator to confirm the port still runs

## 7. Refold the datapath (area and timing)

- [x] 7.1 Drop `-dsp` from `YOSYS_FLAGS`: the hx8k has no DSP blocks and
      nextpnr cannot place the `SB_MAC16` cells yosys infers
- [x] 7.2 Replace the filter decode's `$div`/`$mod` with a 32-entry case
- [x] 7.3 Fold the effect unit's array multipliers onto one shared shift-add
      unit driven by a seven-step micro-sequence in `K_FX`
- [x] 7.4 Prefetch the three pitch increments through one synchronous `pinc`
      port (`K_PF0..2`) and read `recip` through a registered port
- [x] 7.5 Put the 34 sequencer-owned per-channel arrays in a rotating ring
      (`K_ROT`), servicing triggers inside the walk and picking the pattern's
      timing channel as the walk reaches it
- [x] 7.6 Hold the reverb level for one delay line after the last request so
      a note that ends still gets its echo back (the spec's scenario; the old
      test was too weak to catch it)
- [x] 7.7 Ring the synthesis walk's oscillator state and sequence the
      mixer's sample x volume multiply; merge the mixer into the walk so it
      no longer reads the ring a cycle late
- [x] 7.8 Re-measure: 5938 -> 3649 LUT4, 7546 -> 5101 LCs, 19.5 -> 49.2 MHz,
      80 testbench checks green, console sim still 60 fps
