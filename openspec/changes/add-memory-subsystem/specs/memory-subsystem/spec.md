## ADDED Requirements

### Requirement: Memory Interface Abstraction

The console SHALL access main memory through a single interface that names a
request (address, write enable, write data) and a response (read data, an
acknowledgement, and a stall). No module outside a backend SHALL depend on the
storage technology behind it.

#### Scenario: Backend is substituted

- **WHEN** the BRAM backend is replaced by the SDRAM backend
- **THEN** no change is required in the CPU, the arbiter, the PPU or the PSG

#### Scenario: Simulation does not model SDRAM

- **WHEN** the console is simulated
- **THEN** main memory is a flat array behind the same interface, and no SDRAM
  timing is modelled

### Requirement: Whole-Chip Placement

The design SHALL place and route for the target device with the main memory
resident in the board's external RAM rather than in fabric.

#### Scenario: Synthesis completes

- **WHEN** `make bin/toplevel.asc` is run for `hx8k`
- **THEN** it completes, and reports BRAM utilisation within the device's 32
  blocks

#### Scenario: Timing is reportable

- **WHEN** `make timing` is run
- **THEN** it reports achieved Fmax and the critical path with its owning module,
  and exits non-zero if the achieved frequency misses the target

### Requirement: Stalling On Memory

The memory subsystem SHALL stall the CPU when it cannot answer within one CPU
cycle, and the CPU SHALL resume with every access performed exactly once, in
order.

#### Scenario: Row miss

- **WHEN** an access addresses a row that is not open
- **THEN** the CPU is stalled for the duration of the precharge and activate, and
  the access completes exactly once

#### Scenario: Refresh during a write

- **WHEN** an auto-refresh falls due while the CPU is mid-write
- **THEN** the write is performed exactly once, after the refresh, with the
  address and data it was issued with

### Requirement: Hot Pages Remain On-Chip

Zero page and the stack SHALL be served from on-chip memory.

#### Scenario: Zero-page indirect access

- **WHEN** the CPU executes `(zp),Y`
- **THEN** the pointer fetch is served from on-chip memory and does not disturb
  any open SDRAM row
