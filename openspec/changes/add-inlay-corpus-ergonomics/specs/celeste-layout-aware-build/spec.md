## ADDED Requirements

### Requirement: Staged Corpus Migration With Tracked Inventory
The Celeste production source SHALL adopt each ergonomics stage as it
lands, and the conformance inventory (exception count, residual raw
indexed accesses, typed operations, semantic offset queries) SHALL be
updated at each stage's commit with the direction of movement matching the
design's per-stage table. Behavioral acceptance at every stage SHALL be
the existing boot, framebuffer and PSG trace checkpoints plus forced-build
artifact determinism.

#### Scenario: Mask migration removes its exception category
- **WHEN** stage A migrates the complemented and composed mask sites to
  typed byte updates with bitwise constant operands
- **THEN** the "complemented target constant" and "mask constant remains
  target-owned" exception annotations are gone from production source and
  the frozen exception count decreases by the number of migrated sites

#### Scenario: Byte-neutral stages prove neutrality
- **WHEN** a stage documented as byte-neutral (namespace `using`/`export`
  adoption) completes
- **THEN** two forced production builds before and after produce the same
  ROM digest

#### Scenario: Scratch-safety audit for invoke adoption
- **WHEN** stage E converts a call site to `invoke` in a region with live
  `t0`-`t7` values
- **THEN** the site's recorded scratch usage is disjoint from the live
  scratch bytes, or the site is not converted

### Requirement: Metrics Registration Accompanies Each Operation
Every operation introduced by the ergonomics stages SHALL be registered in
the metrics parser and the conformance operation tuple in the same commit
that introduces it, so executable-byte accounting never drops expansion
bytes.

#### Scenario: Unregistered mnemonic fails conformance
- **WHEN** a production module uses a new mnemonic absent from the
  registered operation set
- **THEN** the conformance gate fails naming the mnemonic
