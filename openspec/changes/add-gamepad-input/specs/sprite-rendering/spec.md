## ADDED Requirements

### Requirement: Button Input Register

The system SHALL expose an 8-bit button state at PPU register $4007 (read-only): bit0 left, bit1 right, bit2 up, bit3 down, bit4 O, bit5 X. The simulator SHALL sample host keyboard state once per frame; hardware without buttons SHALL read as zero.

#### Scenario: Polling input

- **WHEN** the CPU reads $4007 while the right arrow is held
- **THEN** bit1 is set

### Requirement: Full RAM Address Map

All CPU addresses outside the PPU register, overlay, and tilemap windows SHALL decode to RAM, giving programs the full 64KB image minus device windows.

#### Scenario: Program data above $1000

- **WHEN** the CPU reads data placed at $1100
- **THEN** it receives the RAM contents rather than open bus
