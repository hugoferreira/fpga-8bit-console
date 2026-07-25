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
      (`synthesis.log` currently ends mid-optimisation) and record the wall time.
      **BLOCKED, and not by the CPU.** `rtl/ram_async.sv` models the 64 KB main
      memory as an on-chip array; hx8k has 16 KB of BRAM in total, so yosys
      emits 1,727,271 AND gates and never finishes ABC9. That memory belongs
      behind a memory interface with the board's external RAM under it — no
      such abstraction exists and `rtl/top.pcf` has no memory pins
- [x] 2.2 Rewrite `make timing` to report achieved Fmax plus the top-10 critical
      paths with the owning module for each, and to exit non-zero when the achieved
      frequency misses `TARGET_FREQ`. Done, and `make cpu-fmax` added — the only
      timing measurement available until 2.1 unblocks
- [~] 2.3 Record achieved Fmax, the attributed paths and `make stat` utilisation in
      `docs/cpu-baseline.json`, including the CPU's own LUT/DFF count as the T8
      budget. **Core-only figures recorded** (old 50.97 MHz / 818 LC, new
      37.94 MHz / 1323 LC); whole-chip figures blocked on 2.1
- [x] 2.4 Resolve whether `TARGET_FREQ = 50` is a goal or a stale constraint:
      `rtl/pll.v` is generated for 50 MHz and `rtl/top.sv` never instantiates it,
      so the board runs the raw 25 MHz pin. Set the T5 target accordingly.
      **Aspirational.** The board meets 25 MHz and both cores close timing
      there. T5 should be stated against 25 MHz until a PLL is actually
      instantiated
- [~] 2.5 Record whether the critical path is inside `cpu`. If it is not, the Fmax
      motivation is void and only decode extensibility justifies the change —
      re-scope before continuing. **Unanswerable whole-chip** (see 2.1). Measured
      core-only: the new core's critical path starts at the memory read data and
      runs through the combinational decode; the old core's starts at a
      registered decode signal. So the path IS in the CPU — but the new core
      currently makes it worse, not better
- [x] 2.6 Check whether anything besides the CPU benefits from a higher clock (LCD
      serialiser, PSG `CLK_HZ` derivation, compositor line budget). PSG and UART
      are parameterised and clock-portable; only the LCD serialiser and the
      compositor's line budget gain
- [x] 2.7 Determine whether PSG register reads have side effects, for the
      `sta PSG_CH,y` site at `src/main.asm:2479` — the corpus's only indexed MMIO
      access. **No side effects**: the CPU-interface block only assigns `dout`

### Phase 2 result

Two findings, both load-bearing.

**The chip does not place, and the CPU is not why.** The 64 KB main memory is
modelled on-chip against an hx8k's 16 KB of BRAM, so yosys emits 1.7 M AND gates
and never finishes. It needs a memory abstraction with the board's external RAM
behind it. T4, T5 and T8 are blocked on that, not on this change.

**Core-only, the new core is 26% slower and 62% larger** — 37.94 MHz / 1323 LC
against 50.97 MHz / 818 LC. Its critical path starts at the memory read data and
runs through the combinational decode into the ALU; the old core's starts at a
*registered* decode signal. Decoding and executing in the cycle the byte arrives
is what buys implied instructions their single cycle, and it is being paid for
in Fmax.

At the board's real 25 MHz both cores close timing, so today the new core's
15.6% lower CPI is a straight 15.6% throughput win. At each core's own Fmax the
ranking inverts by 14%. Task 4.2 (register the decode) is therefore no longer a
speculative improvement — it is the measured fix, and inferring the 256 x 22-bit
table as a BRAM ROM would register it and return most of the extra logic cells
at the same time.

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

