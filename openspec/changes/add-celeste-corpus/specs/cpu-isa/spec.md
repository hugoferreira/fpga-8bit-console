## ADDED Requirements

### Requirement: Multi-Corpus Gate Scoring

ISA ergonomic gates SHALL be scored over a set of corpora rather than a single
program, and every gate result SHALL be reported per corpus alongside the combined
verdict. Idiom counts SHALL NOT be pooled across corpora.

#### Scenario: Gate report names every corpus

- **WHEN** `make metrics` runs with more than one corpus registered
- **THEN** each gate's result is reported for each corpus individually, together
  with that corpus's instruction total, and then as a combined verdict

#### Scenario: Frequency threshold met in one corpus

- **WHEN** an instruction's replaced idiom clears the frequency threshold in one
  corpus and falls below it in another
- **THEN** the gate passes, and the asymmetry is recorded against that
  instruction's entry in the opcode registry

#### Scenario: Regression in any corpus fails

- **WHEN** a slice reduces instruction count or plumbing ratio in one corpus and
  worsens either in another
- **THEN** the gate fails and names the corpus that regressed

#### Scenario: Counts are not pooled

- **WHEN** an idiom occurs 5 times in one corpus and 5 times in another against a
  threshold of 8
- **THEN** the threshold is not treated as met, because counts are per corpus

### Requirement: Corpus Registry

The project SHALL maintain `docs/corpora.md` recording, for every corpus: what
program it is, which of its systems are implemented, which idioms it is well and
poorly suited to measure, and any deliberate divergence from the original work it
ports. A corpus SHALL NOT be used for gate scoring until it is registered.

#### Scenario: Partial port is declared as partial

- **WHEN** a corpus implements only part of the program it ports
- **THEN** the registry states which systems are present, so its idiom counts are
  not read as counts from a finished program

#### Scenario: Unregistered corpus is refused

- **WHEN** a program under `src/` is measured without an entry in the registry
- **THEN** the metrics run fails and names the unregistered corpus

#### Scenario: Divergence is recorded

- **WHEN** a port deliberately differs from the original in behaviour or
  presentation
- **THEN** the divergence is recorded in the registry and in the port's source
  header

### Requirement: Pre-Extension Corpus Baseline

A corpus SHALL be measured on the unextended ISA and its baseline recorded in
`docs/isa-baseline.json` as its own section, before any ISA extension is applied to
it. A corpus without a pre-extension baseline SHALL NOT be used to justify an
instruction.

#### Scenario: Baseline recorded before migration

- **WHEN** a new corpus is added
- **THEN** its instruction total, idiom counts and plumbing ratio on the unextended
  ISA are recorded before it is migrated to use any extension instruction

#### Scenario: Instruction justified without a baseline

- **WHEN** a slice cites idiom counts from a corpus that has no recorded
  pre-extension baseline
- **THEN** the gate fails, because the counts cannot be shown to predate the
  instruction they justify

### Requirement: Corpus Idiom Diversity

The corpus set SHALL between them exercise indirect dispatch through pointers,
multi-byte fixed-point arithmetic, and routine-local state in quantity — the idiom
families that the primary corpus does not contain. Where a corpus fails to produce
counts for one of these families, that absence SHALL be reported as a finding
rather than omitted.

#### Scenario: Weakly evidenced slice gains a pattern count

- **WHEN** a slice whose frequency evidence rests on rewrite measurement is scored
  against a corpus containing the relevant idiom
- **THEN** a literal pattern count is reported for that slice

#### Scenario: Idiom absent from every corpus

- **WHEN** an idiom family produces no counts in any registered corpus
- **THEN** the report states the absence explicitly, and instructions targeting
  that family remain justified only by rewrite measurement
