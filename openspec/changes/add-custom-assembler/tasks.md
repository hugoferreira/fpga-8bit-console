## 1. Base instruction set definition

- [x] 1.1 Add `customasm` to `README.md` prerequisites with a pinned version and
      record the version in the Makefile
- [x] 1.2 Write `src/isa/nmos6502.asm`: `#ruledef` covering all 151 documented
      NMOS opcodes and all addressing modes (vendored from customasm's own
      `std/cpu/6502.asm`, plus two small additions for ca65 idioms the
      corpus uses - see `docs/assembler.md`)
- [x] 1.3 Add range `assert`s distinguishing zero-page from absolute forms so
      the shortest valid encoding is selected automatically (inherited from
      the vendored ruledef's `u8`/`u16` typed rules)
- [x] 1.4 Unit-check the ruledef: assemble a fixture exercising every opcode and
      compare against a known-good byte table (`tools/test_isa_ruledef.py`)

## 2. Memory map and console constants

- [x] 2.1 Write `src/isa/memmap.asm` with `#bankdef`s for zero page, stack, RAM,
      code at `$0300`, and vectors at `$FFFA`
- [x] 2.2 Write `src/isa/console.asm` with the PPU, PSG and gamepad register
      constants currently declared at the top of `src/main.asm`
- [x] 2.3 Verify a bank overflow produces a build error naming the bank
      (verified interactively; error names the bank and the source line)

## 3. Corpus migration

- [x] 3.1 ~~Script the literal rewrite `$hex` → `0xhex`~~ **not needed**:
      customasm v0.14.1 still accepts `$hex` digit literals directly (`$` on
      its own, with no digits following, is the current-address symbol) -
      confirmed empirically, so this rewrite was dropped
- [x] 3.2 Convert `.define NAME v` → `NAME = v` (141 sites)
- [x] 3.3 Convert `.byte` → `#d8` (480 sites; string literals → bare `#d`) and
      `.word` → explicit little-endian byte pairs (3 sites; **not** `#d16`,
      which is big-endian - see `docs/assembler.md`)
- [x] 3.4 Convert `.include` → `#include` (3 sites) and `.segment` → `#bank`
      (2 sites)
- [x] 3.5 Move the register constant block out of `main.asm` into
      `src/isa/console.asm` and include it
- [x] 3.6 Assemble and iterate until output is byte-identical to the `ca65`
      build (**gate A2** - `cmp`-verified byte-for-byte)
- [x] 3.7 (found during migration, not originally scoped) Rewrite ca65 cheap
      local labels `@name` → customasm sub-labels `.name` (398 sites) and
      normalize `,x`/`,y` operand spacing to `, x`/`, y` (customasm v0.14.1
      does not match an operand's index-register comma without a following
      space) - both documented in `docs/assembler.md`

## 4. Build pipeline

- [x] 4.1 Replace the `ca65`/`ld65`/`hexdump` chain with a single `customasm`
      invocation emitting `-f readmemh` straight to `rtl/ram.hex`; confirmed
      byte-for-byte identical to the previous `hexdump` output (token
      comparison, since customasm's `readmemh` groups one byte per line
      rather than 16)
- [x] 4.1a Pin the `--iters` bound explicitly (10); confirmed a too-small
      bound (`-t 1`) fails the build with "instruction encoding did not
      converge" against the real corpus, rather than emitting wrong bytes
- [x] 4.2 Emit `build/<game>.bin` and `build/<game>.sym` alongside it (named
      per-game, matching the existing `build/<game>.lbl` convention, rather
      than the fixed `build/main.*` in the original proposal text)
- [x] 4.3 Keep the previous chain as `make asm-ca65` for games still on it
      (see deviation note below - the bridge stayed relevant longer than the
      proposal assumed)
- [x] 4.4 Remove the unused `OBJCOPY` variable. `src/memory.cfg` and the
      `ca65`/`ld65` rule chain are **kept**, not removed: `nemo`/`celeste`
      still build with them (see deviation note)
- [x] 4.5 Confirm whole-corpus assembly completes in under 1 second (**gate
      A4** - resolves in 3 iterations, well under a second)
- [x] 4.6 Add a version guard to the Makefile: on a missing or mismatched
      `customasm`, fail naming both versions and the `cargo install customasm`
      command (verified against a fake `customasm` reporting a wrong version)
- [x] 4.7 Assemble with `--legacy=off --color=off` explicitly; re-verified
      byte-identity holds with these flags set

## 5. Simulator integration

- [x] 5.1 Load `build/<game>.sym` in `sim/console.cpp` via `--sym <path>`
      (`make run`/`make shot` pass it automatically when the file exists)
- [x] 5.2 Resolve an address to the nearest preceding label plus offset
      (**gate A6**), exposed via `--resolve <addr>`. **Deviation**: no live
      instruction trace - `Vtop`'s top-level ports do not currently expose a
      CPU program-counter signal, so there is nothing to resolve *during* a
      run yet. Wiring this to a real per-instruction trace needs a debug PC
      port surfaced through `top.sv`/`chip.sv`, which is out of scope for
      this change (RTL change, not an assembler one).

## 6. Documentation and gates

- [x] 6.1 Write `docs/assembler.md`: the ca65 → customasm syntax mapping table,
      the `src/isa/` layering, and how a slice adds a `#ruledef` (**gate A1**)
- [x] 6.2 Add negative-path fixtures (**gate A5**): branch out of range
      produces an error naming the source line and the failing assertion
      (verified). The zero-page/absolute half does **not** apply to the base
      NMOS ISA - every zp-addressable mnemonic here also has an absolute
      form, so there is no zp-only rule to violate yet; this applies once an
      ISA extension slice adds one.
- [ ] 6.3 Confirm assembling with and without an extension file, using no
      extension mnemonic, yields identical output - **not applicable yet**:
      no `src/isa/ext_*.asm` slice exists in this repo yet (that is future
      `add-isa-*` work); nothing to test against today.
- [x] 6.4 Run `make metrics` and confirm no gate regression from the migration
- [x] 6.5 Update `README.md`: drop `cc65` from required tools for the primary
      build, document `make asm-ca65` as the deprecated bridge for
      still-ca65 games

## Deviations from the original proposal

- **`nemo`/`celeste` stay on `ca65`.** The proposal's migration surface was
  always just the breakout corpus, but the Makefile and README drafts talked
  about a single global cutover. In practice `nemo`/`celeste` are separate,
  unmigrated ISA corpora whose Python test tooling depends on ca65's `.lbl`
  format, so the `Makefile` now picks the toolchain per game
  (`$(GAME)_ASM`), and `src/memory.cfg`/`OBJCOPY`/the ca65 rule chain stay
  for as long as those games need them - not removed after one release as
  originally planned. `asm-ca65` is a permanent per-game bridge, not a
  breakout-specific waypoint to be deleted.
- **`$hex` literals were never rewritten.** design.md assumed `$4000` had to
  become `0x4000`; customasm v0.14.1 accepts both, so this planned mechanical
  edit (and its scripted rewrite) turned out to be unnecessary.
- **Two migration needs surfaced that the proposal didn't anticipate**: ca65
  cheap local labels (`@name` → `.name`) and a comma-spacing quirk in
  customasm's instruction matcher (`,x` → `, x`). Both mechanical, both
  documented in `docs/assembler.md`.
