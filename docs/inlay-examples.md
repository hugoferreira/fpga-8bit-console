# Inlay Assembly: examples from the game corpus

## Status

Exploratory design examples. This document is not the language specification
and does not propose changes to the console ISA. The implemented first slice,
host/console boundary, exact grammar, limits and build commands are documented
in `docs/inlay.md`.

Implemented today: default/explicit packed structures, deterministic
`aligned(N)` layouts, fixed-width enums, explicit sparse offsets, unions,
non-owning fixed overlays, fixed arrays, nested field paths,
`u8`/`i8`/`u16`/`i16`, pointer fields, typed pointer locations,
`static_assert`, generated layout and pool properties, direct, overlay and
single-index byte operands, fixed pools with explicit address tables, scoped
procedures, physical parameters, default `frame`, explicit `naked`, scalar
frame locals and semantic `ret` lowering for `console6502`. The current slice
also has the target-owned `console6502` convention, return aliases, pointer and
packed aggregate frame locations, and compact parallel-assignment `invoke`.
Celeste's normal build derives
every `O_*` offset and its pool stride from the layout and is byte-identical to
the former direct-customasm build. Its build-only module copies express all 66
eligible direct `pObj`/`pOth` byte operations as typed paths and migrate
`obj_ptr` to a procedure plus typed pool address; the checked-in Celeste
sources remain unchanged.

Methods, user-defined conventions, richer pool strategies and native
instruction encoding below remain design exploration.

The examples apply the architecture-neutral Inlay Assembly concepts to
the three game programs in this repository:

- Breakout, whose state is mostly statically addressed globals and
  structure-of-arrays pools;
- Celeste, whose objects are fixed 64-byte records with per-type method tables;
- Nemo, whose fixed object pool supports class inheritance, a scene graph and
  an event bus.

The syntax is deliberately provisional. Its purpose is to expose the semantic
operations a language frontend and target backend would have to agree on.

## Reading the examples

Each example separates three things:

1. **layout declaration** -- names, types, sizes and offsets known at assembly
   time;
2. **semantic assembly** -- the programmer's machine-level intent;
3. **target lowering** -- one possible instruction sequence on this console's
   extended 6502.

The semantic source is architecture-neutral only where the operation itself is
architecture-neutral. Instruction bodies remain free to be target-specific.
Register names such as `a`, `x`, `ab` and zero-page pointer pairs such as
`pObj` make an example specifically 6502-oriented.

Generated sequences below are representative rather than commitments to exact
instruction selection.

## 1. Celeste object records

### Existing representation

Celeste stores 16 objects in a page-aligned pool. Every slot is 64 bytes. The
first 18 bytes are common object state; the remainder is a per-type area large
enough for the player, including five hair nodes.

The current source declares every offset independently:

```asm
O_TYPE = 0
O_SPR = 1
O_X = 2
O_Y = 3
O_SPDX = 4
O_SPDY = 6
...
O_HAIR = 37
O_SIZE = 64
```

### Inlay declaration

```asm
struct Fixed8_8 packed
    fraction : u8
    integer  : i8
end

struct Hitbox packed
    x : i8
    y : i8
    w : u8
    h : u8
end

struct HairNode packed
    x : Fixed8_8
    y : Fixed8_8
end

struct CelesteObject packed
    kind          : u8
    sprite        : u8
    x             : i8
    y             : i8
    speed_x       : Fixed8_8
    speed_y       : Fixed8_8
    remainder_x   : Fixed8_8
    remainder_y   : Fixed8_8
    hitbox        : Hitbox
    flip          : u8
    flags         : u8
    state         : u8
    delay         : u8
    dash_jumps    : u8
    grace         : u8
    jump_buffer   : u8
    dash_time     : u8
    dash_effect   : u8
    player_bits   : u8
    sprite_offset : u8
    dash_target_x : Fixed8_8
    dash_target_y : Fixed8_8
    dash_accel_x  : Fixed8_8
    dash_accel_y  : Fixed8_8
    target_x      : i8
    target_y      : i8
    hair          : HairNode[5]
    reserved      : u8[7]
end

static_assert CelesteObject.x.offset == 2
static_assert CelesteObject.speed_y.offset == 6
static_assert CelesteObject.hitbox.w.offset == 14
static_assert CelesteObject.hair.offset == 37
static_assert CelesteObject.size == 64
```

This declaration must emit the same bytes as the current layout. The types
exist to calculate and validate those bytes, not to create a runtime object
model.

