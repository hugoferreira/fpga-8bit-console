## ADDED Requirements

### Requirement: Semantic Handwritten Celeste Modules

Every handwritten Celeste language module SHALL enter the frontend through
semantic `include`. Raw `#include` SHALL remain only for target ISA rules and
reviewed generated data payloads that contain no language declarations or
cross-module semantic names.

#### Scenario: Memory declarations are included

- **WHEN** the production root consumes Celeste memory declarations
- **THEN** the frontend parses their locations, overlays, constants and
  visibility rather than passing the file opaquely to customasm

#### Scenario: Generated audio payload is included

- **WHEN** the generated audio table remains a raw target data module
- **THEN** its reviewed `#include` remains valid and is not mistaken for a
  handwritten semantic escape hatch

### Requirement: Memory-map Migration ROM Equivalence

The memory-map migration SHALL preserve every byte of the accepted pre-change
65,536-byte Celeste ROM. Each ownership group SHALL be migrated independently
and SHALL pass focused lowering equivalence before the compatibility aliases
are removed.

#### Scenario: A subsystem moves to typed storage

- **WHEN** game state, MMIO, scratch or fixed storage references are migrated
  to semantic locations and overlays
- **THEN** the rebuilt ROM is byte-for-byte identical to the frozen pre-stage
  image

#### Scenario: Semantic lowering cannot preserve bytes

- **WHEN** a proposed typed operation changes instruction encoding, flags,
  clobbers or volatility
- **THEN** that site remains an explicit raw operation and is documented as an
  exception

### Requirement: Existing Celeste Regression Contract

Eliminating the memory-map aliases SHALL preserve the complete functional,
framebuffer, PSG trace, resource, deterministic-build, strict portability and
OpenSpec validation suites established by the Phase-B Celeste redesign.

#### Scenario: Compatibility file is deleted

- **WHEN** `src/celeste/memmap.inlay.asm` is removed
- **THEN** the complete Celeste regression suite passes against the
  byte-identical frontend-produced image
