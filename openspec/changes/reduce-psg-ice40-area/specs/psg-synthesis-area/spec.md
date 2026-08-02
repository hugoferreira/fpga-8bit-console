## ADDED Requirements

### Requirement: Substantial iCE40 PSG Area Reduction

The fidelity-complete standalone PSG SHALL map and place on an iCE40 HX8K
using no more than 5,500 of 7,680 logic cells and no more than 15 of 32 block
RAMs under the repository's PSG synthesis target. The report SHALL identify
the RTL fingerprint, mapped LUT4/flip-flop/carry/BRAM counts, routed
logic-cell/BRAM counts and routed clock frequency.

#### Scenario: Final standalone synthesis gate

- **WHEN** the final PSG RTL is synthesized and routed through the repository's
  iCE40 standalone target
- **THEN** the report identifies the measured source fingerprint and satisfies
  both the 5,500-LC and 15-BRAM ceilings

### Requirement: Hardware-Bounded Serialized Schedule

The PSG SHALL complete all eight slot visits, waveform/filter/amplitude work
and ordered pairwise mix reduction before every 22,050 Hz sample boundary at
the current 18.75 MHz master-derived PSG clock. Tick/effect work SHALL publish
a complete parameter set before the sample that consumes that tick. A
simulator's host runtime or lowering SHALL NOT impose an RTL clock budget.

#### Scenario: Worst-case sample deadline

- **WHEN** all eight slots exercise the longest supported synthesis path
- **THEN** the sample job completes in fewer than the minimum 850 PSG clocks
  available before the next sample enable

#### Scenario: Variable-duration tick evaluation

- **WHEN** different slots require different effect and instrument microcode
  paths during one tick
- **THEN** the next sample observes either the preceding complete parameter set
  or the following complete parameter set, never a partially published mix

### Requirement: PICO-8 Fidelity Survives Area Transformation

The area implementation SHALL preserve the cart-visible register interface,
eight-slot foreground/music behavior, oscillator transitions, instruments,
filters and ordered pairwise mixing accepted by the PICO-8 export oracle.
Area results SHALL NOT be accepted by weakening an oracle tolerance.

#### Scenario: Complete oracle after each accepted stage

- **WHEN** an architectural area stage is proposed for retention
- **THEN** the complete bounded PICO-8 export matrix is diagnostic-clean under
  the pre-existing per-case thresholds

#### Scenario: Integration remains audible

- **WHEN** Celeste is rebuilt and run headlessly against the transformed PSG
- **THEN** the simulator completes the bounded run and reports active,
  non-constant audio samples

### Requirement: Shared Arithmetic Has One Physical Commit Site

Each shared accumulator or arithmetic result register SHALL have one physical
sequential write site, with operation selection before that site, so
serialization removes arithmetic and destination muxes rather than adding
state-conditioned register inputs.

#### Scenario: Migrating another arithmetic operation

- **WHEN** a phase, filter, interpolation, volume, blend or mix operation is
  moved onto the shared service
- **THEN** mapped synthesis shows no additional parallel instance of that
  operation and the service result commits through its existing write site
