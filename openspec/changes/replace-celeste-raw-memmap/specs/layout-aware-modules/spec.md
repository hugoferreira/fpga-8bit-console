## MODIFIED Requirements

### Requirement: Bounded Module Expansion
Module processing SHALL use caller-owned storage and explicit capacities for
module records, dependency edges, include depth, per-module source bytes and
the persistent semantic tables. It SHALL traverse modules with an explicit
stack and SHALL NOT require a buffer proportional to total expanded source
bytes or total expanded lines.

#### Scenario: Capacity is exact
- **WHEN** an input graph uses exactly each configured module, edge, depth,
  per-module and semantic-table capacity
- **THEN** translation succeeds without requesting more storage

#### Scenario: Total graph exceeds 16-bit byte count
- **WHEN** total source across replayable modules exceeds 65,535 bytes while
  every bounded record and individual module fits
- **THEN** module processing succeeds because total expanded bytes are not a
  storage capacity

#### Scenario: Capacity is exceeded
- **WHEN** one additional module, dependency edge, include level, per-module
  byte or semantic record is required
- **THEN** translation fails with a stable diagnostic naming the exhausted
  resource, actual value and configured limit

## ADDED Requirements

### Requirement: Deterministic Replayable Module Passes

The module layer SHALL expose the discovered graph to each fixed semantic pass
in the same deterministic depth-first order. Every source view SHALL remain
immutable and replayable for the duration of compilation. Includes SHALL act
as graph traversal points rather than copied source text.

#### Scenario: Forward reference crosses modules

- **WHEN** an early module refers to a declaration in a later included module
- **THEN** declaration discovery visits the complete graph before resolution
  and the reference resolves with whole-program semantics

#### Scenario: Module is replayed

- **WHEN** layout resolution and emission revisit the same module
- **THEN** they observe identical source bytes, source id and original line
  numbers

#### Scenario: Source view changes during compilation

- **WHEN** a resolver cannot guarantee an immutable replayable view
- **THEN** compilation fails through the source-provider contract rather than
  mixing passes from different source states

### Requirement: Direct Source Correlation Without Flattening

The active module cursor SHALL attach the current source id and original line
number directly to diagnostics and semantic events. Source-map correctness
SHALL NOT depend on an expanded-line origin table.

#### Scenario: Included operation is emitted

- **WHEN** a typed operation on line 27 of an included module is emitted
- **THEN** its event and host source-map entry identify that module and line 27

#### Scenario: Include directive fails

- **WHEN** a missing or cyclic include is encountered
- **THEN** the diagnostic identifies the including module and the original
  include line
