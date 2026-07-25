## Why

Every ISA gate is scored over one program. `add-isa-ergonomic-gates` names this as
its own biggest risk — *"Breakout is the only substantial program on this console;
an ISA tuned to it may be tuned to one game's habits"* — and leaves the fix as an
open question: port a smaller cart, or write a synthetic benchmark?

The cost of having one corpus is not abstract. It is concentrated in exactly the
three slices with the weakest evidence:

| Slice | Evidence from Breakout Hero | Status |
| --- | --- | --- |
| `add-isa-word-ops` | **zero** literal 16-bit add chains, against 122 `foo+1` operands | G3 met only through the rewrite-measured escape hatch |
| `add-isa-pointer-ops` | 16 `(zp),Y` sites against 41 `ldy` / 62 `ldx` | *"Gate G3 is not yet satisfied for this slice"* |
| `add-isa-frame-pointer` | 141 flat `.define`d globals | *"no G3 pattern evidence and cannot get any"* |

Breakout Hero cannot supply that evidence, and not by accident. It is a
fixed-arena game: flat arrays, tilemap bricks, byte counters, a bounded `X`
index. It has no object system, so it needs no indirect dispatch. Its physics are
table-driven angle vectors with integer positions, so it needs no fractional
accumulator. Its routines are leaf-ish, so globals-as-locals never collides. The
program is not pointer-light and 16-bit-light because the ISA makes those
expensive — it is pointer-light because *that genre does not need them*.

### Why Celeste Classic

[Celeste Classic](https://www.lexaloffle.com/bbs/?tid=2145) (Maddy Thorson and
Noel Berry, 2015) is the complement, and it is the right kind of hard: **8186 of
8192 code tokens, the entire spritemap, the full map, 63 of 64 sound effects** —
the authors' own note is that they used "pretty much all our resources". It is not
a toy, it is famous enough that a port is reviewable by people who know the
original, and its three defining systems are precisely the three the gates cannot
currently see:

| System | Shape in 6502 | Calibrates |
| --- | --- | --- |
| Object list with per-type `update`/`draw` | indirect dispatch through function pointers; walking a struct array | `add-isa-pointer-ops` |
| Sub-pixel movement: `spd.x/y` accumulated into `rem.x/y` each frame, per object | literal 16-bit fixed-point add chains — the pattern `add-isa-word-ops` claims exists and cannot find | `add-isa-word-ops` |
| Per-object state: dash time, grace, `jbuffer`, `djump`, sprite offset, across nested calls | genuine locals, in quantity, in routines that call each other | `add-isa-frame-pointer` |
| `tile_flag_at` / `is_solid` bit tests over map attributes | mask-and-branch on memory | `add-isa-test-and-branch` |

`move()`'s remainder accumulation alone should convert word-ops' G3 from a
rewrite-measured argument into a literal pattern count.

### It fits the console, with one problem and one fix

Checked against the hardware rather than assumed:

- **Horizontally it fits with room to spare.** The console displays 160×120
  (`hvsync_generator.sv:6-11`); PICO-8 is 128 wide, leaving 32 columns — the same
  place Breakout puts its HUD.
- **Vertically it does not.** Celeste is 128 tall and the console displays 120
  lines. A Celeste room is exactly 16×16 tiles and the whole room is meant to be
  on screen at once, so losing 8 lines in a precision platformer is not cosmetic.
- **The compositor already solves it.** The sprite/tile world is 256×128 with a
  7-bit **camera Y** at `$4004` (`sprite_compositor.sv:30`, `:546`), giving
  exactly the 8 lines of vertical travel needed to cover a 128-tall room inside a
  120-line window. The cost is a fidelity decision: Celeste's camera is static per
  room, and this one has to follow the player by up to 8 pixels.
- **Two rooms fit in the tilemap at once.** The map window is 512 cells
  (`$000-$1FF` patterns, `$200-$3FF` attributes) and a room is 16×16 = 256, which
  is what room-transition slides want.

## What Changes

- **A second corpus**: a hand-written 6502 port of Celeste Classic under `src/`,
  added to the set of programs the ISA gates are scored over.
- **Gates become multi-corpus.** G3 (idiom frequency), G5 (corpus reduction) and
  G6 (plumbing ratio) are today defined over `src/main.asm`. They SHALL be scored
  per corpus and reported per corpus, with the threshold met in **at least one**
  and regression permitted in **none**. An instruction justified by one program
  and unused by the other is a finding, not a failure — but it must be visible.
- **Staged scope, with the calibration value in stage 1.** Stage 1 is the engine:
  player entity, collision, the object list and its dispatch, movement with
  sub-pixel remainders, room transitions, camera. Plus three rooms, chosen to
  exercise different tile flags. **Stage 1 alone satisfies the calibration
  purpose** — every code shape above is present in it. Stage 2 is content: the
  remaining rooms, strawberries, balloons, springs, fake walls, the ending. Stage 2
  adds data, not new idioms, and is explicitly optional.
- **Baseline measurement before any ISA slice touches it**, so the corpus records
  what hand-written 6502 costs for these idioms on the *current* ISA. Without that
  pre-slice measurement the corpus cannot calibrate anything.
- **`tools/isa_metrics.py` learns about multiple corpora**: a corpus manifest, per-
  corpus reports, and a combined gate verdict. `docs/isa-baseline.json` grows a
  per-corpus section.
- **Vertical camera follow** as the resolution to the 128-vs-120 problem, recorded
  as a deliberate divergence from the original in the port's header comment.
- **Attribution follows the Breakout convention** already established at
  `src/main.asm:5-7`: the game logic is an original 6502 implementation written for
  this hardware, with the cart's art, map and SFX data used under attribution to
  its authors. The posture is confirmed before the port starts, not after.

Not in scope: making Celeste the *primary* corpus (Breakout Hero stays the
reference for existing baselines), a third corpus, and any ISA change — this
change adds a measurement subject, nothing else.

## Impact

- Affected specs: `cpu-isa` (adds multi-corpus gate scoring; the capability is
  created by `add-isa-ergonomic-gates`)
- Affected code: `src/celeste/*.asm` (new), `src/celeste_data.asm` (new, extracted
  cart data), `tools/isa_metrics.py` (multi-corpus support),
  `docs/isa-baseline.json` (per-corpus sections), `docs/corpora.md` (new),
  `Makefile` (build and measure a second program)
- Depends on: `add-isa-ergonomic-gates` for the gate definitions and the metrics
  tool this extends. The p8.png extraction pipeline from the Breakout port is
  reused.
- **Answers an open question in `add-isa-ergonomic-gates`** ("port a smaller cart,
  or write a synthetic benchmark?") and makes its "second corpus before slice 6"
  mitigation concrete. Recommended earlier than that: **before slice 5
  (`add-isa-word-ops`)**, which is the first slice whose G3 this corpus converts
  from a rewrite argument into a pattern count.
- Blocks nothing outright, but every slice that lands before it is calibrated
  against one program and will need re-scoring afterwards. That re-scoring cost is
  the argument for doing it early.
- **Corpus size is unknown until ported.** 8186 Lua tokens does not convert to a
  known 6502 instruction count; Breakout Hero is 1919 instructions and Celeste's
  engine is plausibly larger. The gate thresholds in
  `add-isa-ergonomic-gates` are absolute counts (≥8 sites) rather than ratios, so
  a larger corpus makes G3 easier to satisfy — which is a reason to report per
  corpus rather than pooling the counts.