The explicit `reserved` tail is preferable to an implicit size override. It
makes the seven unused bytes visible and ensures that adding a field cannot
silently grow the record past its pool stride.

### Sparse views over the same Celeste object

Code that needs only the common header or motion fields can describe exactly
those offsets without manufacturing padding fields:

```asm
enum ObjectKind : u8
    empty = 0
    player = 1
    spawn = 2
end

struct ObjectHeaderView
    kind  : ObjectKind at 0
    flags : u8         at 17
end

struct ObjectMotionView
    x  : i8      at 2
    y  : i8      at 3
    vx : Fixed8_8 at 4
    vy : Fixed8_8 at 6
end

overlay header : ObjectHeaderView at OBJPOOL
overlay motion : ObjectMotionView at OBJPOOL
```

The gaps in each structure mean “not part of this view”; they do not reserve,
clear or own the omitted bytes. Both overlays deliberately cover the same
fixed storage, may differ in size, and may overlap. A byte access such as
`lda [header + ObjectHeaderView.flags]` lowers to the same absolute
`OBJPOOL + 17` access a programmer would write by hand.

Alternative payload interpretations use a union rather than overlapping
fields inside one structure:

```asm
union ObjectPayload
    raw    : u8[46]
    player : PlayerState
    smoke  : SmokeState
end
```

This supplies offset and size calculations only. There is no active-member
tag, runtime check, construction, destruction or coupling to `ObjectKind`.

### Typed field access

The current `player_init` treats the zero-page pair `pObj` as its receiver.

```asm
proc CelesteObject.player_init naked
    self : ptr CelesteObject in pObj
begin
    lda #1
    sta [self + CelesteObject.hitbox.x]

    lda #3
    sta [self + CelesteObject.hitbox.y]

    lda #6
    sta [self + CelesteObject.hitbox.w]

    lda #5
    sta [self + CelesteObject.hitbox.h]

    lda max_djump
    sta [self + CelesteObject.dash_jumps]

    lda #1
    sta [self + CelesteObject.sprite]

    jmp create_hair
end
```

`self` is a typed alias for the physical pointer pair `pObj`. It is not a
virtual register and the assembler does not preserve its value if either byte
of `pObj` is overwritten.

The semantic store:

```asm
sta [self + CelesteObject.hitbox.w]
```

may lower on the current extended 6502 to:

```asm
sta (pObj), #14
```

An NMOS-compatible backend may instead lower it to:

```asm
ldy #14
sta (pObj), y
```

The field path has one compile-time meaning while the cost and clobbers belong
to the backend. In particular, the NMOS lowering must report that it consumes
`Y`.

## 2. Celeste's fixed object pool

### Declaration

```asm
pool objects : CelesteObject[16] at OBJPOOL table obj_lo, obj_hi
```

The pool declaration provides:

```asm
objects.count
objects.size
objects.stride
objects[slot]
```

with:

```asm
static_assert objects.count == 16
static_assert objects.stride == 64
static_assert objects.size == 1024
```

It does not provide allocation tracking. A zero `kind` remains the program's
explicit free-slot marker.

### Indexed address calculation

```asm
proc object_at
    object : ptr CelesteObject in pObj
    slot : u8 in a
begin
    address object, objects[a]
    ret
end
```

The language-level address is:

```text
OBJPOOL + slot * CelesteObject.size
```

The implemented console6502 backend lowers that operation with Celeste's two
16-byte tables:

```asm
tax
mov pObj, obj_lo + x
lda obj_hi, x
sta pObj+1
```

That is a legitimate backend lowering. The language must not require arithmetic
when a table is smaller and faster on the selected target. Conversely, a
backend with a scaled-add instruction need not emit or retain the tables.

If address materialisation requires a temporary and no legal temporary is
available, the backend must reject the operation or require an explicit
scratch annotation.

## 3. Celeste method tables

Celeste dispatches by object type through separate low- and high-byte tables for
`init`, `update` and `draw`. The split representation is efficient for the
6502, even though an architecture with native word loads would more naturally
use an array of records.

One possible semantic declaration is:

```asm
interface CelesteMethods
    init   (self : ptr CelesteObject)
    update (self : ptr CelesteObject)
    draw   (self : ptr CelesteObject)
end

method_table celeste_methods : CelesteMethods by kind
    Player => {
        init   = player_init
        update = player_update
        draw   = player_draw
    }
    Spawn => {
        init   = spawn_init
        update = spawn_update
        draw   = spawn_draw
    }
    Smoke => {
        init   = smoke_init
        update = smoke_update
        draw   = smoke_draw
    }
    Title => {
        init   = title_init
        update = title_update
        draw   = title_draw
    }
end
```

