## 1. Opcode registry and assembler

- [x] 1.1 Claim `$03`, `$13`, `$23`, `$33`, `$43`, `$53`, `$63`, `$73` in
      `docs/opcodes.md` with bytes, cycles, clobbers and flags. `docs/opcodes.md`
      is generated from the decode table, so claiming a slot is a row in
      `rtl/cpu6502_decode.sv` plus `make opcodes`; `make check-decode` fails if a
      row lands in a reserved slot or one no slice was assigned
- [ ] 1.2 Record the two gate rejections in the registry's notes: `MOV zp, zp`
      (4 sites) and `DBNZ` (5 sites), so they are not re-proposed blind
- [ ] 1.3 Record the `TRAP` exemption from gate G3 with its justification
- [x] 1.4 Write `src/isa/ext_core.asm` with the eight rules and range assertions
      distinguishing the `zp` and `abs` `MOV` forms
- [ ] 1.5 Verify `make metrics --check-registry` passes

## 2. RTL: MOV

- [x] 2.1 Add the held destination-address register and its load path
- [x] 2.2 Implement `MOV zp, #imm` (`$03`) as a 4-state sequence
- [x] 2.3 Implement `MOV abs, #imm` (`$13`) as a 5-state sequence
- [x] 2.4 Implement `MOV zp, abs,X` (`$23`) reusing the existing indexed
      address-generation states, including the page-cross extra cycle
- [x] 2.5 Confirm no `MOV` form writes `A`, `X`, `Y` or any flag bit

## 3. RTL: ADD / SUB

- [x] 3.1 Force the carry-in mux to 0 for `ADD` and 1 for `SUB` on the existing
      `ADC`/`SBC` datapath
- [x] 3.2 Disable the decimal adjust for `ADD`/`SUB` only, leaving `ADC`/`SBC`
      behaviour untouched
- [x] 3.3 Decode `$33`, `$43`, `$53`, `$63` onto those paths
- [x] 3.4 Confirm `N`, `V`, `Z`, `C` match `ADC`/`SBC` for the same operands with
      carry-in forced

## 4. RTL: TRAP

- [x] 4.1 Decode `$73`, add a `trap_valid`/`trap_code` output pulsed for one
      cycle, and continue to the next instruction
- [x] 4.2 Confirm no register, flag or memory effect
- [x] 4.3 Tie the output off in `rtl/top.sv` so the FPGA build is unaffected

## 5. Tests

- [ ] 5.1 Add per-instruction tests to `rtl/cpu6502_tb.sv`: value correctness,
      byte count, cycle count, and the full register/flag preservation check
- [ ] 5.2 Test the `MOV zp, abs,X` page-cross cycle count
- [ ] 5.3 Test `ADD` with carry set on entry and with decimal mode set
- [ ] 5.4 Test an `ADD`/`ADC` 16-bit chain
- [ ] 5.5 Test a `CMP` / `MOV` / branch sequence branches on the `CMP`
- [ ] 5.6 Run the 6502 conformance suite on the extended core (**gate G7**)
- [ ] 5.7 Confirm the unmigrated corpus still builds byte-identically
      (**gate G7**)

## 6. Simulator

- [ ] 6.1 Handle `trap_valid`/`trap_code` in `sim/console.cpp` with the
      documented code dispatch
- [ ] 6.2 Resolve the trap PC to the nearest preceding label from
      `build/main.sym`
- [ ] 6.3 Add a `--stop-on-trap` flag for the assertion code

## 7. Corpus migration

- [ ] 7.1 Extend `tools/isa_metrics.py` with the flag-consumption detector:
      report any `lda`/`sta` pair whose `N`/`Z` result is read before being
      overwritten
- [ ] 7.2 Migrate the 100 immediate-to-zero-page stores; run `make metrics`
- [ ] 7.3 Migrate the 55 immediate-to-absolute stores; run `make metrics`
- [ ] 7.4 Migrate the 24 indexed-read-to-zero-page moves; run `make metrics`
- [ ] 7.5 Migrate the 70 `clc`/`adc` and 17 `sec`/`sbc` pairs, skipping any site
      the detector flags
- [ ] 7.6 Confirm the corpus mode split assumed by this proposal (`adc`/`sbc`:
      55 immediate, 40 zero page, 9 indexed) still holds post-migration, and
      re-measure whether the deferred indexed-destination `MOV` forms now clear
      the G3 threshold

## 8. Gates

- [ ] 8.1 **G3** every added instruction except `TRAP` replaces an idiom with
      ≥ 8 sites
- [ ] 8.2 **G4** measured cycles confirm every instruction beats its replaced
      sequence in bytes and cycles
- [ ] 8.3 **G5** ≥ 230 instructions removed and `build/main.bin` did not grow
- [ ] 8.4 **G6** plumbing ratio ≤ 15%
- [ ] 8.5 **G8** frame-work cycles did not increase on the replay
- [ ] 8.6 Update `docs/isa-baseline.json` with the post-slice measurement as the
      new reference for slice 4

### Migration result (breakout)

`python3 tools/65x02/migrate_ext.py src/main.asm build/breakout.sym --apply`

| | before | after | |
| --- | --- | --- | --- |
| instructions | 1928 | 1770 | **−8.2%** |
| code bytes | 3894 | 3736 | −4.1% |
| plumbing (**G6**) | 32.9% | **22.0%** | −10.9 points |
| toll | 464 | 290 | |
| ceremony | 95 | 24 | |

158 sites rewritten: 78 `lda #k / sta v`, 62 `clc/adc`, 9 `sec/sbc`, 9
`lda t,x / sta v`. **G5 met** — the count falls and the image does not grow.

101 sites were declined and every one is categorised. The tool proves each
rewrite safe rather than assuming it: `MOV` touches neither `A` nor N/Z where
`lda`/`sta` set both, so a site is only rewritten where a conservative forward
scan shows both dead. A label, a branch, a call or a read of either rejects it.
The largest categories are 21 `sta dst,x` (no `MOV` form), 20 `jsr`, 19 label
and 17 `A read by sta`.

The last of those is a missed opportunity rather than a hazard: `lda #0 / sta a
/ sta b` cannot become `mov a,#0 / sta b`, but it could become two `MOV`s. Left
for a second pass.

Three form constraints were found by the assembler rejecting the output, which
is the right way to find them:

- `MOV zp, abs+X` has no absolute-destination form, so 12 sites were declined.
- `ADD`/`SUB` exist only as `#imm` and `zp`, so 9 `adc`/`sbc` on absolute or
  indexed operands were declined.
- **`lda zp,x` wraps inside page zero and `abs,x` does not.** Rewriting one such
  site would have changed behaviour whenever `zp+X` crossed `$FF`. Declined, and
  the tool now resolves symbol values from the assembler's own output to tell
  the two apart.
