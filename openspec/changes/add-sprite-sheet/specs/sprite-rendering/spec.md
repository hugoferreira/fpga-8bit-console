## ADDED Requirements

### Requirement: Sprite Sheet with Plane-Slot Addressing

The system SHALL store patterns in a 2KB sprite sheet of 256 uniform 8-byte plane slots (one 8x8 bitplane per slot). Each sprite list entry SHALL reference its pattern by an 8-bit plane-slot base address, and the pattern SHALL occupy exactly bpp consecutive slots starting at that base, so that plane p row r of an entry's pattern is the byte at {base + p, r}.

#### Scenario: Distinct patterns per sprite

- **WHEN** two entries carry different base addresses
- **THEN** they render different patterns in the same frame

#### Scenario: Proportional footprint

- **WHEN** a 1bpp pattern and a 4bpp pattern are stored
- **THEN** they occupy 1 and 4 plane slots respectively, with no padding between patterns

#### Scenario: Deterministic fetch

- **WHEN** the engine blits an entry of depth bpp
- **THEN** it performs exactly bpp sheet reads at addresses derived only from the entry's base, bpp, and the current row - no configuration state or lookup tables

## MODIFIED Requirements

### Requirement: CPU Sprite List Interface

The CPU SHALL program the sprite sheet and the sprite list through the $400x register window: $4000 sheet address low, $4001 sheet address high, $4002 sheet data (write stores the byte at the sheet address and auto-increments it), $4008 list index, $4009 staged X, $400A staged Y, $400E staged pattern base, $400B flags (bit0 xflip, bit1 yflip, bits3:2 bpp-1, bits7:4 palette base; write commits the staged entry and auto-increments the index), $400C active sprite count, $400D read-only frame counter that increments once per vsync.

#### Scenario: Streaming entries

- **WHEN** the CPU writes X, Y, pattern base, then flags repeatedly
- **THEN** consecutive list entries are populated without rewriting the index register

#### Scenario: Sheet upload

- **WHEN** the CPU sets the sheet address once and writes N data bytes
- **THEN** N consecutive sheet bytes are stored without further address writes

#### Scenario: Vsync-paced game loop

- **WHEN** the CPU polls $400D until its value changes
- **THEN** it resumes exactly once per displayed frame, enabling per-frame animation updates
