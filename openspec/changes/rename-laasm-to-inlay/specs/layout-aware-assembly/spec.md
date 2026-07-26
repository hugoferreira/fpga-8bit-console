## ADDED Requirements

### Requirement: Canonical Inlay Identity

The system SHALL identify the language as **Inlay Assembly**, SHALL permit
**Inlay** as its short name, and SHALL describe it with the tagline “Structured
assembly, close to the metal.” The canonical host command SHALL be `inlay`, and
the canonical source suffix SHALL be `.inlay.asm`.

The public rename SHALL NOT change the language syntax or semantics, the
portable `la_` C API, generated `__la_` private symbols, serialized format
versions, semantic event stream, emitted instruction stream or final machine
bytes.

#### Scenario: A user inspects the canonical command

- **WHEN** the user runs `inlay --help` or `inlay --version`
- **THEN** the command identifies itself as Inlay
- **AND** help output includes the Inlay Assembly name and tagline
- **AND** version output begins with `inlay`
- **AND** the reported language, target and map format versions equal their
  pre-rename values

#### Scenario: A canonical Inlay source is translated

- **WHEN** the host frontend translates a valid `program.inlay.asm`
- **THEN** it accepts the file through the normal source input path
- **AND** it applies exactly the same parsing, analysis and lowering rules as
  it applies to an otherwise identical source with a legacy suffix

#### Scenario: Internal namespaces remain stable

- **WHEN** the Inlay host and portable core are built and exercised
- **THEN** the public C API continues to use `la_` identifiers
- **AND** generated private symbols continue to use the `__la_` namespace
- **AND** no serialized format version is incremented solely for the rename

### Requirement: Inlay Naming Compatibility

The system SHALL provide `laasm` as a compatibility command for `inlay` and
SHALL continue to accept `.la.asm` source paths. Compatibility SHALL remain
until a separate specification change explicitly removes it.

The `laasm` command SHALL run the same implementation with the same arguments,
stdout, generated files, exit status and signal behavior as `inlay`, except
that it SHALL emit a concise deprecation diagnostic to stderr directing the
user to `inlay`.

#### Scenario: A legacy command invocation succeeds

- **WHEN** a user invokes `laasm` with arguments accepted by `inlay`
- **THEN** the invocation produces the same stdout, generated files and exit
  status as the corresponding `inlay` invocation
- **AND** stderr identifies `laasm` as deprecated and names `inlay` as its
  replacement

#### Scenario: Compatibility preserves machine-readable output

- **WHEN** a user invokes `laasm` in a mode whose stdout is JSON
- **THEN** stdout contains only the same valid JSON emitted by `inlay`
- **AND** the deprecation diagnostic is written only to stderr

#### Scenario: A legacy source suffix is accepted

- **WHEN** the host frontend is given a valid source named `program.la.asm`
- **THEN** it accepts the source without changing its syntax or semantics
- **AND** its semantic events, emitted instructions and machine bytes equal
  those from the same source named `program.inlay.asm`
