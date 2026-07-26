# Layout-aware Modules

## Purpose

Defines bounded, platform-neutral module resolution and original-source
correlation for layout-aware assembly.

## Requirements

### Requirement: Platform-neutral Module Resolution
The frontend SHALL resolve owned module directives through a caller-provided
callback returning immutable source bytes, a stable source id and a logical
name. The portable module layer SHALL NOT open files or allocate memory.

#### Scenario: Host module is requested
- **WHEN** source contains `include "physics.la.asm"`
- **THEN** the core passes the logical name and including source id to the
  resolver and expands the returned source view

#### Scenario: Console editor module is requested
- **WHEN** a console resolver maps the same logical name to an editor buffer
- **THEN** expansion and semantic events require no host filesystem API

### Requirement: Bounded Module Expansion
Module expansion SHALL use caller-owned storage and explicit capacities for
module records, flattened bytes, source lines and include depth. It SHALL use
an explicit stack rather than platform recursion.

#### Scenario: Capacity is exact
- **WHEN** an input uses exactly each configured module capacity
- **THEN** expansion succeeds without requesting more storage

#### Scenario: Capacity is exceeded
- **WHEN** one additional module, line, byte or include level is required
- **THEN** expansion fails with a stable diagnostic naming the exhausted
  resource, actual value and configured limit

### Requirement: Deterministic Include Graph
The module layer SHALL reject missing modules, active include cycles and a
second inclusion of an already completed module. Resolution order and assigned
source ids SHALL be deterministic depth-first source order.

#### Scenario: Include cycle exists
- **WHEN** module A includes B and B includes A
- **THEN** expansion reports a cycle at B's include directive without consuming
  platform call stack

#### Scenario: Module is included twice
- **WHEN** two directives resolve to the same stable module identity
- **THEN** the second directive receives a duplicate-module diagnostic

### Requirement: Original Source Correlation
Every expanded line SHALL retain its original source id and line number.
Semantic events, frontend diagnostics and host source-map entries SHALL report
that origin rather than only the flattened line.

#### Scenario: Included typed operand fails
- **WHEN** an invalid field path occurs on line 17 of an included module
- **THEN** the diagnostic reports that module's source id and line 17

#### Scenario: Included raw line is emitted
- **WHEN** an included raw customasm line reaches host output
- **THEN** source-map format 2 identifies its logical module and original line

### Requirement: Include Syntax Separation
`include "name"` SHALL be frontend-owned module syntax, while `#include` SHALL
remain uninterpreted raw target assembly.

#### Scenario: ISA rule include is encountered
- **WHEN** source contains `#include "../../src/isa/nmos6502.asm"`
- **THEN** the line passes to customasm byte-for-byte and no module resolver is
  called
