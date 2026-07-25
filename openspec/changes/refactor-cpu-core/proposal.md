## Why

The console runs Arlet Ottens' 6502 (`rtl/cpu6502_arlet.sv`, 1240 lines, a
50-state microcoded FSM). It has two problems, and they have the same root.

**It cannot close timing, because it has no pipeline register between itself and
memory.** The data that arrives from RAM in cycle *N* combinationally determines
what the CPU asks RAM for in cycle *N+1*:

| Unregistered path | Route | Evidence |
| --- | --- | --- |
| read data → next address | `ram_async` registered output → arbiter 4-way read mux → `DIMUX` → 12-arm `AB` mux → arbiter bus mux → BRAM address port | `ram_async.sv:42`, `memory_arbiter.sv:162`, `cpu6502_arlet.sv:858`, `cpu6502_arlet.sv:329-390` |
| read data → decode → next state | same, up to `DIMUX` → `IR` → **17** separate `casex(IR)` decoders → state and control flops | `cpu6502_arlet.sv:838`, `cpu6502_arlet.sv:875-969` |
| read data → ALU → flags | `DIMUX` → `BI` mux → 8-bit adder with BCD half-carry → ALU flops | `cpu6502_alu.sv:96-111` |
| ALU result → BCD adjust → register file | `ADD` flop → `ADJH`/`ADJL` `casex` → two 4-bit adders → `AXYS` write | `cpu6502_arlet.sv:488-520` |

`AB = {ZEROPAGE, DIMUX}` and `AB = {DIMUX, ADD}` are the literal lines: every
zero-page and absolute addressing cycle routes a byte out of a BRAM, through
three muxes, and back into a BRAM address port inside one clock. The CPU shares
that clock with the PPU, the PSG and the LCD serialiser, so the cost is charged
chip-wide.

**It cannot absorb the ISA programme, because its decode is 17 scattered
`casex(IR)` blocks** that pattern-match bit fields of the NMOS encoding. The
seven `add-isa-*` slices add ~40 opcodes in two orthogonal columns (`$x3`,
`$xB`), a `$02` prefix page, 16-bit sequences up to 11 cycles, block copy and
fill that must be interruptible mid-instruction, and a new architectural register
that interrupts save and restore. Each of those is an amendment to all 17 blocks.

Retrofitting pipeline registers into that structure was the previous plan here.
It was the expensive way to solve both problems, for one reason: **there was no
regression net.** `make test` checks that `AB == $0300` after reset, prints trace
lines, and exits 0 whether it passed or failed (`cpu6502_tb.sv:88-101`). Every
step of a retrofit had to be justified by fear rather than by evidence.

### What changes the calculus: a per-opcode golden suite

