## Context

The portable frontend currently has one aggregate form: a nominal,
alignment-one structure whose fields are laid out consecutively. That covers
Celeste's record but not tagged game state, alternative interpretations of the
same bytes, sparse hardware layouts or fixed storage viewed through multiple
nominal types. Existing work also established constraints that this change must
preserve: bounded caller-owned storage, conservative C89 portability,
structured semantic events, raw target assembly as an escape hatch and exact
assembly equivalence through the customasm bootstrap.

This change follows `add-unified-procedure-locations`. It changes layout and
typed-address semantics only; procedure roles, invocation and frame behavior
remain orthogonal.

## Goals / Non-Goals

**Goals:**

- Add enums as fixed-width nominal scalar layout types and compile-time values.
- Add sparse but ordered packed structure placement with explicit offsets.
- Make packed layout the default and add deterministic `aligned(N)` layout.
- Add nominal unions with mechanically obvious overlapping storage.
- Add non-owning named views over fixed target symbols.
- Make all new state bounded, deterministic, source-correlated and available
  to a future in-console emitter.
- Retain exact target bytes for existing inputs and focused console6502
  lowering.

**Non-Goals:**

- Runtime discriminant checking or automatic coupling between an enum tag and
  a union.
- Constructors, destructors, ownership, active-union-member tracking or
  automatic initialisation of explicit gaps.
- Anonymous unions, anonymous fields, C bitfields or target-native ABI layout.
- Implicit enum numbering, implicit integer/enum conversions or instruction
  operand rewriting outside target-registered semantic forms.
- Static-object allocation, arrays of overlays, pointer casts, methods,
  indirect dispatch or native machine-code encoding.

## Decisions

### Enums require an underlying type and explicit values

Canonical syntax is:

```asm
enum ObjectKind : u8
    player = 1
    balloon = 2
    platform = 3
end
```

The underlying type is restricted initially to `u8`, `i8`, `u16` or `i16`.
Every member has an explicit compile-time expression and is referenced as
`ObjectKind.player`. Explicit values avoid hidden renumbering when members are
reordered or inserted, which matters for save data, hardware and game tables.
Names are unique, but equal values are allowed because low-level formats often
have aliases.

Enums resolve in declaration order. A value may use integer operators and
previously declared qualified enum members; self-reference and forward
reference are rejected. Enums and unions must each contain at least one member,
so neither declaration is a vacuous name with no representable variant.

An enum is nominal for type checking and scalar for layout: its size and signed
range come from the underlying primitive. No runtime representation beyond
those storage units is introduced. Enum constants are initially accepted only
in frontend-owned compile-time expressions and registered semantic operands;
the core does not search and rewrite arbitrary raw instruction text.

Automatic zero-based numbering was rejected for this slice because it makes
binary representation depend on declaration order. A later opt-in syntax can
be proposed without changing explicit declarations.

### Explicit structure offsets advance a monotonic cursor

Canonical syntax follows the existing field declaration:

```asm
struct DeviceBlock
    status : u8 at 0
    control : u8 at 4
    data : u16 at 8
end
```

An unqualified field begins at the cursor. An `at` expression supplies its
offset and must be at or beyond the cursor. The cursor then advances to the
field end. Gaps contribute to structure size but have no field, emitted bytes
or initialisation policy.

An explicit gap may deliberately omit fields that exist in the backing memory
but are irrelevant to this nominal view. A view need not name every byte from
zero through its highest field, and its size is simply one past the highest
described field end. The omitted bytes have no path or property through that
type; another overlay over the same base may describe them independently.

For example:

```asm
struct ObjectHeaderView
    kind : ObjectKind at 0
    flags : u8 at 17
end

struct ObjectMotionView
    x : i8 at 2
    y : i8 at 3
    vx : i8 at 6
    vy : i8 at 7
end
```

Both are complete nominal layouts even though each deliberately describes only
a subset of a larger object record.

Allowing later declarations to backfill earlier gaps was rejected. A monotonic
cursor keeps source order equal to address order, makes overlap diagnostics
local and prevents an innocent-looking later field from changing the meaning
of an earlier reserved region. Intentional overlap uses a union or separate
overlays.

