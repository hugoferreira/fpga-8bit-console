## ADDED Requirements

### Requirement: Comment-aware Expanded Source
The module expander SHALL remove semicolon comments outside quoted strings
before consuming expanded-source capacity. It SHALL retain one expanded line
and the original source origin for every input line.

#### Scenario: Commented source is expanded
- **WHEN** a semantic module contains code followed by a semicolon comment
- **THEN** expanded source contains the code and newline without the comment,
  and diagnostics still map to the original line

#### Scenario: Comment-only line is expanded
- **WHEN** a source line contains only whitespace and a semicolon comment
- **THEN** expansion contributes one newline and no comment bytes

#### Scenario: Semicolon occurs inside a quoted string
- **WHEN** an include path or raw target string contains a semicolon
- **THEN** the semicolon and following string contents are preserved

### Requirement: Comment-independent Module Capacity
Module source-capacity decisions SHALL depend on semantic code and retained
newlines rather than checked-in comment length.

#### Scenario: Readable and compact sources are equivalent
- **WHEN** two modules differ only in comments and comment-adjacent whitespace
- **THEN** they produce identical expanded code, semantic events and target
  bytes, with source mappings retaining their respective original lines
