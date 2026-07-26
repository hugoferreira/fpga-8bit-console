## MODIFIED Requirements

### Requirement: Authoritative Celeste Object Layout
The Celeste frontend entry SHALL declare the complete packed 64-storage-unit
object layout as an 18-unit common core and a 46-unit variant payload union,
including nested fixed-point values, the nested hitbox and five hair nodes.
Production source SHALL consume qualified layout properties and typed
operations directly rather than defining `O_*` compatibility symbols.

#### Scenario: Layout matches the established memory map
- **WHEN** the Celeste layout-aware entry is translated
- **THEN** its size is 64, hair begins at 37, nested hitbox members occupy
  offsets 12 through 15, and every consumed variant field resolves to its
  established storage unit

#### Scenario: Object layout grows
- **WHEN** a field moves or the record grows beyond 64 storage units
- **THEN** translation fails at a layout assertion before customasm accepts a
  game image

### Requirement: Complete Frontend Build Path
`make GAME=celeste hex` SHALL translate the production Celeste Inlay entry with
the portable semantic core and SHALL pass the resulting custom-CPU assembly to
the pinned customasm encoder. It SHALL retain binary, symbol, converted-label
and readmemh outputs. Production Celeste output SHALL NOT be required to
assemble with ca65.

#### Scenario: Celeste image is built
- **WHEN** a user runs `make GAME=celeste hex`
- **THEN** generated assembly and its source map are written beneath
  `build/inlay/` before customasm produces `build/celeste.bin`,
  `build/celeste.sym`, `build/celeste.lbl` and `rtl/ram.hex`

#### Scenario: Frontend portability is tested
- **WHEN** the Inlay portability suite runs
- **THEN** the frontend core still compiles under cc65 independently of whether
  ca65 can encode the generated Celeste instruction stream

### Requirement: Celeste Functional Regression
The reset-vector Celeste suite SHALL run against the customasm image produced
through Inlay. Functional assertions SHALL be supplemented by deterministic
framebuffer checkpoints, PSG command traces, memory-layout assertions and
resource/custom-operation metrics.

#### Scenario: Redesigned game is tested
- **WHEN** a user runs `make test-celeste`
- **THEN** boot, physics, collision, audio, HUD and room-transition tests run
  against the frontend output together with visual, audio and resource gates

#### Scenario: Instruction bytes differ from Phase A
- **WHEN** custom-CPU adoption changes the generated ROM while all behavioral
  and resource gates pass
- **THEN** the build is accepted and reports the new image digest

### Requirement: Typed Celeste Module Migration
The production Celeste modules SHALL use typed field, overlay, offset, word and
read-modify-write operations wherever the frontend and selected target define
the required semantics. Raw target instructions SHALL remain available for
forms whose register, flag, volatility or clobber behavior cannot be expressed.

#### Scenario: Direct field operation is eligible
- **WHEN** a Celeste module loads or stores a supported byte field
- **THEN** source names its owning typed field path

#### Scenario: Residual indexed operation needs its offset
- **WHEN** a following raw operation requires Y to contain a field displacement
- **THEN** source explicitly materializes the qualified field offset without an
  `O_*` alias

#### Scenario: Typed form is not semantically equivalent
- **WHEN** no registered typed operation preserves the required machine-state
  contract
- **THEN** source retains explicit target assembly and conformance records the
  explained exception

### Requirement: Celeste Structured Address and Procedure Migration
The production Celeste modules SHALL express pool addressing, lifecycle
dispatch and subsystem entry points through typed addresses, qualified
procedure identities and explicit physical parameter contracts. Generated
method tables SHALL NOT name backend-mangled symbols directly.

#### Scenario: Object pointer routine is migrated
- **WHEN** object-pool code materializes a slot address
- **THEN** it uses the typed pool address operation and a scoped procedure
  contract

#### Scenario: Lifecycle table is emitted
- **WHEN** dispatch metadata is generated
- **THEN** low/high entries resolve from qualified procedures through semantic
  data declarations

## REMOVED Requirements

### Requirement: Narrow Build-only Source Adaptation

**Reason**: Production Celeste is now authoritative Inlay source; a generated
compatibility copy would preserve the mechanical port and prevent module-level
redesign.

**Migration**: Edit the production `.inlay.asm` modules directly and retain the
Phase-A corpus only as a historical baseline.

### Requirement: Assembly Equivalence Gate

**Reason**: Custom-CPU instruction adoption and control-flow restructuring
intentionally change the ROM.

**Migration**: Retain focused lowering-reference tests and replace full-image
equality with functional, framebuffer, PSG trace, layout and resource gates.

### Requirement: Migrated Full-ROM Equivalence

**Reason**: The Phase-A digest records the starting point but cannot be the
acceptance image for an encoding-changing redesign.

**Migration**: Record both Phase-A and redesigned digests, require deterministic
new output, and accept it through the layered redesign regression gates.
