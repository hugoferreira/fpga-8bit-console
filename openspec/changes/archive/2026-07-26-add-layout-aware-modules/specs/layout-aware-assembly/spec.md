## ADDED Requirements

### Requirement: Multi-source Semantic Compilation
The portable frontend SHALL accept module-expanded input whose origin callback
maps flattened lines to stable source ids and original line numbers. Existing
single-stream callers without an origin callback SHALL retain their current
behavior.

#### Scenario: Declaration and use span modules
- **WHEN** one module declares a nominal layout and another module uses it in a
  typed operand
- **THEN** the complete expanded source is resolved as one semantic module
  graph

#### Scenario: Legacy single input is compiled
- **WHEN** a caller supplies the existing streaming input without module
  origins
- **THEN** all events retain the input's single source id as before
