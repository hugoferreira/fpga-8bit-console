## ADDED Requirements

### Requirement: Language Behavior Is Description-resolved And Unchanged
Typed operations, procedure conventions, frames, invoke marshalling,
inline expansion and generated data SHALL resolve through the active
target description rather than core-resident target knowledge, and the
observable language behavior for `console6502` SHALL be unchanged:
identical diagnostics for identical source, identical generated
customasm, and an identical Celeste ROM digest.

#### Scenario: Existing source is unaffected
- **WHEN** the production Celeste source is built after the
  description migration
- **THEN** the generated assembly, source map, and ROM digest equal
  the pre-migration artifacts

#### Scenario: Capability gating is description presence
- **WHEN** a target description omits an operation entry that
  `console6502` declares
- **THEN** source using that operation rejects under the omitting
  description and assembles under `console6502`, with no core change
  between the two
