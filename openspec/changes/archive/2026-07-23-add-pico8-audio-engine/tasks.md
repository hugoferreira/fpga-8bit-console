## 1. Tables and tools

- [x] 1.1 Wave-ROM generator (tools/gen_psg_tables.py): 8 x 256 x 8-bit
      signed samples from the PICO-8 formulas -> `rtl/psg_waves.hex`
- [x] 1.2 Regenerated `rtl/psg_pitch.hex` for the 22 050 Hz virtual sample
      rate (24-bit phase: inc = round(2^24 * 440*2^((p-33)/12) / 22050))
- [x] 1.3 Reciprocal table `rtl/psg_recip.hex`: 65536/speed for Q8 row
      progress u = (fcnt * recip[speed]) >> 8
- [x] 1.4 Extractor tools/p8_audio.py: decodes the .p8.png ROM (incl. old
      :c: code decompression to report the cart's sfx()/music() calls) and
      dumps $3100-$42FF verbatim to src/breakout_sfx.asm - the PNG ROM
      already holds the packed runtime format, so no repacking was needed

## 2. PSG v2 RTL

- [x] 2.1 Timing: fractional 22 050 Hz `sample_en` divider (CLK_HZ param),
      /183 `tick_en`; vsync tick port removed
- [x] 2.2 Audio RAM (4608 B) + 16-bit PICO-8-addressed auto-inc upload port
- [x] 2.3 Row sequencer per channel: speed/loop metadata from the SFX
      record, loop_start/loop_end semantics incl. length-only convention
- [x] 2.4 Effects engine (per tick): slide, vibrato, drop, fade in/out,
      fast/slow arpeggio (incl. speed<=8 halving and arp row re-fetch)
- [x] 2.5 Synthesis datapath: serialized channels on sample_en, wave-ROM
      lookup, LFSR pitched noise, phaser dual accumulator, shared
      volume multiplier, 4-channel signed mix + PICO-8-style clip
- [x] 2.6 Music sequencer FSM: pattern fetch/launch, timing-channel end
      rule, loop-start/loop-back/stop flow control, channel mask, 32-row
      fallback for all-looping patterns
- [x] 2.7 Register map v2 ($10+c one-write SFX triggers, $20 music, $21
      mask, $03 status) and chip.sv wiring (tick connection removed)

## 3. Verification

- [x] 3.1 TB (rtl/psg_tb.sv, Verilator --binary): row timing at speed,
      loop rows [2,6) cycle, length-only convention stops after N rows
- [x] 3.2 TB: effect trajectories - slide rises f(21)->f(33) across the
      row, drop falls toward zero, fade-in/out volume ramps, arpeggio
      sounds all four group pitches
- [x] 3.3 TB: music - pattern chain 0->1, loop-back returns to the
      loop-start pattern, stop flag halts, $80 stops and silences
- [x] 3.4 Whole-system Verilator build clean; headless capture of the
      booted ROM shows the title song playing pitches that match the
      cart's SFX records (Goertzel analysis of the WAV)

## 4. Runner and game

- [x] 4.1 sim/console.cpp: no code change needed - the existing 44.1 kHz
      Bresenham sampling is a natural 2x zero-order hold of the chip's
      22 050 Hz PCM (comment updated)
- [x] 4.2 main.asm: new register defines; 4608-byte verbatim boot upload;
      sfx_play is one write; brick blips use the cart's rising 2+chain
      slots; SND ids are the cart's own SFX numbers
- [x] 4.3 Cart music wired: title loop music(1) at boot / after game over,
      stopped at serve; level-clear jingle music(6); game-over jingle
      music(7)
- [x] 4.4 docs/hardware-gaps.md updated (audio gap now v2 with the
      remaining fidelity items listed)
