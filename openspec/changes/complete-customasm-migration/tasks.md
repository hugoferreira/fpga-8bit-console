## 1. nemo migration

- [ ] 1.1 Check `src/isa/` for any `ext_*.asm` ISA-extension files that exist
      by the time this is implemented, and confirm which of them `nemo`'s
      corpus needs included
- [ ] 1.2 Write `src/nemo/console.asm` with `nemo`'s register/zero-page
      constants (mirroring `src/isa/console.asm`'s role for breakout),
      extracted from the top of `src/nemo/main.asm`
- [ ] 1.3 Migrate `src/nemo/*.asm` to customasm syntax (`.define`→`=`,
      `.byte`→`#d8`, `.word`→little-endian byte pairs, `.include`→`#include`,
      `.segment`→`#bank`, `@name`→`.name`, comma-spacing, `<label`/`>label`)
- [ ] 1.4 Assemble and iterate until output is byte-identical to the current
      `ca65`/`ld65` `nemo` build (gate: per-game byte identity)
- [ ] 1.5 Run `make shot GAME=nemo` and eyeball the result against the
      pre-migration build

## 2. nemo tooling port

- [ ] 2.1 Confirm whether `tools/sim6502.py` reads `.lbl` files directly or
      only receives a pre-parsed symbol dict from its callers
- [ ] 2.2 Port `tools/isa_metrics.py`'s label loading from ca65's `.lbl`
      format to customasm's `-f symbols` format
- [ ] 2.3 Port `tools/test_nemo.py`'s `load_labels` and
      `tools/test_nemo_loop.py`'s equivalent the same way
- [ ] 2.4 Run `make test-nemo` and confirm output is unchanged from the
      pre-migration run (same checks, same pass/fail)

## 3. celeste migration

- [ ] 3.1 Write `src/celeste/console.asm` with `celeste`'s constants
- [ ] 3.2 Migrate `src/celeste/*.asm` to customasm syntax (same transforms
      as nemo)
- [ ] 3.3 Assemble and iterate until output is byte-identical to the current
      `ca65`/`ld65` `celeste` build
- [ ] 3.4 Run `make shot GAME=celeste` and eyeball the result

## 4. celeste tooling port

- [ ] 4.1 Port `tools/test_celeste.py`'s label loading to customasm's
      `-f symbols` format
- [ ] 4.2 Run `make test-celeste` and confirm output is unchanged from the
      pre-migration run

## 5. Remove the ca65/ld65 chain

- [ ] 5.1 Set every game's assembler to customasm (or remove the `GAME_ASM`
      per-game dispatch entirely, now that all three agree)
- [ ] 5.2 Remove the `$(GAME_OBJ)`/`$(GAME_BIN)` ca65 rules, `CA65`/`LD65`/
      `CA65FLAGS`/`LD65FLAGS`, and the `hex-ca65`/`asm-ca65` bridge targets
      from the `Makefile`
- [ ] 5.3 Remove `src/memory.cfg`
- [ ] 5.4 Confirm `make asm`, `make run`, `make shot`, `make test-nemo`,
      `make test-celeste` all still work for every game with no `ca65`
      installed (or with it deliberately removed from `PATH`, to prove the
      dependency is actually gone)

## 6. Documentation

- [ ] 6.1 Update `README.md`: drop `cc65` from prerequisites entirely
- [ ] 6.2 Update `docs/assembler.md`: remove the "nemo/celeste stay on ca65"
      note, since it no longer applies
- [ ] 6.3 Update `openspec/changes/add-custom-assembler/tasks.md`'s
      "Deviations" section to note this follow-up change closed the gap