The runtime representation must be inspectable. On this target, the backend may
emit the existing six byte arrays:

```text
type_init_lo, type_init_hi
type_update_lo, type_update_hi
type_draw_lo, type_draw_hi
```

On a target with naturally addressable code pointers it may emit four records
containing three code pointers each.

Invocation remains explicit:

```asm
load method, celeste_methods[kind].update
bz method, .next
invoke.indirect method, self = pObj
```

The declaration supplies table shape, code-pointer width and signature
checking. It does not add dynamic dispatch to ordinary method calls.

## 4. Nemo classes and inherited lookup

### Existing representation

Nemo uses 16-byte object records. Each record points to an eight-byte class
descriptor containing a base-class pointer and three method slots. A missing
method causes the program to walk to the base descriptor and try again.

### Layout-aware declaration

```asm
struct NemoClass packed
    base   : ptr NemoClass
    init   : codeptr
    draw   : codeptr
    update : codeptr
end

struct NemoObject packed
    class        : ptr NemoClass
    x            : i8
    y            : i8
    flags        : u8
    first_child  : u8
    next_sibling : u8
    state        : u8[9]
end

static_assert NemoClass.init.offset == 2
static_assert NemoClass.update.offset == 6
static_assert NemoClass.size == 8

static_assert NemoObject.first_child.offset == 5
static_assert NemoObject.state.offset == 7
static_assert NemoObject.size == 16
```

### Explicit inherited method lookup

```asm
proc NemoObject.find_method
    self : ptr NemoObject in pObj
    slot : u8             in t3
    method : codeptr return in pFn
begin
    load pCls, [self + NemoObject.class]

.try:
    bz pCls, .none
    load pFn, [pCls + slot]
    bnz pFn, .found
    load pCls, [pCls + NemoClass.base]
    jmp .try

.found:
    ret

.none:
    clear pFn
    ret
end
```

Here `slot` may be constrained to one of:

```asm
NemoClass.init.offset
NemoClass.draw.offset
NemoClass.update.offset
```

The lookup loop remains ordinary program code. The structured language
calculates offsets, validates pointer interpretations and knows that each
method slot contains a `codeptr`; it does not silently implement inheritance.

This distinction also preserves Nemo's value as an ISA corpus: the pointer
walk and indirect call remain measurable rather than disappearing inside an
opaque runtime primitive.

## 5. Nemo event records

Nemo's event bus stores 16 entries of `{event, handler, context}`. Each entry is
four bytes.

```asm
struct Subscription packed
    event   : u8
    handler : codeptr
    context : u8
end

pool subscriptions : Subscription[16] at EVPOOL

static_assert Subscription.handler.offset == 1
static_assert Subscription.context.offset == 3
static_assert Subscription.size == 4
```

Registration can name the record rather than repeat shift counts and offsets:

```asm
proc EventBus.on
    event   : u8      in a
    handler : codeptr in pFn
    context : u8      in t6

    entry : ptr Subscription in frame
begin
    address entry, subscriptions[ev_count]

    store [entry + Subscription.event], event
    store [entry + Subscription.handler], handler
    store [entry + Subscription.context], context

    inc ev_count
    ret
end
```

For the current 6502, `subscriptions[ev_count]` can be lowered by multiplying
the index by four with two shifts, exactly as the existing code does. Another
backend may fold the scale into each memory operand.

The example raises a useful scratch-policy question: `entry` is a pointer-sized
local, but the current 6502 frame proposal places locals in zero page and its
frame-relative instruction set may not support indirect access through a
pointer stored there. A complete backend contract must say whether:

- addressable pointer locals are supported directly;
- `entry` must bind to a named zero-page pointer pair;
- the address expression is rematerialised at each use; or
- the procedure is rejected without an explicit pointer location.

## 6. Breakout's two balls

### Existing representation

The primary ball occupies eight contiguous zero-page bytes:

```text
ballx, bally, bvx, bvy
```

The secondary ball has the same eight-byte shape at `b2x`. `ball_step` operates
only on the primary addresses, so the program swaps all eight bytes before and
after updating the secondary ball.

### Layout declaration

