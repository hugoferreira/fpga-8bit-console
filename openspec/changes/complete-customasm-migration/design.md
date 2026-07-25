## Context

`add-custom-assembler` proved the migration path on breakout: customasm's
vendored `std/cpu/6502.asm` ruledef plus two small additions, mechanical
syntax rewrites, and a `cmp`-verified byte-identical build. `src/isa/` (the
ruledef, memory map, and console-constants files) already exists and is
shared infrastructure — this change reuses it as-is; it does not touch
`src/isa/nmos6502.asm` or `src/isa/memmap.asm`.

What's left is repeating that migration for `nemo` and `celeste`, and — the
part breakout didn't need — updating the Python tooling that reads `ca65`'s
`.lbl` label format, since that format only exists on the ca65 path this
change removes.

## Goals / Non-Goals

**Goals**

- `nemo` and `celeste` assemble with customasm, byte-identical to their
  current `ca65`/`ld65` builds (the same correctness bar as breakout).
- Every Python tool that currently reads a `.lbl` file reads a customasm
  `-f symbols` file instead, with no loss of functionality.
- `ca65`, `ld65`, and `cc65` are no longer required to build or test any part
  of this project.

**Non-Goals**

- Changing `src/isa/nmos6502.asm`/`memmap.asm` — those are shared and already
  correct.
- Any behavior change to the games themselves. This is a toolchain migration;
  gate A2 (byte identity) is what makes that provable.

## Decisions

### Decision: migrate nemo and celeste the same way breakout was migrated

Each game gets its own `#include "<game>-console.asm"`-style constants file
(mirroring `src/isa/console.asm`), placed alongside its corpus (e.g.
`src/nemo/console.asm`), rather than a shared one — `nemo` and `celeste` have
their own, non-overlapping zero-page layouts and register usage, so sharing
a single constants file across three games would mean carrying dead symbols
into each build for no benefit. The `Makefile`'s existing `_INC` per-game
include path becomes unnecessary once each corpus resolves its own
includes relative to its own directory (customasm resolves `#include`
relative to the including file, as breakout's migration already relies on).

### Decision: port the `.lbl` readers to customasm's `-f symbols` format, not the other way around

`ld65 -Ln`'s format (`al 001234 .name`) only exists because ld65 produces it;
once ld65 is gone, so is the format. customasm's `-f symbols` format
(`NAME = 0xVALUE`, one per line) is already what `build/breakout.sym` uses
and what `sim/console.cpp`'s `load_symbols` already parses — the same
few-line parser shape, just in Python instead of C++:

```python
def load_symbols(path):
    sym = {}
    for line in open(path):
        name, _, value = line.partition("=")
        name = name.strip()
        if name:
            sym[name] = int(value.strip(), 0)
    return sym
```

This replaces `load_labels`'s regex in `tools/test_nemo.py` (and the
equivalent in `tools/test_celeste.py`, `tools/isa_metrics.py`,
`tools/sim6502.py` if it reads labels directly rather than being handed a
pre-parsed dict). Call sites that pass a `.lbl` path change to pass a `.sym`
path; the `Makefile` already emits `build/<game>.sym` for customasm games.

### Decision: remove the ca65 path in one commit per game, not all at once

Migrate and byte-identity-prove `nemo`, then `celeste`, as two independent
steps (each gated on its own byte-identity check) before touching the
`Makefile`'s shared `ca65`/`ld65` rules. Only once both are on customasm does
removing the shared `GAME_ASM` dispatch and the `hex-ca65`/`asm-ca65` bridge
become safe — removing it earlier would break whichever game hadn't migrated
yet.

## Risks / Trade-offs

- **Two more corpora to migrate by hand** (mechanical, but `nemo` in
  particular is described as "ISA corpus" and may have accumulated ISA
  extension mnemonics from `add-isa-*` slices landed since
  `add-custom-assembler`; those need their own `src/isa/ext_*.asm` includes
  wired into `nemo`'s migrated source, not just the base `nmos6502.asm`).
  Mitigation: check `src/isa/` for any `ext_*.asm` files that exist by the
  time this is implemented, and confirm `nemo`'s corpus assembles against
  them before claiming byte identity.
- **Test tooling regression risk**: `tools/test_nemo.py` and friends are the
  correctness net for the ISA extension programme; a bug in the `.sym`
  parser silently resolving the wrong address would be worse than the
  current `.lbl` parser being ca65-only. Mitigation: run each test suite
  (`make test-nemo`, `make test-celeste`) after the tooling port and require
  identical pass/fail output to the pre-migration run.
- **`cc65` removal is user-facing**: anyone with a build script or CI config
  invoking `ca65`/`ld65` directly breaks. Mitigation: this is the intended,
  previously-flagged final step (`add-custom-assembler`'s proposal always
  scoped `cc65` removal as the end state, just deferred past its own
  breakout-only scope).

## Migration Plan

1. Migrate `src/nemo/*.asm` to customasm syntax; assemble and `cmp` against
   the current `ca65`/`ld65` `nemo` build until byte-identical.
2. Port `tools/isa_metrics.py`, `tools/sim6502.py` (if applicable),
   `tools/test_nemo.py`, `tools/test_nemo_loop.py` to read `build/nemo.sym`;
   confirm `make test-nemo` passes identically to the pre-migration run.
3. Repeat steps 1-2 for `celeste` (`tools/test_celeste.py`, `make
   test-celeste`).
4. Set `nemo_ASM = customasm` and `celeste_ASM = customasm` in the `Makefile`
   (or remove the `GAME_ASM` dispatch entirely, since every game now agrees).
5. Remove the `ca65`/`ld65` rule chain, `hex-ca65`/`asm-ca65` bridge targets,
   `CA65`/`LD65`/`CA65FLAGS`/`LD65FLAGS`, and `src/memory.cfg`.
6. Update `README.md`: drop `cc65` from prerequisites.

Rollback at any point before step 5 is simply not flipping that game's
`GAME_ASM` — the ca65 chain stays available until it is deliberately removed.

## Open Questions

- Does `tools/sim6502.py` read `.lbl` files itself, or only receive an
  already-parsed dict from its callers? (Affects whether it needs its own
  port or just its callers do.) Confirm by reading it when implementation
  starts — not investigated in this proposal.
