## Why

`add-celeste-corpus` fixes the single-corpus problem and states the residual one
plainly: *"two PICO-8 action games are still one genre family. Two corpora bound
the single-genre risk; they do not eliminate it."* Both Breakout Hero and Celeste
are 60 fps action games with per-frame entity updates and a frame budget the
programmer is fighting.

That shared property is not cosmetic — it confounds the measurement. The gates
exist to answer whether the ISA is *a better human target*: `add-isa-ergonomic-gates`
is explicit that the goal is "to reduce the amount of machine state a person has to
simulate in their head", **not** to make the CPU faster. But in a program under
frame pressure, a share of the plumbing ratio is hand-optimisation, not
expressiveness. You cannot separate "the programmer wrote it this way because the
ISA forced them" from "the programmer wrote it this way because it had to fit in
the frame".

A corpus with no frame pressure separates them. What is left is what the programmer
wrote for clarity.

### Why NEMO - Puzzle Pack II

[NEMO - Puzzle Pack II](https://www.lexaloffle.com/bbs/?pid=109965) (mooon, 2022)
is a nonogram/picross game: 50 hand-designed puzzles, grids up to 15×15,
string-encoded puzzle data, per-puzzle progress saved across sessions, and a
text-heavy interface of row and column clues. It contributes four idiom families
that neither action game contains:

| System | Shape in 6502 | Calibrates |
| --- | --- | --- |
| Variable-stride grid addressing | `(i-1)*pz_w + j` where `pz_w` is read at **runtime** — a variable × variable multiply | pointers, row-base tables, and the deferred `add-math-coprocessor` |
| Class hierarchy, scene graph, event bus | vtables with a fallback chain, recursive child-list walks, arrays of `{function, context}` pairs | `add-isa-pointer-ops` |
| 7-bit-packed puzzle bitmaps | sequential stream decode: read a character, emit 7 bits, expand into the grid | `add-isa-pointer-ops`, in its purest auto-increment form |
| Clue derivation and validation | nested loops over a 2D grid accumulating run lengths, many per-row temporaries | `add-isa-frame-pointer`, `add-isa-test-and-branch` |
| Per-cell tri-state board (empty / filled / marked) | packed bitfield set, clear and test | `add-isa-test-and-branch`'s `TBZ`/`TBNZ` mask forms |

The grid stride looked like the sharpest of these. Breakout's tilemap is 8-aligned
and Celeste's rooms are 16×16, so both index by shifting. NEMO's 50 puzzles use
widths **7, 9, 10, 11, 12, 13, 14 and 15** — *not one is a power of two* — and the
stride is a runtime variable, so it cannot be strength-reduced at assembly time
either. No puzzle in this corpus is shift-indexable.

**Then the port was written, and the multiply disappeared.** A cell array is at
most 15×15 = 225 bytes, so it fits in one page; page-align it and a row base is a
single byte; build that 15-entry byte table once per puzzle by adding `pz_w`
fifteen times. Every cell access is then one indexed load plus one `(zp),Y`. The
finished port contains exactly one general multiply, called three times per puzzle
load.

So this corpus turned out to be evidence **against** a math coprocessor for array
indexing and **for** cheap pointer setup — the opposite of what this proposal
predicted, and the most useful thing it produced. The prediction and its refutation
are both recorded, in `src/nemo/grid.asm` and `docs/corpora.md`.

### It surfaces two capabilities the console does not have

Checked against the RTL, not assumed:

- **No persistent storage.** Nothing in `rtl/` implements EEPROM, flash or NVRAM.
  NEMO saves progress across 50 puzzles via PICO-8's `cartdata()`; on this console
  that has nowhere to go. The port must record this as a hardware gap rather than
  stub it out quietly — which is the convention `docs/hardware-gaps.md` already
  establishes from the Breakout port.
- **No multiply, and none available.** The compositor is deliberately built with
  "no tables, no multiplies" (`sprite_compositor.sv:11`), and the Makefile records
  that `-dsp` is disabled because **the hx8k has no `SB_MAC16` cells at all**
  (`Makefile:5-6`). So `add-math-coprocessor`, when it is written, is a LUT-based
  multiplier — not a free DSP block. That materially changes its cost estimate,
  and this corpus is what makes the demand for it measurable.

## What Changes

- **A third corpus**: a hand-written 6502 port of NEMO - Puzzle Pack II under
  `src/`, registered in `docs/corpora.md` and scored by the existing per-corpus
  gate machinery.
- **The corpus set gains a frame-budget-independent member.** The corpus registry
  SHALL record, per corpus, whether it is bound by the frame budget, and gate
  reports SHALL distinguish plumbing measured under frame pressure from plumbing
  measured without it. This is the point of adding it.
- **Gaps found while porting are recorded, never silently stubbed.** When a corpus
  needs a capability the console lacks, the port records it in
  `docs/hardware-gaps.md` with what the original did and what the port does
  instead. Persistent save and multiply are the two this corpus finds.
- **Scope is the whole game, because the whole game is small.** Unlike Celeste,
  NEMO does not need staging: the bulk of the cart is puzzle data, and the code is
  a grid, a decoder, a validator and a menu. The 50 puzzles are data extraction,
  not 50 units of work.
- **G8 gets no useful signal from this corpus, and that is recorded.** There is no
  meaningful frame-work window in a puzzle game that idles waiting for input. The
  registry states which gates each corpus can and cannot inform, so a missing G8
  number is a declared property rather than an omission.
- **Attribution involves a third party.** The cart's music is from Gruber's
  *Pico-8 Tunes Volume 1*, so the posture covers mooon (code and puzzle designs)
  **and** Gruber (music), on top of the original-implementation convention from
  `src/main.asm:5-7`. Confirmed before the port starts.

Not in scope: adding persistent storage or a multiplier to the console — both are
findings this change records, and each needs its own proposal. Making NEMO gate any
ISA slice: unlike `add-celeste-corpus`, this corpus adds calibration *breadth*, not
missing evidence for a specific slice, so it blocks nothing.

## Impact

- Affected specs: `cpu-isa` (adds frame-budget classification and gap reporting to
  the corpus contract)
- Affected code: `src/nemo/*.asm` (new), `src/nemo_data.asm` (new, extracted puzzle
  and music data), `docs/corpora.md` (third entry), `docs/hardware-gaps.md` (two
  new gaps), `docs/isa-baseline.json` (third per-corpus section),
  `tools/isa_metrics.py` (frame-budget flag per corpus), `Makefile`
- Depends on: `add-celeste-corpus` for the multi-corpus machinery — the registry,
  per-corpus scoring, and the pre-extension baseline requirement. This change adds
  a corpus, not a mechanism.
- Feeds: the deferred `add-math-coprocessor` proposal, which currently has no
  measured demand. This corpus is where that demand becomes countable, and it also
  establishes that the multiplier must be LUT-based on hx8k.
- Blocks nothing. Recommended after `add-celeste-corpus` and before the corpus set
  is used to justify `add-math-coprocessor` or any persistent-storage work.
- **Corrected after extraction** (`inventory.md`): this proposal originally guessed
  the code volume was "likely modest". It is not — 1587 lines and 36119 characters
  of Lua, with eight classes in a three-level prototype chain, a retained scene
  graph and an event bus. On the indirection axis it is the **most** demanding of
  the three corpora, Celeste included, so it may well carry G3 thresholds rather
  than merely supplementing them.
- **Honest limitations** that survive: the port must reproduce PICO-8's procedural
  drawing (rounded boxes, dotted lines) with tiles and the 1bpp overlay, since the
  console has no line or circle primitive — a difference worth its own gap entry.
  And the 7-bit character encoding has no direct 6502 analogue, so the port's
  re-encoding is partly the porter's choice rather than the original's, the same
  bias class flagged for Celeste.
