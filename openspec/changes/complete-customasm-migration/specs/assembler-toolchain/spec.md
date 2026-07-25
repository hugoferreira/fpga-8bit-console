## MODIFIED Requirements

### Requirement: Migration Byte Identity

Every game's corpus (`breakout`, `nemo`, `celeste`) SHALL assemble to a binary
byte-identical to the one produced by that game's pre-migration `ca65`/`ld65`
pipeline. The previous pipeline SHALL remain available as `make asm-ca65` per
game only until that game's equivalence has been demonstrated; once every
game has demonstrated it, the `ca65`/`ld65` pipeline SHALL be removed
entirely rather than kept as a permanent bridge.

#### Scenario: Equivalence is demonstrated per game

- **WHEN** a game's customasm build and its prior `ca65`/`ld65` build both
  assemble that game's corpus
- **THEN** the resulting binaries compare equal byte for byte

#### Scenario: Bridge is removed once every game has migrated

- **WHEN** `breakout`, `nemo` and `celeste` have each demonstrated byte
  identity on customasm
- **THEN** the `ca65`/`ld65` rule chain, the `hex-ca65`/`asm-ca65` targets,
  `src/memory.cfg`, and the `cc65` prerequisite are removed from the project

## ADDED Requirements

### Requirement: Single Assembler For All Games

customasm SHALL be the only assembler used to build any game in this
project. No game SHALL select `ca65` as its assembler, and the `Makefile`
SHALL NOT dispatch per-game between two assembler toolchains.

#### Scenario: No per-game assembler selection remains

- **WHEN** `make asm GAME=<any game>` runs, for any game in `GAMES`
- **THEN** the build uses customasm, and no `ca65`/`ld65` invocation occurs
  anywhere in the build for that game

### Requirement: Test Tooling Reads customasm Symbols

Python tooling that resolves an assembled address to a symbol name (test
suites, ISA metrics) SHALL read customasm's `-f symbols` output format
(`NAME = 0xVALUE` per line). It SHALL NOT depend on `ca65`'s `.lbl` label
format.

#### Scenario: Test suite resolves a symbol from the customasm build

- **WHEN** `tools/test_nemo.py` or `tools/test_celeste.py` runs against a
  customasm-built binary and its `build/<game>.sym` file
- **THEN** every symbol lookup the test performs resolves to the same
  address it resolved to before the migration, and the suite's pass/fail
  output is unchanged from the pre-migration `ca65` run
