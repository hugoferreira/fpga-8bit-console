## Context

The frontend now has packed layouts, typed physical locations, fixed pools,
procedures, physical parameters, default frames, naked procedures and scalar
frame locals. Its declaration grammar is mostly regular: a named member is
written `name : type`, with additional words describing representation.

The provisional procedure grammar breaks that pattern for locals:
`local name : type`. It also has no representation for returns,
convention-assigned locations, pointer/aggregate frame storage or a structured
call. Adding those independently would create several unrelated mini-grammars
and move the source away from its layout-oriented foundation.

The portable core remains bounded C89 with caller-owned storage. The
console6502 backend emits customasm today, but the semantic events must remain
usable by a future in-console encoder. Every adopted lowering remains subject
to focused assembly equivalence and full Celeste ROM equivalence.

## Goals / Non-Goals

**Goals:**

- Use `name : type` for every procedure member.
- Express input, local and return roles through orthogonal qualifiers.
- Keep every name bound to a real physical or frame location.
- Allow a target convention to supply omitted input and return placements.
- Provide concise instruction-form invocation with deterministic argument
  marshalling and parallel-copy semantics.
- Support pointer and fixed-size aggregate frame locals.
- Preserve exact, inspectable target lowering and bounded resource use.

**Non-Goals:**

- General register allocation or SSA values.
- Automatic preservation of parameters across calls.
- Inferred object lifetimes, ownership, constructors or destructors.
- User-defined calling-convention declarations in the first slice.
- Stack parameters, variadic calls or ABI aggregate-by-value classification.
- Whole-procedure clobber analysis or optimisation.
- Native opcode encoding or an in-console editor shell.

## Decisions

### One procedure-member declaration

The canonical forms are:

```asm
proc Player.damage using console6502
    self       : ptr Player in pObj
    amount     : u8
    saved_self : ptr Player in frame
    result     : u8 return
begin
    ...
end
```

The grammar after the type is:

```text
input   := name ":" type [ "in" physical ]
local   := name ":" type "in" "frame"
return  := name ":" type "return" [ "in" physical ]
```

An unqualified member is an input. `return` changes its role to output.
`in frame` changes its role to local. `frame` is a reserved abstract location,
not a physical register name. Qualifiers use one canonical order; alternative
orders are rejected rather than silently normalised.

This makes role and placement explicit without adding declaration prefixes.
The alternative—retaining `local name : type` and adding `returns name :
type`—was rejected because it makes equivalent typed locations use unrelated
surface forms.

### Explicit placement wins; convention fills omissions

`proc Name using Convention` selects target-owned convention metadata.
Explicit `in <physical>` placement always wins. Each unplaced input or return
is assigned in declaration order by its type class. Failure to classify a type
or exhaustion of locations is a translation error.

The initial built-in `console6502` convention assigns scalar inputs to `A`,
`X`, then `Y`, and a scalar return to `A`. Pointer inputs and returns require
explicit locations because the target has no universal application-independent
zero-page pointer pool. Procedures without `using` continue to require
explicit placement for every input and return.

The convention is backend metadata, not a source-level `callconv` declaration.
User-defined conventions remain deferred until the target metadata model has
been exercised.

### Names remain aliases, including returns

A member denotes its assigned physical location or frame slot. Overwriting the
physical location overwrites the named value. A result declaration does not
cause `ret` to calculate, copy or preserve anything; the body must place the
result in its alias before returning.

This keeps return declarations descriptive. The alternative—treating a result
name as a compiler-managed logical value—would require value tracking and
register allocation.

### Frame is a typed placement class

`in frame` accepts fixed-size types whose complete layout is known. Locals are
laid out in declaration order with target-required alignment. The frame event
publishes total size, and each local event publishes its type, offset, size and
source span.

The first console6502 implementation supports scalar, pointer and packed
aggregate frame storage up to the existing 255-byte procedure-frame limit.
Typed pointer moves between a physical location and a frame location use:

```asm
mov [saved_self], self
mov self, [saved_self]
```

The backend lowers the complete pointer width in declaration order. Packed
aggregate locals expose their fields through the same qualified path model as
other typed storage, for example
`lda [temporary + Vec2.x]`; whole-aggregate copies remain deferred. No implicit
copy occurs at declaration or return.

