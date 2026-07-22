## ADDED Requirements

### Requirement: Scrolling Tilemap Layer

The system SHALL composite a 32x16-cell tilemap behind the sprites. Each 16-bit cell holds {palette base[3:0], bpp-1[1:0], yflip, xflip, pattern base[7:0]} and references the sprite sheet by plane-slot base addressing, exactly as sprite entries do. Cell value $0000 SHALL be treated as empty. Camera registers SHALL scroll the layer with pixel granularity, wrapping over the 256x128-pixel map world, with the camera position latched once per scanline.

#### Scenario: Smooth scroll

- **WHEN** camera_x is incremented by 1 between frames
- **THEN** the tile layer shifts left by exactly one pixel, including partial tiles at both screen edges

#### Scenario: Tiles behind sprites

- **WHEN** a sprite overlaps a non-empty tile
- **THEN** the sprite's opaque pixels draw over the tile, and the sprite's transparent pixels show the tile

#### Scenario: Text as tiles

- **WHEN** a cell's pattern base is 128 + an ASCII code with depth 1bpp
- **THEN** the glyph renders from the font stored in sheet slots 128-255 with the cell's palette base

## MODIFIED Requirements

### Requirement: CPU Sprite List Interface

The CPU SHALL program the sprite sheet and the sprite list through the $400x register window: $4000 sheet address low, $4001 sheet address high, $4002 sheet data (write stores the byte at the sheet address and auto-increments it), $4003 camera X, $4004 camera Y, $4005 control (bit0 tilemap enable), $4008 list index, $4009 staged X, $400A staged Y, $400E staged pattern base, $400B flags (bit0 xflip, bit1 yflip, bits3:2 bpp-1, bits7:4 palette base; write commits the staged entry and auto-increments the index), $400C active sprite count, $400D read-only frame counter that increments once per vsync. The CPU SHALL program the tilemap through the $F000 window: cell low bytes (pattern base) at $F000-$F1FF and cell high bytes (attributes) at $F200-$F3FF, write-only.

#### Scenario: Streaming entries

- **WHEN** the CPU writes X, Y, pattern base, then flags repeatedly
- **THEN** consecutive list entries are populated without rewriting the index register

#### Scenario: Sheet upload

- **WHEN** the CPU sets the sheet address once and writes N data bytes
- **THEN** N consecutive sheet bytes are stored without further address writes

#### Scenario: Placing a tile

- **WHEN** the CPU writes a base to $F000+cell and attributes to $F200+cell
- **THEN** that cell renders the referenced pattern on the next composed line that intersects it

#### Scenario: Vsync-paced game loop

- **WHEN** the CPU polls $400D until its value changes
- **THEN** it resumes exactly once per displayed frame, enabling per-frame animation updates
