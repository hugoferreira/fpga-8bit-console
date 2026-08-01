## Context

The console runs Arlet Ottens' 6502 (`rtl/cpu6502_arlet.sv`, ~1240 lines): a
state-machine core with `casex(IR)` decode over a shared 8-bit ALU, one memory
access per cycle. The game is hand-written assembly (`src/main.asm`, 2614 lines)
built with `ca65`/`ld65`.

The goal of the ISA work is **not** to make the CPU a better compiler target. It
is to make it a better *human* target: to reduce the amount of machine state a
person has to simulate in their head while reading and writing a line of code.
That is a different objective function, and it needs its own measurements.

## Goals / Non-Goals

**Goals**

- A definition of "more ergonomic" that is computed, not argued.
- A per-slice pass/fail gate, checkable in CI, that can *reject* an instruction.
- One authoritative opcode map shared by all slices.
- Absolute binary compatibility with the NMOS 6502 subset in use today.

**Non-Goals**

- Adding general-purpose registers (`R0`–`R7`). It makes this a different CPU,
  invalidates every 6502 instinct and all existing tooling, and does not fix the
  actual problem — see "Why not more registers".
- Being a good C target. `cc65` must keep working, but codegen quality for C is
  explicitly not a gate.
- Arithmetic that belongs in a peripheral. Multiply, divide, `sqrt` and `atan2`
  are cheaper and simpler as MMIO next to the existing LFSR at `$400F`: they
  cost a few `sta`/`lda` cycles but zero decode complexity and zero assembler
  work. Deferred to a separate `add-math-coprocessor` proposal.
  **Update: the expected demand has not materialised.** `add-nemo-corpus` looked
  like the case that would prove it — a nonogram whose grid stride is a runtime
  variable across eight widths, none a power of two, so neither shiftable nor
  strength-reducible. Written idiomatically the multiply disappeared: a cell array
  fits in a page, so page-align it and a row base is a single byte, built once per
  puzzle by repeated addition; every access is then one indexed load and one
  `(zp),Y`. The finished port contains one general multiply, called three times
  per puzzle load. The target device also has no `SB_MAC16` cells, so any
  multiplier would be a LUT-based shift-add sequencer rather than an inferred DSP
  block. See `docs/corpora.md` and `docs/hardware-gaps.md`; revisit only if a
  corpus turns up a multiply in an inner loop.

## Why not more registers

The measured problem is not "too few places to put values". It is that **`A` is
a mandatory toll booth** (24% of instructions) and that **instructions have
preconditions** (5% ceremony). Adding `R0`–`R7` addresses neither directly: you
still write `mov r0, thing` twice as often as you write arithmetic, and you have
added eight new things to track. `MOV mem, mem` removes the toll booth without
adding any state. Purity rule P2 (an instruction may not clobber `A`/`X`/`Y`
unless that is its result) is what actually relieves register pressure, because
it means adding an instruction never costs you a live value.

## The gates

Scored by `tools/isa_metrics.py` against `docs/isa-baseline.json`.

| Gate | Statement | Check |
| --- | --- | --- |
| **G1 Purity** | Every added instruction satisfies P1–P3. | Spec review; each instruction's delta states preconditions (must be "none") and clobber set. |
| **G2 Encoding** | Every added instruction is registered in `docs/opcodes.md`, claims no reserved slot, and no slot is claimed twice. | `isa_metrics.py --check-registry` |
| **G3 Idiom frequency** | Each added instruction replaces a sequence occurring **≥ 8 times** in the corpus, *or* carries a written rewrite-based justification when the idiom is diffuse rather than literal (see "Rewrite-measured evidence"). | Pattern count in the report; diffuse cases need an explicit `justification` field. |
| **G4 Strict improvement** | Each added instruction is **≤** its replaced sequence in bytes **and** in cycles, and strictly smaller in at least one. | Per-instruction table in the slice's `design.md`, confirmed by the cycle-accurate testbench. |
| **G5 Corpus reduction** | After migrating `src/main.asm`, static instruction count falls by at least the slice's declared target and `build/main.bin` does not grow. | `make metrics` |
| **G6 Plumbing ratio** | `plumbing = (toll + ceremony + transfers + spills) / instructions` is non-increasing for every slice, reaching **≤ 15%** once slice 3 lands and **≤ 12%** once slices 4–5 land (from 32.8%). | `make metrics` |
| **G7 Compatibility** | Klaus Dormann's `6502_functional_test` passes on the extended core, and a build with extensions unused is byte-identical to the pre-slice build. | `make test`, `cmp` |
| **G8 No cycle regression** | Frame-work cycles (cycles from leaving the `main_loop` `SPR_FRAME` spin to re-entering it) do not increase on a fixed input replay. | `make metrics` (sim `--metrics`) |

