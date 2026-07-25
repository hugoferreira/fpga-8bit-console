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
   job. What stops it is one line: `sprite_compositor.sv:317` mixes it with a
   single mux, so it is always ABOVE tiles and sprites and always one colour.
   Clouds need to be behind, in colour 1; the HUD needs to be in front, in
   white; there is one plane and one priority, so they cannot coexist.

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

`make psg-rows CART=... SFX=n` renders one SFX through the real RTL and lines up
the energy of each row against the cart's own note data. It needs no reference
recording: the cart already says what each row should be, so a silent row that
should sound localises the fault to a row, and therefore to a waveform, a volume
or an effect.

It is how the phaser bug above was found. Every silent row in NEMO's SFX 8 was
wave 7 and no other waveform was affected, which ruled out sequencing, pitch and
the mixer in one pass and pointed at the phaser. The companion tools are
`make psg-wav` (render to a WAV and listen) and `make psg-notes` (per-row pitch
and waveform), both from the celeste agent.

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
   check `make psg-notes` went from 28/32 to 31/32 on SFX 7 at the same time,
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