### Packed is the default; aligned layout is explicit

The accepted aggregate headers are:

```asm
struct Dense
struct Dense packed
struct AbiShape aligned(4)

union Value
union Value packed
union Register aligned(2)
```

Omitting a policy means `packed`. The explicit `packed` spelling remains valid
as documentation and preserves existing source. Combining `packed` and
`aligned(N)`, repeating a policy or naming an unknown policy is an error.

`aligned(N)` is deterministic language layout, not delegation to a target ABI.
`N` is a positive power of two measured in target addressable storage units;
on current byte-addressed targets those units are bytes. A target publishes the
largest alignment its representation supports and rejects a larger value.

Within `aligned(N)`, effective field alignment is:

- `min(type size, N)` for fixed-width primitives and enum underlying types;
- `min(pointer storage units, N)` for pointers;
- `min(declared aggregate alignment, N)` for nested structures and unions;
- the effective alignment of the element type for fixed arrays.

Before an implicit field, the cursor is rounded upward to its effective
alignment. An explicit `at` offset must be at or beyond the cursor and divisible
by the field's effective alignment. After the last field, total size is rounded
up to `N`, and the aggregate publishes alignment `N`. Automatic field padding
and tail padding have no field paths or initialisation behavior.

For example:

```asm
struct Example aligned(4)
    a : u8
    b : u16
    c : u8
end
```

resolves `a` at 0, `b` at 2, `c` at 4, size 8 and alignment 4.

Treating `aligned(N)` as target-native layout was rejected because it would
make declarations depend on undocumented ABI policy. Treating it as “place
every field on an N-unit boundary” was rejected because it wastes space and
ignores field type. A future ABI-specific policy requires a distinct explicit
keyword and backend contract.

The resolved alignment is also a placement requirement. Pools, fixed overlays
and frame locations that contain an aligned aggregate publish `N` to their
backend. A platform that can resolve a fixed base must verify its divisibility;
a backend that cannot provide the required frame or pointer alignment rejects
that placement rather than silently treating it as packed. Layout calculation
itself remains useful even when a particular storage class cannot satisfy it.

### Unions reuse field records but have a distinct nominal kind

Canonical syntax mirrors structures:

```asm
union ObjectPayload
    player : PlayerState
    balloon : BalloonState
end
```

Every member offset is zero. A default or explicit `packed` union has alignment
one and size equal to its maximum member extent. An `aligned(N)` union has
alignment `N` and rounds its maximum member extent up to `N`; member
interpretation uses the same effective-alignment cap as an aligned structure.
Union members accept primitives, enums, pointers, complete structures,
complete unions and fixed arrays. `at` is rejected because it conflicts with
the defining union rule. Structure/union resolution shares one bounded
by-value dependency graph so cycles cannot hide across aggregate kinds.

Representing a union as a structure with an `overlap` flag was rejected at the
source level: a distinct declaration communicates intent and prevents
accidental overlap from being normalized into a feature. Internally the two
kinds may share field storage and path traversal code.

### Overlays are named, fixed-base, non-owning views

Canonical syntax is:

```asm
overlay object_header : ObjectHeader at OBJECT_RAM
overlay player_view : PlayerObject at OBJECT_RAM
```

The base is a target symbol, following the existing fixed-pool base model.
The declared type must resolve to a complete structure or union. Multiple
overlays may share a base. An overlay owns neither the base symbol nor its
bytes and therefore emits no storage, initialisation, constructor or lifetime
event.

Overlay views sharing a base do not need equal sizes and do not need to cover
the same offsets. Their declared fields may overlap because the overlap is
between independent interpretations, not between fields inside one structure.
Thus the two sparse layouts above may be composed as:

```asm
overlay header : ObjectHeaderView at OBJECT_RAM
overlay motion : ObjectMotionView at OBJECT_RAM
```

`header` can address offsets 0 and 17 while `motion` can address offsets 2, 3,
6 and 7. The declarations impose no ownership, exclusivity or backing-region
size check.

The explicit typed operand remains type-qualified:

```asm
lda [player_view + PlayerObject.health]
```

