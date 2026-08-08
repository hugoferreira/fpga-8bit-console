## ADDED Requirements

### Requirement: Bitwise Compile-time Operators
The frontend expression evaluator SHALL support unary `~` and binary `&`,
`^`, `|`, `<<`, `>>` over target-storage-unit integers, with precedence
(tightest first): unary operators; `* / %`; `+ -`; `<< >>`; `&`; `^`; `|`.
A bitwise expression SHALL yield a plain integer, never an enum type. An
operand of a comparison, equality, `&&` or `||` operator that is itself an
unparenthesized bitwise expression SHALL be rejected with a diagnostic, and
vice versa; mixing bitwise operators with arithmetic operators SHALL remain
unrestricted. A bitwise result bound to an N-unit operand SHALL be masked
to N units at the operand, and any range check SHALL apply to the masked
value in masking contexts (byte-update masks, `data u8`, byte immediates,
word-immediate halves); contexts defined as rejecting out-of-range values
(word immediates as a whole, enum member values, explicit field offsets)
SHALL reject before masking.

#### Scenario: Complemented mask in a typed byte update
- **WHEN** source contains `and [p + T.flags], #~M` where `M` is a
  one-byte constant
- **THEN** the frontend evaluates `~M`, masks it to one storage unit, and
  emits the registered byte-update lowering with that mask, with bytes
  identical to the raw `#<!M` spelling

#### Scenario: Unparenthesized bitwise/comparison mix rejected
- **WHEN** a compile-time expression contains `a & b == c` without
  parentheses
- **THEN** the frontend reports a stable-code diagnostic identifying the
  ambiguous mix, and assembly fails

#### Scenario: Enum members compose to a plain integer
- **WHEN** an operand is `#EnumA.x | EnumA.y`
- **THEN** the result is a plain integer immediate whose emitted bytes
  equal the raw spelling's, with no enum-range validation applied to the
  composed value

### Requirement: Decrement-unless-zero Branch Operation
The frontend SHALL accept `decz [pointer + Type.field], label` for one-byte
scalar fields of a registered pointer base. When the field is zero, control
SHALL branch to `label` with the field unmodified; otherwise the field
SHALL be decremented and control falls through with A holding the
post-decrement value. Flags other than the branch decision SHALL be
unspecified. Arrays, non-byte fields, and fixed overlays SHALL be rejected.

#### Scenario: Timer at zero branches without writing
- **WHEN** `decz [pObj + T.timer], .done` executes with the field equal to 0
- **THEN** control transfers to `.done` and the field still reads 0

#### Scenario: Nonzero timer decrements and falls through
- **WHEN** `decz [pObj + T.timer], .done` executes with the field equal to 1
- **THEN** the field reads 0 afterward, control falls through, and A holds 0

### Requirement: Word Zero-test Operation
The frontend SHALL accept `tstw [pointer + Type.field]` for two-unit fields
and `tstw wordloc` for declared two-unit locations, lowering to a low-unit
load followed by a high-unit inclusive-or. Z SHALL be set iff the two-unit
value is zero; N SHALL be documented as meaningless; A and flags are
clobbered; X and Y are preserved.

#### Scenario: Zero word field sets Z
- **WHEN** `tstw [pObj + T.speed_x]` executes with both field units zero
- **THEN** Z is set and a following `beq` branches

#### Scenario: Word location form
- **WHEN** `tstw Fixed.word0` executes with a nonzero value
- **THEN** Z is clear, and X and Y hold their prior values

### Requirement: Word Immediate and Word Move Operations
The frontend SHALL accept `movw wordloc, #expr16`,
`movw wordloc, wordloc` and `stw [pointer + Type.field], #expr16`, where
each destination word location is a declared two-unit physical location and
each `#expr16` is a compile-time expression whose value fits 16 bits signed
or unsigned; out-of-range values SHALL be rejected. Lowering transfers the
low unit then the high unit through A in target byte order; A and flags are
clobbered.

#### Scenario: Negative constant in one spelling
- **WHEN** source contains `movw Fixed.word1, #-K` for a 16-bit constant `K`
- **THEN** both emitted immediate bytes equal the two's-complement halves
  the paired `#<(-K & $FFFF)` / `#>(-K & $FFFF)` spelling produces

#### Scenario: Word location copy
- **WHEN** source contains `movw Fixed.word2, Player.accel` with both
  declared as two-unit locations
- **THEN** the lowering copies low then high through A and no other
  location changes

#### Scenario: Immediate store through a pointer field
- **WHEN** source contains `stw [pObj + T.speed_y], #K`
- **THEN** the lowering writes both field units via pointer-displacement
  stores and both displacements are validated against the target range

### Requirement: Invoke Marshalling Order and Elision
`invoke` SHALL marshal bindings under an explicit ordering contract:
register-borne sources are saved before any typed-field source is read,
typed-field sources are read before any destination is written, and a
typed-field source SHALL take a read-dependency on its base pointer
location such that a binding writing that pointer is ordered after the
read or rejected when no safe order exists. A binding whose source
location equals its destination placement SHALL emit no code and reserve
no scratch. Scratch SHALL be reserved only for bindings that conflict
under the ordering contract, and per-site scratch usage SHALL be recorded
in the source map.

