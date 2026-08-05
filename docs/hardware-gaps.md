# Hardware gaps for faithful game ports

Findings from porting Breakout Hero (PICO-8) with the intent of matching the
original, not dumbing it down. Based on a full read of the original's systems:
angle-based ball physics with sub-stepping, paddle momentum, a general
particle system (gravity, color ramps, rotating sprite shards, line-type
speed effects, ambient background dust), decaying random screen shake,
palette fades/flashes, chain multiplier, sudden death, and pervasive SFX.

## Real gaps (hardware evolution candidates)

1. **Audio.** v2 DONE (rtl/psg.sv, $4100 window): a PICO-8-equivalent chip.
   The cart's audio RAM image ($3100-$42FF: 64 music patterns + 64 SFX
   records) uploads verbatim; sfx(n,ch) and music(m) are one register write
   each. PICO-8 timing (22050 Hz virtual rate, 120.49 Hz tick, speed =
   ticks/row), all 8 waveforms (wave ROM + pitched LFSR noise + dual-osc
   phaser), all 8 note effects (slide/vibrato/drop/fades/arpeggios), loop
   and length-only conventions, and a hardware music sequencer with
   loop-start/loop-back/stop flow control. The filter byte is interpreted
   too (add-psg-filters-output): per-channel DAMPEN (one-pole low-pass),
   DETUNE (second voice on the phase-2 accumulator), NOIZ/BUZZ noise modes
   (white/pitched/brown), BUZZ duty-shift on square/pulse, and a shared
   REVERB echo (behind a compile-time parameter). The board output stage
   exists: rtl/dsigma.sv (first-order delta-sigma, 8-bit PCM -> 1-bit
   audio_pwm pin, RC-reconstructed off-board), and CLK_HZ is a chip/top
   parameter so the 22050 Hz rate is right on any master clock. Remaining
   for full fidelity: custom SFX/wavetable instruments, auto channel
   selection (sfx -1/-2), music fades, and per-channel (not shared) reverb.
   Two board knobs an operator sets for their wiring: top.sv's BOARD_CLK_HZ
   (the actual master clock) and top.pcf's audio_pwm pin. The simulator
   samples the 22050 Hz PCM at 44.1 kHz via SDL.
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
5. **Persistent storage.** OPEN. Found porting NEMO - Puzzle Pack II, which
   tracks which of its 50 puzzles you have completed across sessions via
   PICO-8's cartdata()/dget/dset. Nothing in rtl/ implements EEPROM, flash or
   NVRAM, so the port keeps progress in RAM at PROGRESS and loses it on
   power-off. The demand is unusually small and specific: **50 bits, i.e. 7
   bytes** - one completion flag per puzzle. So the smallest useful fix is a
   handful of bytes behind an MMIO window with a write-enable, not a filesystem
   and not a save-state. Worth doing before any cart with progression.
6. **Procedural drawing primitives.** OPEN, low priority. PICO-8 carts draw
   with line/rect/circ; this console has tiles, sprites and a 1bpp overlay, so
   NEMO's rounded-corner popups, dotted rules and drop shadows have no direct
   equivalent. The port draws dotted grid lines by plotting every other pixel
   and omits the rounded boxes. Pre-baked tiles cover most cases, so this is a
   convenience gap rather than a capability gap - but it recurs in every PICO-8
   port and a horizontal/vertical run-fill helper in the overlay path would pay
   for itself.

7. **The PSG's music channel reservation is advisory.** `$4121` records which
   channels are reserved for music, but the hardware does not enforce it: the
   sequencer sets `music_owned[i]` when it launches a pattern channel, yet a CPU
   write to `$4110+c` will still trigger an SFX on that channel. Since the
   sequencer decides a pattern has ended by watching `playing[tch]` for the
   pattern's timing channel, stealing that channel makes it end the pattern
   early - and on a stop flag or pattern 63 it sets `mus_playing = 0`, killing
   the music outright. Every game therefore has to maintain `$4121` by hand and
   keep it correct as patterns change. Two cheap fixes: expose `music_owned` in
   a readable register so the CPU can consult reality rather than a hint, or
   have the sequencer refuse to use a hijacked channel for timing. Found while
   porting NEMO, whose cart passes `music(n, fade, 2)` - reserving one channel -
   while every one of its patterns plays on two.

8. **Overlay blit modes.** OPEN, and the cleanest fix for a recurring problem.
   The overlay is 1bpp with one global colour register, so everything drawn in it
   is the same colour - which is why this port's labels are all white where the
   cart uses white text with a black drop shadow, and grey for satisfied clue
   strips. Text cannot go in the tile layer instead: the sheet's font is 8x8 and
   a PICO-8 port wants 4x6, and an 8-pixel tile grid cannot place a 4-pixel
   glyph, so both ports blit text into a framebuffer.
   A small combining mode on the overlay would cover it: per-write or per-region
   OR / AND / XOR / constant-colour, so a shadow is the same glyph blitted once
   offset in one colour and once on top in another. That is a shift and a mask in
   the display path, far cheaper than a second overlay plane, and it would also
   give inverse-video and one-pixel outlines for free. Suggested while porting
   NEMO's title screen.

   **Where it lands now (2026-07-25, refactor-ppu-core).** The display path is
   `rtl/ppu_display.sv`, and the mix is the `if (ovl_en && ovl_rdata[...])` at
   the bottom of it. A combining mode is a change to that expression and to the
   registers feeding it; it does not touch the engine FSM, the fetch or the
   blit. That was the point of the split.

9. **Layer priority for the overlay, and the fill-rate ceiling behind it.**
   OPEN, but **no longer needed for the case that raised it** - the clouds were
   solved by sprites instead. The sprite list is ordered, the behind-split at
   `$4036` already partitions it, and entry 10's repeat field made a whole
   cloud cost one entry. So a background bitmap plane was never required here;
   what follows is still the right analysis for a program that genuinely needs
   arbitrary background drawing, and the fill-rate ceiling below is the part
   that stays true whatever gets built. Found porting Celeste, whose background
   was missing: 17 scrolling
   clouds (`rectfill`, colour 1, drawn BEFORE the map so they sit behind the
   terrain) and 25 drifting particles (1-2 px, colours 6/7, drawn after
   everything). Breakout's ambient dust and NEMO's rounded boxes are the same
   shape of problem.

   The overlay is the console's framebuffer layer and it very nearly does the
   job. What stops it is one expression: the mix at the bottom of
   `rtl/ppu_display.sv` is a single mux, so the overlay is always ABOVE tiles
   and sprites and always one colour. Clouds need to be behind, in colour 1;
   the HUD needs to be in front, in white; there is one plane and one priority,
   so they cannot coexist.

   **Two measurements from refactor-ppu-core that this entry needs.**

   - **There is no spare block RAM.** The PPU is 16 of the hx8k's 32 and the
     PSG is the other 16. A second overlay plane is +5, and eleven of the PPU's
     sixteen are capacity-forced with no slack to reclaim (design.md of
     refactor-ppu-core costs both width-forced consumers and rejects both).
     The plane is affordable only against a device with more block RAM, or
     against the 64 KB `ram_async` array being dealt with first - which is the
     real blocker, since the chip does not place at all today.
   - **The overlay's read multiplexer is now the PPU's critical path**: 2.15 ns
     of block-RAM clock-to-q plus five LUT levels selecting between the five
     blocks the 2560-byte array is spread across, into the colour register. A
     second plane makes that mux wider, not narrower. Whatever closes this gap
     should register the block select or narrow the array, not just add a
     second one beside it.

   Cheapest fixes, in order:
   - **An overlay priority bit** (`$4005` bit 2): composite the overlay below
     the layers instead of above, i.e. use `ovl_color` only where the
     composited pixel is still 0. One comparator in the display path, no new
     storage. Does not by itself let the HUD and the clouds coexist.
   - **A second overlay plane** with its own colour and priority: +2400 bytes
     of BRAM and a second display read port. Plane A behind in colour 1 for
     clouds, plane B in front in white for text. This is the one that closes
     the gap, and it is the shape every system in the prior art below settled
     on - a bitmap that is *a layer with a priority number*, not a bitmap that
     replaces the layers.

   **The reason not to go further than that** is fill rate, not composition.
   At 3.5 MHz and 30 Hz logic the CPU has 116,886 cycles a frame:

   | | bytes | clear only | share of the frame |
   | --- | --- | --- | --- |
   | 1bpp overlay (today) | 2400 | 12,000 cyc | 10% |
   | 2bpp overlay | 4800 | 24,000 cyc | 20% |
   | 4bpp full framebuffer | 9600 | 48,000 cyc | **41%** |

   A full-colour framebuffer is unaffordable before a single pixel is *drawn*,
   so copying PICO-8's model wholesale is the wrong target: PICO-8's
   framebuffer is filled by a host CPU three orders of magnitude faster. The
   affordable envelope is roughly 2-3 KB of CPU-written pixels per frame, which
   is exactly one 1bpp plane. Celeste's 17 clouds fit inside it - 2176 bytes of
   run-fill, about 9% of the frame - and its 25 particles want no framebuffer
   at all: they are 25 of 128 sprite entries and cost zero CPU pixels.

   Which points at the other half, already noted in gap 6: **a run-fill helper
   in the overlay path** (write a value across a byte range) is worth more than
   any extra plane. It is the Amiga blitter's lesson at 1/1000 scale - the
   machines that made arbitrary drawing practical did it by making the FILL
   cheap, not by adding planes.

   ### Prior art: bitmaps as priority layers

   | System | How it composites arbitrary drawing |
   | --- | --- |
   | **Sega Saturn** (1994) | VDP1 renders sprites/polygons into a double-buffered framebuffer; VDP2 then treats that framebuffer as **one more layer** among its five scroll backgrounds, with per-layer priority and colour calculation. The canonical form of this idea. |
   | **Nintendo DS** (2004) | A BG slot can be a direct bitmap, and the 3D engine's output is composited **as BG0**, with per-layer priority and alpha blending. |
   | **Sharp X68000** (1987) | Four bitmap graphics planes + a text plane + sprites, ordered by a **priority controller** - closest to "sprites, tiles and framebuffers in one scene". |
   | **PC Engine SuperGrafx** (1989) | Two VDCs feeding a **VPC (Video Priority Controller)** that composites their outputs under programmable priority. Obscure, and exactly on point. |
   | **Commodore Amiga** (1985) | Dual playfield: two bitplane framebuffers composited with priority against sprites - plus the **Blitter** (256 minterms, area fill, line draw) to make filling them affordable, and the Copper for per-scanline register changes. The fill-rate half of the answer. |
   | **SNES** (1990) | Main screen / sub screen with colour math and per-pixel windows: a compositor in all but name. No bitmap layer, so games reached for HDMA instead. |
   | **GBA** (2001) | Bitmap modes 3/4/5 present the framebuffer **as BG2**, still composited with sprites, windows and blending; mode 4 page-flips. |
   | **Raspberry Pi HVS**, DRM/KMS planes, Android HWC | The same idea now: planes with z-order composited **during scanout** rather than into memory. The HVS in particular is a scanline compositor, which is what `sprite_compositor.sv` already is. |

   The common thread: none of them made everything a framebuffer. They gave the
   framebuffer a priority number and put it in the same scene as the tiles and
   sprites - and the ones that made drawing into it practical added a blitter.
   That is the order this console should follow too.

