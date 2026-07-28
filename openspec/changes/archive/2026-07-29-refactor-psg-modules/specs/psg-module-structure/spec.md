# psg-module-structure

The functional decomposition of the PSG: module boundaries, shared-resource
interface contracts, composition, and the netlist-neutrality gates that
every structural change to the PSG's RTL must pass.

## ADDED Requirements

### Requirement: Functional module boundaries follow process ownership

The PSG SHALL be composed of functional submodules in which every register
is written by exactly one submodule — the one owning the process that
writes it today — with cross-module reads carried on ports and no
cross-module writes. The submodule set SHALL be: timing
(`psg_timing`), audio RAM and its shared read port (`psg_aram`), multiply
service (`psg_mulsvc`), divide service (`psg_divsvc`), scheduled record
store (`psg_state_mem`), computed wave layer (`psg_wave`), per-sample
synthesis walk (`psg_walk`), tick sequencer (`psg_seq`), with `psg`
remaining the top-level composition owning the CPU read mux and `dbg`.

#### Scenario: A register has one writing module

- **WHEN** any register or memory in the flattened netlist is traced to
  its driving process
- **THEN** that process lives in exactly one submodule, and every other
  module that consumes the value reads it through a port

#### Scenario: External interface is unchanged

- **WHEN** `psg` is instantiated by `rtl/chip.sv`, `rtl/target_psg.sv`,
  `rtl/psg_tb.sv` or `sim/psg_wav.cpp`
- **THEN** its port list, parameters and reset/CPU-visible behavior are
  identical to the pre-refactor module, and none of those consumers
  require edits to compile (testbench hierarchical binds excepted)

### Requirement: Shared resources are single-instance module interfaces

The shared multiply service, divide service, scheduled record store port
pair, and audio RAM read port SHALL each exist exactly once, inside their
owning submodule, with every requester reaching them through explicit
request/response ports. The walk-freeze contract
(`walk_frozen = seq_frozen | prun | state_replay | fold_busy`) SHALL be
formed at the top level from its owners' exported terms.

#### Scenario: One multiplier serves both walks

- **WHEN** the sequencer's effect microprogram and the sample walk both
  require products in the same sample interval
- **THEN** both are served by the single `psg_mulsvc` instance through
  the merged request interface, with the walk's request taking priority
  exactly as the pre-refactor mux resolved it

#### Scenario: Record store priority is structural

- **WHEN** the sample walk and the tick engine both present `state_m`
  requests
- **THEN** `psg_state_mem` applies the fixed pre-refactor priority
  (sample write-back, then tick/engine) through its two owner bundles,
  and the store still infers as one simple-dual-port block RAM

### Requirement: Structural changes pass the netlist-neutrality gates

Any change restructuring the PSG's RTL without intending behavioral
change SHALL pass, per landed stage: (1) a pre-mapping structural stat
whose FLOP COUNT is exactly equal to the previous stage's, with the cell
delta measured and quoted; (2) seed-1 placed LC measured against the
7,224 anchor with successful fit and routed Fmax at or above 28.125 MHz;
(3) all 59 oracle WAVs byte-identical to
`build/psg_oracle/adopt-exact/rtl`; (4) `psg_tb` reporting ALL TESTS
PASSED; (5) zero Verilator warnings in the psg_tb, standalone-psg and
`REALTIME_PREVIEW=1` lint configurations.

Gates 3, 4 and 5 are EXACT and are what convict a behavioural change.
Gate 1's flop count is exact and is what convicts duplicated or lost
state. The cell census and the placed LC are measurements to be recorded
and justified, not equalities: the pre-mapping census is NOT invariant
under a pure verbatim move, because flattening restores the netlist but
not the optimiser's sharing order, and a module boundary can break a
carry chain that used to span it.

#### Scenario: A stage lands

- **WHEN** an extraction stage is committed
- **THEN** the commit message quotes the five gate results including the
  synthesis fingerprint, the cell and placed-LC deltas, and the exact
  gates are green

#### Scenario: A cell-count delta appears

- **WHEN** the structural stat after an extraction differs from the
  previous stage in any cell row
- **THEN** the delta is recorded in the commit message with its
  signature (which cell types moved) and an account of what caused it;
  a delta whose cause cannot be accounted for, or any change in the flop
  count, blocks the stage until the extraction is respelled
  (wire-bit deltas from port nets are recorded, not blocking)

### Requirement: Composition preserves single-include consumption

The PSG SHALL remain consumable by a single `` `include "psg.sv" ``:
`psg.sv` includes its submodule files, every new file carries an include
guard, and listing a submodule file explicitly alongside `psg.sv` SHALL
be harmless.

#### Scenario: Existing consumers build unchanged

- **WHEN** `rtl/chip.sv` or `rtl/target_psg.sv` is compiled exactly as
  before the refactor
- **THEN** the full module set resolves through the existing single
  include with no duplicate-definition errors

### Requirement: Testbench observability survives extraction

Every hierarchical bind `rtl/psg_tb.sv` makes into the PSG SHALL resolve
after each stage — either unchanged (the signal remains top-level
interconnect) or re-pointed to the owning submodule instance in the same
stage that moves the signal.

#### Scenario: A bound register moves

- **WHEN** a stage moves a register or memory that `psg_tb` binds (e.g.
  `state_m`, `crom`, `sst`, `fmc`)
- **THEN** the same stage re-points the bind to the new instance path,
  and the testbench compiles and passes in that stage's gate run
