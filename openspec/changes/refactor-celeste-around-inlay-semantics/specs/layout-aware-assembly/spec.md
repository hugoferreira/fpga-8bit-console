## ADDED Requirements

### Requirement: Qualified Procedure Names

Procedure names SHALL accept dot-separated identifier components. Qualified
names SHALL remain nominally distinct in frontend diagnostics and invocation
resolution. A target backend MAY encode a qualified name using a different
target-valid spelling, but the mapping SHALL be deterministic and SHALL
establish a fresh scope for target-local labels.

#### Scenario: Namespaced procedure is declared

- **WHEN** source declares `proc Player.update using console6502`
- **THEN** the frontend records the complete name `Player.update` and emits the
  backend's deterministic symbol spelling for that procedure

#### Scenario: Qualified procedures contain equal local labels

- **WHEN** two qualified procedures each contain a target-local label named
  `.done`
- **THEN** both procedures assemble without a duplicate-symbol collision

#### Scenario: Qualified procedure is duplicated

- **WHEN** source declares the same qualified procedure name twice
- **THEN** translation fails with a duplicate-procedure diagnostic