This avoids introducing a second short field-path convention. The semantic
event distinguishes a static overlay base from an indirect typed location, so
console6502 can lower a byte access to absolute base-plus-displacement while a
different target may reject it or select another registered form.

Pointer reinterpretation was excluded from this first overlay form. Explicitly
casting one physical pointer location between nominal types has aliasing and
clobber implications better handled with the later typed address/object work.

### Properties and semantic output remain representation-independent

Enums publish their size, underlying signedness/width and qualified member
values. Unions publish size/alignment plus ordinary field offset/size/count/
stride properties. Explicit structure fields publish their resolved offsets.
Overlays publish their nominal type and base symbol but do not manufacture an
address integer when the target symbol is not numerically known.

The host emitter uses the existing collision-free mangling family for generated
enum and layout constants. Core events contain handles, numeric values and
source slices rather than generated customasm spellings. Raw assembly is not
rewritten to substitute qualified enum names.

### Every new collection is independently bounded

`LaLimits`, `LaStats` and workspace calculation gain independent maxima and
high-water counts for enums, enum members, unions and overlays. Exact and
one-past tests cover each table. Aggregate-kind and explicit-offset fields
reuse the existing bounded field and expression tables. No recursive
host-stack traversal is added; the existing bounded iterative layout resolver
is extended across both aggregate kinds.

### Adoption is fixture-first

The focused structured fixture will exercise:

- signed and unsigned enum bounds and aliases;
- implicit and explicit structure placement with gaps;
- omitted/explicit packed compatibility and deterministic aligned padding;
- union size and nested member paths;
- two overlays over one fixed symbol;
- exact absolute console6502 overlay byte loads and stores;
- deterministic properties and source maps.

A handwritten customasm reference will prove exact instruction and data bytes.
The complete Celeste frontend ROM remains a regression gate, but owned game
source will not be edited to manufacture examples.

## Risks / Trade-offs

- **[Enum constants cannot yet appear naturally in every raw instruction]** →
  Document the boundary and accept them only in frontend-owned expressions or
  registered operands; later typed-immediate work can extend this without raw
  text rewriting.
- **[Explicit gaps may be mistaken for reserved storage]** → State that gaps
  omit bytes from one view and have no field, ownership or initialisation
  behavior; require an explicit `u8[n]` field when the bytes themselves need a
  name in that view.
- **[Union access can reinterpret invalid bit patterns]** → Keep active-member
  and runtime validity entirely explicit; the language only calculates bytes.
- **[Overlay names may look like allocated objects]** → Require `at BASE` and
  emit no storage; semantic events label the declaration as a non-owning view.
- **[Future alignment rules could change union size]** → Specify deterministic
  `packed` and `aligned(N)` policies now and leave native ABI layout separate.
- **[Alignment may be mistaken for a target ABI promise]** → Publish the
  storage-unit algorithm, resolved offsets, padding, size and alignment rather
  than consulting undocumented ABI rules.
- **[New tables increase the fixed workspace]** → Publish the revised default
  reservation and measure it; keep each limit independently reducible for the
  eventual console profile.

## Migration Plan

1. Extend the public bounded records, limits, statistics, events and stable
   diagnostics without changing existing defaults semantically.
2. Add enum, aggregate-kind and optional layout-policy parsing, then resolve
   the combined layout graph.
3. Add packed-default, aligned cursor placement, explicit offsets and property
   evaluation.
4. Add overlay declarations, typed resolution and console6502 static access
   events.
5. Add strict C89, UBSan, cc65/ca65, capacity, negative and determinism tests.
6. Add focused handwritten assembly equivalence and rerun complete Celeste ROM
   equivalence and repository gates.
7. Update the language and corpus examples, sync the delta specification, then
   archive.

Rollback consists of removing the new declarations and records; existing
packed-structure source requires no migration and retains its prior layout.

## Open Questions

- Whether a later enum extension should permit an explicit opt-in
  auto-increment syntax.
- Whether fixed overlays should later accept arrays and numeric base
  expressions in addition to one target symbol.
- Whether pointer overlays should be introduced with typed address-of
  expressions or remain an explicit cast facility.
- Which registered typed-immediate forms should first accept enum constants in
  executable instructions.
