## Why

Every ISA extension slice is blocked on one thing: `ca65` cannot emit an opcode
it does not know about. Its instruction table is compiled into the binary, so
new instructions can only be expressed as `.byte` blobs — which defeats the
entire point, since the ergonomic win of `mov ballx, #0` over `lda #0` / `sta
ballx` evaporates if you have to write it as `.byte $03, $30, $00`.

The toolchain also carries costs that have nothing to do with the ISA work:
`ca65` → `ld65` → `hexdump` is a three-stage pipeline with an intermediate
object file and a linker config for a program that has exactly one output; and
"branch out of range" is a hand-editing chore the assembler could solve.

The migration surface turns out to be very small. The entire corpus
(`src/main.asm`, `src/breakout_data.asm`, `src/breakout_sfx.asm`,
`src/breakout_tables.asm`) uses **five** `ca65` directives:

| Directive | Uses |
| --- | --- |
| `.byte` | 480 |
| `.define` | 141 |
| `.word` | 3 |
| `.include` | 3 |
| `.segment` | 2 |

No macros, no `.proc`, no `.struct`, no relocatable segments, no libraries. The
project is not using `ca65` for anything that is hard to replace.

## What Changes

- **Adopt [customasm](https://github.com/hlorenzi/customasm)** as the console's
  assembler. It is a Rust tool (`cargo install customasm`) whose instruction set
  is *data*: `#ruledef` blocks map source syntax to bit patterns, so adding an
  instruction is editing a text file in `src/isa/`, not patching a compiler.
  Alternatives (macro pack, forking `ca65`, writing our own) are analysed in
  `design.md`; this proposal recommends customasm and keeps a `ca65` macro pack
  as the interim bridge.
- **New capability `assembler-toolchain`** covering the instruction-set
  definition files, the build pipeline, the memory map, symbol output and the
  migration guarantee.
- **New `src/isa/` tree**, layered so ISA slices land as additive files:
  - `src/isa/nmos6502.asm` — `#ruledef` for the 151 NMOS opcodes
  - `src/isa/memmap.asm` — `#bankdef` for the memory map, replacing
    `src/memory.cfg`
  - `src/isa/console.asm` — the MMIO register constants currently inlined at the
    top of `main.asm`
  - `src/isa/ext_*.asm` — one file per ISA slice, each `#include`d only when its
    hardware is present
- **Single-command build**: `customasm src/main.asm -f readmemh -o rtl/ram.hex`
  replaces `ca65` + `ld65` + `hexdump`. `src/memory.cfg`, `build/main.o` and the
  `objcopy`/`hexdump` steps are removed from the Makefile. (`readmemh`, not
  customasm's `hexdump` — the latter emits an address column and an ASCII
  sidebar that `$readmemh` would parse as data.)
- **Symbol output** (`-f symbols`) written to `build/main.sym`, consumed by the
  simulator so traces and the future `TRAP` instruction can print names rather
  than addresses.
- **Automatic shortest encoding.** customasm assembles to a fixed point,
  selecting the rule producing the fewest bits. Once
  `add-isa-test-and-branch` adds 16-bit branch displacements, `beq far_label`
  picks the short or long form on its own — "branch out of range" stops being a
  thing the programmer handles.
- **Corpus migration** of the four `src/*.asm` files. Mechanical:
  `$1234` → `0x1234` (customasm reserves `$` for the current address),
  `.define NAME v` → `NAME = v`, `.byte`/`.word` → `#d8`/`#d16`,
  `.include` → `#include`, `.segment` → `#bank`.
- **BREAKING (build tooling)**: `cc65` is no longer required to build the
  console's own software. The `ca65`/`ld65` path is kept behind a
  `make asm-ca65` target for one release as the byte-identity reference, then
  removed.

## Impact

- Affected specs: `assembler-toolchain` (new capability)
- Affected code: `Makefile`, `src/main.asm`, `src/breakout_data.asm`,
  `src/breakout_sfx.asm`, `src/breakout_tables.asm`, `src/memory.cfg` (removed),
  `src/isa/*` (new), `sim/console.cpp` (symbol loading), `README.md`
  (prerequisites)
- Depends on: `add-isa-ergonomic-gates` (gate G7 byte-identity reference)
- Blocks: every `add-isa-*` slice
