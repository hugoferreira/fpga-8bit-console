## ADDED Requirements

### Requirement: Documented Instruction Subset

The CPU SHALL implement exactly the 151 documented NMOS 6502 opcodes, as
enumerated in `docs/opcodes.md`, plus any opcodes claimed by a landed ISA
extension. Undocumented NMOS opcodes SHALL NOT be implemented, and NMOS defects —
including the `JMP ($xxFF)` page wrap and the read-modify-write double write —
SHALL NOT be reproduced.

#### Scenario: Undocumented opcode is not emulated

- **WHEN** an opcode outside the documented set and unclaimed by any ISA extension
  is executed
- **THEN** the core does not perform the corresponding NMOS undocumented operation

#### Scenario: Documented opcode behaves as documented

- **WHEN** any of the 151 documented opcodes is executed in any addressing mode
- **THEN** its architectural effect matches the golden test suite under the
  declared flag mask

#### Scenario: Extension opcode supersedes the trap

- **WHEN** an ISA extension claims a previously undefined opcode slot and lands
- **THEN** that opcode executes the extension instruction instead of trapping, and
  `docs/opcodes.md` records the claim

### Requirement: Undefined Opcode Trap

Executing an opcode that is neither documented nor claimed by a landed ISA
extension SHALL raise a diagnostic trap. The trap SHALL report the offending
opcode and program counter in the simulator and SHALL be inert on hardware. It
SHALL NOT halt the core in an unrecoverable state and SHALL NOT be silent.

#### Scenario: Wild jump lands on an undefined opcode

- **WHEN** the program counter reaches a byte that decodes to no defined
  instruction
- **THEN** the simulator reports the opcode and the address at which it was fetched

#### Scenario: Trap is inert on hardware

- **WHEN** the same undefined opcode is executed on the FPGA
- **THEN** the core continues in a defined state without external effect

### Requirement: Golden Suite Conformance

The CPU SHALL be verified against the SingleStepTests/65x02 `6502/v1` suite at a
pinned commit, over all 10,000 cases for each documented opcode. Two tiers SHALL
be mandatory and one SHALL be diagnostic only:

- **Tier 1 — architectural state.** For each case, the resulting `PC`, `S`, `A`,
  `X`, `Y`, masked `P` and every `ram` entry SHALL match the case's `final` state.
- **Tier 2 — access footprint.** The core SHALL NOT access any address absent from
  the case's `ram` lists.
- **Tier 3 — cycle-by-cycle bus trace.** Comparison against the case's `cycles`
  array SHALL be available as a diagnostic and SHALL NOT gate acceptance, because
  the core's timing is permitted to diverge from the NMOS.

Every reported result SHALL state how many cases per opcode were run.

#### Scenario: Full sweep gates a change to the core

- **WHEN** the core's structure changes and the full sweep is run
- **THEN** all documented opcodes pass Tiers 1 and 2, and the report states the
  case count and the pinned suite commit

#### Scenario: Stray access is caught

- **WHEN** the core reads or writes an address that the case's `ram` lists do not
  contain
- **THEN** Tier 2 fails and names the opcode, the case and the offending address

#### Scenario: Timing divergence does not fail the suite

- **WHEN** the core completes an instruction in a different number of cycles than
  the case's `cycles` array
- **THEN** Tiers 1 and 2 still pass, and the divergence is reported as
  informational

#### Scenario: Partial run is not reported as a full pass

- **WHEN** a reduced subset of cases per opcode is run
- **THEN** the result states the subset size and is not presented as full
  conformance

### Requirement: Declared Flag Mask

Only the `N`, `V`, `D`, `I`, `Z` and `C` flags SHALL be contractual. Flag results
that the NMOS 6502 leaves undocumented SHALL be excluded from conformance
comparison through an explicit mask table, each entry carrying a reason. The
harness SHALL count and report every mismatch that the mask suppresses.

#### Scenario: Undocumented decimal-mode flags are excluded

- **WHEN** `ADC` or `SBC` executes with the decimal flag set and the resulting `N`
  or `V` differs from the suite's expectation
- **THEN** the case is not failed, and the suppression is counted against that mask
  entry