```asm
struct Ball packed
    x  : Fixed8_8
    y  : Fixed8_8
    vx : Fixed8_8
    vy : Fixed8_8
end

object primary_ball   : Ball at $04
object secondary_ball : Ball at $4e

static_assert Ball.size == 8
```

The current flow is conceptually:

```asm
jsr ball_step

jsr swap_ball2
jsr ball_step
jsr swap_ball2
```

A receiver-based version can state the actual relationship:

```asm
invoke Ball.step, self=&primary_ball
invoke Ball.step, self=&secondary_ball
```

```asm
proc Ball.step frame
    self : ptr Ball in pObj

    center_x : i8 in frame
    center_y : i8 in frame
begin
    loadw ab, [self + Ball.x]
    addw  ab, [self + Ball.vx]
    storew [self + Ball.x], ab

    loadw ab, [self + Ball.y]
    addw  ab, [self + Ball.vy]
    storew [self + Ball.y], ab

    ...
end
```

This is intentionally also a cost example. On the current 6502:

- the primary ball's statically known zero-page fields are exceptionally cheap;
- accessing either ball through a pointer is more uniform but may cost more;
- creating a frame adds entry, exit and frame-relative access costs;
- removing two eight-byte swaps may or may not recover those costs.

The language must expose that trade-off. A structured representation is not
permission to claim that every target lowers it efficiently.

A backend may also specialise a known receiver:

```asm
invoke Ball.step, self=&primary_ball
```

could bind the receiver statically and use direct zero-page operands, while the
secondary call uses pointer-relative operands. Such specialisation must be
explicitly selected or documented because it produces two different lowering
strategies for the same logical procedure.

## 7. Breakout frame locals

`ball_step` currently uses shared globals such as `tmp` and `tmp2` for its
centre and intermediate arithmetic. This is representative of the namespace
pressure addressed by the experimental zero-page frame proposal.

```asm
proc Ball.step frame
    self : ptr Ball in pObj

    center_x : i8 in frame
    center_y : i8 in frame
    half_vx  : Fixed8_8 in frame
    half_vy  : Fixed8_8 in frame
begin
    ...
end
```

For this target, default `frame` mode could emit:

```asm
enter #6
...
leave
rts
```

and refer to locals as `f+0` through `f+5`. On ARMv7 the backend might reserve
stack space and address it relative to `sp` or a frame pointer. On a target
with sufficient registers, a backend still must not promote these locals to
registers unless the language explicitly permits register allocation.

The default frame mode is semantic responsibility, not mandatory prologue
emission. A leaf procedure with no locals may require no frame instructions.

## 8. Breakout's structure-of-arrays particle pool

Layout awareness must not imply array-of-structures storage. Breakout's particle
loop walks individual attributes across all live particles, so its
structure-of-arrays representation is appropriate.

```asm
struct ParticlePool
    x     : u8[16]
    y     : u8[16]
    vx    : i8[16]
    vy    : i8[16]
    life  : u8[16]
    color : u8[16]
    kind  : u8[16]
end

object particles : ParticlePool at scratch + $100
```

The current absolute addresses become derived properties:

```asm
static_assert particles.x.address == scratch + $100
static_assert particles.y.address == scratch + $110
static_assert particles.life.address == scratch + $140
static_assert particles.kind.address == scratch + $160
```

The hot loop remains assembly-like:

```asm
ldx particle_index
lda [particles + ParticlePool.life[x]]
beq .dead

lda [particles + ParticlePool.x[x]]
add [particles + ParticlePool.vx[x]]
sta [particles + ParticlePool.x[x]]
```

On 6502 these can lower to the existing efficient absolute-indexed accesses:

```asm
lda PLIFE, x
beq .dead
lda PPX, x
add PVX, x
sta PPX, x
```

The type system supplies field names, element widths and array counts without
changing the chosen data-oriented layout.

## 9. Memory-mapped console hardware

The layout model applies equally to volatile peripheral registers.

```asm
peripheral SpritePort at $4008
    index : volatile u8          at $00
    x     : volatile u8          at $01
    y     : volatile u8          at $02
    flags : volatile u8          at $03
    count : volatile u8          at $04
    frame : volatile readonly u8 at $05
    base  : volatile u8          at $06
end
```

Usage:

```asm
store [SpritePort.index], #0
store [SpritePort.x], ball_x
store [SpritePort.y], ball_y
store [SpritePort.base], #0
store [SpritePort.flags], #$0c
```

On the 6502 backend these are ordinary absolute stores to `$4008` through
`$400b` and `$400e`.

