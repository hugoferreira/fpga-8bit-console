## 1. Golden suite harness (built and validated before the new core exists)

- [x] 1.1 Make `cpu6502_tb` able to fail: replace the `$display("TEST FAILED")`
      path at `rtl/cpu6502_tb.sv:88-101` with `$fatal`, so `make test` exits
      non-zero
- [x] 1.2 Add a suite fetch to the Makefile: clone `SingleStepTests/65x02` at a
      **pinned commit** into a cache outside the tree; never vendor the 1,082 MB
      of `6502/v1/`
- [x] 1.3 Write the JSON → packed-binary converter for `6502/v1/*.json`, run once
      per pinned commit and cached; record the case count and commit in the
      fixture header
- [x] 1.4 Write `tools/65x02/` — Verilate the core alone against a flat 64 K
      memory, and per case: load `initial.ram`, force `PC`/`S`/`A`/`X`/`Y`/`P`,
      run one instruction, compare
- [x] 1.5 Implement Tier 1 (architectural state: `PC`, `S`, `A`, `X`, `Y`, masked
      `P`, all `ram` entries)
- [x] 1.6 Implement Tier 2 (access footprint: fail on any access to an address
      absent from the case's `ram` lists)
- [x] 1.7 Implement Tier 3 (`cycles` array comparison) as a diagnostic mode that
      never affects the exit code
- [x] 1.8 Implement the flag-mask table with a reason per entry, and count and
      report every suppressed mismatch
- [x] 1.9 Add the documented-151 opcode list, and make the harness skip the 105
      undefined files by default and report that it did
- [x] 1.10 Add fast-subset mode (N cases per opcode) and make every result state
      the case count and the pinned suite commit
- [x] 1.11 **Run the harness against the existing Arlet core.** This validates the
      harness against a known-good implementation. Record every divergence Arlet
      already has, before it is deleted
- [x] 1.12 Emit `docs/cpu-timing.json` for the Arlet core as the baseline cycle
      table, and cross-check it against published NMOS cycle counts.
      **Done** as `docs/cpu-timing-arlet.json` (one file per core; the frozen
      `docs/cpu-timing.json` comes at task 6.7). Cross-checked against the
      suite's own `cycles` arrays rather than a published table: identical on
      all 151 opcodes, mean 4.010

### Phase 1 result

`make test-65x02 CASES=0`: **1,509,471 / 1,510,000 pass** Tiers 1 and 2 in 17 s.
One opcode fails - `BRK`, 529 cases - and the cause is pinned exactly: Arlet
re-decodes `adc_sbc`/`adc_bcd` during `BRK0`, where the instruction register
still holds `BRK`'s signature byte. 631 cases have a signature byte matching
`x11x_xx01`; every one of the 529 failures is in that set and none is outside
it. Written up in `docs/cpu-core.md`, with the `JMP ($xxFF)` divergence and the
three Tier 3 access-pattern families.

The harness runs on any 6502 core: state is set through the bus with a
flag-neutral preamble rather than by forcing registers, so it was validated
against Arlet before the new core exists, exactly as the bring-up plan asks.

## 2. Baseline measurement (no RTL change)

- [ ] 2.1 Get a `yosys` → `nextpnr` → `icetime` run to complete for `hx8k`
      (`synthesis.log` currently ends mid-optimisation) and record the wall time
- [ ] 2.2 Rewrite `make timing` to report achieved Fmax plus the top-10 critical
      paths with the owning module for each, and to exit non-zero when the achieved
      frequency misses `TARGET_FREQ`
- [ ] 2.3 Record achieved Fmax, the attributed paths and `make stat` utilisation in
      `docs/cpu-baseline.json`, including the CPU's own LUT/DFF count as the T8
      budget
- [ ] 2.4 Resolve whether `TARGET_FREQ = 50` is a goal or a stale constraint:
      `rtl/pll.v` is generated for 50 MHz and `rtl/top.sv` never instantiates it,
      so the board runs the raw 25 MHz pin. Set the T5 target accordingly
- [ ] 2.5 Record whether the critical path is inside `cpu`. If it is not, the Fmax
      motivation is void and only decode extensibility justifies the change —
      re-scope before continuing
- [ ] 2.6 Check whether anything besides the CPU benefits from a higher clock (LCD
      serialiser, PSG `CLK_HZ` derivation, compositor line budget)
- [ ] 2.7 Determine whether PSG register reads have side effects, for the
      `sta PSG_CH,y` site at `src/main.asm:2479` — the corpus's only indexed MMIO
      access

## 3. New core, non-pipelined

- [x] 3.1 Write `rtl/cpu6502_decode.sv`: one row per opcode — addressing mode,
      operation, operand source and destination, flag write set — with a default
      row that traps
- [x] 3.2 Add a check that the decode table and `docs/opcodes.md` agree on every
      implemented opcode, failing on any disagreement. `make check-decode`,
      run as a prerequisite of `make test-65x02`. Against
      `tools/65x02/opcodes.txt` until `docs/opcodes.md` exists
- [x] 3.3 Write `rtl/cpu6502.sv`: registered address and write-data outputs, an
      addressing-mode sequencer, and the ALU. No pipelined decode yet.
      **Built as `rtl/cpu6502_core.sv` with a COMBINATIONAL address**, decided
      with the user: `ram_async` answers in the next cycle, so a registered
      address costs a second cycle on every data-dependent address and only
      overlapping instructions (phase 4) wins it back - roughly 2x the cycles
      in the meantime. The path is attacked by narrowing it instead (an 8-bit
      adder and a small mux). Registering it stays available if phase 2's
      measurement says the narrow path is not enough
- [x] 3.4 Compute the BCD adjust inside the ALU's registered stage from the
      pre-flop carry and half-carry — never as adders hanging off the flopped
      result on the way to the register file
- [x] 3.5 Expose `PC`, `S`, `A`, `X`, `Y`, `P` as a documented, synthesis-inert
      test interface
- [x] 3.6 Implement the undefined-opcode trap, sharing `TRAP` semantics with
      `add-isa-core-ergonomics`, and report opcode and `PC` in the simulator
- [x] 3.7 Pass Tiers 1 and 2 on the fast subset, then on the full 1.51 M sweep
      (**gate T1**)
- [x] 3.8 Record the non-pipelined core's cycle table and confirm static mean CPI
      ≤ 3.08 over the corpus. `docs/cpu-timing-v2.json`; static mean CPI
      **2.6234** over Breakout's 1,928 instructions against the old core's
      3.0334 (`make cpu-static-cpi`). Uniform mean over the 151 opcodes is
      3.278 vs 4.010 - 108 opcodes faster, 43 equal, none slower

### Phase 3 result

`make test-65x02 SST_CORE=v2 CASES=0`: **1,510,000 / 1,510,000 pass** Tiers 1
and 2, in 3.5 s - including the 529 `BRK` cases the Arlet core fails. Gate T1 is
met for the documented subset.

18.2% fewer cycles than NMOS across the 151 opcodes and 13.5% fewer than the old
core weighted by the corpus, with no opcode slower than NMOS. There are no dummy
cycles: no RMW dummy write, no un-indexed zero-page read, no page-cross penalty,
no dummy stack access.

Not yet done and not claimed: interrupts (accepted and ignored), the stall
testbench, and integration. `rtl/cpu6502_wrapper.sv` still points at Arlet.

## 4. Pipeline it

- [ ] 4.1 Design the global stall first, not last: a single `stall` term gating
      every state element including the write path, with a documented rule for what
      each register holds while stalled
- [ ] 4.2 Register the decode: latch the opcode and its decoded control signals, so
      no 256-way decode hangs off a memory output
- [ ] 4.3 Re-run the full sweep unchanged (**gate T1**) — this is the payoff of
      building the net first
- [ ] 4.4 Regenerate `docs/cpu-timing.json` and confirm CPI is still ≤ 3.08, or
      that T6 covers the difference in wall-clock terms
- [ ] 4.5 Write `rtl/cpu6502_stall_tb.sv`: drop `RDY` for 1..3 cycles in each
      reachable state and assert execution matches the unstalled run (**gate T7**)

## 5. Interrupts

- [ ] 5.1 Write `rtl/cpu6502_irq_tb.sv` covering `IRQ`/`NMI` entry, relative
      priority, `I`-flag masking, vector fetch, the `BRK`-vs-hardware `B`-flag
      distinction, and `RTI` (**gate T3**)
- [ ] 5.2 Note in `docs/cpu-core.md` that 65x02 does not cover interrupts, so T3 is
      the only evidence for this path
- [ ] 5.3 Decide whether to wire a real interrupt source now (the PPU frame signal)
      or leave `IRQ`/`NMI` tied low as `cpu6502_wrapper.sv:37-38` does today;
      `add-isa-frame-pointer` will need them

## 6. Integration

- [ ] 6.1 Point `rtl/cpu6502_wrapper.sv` at the new core, keeping the Arlet core
      behind an opt-in target for A/B comparison
- [ ] 6.2 Run Dormann's `6502_functional_test` and confirm Breakout runs and plays
      with the unmodified `rtl/ram.hex` (**gate T2**)
- [ ] 6.3 Verify the BCD score path specifically: `main.asm:1437` and the repeated
      decimal-addition loop at `main.asm:1481-1495`
- [ ] 6.4 Remove the `cpu_rdy` workaround at `rtl/memory_arbiter.sv:76-85`, let
      `dma_request` assert freely, and confirm DMA runs with the CPU mid-write
- [ ] 6.5 Update the comment block at `rtl/memory_arbiter.sv:76-84` to record that
      the limitation is fixed, and update `docs/hardware-gaps.md`
- [ ] 6.6 Run gates T4, T5, T6 and T8; record results against
      `docs/cpu-baseline.json`
- [ ] 6.7 Delete `rtl/cpu6502_arlet.sv` and `rtl/cpu6502_alu.sv` once all gates
      pass; freeze `docs/cpu-timing.json`

## 7. Coordination and documentation

- [ ] 7.1 Amend `add-isa-ergonomic-gates`: restate G4 against
      `docs/cpu-timing.json` in wall-clock time, and restate G7's compatibility
      clause as documented-subset conformance via 65x02 rather than NMOS binary
      compatibility and byte-identical builds
- [ ] 7.2 Add `refactor-cpu-core` to the roadmap table in
      `openspec/changes/add-isa-ergonomic-gates/design.md` at position 2 and
      renumber the slices after it
- [ ] 7.3 Re-derive the "Was" cycle columns in the `design.md` of
      `add-isa-core-ergonomics`, `add-isa-test-and-branch`, `add-isa-word-ops`,
      `add-isa-pointer-ops` and `add-isa-frame-pointer` against the frozen table
- [ ] 7.4 Write `docs/cpu-core.md`: the pipeline structure, what each register
      holds, the stall rule, the decode-table format and how a slice adds a row,
      the flag mask with reasons, and the cycle accounting
- [ ] 7.5 Record in `docs/opcodes.md` that the 105 undefined slots trap, and that
      the reservation policy still governs which a slice may claim
- [ ] 7.6 Decide the open question on generating both the customasm `#ruledef` and
      the decode table from `docs/opcodes.md`; if adopted, raise it as its own
      change rather than expanding this one
