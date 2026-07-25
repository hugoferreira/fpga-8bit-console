## Context

`add-isa-ergonomic-gates` computes ergonomics over `src/main.asm`: 1919
instructions, 32.8% plumbing, and a set of idiom counts that decide which
instructions get opcode slots. Its own risk section flags that one corpus is a
weak basis, and its worked example (rejecting `DBNZ` on 5 sites) shows the gates
have teeth — which is exactly why the input matters. A gate that can reject an
instruction on evidence can also *accept* one on evidence that only holds for one
genre.

Three slices are already visibly constrained by this. Word-ops has zero literal
16-bit chains to count. Pointer-ops states outright that G3 is not satisfied.
Frame-pointer states that it cannot be satisfied, and is sequenced last so it can
be abandoned. Those are not three independent problems; they are one program's
shape showing through three times.

## Goals / Non-Goals

**Goals**

- A second corpus whose idioms are genuinely different from Breakout Hero's.
- Per-corpus gate scoring, so a single-program justification is visible as such.
- A pre-slice baseline for the new corpus, without which it calibrates nothing.
- Honest reporting when an instruction pays off in one program and not the other.

**Non-Goals**

- Replacing Breakout Hero as the reference corpus. Existing baselines stay valid.
- A complete, content-finished Celeste port. Stage 2 is optional and the
  calibration does not wait for it.
- Any ISA change. This change adds a measurement subject only.
- A synthetic benchmark. Considered and rejected below.

## Decisions

### Decision: a real port, not a synthetic benchmark

The open question offered both. A synthetic benchmark exercising pointers and
16-bit math would be cheaper and would produce the counts on demand — which is
precisely why it is worthless here. The gates measure *what a human writing a game
actually does*, and a benchmark written to justify an instruction will contain the
idiom that instruction replaces. It is the purest form of gaming the metric, and
`add-isa-ergonomic-gates` already lists metric-gaming as a risk.

A real port has the property that matters: the programmer is trying to make a game
work, and the idiom counts are a side effect.

### Decision: Celeste Classic, and why not a smaller cart

The open question suggested "a smaller cart". Smaller is the wrong axis — a small
cart is likely to be *simpler*, and simpler means fewer of the structures that are
missing. What is needed is a program that is **structurally different and
structurally demanding**, and Celeste is both: an object system with per-type
dispatch, sub-pixel physics with per-object accumulators, and enough per-object
state that globals-as-locals stops working.

Alternatives considered:

- **A smaller/simpler cart.** Cheap, but likely to reproduce Breakout's shape:
  flat state, integer positions, leaf routines. Would cost real work and calibrate
  nothing.
- **A non-game program** (a monitor, a text tool). Would exercise pointers heavily
  and 16-bit math lightly, and would not exercise the frame budget at all, so G8
  gets no signal. Useful as a *third* corpus, not a second. **Taken up by
  `add-nemo-corpus`**, which chose a puzzle game over a utility: the axis that
  matters turned out to be frame pressure rather than genre, and a utility would
  exercise none of the PPU while being a benchmark in disguise.
- **A cart with a different genre but comparable size** — an RPG or a shmup.
  Reasonable, and the argument for Celeste over these is evidence quality: at
  8186/8192 tokens it is known to be resource-saturated, so its structures are the
  ones a programmer reaches for under pressure rather than the ones they reach for
  when there is slack.

The honest caveat: two PICO-8 action games are still two PICO-8 action games. Two
corpora bound the single-genre risk; they do not eliminate it.

### Decision: gates are scored per corpus, never pooled

Pooling the counts would let a large corpus carry a threshold that a small one
fails, and would hide the interesting case entirely. The rule:

- **G3 (idiom frequency):** threshold met in **at least one** corpus. Report the
  count for every corpus. An instruction that clears ≥8 in Celeste and scores 2 in
  Breakout is *acceptable* — that is what a second corpus is for — but the
  asymmetry is recorded in the opcode registry alongside the claim.
- **G5 (corpus reduction) and G6 (plumbing ratio):** must not regress in **any**
  corpus. A slice that improves one program and worsens another has not earned its
  slot.
- **G8 (frame-work cycles):** measured per corpus that runs, since each has its own
  frame budget and input replay.

Because G3's threshold is an absolute count (≥8) rather than a ratio, a larger
corpus satisfies it more easily. Per-corpus reporting is what keeps that visible;
pooling would launder it.

### Decision: stage the port, and put the calibration value in stage 1

| Stage | Contents | Purpose |
| --- | --- | --- |
| 1 | Player entity; collision (`is_solid`, `tile_flag_at`); the object list and its per-type dispatch; `move()` with sub-pixel remainders; room transitions; camera. Three rooms with differing tile flags. | **All calibration value.** Every idiom in the table above appears here. |
| 2 | Remaining rooms, strawberries, balloons, springs, fake walls, snow, the ending. | Content. Adds data and a little dispatch breadth; no new idioms. |

Stage 1 is the deliverable this change is gated on. Stage 2 is explicitly optional
and can be abandoned without affecting the gates — which matters, because a full
Celeste port is comparable in size to the Breakout port and should not be able to
block slice 5 indefinitely.

The risk of stopping at stage 1 is that idiom counts from a partial program
understate the whole. Mitigation: report the corpus's instruction total alongside
every count, and state in `docs/corpora.md` which systems are present, so a count
of 14 is never mistaken for a count from a finished game.