- [x] 4.1 Design the global stall first, not last: a single `stall` term gating
      every state element including the write path, with a documented rule for what
      each register holds while stalled. **Done, and it found a real defect**:
      the RAM's read port keeps clocking while the CPU is held, so the byte
      answering the pending request is overwritten by the answer to the address
      the stalled core is still presenting. Without a hold register, RDY
      silently corrupts the instruction in flight — 22,537 of 30,200 cases
      failed. `di_hold`/`di_held` latch DI on the first stalled cycle
- [x] 4.2 Register the decode: latch the opcode and its decoded control signals, so
      no 256-way decode hangs off a memory output. Split in two: `dec_c` is
      combinational and used only in S_DECODE to pick the next state and the
      register a push reads; `dec_r` is registered and feeds everything that
      reaches the ALU, the flags or a store. Implied/accumulator instructions
      moved to S_IMP and cost one more cycle. **Fmax 37.94 → 50.18 MHz, +32%**
- [x] 4.3 Re-run the full sweep unchanged (**gate T1**) — this is the payoff of
      building the net first. **1,510,000 / 1,510,000 pass**, unchanged
- [x] 4.4 Regenerate `docs/cpu-timing.json` and confirm CPI is still ≤ 3.08, or
      that T6 covers the difference in wall-clock terms. Static mean CPI
      2.6234 → **2.7552**, still 9.2% inside the old core's 3.0334, and
      wall-clock is ahead on both clocks (see the phase 4 result)
- [x] 4.5 Write `rtl/cpu6502_stall_tb.sv`: drop `RDY` for 1..3 cycles in each
      reachable state and assert execution matches the unstalled run (**gate T7**).
      **Done as `make test-65x02 STALL=N` rather than a directed testbench.**
      Dropping RDY for 1..3 cycles at a pseudo-random 1-in-N rate across the
      whole 65x02 sweep reaches every state the suite reaches and checks the
      full architectural result of each, not just that execution "matches":
      **1,510,000 / 1,510,000 pass with 5,470,098 stall cycles injected**, and
      `WE` asserted while `RDY` is low is itself a failure. A directed
      testbench over 50 states could not have covered as much

### Phase 4 result

Registering the decode was the measured fix and it delivered: **Fmax 37.94 →
50.18 MHz, +32%** (mean of three placement seeds), for 0.13 cycles of static CPI.
The remaining path is `memory → decode table → next state`; the ALU and flag
paths now start at a flop.

Against the core being replaced: 50.18 vs 53.01 MHz Fmax (−5%), 2.7552 vs 3.0334
static CPI (−9.2%), which is **+4.2% instructions per second at each core's own
Fmax and +10.1% at the board's actual 25 MHz**. Area is the remaining
regression: 1378 vs 818 logic cells (+68%), which the BRAM-ROM idea in phase 2's
notes would address if T8 ever binds.

Gate T7 is met, and getting there found a real defect that a directed testbench
would have been unlikely to reach — see task 4.1.

## 5. Interrupts

> **Note, before anyone starts here.** Two things changed under this section.
>
> 1. **`add-memory-subsystem` makes the interrupt path harder to get right, and
>    should probably land first.** External memory means row misses and refresh
>    stall the CPU, so an interrupt can now arrive while the core is held. The
>    entry sequence has to be correct across a stall, not just in isolation.
>    Gate T7 already covers stalls for ordinary instructions
>    (`make test-65x02 STALL=3`), but the suite contains no interrupt cases at
>    all, so nothing extends that evidence to the entry sequence.
> 2. **The harness can carry most of this.** `--stall` showed that driving a pin
>    across the whole 65x02 sweep finds what directed tests miss. The same trick
>    applies: assert `IRQ`/`NMI` pseudo-randomly and require that the *only*
>    difference from the unstalled run is a well-formed interrupt entry — vectors
>    fetched, `P` pushed with `B` clear, `I` set, `PC` correct. That is a much
>    stronger T3 than a directed testbench, and it reuses machinery that exists.
>
> The core accepts `IRQ` and `NMI` today and ignores them
> (`rtl/cpu6502_core.sv`, the `_unused` wire). Nothing is half-done.

