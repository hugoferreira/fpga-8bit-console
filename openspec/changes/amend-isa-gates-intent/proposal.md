## Why

**The gates measure the corpus against itself.**

G3 requires a new instruction to replace a sequence occurring **≥ 8 times** in
`src/main.asm`. But `src/main.asm` was written by a person working around the
6502. An idiom the 6502 makes expensive does not appear in it — not because the
program does not want it, but because the author routed around it. Counting
occurrences measures *what the 6502 made cheap enough to write*, not what the
program means.

That is not a hypothetical. Measured on the corpus:

| Evidence | Count |
| --- | --- |
| Textbook 16-bit add chains (`clc`/`lda`/`adc`) | **0** |
| Operands naming the high half of a 16-bit value (`foo+1`) | **119** |
| Adjacent `lda`→`sta` pairs — data forced through `A` | **232 (24% of instructions)** |
| Up-counters (`inx`/`iny`/`inc`) vs down-counters | **59 vs 29** |

An idiom counter sees **zero** 16-bit arithmetic in a program that is full of
it, because the author hand-scheduled it into whatever registers were free.
`DBNZ` was rejected on exactly this basis — "this program counts *upward*" —
which is the signature of avoidance, not of absence of need.

The same program expressed twice makes it plainer. Celeste exists here as
PICO-8 Lua (the port's source of truth, predating every 6502 decision) and as a
6502 port:

| | |
| --- | --- |
| Lua: assignments as a share of semantic operations | 554 / 2464 = **22%** |
| 6502 port: `lda`+`sta` as a share of instructions | 1151 / 2707 = **43%** |
| 6502 port: plus `ldy`/`ldx` index setup | **53% of the program moves bytes** |

### The falsification test

If the gates were sound, they would predict that replacing the CPU with a
substantially better-matched ISA — 16-bit registers, base+index+displacement
addressing, block move — would show little gain, because the idioms those
features target "do not occur ≥ 8 times". That prediction is obviously wrong.
The gates cannot see the win because the corpus was written to avoid needing it.

A metric that cannot distinguish "this program does not need X" from "this
program was written to avoid X" cannot be used to reject X.

## What Changes

- **G3 stops being able to reject an instruction on its own.** Idiom frequency
  remains as supporting evidence and as an anti-gaming check — it is good at
  catching an instruction added for its own sake — but a low count is no longer
  sufficient grounds for rejection.
- **Rewrite-measured evidence becomes the primary method**, not the escape
  hatch it is today. A slice names routines, re-expresses them for the proposed
  ISA, and reports both measurements.
- **An intent oracle, where one exists.** Breakout, nemo and celeste are ports;
  the original PICO-8 Lua states what each program means, free of any 6502
  decision. `tools/p8_unpack.py` already extracts it. New measure:
  `expansion = instructions / semantic operations`, which the ISA's job is to
  reduce and which no amount of 6502 idiom is able to flatter.
- **A new gate, G9 — anti-circularity.** Any instruction rejected on idiom
  frequency must state what the corpus does *instead*, and argue that the
  alternative is a genuine preference rather than an avoidance. `DBNZ`'s
  rejection does not currently pass this and should be re-heard.

## Impact

- **Slices 4-7 should be re-argued on intent**, not re-scored on idioms. The
  conclusion that they "lose headroom" because `refactor-cpu-core` made
  `jsr`/`rts` and `pha`/`pla` cheaper is itself an artefact of measuring against
  the encoding: a cheaper workaround is not the same as a workaround that is no
  longer needed.
- **Slice 3 is unaffected either way.** Its case — 232 `lda`→`sta` pairs, 24% of
  the program — is not an idiom the author chose; it is the absence of a
  mem-to-mem move showing up as instructions. Intent-based measurement makes
  that case stronger, not weaker.
- **This changes a shared metric.** `plumbing` and the G-series are used by all
  three corpora and every recorded baseline. Per the standing agreement in
  `docs/agent-coordination.md`, this is proposed rather than applied, and needs
  all three corpora re-measured in one commit if adopted.
- **Risk: intent counting is soft.** Semantic operations in Lua are not a
  hard unit, and the counting above is crude. It is a denominator for comparing
  two encodings of the *same* program, not an absolute. It must never become a
  target on its own — hence rewrite measurement stays primary.