10. **A repeat count per sprite entry (meta-sprites).** **DONE** - `$4037`,
    staged repeat in cells; a committed entry blits its one fetched row into
    that many consecutive 8-pixel cells. 0 and 1 both mean one cell, so the
    reset value is the old behaviour and breakout and nemo are unaffected.
    Verified in `rtl/sprite_compositor_tb.sv`: one entry with rep=8 renders
    **pixel-identical** to the eight entries it replaces, over the whole frame.
    Celeste's background went from 133 entries (over budget) to 46, which is
    what let it carry the cart's own 17 clouds and 25 particles.
    The original case for it follows. Every sprite entry is exactly one 8x8
    cell, which makes a flat run cost one entry per cell. Celeste's clouds are
    the case that exposes it: they are solid rectangles 32-56 px wide, so

    | | entries today | with a repeat field |
    | --- | --- | --- |
    | 12 clouds, 4-7 cells each | **66** | 12 |
    | 16 particles | 16 | 16 |
    | player + hair | 6 | 6 |
    | **total** | **88 of 128** | **34** |
    | the cart's own 17 clouds + 25 particles | 133 — *over budget* | 48 |

    So the list, not the scanline, is what forced the port to cut the cart's
    counts (17 clouds and 25 particles became 12 and 16). A repeat field would
    let them be restored exactly.

    **Two different features hide behind "meta-sprite", and this needs the
    cheaper one:**
    - *Size with consecutive patterns* (Mega Drive's 1-4 cell hsize/vsize, GBA's
      shape+size up to 64x64): cell *n* uses pattern base+*n*. Right for big
      characters, and it costs sheet slots - a 4x4 sprite needs 16 patterns.
    - *Repeat of one pattern*: every cell uses the SAME base. Right for flat
      fills, and it costs one pattern total. This is what clouds want.

    One bit selects between them if both are ever wanted; the repeat form alone
    is what pays here.

    Cost, against `sprite_compositor.sv` as it stands:
    - Entry format grows by 3 bits (repeat 1-8): 128 x 31 -> 128 x 34 bits.
    - `$400B` is full ({pal, bpp-1, yflip, xflip}), so the count needs its own
      staging register - `$4037`, reset value 1, so existing programs are
      unaffected.
    - The engine change is small and lands in the right place: at `E_WR1`, if
      cells remain, add 8 to `e_x` and go back to `E_RD0` **without re-fetching
      the planes** - `prow` already holds the row. A 3-bit counter, an adder and
      one state transition.

    It is faster as well as smaller: today a 7-cell run costs 7 x (bpp+7) = 56
    clocks plus 7 scan clocks; as one entry it is (bpp+2) + 7 x 5 = 38 plus one
    scan clock, because the sheet fetch is paid once instead of seven times.

    Prior art: a size field per sprite is the norm, not the exception - NES
    (8x8/8x16), SNES (two selectable sizes), **Mega Drive (1-4 cells per axis in
    one attribute-table entry)**, GBA (shape+size to 64x64). A fixed 8x8 entry
    is the TMS9918/2600 model, and this console inherited it.

11. **Neither draw palette nor screen palette reads back.** OPEN, found
    2026-07-25 by the golden-frame harness the first time anything asserted the
    register map instead of reading it. `$4010-$401F` (draw palette) return the
    corresponding **screen** palette entry, and `$4020-$402F` return 0.

    One `casez` arm does both: it is `6'b01????`, which matches `$10-$1F` only,
    and inside that range `addr[4]` - the bit the arm uses to choose between the
    two palettes - is always 1. `$20-$2F` are `6'b10????` and match no arm at
    all, so they fall through to the default. The discriminator wanted is
    `addr[5:4]`: `01` -> draw, `10` -> screen.

    **Writes are unaffected** and always have been - both palettes take their
    values correctly, and the golden scenes render through them - so nothing on
    screen is wrong and no port is affected. It is a readback decode bug only,
    which is exactly why it survived: nothing had ever read them back.

    Not fixed in `refactor-ppu-core`, deliberately: that change is
    behaviour-preserving and its whole method is that every pixel and every
    register value is identical before and after. Slipping a real change inside
    it would defeat the point. `rtl/ppu_golden_tb.sv` asserts the behaviour **as
    it is**, with a comment pointing here, so whoever fixes it will see the test
    fail and know it is the assertion that has to move.

## Audio fidelity: what has been ruled out

