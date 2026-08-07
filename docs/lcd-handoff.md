# LCD bring-up handoff

Written 2026-08-07, mid-debug, because the session that produced it was
introducing regressions faster than it was fixing them. State is committed but
**the display is not correct** on hardware. Read "The bench" before touching
`rtl/lcd.sv`; three of the last five display faults were introduced by the fix
for the previous one, and every one of them got through the bench as it stood.

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
   `dataout`) and the scroll persisted, so there is at least one more.

   **`lcd.sv` is now excluded as the source, by measurement.** `make test-lcd`
   decodes two consecutive frames off the pins and asserts, at both
   `SPI_HALF=2` and `SPI_HALF=3`: exactly `2*WIDTH*HEIGHT` = 153600 data bytes
   between consecutive RAMWRs, exactly 240 line-runs of exactly 640 bytes each
   (split on the blanking gaps, so line lengths are measured, not inferred),
   no command byte anywhere but at a line start, and both frames decoding
   pixel-exact against the pattern. A deliberately injected extra byte per
   frame is caught by three of those assertions - see "negative controls"
   below. The `load <= 1'b1` at the top of the `byte_done` block, previously
   the prime suspect, cannot fire on a transition cycle: `byte_done` only
   pulses when the shifter completes a byte, and it is idle throughout
   blanking.

   So if the scroll is still on hardware after commit `2ac2eeb`, it is not in
   the byte stream. Remaining candidates, in order: the console side (the
   compositor composes `vpos + 1` and swaps banks on `hpos == H_DISPLAY`, so a
   line-phase error there scrolls the *content* while the geometry stays
   exact); a bit slip on the link at the shipped rate; or an observation that
   predates the fix. Confirm the hardware was reflashed after `2ac2eeb` before
   spending anything else on this.

2. **Sprites render but do not move.** `vsync` used to be
   `state == start_frame`; the frame now re-issues RAMWR from blanking without
   passing through `start_frame`, so it never asserted and the console's game
   loop never ticked. `rtl/lcd.sv` now has
   `assign vsync = (state == h_blank) && (vpos == HEIGHT);` - **now verified in
   simulation**: exactly one pulse per frame, 65 `clk` wide at `SPI_HALF=2` and
   97 at `SPI_HALF=3`, against the 32 `clk` (284 ns) `masterclk` period it has
   to survive. Still unconfirmed on hardware.

3. ~~**Colours are wrong.**~~ **SOLVED. It was never the panel, the byte order
   or the colour space - it was the palette ROM.**

   `chip.sv` hardcoded the 24-bit `palette888.bin` into its `palette` instance
   and ignored the `FILE` parameter both Tang tops pass. `palette` reads FILE
   with `$readmemb` into `RGB`-bit words, and `$readmemb` given a wider word
   keeps the **low** bits and says nothing louder than a warning. So every
   RGB565 top loaded the low 16 bits of a 24-bit colour and re-read them as
   5:6:5:

   | PICO-8 | should be | reached the panel |
   | --- | --- | --- |
   | 1 dark blue (background) | (29,43,83) navy | (41,105,156) **blue** |
   | 14 pink (tiles) | (255,119,168) | (115,247,66) **green** |
   | 7 white (text) | (255,241,232) | (247,60,66) **red** |

   All three observations, exactly. `make shot` could not see it:
   `top_simulator.sv` builds the chip at RED=GREEN=BLUE=8, the one width at
   which the hardcoded file was correct. Fixed by passing `FILE` through, and
   guarded by `make test-palette`.

   **The rule this document used to give here was wrong**, and it cost time:
   "white is symmetric under inversion and R<->B swap, so if white is not white
   the fault is alignment, not colour". Symmetry under those two faults does not
   make white a fixed point of *every* fault - a wrong palette word maps it
   anywhere. The correct rule is narrower: if white is not white, the fault is
   not inversion and not a channel swap. Say what a test excludes, not what it
   proves.

   `build/shot.ppm` from `make shot` remains the reference: dark navy background
   (29,43,83), pink tiles (255,119,168), white text, yellow ball, light-grey
   paddle. Compare against it before theorising, and do not flip `INVON`/`BGR`
   speculatively.

