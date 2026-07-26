## ADDED Requirements

### Requirement: Canonical Inlay Module Names

Repository-owned Inlay modules SHALL use the `.inlay.asm` suffix. The module
frontend SHALL accept logical module names ending in either `.inlay.asm` or the
legacy `.la.asm` suffix and SHALL pass the exact requested logical name to the
module resolver.

Module suffixes SHALL NOT select a syntax, semantic or lowering mode. Legacy
module names SHALL remain supported until a separate specification change
explicitly removes them.

#### Scenario: A canonical Inlay module is included

- **WHEN** an entry module contains `include "physics.inlay.asm"`
- **THEN** the resolver receives the exact logical name
  `physics.inlay.asm`
- **AND** the resolved module participates in deterministic expansion,
  duplicate suppression, import filtering and source mapping

#### Scenario: A legacy module name remains valid

- **WHEN** an entry module contains `include "physics.la.asm"`
- **THEN** the resolver receives the exact logical name `physics.la.asm`
- **AND** the module is parsed and expanded with the same rules as a canonical
  Inlay module

#### Scenario: Suffix-only module migration preserves behavior

- **WHEN** a closed module graph and all of its include declarations are
  renamed from `.la.asm` to `.inlay.asm` without changing their contents
- **THEN** expansion produces the same semantic events and emitted
  instructions
- **AND** source-map structure and addresses remain equivalent apart from the
  renamed logical source strings