Three reports that the ported music sounds unlike the cart ("missing
instruments", "channels don't compose cleanly", "a bloop that isn't in the
original") were narrowed by tracing rather than by ear. `rtl/psg.sv` carries a
verification-only `dbg` bus - per-channel playing/owned/sfx/row plus the music
pattern - threaded to the simulator and printed by `make psg-trace` in the same
shape as PICO-8's `stat(46..49)` and `stat(50..53)`, so a real cart running under
PICO-8 and the same cart running here can be diffed frame by frame.

Over a 239-frame window of NEMO's title music, against the real cart:

| | frames differing |
| --- | --- |
| SFX playing on channel 0 | **0** / 239 |
| SFX playing on channel 1 | **0** / 239 |
| music pattern | **1** / 239 (a one-frame boundary offset) |
| note row within the SFX | 30 / 239, all +-1 frame of boundary jitter, no drift |

So channel allocation, SFX selection, pattern flow control and note timing are
all correct. **Whatever differs is in synthesis** - how a note becomes samples -
not in which notes play or when.

### How to compare a suspect voice against the cart, without PICO-8

`make psg-analyze CART=... SFX=n` renders one SFX through the real RTL and lines up
the energy of each row against the cart's own note data. It needs no reference
recording: the cart already says what each row should be, so a silent row that
should sound localises the fault to a row, and therefore to a waveform, a volume
or an effect.

It is how the phaser bug above was found. Every silent row in NEMO's SFX 8 was
wave 7 and no other waveform was affected, which ruled out sequencing, pitch and
the mixer in one pass and pointed at the phaser. The companion tools are
`make psg-wav` (render to a WAV and listen) and `make psg-analyze` (per-row
energy and stable-note pitch alongside the requested waveform).

### The mixer runs 2x hot, so the channels do not compose the way PICO-8's do

An earlier pass called the mixer sound because it has headroom for two channels.
Against zepto-8 that is the wrong bar. PICO-8 sums four channels and clips only
at the sum:

    chan = clamp(waveform * (vol/7) * 0.5, +-1)      // 0.5 is volume_sfx/music
    mix  = clamp(sum of four chan, +-1)

A full-volume triangle is `0.5 * 1 * 0.5` = **a quarter** of full scale, so four
channels at full volume sum to exactly 1.0 and never clip. The PSG:

    n_res = (|sample| * eff_vol) >> 8                // caps at 125
    dry8  = clamp(mixacc, +-255) >>> 1               // full scale is 127

puts one full-volume channel at **125/254 = 0.49**, near enough half scale - and
four at 1.97, hard clipped. Every channel is **1.97x hotter than PICO-8's**.

For NEMO's title music - two channels at note volume 4/7 plus a volume-3 SFX -
the PSG sits at **77% of full scale where PICO-8 sits at 39%**. Transients that
have room in PICO-8 hit the clip here, which is what "the channels don't compose
cleanly" sounds like.

**FIXED, by widening the datapath instead of choosing a side.** The trade-off was
only a trade-off while the chip was 8-bit end to end. It is not:

- **The per-channel volume multiply was throwing away half its result.** The
  shift-add multiplier computes a full 16-bit product and `n_res = n_p[15:8]`
  kept only the top byte. A note at PICO-8 volume 1 has `eff_vol` 36, so
  `(127*36)>>8` = **17 levels, 4.2 bits** - and **two thirds of NEMO's title
  music is volume 1 or 2** (48% volume 1, 19% volume 2). That, not the mix
  balance, was the largest single defect in the chip. `n_res` is now the whole
  16-bit product.
- **The delta-sigma stage never needed 8-bit input.** It runs at the 25 MHz
  master clock against a 22050 Hz signal - an oversampling ratio of ~1134 - and
  a first-order modulator at that ratio carries on the order of 14 bits in the
  audio band. Feeding it 8 bits was discarding resolution the output stage
  already had. `rtl/dsigma.sv` now takes signed 16-bit.
- With a 16-bit path, PICO-8's quarter-scale channels cost nothing, so the mixer
  now matches: `clamp(mixacc, +-131068) >>> 2` puts one full channel at a
  quarter of full scale and four at exactly full scale, no clipping.

Measured over 150 frames in the simulator, counting distinct output sample
values:

| | before (8-bit) | after |
| --- | --- | --- |
| nemo | 73 levels, **6.2 bits** | 5870 levels, **12.5 bits** |
| breakout | ~200 levels, ~7.6 bits | 9788 levels, **13.3 bits** |

The reverb delay line stays 8-bit deliberately: it is a shared echo at a low
level, and widening it would double its BRAM for no audible gain.

### Music channels are preempted and restored

FIXED. PICO-8 lets an SFX take a channel the music is using: the displaced music
SFX is stored on that channel (`sfx_music` in zepto-8/fake-08) and **relaunched
when the SFX finishes**. That is why a cart can pass `music(n, fade, 2)` -
reserving one channel - while its patterns play on two, as NEMO's does.

The PSG now does the same. Taking a music-owned channel saves its SFX number and
row (`sav_sfx`/`sav_row`/`sav_valid`); when that channel would stop, it
relaunches the music SFX at the saved row instead. `playing` is deliberately
never cleared on that path, because the sequencer decides a pattern has ended by
watching `playing[tch]` and a one-cycle dip would end the pattern early. An
explicit stop (`$80`) forgets the saved SFX, and a pattern change invalidates it.

Covered by `rtl/psg_tb.sv` test **18b**, which launches a pattern on all four
channels, borrows channel 0 for a short SFX, and checks that the music's own SFX
comes back on it. Note the test polls for the restore rather than waiting a fixed
time: wait too long and the pattern advances and relaunches the channel
legitimately, which looks like the same thing and is not.

`src/nemo/sound.asm` reverted to the cart's own mask (`$02`) as a result - it had
been widened to `$03` purely to work around this.

**Not a gap, on inspection:** PICO-8's separate `volume_music` / `volume_sfx`
constants are both 0.5 and are not cart-settable - they are how zepto-8 arrives
at quarter-scale channels. This PSG's mixer now produces quarter-scale channels
directly, so it is already at parity; separate registers would be a feature
beyond PICO-8, not a fidelity fix.

That narrowed it to synthesis, and comparing against **zepto-8's `synth.cpp`**
(reached via `jtothebell/fake-08`, which ports its audio) found the rest.

What is already right: the wave ROM generated by `tools/gen_psg_tables.py`
reproduces zepto-8's formulas exactly, **including the per-waveform amplitudes**
that make the instruments balance - 0.5 triangle, 0.5 tilted saw, 0.653 saw,
0.25 square and pulse, /9 organ. The filter bit assignment is right too: zepto-8
reads NOIZ as bit 1 and BUZZ as bit 2, and so does this PSG. Both title SFX carry
filter `0x01`, and ignoring bit 0 is correct - in PICO-8 that bit is the editor's
view mode, not an audio flag.

Waveforms **6 (noise)** and **7 (phaser)** are not in the ROM; they are generated
in RTL, and both are wrong. NEMO's title music uses both.

1. **Noise had no pitch dependence at all.** FIXED, and the first reading of this
   was backwards - recorded here because the correction is the interesting part.

   zepto-8 applies a make-up gain of `1.5 * (1 + (1 - key/63)^2)`, which is
   largest at the lowest note, so the obvious conclusion is "low noise should be
   louder". It is the wrong conclusion: that gain compensates a one-pole filter
   whose cutoff follows the pitch, and the filter attenuates low notes *more*
   than the gain lifts them. The net RMS therefore **rises** with pitch. The
   steady state of `new = (last + s*r)/(1 + s)` with `r` uniform is
   `sqrt(s/(3(s+2)))`, so the curve is analytic:

   | key | zepto-8 RMS | PSG before (flat) |
   | --- | --- | --- |
   | 8 | 0.218 | 0.433 - **2x too loud** |
   | 32 | 0.299 | 0.433 |
   | 63 | 0.500 | 0.433 - slightly quiet |

   This PSG makes noise by sample-and-holding an LFSR at the pitch rate, which
   gets the spectral shaping roughly right but leaves the amplitude flat.
   `tools/gen_psg_tables.py` now emits `rtl/psg_noise.hex`, 64 gain entries
   indexed by key (87/256 at the bottom to 222/256 at the top), applied to
   `nz_hold`.

   Verified by rendering a synthetic 8-row noise SFX across the key range through
   `make psg-wav` and measuring RMS per row: **within 3% of the reference curve
   at every key** (ratios 0.97-1.02), against a 2x error at the bottom before.
2. **The phaser was at 3% of its proper amplitude - inaudible.** FIXED, and it
   was the "the melody doesn't play start to finish" report.

       samp = 8'((ph_sum * 11'sd85) >>> 8);        // wrong

   `ph_sum` is 11 bits and so was the constant, so Verilog evaluated the product
   at 11-bit width. `ph_sum` peaks at 381; 381*85 = 32385 wraps modulo 2048 to
   -383, and `>>> 8` leaves -2. The phaser's entire output was truncation
   debris. Widened to a 19-bit multiply, it now peaks at 126 like every other
   waveform.

   Measured against a triangle at the same pitch and volume: **0.03x before,
   0.89x after**, consistent across pitches 21, 33 and 45. On NEMO's SFX 8 -
   14 of its 29 audible rows are phaser - **11 silent rows became 0**. The pitch
   check `make psg-analyze` went from 28/32 to 31/32 on SFX 7 at the same time,
   because rows that were previously too quiet to measure now carry a signal.

   Note this is not the same bug as the beat rate below, and it hid it: a
   waveform at 3% amplitude cannot be heard to beat at any rate.

3. **Phaser beat rate was 7.4% fast.** FIXED. The second oscillator must run at
   109/110 of the first (0.9909091); the shift pair in use gave 0.9902344, so the
   beat was 4.30 Hz instead of 4.00 at A440. Three shifts give 0.9909668 - 0.6%
   error - for one more adder.

## Investigated and NOT recommended

- **Hardware multiply.** `add-isa-ergonomic-gates` deferred multiply/divide to a
  future `add-math-coprocessor` on the assumption that a demand would show up.
  NEMO looked like the case that would prove it: its grid stride is
  `(i-1)*pz_w+j` with `pz_w` read at runtime, and none of the 50 puzzle widths
  (7, 9, 10, 11, 12, 13, 14, 15) is a power of two, so the stride is neither
  shiftable nor strength-reducible at assembly time.
  **Written idiomatically the multiply disappears.** A cell array is at most
  15x15 = 225 bytes so it fits in a page; page-align it and a row base is a
  single byte; build that 15-entry byte table once per puzzle by repeated
  addition. Every access is then one indexed load plus one `(zp),Y`. The whole
  port contains one general multiply, called three times per puzzle load.
  See `src/nemo/grid.asm` and `docs/corpora.md`.
  Note also that the target device cannot help: `Makefile` disables yosys `-dsp`
  because the hx8k has no `SB_MAC16` cells, so any multiplier is LUT-based - a
  shift-add sequencer, not an inferred DSP block. Revisit only if a corpus turns
  up a multiply in an inner loop.

