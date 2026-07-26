## ADDED Requirements

### Requirement: Complete Celeste Inlay Corpus
`src/celeste/` SHALL contain the complete production game as a flat set of
`.inlay.asm` modules. The set SHALL include the entry, layout, memory map, every
handwritten code module, and generated graphics, rooms and audio data.

#### Scenario: Developer inspects the production directory
- **WHEN** a developer lists regular files beneath `src/celeste/`
- **THEN** every file ends in `.inlay.asm` and exactly one
  `main.inlay.asm` entry exists

#### Scenario: Production dependency graph is followed
- **WHEN** the local includes reachable from `main.inlay.asm` are resolved
- **THEN** every dependency is another checked-in `.inlay.asm` module beneath
  `src/celeste/`, with opaque target inclusion limited to `memmap`, `gfx`,
  `rooms` and `audio`

### Requirement: Test-only Direct Assembly Oracle
The former direct customasm Celeste corpus SHALL reside beneath
`tests/inlay/reference/celeste-customasm/` and SHALL be used only by
conformance. Production build inputs SHALL NOT reference that tree.

#### Scenario: Normal game build runs
- **WHEN** a user runs `make GAME=celeste hex`
- **THEN** no source beneath `tests/inlay/reference/celeste-customasm/` is read

#### Scenario: Equivalence runs
- **WHEN** Celeste conformance executes
- **THEN** it assembles the test-only direct entry independently and compares
  it with the translated production entry

### Requirement: Celeste Source-boundary Gate
Conformance SHALL reject an incomplete or hybrid production corpus before
testing ROM bytes.

#### Scenario: Legacy local include is introduced
- **WHEN** a production Celeste module references a Celeste `.asm` source or
  the test-only oracle
- **THEN** conformance fails with the offending source path

#### Scenario: Unapproved opaque include is introduced
- **WHEN** a handwritten instruction module is included without semantic
  expansion, or another opaque data module is added outside the four-file
  allowlist
- **THEN** conformance fails with the offending include

#### Scenario: Production module is missing or misnamed
- **WHEN** the exact expected `.inlay.asm` module set is not present
- **THEN** conformance fails before translation

### Requirement: Inlay-named Generated Assets
Celeste asset generators SHALL emit graphics, room and audio assembly inputs
using `.inlay.asm` filenames suitable for direct inclusion in the production
Inlay graph.

#### Scenario: Cart assets are regenerated
- **WHEN** the Celeste graphics/room or audio generation workflow runs
- **THEN** it produces the filenames consumed by `main.inlay.asm` without a
  rename or compatibility copy step

## MODIFIED Requirements

### Requirement: Complete Frontend Build Path
`make GAME=celeste hex` SHALL translate `src/celeste/main.inlay.asm`, its
semantically expanded handwritten module graph, and its allowlisted opaque
`.inlay.asm` declaration/data modules with the portable core, then pass the
result to pinned customasm. It SHALL retain the binary, symbol, converted
label and readmemh outputs.

#### Scenario: Celeste image is built
- **WHEN** a user runs `make GAME=celeste hex`
- **THEN** `build/inlay/celeste.asm` and its source map are generated before
  customasm produces `build/celeste.bin`, `build/celeste.sym`,
  `build/celeste.lbl` and `rtl/ram.hex`

### Requirement: Typed Celeste Module Migration
The production Celeste modules SHALL express every eligible direct byte
`lda`/`sta` through `pObj` or `pOth` as an explicit typed field operand. They
SHALL preserve non-equivalent indexed target sequences and SHALL derive any
compatibility `O_*` aliases from the authoritative object layout.

#### Scenario: Direct field operation is eligible
- **WHEN** a production module loads the hitbox width through `pObj`
- **THEN** source contains `lda [pObj + CelesteObject.hitbox.w]` and emits the
  same instruction bytes as the legacy oracle

#### Scenario: High fixed-point byte is eligible
- **WHEN** an operation addresses the high byte of speed X
- **THEN** source uses `CelesteObject.speed_x.integer`

#### Scenario: Indexed operation is not equivalent
- **WHEN** source loads Y with an `O_*` value and uses `(pObj),y`
- **THEN** the production module preserves that target-specific sequence

### Requirement: Migrated Full-ROM Equivalence
The conformance gate SHALL require the expected typed-operation and
structured-procedure counts in the production corpus, compare all 65,536
output bytes against the test-only direct oracle, and assert the established
SHA-256 digest.

#### Scenario: Complete production corpus is accepted
- **WHEN** all modules translate and assemble
- **THEN** construct counts match, every byte equals the direct oracle, ROM
  size is 65,536, and SHA-256 is
  `d85795e3daa7f1fbea0cef869efd554871f316c6196586dac3938e6340ae011a`

### Requirement: Celeste Structured Address and Procedure Migration
The production object module SHALL express object pool address materialisation
through a scoped procedure declaration and unified parameter and
return-location syntax while retaining the current machine bytes.

#### Scenario: Object pointer routine is inspected
- **WHEN** `src/celeste/obj.inlay.asm` is read
- **THEN** `obj_ptr` is a structured procedure using a typed pool address
  operation

## REMOVED Requirements

### Requirement: Narrow Build-only Source Adaptation
**Reason**: A complete checked-in Inlay corpus replaces generated compatibility
sources and mixed legacy production dependencies.

**Migration**: Edit the flat `src/celeste/*.inlay.asm` graph directly and use
the test-only direct corpus for equivalence.

### Requirement: Checked-in Celeste Inlay Source
**Reason**: The former requirement allowed a partial checked-in wrapper plus
legacy production includes.

**Migration**: Use the stricter Complete Celeste Inlay Corpus and Celeste
Source-boundary Gate requirements.

### Requirement: Golden Celeste Image
**Reason**: Golden digest enforcement is incorporated into Migrated Full-ROM
Equivalence rather than specified separately.

**Migration**: None; the digest remains mandatory.
