## Context

The corpus set after `add-celeste-corpus` is Breakout Hero and Celeste Classic:
both 60 fps action games, both with per-frame entity updates, both written against
a frame budget. `add-celeste-corpus` records this as its residual risk and suggests
a non-game third corpus as the fix, deferred rather than dismissed.

This change takes that up, with a puzzle game rather than a non-game. The
distinction that matters is not "game vs tool" — it is **frame pressure vs none**.

## Goals / Non-Goals

**Goals**

- Measure the plumbing ratio in a program where nothing was hand-optimised to fit
  a frame.
- Contribute the idiom families two action games structurally lack: non-power-of-two
  2D indexing, sequential stream decoding, packed tri-state bitfields.
- Make the demand for a multiply measurable, since `add-math-coprocessor` currently
  has none.
- Record the capabilities the console lacks, instead of stubbing around them.

**Non-Goals**

- Carrying G3 thresholds. This corpus is small; its value is diversity.
- Informing G8. A puzzle game idling on input has no frame-work window worth
  measuring, and pretending otherwise would be worse than declaring the gap.
- Adding persistent storage or a multiplier. Both are findings here and proposals
  elsewhere.
- Replacing either existing corpus.

## Decisions

### Decision: the axis is frame pressure, not genre

It is tempting to describe this corpus as "a different genre", but genre is a proxy.
The property that confounds the gates is that a programmer under frame pressure
hand-optimises, and hand-optimisation *is* plumbing: values get kept in registers
across statements, stores get hoisted, a loop gets unrolled so `A` stays live. The
32.8% plumbing figure for Breakout is therefore partly a measure of the ISA and
partly a measure of the programmer working around the frame budget.

A nonogram board is redrawn when the cursor moves and otherwise not at all. Nothing
in it is written for speed. Whatever plumbing remains is the ISA's fault, and that
is the number worth having.

Consequence for the metrics tool: the corpus registry carries a
`frame_bound: true|false` flag, and gate reports group by it. Comparing Breakout's
plumbing ratio to NEMO's directly would be a category error; comparing each against
its own pre-extension baseline is the valid operation.

### Decision: NEMO rather than a non-game utility

`add-celeste-corpus` floated "a monitor, a text tool" as the third corpus.
Rejected in favour of a game, for two reasons:

- **A utility has no visual output pipeline**, so it exercises none of the PPU, the
  tilemap, the overlay or the sprite list. A corpus that touches no hardware
  measures the ISA in a vacuum this console never runs in.
- **A utility written for this purpose is a benchmark in disguise** — the same
  objection `add-celeste-corpus` raises against synthetic corpora. NEMO is a real
  cart somebody shipped, with 50 puzzles and a save system, written without any
  knowledge of this project.

A puzzle game keeps the "real program, real constraints, no frame pressure"
combination that is actually wanted.

### Decision: the 15-wide grid is the headline evidence

Every 2D structure in the corpus set so far is power-of-two aligned:

| Structure | Width | Indexing |
| --- | --- | --- |
| Breakout tilemap | 8-aligned tiles | shift |
| Celeste room | 16×16 tiles | shift |
| **NEMO grid** | **15** | **multiply, or a 15-entry row-base table** |

The 6502 has no multiply. So the port must either build a row-base table (a pointer
idiom, evidence for `add-isa-pointer-ops`) or synthesise `×15` from shifts and adds
(`(y<<4) - y`, evidence for nothing except that it hurts). **Whichever the porter
writes is the finding**, and it must be recorded rather than chosen in advance —
the same rule `add-celeste-corpus` applies to its object dispatch.

This is the first countable demand for `add-math-coprocessor`, which
`add-isa-ergonomic-gates` deferred on the grounds that multiply "belongs in a
peripheral" without any measurement showing it was wanted.

### Decision: gaps are recorded, not stubbed

`docs/hardware-gaps.md` already exists and already works this way — its header is
*"Findings from porting Breakout Hero with the intent of matching the original, not
dumbing it down"*, and it is what produced the PSG, the sprite-vs-tilemap split and
the hardware LFSR. The discipline is: port faithfully, and where the hardware cannot
do it, write down the gap rather than degrading the game quietly.

This corpus finds two:

- **Persistent storage.** No EEPROM, flash or NVRAM anywhere in `rtl/`. NEMO tracks
  completion across 50 puzzles; PICO-8 gives it `cartdata()`. The port keeps
  progress in RAM, loses it on power-off, and the gap is recorded with what it would
  take to fix — the smallest useful version is probably a handful of bytes behind an
  MMIO window, not a filesystem.
