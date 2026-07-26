## MODIFIED Requirements

### Requirement: Complete Frontend Build Path

`make GAME=celeste hex` SHALL translate the Celeste Inlay entry and module
graph with the portable semantic core and SHALL pass the resulting assembly to
the existing pinned `customasm` invocation. The build SHALL NOT require the
deprecated `laasm` compatibility command.

#### Scenario: Celeste image is built

- **WHEN** `make GAME=celeste hex` is run from a clean checkout
- **THEN** the generated entry `build/inlay/celeste.inlay.asm`, generated
  modules under `build/inlay/modules/`, emitted
  `build/inlay/celeste.asm` and its source map are created before
  `build/celeste.bin` and `rtl/ram.hex`
- **AND** the build invokes `inlay`, not the deprecated `laasm` command
- **AND** the final image contains no unresolved layout handles or
  `__la_` placeholders

## ADDED Requirements

### Requirement: Celeste Inlay Rename Equivalence

Renaming the Celeste frontend, module sources, build labels and generated paths
to Inlay SHALL NOT change the translated program or final ROM bytes.

#### Scenario: Pre-rename and Inlay Celeste artifacts are compared

- **WHEN** the same pinned Celeste source and target description are built
  through the pre-rename layout-aware path and the canonical Inlay path
- **THEN** their semantic events and emitted instruction streams are
  equivalent apart from branding comments and logical source names
- **AND** their final binary and hexadecimal ROM payloads are byte-identical
- **AND** their instruction, code-byte, data-byte, resolved-handle and
  module-count measurements are unchanged

#### Scenario: Inlay Celeste sources use canonical suffixes

- **WHEN** the Celeste Inlay frontend materializes its entry and module graph
- **THEN** every generated Inlay source path ends in `.inlay.asm`
- **AND** no repository-owned Celeste source or include declaration requires
  the legacy `.la.asm` suffix
