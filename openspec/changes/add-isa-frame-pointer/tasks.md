## 1. Zero-page budget

- [ ] 1.1 Map the current zero-page usage from the 141 `.define`s: highest
      address used, gaps, and how many bytes are free for a frame region
- [ ] 1.2 **Decision point**: if fewer than 48 bytes are available for frames,
      stop and record that this program is too small to need them

## 2. Registry and assembler

- [ ] 2.1 Claim the `$02` prefix-page slots for `ENTER`, `LEAVE` and the
      frame-relative forms in `docs/opcodes.md`
- [ ] 2.2 Write `src/isa/ext_frame.asm`, including frame-relative forms of the
      load/store/compare instructions and of `MOV`
- [ ] 2.3 Add the frame region to `src/isa/memmap.asm`, growing downward from
      the top of zero page
- [ ] 2.4 Add a `f+n` operand syntax with a range assertion on `n`

## 3. RTL: frame pointer and addressing

- [ ] 3.1 Add the `F` register and the frame-support mode bit, clear at reset
- [ ] 3.2 Add the frame-relative addressing mode, resolving `(F + n) mod 256`
- [ ] 3.3 Implement `ENTER #n` and `LEAVE`
- [ ] 3.4 Add the frame floor register and the overflow trap on `ENTER`
- [ ] 3.5 Confirm `F` cannot be set to an arbitrary value by any instruction

## 4. RTL: interrupt safety

- [ ] 4.1 Save `F` on interrupt entry and restore it in `RTI` when frame support
      is enabled
- [ ] 4.2 Confirm that with frame support disabled, interrupt entry and `RTI`
      are cycle-identical to the pre-change core (**gate G7**)

## 5. Simulator

- [ ] 5.1 Walk and print the frame chain on a diagnostic trap: base, size and
      allocating routine from `build/main.sym`
- [ ] 5.2 Report frame overflow with the routine name and halt
- [ ] 5.3 Land this before any corpus migration — frame values have no fixed
      address, so debugging regresses until this exists

## 6. Tests

- [ ] 6.1 Frame allocation, release, nesting and zero-page wrap
- [ ] 6.2 Recursion to depth 4 with a distinct local value per level
- [ ] 6.3 Interrupt inside a framed routine, handler allocating its own frame
- [ ] 6.4 Overflow trap fires at the floor
- [ ] 6.5 Run the 6502 conformance suite with frame support both disabled and
      enabled (**gate G7**)

## 7. Rewrite gate

- [ ] 7.1 Rewrite `pad_zone` (leaf with temporaries) using a frame
- [ ] 7.2 Rewrite `ball_step` (mid-level) using a frame
- [ ] 7.3 Rewrite `update_pills` / `swap_ball2`, which currently share scratch
      bytes, so that each owns its locals
- [ ] 7.4 Implement one genuinely recursive routine that is impossible today
- [ ] 7.5 Count the `.define`s eliminated from the global map
- [ ] 7.6 **Gate decision point**: fewer than 20 globals freed means the slice is
      abandoned and the outcome recorded in `docs/opcodes.md`

## 8. Gates

- [ ] 8.1 **G5 (inverted)** instruction count and byte count grew by no more
      than 2%
- [ ] 8.2 **G6** plumbing ratio non-increasing
- [ ] 8.3 **G8** frame-work cycles did not increase
- [ ] 8.4 Record the freed-globals count as a new tracked metric in
      `docs/isa-baseline.json`
- [ ] 8.5 Update `openspec/project.md` with the frame convention if the slice
      ships