- [ ] 5.1 Write `rtl/cpu6502_irq_tb.sv` covering `IRQ`/`NMI` entry, relative
      priority, `I`-flag masking, vector fetch, the `BRK`-vs-hardware `B`-flag
      distinction, and `RTI` (**gate T3**)
- [ ] 5.2 Note in `docs/cpu-core.md` that 65x02 does not cover interrupts, so T3 is
      the only evidence for this path
- [ ] 5.3 Decide whether to wire a real interrupt source now (the PPU frame signal)
      or leave `IRQ`/`NMI` tied low as `cpu6502_wrapper.sv:37-38` does today;
      `add-isa-frame-pointer` will need them

## 6. Integration

- [x] 6.1 Point `rtl/cpu6502_wrapper.sv` at the new core, keeping the Arlet core
      behind an opt-in target for A/B comparison. **Replaced outright** at the
      user's direction; the A/B was used to verify the swap and then removed
      with task 6.7
- [x] 6.2 Run Dormann's `6502_functional_test` and confirm Breakout runs and plays
      with the unmodified `rtl/ram.hex` (**gate T2**). Dormann trapped at
      **$3469, the success address, after 30,646,179 instructions**.
      `make test-functional` runs it; the binary is fetched to a cache outside
      the tree. Breakout runs, and every pixel matches the old core except the
      dust particles — `src/main.asm:153` seeds them from the free-running
      hardware LFSR `SPR_RND`, so any core with different timing reads a
      different seed. Verified by elimination: 30 pixels, all 2x2 blocks in
      exactly two colours, identical at frames 18-22 rather than drifting
- [x] 6.3 Verify the BCD score path specifically: `main.asm:1437` and the repeated
      decimal-addition loop at `main.asm:1481-1495`. Covered twice over:
      Dormann's decimal ADC/SBC test iterates every valid BCD operand pair with
      both carry inputs, and the score renders identically in the frame
      comparison
- [ ] 6.4 **Unblocked, and deliberately not done here.** The CPU limitation this
      worked around is gone — the core survives stalls at any point, proven over
      5,470,098 injected stall cycles. What remains is that letting DMA steal
      cycles mid-frame changes what the display sees, and there is no test
      covering DMA at all. Needs something watching before it is switched on.
      Remove the `cpu_rdy` workaround at `rtl/memory_arbiter.sv:76-85`, let
      `dma_request` assert freely, and confirm DMA runs with the CPU mid-write
- [x] 6.5 Update the comment block at `rtl/memory_arbiter.sv:76-84` to record that
      the limitation is fixed, and update `docs/hardware-gaps.md`. Comment
      updated; `docs/hardware-gaps.md` left alone - it is append-only and shared,
      and the entry there is the PPU/PSG agents' to keep
- [ ] 6.6 Run gates T4, T5, T6 and T8; record results against
      `docs/cpu-baseline.json`
- [x] 6.7 Delete `rtl/cpu6502_arlet.sv` and `rtl/cpu6502_alu.sv` once all gates
      pass; freeze `docs/cpu-timing.json`. **Deleted**, along with
      `cpu6502_defs.sv`, `cpu_reset_tb.sv`, `debug_test.sv` and the two
      `run_test*.sh` scripts that drove them. Not every gate passes — T3
      (interrupts) is unimplemented and T4/T5 are blocked on the device fit,
      which is not the CPU's doing — but the replacement was directed and the
      baseline numbers are recorded in `docs/cpu-baseline.json`. The files are
      at commit `ae37bbc` if they are ever wanted

### Phase 6 result

The console runs on the new core. `rtl/cpu6502_wrapper.sv` instantiates
`cpu6502_core`; `cpu6502_arlet.sv` and `cpu6502_alu.sv` are gone.

