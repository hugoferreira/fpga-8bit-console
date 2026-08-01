## ADDED Requirements

### Requirement: NMOS Compatibility Contract

The console CPU SHALL remain a strict superset of the NMOS 6502 instruction set
in use today. Every opcode defined by the NMOS 6502 SHALL keep its documented
mnemonic, addressing mode, byte count, cycle count and flag effects. ISA
extensions SHALL only occupy opcode slots that are undefined on the NMOS 6502.

#### Scenario: Existing program is unaffected

- **WHEN** a program built before an ISA extension is assembled and run on the
  extended core
- **THEN** it produces byte-identical output and identical observable behaviour
  to the pre-extension core

#### Scenario: Conformance suite passes

- **WHEN** `make test` runs the 6502 functional conformance test on the
  extended core
- **THEN** the test reaches its success trap with no reported failure

### Requirement: Opcode Allocation Registry

The project SHALL maintain `docs/opcodes.md` as the single authoritative map of
all 256 opcode slots. Every extension instruction SHALL be recorded there with
its opcode, mnemonic, operand encoding, byte count, cycle count, clobber set and
owning change. Slots defined by the WDC 65C02 or the Rockwell R65C02 SHALL be
marked reserved and SHALL NOT be allocated to a new instruction.

#### Scenario: Slot claimed twice

- **WHEN** the registry check runs and two entries claim the same opcode
- **THEN** the check fails and names both claimants

#### Scenario: Reserved slot claimed

- **WHEN** an extension instruction is registered on a slot marked reserved for
  a 65C02 or R65C02 instruction
- **THEN** the check fails and names the reserved instruction

### Requirement: Instruction Purity

Every instruction added by an ISA extension SHALL satisfy the following purity
rules, and its spec delta SHALL state its preconditions and clobber set
explicitly.

- **P1 — No preconditions.** The instruction's result SHALL NOT depend on any
  flag or register that the programmer must establish beforehand.
- **P2 — Minimal declared clobber set.** The instruction SHALL NOT modify `A`,
  `X` or `Y` unless that register is its named result, and SHALL modify only the
  flags listed in its declaration.
- **P3 — No hidden temporaries.** The instruction SHALL be writable as one
  source line referring only to symbols the program already defines, without the
  assembler allocating scratch storage.

#### Scenario: Instruction requiring a flag setup is rejected

- **WHEN** a proposed instruction's result depends on the state of the carry
  flag on entry
- **THEN** it violates P1 and SHALL NOT be added

#### Scenario: Memory-to-memory move preserves registers

- **WHEN** a memory-to-memory move instruction executes
- **THEN** `A`, `X` and `Y` hold the same values as before the instruction

### Requirement: Ergonomic Acceptance Gates

An ISA extension SHALL NOT be archived until gates G1 through G8 pass, as
defined in the extension programme's design record.

- **G1** purity rules P1–P3 hold for every added instruction
- **G2** every added instruction is registered and claims no reserved or
  already-claimed slot
- **G3** every added instruction replaces an idiom occurring at least 8 times in
  the measured corpus, or carries a written rewrite-based justification
- **G4** every added instruction is no worse in bytes and no worse in cycles
  than the sequence it replaces, and strictly better in at least one
- **G5** static instruction count of the migrated corpus falls by at least the
  slice's declared target, and the built binary does not grow
- **G6** the plumbing ratio is non-increasing
- **G7** the compatibility contract above holds
- **G8** frame-work cycles on a fixed input replay do not increase

#### Scenario: Slice with an unused instruction is blocked

- **WHEN** a slice adds an instruction whose replaced idiom occurs 5 times in
  the corpus and no rewrite justification is supplied
- **THEN** gate G3 fails and the slice is not archivable

#### Scenario: Slice that trades cycles for bytes is blocked

- **WHEN** a migrated corpus shrinks in bytes but frame-work cycles rise
- **THEN** gate G8 fails and the slice is not archivable

### Requirement: Ergonomic Metrics Tool

The project SHALL provide `tools/isa_metrics.py`, invoked by `make metrics`,
which computes the corpus metrics from `src/*.asm` and the simulator, emits a
JSON report, compares it against `docs/isa-baseline.json`, and exits non-zero
when any gate regresses.

The report SHALL include: total static instruction count, built binary size,
`toll`, `ceremony`, `transfers`, `spills`, the derived plumbing ratio, per-idiom
occurrence counts, frame-work cycles, and a pass/fail line per gate.

#### Scenario: Regression detected

- **WHEN** `make metrics` runs after a change that raises the plumbing ratio
- **THEN** it prints the failing gate with its before and after values and exits
  with a non-zero status

#### Scenario: Parser drift detected

- **WHEN** the instruction count derived from the source differs from the count
  derived from the built binary by more than 2%
- **THEN** the tool reports a parser-drift error and exits non-zero

### Requirement: Recorded Corpus Baseline

The project SHALL record the pre-extension measurement in
`docs/isa-baseline.json` as the fixed reference point for all gate comparisons.
The baseline SHALL identify the corpus by git commit so a measurement can be
reproduced.

#### Scenario: Baseline is reproducible

- **WHEN** `make metrics` runs against the commit named in the baseline
- **THEN** it reports metrics identical to the recorded baseline values