[SingleStepTests/65x02](https://github.com/SingleStepTests/65x02) removes that
constraint. `6502/v1/` is **256 files, `00.json`–`ff.json`, 10,000 randomly
generated cases each — 1,082 MB, 2.56 M cases**, of which the **151 documented
opcodes account for 1.51 M**. Each case is one instruction with full state before
and after:

```
{ "name": …, "initial": { "pc":…, "s":…, "a":…, "x":…, "y":…, "p":…,
                          "ram": [[addr, value], …] },
             "final":   { … same shape … },
             "cycles":  [[address, value, "read"|"write"], …] }
```

and the suite's own rule — *"Any memory address not included in a test's `ram`
lists must not be accessed during that test"* — polices stray accesses without
requiring cycle-exactness.

Against that, a from-scratch core is *safer* than a retrofit, not riskier. The
class of bug a rebuild is feared for is exactly what 10,000 cases per opcode
catches immediately: the indirect-addressing regression fixed in `1c6f5e3`, where
`STA (zp),Y` took the next opcode as its target high byte, would die within the
first hundred cases of `91.json`.

### What the corpus licenses us to drop

Divergence from NMOS is only safe if nothing depends on what we drop. Measured
over `src/*.asm`:

- **No undocumented opcodes.** `ca65` cannot emit them, and the 47 `.byte`
  directives in `main.asm` are data tables (`nb_dr`, `nb_dc`, …), not encodings.
- **No read-modify-write on any MMIO window**, and exactly **one** indexed MMIO
  access in the whole corpus: `sta PSG_CH,y` at `main.asm:2479`, with `y` in
  0..3 against `$4110`, so it does not cross a page. NMOS spurious accesses have
  essentially no exposure to the PPU or PSG register windows.
- **Interrupts are entirely unused today.** `brk`, `sei` and `cli` appear zero
  times; `nmi_handler` and `irq_handler` are a bare `rti` each
  (`main.asm:2606-2609`); the vector table is `$0000, $0300, $0000`, so it does
  not even point at those handlers; and `cpu6502_wrapper.sv:37-38` ties `IRQ` and
  `NMI` to zero.

And one thing the corpus does **not** license us to drop:

- **Decimal mode is load-bearing.** The score is 3-byte BCD, updated through
  `sed`/`clc`/`adc` chains at `main.asm:1437` and again at `main.asm:1481` — the
  latter a multiply-by-repeated-addition loop (`score += points[type] × chain`).
  BCD arithmetic stays. What *can* go is the undocumented part: no branch in the
  corpus consumes `N`, `V` or `Z` from a decimal-mode `ADC`; only the carry chain
  and the result bytes are read.

## What Changes

- **Replace the core.** A new `rtl/cpu6502.sv`, written for this console rather
  than adapted to it: registered address and write-data outputs, a registered
  decode, a table-driven decoder that an ISA slice extends by adding rows, and a
  global stall that is correct in every cycle. `cpu6502_arlet.sv` and
  `cpu6502_alu.sv` stay in tree behind an opt-in target for A/B comparison until
  the new core passes its gates, then are deleted.
- **BREAKING (CPU behaviour, deliberately)**: the new core implements **the 151
  documented NMOS opcodes and no others**. The 105 undefined slots are not
  emulated. NMOS bug-compatibility — the `JMP ($xxFF)` page wrap, the RMW
  double-write, undocumented flag results — is **not** preserved. This is safe for
  this console and for nothing else; the corpus evidence above is the
  justification.
- **Undefined opcodes trap instead of jamming.** Any opcode neither in the
  documented set nor claimed by an ISA slice raises the diagnostic trap that
  `add-isa-core-ergonomics` introduces as `TRAP #imm`: loud, reported by the
  simulator with the offending `PC`, inert on hardware. A wild jump or a
  mis-assembled byte becomes a diagnostic instead of undefined behaviour.
- **65x02 becomes the conformance gate, in three tiers**, because the suite
  specifies more than we intend to promise:
  - **Tier 1 — architectural state (mandatory).** `initial` → `final` for `PC`,
    `S`, `A`, `X`, `Y`, the masked `P`, and every `ram` entry. Timing-free.
  - **Tier 2 — access footprint (mandatory).** No address outside the case's
    `ram` list may be accessed. This is what protects the memory-mapped PPU and
    PSG from stray reads and writes, and it is also timing-free.
  - **Tier 3 — cycle-exact bus trace (diagnostic, never a gate).** The full
    `cycles` array, used during bring-up and to explain a Tier 1/2 failure. The
    new core is explicitly free to diverge in timing.
- **A declared flag mask, with masked disagreements reported rather than
  hidden.** Only `N`, `V`, `D`, `I`, `Z`, `C` are contractual. Excluded: `N` and
  `V` after `ADC`/`SBC` with `D=1`, and `P` bits 4–5 outside a pushed `P`. The
  harness counts every masked-out mismatch, so an exclusion cannot quietly grow
  into a bug.
- **Interrupts get their own directed tests**, because 65x02 is
  single-instruction and does not cover `IRQ`/`NMI` entry at all. They must work
  regardless: the PPU has a frame signal, and `add-isa-frame-pointer` requires `F`
  to be saved and restored across interrupt entry.
- **Klaus Dormann's `6502_functional_test` is kept** as a second, whole-program
  gate. It catches sequence- and interaction-level faults that a
  single-instruction suite structurally cannot.
- **The cycle model becomes a design variable with a declared target** rather than
  an inheritance. Dropping bug-compatibility makes NMOS's wasted cycles
  recoverable — the RMW dummy write, the indexed and branch page-cross penalties.
  The honest size of that prize is small: 38 RMW sites in the corpus, ~0.6% of
  static cycles. The real value is that the new core is not *forced* to pay
  +1 CPI for a registered decode, the way the retrofit plan was.
- **The timing and area gates survive unchanged** from the retrofit plan:
  `make timing` reporting achieved Fmax with module attribution, a per-opcode
  cycle table, wall-clock non-regression, and an area budget with headroom for the
  remaining ISA slices.

## Impact

- Affected specs: `cpu-microarchitecture` (new capability)
- Affected code: `rtl/cpu6502.sv` (new core), `rtl/cpu6502_decode.sv` (new decode
  table), `rtl/cpu6502_arlet.sv` and `rtl/cpu6502_alu.sv` (retired, then deleted),
  `rtl/cpu6502_wrapper.sv`, `rtl/memory_arbiter.sv` (stall handshake),
  `tools/65x02/` (new harness), `rtl/cpu6502_irq_tb.sv` (new), `Makefile`
  (`timing`, `test`, suite fetch and cache), `docs/cpu-core.md`,
  `docs/cpu-timing.json`, `docs/cpu-baseline.json`
- **Renamed** from `add-cpu-pipeline`: the pipeline is still the goal, but the
  deliverable is a new core and the change id should say so.
- Depends on: nothing blocking. The 65x02 harness replaces Klaus Dormann as the
  critical prerequisite, so this no longer waits on `add-isa-ergonomic-gates` —
  though G8's `--metrics` frame-work counter is still wanted for the wall-clock
  gate, and `TRAP` semantics are shared with `add-isa-core-ergonomics`.
- Blocks: `add-isa-core-ergonomics` and every slice after it. They should be
  written against the new decode table, not against 17 `casex` blocks.
- **Requires an amendment to `add-isa-ergonomic-gates`**: gate **G4** is
  denominated in NMOS cycle counts and gate **G7** promises byte-identical builds
  and NMOS binary compatibility. Both assumptions are void by intent. G4 should be
  restated against `docs/cpu-timing.json` in wall-clock time; G7's compatibility
  clause should become documented-subset conformance via 65x02. The opcode
  registry's reservation policy is unaffected and still governs.
- The 1,082 MB suite is **not vendored**: fetched and cached, with a fast subset
  (N cases per opcode) for routine runs and the full 1.51 M-case sweep gated per
  phase.
- Proposed roadmap position: **2**, after `add-isa-ergonomic-gates` and parallel
  with `add-custom-assembler`.