| Gate | State |
| --- | --- |
| T1 documented-subset conformance | **met** — 1,510,000 / 1,510,000 |
| T2 the console still works | **met** — Dormann to $3469, Breakout renders |
| T3 interrupts proven | not started; `IRQ`/`NMI` accepted and ignored |
| T4 critical path relocated | blocked — the design does not place |
| T5 Fmax | blocked — same |
| T6 wall-clock non-regression | **met** — +10.1% at the board clock |
| T7 stall correctness | **met** — 5,470,098 stall cycles injected |
| T8 area | **answered** — the CPU is 9% of the design |

Repairs made on the way through, all of which were pre-existing:

- `rtl/test_ram.hex` described a memory map in comments while `$readmemh` loaded
  it sequentially, so the "program at $0300" was at $0030 and the reset vector
  never reached $FFFC. Rewritten with `@` directives.
- `cpu6502_tb.sv` wired `rw` inverted against how `chip.sv` wires it, so the RAM
  never drove a read; compared with `!=` rather than `!==`, so an all-X bus
  reported PASSED; and asserted the PC's position at a fixed cycle count, which
  is an assertion about speed rather than correctness. All three fixed.
- `ram_async.sv` declared its parameters after the ports that used them, which
  iverilog cannot bind. `make test` now elaborates and passes for the first
  time in this repo's history.

## 7. Coordination and documentation

- [ ] 7.1 Amend `add-isa-ergonomic-gates`: restate G4 against
      `docs/cpu-timing.json` in wall-clock time, and restate G7's compatibility
      clause as documented-subset conformance via 65x02 rather than NMOS binary
      compatibility and byte-identical builds
- [ ] 7.2 Add `refactor-cpu-core` to the roadmap table in
      `openspec/changes/add-isa-ergonomic-gates/design.md` at position 2 and
      renumber the slices after it
- [~] 7.3 Re-derive the "Was" cycle columns in the `design.md` of
      `add-isa-core-ergonomics`, `add-isa-test-and-branch`, `add-isa-word-ops`,
      `add-isa-pointer-ops` and `add-isa-frame-pointer` against the frozen table.
      **Tool built and the answer measured** (`make isa-seq`,
      `tools/65x02/isa_seq.py`). The slices split cleanly:

      | idiom | now | NMOS | |
      | --- | --- | --- | --- |
      | `lda #/sta zp`, `lda zp/sta zp`, `clc/adc zp` | 5,6,5 | 5,6,5 | unchanged |
      | `lda zp/cmp #/bne` | 7.00 | 7.63 | −0.63 |
      | `inc zp/bne` | 6.00 | 7.63 | −1.63 |
      | `pha/…/pla` | 9.00 | 12.00 | **−3.00** |
      | `jsr/rts` | 8.00 | 12.00 | **−4.00** |

      So **slice 3 (`add-isa-core-ergonomics`) is unaffected** — its whole case
      is `lda`/`sta`/`clc`/`adc`, which sit at the bus floor on both cores.
      Slices 4-7 all lose margin, and slice 7 loses most: this core already
      removed a third of the cost of a call and half the cost of a push/pull,
      which is a large part of what a frame pointer was going to buy. Each
      slice's own `design.md` still needs its table restated - that is the
      remainder of this task
- [ ] 7.4 Write `docs/cpu-core.md`: the pipeline structure, what each register
      holds, the stall rule, the decode-table format and how a slice adds a row,
      the flag mask with reasons, and the cycle accounting
- [x] 7.5 Record in `docs/opcodes.md` that the 105 undefined slots trap, and that
      the reservation policy still governs which a slice may claim.
      `docs/opcodes.md` now exists and is generated (`make opcodes`): 151
      implemented, 58 reserved for 65C02 compatibility, 33 extension slots
      assigned, 14 unallocated. The generator fails on a policy conflict rather
      than emitting a registry that contradicts the hardware
- [ ] 7.6 Decide the open question on generating both the customasm `#ruledef` and
      the decode table from `docs/opcodes.md`; if adopted, raise it as its own
      change rather than expanding this one