### Decision: vertical camera follow resolves 128 vs 120

The console displays 160×120 (`hvsync_generator.sv:6-11`, halved from 320×240 by
`scalescreen`). PICO-8 is 128×128. Horizontally there are 32 columns spare, which
is where Breakout puts its HUD and where this port puts its strawberry count.
Vertically the port is 8 lines short of a Celeste room.

Options weighed:

1. **Crop 8 lines.** Cheapest, and wrong: in a precision platformer the bottom
   half-tile row carries floors, spikes and room-transition boundaries.
2. **Camera Y follow** (chosen). The compositor's world is 256×128 with a 7-bit
   camera Y at `$4004`, so 8 lines of vertical travel are already available at zero
   cost. The camera tracks the player within that 8-pixel band.
3. **Squash vertically.** Breaks the 8×8 tile grid and the sprite sheet.
4. **Change the video timing to 128 lines.** Touches `hvsync_generator`,
   `scalescreen`, the LCD driver and the compositor's line budget, for one program.
   Rejected as disproportionate — though worth noting it is the only option that is
   fully faithful, and if a *third* PICO-8 port arrives the calculus changes.

Option 2 is a real, visible divergence from the original: Celeste's camera is
static per room. It goes in the port's header comment next to the attribution, the
way `src/main.asm` documents its own divergences.

### Decision: attribution follows the Breakout convention

`src/main.asm:5-7` establishes it: *"Original game (c) Krystman / Lazy Devs
Academy… this 6502 game code is an original implementation written for this
hardware. Level layouts and paddle/ball art come from the cart."* The same posture
applies — original 6502 implementation of the game logic, cart art/map/SFX data
extracted and used with attribution to Maddy Thorson and Noel Berry.

This is confirmed before the port starts rather than after it is written. A PICO-8
BBS cart being source-visible by design is not the same thing as a license grant,
and the project should be as careful with the second port as it was with the first.

## Acceptance gates

| Gate | Statement |
| --- | --- |
| **C1 Runs** | Stage 1 runs on the console at 60 fps: player moves, dashes, collides, dies, and rooms transition. |
| **C2 Baseline recorded** | The corpus is measured on the **pre-slice** ISA and recorded as its own section of `docs/isa-baseline.json`, with its instruction total and its plumbing ratio. |
| **C3 Idioms present** | The corpus supplies literal pattern counts for the three weak slices: 16-bit add chains (word-ops), indirect dispatch and struct walks (pointer-ops), and per-routine local counts (frame-pointer). Each count is reported even if it is low. |
| **C4 Per-corpus scoring** | `make metrics` reports every gate per corpus and a combined verdict, and fails if any corpus regresses on G5 or G6. |
| **C5 Documented** | `docs/corpora.md` states, per corpus, what it is, which systems it implements, what it is good and bad at measuring, and which divergences from the original it carries. |

C3 is the one that can fail informatively. If Celeste's ported engine *also* shows
no 16-bit add chains, that is a genuine finding about hand-written 6502 rather than
about Breakout — and `add-isa-word-ops` would need to be re-argued rather than
re-measured.

## Risks / Trade-offs

- **A full Celeste port is a large piece of work**, comparable to the Breakout
  port. Mitigation: staging, with all calibration value in stage 1 and stage 2
  explicitly abandonable.
- **Two PICO-8 action games are still one genre family.** Mitigation: state it in
  `docs/corpora.md`, and note that a non-game third corpus would cover different
  ground (heavy pointers, no frame budget).
- **The port is written by someone who knows the ISA slices are coming**, which is
  a subtle way to bias the corpus toward the idioms the slices target. Mitigation:
  measure the baseline (C2) before any slice lands, and prefer transliterating the
  original's structure over inventing a 6502-idiomatic redesign.
- **Corpus size is unknown until ported**, and G3's threshold is an absolute count,
  so a bigger corpus clears it more easily. Mitigation: per-corpus reporting plus
  the instruction total next to every count; never pool.
- **Stage 1 counts understate a finished game.** Mitigation: `docs/corpora.md`
  records which systems are present; counts are always reported with the total.
- **Camera-Y follow changes how the game feels** in a game whose feel is the point.
  Mitigation: documented divergence, and the 8-pixel band is small enough that the
  camera is nearly static in practice.
- **Slices landing before this corpus exists** are calibrated against one program
  and will need re-scoring. Mitigation: land before slice 5; if a slice lands
  first, its `design.md` records that its G3 count is single-corpus.

## Open Questions

- **Stage 1 room selection.** Three rooms exercising different tile flags — which
  three? The first room is obvious; the other two should be chosen for tile-flag
  and object variety rather than for progression order.
- **Does the object dispatch use a jump table or a chain of comparisons?** The
  first is the pointer-heavy idiom that calibrates slice 6; the second is what a
  6502 programmer might naturally write given how expensive pointers currently are.
  Writing whichever is natural is the honest choice, and the answer is itself
  evidence about the ISA — so it should be recorded, not decided in advance.
- ~~**Is a non-game third corpus worth planning now?** It would cover the one axis
  two action games share.~~ **Resolved** by `add-nemo-corpus`: a nonogram game, on
  the grounds that the confounding axis is frame pressure rather than genre — under
  a frame budget, part of the measured plumbing is hand-optimisation rather than
  the ISA's doing.
