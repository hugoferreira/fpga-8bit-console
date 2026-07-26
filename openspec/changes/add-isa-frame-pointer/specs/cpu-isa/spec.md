## ADDED Requirements

### Requirement: Frame Pointer Register

The CPU SHALL provide an 8-bit frame pointer register `F` selecting a base
address within zero page. Frame-relative operands `f+n` SHALL address location
`(F + n)` modulo 256.

`F` SHALL only be modified by `ENTER`, `LEAVE`, interrupt entry and `RTI`. No
instruction SHALL be provided that sets `F` to an arbitrary value.

#### Scenario: Frame-relative access resolves against F

- **WHEN** `F` holds `$C0` and a frame-relative store to `f+2` executes
- **THEN** location `$C2` is written

#### Scenario: Frame-relative access wraps within zero page

- **WHEN** `F` holds `$FE` and a frame-relative access to `f+4` executes
- **THEN** location `$02` is accessed

### Requirement: Frame Allocation

The CPU SHALL provide `ENTER #n`, which saves the current `F`, allocates `n`
bytes of frame below the current allocation point, and sets `F` to the new
frame's base; and `LEAVE`, which releases the current frame and restores the
saved `F`.

Frames SHALL be allocated downward from the top of zero page.

#### Scenario: Frame is allocated and released

- **WHEN** a routine executes `ENTER #4`, writes to `f+0` through `f+3`, and
  executes `LEAVE`
- **THEN** `F` holds the value it held before the `ENTER`

#### Scenario: Nested frames do not overlap

- **WHEN** a routine with a frame calls another routine that allocates its own
  frame
- **THEN** the callee's frame occupies addresses below the caller's, and the
  caller's locals are unchanged when the callee returns

#### Scenario: Recursion is supported

- **WHEN** a routine that allocates a frame calls itself to a depth of 4 and
  each level writes a distinct value to `f+0`
- **THEN** each level reads back its own value as it unwinds

### Requirement: Frame Overflow Detection

The CPU SHALL hold a configurable frame floor address. When `ENTER` would
allocate a frame extending below the floor, the CPU SHALL raise the diagnostic
trap signal with a reserved code. The simulator SHALL report the overflow and
the executing routine; on hardware the signal SHALL have no observable effect.

#### Scenario: Overflow is reported

- **WHEN** nested `ENTER` instructions would allocate past the frame floor
- **THEN** the simulator halts reporting a frame overflow and the routine in
  which it occurred

### Requirement: Frame Pointer Interrupt Safety

When frame support is enabled, interrupt entry SHALL save `F` and `RTI` SHALL
restore it, so that an interrupt handler may allocate its own frames without
disturbing the interrupted routine's locals.

Frame support SHALL be disabled at reset. While disabled, interrupt entry and
`RTI` SHALL be cycle-identical and byte-identical in behaviour to the CPU
without this change.

#### Scenario: Handler frames do not corrupt the interrupted routine

- **WHEN** an interrupt is taken inside a routine holding a frame, the handler
  allocates and releases its own frame, and `RTI` returns
- **THEN** the interrupted routine's `F` and locals are unchanged

#### Scenario: Disabled frame support preserves interrupt timing

- **WHEN** frame support is disabled and an interrupt is taken
- **THEN** interrupt entry and `RTI` take exactly the same number of cycles as on
  the CPU without frame support

### Requirement: Frame Chain Reporting

The diagnostic trap SHALL report the current frame chain. Given a symbol file,
the simulator SHALL print each active frame's base address, size and the routine
that allocated it.

#### Scenario: Trap prints a frame chain

- **WHEN** a diagnostic trap fires three frames deep
- **THEN** the simulator prints three frames, each with its base address, size
  and routine name
