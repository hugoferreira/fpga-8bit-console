## ADDED Requirements

### Requirement: Inline Procedure Declaration
The frontend SHALL accept `inline` as a procedure qualifier using the
existing member grammar. An inline procedure SHALL emit no standalone body
and no label; `low(...)`, `high(...)` and `data codeptr` references to an
inline procedure SHALL be rejected. `frame` members and `ret` SHALL be
rejected inside inline procedures; the body falls through at its end. A
tail `jmp` to a non-inline procedure SHALL be permitted inside the body.

#### Scenario: Address of an inline procedure rejected
- **WHEN** source contains `data codeptr Lib.helper` where `Lib.helper` is
  declared inline
- **THEN** assembly fails with a stable-code diagnostic

#### Scenario: Frame member rejected
- **WHEN** an inline procedure declares `saved : u8 in frame`
- **THEN** assembly fails with a stable-code diagnostic

### Requirement: Inline Expansion Semantics
Invoking an inline procedure SHALL marshal bindings under the invoke
ordering and elision contract, then splice the body at the call site in
place of any transfer instruction. Local labels in the body SHALL be
freshened per expansion as dot-local names in the reserved generated
family so that no new target label scope opens at the expansion site.
Non-local labels in an inline body SHALL be rejected. Inline-in-inline
expansion SHALL be bounded by an explicit depth limit; recursion SHALL be
rejected. A tail `jmp` in the body SHALL be rejected at expansion sites
whose enclosing procedure has frame size greater than zero, with a
diagnostic naming both the inline procedure and the call site.

#### Scenario: Caller's local labels survive expansion
- **WHEN** an inline body containing `.loop` expands between a caller's
  `.retry` label and a backward branch to `.retry`
- **THEN** the caller's branch still resolves to its own `.retry` and the
  expanded `.loop` receives a freshened dot-local name

#### Scenario: Identity-placed expansion is byte-exact
- **WHEN** an inline procedure's members are placed in the caller's own
  locations and every binding is an identity
- **THEN** the expansion emits exactly the body's instructions and nothing
  else

#### Scenario: Tail jmp checked against the enclosing frame
- **WHEN** an inline body ending in `jmp Fixed.store_object` is invoked
  from a procedure with one frame byte
- **THEN** assembly fails with a diagnostic naming the inline procedure
  and the expansion site

### Requirement: Inline Expansion Metrics Visibility
Inline expansions SHALL be visible to the metrics and conformance tooling:
an expansion-site count SHALL appear in the metrics snapshot, and expanded
instructions SHALL be attributed to executable-byte accounting at their
expansion sites.

#### Scenario: Byte-neutral adoption stays measurable
- **WHEN** a migration replaces an open-coded idiom with an inline
  invocation of identical bytes
- **THEN** the ROM digest is unchanged and the expansion-site count in the
  metrics snapshot increases