- **Per-pattern palette selection (a mask, or an explicit colour list).**
  Proposed while re-encoding Celeste's terrain: instead of the 4-bit palette
  BASE, give a sprite/tile entry a 16-bit MASK naming which global palette
  entries it uses, with pixel value *v* selecting the *v*-th set bit in
  increasing order. It is a strictly more general scheme than base+window - any
  colour set becomes expressible at the minimum bpp - and it is the right
  encoding if this is ever built: 12 more bits per entry against ~60 for an
  explicit 15-entry list.

  **Measured demand today: zero.** The compositor computes `palette base +
  pixel value` and then remaps through the draw palette at $4010, so the
  generator is free to choose what pixel values MEAN and to arrange the palette
  so that each pattern's colours land in some window. With that,
  `tools/p8_celeste.py` hits the theoretical minimum exactly - 146 slots for
  stage 1, 158 for all 32 rooms - which is precisely what a per-pattern palette
  would cost. The saving from new hardware would be **0 slots**.

  It works because a 16-entry cyclic palette has 16 three-windows, and Celeste
  needs **5 distinct three-colour sets** across the entire game (14 distinct
  colours, 20 distinct colour sets, most of them nested subsets). The scheme
  degrades only when a program has more distinct 3-colour COMBINATIONS than
  there are windows to hold them. Measured on synthetic sets drawn from all 16
  colours:

  | distinct 3-colour sets | base+window | per-pattern palette | penalty |
  | --- | --- | --- | --- |
  | 8 | 16 | 16 | none |
  | 12 | 33 | 24 | +37% |
  | 16 | 44 | 32 | +37% |
  | 24 | 70 | 48 | +46% |
  | 32 | 97 | 64 | +52% |

  So the crossover is around **8-12 distinct three-colour combinations**, and
  Celeste sits at 5. A painterly cart that dithers many colour pairs would pass
  it easily; three PICO-8 ports have not come close.

  If it is ever built, two implementation notes worth keeping:
  - **Expand once per entry, not per pixel.** All eight pixels of a row share
    one list entry, so the mask can be expanded to a 15x4-bit local palette at
    fetch time and the per-pixel path stays a mux. Eight parallel "select the
    v-th set bit of 16" circuits would land in the timing-critical pixel
    datapath; one expansion does not.
  - **The tilemap cannot carry it.** A cell is two bytes and the attribute byte
    is fully spent on {pal, bpp-1, yflip, xflip}. A 16-bit mask needs a third
    map plane (+512 bytes of BRAM). The cheaper variant that fits the existing
    format is palette BANKS: reinterpret the 4-bit field as a selector into 16
    register-file banks of three colours (192 bits of registers, no extra
    per-entry bits, no new map plane). That buys most of the generality for
    almost nothing - and is the form to reach for first.

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

## Voice architecture: every voice is an oscillator pair (2026-08-05)

Orientation distilled from the app-bundle disassembly (`pico8-psg-re.md`);
formulas live there, this is the mental model.

**Every PICO-8 voice is structurally TWO oscillators**, not one with an
optional detune: the output of every built-in waveform is
`shape(p) + shape(q)/2`. `p` is the primary 16-bit phase (`s_phase` here);
`q0` is a secondary 17-bit phase (`s_phase2[16:0]`) advancing at a rate
derived from `dp` by wave- and detune-mode-dependent ratios — the `dq`
formulas with their exact integer ceil corrections (the 524,288-case dq
sweep in `make test-psg` pins them). CONFIRMED against the binary-verified
dq contract (psg_dqsvc: dq = floor(K*dp13/256), K in {193, 250, 254, 255,
256, 384, 508}): for the u16-view waves the secondary sits at or near the
SUB-OCTAVE — K=256 is exactly half frequency, 250/254/255 beat slowly
against it, 384 is a fourth below, 508 the near-unison shimmer. Every
PICO-8 voice carries a half-weight sub-octave shadow; that body is the
"thick" sound, and it is why a textbook single-oscillator
reimplementation sounds thin and never matches bit-for-bit.

**The pair is asymmetric by organic accretion, not design.** Most waveforms
read the secondary through a 16-bit view (`u16(q0 << (mode==2))`), so for
them `q0`'s bit 16 is unobservable. Triangle (0) and phaser (7) instead
evaluate the RAW 17-bit phase: `tri_raw`'s second branch is an unguarded
`else` in the machine code, extending over `[65536, 131071]` — the
secondary triangle is a 2^17-periodic quarter-up / three-quarters-down ramp
plunging ~5x the primary's depth, i.e. a strong octave-below component with
sawtooth asymmetry. Almost certainly a masking accident (`& 0x1ffff`) that
shipped and became the spec.

**Why 17 bits and not 16 + halved dq — the orbit theorem.** An odd `dq`
is coprime to 2^17, so the phase orbit visits all 131,072 states with
period 2^17 samples, and the output sequence inherits that period because
`tri_raw` is not 2^16-periodic over the extended domain
(`tri_raw(x) != tri_raw(x + 65536)` except at 0). A 16-bit-state generator
has period at most 2^16, so no reformulation reproduces the sequence: the
17th bit is irreducible state. Dither schemes (alternate floor/ceil
increments in 16-bit space) merely relocate the bit into a carry flop —
fractional rate implies fractional state, somewhere. Same conservation law
as the Bresenham sample clock (H166).

**But it is NOT a clean fixed-point split.** The litmus test: a true
"16 integer + 1 fractional bit" design would have the waveform read
`q0[16:1]` and keep `q0[0]` out of the output entirely (pure accumulation
carry). PICO-8 fails that test twice: the u16-view waves read `q0[15:0]`
(for them bit 16 is invisible, neither integer nor fraction), and the
triangle arm feeds ALL 17 bits into the amplitude — slope 3 means `q0[0]`
adds +-3 pre-`/8`, sub-quantum dither that occasionally flips a truncation
boundary, so the LSB is faintly audible. The register is one 17-bit
integer serving two incompatible phase conventions at once: a mod-2^16
full-rate phase for most waves and a mod-2^17 half-rate domain for
triangle/phaser. "16.1 fixed point" is the correct RATE model (it is why
halving dq drifts the chorus); it is not the bit layout.

**This PSG adds a second, deliberate layer on top:** the two oscillators
exist per voice as state, but share ONE serialized wave shaper, gain
multiplier and mix path — the `iss_om`/`iss_os` slots, the `qv_*` steering
and the `mxs_*` sign/magnitude handling are that time-multiplexing. When
the walk reads as "one oscillator with complex logic", two layers are in
view at once: PICO-8's asymmetric pair (inherent, preserved bit-for-bit)
and this design's serialization of it (chosen; the steering muxes are
cheaper than a second shaper — see the area ledger's LAW).

## PSG vs the PICO-8 binary (reverse-engineering notes, 2026-07-25)

Source: `/Applications/PICO-8.app/Contents/MacOS/pico8-psg-re.md` - a
routine-level disassembly of the shipping PICO-8 binary. It supersedes
zepto-8 as the reference where the two disagree, because it is the real
implementation rather than a reimplementation.

Checked and already correct, so not gaps:

- **Relative waveform amplitudes.** The binary's waves have deliberately
  different peaks (square/pulse are half the amplitude of triangle, saw and
  organ two thirds). `rtl/psg_waves.hex` already reproduces that ratio to
  within 2%, so instrument balance is not the cause of a bad-sounding mix.
- **Tick length.** 183 samples at 22050 Hz = 120.49 Hz, which is `TICK_HZ`.

Real gaps, in the order they are likely to be audible:

1. **The song clock. FIXED 2026-07-25.** PICO-8's song scheduler records the
   pattern length at launch and runs a global pattern-tick counter, explicitly
   so that no single voice can advance the song clock. This PSG instead ended a
   pattern when its timing channel's `playing` bit dropped, so anything that
   disturbed that channel - above all an SFX borrowing it - could end the
   pattern early or hold it open. See `rtl/psg.sv` `W_MUS`/`T_NL` and test 18c
   in `rtl/psg_tb.sv`.

2. **Sixteen voices, not four.** PICO-8's four "channels" are logical tags on a
   pool of 16 mixer voices. `sfx(n, -1)` takes a *free voice* from that pool,
   so a sound effect can never displace music - the situation this PSG's
   borrow/restore machinery exists to survive simply cannot arise upstream.
   Four physical channels cannot reproduce this. The closest faithful
   approximation is that an auto-picked SFX must never take a channel the music
   owns, and should be dropped instead when nothing is free; today
   `src/nemo/sound.asm`'s steal path only skips the reservation mask, so it can
   still take a music channel that the mask does not name.

3. **The mixer is nonlinear and pairwise.** Voices are combined in a binary
   reduction tree, and every pair goes through `soft_add`: below +-24576 it is
   a plain sum, above it the excess is compressed 5:1 rather than clipped.
   This PSG sums all four channels flat and hard-clips the total. Because
   `soft_add` is not associative the tree order matters, which is why a loud
   mix cannot be matched by a single final limiter.

4. **The phaser is a comb filter, not a detuned pair.** Waveform 7 is the
   triangle plus half of a sample taken from an 8-slot ring of 183-sample tick
   buffers, tapped 4 (or 6) ticks back: `y = (4y + 2*history[tap][i]) / 4`.
   This PSG synthesises it as two detuned triangles, which is a different
   effect that happens to sound similar in isolation.

