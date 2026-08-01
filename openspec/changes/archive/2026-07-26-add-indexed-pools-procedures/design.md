## Context

The portable frontend already resolves packed layouts, direct byte field
operands and multi-file input into target-neutral semantic events. The
`console6502` host emitter lowers those events to customasm, and complete
Celeste equivalence is the adoption gate.

Three related gaps remain. Array paths cannot carry a runtime index; fixed
object pools are still handwritten addresses and tables; and procedure
boundaries cannot describe their physical parameters or stack responsibility.
The implementation must remain bounded C89 in the portable layer and must not
edit the Celeste sources.

## Goals / Non-Goals

**Goals:**

- Resolve one runtime index in a typed array field path and expose its stride
  to the backend.
- Describe fixed pools and materialise a typed element pointer through an
  explicit target lowering.
- Parse scoped procedures, physical parameter aliases, scalar frame locals,
  default `frame`, explicit `naked`, and semantic `ret`.
- Provide deterministic console6502 sequences and precise clobber/constraint
  diagnostics.
- Preserve focused instruction bytes and all 65,536 Celeste ROM bytes.

**Non-Goals:**

- Bounds checks, allocation tracking, register allocation or implicit value
  preservation.
- General expressions as runtime indexes, multiple indexes in one path,
  aggregate locals, stack parameters, `invoke`, return-value declarations or
  user-defined calling conventions.
- Generating pool lookup tables or choosing between optimisation strategies.
- Editing ISA rules, RTL, the owned game sources or adding native encoding.

## Decisions

### One explicit physical index

The first indexed spelling is:

```asm
lda [pObj + CelesteObject.hair[x].x.integer]
```

The index is a physical target location, not a logical value. Exactly one
array component may carry an index. The core resolves its element stride,
constant field displacement and byte leaf, then publishes those facts in a
structured event.

For `console6502`, `x` is accepted as the element index. Loads calculate
`offset + x * stride` through A and Y before an indirect-Y load. Stores save A
on the hardware stack while calculating Y, then restore it before the store.
Only power-of-two strides 1, 2, 4 and 8 are initially accepted. The event and
diagnostics remain architecture-neutral even though this lowering is not.

Alternatives considered: treating Y as a pre-scaled byte displacement loses
the declared array stride; silently selecting scratch storage hides clobbers.

### Pools declare an explicit address-table strategy

The first pool form is deliberately concrete:

```asm
pool objects : CelesteObject[16] at OBJPOOL table obj_lo, obj_hi
```

It provides `.count`, `.stride` and `.size`. `address pObj, objects[a]`
publishes a pool-address event. The console6502 table strategy lowers to the
existing `tax`, low-table move, high-table load and high-byte store sequence.
Tables remain ordinary source so their bytes and placement stay visible.

Alternatives considered: generating tables would create hidden data; mandatory
multiply/shift lowering would be worse than the corpus's current code.

### Parameters are scoped physical aliases

Procedure headers use:

```asm
proc Name
    self : ptr CelesteObject in pObj
begin
    ...
end
```

`frame` is the default and `naked` is explicit. A parameter name resolves to
its declared physical location only inside its procedure. Overwriting the
physical location overwrites the parameter; the frontend never spills it.
The first slice accepts scalar and pointer parameters but only pointer aliases
participate in typed field operands.

### Console6502 frames use the hardware stack

Scalar locals use:

```asm
local saved : u8
lda [local saved]
sta [local saved]
```

A frame prologue emits one `pha` per local byte. A local access emits `tsx`
and an absolute-X page-one access derived from the current stack pointer. The
epilogue restores SP with `tsx`, the required `inx` steps and `txs`, followed
by `rts`. This preserves A across the epilogue but clobbers X and N/Z as a
documented backend property.

Because offsets are relative to the current SP, raw stack-mutating
instructions are rejected in a framed procedure with locals; nested `jsr`
calls are safe once they return. Naked procedures cannot declare locals.
Zero-local frame procedures elide entry and exit adjustment and `ret` lowers
directly to `rts`.

Alternatives considered: a persistent X frame pointer fails across ordinary
calls; hidden zero-page storage risks collisions; waiting for a proposed frame
pointer ISA would unnecessarily couple the language model to unimplemented
hardware.

### Procedure syntax is removed, not copied, by the emitter

Procedure declarations, parameters, locals, `begin`, `end`, pool declarations
and address operations are frontend-owned. The host emits the procedure symbol
and documented lowering sequences. Ordinary labels and raw instructions inside
the body remain unchanged.

## Risks / Trade-offs

- **[Large generated sequences for indexed stores]** → Make clobbers and exact
  bytes visible in conformance fixtures; do not claim this is an optimisation.
- **[Hardware-stack locals reduce available stack]** → Bound frame size and
  report it; preserve explicit `naked` for hand-managed routines.
- **[Raw stack mutation invalidates local offsets]** → Reject it while locals
  are active rather than attempting partial stack-delta inference.
- **[Scoped aliases add bounded tables]** → Add explicit procedure/local
  capacities and exact/one-past tests.
- **[Celeste migration could perturb layout]** → Generate copies beneath
  `build/`, assert exact converted counts and compare complete ROMs.

## Migration Plan

1. Extend the public bounded records, limits, events and diagnostics.
2. Implement indexed path resolution and focused byte-equivalence fixtures.
3. Implement pools and table-address materialisation; migrate generated
   `obj_ptr`.
4. Implement scoped procedure parsing and frame/naked lowering; wrap selected
   generated routines without changing their machine bytes.
5. Run portability, frontend, full-ROM and game functional gates.

Rollback is removal of the generated constructs and restoration of their raw
build-only module text; checked-in game sources remain untouched.

## Open Questions

- A future backend contract must generalise scratch selection beyond the fixed
  console6502 A/X/Y sequences.
- Stack-delta annotations, aggregate locals, stack parameters and nonlocal
  returns remain later procedure work.
