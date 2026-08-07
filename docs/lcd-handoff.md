# LCD bring-up handoff

Written 2026-08-07 mid-debug, when the session producing it was introducing
regressions faster than it was fixing them. **All three faults it was written to
hand over are now closed and confirmed on hardware**, and the machine runs at
60.6 fps rather than 15.2. Kept because the reasoning that was wrong is more
useful than the fix that was right: two of the three were misdiagnosed here in
ways that pointed away from the cause, and both misdiagnoses are recorded below
next to what replaced them.

Read "The bench" before touching `rtl/lcd.sv`. Three of the last five display
faults were introduced by the fix for the previous one, and every one of them
got through the bench as it stood.

## Where it stands

Working, verified on a Tang Primer 20K + Dock with MuseLab PMODs:

- 27 MHz crystal, rPLL 112.5 MHz, CLKOUTD **/8** (14.0625 MHz chip clock - it
  was /32, see "The clocking" below), both user LEDs (active **low**,
  silkscreened LED4/LED5 where litex calls them led0/led1).
- PMOD0 audio: `dsigma` -> PAM8403 -> speaker. Confirmed with a tone.
- PMOD2 panel: pins, orientation, power all correct. Panel initialises, accepts
  **56.25 MHz** SPI with a per-pixel grid pattern (a flat fill cannot detect a
  bit slip - do not use one to qualify a link).
- Panel init bytes, all measured not guessed: `INVOFF` (0x20), `MADCTL 0xE8`
  (MY|MX|MV|BGR). See `rtl/setup_st7789_565.hex`, and
  `rtl/setup_st7789_444.hex` for the 12-bit mode that ships.
- The panel accepts `COLMOD 0x03` (12 bits/pixel, three bytes per two pixels).
- The console runs: CPU, PPU, compositor, tiles and sprites all render, at
  60.6 fps. Celeste runs.

## The three faults, all closed

1. ~~**The image scrolls up one row per frame.**~~ **SOLVED by `2ac2eeb`; the
   observation recorded below predated the reflash.** An extra byte per frame, so the
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

   The last of those candidates was the right one: the board had not been
   reflashed after `2ac2eeb`. **Confirm the hardware is running the commit you
   are debugging before spending anything on a symptom.** That check costs one
   flash; not doing it cost most of a session and produced this document.

2. ~~**Sprites render but do not move.**~~ **SOLVED, confirmed on hardware.** `vsync` used to be
   `state == start_frame`; the frame now re-issues RAMWR from blanking without
   passing through `start_frame`, so it never asserted and the console's game
   loop never ticked. `rtl/lcd.sv` now has
   `assign vsync = (state == h_blank) && (vpos == HEIGHT);` - **now verified in
   simulation**: exactly one pulse per frame, 65 `clk` wide at `SPI_HALF=2` and
   97 at `SPI_HALF=3`, against the 32 `clk` (284 ns) `masterclk` period it has
   to survive - and now confirmed on hardware. (Both numbers moved with the
   divider change: the `masterclk` period is 8 `clk` now, and at the shipped
   RGB444/`SPI_HALF=1` the pulse is 25 `clk`.)

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

`make test-lcd` runs **RGB444 at `SPI_HALF=1`** - what the boards ship - plus
RGB565 at `SPI_HALF=1`, `2` and `3`. Blanking is timed in `clk` cycles and bytes
in SCL phases, so the two counters interact, and testing only the module default
leaves the built design untested. `SPI_HALF=1` is also the degenerate case where
`DIVW` collapses to one bit and the divider never counts. Against ~90 s plus a
human per hardware round trip, running all four is free.

### Negative controls

Every assertion in a bench that has never failed is a hypothesis. These three
mutations of `lcd.sv` were each confirmed to fail the bench before the passing
result above was believed:

| mutation | caught by |
| --- | --- |
| one extra data byte per frame (frame end via a pad state) | frame length 153602, line count 241, malformed final line |
| `assign vsync = (state == start_frame)` (the original defect) | 0 vsync pulses in each frame |
| `vsync` narrowed to one `clk` | pulse width 1 < 32 |
| RGB444 phase-1 nibbles swapped | 72,840 of 76,800 pixels wrong, from (0,0) |
| `hpos` stepped every phase, not once per pixel | 71,520 wrong, from (15,0) |
| line resume restarts the pixel group (`ph <= 0`) | wrong from exactly (0,1) |

