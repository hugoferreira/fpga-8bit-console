## ADDED Requirements

### Requirement: Decoupled Instruction Fetch

The CPU SHALL fetch instruction bytes into a queue over a path that does not
consume data-access bandwidth, and SHALL decode from that queue.

#### Scenario: Data access does not stall fetch

- **WHEN** an instruction performs a data read or write
- **THEN** instruction bytes for following instructions continue to be fetched

#### Scenario: Queue supplies a whole instruction

- **WHEN** the queue holds at least as many bytes as the instruction requires
- **THEN** decode proceeds without waiting on memory

### Requirement: Prefetch Confined To Memory

The prefetcher SHALL NOT issue a read to any address outside the RAM region, and
SHALL stop at a peripheral window boundary rather than read across it.

#### Scenario: Code runs up to a peripheral window

- **WHEN** the program counter approaches `$4000` with the queue not full
- **THEN** no read is issued to `$4000` or beyond until execution reaches it

### Requirement: Queue Coherence

The queue SHALL be invalidated when a control transfer occurs, and when a write
targets an address whose byte the queue holds.

#### Scenario: Branch taken

- **WHEN** a branch is taken
- **THEN** bytes fetched from the not-taken path are discarded and none of them
  is executed

#### Scenario: Program modifies an instruction it has already fetched

- **WHEN** a store writes to an address currently held in the queue
- **THEN** the queue is invalidated and the instruction is re-fetched from memory

### Requirement: Conformance Distinguishes Prefetch

The conformance harness SHALL classify each memory access as an instruction's
own access or a prefetch, SHALL apply the existing access-footprint rule to the
former, and SHALL permit the latter only within the queue's reach in RAM.

#### Scenario: Prefetch beyond the instruction

- **WHEN** a case completes and the core has read bytes past `final.pc`
- **THEN** those reads do not fail the case, and are counted and reported

#### Scenario: Prefetch outside the queue's reach

- **WHEN** the core reads an address neither listed by the case nor within the
  queue's reach of `final.pc`
- **THEN** the case fails
