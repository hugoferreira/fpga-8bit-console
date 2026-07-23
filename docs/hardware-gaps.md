# Hardware gaps for faithful game ports

Findings from porting Breakout Hero (PICO-8) with the intent of matching the
original, not dumbing it down. Based on a full read of the original's systems:
angle-based ball physics with sub-stepping, paddle momentum, a general
particle system (gravity, color ramps, rotating sprite shards, line-type
speed effects, ambient background dust), decaying random screen shake,
palette fades/flashes, chain multiplier, sudden death, and pervasive SFX.

## Real gaps (hardware evolution candidates)

1. **Audio - the biggest gap by far.** The console has no sound path at all;
   the original's SFX/music dimension is simply unportable. Needs: a PSG-class
   synth (2-4 channels: pulse/noise, pitch + envelope registers) plus a DAC/
   PWM output on hardware and a sample-rate hook in the simulator runner.
2. **Sprite-vs-tilemap priority.** Ambient background particles float BEHIND
   the bricks in the original. Our compositor draws all sprites above the
   tilemap. Classic solution (NES-style): a per-entry priority bit - entries
   are exactly 31 bits, so the bit fits - and a second scan pass composing
   behind-tiles entries between clear and the tile phase. Budget cost: one
   extra list scan per line.
3. **Sprite rotation.** Brick shards spin as they fly. Era-authentic answer:
   pre-rotated pattern frames in the sheet (cheap, no hardware). Hardware
   rotation would be a luxury; not recommended.
4. **Hardware RNG.** The original uses rnd() everywhere (shake, particles,
   serve variation). A free-running LFSR readable at a PPU register is a
   few dozen LUTs and removes a recurring software burden. Nicety, not a
   blocker (a 6502 LFSR works).

## Covered by existing hardware (no gap)

- Palette fades / whole-screen flashes: screen palette registers ($4020-2F)
- Draw-time recoloring: draw palette + per-entry palette base
- Trails / particles / shards-without-rotation: sprite list capacity (128)
  with per-entry patterns; 1bpp effects patterns cost one plane slot each
- Screen shake: camera registers + inverse sprite offset
- Per-color transparency (palt): $4034 mask
- Dense text / HUD: tilemap font tiles + 4x6 overlay font
- Smooth 60 fps ball motion: fixed on the platform side (see below) plus
  table-driven angle vectors in software; PICO-8 positions are integer at
  draw time, so no subpixel rendering is needed

## Platform (simulator) findings, fixed en route

- The Rust/verilated-rs runner compiled the Verilated model with no C++
  optimization, added an FFI call per half-clock, and let the window
  backpressure the sim thread: ~49-57 fps ceiling. Replaced wholesale by
  a single C++ + SDL2 runner (sim/main.cpp): the model runs at ~130 fps raw
  and is paced to a locked 60.00.
- Simulator pixels are now 3 clocks (the /4 dated from the retired
  textbuffer); the PPU display pipeline needs exactly 3.
