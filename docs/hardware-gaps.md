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
2. **Sprite-vs-tilemap priority.** DONE (behind-split register $4036):
   the list is PARTITIONED, not flagged - entries below the split composite
   before the tile layer, the rest after. Zero extra scan cost (the list is
   still walked exactly once per line), no entry-format change, and the
   reset value 0 keeps old behavior. Chosen over a per-entry priority bit,
   which would have required scanning the list twice per line and would
   have blown the 483-cycle line budget.
3. **Sprite rotation.** Resolved by convention: the port's shards tumble by
   alternating two silhouette patterns plus the flip bits (2 patterns x
   flips = 8 apparent poses). True hardware rotation stays not-recommended:
   per-pixel source rotation in a scanline blitter needs a DDA/multiplier
   per fetch and buys little over pre-rotated frames at 8x8.
4. **Hardware RNG.** DONE: free-running 16-bit maximal LFSR readable at
   $400F. The port uses it for dust spawns and serve variation.

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