### Metric definitions

Over the instruction stream of `src/main.asm`:

- `toll` = 2 × (count of adjacent `lda`→`sta` pairs) = **464** at baseline
- `ceremony` = count of `clc`,`sec`,`cld`,`sed`,`sei`,`cli`,`clv` = **95**
- `transfers` = `tax`,`txa`,`tay`,`tya`,`tsx`,`txs` = **47**
- `spills` = `pha`,`pla`,`php`,`plp` = **28**
- `instructions` = **1928**; `plumbing` = **32.9%**

These are corrected from the 1919/460/32.8% first published here. The nine
missing instructions all share a line with a ca65 local label (`@wf: cmp
SPR_FRAME` and eight others), which the original parser's label pattern did not
admit; two of them are the `sta` half of an `lda`/`sta` pair, hence 464 rather
than 460. See `docs/corpora.md`. The correction does not change any slice's
targets materially, but the gate's own numbers should be right.

`toll` deliberately counts only *adjacent* pairs — it is a conservative
under-count of data movement through `A`, which is the point: the gate should be
hard to game.

### Rewrite-measured evidence (G3 escape hatch)

Some wins are real but not visible as a literal instruction pattern. The corpus
contains **zero** textbook 16-bit add chains (`clc/lda/adc/sta/lda/adc/sta`) yet
**122** operands referencing the high half of a pair (`foo+1`) — the 16-bit work
is there, just hand-scheduled into whatever registers were free. For such cases
G3 is satisfied by rewriting one named routine both ways and reporting both
measurements, rather than by a pattern count. The slice must name the routine in
its `tasks.md`.

### Worked example: the gates rejecting an instruction

`DBNZ zp, rel` (decrement memory, branch if non-zero) was in the first sketch of
slice 1. It is a classic ergonomic instruction, it satisfies P1–P3, and it is
strictly better than what it replaces (3 bytes/6 cycles vs 4 bytes/8 cycles).

It still fails, on **G3**: the corpus contains 3 `dec`→`bne` and 2
`dex`/`dey`→`bne` sites. Five. This program counts *upward* (`inx` … `cpx #n` …
`bne`, 24 `inx` sites). `DBNZ` would be an opcode slot spent on an idiom this
codebase does not use.

That is the gate working. `DBNZ` is not rejected forever — it is rejected until
a corpus asks for it.

## Opcode allocation policy

The NMOS 6502 leaves 105 of 256 slots undefined. They are not all equally free:
the WDC 65C02 and Rockwell R65C02 define many of them, and those definitions are
ones we may want to *adopt* later (`BRA`, `STZ`, `PHX`/`PHY`, `(zp)`,
`SMB`/`RMB`/`BBR`/`BBS`, `TRB`/`TSB`). Reusing them would burn that option.

**Reserved — never allocated to a new instruction:**

- Every opcode defined by the WDC 65C02, including `$x7`/`$xF` (Rockwell
  bit ops), `$04`/`$0C`/`$14`/`$1C`, `$12`-column `(zp)` modes, `$1A`/`$3A`,
  `$5A`/`$7A`/`$DA`/`$FA`, `$64`/`$74`/`$9C`/`$9E`, `$80`, `$89`, `$3C`, `$7C`.
- All 151 NMOS-defined opcodes.

**Extension space:**

