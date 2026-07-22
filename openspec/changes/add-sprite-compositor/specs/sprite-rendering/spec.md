## ADDED Requirements

### Requirement: Multi-Instance Sprite Compositing

The system SHALL render up to 128 instances of a shared 8x8 1bpp sprite pattern per frame at arbitrary screen coordinates, composited one scanline ahead of the display beam into a double-buffered line buffer.

#### Scenario: Many sprites on one scanline

- **WHEN** the sprite list contains up to 128 enabled entries whose Y ranges overlap a given scanline
- **THEN** every entry is rendered on that scanline with no per-line sprite limit below the list size

#### Scenario: Sprite positioned at coordinates

- **WHEN** a list entry has position (X, Y)
- **THEN** the 8x8 pattern's top-left pixel appears at screen coordinate (X, Y), clipped at the right screen edge

### Requirement: Per-Instance Flip Transforms

Each sprite list entry SHALL support independent horizontal and vertical flip flags applied at zero cycle cost.

#### Scenario: Horizontal flip

- **WHEN** an entry's xflip flag is set
- **THEN** the pattern's rows are rendered mirrored left-to-right

#### Scenario: Vertical flip

- **WHEN** an entry's yflip flag is set
- **THEN** the pattern's rows are rendered in reverse order

### Requirement: CPU Sprite List Interface

The CPU SHALL program the shared pattern and the sprite list through the existing $400x register window using an indexed interface: $4000-$4007 pattern rows, $4008 list index, $4009 staged X, $400A staged Y, $400B flags (write commits the staged entry and auto-increments the index), $400C active sprite count, $400D read-only frame counter that increments once per vsync.

#### Scenario: Streaming entries

- **WHEN** the CPU writes X, Y, then flags repeatedly
- **THEN** consecutive list entries are populated without rewriting the index register

#### Scenario: Vsync-paced game loop

- **WHEN** the CPU polls $400D until its value changes
- **THEN** it resumes exactly once per displayed frame, enabling per-frame animation updates
