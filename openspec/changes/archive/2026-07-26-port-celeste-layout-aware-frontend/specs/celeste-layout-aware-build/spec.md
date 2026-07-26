## ADDED Requirements

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
- **THEN** all non-object memory-map declarations and all game source lines are
  preserved for customasm

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