#### Scenario: Identity binding is free
- **WHEN** `invoke f, self=pObj` binds to a member placed in `pObj`
- **THEN** no instructions and no scratch units are attributed to that
  binding

#### Scenario: Receiver-writing binding ordered after field reads
- **WHEN** an invocation binds `self=pOth` and `x=[pObj + T.x]` where the
  callee places `self` in `pObj`
- **THEN** the field read through `pObj` is emitted before any write to
  `pObj`

### Requirement: Invoke Word-immediate and Typed-field Sources
`invoke` SHALL accept a 16-bit immediate source for a `u16` member placed
in a declared two-unit location, lowering through the word-immediate move,
and SHALL reject a 16-bit immediate bound to a one-unit member. `invoke`
SHALL accept typed-field sources `[pointer + Type.field]` for one- and
two-unit leaves, with an optional constant byte displacement written
`[pointer + Type.field] + K`, applied after the field read.

#### Scenario: Word immediate to a word member
- **WHEN** `invoke Fixed.approach, amount=#$0026` binds to a `u16` member
  in a two-unit location
- **THEN** the marshalling emits the word-immediate move into that location

#### Scenario: Field source with constant displacement
- **WHEN** `invoke Objects.spawn_smoke, x_position=[pObj + T.x] + 4` binds
  to a byte member
- **THEN** the field is read, 4 is added, and the result reaches the
  member's placement before the transfer

### Requirement: Invoke Tail Transfer
`invoke tail` SHALL perform identical marshalling to `invoke` and emit the
final transfer as `jmp` instead of `jsr`. It SHALL be rejected with a
diagnostic when the enclosing procedure's frame size is greater than zero.

#### Scenario: Tail call from a zero-frame procedure
- **WHEN** `invoke tail g, x=a` appears in a default-frame procedure with
  no frame members
- **THEN** marshalling is followed by `jmp` to the callee and no `jsr`/
  `rts` pair is emitted

#### Scenario: Tail call rejected with a live frame
- **WHEN** `invoke tail g` appears in a procedure with one frame byte
- **THEN** assembly fails with a stable-code diagnostic naming the frame
  conflict

### Requirement: Pool-emitted Address Tables
The `pool` declaration SHALL accept an emitting form
`pool name : Type[N] at BASE emit table qlow, qhigh` where `qlow` and
`qhigh` may be qualified names. The frontend SHALL generate the low and
high address-byte tables from the pool's base, stride and count. The
non-emitting `table` form SHALL remain valid. Qualified generated table
labels SHALL resolve in raw indexed operands, including with constant
offsets.

#### Scenario: Emitted tables match handwritten bytes
- **WHEN** a pool with base `OBJPOOL`, stride 64 and count 16 uses
  `emit table Objects.slot_lo, Objects.slot_hi`
- **THEN** the generated tables are byte-identical to the corresponding
  handwritten low/high tables

#### Scenario: Qualified table with offset in an indexed operand
- **WHEN** raw source reads `lda Objects.slot_lo + 1, x`
- **THEN** the operand resolves to the generated label plus one and
  assembles

### Requirement: Namespace Convention Default and Export Qualifier
`namespace X using <target>` SHALL set the default procedure convention for
procedures declared inside; a per-procedure `using` SHALL override it.
`export` SHALL be accepted as a declaration qualifier on procedures,
locations, constants and scoped labels, equivalent to a header `export`
line; header lists SHALL remain valid. Adopting either form SHALL NOT
change emitted bytes.

#### Scenario: Namespace default convention
- **WHEN** a namespace declares `using console6502` and a procedure inside
  omits its `using` clause
- **THEN** the procedure receives the console6502 convention and its
  lowering is identical to the explicit spelling

#### Scenario: Byte-identical adoption
- **WHEN** a module converts header export lists and per-proc `using`
  clauses to the new forms with no other change
- **THEN** a forced production build produces an identical ROM digest

### Requirement: Pinned Byte Update Register Contract
The typed byte updates `inc`, `dec`, `and`, `ora` SHALL be documented and
tested to leave the post-operation value in A with N and Z derived from
it, verified against a reference model over all 256 pre-operation values.

#### Scenario: Post-decrement observation
- **WHEN** `dec [pObj + T.delay]` executes with the field equal to 0
- **THEN** A holds $FF and N is set

### Requirement: Bounded Resources for New Declarations
Inline procedures, inline expansion sites, inline expansion depth, method
tables, method-table rows and method-table columns SHALL be bounded
resources in the workspace contract with explicit limits, stable
diagnostic codes, and tests exercising the exact limit and one past it.
Inline expansion SHALL charge its body's operations and lines against the
existing structured-operation and flattened-source budgets.

#### Scenario: Expansion-site limit enforced
- **WHEN** a source exceeds the inline expansion-site limit by one
- **THEN** the frontend reports the resource's stable diagnostic code with
  actual value and limit
