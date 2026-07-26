## 1. Evidence gathering (before any RTL)

- [ ] 1.1 Measure `ADDW (zp), #imm8` candidate sites: pointer advances by a
      constant stride in `src/main.asm`
- [ ] 1.2 Identify and measure the hand-written copy and fill loops
      (`msg_clear`, `build_level`, the sprite shadow update): instruction count,
      byte count, cycles
- [ ] 1.3 Check whether the PPU already offers a shadow-update path that makes a
      block copy redundant for the largest copy in the program
- [ ] 1.4 **Gate decision point**: any instruction group without ≥ 8 sites or a
      rewrite that halves a named routine is cut before implementation, and its
      slots returned to the free list in `docs/opcodes.md`

## 2. Registry and assembler

- [ ] 2.1 Claim the surviving slots from `$8B`–`$FB` in `docs/opcodes.md`
- [ ] 2.2 Write `src/isa/ext_pointer.asm`
- [ ] 2.3 Document in `docs/assembler.md` that block instructions modify their
      own operands

## 3. RTL: post-increment forms

- [ ] 3.1 Implement `LDA (zp)+` (`$8B`) and `STA (zp)+` (`$9B`)
- [ ] 3.2 Implement `MOV (zp)+, #imm` (`$AB`) and `MOV zp, (zp)+` (`$BB`)
- [ ] 3.3 Implement `ADDW (zp), #imm8` (`$CB`)
- [ ] 3.4 Confirm the access uses the pre-increment address and the increment
      carries into the high byte
- [ ] 3.5 Confirm `X` and `Y` are never touched

## 4. RTL: block fill

- [ ] 4.1 Implement `FILL (dst), #imm, zp` (`$FB`) as a per-byte loop committing
      pointer and count to memory each step
- [ ] 4.2 On an interrupt, back the pushed return address up to the instruction
      so `RTI` resumes it
- [ ] 4.3 Confirm a zero count writes nothing

## 5. RTL: block copy

- [ ] 5.1 Implement `CPY (dst), (src), #imm` (`$DB`)
- [ ] 5.2 Implement `CPYW (dst), (src), zp` (`$EB`)
- [ ] 5.3 Reuse the fill instruction's resume machinery

## 6. Tests

- [ ] 6.1 Post-increment tests: pre-increment access, page-boundary carry,
      register preservation, cycle counts
- [ ] 6.2 Block operation correctness for counts of 0, 1, 255, 256 and 512
- [ ] 6.3 **Interrupt-resume sweep**: fire an interrupt at every cycle offset
      within a 256-byte copy and confirm every run matches the uninterrupted
      result
- [ ] 6.4 Confirm interrupt latency during a block operation is bounded by the
      per-byte step, not the whole operation
- [ ] 6.5 Measure per-byte bus occupancy against video and audio contention
- [ ] 6.6 Run the 6502 conformance suite (**gate G7**)

## 7. Migration and the counterfactual test

- [ ] 7.1 Migrate the 16 `(zp),Y` sites to post-increment forms
- [ ] 7.2 Migrate the fill loops, then the copy loops
- [ ] 7.3 Write one **new** routine pointer-first and compare it against the
      indexed-absolute version a 6502 programmer would otherwise write; record
      both. This is the test of the slice's premise that the program is flat
      because pointers are expensive
- [ ] 7.4 If the counterfactual test fails, reduce the slice to the
      post-increment forms and record the outcome in the registry

## 8. Gates

- [ ] 8.1 **G3** every retained instruction has ≥ 8 sites or a halving rewrite
- [ ] 8.2 **G4** measured cycles beat the replaced sequences
- [ ] 8.3 **G5** declared reduction met, binary did not grow
- [ ] 8.4 **G6** plumbing ratio non-increasing
- [ ] 8.5 **G8** frame-work cycles did not increase
- [ ] 8.6 Update `docs/isa-baseline.json`