#### Scenario: Suppression counts are visible

- **WHEN** a conformance run completes
- **THEN** it reports the number of mismatches suppressed per mask entry, so a
  growing count is visible rather than silent

#### Scenario: Documented flag mismatch always fails

- **WHEN** a documented flag differs from the suite's expectation outside a mask
  entry's stated scope
- **THEN** the case fails

### Requirement: Interrupt Verification

Because the golden suite executes single instructions and does not cover interrupt
entry, interrupt behaviour SHALL be verified by directed tests covering `IRQ` and
`NMI` entry, relative priority, `I`-flag masking, vector fetch, the distinction
between a `BRK`-pushed and a hardware-pushed `B` flag, and `RTI`.

#### Scenario: Masked IRQ is deferred

- **WHEN** `IRQ` is asserted while the `I` flag is set
- **THEN** the core continues executing and takes the interrupt only after the `I`
  flag is cleared

#### Scenario: NMI takes priority

- **WHEN** `IRQ` and `NMI` are asserted in the same cycle
- **THEN** the core services `NMI` first and `IRQ` afterwards

#### Scenario: BRK is distinguishable from a hardware interrupt

- **WHEN** a handler inspects the pushed processor status
- **THEN** it can distinguish a `BRK`-originated entry from a hardware-interrupt
  entry

### Requirement: Existing Program Compatibility

The console's current software SHALL continue to run on the new core without
modification or reassembly, and a whole-program conformance test SHALL pass. This
requirement is about the software this console actually runs; it does not extend
to NMOS binary compatibility in general.

#### Scenario: Game runs unmodified

- **WHEN** the pre-change `rtl/ram.hex` is loaded without reassembly
- **THEN** the game runs and plays

#### Scenario: Whole-program conformance test passes

- **WHEN** `make test` runs the 6502 functional conformance test
- **THEN** it reaches its success trap and the target exits non-zero on any
  reported failure

#### Scenario: Decimal arithmetic still works

- **WHEN** the game's BCD score is incremented through a decimal-mode `ADC` carry
  chain
- **THEN** the resulting score bytes and carry match the pre-change core

### Requirement: Declared Per-Opcode Cycle Table

The project SHALL maintain `docs/cpu-timing.json`, a per-opcode cycle count
generated by the cycle testbench rather than written by hand. It SHALL be the
authoritative baseline that ISA instruction budgets are scored against, replacing
published NMOS cycle counts for that purpose.

#### Scenario: Cycle count changes without the table

- **WHEN** a change alters any opcode's measured cycle count and
  `docs/cpu-timing.json` is not updated in the same commit
- **THEN** the cycle testbench fails and names the opcodes that disagree

#### Scenario: Table is generated, not authored

- **WHEN** the cycle testbench is run against an unmodified core
- **THEN** it reproduces `docs/cpu-timing.json` exactly

### Requirement: Wall-Clock Non-Regression

CPU performance SHALL be scored in wall-clock time, not in cycles. For every
opcode, `cycles_after / Fmax_after` SHALL be less than or equal to
`cycles_before / Fmax_before` against the recorded baseline, the static mean cycles
per instruction over the corpus SHALL NOT exceed the recorded baseline, and the
frame-work window SHALL NOT increase when expressed in microseconds at a stated
clock frequency.

#### Scenario: Added cycle paid for by a higher clock

- **WHEN** a change adds cycles to an instruction and raises achieved Fmax by more
  than enough to cover them
- **THEN** the gate passes and the report states both the cycle cost and the
  wall-clock gain

#### Scenario: Added cycle not paid for

- **WHEN** a change adds cycles and the Fmax gain does not cover them
- **THEN** the gate fails, naming the opcodes that got slower in wall-clock terms

#### Scenario: Frame-work window measured in time

- **WHEN** the frame-work counter is reported for a fixed input replay
- **THEN** it is expressed in microseconds at a stated clock and compared against
  the recorded baseline in the same unit

### Requirement: Timing Closure Reporting

The build SHALL provide a `make timing` target that completes a place-and-route run
and reports achieved Fmax together with the longest paths attributed to their owning
module. It SHALL exit non-zero when the achieved frequency misses the declared
constraint.