| Space | Slots | Assigned to |
| --- | --- | --- |
| Column `$x3` low half (`$03`–`$73`) | 8 | `add-isa-core-ergonomics` |
| Column `$x3` high half (`$83`–`$F3`) | 8 | `add-isa-word-ops` |
| Column `$xB` low half (`$0B`–`$7B`) | 8 | `add-isa-test-and-branch` |
| Column `$xB` high half (`$8B`–`$FB`) | 8 | `add-isa-pointer-ops` |
| Prefix `$02` + second page | 256 | `add-isa-frame-pointer`, overflow, future |

Columns `$x3` and `$xB` are undefined on NMOS and are 1-byte/1-cycle NOPs on the
WDC 65C02 — no functional 65C02 opcode is lost by taking them. `$02` is a JAM on
NMOS and a 2-byte NOP on the 65C02; as a prefix it costs 1 byte and 1 cycle and
buys unlimited headroom for cold instructions.

`docs/opcodes.md` is the registry and the arbiter. A slice that needs a slot
edits the registry in the same commit that adds the decode.

## Roadmap

Ordered by measured value, each independently shippable:

| # | Change | Targets | Corpus evidence |
| --- | --- | --- | --- |
| 1 | `add-isa-ergonomic-gates` | measurement, policy | — |
| 2 | `add-custom-assembler` | ability to emit new opcodes at all | 5 directives in use; migration is mechanical |
| 3 | `add-isa-core-ergonomics` | the toll booth + ceremony | 172 immediate stores, 58 memory moves, 70 `clc`→`adc` |
| 4 | `add-isa-test-and-branch` | branch idioms + range anxiety | 30 `lda/cmp/branch`, 46 `lda/branch`, 16 `lda/and/branch` |
| 5 | `add-isa-word-ops` | 16-bit values | 122 `+1` half-pair operands |
| 6 | `add-isa-pointer-ops` | pointer walks, table copies | 16 `(zp),y`, 41 `ldy` |
| 7 | `add-isa-frame-pointer` | zero-page as a global namespace | 141 `.define`s in one flat map |

## Risks / Trade-offs

- **Gates measure one corpus.** Breakout is the only substantial program on this
  console; an ISA tuned to it may be tuned to one game's habits. Mitigation: G3
  thresholds are deliberately low-precision (≥8), gates are non-regression
  rather than optimisation targets, and a second corpus is added by
  `add-celeste-corpus` — a port of Celeste Classic, whose object dispatch,
  sub-pixel physics and per-object locals supply exactly the evidence slices 5–7
  cannot get from Breakout. It should land **before slice 5**, not slice 6:
  word-ops is the first slice whose G3 it converts from a rewrite argument into a
  pattern count. Gates G3, G5, G6 and G8 become per-corpus, and idiom counts are
  never pooled.
- **Metrics can be gamed** by rewriting the corpus to use new instructions in
  places where the old code was already fine. Mitigation: G8 (cycles) and G5
  (bytes) bound this from the other side.
- **Cycle budgets in slice designs are estimates** against Arlet's one-access-
  per-cycle model until the decode is actually written. G4 is only satisfied by
  measured cycles from the testbench, not by the estimate.
- **`isa_metrics.py` parses assembly with regexes**, so it will drift if the
  source style changes. Mitigation: it reports the instruction total, which is
  cross-checked against the disassembled `build/main.bin` size; a mismatch of
  more than 2% fails the run.

## Open Questions

- Should G6's 18% target be a hard gate or a tracked indicator? Proposed: hard
  gate on non-increase, tracked indicator on the 18% end state.
- ~~Second corpus for gate calibration: port a smaller cart, or write a synthetic
  benchmark exercising pointers and 16-bit math?~~ **Resolved** by
  `add-celeste-corpus`: a real port, not a benchmark (a benchmark written to
  justify an instruction contains the idiom that instruction replaces), and
  Celeste Classic rather than a *smaller* cart (smaller tends to mean simpler,
  which reproduces Breakout's shape instead of complementing it).
- Is a non-game third corpus worth planning? It would cover the axis two PICO-8
  action games share. Deferred in `add-celeste-corpus`, not dismissed.
