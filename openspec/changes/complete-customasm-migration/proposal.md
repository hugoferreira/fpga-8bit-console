## Why

`add-custom-assembler` migrated only the breakout corpus to customasm and
proved it byte-identical to the prior `ca65`/`ld65` build. `nemo` and
`celeste` were deliberately left on `ca65`/`ld65` because their Python test
tooling (`tools/test_nemo.py`, `tools/test_nemo_loop.py`,
`tools/test_celeste.py`, `tools/isa_metrics.py`, `tools/sim6502.py`) reads
ca65's `.lbl` label-file format. That leaves the project with two assemblers,
a per-game `GAME_ASM` dispatch in the `Makefile`, a `make asm-ca65` bridge,
`src/memory.cfg` still live, and `cc65` still a required tool for two of the
three games — the migration is half-finished, and every ISA extension slice
that touches `nemo` or `celeste` (which is most of them: `nemo`'s own
description is "ISA corpus") still can't add a new opcode without a `.byte`
blob, which is the exact problem `add-custom-assembler` set out to remove.

## What Changes

- Migrate `src/nemo/*.asm` and `src/celeste/*.asm` to customasm syntax, using
  the same mechanical transforms already documented in `docs/assembler.md`
  (`.define`→`=`, `.byte`→`#d8`, `.word`→explicit little-endian byte pairs,
  `.include`→`#include`, `.segment`→`#bank`, `@name`→`.name` cheap locals,
  comma-spacing normalization, `<label`/`>label` handling), each corpus
  including `src/isa/nmos6502.asm`/`memmap.asm`/`console.asm` plus its own
  register/zero-page constants file.
- Prove byte-identical output for both corpora against their current
  `ca65`/`ld65` builds, the same way breakout was proven.
- Port `tools/test_nemo.py`, `tools/test_nemo_loop.py`, `tools/test_celeste.py`,
  `tools/isa_metrics.py`, and `tools/sim6502.py` off ca65's `.lbl` format onto
  customasm's `-f symbols` format (already used by `build/breakout.sym`).
- **BREAKING**: Remove the `ca65`/`ld65` chain entirely from the `Makefile` —
  the `$(GAME_OBJ)`/`$(GAME_BIN)` ca65 rules, `CA65`/`LD65`/`CA65FLAGS`/
  `LD65FLAGS`, the `hex-ca65`/`asm-ca65` bridge targets, and the `GAME_ASM`
  per-game dispatch. customasm becomes the only assembler for every game.
- Remove `src/memory.cfg`, superseded by `src/isa/memmap.asm`.
- **BREAKING**: Drop `cc65` from `README.md` prerequisites entirely.

## Capabilities

### New Capabilities

(none — this completes an existing capability rather than introducing one)

### Modified Capabilities

- `assembler-toolchain`: the migration guarantee extends from "breakout only,
  ca65 kept as a bridge" to "every game, ca65/cc65 fully retired." The
  `assembler-toolchain` capability itself was introduced by
  `add-custom-assembler` (not yet archived into `openspec/specs/`); this
  change's delta spec supersedes that one's "ca65 kept for one release" and
  per-game-dispatch language.

## Impact

- Affected code: `Makefile`, `src/nemo/*.asm`, `src/celeste/*.asm`,
  `src/memory.cfg` (removed), `tools/test_nemo.py`, `tools/test_nemo_loop.py`,
  `tools/test_celeste.py`, `tools/isa_metrics.py`, `tools/sim6502.py`,
  `README.md`
- Depends on: `add-custom-assembler` (this change's `src/isa/*` and
  `docs/assembler.md` are the foundation being extended)
- Not started: this proposal captures the remaining work; implementation has
  not begun.
