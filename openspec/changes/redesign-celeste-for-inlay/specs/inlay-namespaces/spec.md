## ADDED Requirements

### Requirement: Lexical Namespace Declarations

The frontend SHALL accept `namespace NAME` ... `end` blocks. A namespace SHALL
form a compile-time lexical scope and SHALL NOT allocate storage, emit runtime
initialization or imply dynamic dispatch.

#### Scenario: Namespace contains declarations

- **WHEN** a namespace contains constants, types, locations and procedures
- **THEN** each declaration has a fully qualified name beginning with that
  namespace and retains its ordinary runtime semantics

#### Scenario: Namespace is empty

- **WHEN** a namespace reaches `end` without a member
- **THEN** translation succeeds and emits no runtime output for that namespace

### Requirement: Nested Namespace Membership

Namespaces SHALL contain constants, target data labels, enums, structures,
unions, overlays, locations, pools, procedures and nested namespaces supported
by the selected language slice. A nested declaration's canonical name SHALL
contain every enclosing component in source order.

#### Scenario: Procedure belongs to a subsystem

- **WHEN** `proc update` is declared within `namespace Player`
- **THEN** its canonical frontend name is `Player.update`

#### Scenario: Generated data belongs to a subsystem

- **WHEN** `draw_palette:` is declared within `namespace Gfx`
- **THEN** the label and validated raw references use the canonical name
  `Gfx.draw_palette`

#### Scenario: Namespace is nested

- **WHEN** `namespace Sprite` appears within `namespace Gfx` and declares
  `player`
- **THEN** the canonical name is `Gfx.Sprite.player`

### Requirement: Deterministic Lexical Lookup

An unqualified reference SHALL search the innermost namespace, then each
enclosing namespace, then the global scope. A qualified reference SHALL resolve
from its written root and SHALL NOT perform suffix matching. The frontend SHALL
reject ambiguous or missing references.

#### Scenario: Private helper is referenced locally

- **WHEN** `Player.update` refers to unqualified `sample_input` and
  `Player.sample_input` exists
- **THEN** the reference resolves to `Player.sample_input`

#### Scenario: Qualified reference names another subsystem

- **WHEN** player code calls `Collision.solid_at`
- **THEN** lookup resolves exactly that exported qualified procedure

#### Scenario: Qualified suffix happens to match

- **WHEN** source refers to `update` outside a namespace and only
  `Player.update` exists
- **THEN** translation reports an unknown name rather than resolving by suffix

### Requirement: Explicit Module Exports

Names declared in a semantic module SHALL be private to that module by default.
An `export NAME` declaration inside a namespace SHALL expose that member under
its fully qualified name to other semantic modules. Exporting a nested
namespace SHALL expose the namespace name but SHALL NOT implicitly export its
private descendants.

#### Scenario: Exported member is used by another module

- **WHEN** `Gfx` exports `draw_palette` and another module refers to
  `Gfx.draw_palette`
- **THEN** the reference resolves across the module boundary

#### Scenario: Private generated constant is used externally

- **WHEN** another module refers to an unexported `Gfx.sheet_bytes`
- **THEN** translation fails with a private-name diagnostic identifying its
  defining module

#### Scenario: Same-module private member is used

- **WHEN** a declaration in the defining module refers to an unexported member
  by a valid lexical name
- **THEN** the reference resolves normally

### Requirement: Collision-free Target Symbols

Each exported storage or procedure name requiring a target symbol SHALL lower
through a deterministic, collision-free encoding of its qualified components.
The encoding SHALL distinguish qualified names from source identifiers
containing underscores. Diagnostics and source maps SHALL retain the canonical
source name rather than exposing the encoded target spelling.

#### Scenario: Qualified and underscored names coexist

- **WHEN** source declares `Player.update` and global `Player_update`
- **THEN** they emit distinct target symbols

#### Scenario: Procedure contains target-local labels

- **WHEN** two namespaced procedures each contain `.done`
- **THEN** each local label belongs to its own emitted procedure scope

### Requirement: Bounded Namespace State

Namespace depth, namespace records, exports and qualified-name storage SHALL
use caller-supplied bounded workspace. Exact-capacity use SHALL succeed and
one-past-capacity use SHALL fail deterministically before partial target output.

#### Scenario: Namespace depth is exhausted

- **WHEN** source opens one namespace beyond the configured nesting limit
- **THEN** translation reports the actual and permitted depth at the opening
  declaration

#### Scenario: Export capacity is exhausted

- **WHEN** source declares one more export than the configured capacity
- **THEN** translation reports an export-capacity diagnostic

#### Scenario: Scoped-label capacity is exhausted

- **WHEN** source declares one more namespace data label than the configured
  capacity
- **THEN** translation reports a label-capacity diagnostic

### Requirement: Namespace Syntax Remains Assembly-like

The initial namespace slice SHALL NOT add wildcard imports, namespace aliases,
implicit imports or runtime namespace objects. Fully qualified dots and lexical
lookup SHALL be the only cross-scope reference mechanisms.

#### Scenario: Wildcard import is attempted

- **WHEN** source attempts a wildcard or `using namespace` declaration
- **THEN** translation rejects it as unsupported rather than changing lookup
  implicitly
