## ADDED Requirements

### Requirement: Draw State

The system SHALL apply a global draw state to compositing: a clip rectangle (x0,y0)-(x1,y1) inclusive outside which tiles and sprites SHALL NOT write; a 16-bit transparency mask where bit v makes pixel value v transparent; and a 16-entry draw palette remapping the post-palette-base color index of every composited pixel. The system SHALL additionally apply a 16-entry screen palette to every displayed pixel, including the overlay and the background. At reset the clip rectangle SHALL be the full screen, the transparency mask $0001, and both palettes identity.

#### Scenario: Clip rectangle

- **WHEN** a sprite or tile row extends past the clip rectangle
- **THEN** only its pixels inside the rectangle are written; the overlay is unaffected

#### Scenario: Extra transparent value

- **WHEN** transparency-mask bit 3 is set
- **THEN** pixels with stored value 3 become transparent in tiles and sprites while other values render normally

#### Scenario: Screen fade

- **WHEN** the CPU rewrites the screen palette
- **THEN** all subsequently displayed pixels (composited layers and overlay alike) remap through it with no recompositing

## MODIFIED Requirements

### Requirement: CPU Sprite List Interface

The CPU SHALL program the PPU through the $4000-$403F register window: $4000-$400E as previously specified (sheet port, camera, control, overlay color, list interface, count, frame counter, pattern base), plus $4010-$401F draw palette entries, $4020-$402F screen palette entries, $4030-$4033 clip rectangle x0/y0/x1/y1, and $4034/$4035 transparency mask low/high. The tilemap ($F000 window) and overlay ($E000 window) remain write-only.

#### Scenario: Draw-state write

- **WHEN** the CPU writes $4019 with value $0E
- **THEN** composited color index 9 subsequently renders as color 14

#### Scenario: Defaults preserve behavior

- **WHEN** no draw-state register has been written since reset
- **THEN** rendering is identical to the pre-draw-state PPU
