## Why

Porting a real game (Breakout Hero, PICO-8 BBS cart 53976) exposed two console gaps: there was no input path at all (the simulator never forwarded keys into the RTL), and the memory arbiter only decoded $0000-$0FFF as RAM, silently open-bussing any program larger than 4KB - the port's level data was the first thing to cross the line.

## What Changes

- **Buttons register**: new `buttons[7:0]` input threaded top -> chip -> PPU, readable at $4007 (bit0 left, bit1 right, bit2 up, bit3 down, bit4 O, bit5 X - PICO-8 ordering). The Rust runner samples minifb keys (arrows + Z/X) once per frame; the hardware top ties the port to 0 until physical buttons exist.
- **Full 64KB RAM map**: the arbiter now treats everything outside the device windows ($4000-$40FF PPU, $E000-$E9FF overlay, $F000-$F7FF tilemap) as RAM, matching the 64KB ram_async that always backed it.
- First real cart port ships as `src/main.asm` + `src/breakout_data.asm`: Breakout Hero's 15 level layouts and paddle/ball art extracted from the cart, original 6502 game logic (serve/play/game-over states, 8.8 fixed-point ball physics, paddle english zones, two-point brick collision, BCD scoring, brick types with hardened/indestructible behavior).

## Impact

- Affected specs: sprite-rendering (CPU interface gains $4007)
- Affected code: `rtl/sprite_compositor.sv`, `rtl/chip.sv`, `rtl/top_simulator.sv`, `rtl/top.sv`, `rtl/memory_arbiter.sv`, `rust/src/main.rs`, `src/main.asm`, `src/breakout_data.asm`
- Scope notes: power-ups, multiball, sudden death, high scores and audio from the original cart are not ported (no audio hardware; kept minimal deliberately)