## The bench

`rtl/lcd_tb.sv` is the only thing that made progress possible. The three
weaknesses this document was written to flag are closed:

- **Two consecutive frames are decoded** and the frame boundary is *located*,
  not counted: every byte after RAMWR is data until the next command byte, so
  scanning for that byte and asserting its index is what makes the frame length
  an assertion. Per-frame drift was structurally invisible to the old
  single-frame decode.
- **Bytes-per-line and bytes-per-frame are asserted explicitly.** Line
  boundaries carry no marker on the wire - the driver just stops shifting for
  the blanking interval - so the bench timestamps every byte and splits the
  stream on the gaps. A malformed line is reported by its row number instead of
  surfacing as a sheared image several hundred rows later.
- **`vsync` is asserted to pulse once per frame** and to be at least one
  `masterclk` (32 `clk`) wide.
- Per-pixel exactness against a known pattern, for **both** frames. That check
  found three distinct bugs within minutes, each with exact coordinates, after
  several hardware round trips had failed to.

`make test-lcd` runs it at `SPI_HALF=2` **and** at the `SPI_HALF=3` the boards
ship: blanking is timed in `clk` cycles and bytes in SCL phases, so the two
counters interact and testing only the module default leaves the built design
untested. ~40 s for both, against ~90 s plus a human per hardware round trip.

### Negative controls

Every assertion in a bench that has never failed is a hypothesis. These three
mutations of `lcd.sv` were each confirmed to fail the bench before the passing
result above was believed:

| mutation | caught by |
| --- | --- |
| one extra data byte per frame (frame end via a pad state) | frame length 153602, line count 241, malformed final line |
| `assign vsync = (state == start_frame)` (the original defect) | 0 vsync pulses in each frame |
| `vsync` narrowed to one `clk` | pulse width 1 < 32 |

Re-run them if you change the checks. A bench that passes a mutant is not
evidence about the real design.

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
- **A `$readmem*` whose file is wider than the array it loads is silent.** It
  keeps the low bits and populates the memory, so the design passes utilisation,
  timing, every gate and boots - wrong. `make test-palette` therefore elaborates
  `chip` at the width the *boards* build it, not `palette` on its own: the
  module and the file were both correct throughout, and the defect was in the
  parameter between them. Test the wiring at the configuration that ships.
- **The simulator is not a reference for anything it is built differently
  from.** `top_simulator.sv` builds the chip at 8:8:8 and the boards at 5:6:5,
  and the whole colour bug lived in that gap for the life of the file.
- `build/shot.ppm` is the golden reference for what the console should look
  like. Compare against it before theorising about colour.
- Three of the last five display faults were introduced by the fix for the
  previous one. Simulate first; each hardware round trip is ~90 s plus a human.

## Files

| file | what |
| --- | --- |
| `rtl/lcd.sv` | the driver. CS low for the session, `pllclk`, blanking, per-pixel latch |
| `rtl/lcd_tb.sv` | `make test-lcd`. Two frames, both dividers. Renders `build/lcd_frame{,2}.ppm` |
| `rtl/setup_st7789_565.hex` | init ROM, values measured on hardware |
| `rtl/rgb_quant.sv` | RGB565->444, `make test-rgb-quant`. Not yet in the path |
| `rtl/tangprimer20k.cst` | hardware-verified pinout incl. the RS-on-pin-10 trap |
| `rtl/top_tangprimer20k_{blink,lcdtest,lcdspeed}.sv` | bring-up tops |
| `tools/gowin_build.sh` | vendor flow, `$readmemh` staging, `EX3988` guard |
