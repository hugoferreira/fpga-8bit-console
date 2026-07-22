## ADDED Requirements

### Requirement: Primitives Overlay

The system SHALL provide a 160x120 1bpp overlay bitmap mixed above all composited layers at display time. Byte address = y*20 + x/8 with bit 0 as the leftmost pixel of its byte. A set bit SHALL display the overlay color register; a clear bit SHALL be transparent. Enabling, and the 4-bit overlay color, SHALL be CPU-controlled, with the color sampled per displayed pixel.

#### Scenario: Pixel primitive

- **WHEN** the CPU sets a bit in the overlay
- **THEN** that screen pixel shows the overlay color regardless of tiles or sprites beneath it

#### Scenario: Arbitrary-pitch text

- **WHEN** the CPU renders glyphs into the overlay at a 4-pixel advance
- **THEN** the text displays at that pitch, unconstrained by the 8-pixel tile grid

#### Scenario: Disabled by default

- **WHEN** control bit1 is 0 (reset state)
- **THEN** the display shows exactly the composited tile and sprite layers

## MODIFIED Requirements

### Requirement: CPU Sprite List Interface

The CPU SHALL program the sprite sheet and the sprite list through the $400x register window: $4000 sheet address low, $4001 sheet address high, $4002 sheet data (write stores the byte at the sheet address and auto-increments it), $4003 camera X, $4004 camera Y, $4005 control (bit0 tilemap enable, bit1 overlay enable), $4006 overlay color, $4008 list index, $4009 staged X, $400A staged Y, $400E staged pattern base, $400B flags (bit0 xflip, bit1 yflip, bits3:2 bpp-1, bits7:4 palette base; write commits the staged entry and auto-increments the index), $400C active sprite count, $400D read-only frame counter that increments once per vsync. The CPU SHALL program the tilemap through the $F000 window (cell low bytes at $F000-$F1FF, high bytes at $F200-$F3FF) and the overlay through the $E000-$E95F window, both write-only.

#### Scenario: Streaming entries

- **WHEN** the CPU writes X, Y, pattern base, then flags repeatedly
- **THEN** consecutive list entries are populated without rewriting the index register

#### Scenario: Overlay byte write

- **WHEN** the CPU stores a byte at $E000 + y*20 + x/8
- **THEN** those eight overlay pixels update on the next displayed frame

#### Scenario: Vsync-paced game loop

- **WHEN** the CPU polls $400D until its value changes
- **THEN** it resumes exactly once per displayed frame, enabling per-frame animation updates