- **Multiply.** Not merely absent but *unavailable in hardware*: `Makefile:5-6`
  records that `-dsp` is disabled because the hx8k has no `SB_MAC16` cells, and
  `sprite_compositor.sv:11` documents the compositor as deliberately built with "no
  tables, no multiplies". Any multiplier is LUT-based. That belongs in the gap entry,
  because it changes `add-math-coprocessor`'s cost from "infer a DSP block" to
  "spend LUTs on a shift-add sequencer", which is a different proposal.

### Decision: no staging

Celeste needed staging because its engine is large and its content is 30 rooms of
level design. NEMO inverts that: the code is a grid, a decoder, a validator and a
menu, and the 50 puzzles are a data-extraction step. Staging would add ceremony
without reducing risk.

## Acceptance gates

| Gate | Statement |
| --- | --- |
| **N1 Runs** | The port plays: puzzle select, cursor movement, fill and mark, clue display, win detection, and progression across puzzles. |
| **N2 Baseline recorded** | Measured on the **pre-slice** ISA and recorded as its own section of `docs/isa-baseline.json`, flagged `frame_bound: false`. |
| **N3 New idioms counted** | Reports counts for non-power-of-two 2D indexing, sequential stream decode, and packed bitfield test/set/clear — the three families absent from the other corpora. |
| **N4 Gaps recorded** | `docs/hardware-gaps.md` gains entries for persistent storage and multiply, each stating what the original does, what the port does instead, and what a fix would cost. |
| **N5 Grouped reporting** | `make metrics` groups plumbing ratios by `frame_bound`, and never compares a frame-bound corpus's ratio directly against a non-frame-bound one. |

N3 is informative either way. If a program with no frame pressure still shows ~33%
plumbing, that is strong evidence the ratio is the ISA's doing and the whole
programme is well aimed. If it shows substantially less, then a meaningful part of
Breakout's figure was frame-budget optimisation, and the slices' projected savings
are overstated — which would be an uncomfortable finding, and exactly the sort the
gates were built to surface.

## Risks / Trade-offs

- ~~**The corpus is probably small**, so it rarely clears G3 alone.~~ **Disproved by
  extraction** (`inventory.md`): 1587 lines, 36119 characters, eight classes in a
  three-level prototype chain with a scene graph and an event bus. The real risk is
  the opposite one — that porting a metatable-based OOP program to 6502 is a larger
  job than a nonogram game sounds like, and that the porter's choice of how to
  represent classes dominates the idiom counts. Mitigation: record the
  representation decision explicitly, as with the `×pz_w` question below.
- **The 7-bit character encoding has no direct 6502 analogue**, so the port
  re-encodes the puzzle bitmaps. That makes the stream-decode idiom partly the
  porter's choice. Mitigation: mirror the cart's scheme as closely as the platform
  allows — 7-bit packing over a 128-entry alphabet is portable as-is — and record any
  divergence in the registry.
- **PICO-8's procedural drawing has no hardware equivalent.** The cart draws rounded
  boxes, dotted lines and drop shadows with `line`/`rect`/`circ`; the console has
  tiles, sprites and a 1bpp overlay. Mitigation: pre-baked tiles plus overlay
  plotting, and a gap entry recording the difference.
- **The porter knows which slices are coming.** Same bias as Celeste, same
  mitigation: pre-extension baseline first, transliterate rather than redesign.
- **Three corpora is a maintenance load.** Every slice now migrates and re-measures
  three programs. Mitigation: this is the last corpus proposed; the registry caps the
  set rather than inviting a fourth, and `docs/corpora.md` states what a fourth would
  have to add that these three do not.
- **A puzzle game may exercise the PPU thinly** — mostly static tiles and text,
  little of the 128-sprite list. So it complements the action carts on the CPU axis
  while telling us less about the PPU. Recorded, not fixed.
- **Attribution now spans two authors.** mooon for the code and puzzle designs,
  Gruber for the music via *Pico-8 Tunes Volume 1*. Mitigation: confirm both before
  starting, and treat the music data as a separate attribution line.

## Open Questions

- **Does the port need the music at all?** Dropping it removes the Gruber
  attribution question and costs nothing on the CPU axis, since the PSG sequencer is
  hardware. But the Breakout port's convention is faithfulness, and the PSG's
  verbatim-upload path makes including it nearly free. Leaning include.
- **How is progress stored, given there is no NVRAM?** RAM-only for now, with the
  gap recorded. Worth deciding whether the port presents the loss to the player (a
  "progress not saved" notice) or silently forgets — the first is more honest about
  the hardware's limits.
- **Row-base table or shift-add for `×15`?** Deliberately not decided here; the
  porter writes whichever is natural and the choice is recorded as evidence.
- **What would a fourth corpus have to add?** If the answer is "nothing these three
  lack", the registry should say so and close the question.