5. **Noise has an exact form.** The hold period is `N` samples derived from the
   phase increment (`t = 64 - x>>16`, `N = 4t-192` for `t < 64`), the generator
   is a specific RNG (`H = rol32(H,16)+L; L = L+H`), and modes above 1
   *interpolate* between successive random values rather than holding them,
   which is what makes the spectrum change with pitch. This PSG uses a 15-bit
   LFSR sample-and-hold plus the empirical gain curve in `rtl/psg_noise.hex`.

6. **Every waveform is evaluated at two phases**, primary and a 17-bit
   secondary with its own increment, summed at roughly 2:1 (triangle at 4:8).
   This PSG runs a second voice only when detune is on. Worth confirming
   against the binary's `_get_dx_for_note_fine` before changing anything: if
   the two increments are equal the secondary is only a gain.

## The target device is now a variable (2026-07-25, add-tangnano20k-target)

Appended, not woven in: several entries above cost a gap against *the hx8k*,
and that is now one of two devices. See `docs/boards.md`.

The console builds for the Sipeed Tang Nano 20K (Gowin GW2AR-18C) from the same
RTL as the BlackIce MX, and on that device the whole design is 50% of the logic
and 45 of 46 block RAMs — with the **full 64 KB main memory**, which is what
`rtl/top.sv` has never been able to carry.

What that does and does not change, for the entries above:

- **Gap 9's second overlay plane is still not affordable.** It costs "+5 blocks
  on the hx8k"; the Tang Nano build has **one** block spare. The device is 4x
  larger in logic and only 6 blocks larger than what this design already needs,
  so block RAM stays the currency and the analysis in gap 9 stands unchanged.
  What did change is that the two measurements it rests on ("there is no spare
  block RAM"; "the plane is affordable only against a device with more block
  RAM, or against the 64 KB `ram_async` array being dealt with first") were both
  about the hx8k, and the *second* of those has now happened by moving device.
  The plane is still one block short.

- **"Hardware multiply: the target device cannot help" is device-specific.**
  Under *Investigated and NOT recommended* that entry notes the Makefile
  disables yosys `-dsp` because the hx8k has no `SB_MAC16`. The GW2AR-18C has
  **48 18x18 multipliers**, and `synth_gowin` already infers four of them from
  the PSG's volume multiply with no flags at all. The entry's *conclusion* is
  unaffected — NEMO's measured demand for a general multiply is still one
  routine called three times per puzzle load, and that is the reason not to
  build a coprocessor. But the supporting sentence about the device is now only
  true of one of the two.

- **Gap 5, persistent storage (50 bits for NEMO's puzzle completion), has a
  cheaper answer on this board.** It carries 64 Mbit of QSPI flash and a
  microSD slot, both on dedicated pins. Nothing is implemented; the point is
  only that "nothing in rtl/ implements EEPROM, flash or NVRAM" now describes
  the RTL rather than the hardware.

- **The fill-rate ceiling in gap 9 is unchanged**, and always will be: it is a
  fact about the CPU's cycles per frame, not about the FPGA.

One number this produced that belongs here rather than in a board document:
**the PSG's 112.5 MHz clock domain closes at 46.27 MHz on the GW2AR-18C**,
against 28.24 MHz measured on the hx8k by `refactor-build-targets`. A device
four times larger moves a 4x miss to a 2.4x miss and no further, which settles
it as an RTL problem rather than a device problem. `cpuclk` - the CPU, PPU,
compositor and video timing - has 14.8x of margin, so nothing outside the PSG
is near the edge on either device.

Not verified on hardware. The bitstream builds (`yosys` ->
`nextpnr-himbaechel` -> `gowin_pack`, 7.3 MB `.fs`) and every number above is
read out of a routed netlist, but no board has been programmed.
`docs/boards.md` says exactly what is proven and what is not.

### Re-measured on the GW2AR-18C (2026-07-25, add-tangnano20k-target)

The `refactor-build-targets` section below closes with "This is an HX8K
result… the number does not carry over; it needs re-measuring there." It has been re-measured on a routed
netlist, and it does carry over — which is the more useful answer, because it
removes an option:

| | PSG clock domain Fmax | needed |
| --- | --- | --- |
| iCE40 HX8K (PSG alone) | 28.24 MHz | 112.5 MHz |
| **Gowin GW2AR-18C (whole chip, routed)** | **49.62 MHz** | 112.5 MHz |

A device four times larger in logic, with hardware multipliers the PSG's volume
multiply does infer (1 `MULT18X18` + 3 `MULT9X9`), moves a 4x miss to a 2.3x
miss. **So "wait for a bigger board" is not one of the options.** Of the two
fixes listed above, the reciprocal pipeline is the one that works on both
devices.

The critical path here is a different one — ~21 ns over ~31 levels, mostly
routing, running `clocks0.reset_counter` -> the arbiter's PSG select decode ->
`psg0.ins_wt`/`playing` -> `psg0.eff_vol[2].RESET` — so there is more than one
path at this length and pipelining only the reciprocal may not be enough on its
own. Measure after, not before.

`cpuclk` (CPU, PPU, compositor, video) closes at 55.22 MHz against the
3.515625 MHz it needs: 15.7x of margin. Nothing outside the PSG is near the
edge on either device.

### A second timing defect, found by the same run and fixed there

**`rtl/clocks.sv` divides the PLL output in a counter, which makes the chip
clock a flip-flop output rather than a clock network.** Place-and-route treats
it as an ordinary signal: 2.04 ns of skew corner to corner on the GW2AR, and
**three hold violations in the PPU blit** —

    ERROR: Hold/min time violation for clock 'posedge cpuclk':
      clk-skew -2.04 -2.04 Net cpuclk (31,5) -> (1,13)
                           Sink chip.g_ppu.s0.blit.data64_q_DFFR_Q_10.CLK

A hold violation is a bitstream that does not work, not one that is slow, and it
is invisible to every check this project had, because nothing had ever placed.

Fixed for the Tang Nano in `rtl/pll_gowin.v` by taking the /32 from the rPLL's
`CLKOUTD` output, which rides the clock network: 0 violations and 294 fewer
LUT4s, with the frequency, the 32:1 ratio and the phase lock unchanged.

**`rtl/top.sv` has the same structure and has never been placed.** `SB_PLL40_CORE`
has no second divided output, so the iCE40 fix is an `SB_GB` global buffer on the
divided clock. Worth doing before anyone flashes a BlackIce and wonders why the
picture is wrong.

Full numbers, and what is and is not verified on hardware, in `docs/boards.md`.

## The PSG is clocked at four times its closing frequency (2026-07-25, refactor-build-targets)

`rtl/clocks.sv` assigns `psgclk = clk`, the undivided PLL output, and
`rtl/pll.v` is generated for **112.5 MHz**. Synthesised and placed on its own
(`make synth-psg`, iCE40 HX8K tq144:4k, seed 1, RTL fingerprint `26545f591961`
at `bd502a6`), the PSG closes at **28.38 MHz**:

```
ICESTORM_LC:  6759/7680  88%      ICESTORM_RAM: 16/32
Max frequency for clock 'psgclk': 28.38 MHz
critical path: psg0.prun -> psg0.n_res      (the reciprocal / divide path)
```

A **4x miss**. The 56.25 MHz (/2) fallback named as the safe option in
`refactor-psg-voice-pool` task 2.2a1 also fails, by 2x. The first divider that
closes is **/4, 28.125 MHz**.

Introduced by `f6fd3ab` ("Clocks: one PLL at 112.5 MHz, everything derived from
it"). Nothing changed here; this is the first target able to report it. The
whole chip has never placed, so no timing report was ever produced for any part
of it — and both `docs/cpu-baseline.json` and
`refactor-psg-voice-pool/design.md` recorded per-domain Fmax as *blocked behind
area*. It was not: it was blocked behind the build having a single top. This
closes task 2.2a1.

**Consequence beyond the clock itself.** The "5102 clocks per 22050 Hz sample"
arithmetic in `clocks.sv`'s header comment and at `chip.sv:200-204` is wrong at
any divider that closes. At /4 the PSG gets **1275 clocks per sample**, which is
still comfortably enough for the sixteen BRAM-streamed voices that
`refactor-psg-voice-pool/design.md` budgets at ~320 clocks — so the voice-pool
plan survives, but its headroom claim does not.

> **SUPERSEDED 2026-07-29 — the "comfortably enough" above is wrong too, and
> by an order of magnitude.** See "What the audio actually needs" below.

**Not fixed here, deliberately.** Two candidate fixes, both owned by
`refactor-psg-voice-pool` and both gated on its render comparison
(`make psg-wav` must stay bit-identical):

1. Pipeline the reciprocal path nextpnr names (`prun` → `n_res`). Preferred:
   it keeps the sample-rate arithmetic intact.
2. Divide psgclk by 4. One line, but it changes *every* PSG rate — the sample
   tick, the sequencer tick, the noise LFSR — so it is a behaviour change
   wearing a clocking change's clothes.

Do not change `rtl/clocks.sv` without that gate.

**Device-specific.** This is an HX8K result. The Tang Nano 20K's GW2AR-18C is a
different fabric with hardware multipliers the PSG's volume multiply already
infers, so the number does not carry over; it needs re-measuring there.

## The PICO-8 binary is an exact oracle; the tolerance gates absorb OUR layers

Established 2026-07-27 from the pre-5.1 diagnostic set
(`build/psg_oracle/area-final/results.json`) and
`/Applications/PICO-8.app/Contents/MacOS/pico8-psg-re.md`:

1. **No hidden output filter.** wave-3-square, wave-4-pulse and length-only
   match the PICO-8 exports at correlation 1.000000 / NRMSE 0.00001 - the two
   shapes our RTL computes exactly pass the whole capture pipeline at
   quantization level. A low/high-pass would deform square hardest, not least.
2. **One mis-recovered constant.** All table waves sit at a systematic fitted
   gain of +0.8%; pre-5.1 saw was the outlier at 1.0289, and our effective
   slope times that fit is 0.6666. The binary's saw is exactly
   `tz((x - 32768) / 4)` on the 16-bit phase; the generator's 0.653 is a
   mis-recovery of 2/3's effect through the common scale.
3. **The universal second phase.** Every waveform is `wave(p)/4 + wave(q0)/8`
   with a 17-bit secondary phase and the common stage
   `scale(z) = tz(G*z/3072)`, `G = tz(3a/2)` (noise divides by 2048). The RE
   notes state outright that a single-phase textbook waveform cannot be
   bit-equivalent. Our 256-entry single-period tables cannot bake the q0
   term; that is the likely floor under the uniform ~1.5% post-fit NRMSE
   while the two-phase detune probes sit at 0.0005.
4. **Drop/dampen is the gate nearest its limit** (NRMSE 0.066-0.073 against
   0.08) and the largest true shape divergence; the binary's exact recurrences
   are in the RE notes, unmined. It is what rejected the triangle formula in
   task 5.1.

Consequence worth a proposal: the binary's native integer forms are cheaper
than our approximations of them (truncating shifts, thresholds, one shared
divide by 3072). Adopting its wave pipeline - 16-bit phase in, its exact
formulas, G*z/3072 through the shared product service - could deliver
byte-level wave exactness and compete on area, while widening the drop-gate
headroom that currently constrains every wave decision.

## Arithmetic shift right (measured 2026-07-28)

The 6502 has no ASR, so every corpus that halves a signed value open-codes one
out of `cmp #$80 / ror` - the compare exists only to put the sign bit into
carry so `ror` can rotate it back into bit 7.

Measured across all three corpora:

| Shape | Sequence | celeste | nemo | breakout | total |
| --- | --- | ---: | ---: | ---: | ---: |
| accumulator | `cmp #$80` / `ror` | 3 | 0 | 4 | 7 |
| word | `lda X+1` / `cmp #$80` / `ror X+1` / `ror X` | 2 | 0 | 0 | 2 |

Nine sites over two corpora. Adopted in source as the `asr`/`asrw` pseudo-ops
(`openspec/changes/add-isa-width-suffixes`), which are byte-identical to the
sequences above, so both ROM images are unchanged by the migration.

The projection, on this core's timings rather than NMOS: `ASR A` at 1 byte and
2 cycles against 3 and 4 saves 2 bytes and 2 cycles per site; `ASRW zp` at 2
bytes and a claimed 8-10 cycles against 8 and 13 saves 6 bytes and 3-5 cycles.
The accumulator form is also the rarer kind of gap - the expansion's final
flags already equal what the hardware instruction would produce, so adopting
the instruction later changes no behaviour at all. The word form is not: it
must load the high byte to test the sign, so as a pseudo-op it clobbers `A` and
leaves `Z`/`N` from the low byte, where hardware would preserve `A` and set
them from the 16-bit result.


## What the audio actually needs, derived from the audio (2026-07-29)

Every clock number in this file until now was derived from the SUPPLY side:
the PLL runs at 112.5 MHz, /4 is the first division that closes, therefore the
PSG has 1275 clocks per sample, therefore (it was assumed) plenty. The demand
side — how many clocks does rendering 22050 Hz of PICO-8 audio actually
require — had never been measured. It has now, two ways.

### The requirement, bisected against the byte-exact oracle

The oracle matrix renders 59 cases and compares every sample byte-for-byte
against the frozen `adopt-exact` set. Re-running it at a swept `--clock` asks
the only question that matters: at what rate does the chip stop producing the
same audio?

| clock | clocks/sample | oracle |
| --- | --- | --- |
| 28.125 MHz (shipping) | 1275 | 59/59 |
| 27.0 MHz | 1224 | 59/59 |
| 26.5 MHz | 1201 | **59/59** |
| 26.25 MHz | 1190 | 58/59 — `mix-four` diverges |
| 26.0 MHz | 1179 | 55/59 — `mix-four`, `pattern-chain`, both `filter-reverb-*` |

**For these 59 cases the PSG needs between 1190 and 1201 clocks per sample. It
is given 1275 — a 6-7% margin, not the 4x that "1275 against a ~320-clock
budget" implies.** The binding case is `mix-four`.

It is NOT a sample-side limit, despite `mix-four` being a mixing case. The
walk's length is a constant: `pph` runs 0..PLAST for each of eight slots, so
the walk is exactly 8 x 109 = **872 clocks regardless of content** — which is
precisely the average AND the maximum the instrumented run measured. Add the
post-walk fold and the sample side is a flat 906. Nothing about it varies, so
nothing about it can be what breaks first. The variable is the tick program,
which spans up to six sample intervals and is frozen for 872 of every 1275
clocks in each of them.

**And the 1190-1201 figure only describes these 59 cases. A real cart does not
behave this way at all — see below.**

Restated as a frequency requirement, from first principles rather than from
the PLL: **f_min = 22050 x 1201 = 26.48 MHz.** The shipping 28.125 MHz clears
it by 6.2%. Routed Fmax is 36.19 MHz, so the design also has 29% of TIMING
margin above the rate it runs at — two different margins that had been
conflated.

### psg_tb's deadline checks do not cover the binding constraint

At 26.0 MHz `psg_tb` reports zero deadline failures — `synthesis deadline:
worst 906 / 1275` — while four of the 59 oracle renders are wrong. Its
accounting measures the walk's completion and the tick pre-run's bank flip;
neither is what breaks first. The failures that do appear at 26 MHz are the
slide trajectory checks, which are value checks, not deadline checks.

So the "worst 906 / 1275" figure is real but it is not the margin: **the
test's own stimulus is not the worst case, and its deadline definition is
necessary but not sufficient.** Treat the oracle clock sweep as the margin
measurement; treat psg_tb's deadline lines as a smoke test.

### Where the clocks actually go

Measured over 116,860 rendered samples (instrumented `psg_tb`, counters that
are properties of the PROGRAM and so independent of the clock rate):

| | clocks | share of all clocks |
| --- | --- | --- |
| synthesis walk (`prun` high) | 101,901,920 | **68.4%** |
| sequencer FSM advancing | 144,033 | **0.097%** |
| sequencer frozen behind the walk | 38,811 | 0.026% |
| idle | ~46.9M | 31.5% |

The walk averages **872 clocks per sample** and peaks at 906 under this
stimulus. The sequencer's ENTIRE per-tick program averages **1.23 clocks per
sample**.

Sequencer occupancy by state group, over 638 ticks (includes frozen cycles):

| group | clocks | per tick |
| --- | --- | --- |
| record streaming `V_LD`/`V_ST`/`K_ROT` | 79,854 | 125 |
| **effect microprogram `K_PF0`/`K_FX`** | **36,957** | **58** |
| slide detour `K_SL0..8` | 24,194 | 38 |
| publication `P_W*`/`PC*` | 22,662 | 36 |
| note fetch `T_*`/`K_NL`/`K_NH`/`K_LD`/`K_ARP*` | 10,670 | 17 |
| tick engine `EA*`/`ES*` | 7,436 | 12 |
| music flow `ML_*`/`MS_*` | 754 | 1.2 |
| instrument `I_*` | 317 | 0.5 |

**The effect microprogram is 58 clocks per tick — 20% of the sequencer's work
and 0.02% of the chip's clocks — for a module that is 33% of its LUT4s.** The
record streaming above it is more than twice as expensive in cycles and is the
first thing to look at if the sequencer is ever re-serialised.

### What this means for time-for-space trades

The two margins point opposite ways and must not be confused:

- **Cycle margin on the sample side is 6-7%, not 4x.** The walk cannot absorb
  a serialisation that costs it more than ~70 clocks per sample without
  raising the clock, and raising the clock is not free (see PSGDIV above).
- **Cycle margin on the tick side is enormous** — the sequencer uses 0.1% of
  the clocks for 33% of the logic. Anything traded there is nearly free in
  time and expensive in area today, which is exactly backwards.

So: further time-for-space work belongs in `psg_seq`, and essentially nowhere
else. And it should take the form that this fabric rewards — moving selection
and constants onto BRAM ports, which have no per-bit input muxes — rather than
slicing wide ALUs into narrow ones, which has been measured to lose here
repeatedly (see `openspec/changes/reduce-psg-ice40-area/design.md`).


## A real cart is not clock-invariant AT ALL (2026-07-29)

> **SUPERSEDED 2026-08-01.** The measurements below remain the evidence for
> the old unbounded schedule. R.54 fixes the root mechanism and establishes a
> new exact `/5` operating point; see the superseding section below.

The oracle's 59 cases are one to three seconds each and mostly exercise a
single event. Celeste is the obvious next question, and the answer is worse
than a margin.

Rendering `celeste-15133.p8.png` music 0 for 60 s (`sim/psg_wav.cpp` built at
`-GCLK_HZ=<f>`, `--clk <f>`) and byte-comparing every pair:

| pair | first difference | samples differing |
| --- | --- | --- |
| 28.125 vs 30.0 MHz | 8.4982 s | 79.6% |
| 28.125 vs 27.0 MHz | 8.4985 s | 66.2% |
| 28.125 vs 26.5 MHz | 8.4985 s | 66.2% |
| 30.0 vs 27.0 MHz | 8.4982 s | 60.6% |
| 27.0 vs 26.5 MHz | 9.3036 s | 35.1% |

**Every clock renders differently, including 30 MHz — MORE clocks per sample
than the shipping 28.125.** So this cannot be a shortage of cycles. The
differences are not small and not a timing shift: peak deviation is 197% of
the signal's own peak, the difference RMS exceeds the signal RMS, and testing
alignments from -40 to +40 samples confirms shift 0 is the best fit. The two
renders are identical sample-for-sample until the divergence and then simply
play different audio.

The divergence instant is not arbitrary. 187,392 samples is **tick 1024.000
exactly** — a tick boundary, and for Celeste's music 0 a pattern-chain event.
Corroborating it from the other direction: of the four oracle cases that break
first at 26 MHz, one is `pattern-chain`, the only case in the matrix that
chains patterns at all.

**Prime suspect, not yet root-caused:** the deferred pattern-length capture in
`rtl/psg_seq.sv`. It is deliberately ungated by `walk_frozen` — the product is
launched fire-and-forget at `T_NL` and picked up "before that sample's own
PWORK+4 product reuses `m_res`", a race the comment prices at nine cycles of
margin. That margin is denominated in clocks while the thing it races is
positioned by clocks-per-SAMPLE, so changing the clock in EITHER direction
re-phases it. The existing `$error` guard covers only the launch being blocked
by a busy multiplier, not the capture losing its race.

**What this means, and it is not a margin statement:** 28.125 MHz is not a
floor that the design clears with 6%. For real cart content it is a FIXED
POINT that the rendered audio is pinned to. The oracle's byte-exact gate
cannot see this because its cases are too short to reach a pattern chain.

Consequences to take seriously:

- The `psgclk` divider cannot be changed - in either direction - without
  re-adjudicating every render. `PSGDIV` was already documented as one-way for
  a different reason; this makes it one-way for a stronger one.
- Porting to another board is affected. The Tang Nano 20K path has its own PLL
  and its own achievable frequencies; on this evidence it will not render the
  same audio unless it is given exactly 1275 clocks per sample.
- The oracle matrix should grow a long, pattern-chaining case. It is the one
  class of content its 59 cases do not cover, and it is the class that fails.

## Superseding result: clock-invariant at `/5`, not `/6` (2026-08-01)

The old fixed point was real but not fundamental. The sequencer advanced for
whatever clocks the sample walk left in each interval, so a different PSG
clock eventually crossed a long pattern-chain boundary in a different state.
R.54 gives it exactly **272 non-walk advances per sample**. The synchronous
audio-RAM path holds its registered output across an arbitrary credit freeze,
and a newly exposed fade/control-ROM collision replays the displaced walker
word. Those changes make the render independent of surplus clocks.

The current full walk is 618 clocks, so the choices are now explicit:

| divider | PSG clock | minimum clocks/sample | fixed job | margin | result |
| --- | ---: | ---: | ---: | ---: | --- |
| `/4` | 28.125 MHz | 1,275 | 618 + 272 | 385 | exact |
| `/5` | 22.5 MHz | 1,020 | 618 + 272 | 130 | **accepted** |
| `/6` | 18.75 MHz | 850 | 618 + 272 | -40 | rejected |

Thus the useful answer is `/5`, not a literal halving and not `/6`. A `/6`
build fails an explicit insufficient-credit assertion; it needs an exact
five-phase-per-slot reduction in the eight-slot walk before it can be retried.

The `/5` clock is generated by a registered modulo counter on the 112.5 MHz
PLL's falling edge. Its high/low duty is 2/3 source cycles. CPU, video and
master clocks remain `/32`, and every non-power-of-two PSG rising edge lands on
a PLL falling phase rather than coinciding with their PLL-rising launch edge.
This is a deterministic phase relationship, not a synchronizer. The minimum
launch-to-capture separation is only half a source period, about **4.44 ns**;
the bus level is stable for at least `floor(32/5) = 6` complete PSG clocks, but
future PLL, divider or bus-timing changes must re-analyse and constrain the
crossing. The routed design has only 61 LCs spare, so this checkpoint does
not add a synchronizer.

Final evidence at source fingerprint `0e5e9be9e713`:

- 6,705 LUT4, 1,663 carries, 1,451 flops and 13 EBRs;
- all nine audio-RAM EBRs use their inferred read clock-enable; the former
  13-bit replay-address register is gone;
- quotient/remainder secondary-increment arithmetic is exhaustively identical
  over 524,288 tuples and removes 27 carry cells;
- 7,619/7,680 placed LCs; seed-1 `router2` Fmax is 33.80 MHz against 22.5 MHz
  required (the default router repeats a fixed high-density impasse);
- `make test-psg`: 618/1,020 sample clocks, 4,791/6,123 tick-preparation
  clocks, 1,332 spare and zero late flips;
- frozen oracle: 59/59 byte-identical;
- final 400,000-sample Celeste music-0 renders at 28.125 and 22.5 MHz:
  byte-identical SHA-256
  `970b0691a90202d2be83ef158be4c750adc4ec66b4528454c9a80abb581737d5`;
- host render time: 57.612 s -> 46.830 s, **18.7% less** (non-normative);
- `make test-clocks` and the five-frame Celeste active-audio smoke pass.

## Superseding result: `/6` closes exactly (2026-08-01)

R.58 recovers the 40 clocks `/6` lacked by shortening every full-schedule slot
visit from 73 to 68 phases. `PSTOR` moves to 51, the blend is consumed on its
first readable phase at 65, dampen/filter commit directly from that result, and
the two late state writes land at 66/67. Phase 67 also closes the slot and
launches the fold. The full walk therefore falls from 618 to 578 clocks.

| divider | PSG clock | minimum clocks/sample | fixed job | margin | result |
| --- | ---: | ---: | ---: | ---: | --- |
| `/4` | 28.125 MHz | 1,275 | 578 + 272 | 425 | exact |
| `/5` | 22.5 MHz | 1,020 | 578 + 272 | 170 | exact |
| `/6` | 18.75 MHz | 850 | 578 + 272 | 0 | **accepted** |

The `/6` clock comes from the registered modulo divider on the 112.5 MHz
PLL's falling edge. Its high/low duty is 3/3 source cycles. CPU, video and
master clocks remain `/32`; the minimum launch-to-capture separation remains
half a source period, about 4.44 ns, and a bus level is stable for at least
`floor(32/6) = 5` complete PSG clocks. This deterministic phase relationship
still needs an explicit timing/CDC constraint; it is not a synchronizer.

Final evidence at source fingerprint `85d2e30c4873`:

- 6,708 LUT4, 1,663 carries, 1,451 flops and 13 EBRs;
- 7,625/7,680 placed LCs; seed-1 router2 with alternate weights routes at
  31.30 MHz against 18.75 MHz required;
- `make test-psg`: 578/850 sample clocks, 4,070/5,103 tick-preparation clocks,
  1,033 spare, zero late flips and no lost state writes;
- multiplier model, 524,288-case dq17 model, lifetime audit and `/4`/`/5`/`/6`
  clock bench pass;
- frozen oracle: 59/59 byte-identical at explicit 18.75 MHz;
- forced Verilator 5.050 Celeste build is warning-clean; the explicit 16-bit
  `s_phase` wrap removes the original WIDTHTRUNC failure;
- five-frame Celeste smoke: 3,668 active samples, range -24,668..24,659 and
  1,073 distinct levels;
- regenerated visualization: 68 hardware / 24 preview phases, no attribution
  warnings.

There is no minimum-interval margin at `/6`. Any full-walk growth or change to
the 272-credit contract must re-open the clock choice. The Tang Nano target is
not changed by this result; it keeps its independent 112.5 MHz PSG clock until
that board has separate clock-routing and placement evidence.

## Further PSG area result: early effect publication (2026-08-01)

R.59 keeps the accepted `/6` schedule and removes two tick-side holding
registers. The final pitch increment is written to the inactive parameter bank
as soon as it is available, then the effect microprogram resumes at the same
step; its later publication point writes only the remaining two words. The
previous-volume operand is read directly from the stable voice fields. Atomic
bank publication, sample timing and the number of sequencer states are
unchanged.

Evidence at source fingerprint `81eb0cefc834`:

- 6,665 LUT4, 1,662 carries, 1,435 flops and 13 EBRs;
- 7,586/7,680 placed LCs, down 39 from R.58;
- seed-1 alternate-weight router2 routes at 34.42 MHz against 18.75 MHz;
- `make test-psg`: 578/850 sample clocks and 4,070/5,103 tick-preparation
  clocks, with 1,033 spare and zero late flips;
- frozen oracle: 59/59 byte-identical at explicit 18.75 MHz;
- forced Verilator 5.050 console build is warning-clean.

The placed delta is smaller than the known +/-60 mapping-sensitivity band, so
it is not used alone as proof. The independent mapped reductions (-43 LUT4,
-1 carry and -16 flops) establish the real structural saving.

## Further PSG area result: narrower shared multiplier (2026-08-01)

R.60 narrows the multiplier's internal magnitude and accumulator boundary from
21 to 18 bits. The older 21-bit proof included a pitch increment already
shifted by eight; current callers supply the unshifted table word and restore
that fixed-point position only at their constant result slices. The limiting
live operand is signed 18-bit (`-131072`), while all other request families are
narrower. The public 34-bit result, every landing offset and every schedule
phase remain unchanged.

Evidence at source fingerprint `95095b93cabb`:

- the cycle-exact model proves all multiplier modes, signs, corner operands,
  overflow bounds, result landings and named consumer slices;
- 6,648 LUT4, 1,656 carries, 1,429 flops and 13 EBRs, reductions of
  17 LUT4, six carries and six flops from R.59;
- 7,566/7,680 placed LCs, down 20 from R.59;
- seed-1 router2 routes at 33.87 MHz against the selected 18.75 MHz clock;
- `make test-psg`: unchanged at 578/850 sample clocks and 4,070/5,103
  tick-preparation clocks, with zero late flips;
- frozen oracle: 59/59 byte-identical at explicit 18.75 MHz;
- forced Verilator 5.050 console build is warning-clean.

## Rejected PSG area result: direct volume-result consumption (2026-08-01)

R.61 removed the twelve-bit effect volume register and read the stable voice
fields plus persistent divider/multiplier results directly. Function and
schedule stayed exact: 578/850 sample clocks, 4,070/5,103 tick-preparation
clocks with 1,033 spare and zero late flips, 59/59 byte-identical renders at
18.75 MHz, and a warning-clean Verilator 5.050 console build.

Area moved the wrong way. Candidate fingerprint `f7b2e1e9705b` maps 6,674
LUT4, 1,655 carries, 1,417 flops and 13 EBRs. Although twelve flops retire,
the new consumer selection costs 26 LUT4s and seed-1 placement rises from
7,566 to **7,590 LCs (+24)**. Routing still completes at 30.79 MHz, but timing
headroom is not the binding resource. The candidate is reverted exactly to
R.60 fingerprint `95095b93cabb`; retry only if the effect order or publication
cone changes enough to remove the selection cost.

## Rejected PSG area result: shape-selected wave payloads (2026-08-01)

R.62 replaced parallel, mutually exclusive wave-pipeline fields with one
18-bit shape payload and one 15-bit divide payload. The change is exact:
the 524,288-case dq17 proof, the 578+272 `/6` schedule, zero-late-flip PSG
suite and 59/59 byte gate all pass.

The source removes 48 fields, but the selected payload maps to only 29 fewer
flops and 54 more LUT4s. Candidate fingerprint `fb9c4d6512fe` uses 6,702 LUT4,
1,656 carries, 1,400 flops, 13 EBRs and **7,591 placed LCs (+25)**; routing is
33.13 MHz. The shape selector costs more than the parallel register islands,
so the candidate is reverted exactly to R.60 fingerprint `95095b93cabb`.

## Rejected PSG area result: accumulator-adder magnitude sharing (2026-08-01)

R.63 reused the multiplier accumulator adder for request-time signed-to-
magnitude conversion. The two operations are cycle-disjoint, and the
cycle-exact multiplier model proves the shared form preserves every sign,
mode, landing and named consumer slice.

The intended carry-chain saving did not reduce the binding area. Candidate
fingerprint `5ee62b672b50` maps 6,668 LUT4, 1,639 carries, 1,429 flops and
13 EBRs. Seventeen carry cells retire, but the load-versus-step operand
selection adds 20 LUT4s; seed-1 placement rises from 7,566 to **7,610 LCs
(+44)** and routes at 31.10 MHz. The candidate was therefore rejected before
the render battery and reverted exactly to R.60 fingerprint `95095b93cabb`.
Only the materially different radix-digit-adder sharing shape warrants one
measurement; another selector-cost result closes this arithmetic-sharing
mechanism.

## Rejected PSG area result: radix-digit-adder magnitude sharing (2026-08-01)

R.64 placed request-time magnitude conversion on the cycle-idle radix-digit
`3A` adder instead of R.63's accumulator adder. The cycle-exact model proves
all signs, modes, landings, overflow bounds and named consumer slices.

Candidate fingerprint `536732e78c3d` maps 6,681 LUT4, 1,640 carries, 1,429
flops and 13 EBRs. Sixteen carry cells retire, but the digit-adder input
selection adds 33 LUT4s and makes more multiplier state unpackable. Seed-1
placement rises from 7,566 to **7,609 LCs (+43)**; routing remains ample at
33.87 MHz. The candidate is reverted exactly to R.60 fingerprint
`95095b93cabb` before the render battery. R.63 and R.64 now close current
multiplier-adder sharing under the two-variant stop rule: both remove a carry
chain but cost more LUT and placed fabric. Reopen only if the digit arithmetic,
request boundary or mapper carry lowering materially changes.

## Rejected PSG area result: narrower effect-volume path (2026-08-01)

R.65 proved that the remaining 12-bit effect-volume value is always at most
`7 * 256 = 1,792` (`0x700`). An exhaustive pre-edit enumeration covers
6,315,840 valid effect speed/count cases plus every instrument volume and all
256 music gains. Interpolation stays between its endpoints; fade effects,
instrument scaling and music gain never amplify. Bit 11 is therefore always
zero, while the signed endpoint difference still fits 12 bits.

The narrower spelling is exact but not smaller on iCE40. Candidate fingerprint
`a15823bc80b2` maps 6,655 LUT4, 1,651 carries, 1,428 flops and 13 EBRs: one
flop and five carries retire, but seven LUT4s are added. Seed-1 placement rises
from 7,566 to **7,572 LCs (+6)**; routing then stalls at 7,819 unresolved arcs
and is stopped because the area gate already fails. The candidate is reverted
exactly to R.60 fingerprint `95095b93cabb` before render testing. The bound is
real, but the mapper already absorbs that zero high bit into the selected
volume arithmetic; retry only if the cone or representation changes.

## Rejected PSG area result: slide low-word lifetime reuse (2026-08-01)

R.66 reused the dead low half of `sl_uhi` for the slide affine's one-cycle
`sl_rlo` lifetime. The schedule proof is direct: the constants low word is
loaded at `K_SL5`, consumed in `sl_u` at `K_SL6`, and the host is wholly
overwritten with the existing high result on that same edge.

Candidate fingerprint `034fb20afb4e` removes all 16 intended flops and maps
6,665 LUT4, 1,650 carries, 1,413 flops and 13 EBRs. The host's added write arm
costs 17 LUT4s; seed-1 placement improves only from 7,566 to **7,557 LCs
(-9)**, inside the known +/-60 mapping-sensitivity band, and routing reaches
34.29 MHz. Because deterministic LUT area regresses, the candidate is rejected
and reverted exactly to R.60 fingerprint `95095b93cabb` before render testing.
An adjacent lifetime still does not pay when it merely replaces one register
with a wider D-input selector; reopen only if the slide stage itself changes.

## Rejected PSG area result: partial reciprocal de-condensation (2026-08-01)

R.67 spent the two EBRs available under the 15-block ceiling on a direct
1,024x7 tilted-saw remainder table. The one-fold identity is exact for every
16-bit phase and the reachable direct index is at most 844, so the arithmetic
and memory sizing are not the issue.

Candidate fingerprint `b3408a401fff` infers 15 EBRs but maps 6,737 LUT4,
1,655 carries and 1,429 flops. Keeping the condensed `/3` and `/15` port while
adding a second registered table/output selector costs **89 LUT4s**; seed-1
placement rises from 7,566 to **7,652 LCs (+86)** and routing reaches 32.13
MHz. The candidate is reverted exactly to R.60 fingerprint `95095b93cabb`
before structural/render testing. R.27's six-block condensation cannot be
profitably reversed one divisor at a time while its original port remains;
retry only as a complete port-partition replacement or after the EBR/selection
contract changes.
