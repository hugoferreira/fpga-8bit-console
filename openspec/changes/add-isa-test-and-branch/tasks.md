## 1. Registry and assembler

- [ ] 1.1 Claim `$0B`–`$7B` in `docs/opcodes.md`, and reserve the `$02` prefix
      page entries for the long branch forms
- [ ] 1.2 Write `src/isa/ext_branch.asm` with the eight primary rules
- [ ] 1.3 Add the long-form rules for every conditional branch, `BSR` and `BRA`,
      each paired with a range-asserted short form so the assembler selects the
      shortest that reaches
- [ ] 1.4 Verify the short-form assertion is monotone in the displacement, and
      add a fixture with deeply nested forward and backward branches to exercise
      convergence
- [ ] 1.5 Verify a target reachable by no form produces a clear error

## 2. RTL: compare and test

- [ ] 2.1 Add a comparison result path that does not commit to the flag register
- [ ] 2.2 Implement `CBEQ`/`CBNE`/`CBLT`/`CBGE` (`$0B`–`$3B`) as a shared
      sequence with a condition mux
- [ ] 2.3 Implement `TBZ`/`TBNZ` (`$4B`, `$5B`) on the same sequence with AND
- [ ] 2.4 Confirm the page-cross extra cycle matches the existing branch
      behaviour
- [ ] 2.5 Confirm no form writes `A`, `X`, `Y` or any flag

## 3. RTL: relative call and jump

- [ ] 3.1 Implement `BSR` (`$6B`) reusing the `JSR` push states with a relative
      target
- [ ] 3.2 Implement `BRA` (`$7B`) on the taken-branch path with the condition
      forced true

## 4. RTL: prefix page and long branches

- [ ] 4.1 Add `$02` prefix decode: fetch the following byte as the real opcode,
      costing one extra cycle
- [ ] 4.2 Implement the 16-bit displacement variants of every conditional
      branch, `BSR` and `BRA`
- [ ] 4.3 Confirm an unrecognised prefix-page opcode behaves as a defined no-op
      rather than hanging the core

## 5. Tests

- [ ] 5.1 Per-instruction tests: taken, not taken, page-cross, byte count, cycle
      count, and full register/flag preservation
- [ ] 5.2 Test that a `CMP` / `CBNE` / conditional-branch sequence branches on
      the `CMP`
- [ ] 5.3 Test `BSR`/`RTS` round trip and position independence
- [ ] 5.4 Test each long branch form reaching forward and backward across a
      distance no short form can express
- [ ] 5.5 Run the 6502 conformance suite (**gate G7**)
- [ ] 5.6 Confirm the unmigrated corpus assembles byte-identically with the
      long-branch rules enabled (**gate G7**)

## 6. Corpus migration

- [ ] 6.1 Migrate the 30 `lda`/`cmp`/branch sites to `CBxx`
- [ ] 6.2 Migrate the 46 `lda`/branch zero tests to `CBEQ`/`CBNE` with `#0`
- [ ] 6.3 Migrate the 16 `lda`/`and`/branch sites to `TBZ`/`TBNZ`
- [ ] 6.4 Migrate `jsr` sites whose target is within range to `BSR`
- [ ] 6.5 **Measure `jmp` sites whose target is within ±127 bytes.** If fewer
      than 8, cut `BRA`, return `$7B` to the free list in the registry, and
      record the rejection alongside `MOV zp, zp` and `DBNZ`
- [ ] 6.6 Run `make metrics` after each pass

## 7. Gates

- [ ] 7.1 **G3** confirm every retained instruction has ≥ 8 migrated sites
- [ ] 7.2 **G4** measured cycles confirm each instruction beats its replaced
      sequence
- [ ] 7.3 **G5** ≥ 150 instructions removed, binary did not grow
- [ ] 7.4 **G6** plumbing ratio non-increasing
- [ ] 7.5 **G8** frame-work cycles did not increase
- [ ] 7.6 Update `docs/isa-baseline.json`