#### Scenario: Constraint missed

- **WHEN** the achieved frequency is below the declared target frequency
- **THEN** `make timing` exits non-zero and prints the failing path

#### Scenario: Critical path attributed outside the CPU

- **WHEN** the longest reported path neither originates in, terminates in, nor
  traverses the `cpu` hierarchy
- **THEN** the report names the module that owns the path, so CPU work can be ruled
  out as the remedy

#### Scenario: Baseline is recorded

- **WHEN** a timing run completes
- **THEN** achieved Fmax, the top paths with attribution, and cell utilisation are
  recorded in `docs/cpu-baseline.json`

### Requirement: Registered Memory Interface

The CPU SHALL present its address bus and write data from registers. There SHALL be
no combinational path from memory read data to the memory address within a single
clock period. The core SHALL perform at most one memory access per clock cycle, and
the arbiter, DMA controller and peripheral register windows SHALL require no change
to their access protocol.

#### Scenario: No read-data-to-address path

- **WHEN** the synthesised netlist is inspected for a combinational route from the
  read-data input to the address output
- **THEN** no such route exists

#### Scenario: One access per cycle preserved

- **WHEN** the core executes any instruction
- **THEN** it issues at most one memory access per clock cycle, and peripherals
  observe a valid access sequence

### Requirement: Stall Correctness At Every Cycle Boundary

De-asserting `RDY` SHALL suspend the CPU cleanly at any cycle boundary, including
during a write cycle. On re-assertion the core SHALL resume with no bus access lost,
duplicated or reordered, and with no change to architectural state caused by the
stall.

#### Scenario: Stall during a write cycle

- **WHEN** `RDY` is de-asserted while the core is performing a write
- **THEN** the write is presented to memory exactly once, and execution resumes at
  the following cycle with correct `PC` and register state

#### Scenario: Stall in every state

- **WHEN** the directed stall test de-asserts `RDY` for one or more cycles in each
  reachable state of the core
- **THEN** the resulting execution is identical to the unstalled execution

#### Scenario: DMA asserts without restriction

- **WHEN** the DMA controller requests the bus at an arbitrary cycle, with the
  arbiter's write-cycle workaround removed
- **THEN** the CPU stalls and resumes correctly and the program continues to run

### Requirement: Extensible Decode Table

The opcode decode SHALL be expressed as a table in a dedicated source file, one row
per opcode, so that an ISA extension adds rows rather than amending scattered
pattern matches. The table SHALL be reviewable against `docs/opcodes.md`.

#### Scenario: Extension adds rows only

- **WHEN** an ISA extension slice adds instructions that reuse existing addressing
  modes
- **THEN** the change to the core is limited to new rows in the decode table

#### Scenario: Table and registry agree

- **WHEN** the decode table and `docs/opcodes.md` are compared
- **THEN** every implemented opcode appears in both with the same mnemonic and
  operand encoding, and any disagreement fails the check

### Requirement: Register State Test Interface

The core SHALL expose its architectural registers — `PC`, `S`, `A`, `X`, `Y`, `P` —
as named signals that a simulation harness can read and force, so that
single-instruction conformance cases can establish initial state directly. This
interface SHALL exist for verification only and SHALL NOT alter synthesised
behaviour.

#### Scenario: Harness establishes initial state

- **WHEN** a conformance case specifies initial register values
- **THEN** the harness forces them directly, without executing a preamble that
  would perturb the flags being set

#### Scenario: Interface is inert in synthesis

- **WHEN** the design is synthesised
- **THEN** the test interface adds no logic and no ports to the hardware build

### Requirement: Area Budget

The CPU SHALL fit within a declared LUT and flip-flop budget recorded in
`docs/cpu-baseline.json`, and the whole design SHALL continue to fit the target
device with stated headroom for planned ISA extensions.

#### Scenario: Budget exceeded

- **WHEN** a change pushes CPU LUT or flip-flop usage past the declared budget
- **THEN** the area check fails and reports both the budget and the actual usage

#### Scenario: Device still fits with headroom

- **WHEN** the design is placed and routed after the change
- **THEN** utilisation is reported and the remaining headroom is stated against the
  planned ISA extension work
