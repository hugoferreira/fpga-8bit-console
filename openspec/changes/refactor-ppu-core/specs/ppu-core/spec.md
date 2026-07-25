## ADDED Requirements

### Requirement: Rendering is pinned by golden frames

The PPU's rendering behaviour SHALL be defined by a committed set of reference
frames rather than by inspection. A regression harness SHALL render a fixed
scene that exercises every path through the compositor and compare the result
bit-for-bit against those frames.

The scene SHALL cover: tiles at 1, 2, 3 and 4 bpp; a non-zero palette base; both
flip bits; the behind-split partition; repeat runs of two or more cells; the
clip rectangle at each edge; a non-default transparency mask; the overlay both
set and clear; and a camera scrolled to a non-zero sub-cell offset on both axes.

#### Scenario: A behaviour-preserving change is accepted

- **WHEN** the compositor is restructured without intending a behaviour change
- **THEN** every pixel of every golden frame matches the committed reference
- **AND** the harness exits zero

#### Scenario: An accidental behaviour change is rejected

- **WHEN** a change alters any composited pixel
- **THEN** the harness reports the first differing frame, pixel coordinate and
  the two colour values, and exits non-zero

#### Scenario: An intended behaviour change

- **WHEN** a change is meant to alter rendering
- **THEN** the reference frames are regenerated in the same commit as the
  change, so that the diff shows exactly which pixels moved and why

### Requirement: The per-line cycle budget is asserted, not assumed

A scanline provides a fixed number of engine clocks, and the compositor SHALL
NOT silently exceed it. The harness SHALL account for the clocks consumed per
line and fail when the engine has not reached its idle state by the end of a
line.

Exceeding the budget degrades gracefully in hardware — the engine restarts at
`line_start`, so the tail of the sprite list is dropped for that line — which is
precisely why it must be detected in test rather than observed as flicker.

#### Scenario: A line that fits

- **WHEN** a line's clear, tile pass and sprite pass complete within the line
- **THEN** the engine is idle before `line_start` and the harness passes

#### Scenario: A line that overruns

- **WHEN** a scene places enough composited entries on one line to exhaust it
- **THEN** the harness reports the line number, the number of entries that did
  not composite, and the clocks by which the budget was exceeded

#### Scenario: The budget is documented as a number

- **WHEN** the cost of a change to the engine is assessed
- **THEN** the per-line budget and the per-entry and per-tile costs are
  available as measured figures rather than estimates

### Requirement: The compositor is built from separable modules

The compositor SHALL be composed of modules with explicit interfaces rather than
a single module sharing state through one procedural block. Each module SHALL
have a single responsibility: the CPU and DMA register file; the tilemap store
and its per-line column walk; the sprite list store and its scan; the pattern
fetch; the blit datapath; the line buffer; and the display read path including
the overlay mix and the screen palette.

#### Scenario: A display-path feature is added

- **WHEN** a change adds a field to the display path, such as an overlay
  priority or blit mode
- **THEN** it is made within the display module and its interface, without
  editing the engine FSM

#### Scenario: Module boundaries do not cost behaviour

- **WHEN** the split is performed
- **THEN** the golden frames are unchanged, and the change is verifiable as
  behaviour-preserving

### Requirement: The blit datapath is pipelined

The path from a sprite or tile entry to the line-buffer write data SHALL be
divided into pipeline stages so that pattern decode, palette lookup, alignment
shift and merge do not occupy a single clock.

The pipeline SHALL NOT reduce throughput: the engine SHALL composite an entry in
no more clocks than before the change, measured by the per-line accounting
above.

#### Scenario: Timing improves without a throughput cost

- **WHEN** the pipelined datapath is placed and routed for the target device
- **THEN** the reported Fmax is no lower than before the change
- **AND** the per-line clock accounting for the same scene is no higher

#### Scenario: Wider pixel formats stay affordable

- **WHEN** a future change widens the pixel path
- **THEN** the added logic lands in one pipeline stage rather than extending a
  single-cycle path from entry register to line buffer

### Requirement: Resource use is reported and bounded

The build SHALL report the PPU's logic-cell, carry, flip-flop and block-RAM
usage, and its post-place-and-route Fmax, so that the cost of a change is
visible at the time it is made.

Block RAM SHALL be accounted for by consumer — pattern sheet, tilemap, overlay
and line buffer — distinguishing storage forced by capacity from storage forced
by port width, because only the latter can be recovered by restructuring.

#### Scenario: A change that costs resources

- **WHEN** a change to the PPU is proposed
- **THEN** its logic and block-RAM cost is stated as a measured delta against
  the recorded baseline, not as an estimate

#### Scenario: The baseline is recorded

- **WHEN** this change completes
- **THEN** the baseline figures are recorded and any reduction achieved is
  stated against them
