# Celeste Layout-aware Build

## Purpose

Defines Celeste adoption of the layout-aware frontend and its exact assembly-equivalence gates.

## Requirements

### Requirement: Authoritative Celeste Object Layout
The Celeste frontend entry SHALL declare the complete packed 64-storage-unit
object layout, including nested fixed-point values, the nested hitbox, five
hair nodes and the seven-byte reserved tail. Every legacy `O_*` object-layout
symbol consumed by the full game SHALL resolve from a generated layout
property rather than a second handwritten number.

#### Scenario: Layout matches the established memory map
- **WHEN** the Celeste layout-aware entry is translated
- **THEN** its size is 64, hair begins at 37, nested hitbox members occupy
  offsets 12 through 15, and every represented `O_*` offset equals the current
  authoritative corpus value

#### Scenario: Object layout grows
- **WHEN** a field moves or the record grows beyond 64 storage units
- **THEN** translation fails at a layout assertion before customasm accepts a
  game image

### Requirement: Narrow Build-only Source Adaptation
The host build SHALL generate Celeste compatibility sources beneath
`build/layout_aware/` without editing the existing Celeste corpus modules. The
adapter SHALL remove only the superseded object-offset block and SHALL fail on
unrecognised declarations or an unexpected main-file include structure.

#### Scenario: Existing source shape is recognised
- **WHEN** the current Celeste main file and memory map are prepared
- **THEN** all non-object memory-map declarations and target-assembly tokens
  are preserved for customasm, while build-only module copies may remove
  comments and trailing whitespace without removing lines

#### Scenario: Offset block contains unknown syntax
- **WHEN** a non-comment line in the contiguous `O_TYPE` through `O_SIZE` block
  is not a recognised numeric `O_*` assignment
- **THEN** preparation fails instead of omitting the line

### Requirement: Complete Frontend Build Path
`make GAME=celeste hex` SHALL translate the Celeste layout-aware entry with the
portable semantic core and SHALL pass the resulting assembly to the existing
pinned customasm encoder. It SHALL retain the current binary, symbol, converted
label and readmemh outputs.

#### Scenario: Celeste image is built
- **WHEN** a user runs `make GAME=celeste hex`
- **THEN** `build/layout_aware/celeste.asm` and its source map are generated
  before customasm produces `build/celeste.bin`, `build/celeste.sym`,
  `build/celeste.lbl` and `rtl/ram.hex`

### Requirement: Assembly Equivalence Gate
The adoption SHALL require both representative typed-operation equivalence and
complete image equivalence. The complete comparison SHALL cover every byte of
the 64 KiB output and MUST fail on the first difference.

#### Scenario: Typed operands are lowered
- **WHEN** direct, nested and load/store Celeste field operands are translated
- **THEN** their instruction bytes equal a handwritten customasm reference

#### Scenario: Complete game is assembled through both paths
- **WHEN** the current direct customasm entry and the generated layout-aware
  entry are assembled with customasm v0.14.1
- **THEN** their 65,536-byte images are byte-for-byte identical

### Requirement: Celeste Functional Regression
The existing reset-vector Celeste functional suite SHALL run against the image
produced through the frontend, and the assembly-equivalence gate SHALL run
before that suite.

#### Scenario: Frontend-generated game is tested
- **WHEN** a user runs `make test-celeste`
- **THEN** full image equivalence passes and all existing boot, physics,
  collision, audio, HUD and room-transition checks run against the frontend
  output

### Requirement: Typed Celeste Module Migration
The layout-aware Celeste build SHALL convert every eligible direct byte
`lda`/`sta` through `pObj` or `pOth` from a legacy `O_*` displacement to an
explicit typed field operand in generated layout-owned modules. It SHALL leave
non-equivalent indexed sequences unchanged and SHALL NOT edit
`src/celeste/`.

#### Scenario: Direct field operation is eligible
- **WHEN** a generated Celeste module contains
  `lda (pObj), #O_HBW`
- **THEN** frontend input contains
  `lda [pObj + CelesteObject.hitbox.w]` and emits identical instruction bytes

#### Scenario: High fixed-point byte is eligible
- **WHEN** an operation uses `#O_SPDX+1`
- **THEN** migration uses `CelesteObject.speed_x.integer`

#### Scenario: Indexed operation is not equivalent
- **WHEN** source loads Y with an `O_*` value and uses `(pObj),y`
- **THEN** the generated module preserves that raw instruction sequence

### Requirement: Migrated Full-ROM Equivalence
The conformance gate SHALL require a nonzero expected typed-operation count
across generated Celeste modules and SHALL compare all 65,536 output bytes
against the direct current source.

#### Scenario: Generated modules are accepted
- **WHEN** all eligible direct operations have been translated and assembled
- **THEN** the typed-operation count matches the migration manifest and the
  complete ROM is byte-for-byte identical

### Requirement: Celeste Structured Address and Procedure Migration
The generated layout-owned Celeste modules SHALL exercise pool address
materialisation and procedure declarations without editing `src/celeste/`.
Each migrated construct SHALL have an exact expected count and retain the
current machine bytes.

#### Scenario: Object pointer routine is migrated
- **WHEN** the generated object module is prepared
- **THEN** the existing object-address routine is expressed through a typed
  pool address operation and a scoped procedure parameter contract

#### Scenario: Full game is rebuilt
- **WHEN** indexed, pool and procedure frontend support is enabled in the
  Celeste layout build
- **THEN** the resulting 65,536-byte ROM is byte-for-byte identical to the
  direct current source
