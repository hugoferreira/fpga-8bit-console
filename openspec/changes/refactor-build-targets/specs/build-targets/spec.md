## ADDED Requirements

### Requirement: Each subsystem is independently synthesisable

The design SHALL provide four synthesis tops — CPU, PSG, PPU and the full
console — each buildable, placeable and measurable without any of the others.

A subsystem's area and frequency SHALL be obtainable without the whole console
being placeable, so that a subsystem measurement is never blocked by an
unrelated subsystem's cost.

#### Scenario: A subsystem is measured while the full console does not fit

- **WHEN** the full console exceeds the device and cannot be placed
- **THEN** each of the CPU, PSG and PPU targets still reports logic cells,
  block RAM, Fmax and a critical path
- **AND** the full-console target reports its utilisation and names the
  resource it exceeds, rather than failing without a number

#### Scenario: A subsystem's cost is attributed

- **WHEN** a subsystem target is synthesised
- **THEN** the reported area covers that subsystem and the bus it is attached
  to, and excludes the other two subsystems

### Requirement: Subsystem targets are the shipping design with parts disabled

A subsystem top SHALL be an instantiation of the same `chip` module that the
board and simulator tops instantiate, configured by parameter. Subsystem tops
SHALL NOT re-describe how the console is wired.

This is what makes a subsystem measurement evidence about the console rather
than about a harness.

#### Scenario: The console's wiring changes

- **WHEN** a signal between the CPU, the arbiter, the DMA controller or a
  subsystem is changed in `chip.sv`
- **THEN** every subsystem target reflects that change with no separate edit
- **AND** no target can be built from a stale copy of the wiring

#### Scenario: A subsystem is disabled

- **WHEN** a subsystem's parameter is set to 0
- **THEN** the subsystem is not instantiated, its bus inputs read as zero, and
  its decode branch is trimmed
- **AND** the remaining design behaves exactly as it does with the subsystem
  present but unaddressed

### Requirement: Enabling every subsystem reproduces today's design

The parameters that select subsystems SHALL default to enabled, and the board
and simulator tops SHALL be unaffected by their introduction.

#### Scenario: The default build is unchanged

- **WHEN** all subsystems are enabled
- **THEN** `make run`, `make ppu-check` and the PSG's render comparison produce
  output byte-identical to the same commands before the parameters existed

### Requirement: Synthesis tops match the shipping top's port tie-offs

A synthesis top SHALL leave verification-only ports unconnected, exactly as the
board top leaves them, so that logic the console trims is not measured.

Where a target's real outputs must be reduced to satisfy the package's pin
budget, only ports that the console genuinely drives SHALL be included in that
reduction.

#### Scenario: A debug bus is not measured

- **WHEN** a subsystem exposes a verification-only output that the board top
  leaves unconnected
- **THEN** the subsystem's synthesis top also leaves it unconnected
- **AND** the reported area excludes the logic driving it

#### Scenario: A real output is not trimmed

- **WHEN** a target's real outputs exceed the package's available pins
- **THEN** they are reduced to a registered probe rather than left unconnected,
  so the datapath producing them is not optimised away

### Requirement: Measurement targets follow one naming scheme

Area, frequency and regression targets SHALL be named uniformly across
subsystems, so that a command learned for one applies to the others.

Target names that existed before SHALL continue to work.

#### Scenario: The same question is asked of a different subsystem

- **WHEN** a maintainer knows how to obtain one subsystem's area or frequency
- **THEN** the equivalent command for any other subsystem differs only in the
  subsystem's name

#### Scenario: An existing command is used

- **WHEN** a target name that existed before this change is invoked
- **THEN** it performs the same function as before

### Requirement: Reported frequency accounts for placement variance

A frequency measurement SHALL be reported over multiple placement seeds, and
SHALL state the range rather than a single figure.

Placement on this device varies by several MHz between seeds, which is wider
than the differences such measurements are typically used to judge.

#### Scenario: Two designs are compared

- **WHEN** two variants' frequencies are compared
- **THEN** each is reported as a range over a stated number of seeds
- **AND** a difference smaller than the observed spread is not reported as a
  result

### Requirement: A subsystem's clock requirement is checked against its closing frequency

Where a subsystem is driven at a specified frequency, that frequency SHALL be
checked against the subsystem's measured closing frequency, and a shortfall
SHALL be recorded as a defect against the design.

#### Scenario: A subsystem is clocked above its closing frequency

- **WHEN** a subsystem's required clock exceeds its measured Fmax
- **THEN** the shortfall is recorded with both figures, the divider that would
  close, and the consequences for any timing derived from the required clock
