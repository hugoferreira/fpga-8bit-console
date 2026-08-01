## 1. Registry and assembler

- [ ] 1.1 Claim `$83`–`$F3` in `docs/opcodes.md`
- [ ] 1.2 Write `src/isa/ext_word.asm` with the eight rules, asserting zero-page
      range on every operand
- [ ] 1.3 Document the little-endian pair convention and the `$FF`/`$00` wrap in
      `docs/assembler.md`

## 2. RTL: word data movement

- [ ] 2.1 Implement `MOVW zp, #imm16` (`$83`) as a 6-state sequence
- [ ] 2.2 Implement `MOVW zp, zp` (`$93`) as an 8-state sequence
- [ ] 2.3 Confirm high-byte address computation wraps modulo 256

## 3. RTL: word arithmetic

- [ ] 3.1 Add the internal carry latch between the low and high byte passes
- [ ] 3.2 Implement `ADDW zp, #imm16` (`$A3`) and `ADDW zp, zp` (`$B3`)
- [ ] 3.3 Implement `SUBW zp, #imm16` (`$C3`)
- [ ] 3.4 Implement `CMPW zp, #imm16` (`$D3`) as `SUBW` without the writes
- [ ] 3.5 Implement `INW` (`$E3`) and `DEW` (`$F3`), leaving `C` unchanged
- [ ] 3.6 Set `N` from bit 15, `Z` from the full 16-bit result, `V` from signed
      16-bit overflow, `C` from bit 16
- [ ] 3.7 Confirm binary operation regardless of the decimal flag
- [ ] 3.8 Confirm `A`, `X`, `Y` are untouched by every instruction in the slice

## 4. Interrupt latency

- [ ] 4.1 Determine whether the console takes interrupts during gameplay
- [ ] 4.2 If so, measure the worst-case IRQ latency with `ADDW zp, zp` in flight
      (11 cycles) against the video timing budget
- [ ] 4.3 If the budget is exceeded, make the word sequences interruptible at a
      byte boundary or drop `ADDW zp, zp` to the prefix page

## 5. Tests

- [ ] 5.1 Per-instruction value, byte-count and cycle-count tests
- [ ] 5.2 Carry propagation, zero-page wrap at `$FF`, and flag derivation for
      each instruction
- [ ] 5.3 Test with the carry flag set on entry and with decimal mode set
- [ ] 5.4 Test `CMPW` followed by each of `BEQ`, `BNE`, `BCC`, `BCS`
- [ ] 5.5 Register-preservation test across the whole slice
- [ ] 5.6 Run the 6502 conformance suite (**gate G7**)

## 6. Rewrite-measured evidence (gate G3)

- [ ] 6.1 Rewrite `ball_step` using the word instructions; record instruction
      count, byte count and cycles before and after
- [ ] 6.2 Rewrite `update_pills` the same way and record both measurements
- [ ] 6.3 Commit both before and after forms so the comparison is reviewable
- [ ] 6.4 **Gate check**: if either routine fails to at least halve its
      instruction count, cut the slice to the instructions the rewrites actually
      used and return the unused slots to the free list

## 7. Corpus migration and gates

- [ ] 7.1 Scan for the remaining 16-bit sites via the `+1`-operand report and
      migrate them
- [ ] 7.2 **G5** ≥ 120 instructions removed, binary did not grow
- [ ] 7.3 **G6** plumbing ratio non-increasing
- [ ] 7.4 **G8** frame-work cycles did not increase
- [ ] 7.5 Update `docs/isa-baseline.json`
