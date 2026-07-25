# The assembler: ca65 → customasm

The console's software (`src/main.asm` and friends) is assembled by
[customasm](https://github.com/hlorenzi/customasm), not `ca65`/`ld65`. See
`openspec/changes/add-custom-assembler/` for the full proposal; this document
is gate A1 (coverage) plus the quirks that surfaced doing the migration.

`nemo` and `celeste` still build with `ca65`/`ld65` — they are unmigrated ISA
corpora whose Python test tooling (`tools/test_nemo.py`, `tools/isa_metrics.py`)
reads ca65's `.lbl` label format. `GAME_ASM` in the `Makefile` selects the
toolchain per game.

## Building

```
make asm GAME=breakout      # rtl/ram.hex, build/breakout.bin, build/breakout.sym
make asm-ca65 GAME=nemo     # deprecated ca65/ld65 bridge, for unmigrated games
```

One `customasm` invocation with three output groups replaces the
`ca65` → `ld65` → `hexdump` pipeline and its `src/memory.cfg` linker script:

```
customasm src/main.asm -t 10 --color=off \
  -f binary  -o build/breakout.bin -- \
  -f symbols -o build/breakout.sym -- \
  -f readmemh,width:8 -o rtl/ram.hex
```

`readmemh`, not customasm's own `hexdump` format — the latter emits an
address column and an ASCII sidebar that `$readmemh` would parse as data.

## src/isa/ layering

| File | Contents |
| --- | --- |
| `src/isa/nmos6502.asm` | `#ruledef` for all 151 documented NMOS opcodes (vendored from customasm's own `std/cpu/6502.asm`, Apache-2.0) plus two small additions the ca65-authored corpus needed (see below) |
| `src/isa/memmap.asm` | `#bankdef`s for zero page, stack, RAM and the vector table, replacing `src/memory.cfg` |
| `src/isa/console.asm` | PPU/PSG/gamepad register constants and the game's zero-page variable layout, extracted from the top of `main.asm` |

A future ISA slice adds its own `src/isa/ext_*.asm` with a `#ruledef` for its
new mnemonics, `#include`d only when its hardware is present — a build
without the file simply cannot assemble that slice's mnemonics.

### This project's additions to the stdlib ruledef

customasm's own 6502 ruledef requires the accumulator addressing mode to be
written out (`asl a`), and has no immediate-lo/hi-byte shorthand. The ca65
corpus uses both idioms, so `nmos6502.asm` adds two small supplementary
`#ruledef`s: `cpu6502_accum_shorthand` (bare `asl`/`lsr`/`rol`/`ror`, no `a`)
and `cpu6502_immediate_lohi` (`lda #<label` / `lda #>label`, matching the
handful of mnemonics — `lda`/`ldx`/`ldy`/`adc` — the corpus actually uses this
way). Everything else is the unmodified stdlib.

## ca65 → customasm syntax map (gate A1)

| ca65 | customasm | Notes |
| --- | --- | --- |
| `.define NAME v` | `NAME = v` | direct substitution, 141 sites |
| `.byte a, b, c` | `#d8 a, b, c` | fixed 8-bit width |
| `.byte "STR"` | `#d "STR"` | `#d8` rejects a string (wrong bit width for the whole literal); bare `#d` splits it into one byte per character |
| `.word v` | two `#d8` bytes, `v[7:0], v[15:8]` | customasm's `#d16` is **big-endian**; the 6502 vector table needs little-endian, so words are written as explicit byte pairs rather than via `#d16` |
| `.include "f.asm"` | `#include "f.asm"` | same quoting |
| `.segment "CODE"` | `#bank ram` / `#addr 0x0300` | see `src/isa/memmap.asm` |
| `.segment "VECTORS"` | `#bank vec` | |
| `<label`, `>label` (in a `.byte` list) | `label[7:0]`, `label[15:8]` | `<`/`>` are customasm comparison operators outside of an instruction pattern, so they only work as literal tokens inside a `#ruledef` (see `lda #<label` below), not inside a `#d8` expression list |
| `<(expr)`, `>(expr)` | `(expr)[7:0]`, `(expr)[15:8]` | same rule, parenthesised expression |
| `lda #<label`, `lda #>label` | unchanged | matched directly by `cpu6502_immediate_lohi` (see above) — not rewritten |
| `@local` (ca65 cheap local label) | `.local` | customasm's `.name` sub-labels reset scope at the next non-dot label, the same rule ca65 uses for `@name`; **not** supported as `@name` at all |
| `$4000` (hex literal) | unchanged | customasm still accepts `$hex` digit-string literals; `$` on its own (no digits following) is the current-address symbol, so this needed no rewriting |

## The one whitespace quirk

`lda addr,x` (no space after the comma) fails to match with
"no match found for instruction"; `lda addr, x` (space after the comma)
works. This is a real behaviour of customasm v0.14.1's instruction matcher,
confirmed in isolation with both label and literal operands. The migration
script normalizes every `,` in the corpus to `, ` to sidestep it.

## Testing the ruledef itself

`python3 tools/test_isa_ruledef.py` assembles one instruction per addressing
mode (plus this project's accumulator-shorthand and immediate-lo/hi
additions) and checks the emitted bytes against a hand-computed table — a
fast, corpus-independent regression guard for `src/isa/nmos6502.asm`.

## Gates

| Gate | Status |
| --- | --- |
| A1 Coverage | This table. |
| A2 Byte identity | `customasm` output for the migrated corpus is byte-identical to the pre-migration `ca65`/`ld65` output (`cmp`-verified during migration; ca65 can no longer parse the migrated corpus, which is the intended one-way cutover). |
| A3 One command | See "Building" above — one `customasm` invocation, no intermediate object file. |
| A4 Build time | Whole-corpus assembly resolves in 3 fixed-point iterations and completes in well under 1 second. |
| A5 Diagnostics | Branch-out-of-range produces an error naming the source line and the failing assertion (verified). The base NMOS ISA has no zero-page-only mnemonic with no absolute fallback, so that half of the gate has no case to exercise yet — it applies once an ISA extension slice adds one. |
| A6 Symbols | `sim/console.cpp` loads a `-f symbols` file via `--sym <path>` and resolves an address to the nearest preceding label plus offset via `--resolve <addr>` (`make run`/`make shot` pass `--sym` automatically when `build/<game>.sym` exists). No CPU program-counter signal is currently exposed through `Vtop`'s top-level ports, so this is a standalone diagnostic today rather than a live per-instruction trace; wiring it to a real trace needs a debug PC port surfaced through `top.sv`, which is out of scope here. |

## Prerequisites

`cargo install customasm --version 0.14.1` (pinned; the `Makefile`'s `hex`
target checks the installed version before assembling and fails readably,
naming both versions and the install command, if it doesn't match).
`cc65` is only needed for `nemo`/`celeste` (`make asm-ca65`), not for
building the console's own primary software.