The provisional `local name : type` spelling is rejected with a migration
diagnostic suggesting `name : type in frame`.

### Invocation is one assembly-style statement

Marshalled calls use:

```asm
invoke Player.damage, self=player, amount=10
```

The grammar is:

```text
invoke := "invoke" callee [ "," binding ]*
binding := name "=" value
```

A trailing comma continues the same invocation onto the next physical line:

```asm
invoke Player.damage,
    self=player,
    amount=10
```

The logical statement ends on the first line that does not end in a comma; it
does not require `end`. Bindings name the callee's input declarations. The
callee must be declared, each required input must appear exactly once, and
returns are observed through their declared physical aliases after the call.
The ordinary target `call`, `jsr` or equivalent remains raw assembly with no
marshalling.

All right-hand sides are read from the pre-invocation machine state.
Marshalling therefore has parallel-assignment semantics. The backend may use a
documented exchange instruction, volatile scratch location or bounded
frame-temporary slot. If no legal temporary exists—especially in naked
code—the invocation is rejected. A temporary is attributable to the `invoke`
event and is included in frame-size and clobber metadata.

The alternative block form was rejected because a call with one or two
arguments should remain one assembly statement. Named bindings retain
readability, and trailing-comma continuation handles the uncommon long call.

### Semantic events stay above instruction spelling

The core publishes resolved member, convention assignment, frame-copy,
parallel-move and invocation events. The console6502 host emitter turns those
events into customasm. It must publish the selected locations, frame bytes,
scratch use and clobbers; it must not embed customasm syntax in the core.

### Celeste adoption remains build-only

The generated `obj_ptr` declaration will adopt `using console6502`, omit the
scalar slot's explicit `in a`, and mark the `pObj` result as `return in pObj`.
Its body retains the typed pool address operation. This exercises unified
input/return declarations without changing the generated instructions.

Pointer/aggregate frame copies and parallel invocation are covered by focused
byte-equivalence fixtures unless an existing Celeste sequence has an exact
lowering. No source under `src/celeste/` is edited merely to manufacture an
adoption site.

## Risks / Trade-offs

- **[An unqualified member could be mistaken for a field]** → Procedure scope
  makes it an input by rule; documentation always shows the default explicitly
  alongside `return` and `in frame`.
- **[Convention defaults can conceal physical registers]** → Generated maps
  and diagnostics expose every resolved location, explicit placement wins, and
  procedures without `using` require placement.
- **[Invoke can require scratch storage]** → Model parallel assignment
  explicitly, report the selected scratch resource, and fail when no legal
  lowering exists.
- **[Aggregate frame copies can be expensive]** → Emit deterministic
  width-visible sequences and never promote or elide copies.
- **[The local spelling is breaking]** → Reject the old spelling with a direct
  replacement diagnostic and migrate all repository fixtures in one change.
- **[A convention could drift from target rules]** → Keep convention metadata
  in the target contract and cover each assignment and call sequence with
  handwritten assembly-equivalence fixtures.

## Migration Plan

1. Extend bounded member records with role, placement and convention handles.
2. Replace prefixed locals with unified member parsing and migration
   diagnostics.
3. Add target convention resolution and typed return aliases.
4. Extend frame layout and typed moves to pointers and packed aggregates.
5. Add bounded invocation bindings, parallel-copy planning and target events.
6. Add deterministic console6502 lowering and negative/capacity coverage.
7. Migrate the generated Celeste `obj_ptr` signature and retain exact counts.
8. Run focused assembly comparisons, full ROM equivalence, functional tests,
   strict C89/UBSan checks and cc65/ca65 smoke builds.

Rollback consists of restoring the prior parser/event version and build-only
Celeste signature; no persisted runtime format or owned game source changes.

## Open Questions

- Whether a later user-defined convention syntax should itself use nested
  `name : type` declarations or target-specific location-class lists.
- Whether return bindings should eventually be allowed inside `invoke`, or
  remain observable only through declared physical result locations.
- Whether a future backend may expose explicitly named scratch policies in
  source when automatic frame temporaries are undesirable.