Re-run them if you change the checks. A bench that passes a mutant is not
evidence about the real design.

One mutation *does* pass, and it is not a gap: dropping `ph <= 2'd0` at the line
end changes nothing, because `LINEBYTES` is a whole number of pixel groups and
`ph` is already 0 there. The assignment is kept as documentation of the
invariant. A control that passes is only worth recording once you know which of
the two it means.

## The clocking, and what actually set the frame rate

**Resolved: 15.2 -> 60.6 fps.** The route this document used to give could not
have got there, and the reason is worth keeping.

`lcd.sv` runs entirely on `pllclk`. Frame time is

    240 lines * 322 pixel-slots * PIXCLK pllclk,
    PIXCLK = bits_per_pixel * 2 * SPI_HALF

| config | PIXCLK | fps |
| --- | --- | --- |
| RGB565, SPI_HALF=3 | 96 | 15.2 |
| RGB565, SPI_HALF=2 | 64 | 22.8 |
| RGB565, SPI_HALF=1 | 32 | 45.5 |
| RGB444, SPI_HALF=1 | 24 | 60.6 |

### What the old analysis got wrong

It said the compositor was the limit: "`sprite_compositor.sv` needs 483 clocks
per 160-pixel console line". **483 is the budget, not the demand** - 161 console
pixels at the 3 clocks `ppu_display` takes for each. The demand is measured and
committed in `rtl/golden/ppu_cycles.txt`, and its worst case across the ten
scenes is **313**. The engine has never been within 35% of running out, so
neither step 1 (composite once per console line) nor step 2 (the hold buffer)
would have raised the frame rate by a single fps. Both reduce a demand that was
never binding.

The claim that `SPI_HALF=2` "starves the compositor" was from the same
arithmetic and is also unsupported: it gives 644 clocks a line against 313.

### What actually bound it

The chip-clock divider, through two constraints that have nothing to do with how
much work the engine does:

1. `ppu_display` needs **>= 3 chip clocks per console pixel** (read issued, data
   registered, colour registered), and a console pixel is `2*PIXCLK` pllclk. At
   the old `DYN_SDIV_SEL=32` that forces `PIXCLK >= 48`, which caps the machine
   at **30.3 fps no matter what the PPU does**.
2. `PIXCLK` must stay an **integer multiple of the divider**. `lcd.sv` drives
   `hpos`/`vpos` into the chip-clock domain across no synchroniser, and the only
   thing making that safe is that the update lands at a fixed phase. Break it
   and a multi-bit bus tears - a fault that looks like geometry, not timing.

At `PIXCLK=24`, constraint 1 gives `N <= 16` and constraint 2 gives
`N` in {8,12,24}; the intersection is 8 or 12. **8** was taken: 14.0625 MHz, a
console pixel every 6 chip clocks, 966 chip clocks a line against the engine's
313. `cpuclk` closes at 33.4 MHz against its 14.06 MHz constraint.

### The three steps, as landed

1. `rtl/pll_gowin.v` `DYN_SDIV_SEL` 32 -> 8, and the `cpuclk` period in
   `rtl/gowin_boards.sdc` to match. `tools/sdc_check.py` derives one from the
   other, so they cannot drift. The CPU, PPU and arbiter all get 4x faster; the
   game loop is vsync-locked, so that is headroom rather than a speed-up.
2. `SPI_HALF` 3 -> 1: SCL 56.25 MHz, the rate the panel was qualified at.
   45.5 fps.
3. `rtl/rgb_quant.sv` into the path and `lcd.sv` taught 12-bit packing - three
   bytes per **two** pixels, `COLMOD 0x03`, `rtl/setup_st7789_444.hex`. 60.6 fps,
   at the cost of 5:6:5 becoming 4:4:4.

`make test-lcd` runs RGB444/SPI_HALF=1 (what ships) plus RGB565 at all three
dividers. The RGB444 packing is the one place a byte spans two pixels, so it
gets its own negative controls: swapping the phase-1 nibbles fails 72,840
pixels, over-stepping `hpos` fails 71,520 from (15,0), and restarting the group
on line resume fails at exactly (0,1).

### Still available, if more is ever wanted

Steps 1 and 2 of the old route are still real work - they just buy engine
headroom rather than frame rate. They would matter if a scene ever approached
the 483-clock budget, which none of the committed ten does.

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