`volatile` is part of the semantic contract:

- accesses may have side effects;
- they must not be eliminated;
- their order must be preserved unless the target's memory model explicitly
  permits otherwise;
- a multi-instruction lowering must not imply atomicity.

Explicit field offsets also support sparse peripherals without requiring
padding bytes to correspond to real storage.

## 10. Parameters on this console

The three games already use a mixture of physical parameter locations:

- `A`, `X` and `Y` for scalar arguments and returns;
- zero-page byte pairs such as `pObj`, `pFn` and `pRow` for pointers;
- shared zero-page locations for excess arguments and results;
- the hardware stack for values that must survive nested calls.

A target backend describes `console6502` with metadata equivalent to:

```asm
backend convention console6502
    scalar_args  a, x, y
    scalar_return a
    pointer_locations target-defined-zero-page-pairs
    frame         zero-page
    call          jsr
    return        rts
    volatile      a, x, y
end
```

This is backend metadata, not a user-defined `callconv` declaration in the
current source language. An ordinary signature can use its defaults:

```asm
proc clamp using console6502
    value : u8
    low : u8
    high : u8
    result : u8 return
begin
    ; value, low, high alias A, X, Y; result aliases A
    ret
end
```

An omitted scalar input receives `A`, `X` or `Y` in declaration order, except
that an explicit placement reserves its location. An omitted scalar return
uses `A`. Returns are aliases, so `ret` does not copy a value.

This does not mean arbitrary procedures can safely receive three independent
arguments in `A`, `X` and `Y`: instruction bodies may need those registers for
addressing or arithmetic immediately. Signatures should therefore permit
explicit locations:

```asm
proc Smoke.spawn using console6502
    x : i8 in a
    y : i8 in x
begin
    ...
end
```

and pointer receivers:

```asm
proc CelesteObject.update using console6502
    self : ptr CelesteObject in pObj
begin
    ...
end
```

Parameters remain aliases for physical locations. If `tax` overwrites `X`, a
parameter residing in `X` has been overwritten. If a call clobbers `pObj`, a
receiver residing in `pObj` has been overwritten.

## 11. Preserving a receiver across a nested call

Celeste's `spawn_at` exists because spawning an object replaces `pObj`, while
the caller must continue updating its original object afterward. The current
routine manually pushes both bytes of `pObj` and restores them after the call.

A frame-mode version could make the lifetime explicit:

```asm
proc CelesteObject.spawn_at frame
    self : ptr CelesteObject in pObj
    saved_self : ptr CelesteObject in frame
begin
    mov [saved_self], self
    invoke init_object, object=self
    mov self, [saved_self]
    ret
end
```

This does not ask the assembler to preserve `self` automatically. The source
requests storage and performs the save and restore. The backend chooses the
physical local offsets and emits the frame maintenance.

Argument bindings are parallel assignments. For example:

```asm
invoke swap_xy, left=x, right=a
```

reads the original `X` and `A` before placing either destination. On the
current backend that is a deterministic snapshot into `t0` and `t1`, followed
by the assignments and `JSR`. A three-way cycle similarly uses three scratch
bytes. Those scratch bytes, destination argument locations and the target call
clobbers are visible costs. If more than the bounded `t0`--`t7` scratch area
is required, assembly fails; a naked procedure does not gain an implicit frame
temporary.

An alternative procedure contract:

```asm
proc init_object
    preserves pObj
```

would move responsibility into `init_object`. That is a different ABI decision
and should not be inferred from the caller's wishes.

## 12. Diagnostics derived from the corpus

The examples imply diagnostics that are more useful than a final encoding
failure:

```text
field 'dash_time' does not exist in type 'NemoObject'
```

```text
CelesteObject is 65 bytes but pool 'objects' declares a 64-byte stride
```

```text
cannot lower objects[slot]:
the 6502 backend requires a pointer pair and no scratch location was supplied
```

```text
parameter 'self' is no longer valid:
its physical location pObj was overwritten by call to init_object
```

```text
cannot address pointer local 'entry' indirectly:
this frame backend supports byte locals but no frame-relative pointer mode
```

```text
write to readonly field SpritePort.frame
```

```text
unaligned code pointer in NemoClass.update
```

## 13. Requirements exposed by the examples

The game corpus requires more than structures and `offsetof`. A useful first
language slice needs:

1. fixed-width integer types and target-defined pointer/code-pointer types;
2. packed layouts, explicit offsets and explicit reserved storage;
3. nested structures and fixed arrays;
4. compile-time size, offset, stride, count and address properties;
5. static instances at fixed addresses;
6. fixed pools without implicit allocation;
7. typed aliases for registers, register pairs and memory-backed pointer
   locations;
8. semantic field and indexed-field address expressions;
9. backend-declared scratch requirements and clobbers;
10. namespaced procedures with explicit receivers;
11. `frame` by default and an explicit `naked` escape hatch;
12. named physical parameter and return locations;
13. raw calls, marshalled invocation and indirect invocation;
14. explicit method-table and code-pointer layouts;
15. volatile and readonly MMIO fields;
16. diagnostics when a symbolic physical location is invalidated.

The examples do not require:

- heap allocation;
- garbage collection;
- implicit construction or destruction;
- automatic register allocation;
- hidden receiver preservation;
- built-in inheritance;
- implicit dynamic dispatch;
- conversion from structure-of-arrays to array-of-structures;
- one universal calling convention;
- one universal assembly instruction syntax.

## 14. Candidate conformance examples

These examples can eventually become backend-independent frontend tests:

| Example | Compile-time invariant | Runtime/lowering invariant |
| --- | --- | --- |
| Celeste object | size 64, hair offset 37 | field access reaches the same byte as `O_*` |
| Celeste pool | 16 slots, stride 64 | every slot address equals the existing table |
| Nemo object | size 16, class offset 0 | class walk visits the same descriptors |
| Nemo subscription | size 4, handler offset 1 | event dispatch calls the same handler |
| Breakout ball | size 8 | position update matches current 8.8 arithmetic |
| Particle pool | arrays remain 16 bytes apart | indexed accesses lower to existing arrays |
| Sprite port | fixed addresses `$4008`--`$400e` | volatile store order is unchanged |

For this repository, a credible prototype should first prove bit-identical or
trace-identical output on a small subset:

1. declare `CelesteObject` and generate the existing `O_*` constants from it;
2. replace a handful of player field accesses with typed paths;
3. declare `NemoObject`, `NemoClass` and `Subscription`;
4. declare Breakout's particle pool without changing its memory layout;
5. verify that all generated addresses and emitted instructions match the
   current source.

Only after layout equivalence is proven should a prototype attempt procedure
frames, marshalled invocation or target-dependent method-table generation.

## 15. Open questions made concrete

### Field operand spelling

These examples use:

```asm
[self + CelesteObject.hitbox.w]
```

as the explicit primitive. Once `self` carries a known pointer type, the
shorter form:

```asm
[self.hitbox.w]
```

could be permitted as sugar.

### Pointer locations versus registers

On this console, `pObj` is a pair of zero-page bytes, not a CPU register.
Therefore the language's location model must be broader than "typed
registers". A typed location may be a register, register pair, fixed memory
slot, frame slot or backend-defined pointer location.

### Code-pointer representation

Celeste benefits from split low/high method arrays while Nemo uses contiguous
little-endian code pointers inside class records. The language must decide
whether a `codeptr` table has:

- one canonical memory representation per target; or
- an explicitly selectable array-of-structures or structure-of-arrays
  representation.

The corpus contains evidence for needing both.

### Frame-addressable pointers

The proposed 6502 frame mechanism makes byte locals cheap but does not by itself
make a pointer stored in a frame usable with `(zp),Y`. The backend interface
must distinguish:

- storage that can hold a pointer value;
- storage that can serve as an indirect-address operand.

Those are the same on many architectures and materially different here.

### Known-instance specialisation

Breakout's primary ball shows why a typed static instance and a pointer receiver
should not automatically be treated as equivalent in cost. It remains open
whether the frontend:

- always honours the declared receiver representation;
- may generate a specialised static-address version;
- requires the programmer to declare a second procedure; or
- provides an explicit specialisation directive.

Whatever choice is made must keep the emitted machine strategy visible.

## Central observation

The games support a narrower and stronger formulation than “object-oriented
assembly”:

> Layouts, field paths, procedure signatures and physical locations can be
> checked and calculated architecture-independently, while storage choices,
> instruction bodies and lowering costs remain explicit properties of the
> target.

Celeste and Nemo show that object-shaped data and dynamic dispatch already
exist in hand-written assembly. Breakout shows that the same layout machinery
is useful for static records and data-oriented arrays. The proposed language
does not introduce those runtime structures; it gives the assembler enough
information to name, validate and lower them without manually synchronising
offset constants.
