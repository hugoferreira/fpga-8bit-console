## 1. Metrics tool

- [ ] 1.1 Write `tools/isa_metrics.py`: parse `src/*.asm` into an instruction
      stream (mnemonic + operand, comments and directives stripped)
- [ ] 1.2 Compute `toll`, `ceremony`, `transfers`, `spills`, instruction total
      and the derived plumbing ratio
- [ ] 1.3 Compute per-idiom occurrence counts: `lda`→`sta` split by source mode
      (immediate / memory) and destination mode (zp / abs / indexed),
      `clc`→`adc`, `lda`/`cmp`/branch, `lda`/`and`/branch, `dec`→`bne`,
      operands referencing `+1`, `(zp),y`
- [ ] 1.4 Cross-check the source-derived instruction count against the built
      binary; fail with a parser-drift error beyond 2%
- [ ] 1.5 Emit a JSON report and a human-readable gate table
- [ ] 1.6 Compare against `docs/isa-baseline.json` and exit non-zero on any
      gate regression
- [ ] 1.7 Add `--check-registry` mode validating `docs/opcodes.md` for duplicate
      and reserved-slot claims

## 2. Frame-work cycle measurement

- [ ] 2.1 Add a `--metrics` mode to `sim/console.cpp` that runs a fixed input
      replay headless for a fixed frame count
- [ ] 2.2 Instrument it to count CPU cycles between leaving the `main_loop`
      `SPR_FRAME` spin and re-entering it, reported per frame and as a mean
- [ ] 2.3 Add a deterministic input replay file under `test/replay/` and make
      the LFSR seed fixed in metrics mode
- [ ] 2.4 Have `isa_metrics.py` invoke it and fold the result into the report

## 3. Opcode registry

- [ ] 3.1 Write `docs/opcodes.md` with all 256 slots: NMOS-defined, WDC 65C02
      reserved, Rockwell R65C02 reserved, extension space, free
- [ ] 3.2 Record the extension-space assignment per the allocation policy
      (`$x3` low/high, `$xB` low/high, `$02` prefix page)
- [ ] 3.3 Document the per-entry format: opcode, mnemonic, operands, bytes,
      cycles, flags, clobbers, owning change

## 4. Compatibility harness

- [ ] 4.1 Vendor Klaus Dormann's `6502_functional_test` binary and its load
      address under `test/`
- [ ] 4.2 Add `rtl/cpu6502_functional_tb.sv` running it to the success trap with
      a cycle cap and a failure report on trap-loop detection
- [ ] 4.3 Extend the `make test` target to run it
- [ ] 4.4 Record the current `build/main.bin` checksum as the byte-identity
      reference for gate G7

## 5. Baseline and wiring

- [ ] 5.1 Add the `make metrics` target
- [ ] 5.2 Run the tool on the current tree and commit `docs/isa-baseline.json`,
      including the corpus commit hash
- [ ] 5.3 Verify the recorded baseline reproduces the numbers in `proposal.md`
      (1919 instructions, toll 460, ceremony 95, transfers 47, spills 28,
      plumbing 32.8%)
- [ ] 5.4 Document the gate workflow in `docs/opcodes.md`'s preamble: a slice
      edits the registry and re-runs `make metrics` in the same commit
