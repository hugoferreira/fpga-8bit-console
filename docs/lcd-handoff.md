# LCD bring-up handoff

Written 2026-08-07, mid-debug, because the session that produced it was
introducing regressions faster than it was fixing them. State is committed but
**the display is not correct**. Read the "Stop and do this first" section before
touching `rtl/lcd.sv`.

## Where it stands

Working, verified on a Tang Primer 20K + Dock with MuseLab PMODs:

- 27 MHz crystal, rPLL 112.5 MHz, CLKOUTD /32, both user LEDs (active **low**,
  silkscreened LED4/LED5 where litex calls them led0/led1).
- PMOD0 audio: `dsigma` -> PAM8403 -> speaker. Confirmed with a tone.
- PMOD2 panel: pins, orientation, power all correct. Panel initialises, accepts
  **56.25 MHz** SPI with a per-pixel grid pattern (a flat fill cannot detect a
  bit slip - do not use one to qualify a link).
- Panel init bytes, all measured not guessed: `INVOFF` (0x20), `MADCTL 0xE8`
  (MY|MX|MV|BGR). See `rtl/setup_st7789_565.hex`.
- The console runs: CPU, PPU, compositor, tiles and sprites all render.

## Broken, in priority order

1. **The image scrolls up one row per frame.** An extra byte per frame, so the
   panel's address pointer is one byte further on each time. I removed one such
   byte (the `v_blank` -> `start_frame` path asserted `load` with a stale
   `dataout`) and the scroll persisted, so there is at least one more. Suspect
   the `h_blank`/`v_blank` resume paths and the `load <= 1'b1` at the top of the
   `byte_done` block, which fires on transition cycles that have no real byte.

2. **Sprites render but do not move.** `vsync` used to be
   `state == start_frame`; the frame now re-issues RAMWR from blanking without
   passing through `start_frame`, so it never asserted and the console's game
   loop never ticked. `rtl/lcd.sv` now has
   `assign vsync = (state == h_blank) && (vpos == HEIGHT);` - **unverified**.
   Check it actually pulses once per frame and is wide enough for `masterclk`
   (284 ns) to sample.

3. **Colours are wrong.** Observed background blue, tiles green, text red.
   The reference is `build/shot.ppm` from `make shot`: dark navy background
   (29,43,83), pink tiles (255,119,168), white text, yellow ball, light-grey
   paddle. Do **not** flip `INVON`/`BGR` speculatively - decode the actual byte
   stream and compare against that file. Two earlier "colour" faults turned out
   to be byte-alignment bugs, not colour-space ones. White is symmetric under
   both inversion and R<->B swap, so **if white is not white, the fault is
   alignment, not colour**.

## Stop and do this first

`rtl/lcd_tb.sv` is the only thing that made progress possible, and it is still
too weak. Every regression below got through it. Before changing `lcd.sv` again:

- **Decode two consecutive frames** and assert the second starts exactly where
  the first ended. The bench decodes one frame, so per-frame drift - the current
  top bug - is structurally invisible to it. This is the single highest-value
  change available.
- **Assert bytes-per-line == 2*WIDTH** and bytes-per-frame == `2*WIDTH*HEIGHT`
  explicitly, rather than inferring position from a contiguous decode.
- **Assert `vsync` pulses once per frame** and holds for at least one
  `masterclk` period.

The bench already asserts per-pixel exactness against a known pattern (added
late; it found three distinct bugs within minutes, each with exact coordinates,
after several hardware round trips had failed to). Keep that.

## The clocking, and why it is not faster

`lcd.sv` runs entirely on `pllclk`. `SPI_HALF` sets SCL = `pllclk/(2*SPI_HALF)`.

- `SPI_HALF=2` -> SCL 28.125 MHz, 22.9 fps. **Starves the compositor**: a
  console pixel changes every 4 `masterclk` against the 3.02 it needs, and the
  sprite pass is what loses. Tiles survive, sprites vanish.
- `SPI_HALF=3` -> SCL 18.75 MHz, 15.3 fps, 6 `masterclk` per console pixel.
  Currently shipped. Sprites render.

The panel would take 56.25 MHz; the limit is `sprite_compositor.sv`, which needs
483 clocks per 160-pixel console line and only gets the slots the display
leaves. `ppu_line.sv` has ONE read port and `disp_slot` always wins.

Route to ~60 fps, in order, each independently measurable:

1. Composite once per **console** line, not per LCD line. `line_end` fires per
   LCD line (240/frame) but `vpos` only has 120 distinct values, so half the
   compositing is redundant - an artefact of the 2x upscale. ~30 -> ~36 fps.
2. Give the upscaler a **hold buffer** (160x16, one BRAM) so the duplicated LCD
   line does not consume `ppu_line`'s single read port. Unlocks ~60 fps.
3. Then, and only then, `rtl/rgb_quant.sv` earns its place: RGB565 at 56.25 MHz
   caps at 45.8 fps, RGB444 reaches 60.2. Below 45 fps it costs colour depth
   and buys nothing.

`make ppu-check` guards steps 1 and 2 and its 483-clock budget assertion will
need revisiting, since the point of step 1 is that alternate lines stop needing
483 clocks.

## Toolchain traps

- **`PNR=gowin` is the default.** `gw_sh` needs `DYLD_FRAMEWORK_PATH` and
  `DYLD_LIBRARY_PATH` set to `IDE/lib`; see `tools/gowin_build.sh`.
- **GowinSynthesis resolves `$readmemh` relative to the SOURCE FILE's
  directory**, not the working directory, and reports a miss as a *warning*
  (`EX3988`) while emitting a bitstream with every memory zeroed - which passes
  timing, utilisation and every gate, and boots into nothing. The build script
  stages the images at the nested path and now treats `EX3988` as fatal. Do not
  remove that guard.
- **The vendor `.vg` netlist is obfuscated.** Do not grep it for `INIT_RAM` or
  any other parameter name; it cannot match, and a zero result means nothing.
  This session drew a wrong conclusion from exactly that twice.
- `PNR=nextpnr` still works and is the only flow whose netlist can be inspected
  (378 non-zero `INIT_RAM` words). Useful as a cross-check.
- The Tang Nano needs `TANGNANO_SEED=2` (its default); seed 1 segfaults nextpnr.

## Measurement discipline this session had to learn the hard way

- An Fmax from `nextpnr` without an SDC is measured against its **12 MHz
  default** and means nothing. `rtl/gowin_boards.sdc` + `tools/gowin_timing.py`.
- A flat colour fill cannot reveal a bit slip. Use a per-pixel-varying pattern.
- `build/shot.ppm` is the golden reference for what the console should look
  like. Compare against it before theorising about colour.
- Three of the last five display faults were introduced by the fix for the
  previous one. Simulate first; each hardware round trip is ~90 s plus a human.

## Files

| file | what |
| --- | --- |
| `rtl/lcd.sv` | the driver. CS low for the session, `pllclk`, blanking, per-pixel latch |
| `rtl/lcd_tb.sv` | `make test-lcd`. Renders `build/lcd_frame.ppm` |
| `rtl/setup_st7789_565.hex` | init ROM, values measured on hardware |
| `rtl/rgb_quant.sv` | RGB565->444, `make test-rgb-quant`. Not yet in the path |
| `rtl/tangprimer20k.cst` | hardware-verified pinout incl. the RS-on-pin-10 trap |
| `rtl/top_tangprimer20k_{blink,lcdtest,lcdspeed}.sv` | bring-up tops |
| `tools/gowin_build.sh` | vendor flow, `$readmemh` staging, `EX3988` guard |
