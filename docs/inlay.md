# Inlay Assembly

Structured assembly, close to the metal.

## Status

The bounded frontend is implemented, and Celeste's normal build passes through
it. The immutable Phase-A frontend image was byte-for-byte identical to the
prior direct-customasm ROM:

```text
size    65536 bytes
sha256  d85795e3daa7f1fbea0cef869efd554871f316c6196586dac3938e6340ae011a
```

Phase B intentionally changes the executable while retaining behavioral,
framebuffer, audio and resource gates. After the object-kind redesign, the
deterministic production image remains 65,536 bytes with SHA-256
`e57a8ea4112c6f16086d6a618254214c453d464d4de9ce19bfa03ac608f53da6`.

customasm v0.14.1 remains the host instruction encoder. The frontend owns
packed and aligned layouts, enums, unions, sparse views, overlays, compile-time
expressions, typed locations, procedure conventions, typed frames, marshalled
invocation and structured field operations; it does not yet own banks,
ordinary instructions or machine-code encoding.

## Architecture

The semantic implementation is the conservative C89-compatible core in
`tools/inlay/inlay_core.c` plus the bounded module expander in
`tools/inlay/inlay_modules.c`. Neither has a heap, filesystem, process,
environment, locale or JSON dependency. A platform supplies:

- a caller-owned byte workspace and explicit table limits;
- an input callback;
- an ordered semantic-event callback;
- a stable-code diagnostic callback;
- a target description.

The host shell in `tools/inlay/inlay_host.c` supplies file I/O, JSON source
maps, customasm text generation and optional customasm process execution. A
future in-console shell can connect the same core to an editor buffer, fixed
RAM and a native encoder without retaining the host adapters.

```text
.inlay.asm source
      |
      v
bounded module expansion
      |
      +-- immutable source views + resolver callback
      +-- per-line source id + original line
      |
      v
bounded portable C core
      |
      +-- properties: owner, path, kind, value
      +-- raw lines: source span + exact bytes
      +-- operations: fields, pool addresses, frames, moves, invocation
      |
      v
host emitter                         future console emitter
      |                                      |
      v                                      v
generated customasm + JSON map       native encoder (deferred)
      |
      v
customasm v0.14.1
```

The structured events, not generated customasm spelling, are the semantic
boundary.

## Implemented source slice

Inlay source files use the `.inlay.asm` suffix. The implemented declarations
are:

```asm
struct Name
    scalar : u8
    signed : i16
    nested : Other
    links  : ptr Other
    array  : Other[5]
end

enum State : u8
    idle = 0
    moving = 1
end

union Value
    byte : u8
    word : u16
end

overlay state_view : Name at OBJECT_RAM

location pObj : ptr Name
pool objects : Name[16] at OBJPOOL table obj_lo, obj_hi

static_assert Name.size == 64
static_assert Name.nested.member.offset == 14
static_assert Name.array.count == 5
static_assert Name.array.stride == 4
static_assert objects.count == 16
static_assert objects.stride == Name.size
```

Layout queries also have compact prefix forms for semantic operands and
compile-time expressions:

```asm
mov y, offset Name.nested.member
mov bytes, sizeof Name.array
mov alignment, alignof Name
mov elements, countof Name.array
mov stride, strideof Name.array

static_assert offset Name.nested.member == 14
static_assert sizeof Name.scalar == 1
```

The query itself identifies a compile-time value, so semantic `mov` does not
use the target immediate marker `#`. `offset` is a prefix operand, not a
standalone instruction. Direct typed memory operations remain preferable to
materialising an offset solely for a following raw instruction.

The fixed-width primitive types are `u8`, `i8`, `u16` and `i16`. `codeptr` is
a distinct target-sized primitive for executable addresses; its storage width
and byte order come from the selected target. Data-pointer width comes from the
target independently. Both are two little-endian storage units for
`console6502`. Layouts are nominal. Forward nominal references are allowed;
unknown types and recursive by-value structure/union graphs are rejected.
Pointer references do not create a by-value cycle.

A complete procedure address uses the target-sized form directly:

```asm
data codeptr Platform.reset
```

The procedure must be declared and visible. The backend receives its canonical
identity, code-pointer width and byte order and emits the target relocation.
`data u8 low(Procedure)` and `data u8 high(Procedure)` remain available for
tables that deliberately store split address bytes. The
`data u16 addr(Procedure)` form remains an explicit fixed-width compatibility
form and is not the portable spelling of a code pointer.

### Enums, layout policies, unions and overlays

Packed layout is the default. The explicit `packed` keyword is accepted as an
identical assertion:

```asm
struct Dense
    a : u8
    b : u16
end

struct AlsoDense packed
    a : u8
    b : u16
end
```

`aligned(N)` is the deterministic alternative; it is not a target ABI request.
`N` is a positive power-of-two count of target storage units and cannot exceed
the target's advertised maximum. Primitive and enum fields align to
`min(size,N)`, pointers to `min(pointer-size,N)`, nested aggregates to
`min(declared-align,N)`, and arrays to their element alignment. The aggregate
size is rounded to `N`.

```asm
struct Shape aligned(4)
    a : u8
    b : u16
    c : u8
end

static_assert Shape.a.offset == 0
static_assert Shape.b.offset == 2
static_assert Shape.c.offset == 4
static_assert Shape.size == 8
static_assert Shape.align == 4
```

A structure field may advance the monotonic layout cursor explicitly:

```asm
struct HeaderView
    kind  : ObjectKind at 0
    flags : u8         at 17
end
```

The bytes between fields are deliberately omitted from this nominal view.
They have no path and are not allocated, reserved or initialised. A later
field cannot backfill a gap or overlap an earlier field. In `aligned(N)`,
explicit offsets must also satisfy the field's effective alignment.

Enums require an underlying `u8`, `i8`, `u16` or `i16` type and an explicit
value for every member:

```asm
enum ObjectKind : u8
    player = 1
    actor = ObjectKind.player
    balloon = 2
end
```

Members resolve in declaration order. Equal-value aliases are valid;
self/forward references and values outside the underlying signed or unsigned
range are errors. Enums are nominal scalar field types. Qualified values work
in frontend compile-time expressions and are emitted as stable generated
constants. Inlay does not search or rewrite arbitrary raw instruction text
containing an enum name.

An ordinary target label declared directly inside a namespace is a bounded
scoped declaration:

```asm
namespace Gfx
    export draw_palette
draw_palette:
    #d8 $00, $01, $02, $03
end

lda Gfx.draw_palette, x
```

The frontend validates qualified procedure, constant and scoped-label tokens
in otherwise raw target operands, applies module privacy, and emits the same
collision-free target spelling at the declaration and use. Strings, comments,
enum operands and target-local labels are not rewritten.

Unions accept the same field types and arrays as structures. Every member is
at offset zero; `packed` unions have alignment one and the largest member size,
while `aligned(N)` rounds that extent to `N`. They track no active member and
perform no runtime conversion or validation.

```asm
union Payload
    byte : u8
    pair : Pair
end
```

An overlay assigns a complete structure or union type to an existing target
symbol without emitting storage:

```asm
overlay header : HeaderView at OBJECT_RAM
overlay motion : MotionView at OBJECT_RAM

lda [header + HeaderView.kind]
sta [motion + MotionView.vy]
```

Multiple overlays may share a base, have different sizes, omit different
offsets and overlap each other. Each underlying structure remains internally
non-overlapping. On `console6502`, byte leaves lower to absolute
`BASE + displacement` loads/stores. Indexed overlays and non-byte overlay
accesses are rejected. A numeric fixed base is checked against an aligned
aggregate's placement requirement; symbolic bases publish that alignment for
downstream validation.

Expressions support decimal integer constants, parentheses, unary `-`, `!`
and `~`, `* / %`, `+ -`, `<< >>`, `&`, `^`, `|`, comparisons, equality,
`&&` and `||`, in that precedence order (tightest first). Bitwise results
are plain integers, never enum values. Mixing the bitwise family with
comparisons, equality or the logical operators requires parentheses around
the inner expression; an unparenthesized mix is a diagnostic. Arithmetic
mixes freely with both families. A bitwise result bound to a byte operand
is masked to the operand width before the range check, so
`and [p + T.flags], #~mask` is the typed spelling of the former raw
`#<!mask`; non-bitwise out-of-range immediates are still rejected. Shift
counts are limited to 0..31. Available properties and values are:

- structure, union and enum `.size` and `.align`;
- qualified enum member values such as `ObjectKind.player`;
- field `.offset` and `.size`;
- array field `.count` and `.stride`.

All non-owned lines, including blank lines and comments, are delivered to the
host emitter unchanged. A semicolon begins a comment for frontend declaration
and typed-operand parsing, without changing the corresponding raw line.

The frontend-owned `include "logical-name.inlay.asm"` directive expands modules
depth-first through a platform resolver. The distinct customasm
`#include "target-source.asm"` directive remains a raw output line. Cycles and
repeated completed modules are errors; source bytes, source lines, module count
and include depth all have explicit limits and caller-owned workspace.

The explicit typed operations registered by `console6502` are:

```asm
lda [pObj + CelesteObject.state]
sta [pObj + CelesteObject.hitbox.w]
```

They lower structurally to `LOAD8_PTR_DISP` and `STORE8_PTR_DISP`. The host
emitter writes the existing extended-6502 forms:

```asm
lda (pObj), #18
sta (pObj), #14
```

The actual output uses generated constants and an inspectable source comment.
Locations are aliases only: a `location` declaration allocates, initializes and
preserves nothing.

Two-storage-unit fields use explicit physical word transfers:

```asm
proc load_speed naked
    self : ptr CelesteObject in pObj
    value : u16 in w0
begin
    ldw value, [self + CelesteObject.core.speed_x]
    stw [self + CelesteObject.core.speed_x], value
    ret
end
```

`ldw WORD, [pointer + Type.field]` and
`stw [pointer + Type.field], WORD` require a declared two-unit physical word
location and a scalar or aggregate field whose complete width is two storage
units. Word constants and word copies have direct forms:

```asm
movw Fixed.word1, #max_run
movw Fixed.word1, #-wall_jump
movw Fixed.word2, accel
stw [self + CelesteObject.core.speed_y], #jump_speed
stw [self + CelesteObject.core.speed_x], #0
```

`movw WORD, #expr16` writes a compile-time 16-bit value (signed or unsigned
acceptance, like `#d16`) into a declared word location; `movw WORD, WORD`
copies one word location to another; `stw [pointer + Type.field], #expr16`
writes the immediate through pointer displacement. All three transfer low
unit then high unit through `A` and clobber `A` and flags only. A single
signed spelling such as `#-wall_jump` replaces the paired
`#<(-k & $FFFF)`/`#>(-k & $FFFF)` halves that previously had to agree by
hand. The semantic operation records the access width, target byte order,
physical pointer and word locations, and its scratch/clobber contract. The
console6502 lowering transfers the low unit and then the high unit through
`A`, so it clobbers `A` and flags but does not consume or change `Y`. Both
field units must fit the target displacement range.

Physical word arithmetic keeps both machine locations visible:

```asm
addw ab, value
subw ab, value
cmpw ab, value
```

For `console6502`, `ab` is the required physical word accumulator and `value`
must be a declared two-unit physical location. The backend lowers these forms
to the target's one-operand `addw value`, `subw value` and `cmpw value`
instructions. Add and subtract update `AB` and publish `N,V,Z,C`; compare
preserves `AB` and publishes `N,Z,C`. A one-operand spelling remains raw target
assembly and receives no Inlay type validation.

Typed byte updates operate on one nonvolatile pointer field:

```asm
inc [self + CelesteObject.payload.player.grace]
dec [self + CelesteObject.payload.player.dash_time]
and [self + CelesteObject.core.flags], #$fd
ora [self + CelesteObject.core.flags], #$02
```

The console6502 backend emits a direct pointer-displacement load, the selected
update, and a direct pointer-displacement store. These operations are
non-atomic and clobber `A` and flags. Their register contract is pinned:
**A holds the post-operation value, with N and Z derived from it** — the
Title banner sequencing depends on exactly this.

Two observation forms join the same family:

```asm
decz [self + CelesteObject.payload.player.grace], .done
tstw [self + CelesteObject.core.speed_x]
tstw Fixed.word0
```

`decz` is a branch operation: when the byte field is zero it branches to the
label with the field untouched; otherwise it decrements the field and falls
through with A holding the post-decrement value (other flags unspecified).
This is the cart's timer idiom — jump buffer, grace, spawn delay — with one
contract instead of a hand-written pre-decrement observation. It clobbers
`A` and flags and rejects fixed overlays, arrays and non-byte fields.

`tstw` sets Z iff the two-unit field or declared word location is zero; **N
is meaningless** — re-test if a following branch needs the sign. The pointer
form lowers through `(base),y` (no `ora (zp), #disp` extended form exists)
and therefore clobbers `A`, `Y` and flags, at the same byte cost as the raw
idiom it replaces; the location form lowers to `lda`/`ora` absolute and
preserves `X` and `Y`. The frontend rejects arrays, non-byte
fields, out-of-range masks and targets without a registered byte-update
lowering. Fixed overlays are deliberately excluded from this operation: they
may describe volatile MMIO, and the current backend does not register a
volatile-safe read-modify-write sequence.

Production conformance treats an adjacent
`mov y, offset CelesteObject.field` / `lda (pObj),y` pair as a missed typed
load when `Y` is overwritten before any intervening read or control-flow
boundary. A sequence with genuinely different flag, control-flow,
update-operand or target-constant semantics must carry an inline
`; inlay-exception: REASON` comment on the offset materialisation. The reason
is reviewed source, not a global suppression.

One array component may carry the physical index `x`:

```asm
lda [pObj + CelesteObject.hair[x].x.integer]
sta [pObj + CelesteObject.hair[x].y.fraction]
```

The frontend resolves the constant displacement, element count, stride and
byte leaf. The initial console6502 backend accepts strides 1, 2, 4 and 8. It
copies `X` to `A`, shifts as required, adds the constant displacement, moves
the result to `Y`, then performs `(base),y`. Indexed loads therefore clobber
`A`, `Y` and flags. Indexed stores preserve the incoming value in `A` with
`PHA`/`PLA`, consume one hardware-stack byte transiently, and clobber `Y` and
flags. Neither form performs a bounds check.

Fixed-overlay byte arrays may instead use physical `Y` directly:

```asm
sta [psg + PsgRegisters.channels[y]]
lda [video + VideoRegisters.draw_palette[y]]
```

The frontend resolves the overlay base, array displacement, count, unit stride,
access width and volatility. The initial console6502 lowering accepts only
byte elements with stride one and emits `BASE + displacement,Y`; it performs
no bounds check and does not materialize another index. Hardware overlays may
append `volatile` to their declaration. The volatility is carried by every
overlay access event so a backend cannot silently substitute an unsafe
sequence.

The implemented pool and address forms are deliberately explicit:

```asm
pool objects : CelesteObject[16] at OBJPOOL table obj_lo, obj_hi
address pObj, objects[a]
```

The declaration describes fixed contiguous storage and a pre-existing
low/high address-table strategy. It provides `.count`, `.stride` and `.size`;
aligned element types also publish `.align`. It does not allocate slots or emit
the storage or tables. On console6502,
`address` requires physical source `A` and a two-byte destination location and
lowers to `TAX`, the low-table move, the high-table load and the high-byte
store.

Procedures use one member grammar for inputs, frame locations and returns:

```asm
proc object_at using console6502
    slot : u8
    result : ptr CelesteObject return in pObj
begin
    address result, objects[a]
    ret
end

proc save_value
    saved : u8 in frame
begin
    sta [saved]
    lda [saved]
    ret
end

proc interrupt_entry naked
begin
    ; fully manual machine state
    ret
end
```

An unqualified member is an input. `in frame` declares explicit local storage.
`return` declares an output, with an optional physical placement after it.
Qualifier order is canonical; the provisional `local name : type` and
`[local name]` forms are migration errors.

`frame` is the default; `naked` is explicit. Inputs and returns are typed names
for physical locations, not virtual values, and are visible only inside their
procedure. `using console6502` assigns omitted scalar inputs to `A`, `X`, then
`Y` in declaration order and assigns an omitted scalar return to `A`. Explicit
placements take precedence. Pointers always require an explicit physical
location; a pointer return is therefore written `return in pObj`. Return
aliases generate no movement by themselves.

Scalar, pointer and complete packed-aggregate frame members occupy bounded
hardware-stack storage. A pointer save and restore is explicit:

```asm
proc preserve_receiver
    self : ptr CelesteObject in pObj
    saved_self : ptr CelesteObject in frame
begin
    mov [saved_self], self
    mov self, [saved_self]
    ret
end
```

The console6502 prologue uses one `PHA` per frame byte. Frame byte operations
use `TSX` and page-one absolute-X addressing; pointer moves copy both bytes in
target byte order. Qualified byte leaves of packed aggregates are addressed
relative to the aggregate's frame offset. Semantic `ret` restores `SP` with
`TSX`/`INX`/`TXS` before `RTS`, preserving `A`. A zero-size frame emits no
frame-management instructions. Frame members in naked procedures, raw stack
mutation, whole-aggregate copies, and raw `RTS` while a frame is active are
rejected. The current console6502 frame backend guarantees alignment one, so
an `aligned(N)` aggregate with `N > 1` is rejected as a frame member rather
than silently weakened to packed layout.

A procedure may be declared `inline`:

```asm
proc bump_timer inline using console6502
    self : ptr CelesteObject in Machine.object
begin
    decz [self + CelesteObject.payload.player.grace], .done
.done:
end
```

An inline procedure emits no standalone body and no label; `low(...)`,
`high(...)` and `data codeptr` references to it are rejected. Its body is
captured at declaration and spliced at each `invoke` site after the normal
binding marshalling, in place of the `jsr`. Local labels are freshened per
expansion as dot-local names in the reserved `__la` family, so no new
target label scope opens mid-procedure; a non-local label in an inline
body is rejected, as are `ret` (the body falls through), `frame` members,
`frame`/`naked` modes, nested declarations, and multi-line `invoke`
continuations. A tail `jmp` to a non-inline procedure is allowed and is
checked per expansion site: splicing a tail `jmp` into a procedure whose
frame size is nonzero is rejected, naming both procedures.
Inline-in-inline expansion is bounded at depth 8; recursion is an error.
Inline procedures, body lines, body bytes and expansions are bounded
resources with stable diagnostic codes (`inline-body`, `inline-depth`,
`inline-capacity`), and each expansion charges its operations and lines
against the existing structured-operation and source budgets. The
expansion count is reported in `--stats`.

`invoke` marshals the declared inputs of an earlier procedure:

```asm
invoke damage, self=pObj, amount=10

invoke blend,
    left=x,
    right=a
```

There is no closing `end` for an invocation. A trailing comma continues the
same statement on following lines. Every input must be bound exactly once;
unknown callees or names, duplicates, missing inputs and incompatible source
types are errors. Supported sources are integer immediates and typed or raw
physical locations.

Bindings have parallel-assignment semantics: every physical source is read
from the pre-invocation state. Marshalling follows an explicit order:
identity bindings (source equals the member's placement) elide entirely;
register sources snapshot into the bounded `t0`-`t7` scratch area; named
locations snapshot only when another binding's destination overlaps them
and are otherwise read directly at assignment; typed-field reads happen
after the register saves and before any destination write, so every base
pointer is dereferenced before it can be overwritten. Register-destination
field reads run after all other assignments (`Y`, then `X`, then `A`,
each through `A`) and take no scratch unless another binding also assigns
`A`. Only the scratch bytes actually reserved and the affected argument
locations are clobbered; assembly fails when the required scratch does not
fit. Raw `jsr` lines remain ordinary target assembly and perform no
marshalling.

Source kinds cover the corpus's argument shapes:

```asm
invoke Objects.spawn_smoke, self=Machine.object,
    x_position=[Machine.object.core.x],
    y_position=[Machine.object.core.y] + 4
invoke Fixed.approach, amount=#$0026
invoke tail Draw.object
```

An immediate is a compile-time expression: byte members keep the byte
range, two-unit scalar members accept the `#d16` range and lower through
the word-immediate move. A typed-field source names a one- or two-unit
leaf through a pointer location; a byte leaf accepts a constant value
addend written `+ K`. `invoke tail` performs identical marshalling and
transfers with `jmp`; it is rejected when the enclosing procedure's frame
size is nonzero, and an inline procedure has no tail form.

Unsupported typed mnemonics, a base/root type mismatch, non-byte leaves,
multiple indexes, unsupported strides and displacements outside 0--255 are
errors. Raw target assembly remains the escape hatch when semantic typed
syntax is not wanted.

Enum-value-keyed dispatch data generates from one declaration:

```asm
method_table lifecycle : ObjectKind[player .. platform]
    tile : u8
    init : code
    update : code
    draw : code
    hide : u8
    player = 0, Player.init, Player.update, Player.draw, 0
    spawn = Room.tile_spawn, Spawn.init, Spawn.update, Spawn.draw, 0
    ...
end
static_assert lifecycle.bias == ObjectKind.player
```

The body uses the language's own declaration shapes: `name : u8` declares
a per-kind attribute slot, `name : code` a method slot, and a bare
`member = value, ...` line assigns one enum member's slots in declaration
order. Members are keyed by enum member value over the declared inclusive
domain, never by declaration order; the domain's low value publishes as
the queryable `NAME.bias`. Coverage is total — a domain value with no
member line is a diagnostic, so adding an enum member inside the domain
without updating the table fails to assemble. Members with duplicate
values inside the domain are rejected. A `code` slot emits split
`TABLE_slot_lo`/`TABLE_slot_hi` tables through the same
procedure-address events as `data u8 low(...)` (inline procedures are
rejected); a `u8` slot emits one `TABLE_slot` byte table, and `absent`
(a zero entry for a dispatch guard) is legal only in `code` slots.
Tables emit at the declaration's source position.

A pool's low/high address tables generate from its own geometry:

```asm
pool tables objects
```

emits the declared `table` labels with `(BASE+offset)` rows computed from
the pool's base, stride and count — the raw high-byte base slices those
tables used to hand-maintain are gone.

The keywords `callconv`, `object` and `interface` remain recognised
deferred features. `invoke` is implemented only for direct, previously
declared procedures; indirect and method-table invocation remains
deferred.

## Workspace contract and defaults

`la_workspace_required()` calculates the byte arena required by a `LaLimits`
profile. The core partitions it once into fixed arrays; it never grows a table.
The portable defaults are:

| Resource | Limit |
| --- | ---: |
| source bytes | 32,767 (host profile: 65,534) |
| interned-name bytes | 8,192 |
| tokens | 8,192 |
| structures | 128 |
| unions | 64 |
| fields | 1,024 |
| enums | 128 |
| enum members | 512 |
| overlays | 128 |
| namespaces | 128 |
| exports | 256 |
| namespace constants | 512 |
| scoped target labels | 512 |
| typed locations | 128 |
| fixed pools | 64 |
| procedures | 256 |
| procedure members | 512 |
| frame locations | 512 |
| invocation bindings | 64 |
| expression values/operators | 256 |
| nesting/property traversal | 32 |
| structured target operations | 2,048 |
| line/path bytes | 512 |
| host-profile reserved workspace | 158,296 bytes |

Every bounded resource has a stable diagnostic code. Core tests exercise exact
limits and one-past-limit failures for the active tables. Diagnostics carry a
source id, line, column, length, two bounded arguments, actual value and limit;
formatting belongs to the platform shell.

The default module profile reserves up to 64 modules, 32,767 flattened bytes,
4,096 flattened lines and include depth 32. The Celeste host profile raises
the byte/line limits to 65,534 and 12,000. The module expander removes
semicolon comments outside quoted strings, omits blank/comment-only lines and
trims insignificant leading indentation and trailing whitespace before
charging source capacity. Its explicit origin table still maps every retained
line to the original module and line. Celeste can therefore keep checked-in
commentary without weakening the bounded model. Current expanded-input
measurements are recorded with each completed migration phase below; the
module workspace reservation is 117,848 bytes.

The installed cc65 compiler successfully compiles the same core and ca65
assembles its output. This is a portability smoke test, not a claim that the
editor shell or core presently fits the final console RAM map.

## Generated namespace and source maps

Raw source may not define names beginning with `__la_`. The host emitter uses
length-prefixed identifier components, so component boundaries cannot collide:

```text
__la_13_CelesteObject__6_hitbox__1_w__offset
```

This denotes `CelesteObject.hitbox.w.offset`. Structure properties omit field
components:

```text
__la_13_CelesteObject__size
```

Enum constants use the same collision-free family:

```text
__la_10_ObjectKind__6_player__value
```

Qualified procedure and data-label names remain qualified in frontend
diagnostics and resolution. The console6502/customasm host uses
length-prefixed components, so `Player.update` deterministically emits
`__inlay_q6_Player6_update:` and establishes a fresh scope for following
`.local` labels.

The generated header records language format 1 and target format 1. Source-map
format 2 is deterministic JSON containing a logical source table and a source
id on every ordered header, enum member, property, overlay, label, raw,
scoped-raw and target-operation mapping.
Absolute host paths are deliberately excluded. Frontend and mapped downstream
diagnostics use the included module's logical name and original line.

## Commands

Build and test Inlay:

```sh
make test-inlay
```

Build Celeste through it:

```sh
make GAME=celeste hex
```

Run Inlay conformance followed by Celeste's functional, framebuffer and PSG
suite:

```sh
make test-celeste
```

Use the host command directly:

```sh
build/inlay/inlay \
  --target console6502 \
  --output build/example.asm \
  --map build/example.map.json \
  input.inlay.asm
```

`--stats` prints bounded-table usage. `--check-customasm` invokes the pinned
downstream assembler after translation. `--native` fails explicitly because
native encoding is not implemented.

### Legacy naming compatibility

`build/laasm/laasm` remains a temporary compatibility command. It emits a
deprecation diagnostic to stderr and executes `build/inlay/inlay` with the
same arguments, stdout and exit status. Source and module paths ending in
`.la.asm` remain accepted and have no different language semantics. Removing
either legacy name requires a separate specification change.

The portable `la_` C API and generated private `__la_` symbols are deliberately
unchanged: they are compatibility namespaces, not the public language name.

## Celeste Inlay port

`src/celeste/main.inlay.asm` is the only production entry. Every regular file
in `src/celeste/` is a flat `.inlay.asm` module: the layout, memory map, all
handwritten code, and the generated graphics, rooms and audio data. There is no
parallel legacy game under the production directory.

`layout.inlay.asm` declares an 18-byte `ObjectCore` followed by a 46-byte
`ObjectPayload` union. Player, spawn, smoke, title and hair views name the
fields each variant actually owns while preserving every established byte
offset. `ObjectKind` and `SpawnPhase` are nominal byte enums; combinable flag
bytes remain bytes. The module also declares typed `pObj` and `pOth`
locations and the 16-record object pool with its 64-byte stride and
1,024-byte size. Production source contains no compatibility `O_*` or `T_*`
aliases.

The twelve player/spawn/smoke/title init, update and draw dispatch targets are
qualified `console6502` procedures with
`self : ptr CelesteObject in pObj`. Their low/high dispatch tables use semantic
qualified procedure-address declarations. `VideoRegisters` and `PsgRegisters`
describe the sparse hardware windows with explicit offsets, including palette,
sprite, clipping, upload, channel-row, channel-length and music controls.
Fixed `video` and `psg` overlays serve eligible direct and indexed byte
operations.

The same layout module gives stable RAM a nominal shape. `TileMap` owns the
pattern and attribute halves at `$f000`; `OverlayFramebuffer` describes both
the write-only framebuffer at `$e000` and its shadow at `$6000`;
`RoomTileBuffer` and `OverlayRowPointers` describe the room cache and row
tables. `ZeroPageWorking` covers the physical zero-page workspace, while the
overlapping `GameState` view rooted at `$30` names persistent state. This
overlap is deliberate: overlays are alternative views of the same bytes, not
allocations. Compile-time assertions pin all established offsets and absolute
region boundaries.

Every handwritten instruction module is expanded through Inlay `include`.
Generated graphics is also semantic: `Gfx` publishes an explicit manifest of
sprite constants and data labels while keeping generator-only values private.
The portable core deliberately uses 16-bit source slices, while the complete
game source is larger, so the two generated data payloads `rooms` and `audio`
remain opaque target includes; every handwritten language module is consumed
semantically. The raw compatibility memory map (`memmap.inlay.asm`) has been
**deleted**: its 142 aliases are now typed overlays, scoped locations and
scoped constants, with the single reviewed exception `OBJPOOL` (the pool base,
needed by the pool strategy's raw `obj_lo`/`obj_hi` tables) declared in
`layout.inlay.asm`. A permanent deny-list rejects any reintroduction.

`Fx` exports only initialization, update and its two draw stages; effect
capacities and sine tables remain private, and the cloud/particle
structure-of-arrays is accessed through the indexed `effects` (`FxStorage`)
overlay. `Fixed` declares the physical `word0`/`word1`/`word2` locations for
signed comparison, sign, absolute value and approach, and uses the custom CPU
word operations for eligible arithmetic.

`Platform` owns the naked reset entry, hardware initialization, frame wait and
input sample services. Reset establishes the physical stack before its first
call and then transfers to `Game.run`; ordinary services retain the default
frame mode. `Game` owns initialization after hardware startup, title/play
transitions, clocks, freeze/restart sequencing and frame orchestration. Every
procedure records inputs, returns, frame locals and physical clobbers.
`main.inlay.asm` is consequently only the target/bank composition root, module
include list, stable debug aliases and vector table.

`Objects` exports typed pool addressing, clearing/allocation, lifecycle
dispatch, receiver-preserving smoke construction and update/draw traversal.
Its method tables derive from qualified lifecycle procedure identities, while
movement uses typed word field transfers and the custom word adder directly.
The shared signed-step helper makes the `t0`/`t1`/`t2` collision contract
explicit. Smoke construction preserves `pObj` through an Inlay pointer frame
local rather than handwritten stack pushes. The two global pool address-table
labels remain a documented target-boundary exception because the current pool
declaration accepts target identifiers rather than qualified semantic labels.

`Player`, `Spawn`, `Smoke` and `Title` are now actual bounded namespaces
rather than dotted global procedure spellings. Each exports only its
`init`/`update`/`draw` lifecycle. Player constants, movement/death/hair helpers
and the persistent `$50`-`$5f` update scratch are private to `Player`;
spawn/smoke constants are similarly private. `Player.update` transfers through
explicit input, environment, active-dash, horizontal, vertical, jump/dash and
animation procedures. The scratch remains deliberately physical because those
values live across several calls and tail transfers; it is not a hidden
virtual value or a short-lived frame local.

`Collision`, `Room`, `Draw` and `Audio` complete the scoped gameplay surface.
Collision exports solid/ice/box/spike queries while keeping tile-range and
direction tests private. Room exports initialization, title detection,
loading, transition/restart and camera services. Draw exports frame, sprite,
object, hair, overlay-lifecycle and room-title services while its font, glyph,
HUD and palette machinery remains private. Audio exports upload, direct and
guarded SFX, music, fade and stop services. Cross-module call sites use these
qualified names; the old global helper labels are absent.

The completed subsystem migration expands to 65,394 significant bytes across
3,519 retained lines and 14 namespaces. Blank and comment-only source lines do
not consume that bounded flattened capacity, but every retained line keeps its
original module/line mapping. The resulting image is unchanged from Phase 9:
65,536 bytes with SHA-256
`e57a8ea4112c6f16086d6a618254214c453d464d4de9ce19bfa03ac608f53da6`.

The old direct customasm corpus lives only at
`tests/inlay/reference/celeste-customasm/` as the immutable Phase-A baseline.
Phase B intentionally changes instruction bytes, so acceptance is based on
focused lowering references plus functional, framebuffer and PSG behavior
rather than whole-ROM equality. Conformance rejects production references to
the baseline and enforces the exact production module set and opaque-include
allowlist.

Regenerate the Inlay-named data files directly:

```sh
python3 tools/p8_celeste.py cart.p8.png --out src/celeste
python3 tools/p8_audio.py cart.p8.png src/celeste/audio.inlay.asm
```

The conformance gate independently:

1. validates the production module set and dependency boundary;
2. rejects compatibility `O_*`, `T_*` and generated-property aliases;
3. rejects mechanically eligible legacy field sequences unless their different
   flag, liveness, volatility or clobber semantics are documented inline;
4. compares direct, indexed, word, read-modify-write and overlay operations
   with handwritten lowering references;
5. compares pool address, conventions, returns, scalar,
   pointer and aggregate frames, and marshalled calls with handwritten bytes;
6. assembles the complete production entry with customasm;
7. checks the semantic manifest, Platform/Game/Objects/object-kind public APIs,
   procedure manifests and contracts, minimal composition root and
   readable-source rules;
8. inventories 50 overlay operations, 89 typed operations, 97 semantic
   offset queries, zero legacy `offset y` setups and 129 residual raw
   `(pObj|pOth),y` accesses;
9. runs the reset-vector, framebuffer and PSG checks against the frontend
   image.

### Phase-B final measurements

The machine-readable snapshots are
`tests/inlay/reference/celeste-phase-a-baseline.json` and
`tests/inlay/reference/celeste-phase-b-final.json`. Both are produced by
`tools/inlay/celeste_redesign_metrics.py` from source plus customasm annotated
output.

| Metric | Phase A | Phase B | Delta |
| --- | ---: | ---: | ---: |
| ROM image | 65,536 B | 65,536 B | 0 |
| encoded instruction sites | 2,336 | 2,304 | -32 (-1.4%) |
| executable instruction bytes | 5,142 | 5,155 | +13 (+0.3%) |
| program span (`$0300` origin) | 12,794 B | 12,807 B | +13 |
| manual `ldy #O_*` setups | 127 | 0 | -127 (-100%) |
| raw `(pObj|pOth),y` accesses | 157 | 129 | -28 (-17.8%) |

The instruction-count and manual-offset requirements improve. The small byte
increase is the visible cost of explicit frame receiver preservation and
structured boundaries; it is reported rather than treated as an optimization.
The final program ends at `$3507`, before the object pool at `$5000`, and all
layout assertions retain the established zero-page, pool, room, overlay and
MMIO regions.

The byte increase was first published as +19. `Draw.hair_chase` then dropped
three redundant word-accumulator sites — `stab` does not disturb `AB`, so the
reload after each store was dead, and `addw` is carry-free (`w_lo` in
`rtl/cpu6502_core.sv`), so the two shifted terms chain into one accumulator
run. That is -6 bytes, and the frame and PSG checkpoints are unchanged.

The instruction-site count then fell a further -22 when 11 runs of repeated
accumulator shifts adopted the counted `asl a, N` forms (task 10.9). That
adoption is deliberately byte-neutral: the ROM digest is identical across it,
which is why `source.countedShiftSites` is recorded and gated separately — a
byte measurement cannot see it at all.

### Counted accumulator shifts

`asl a, N`, `lsr a, N`, `rol a, N` and `ror a, N` (N in 1..8) emit exactly N
copies of the corresponding accumulator instruction. The explicit `a` operand
is **required**, and is not cosmetic: `asl {zaddr: u8}` already matches a bare
expression, so the shorter `asl N` is ambiguous, and customasm v0.14.1 resolves
that ambiguity by silently preferring the smaller encoding — `asl 3` assembles
to `06 03`, a read-modify-write of zero page address 3, with no diagnostic.
The counts are enumerated one per rule rather than computed by slicing a
repeated constant, because a computed slice zero-extends past its width and
turns `asl a, 9` into `00` (BRK) followed by eight shifts. `make pseudo-check`
verifies all 32 rules byte-for-byte, executes the boundary counts against a
reference model to check the accumulator and carry, and asserts that
out-of-range counts and memory-operand forms fail to assemble.

### Operand width, and why it is not spelled `.w`

The pseudo-op layer marks a 16-bit operand with a trailing `w` — `asr` is the
byte form, `asrw zp` the zero-page pair — matching the `addw`/`subw`/`cmpw`
spelling the hardware word instructions already use. A bare mnemonic is always
the byte form, so the convention is additive.

The m68k `.b`/`.w` spelling was tried first and does not work here, for a reason
worth recording: `.` is Inlay's **member separator**, the same dot as in
`Fixed.word1` and `CelesteObject.core`. At statement position a dotted mnemonic
is lexically indistinguishable from a qualified name, and the frontend resolves
it as one — `asr.w Fixed.word1` came out as
`__inlay_q3_asr1_w __inlay_q5_Fixed5_word1` and did not assemble. Excepting a
mnemonic whitelist would make `.` mean one thing at statement start and another
everywhere else, which is the same positional ambiguity that makes `asl 3`
dangerous.

Note that the two conventions are not unified: `ldab`/`stab` name the `AB`
register pair rather than a width, and no suffix expresses that. The width axis
covers operand size only.

`asr`/`asrw` carry **different contracts**, which the rule comments state at the
site. `asr`'s flags are exactly what a hardware `ASR A` would leave, verified
over all 256 accumulator values against both carries and both overflow states,
so neither form refines the other. `asrw` is weaker than its hardware form: it
loads the high byte to test the sign, so it clobbers `A` and leaves `Z`/`N` from
the low byte. Do not branch on an `asrw` result without re-testing it.

When adding a pseudo-op, register it in `CUSTOM_OPS` in
`tools/inlay/celeste_redesign_metrics.py` and in the matching tuple in
`tools/inlay/test_conformance.py`. This is not bookkeeping: the annotated parser
skips any line whose mnemonic it does not recognise, so an unregistered pseudo-op
drops its expansion bytes from `executableBytes` and a byte-neutral migration
reports a saving it did not make.

| Custom/pseudo operation | Phase A | Phase B | Delta |
| --- | ---: | ---: | ---: |
| `mov` | 125 | 219 | +94 |
| `add` | 60 | 57 | -3 |
| `sub` | 35 | 28 | -7 |
| `ldab` | 12 | 18 | +6 |
| `stab` | 12 | 19 | +7 |
| `addw` | 2 | 6 | +4 |
| `subw` | 3 | 5 | +2 |
| `cmpw` | 0 | 0 | 0 |
| `cbeq` | 2 | 2 | 0 |
| `cbne` | 5 | 5 | 0 |
| `cblt` | 3 | 3 | 0 |
| `cbge` | 3 | 3 | 0 |
| `tbz` | 12 | 12 | 0 |
| `tbnz` | 0 | 0 | 0 |
| `bzero` | 0 | 0 | 0 |
| `bnzero` | 0 | 0 | 0 |

The final source also contains 89 typed object operations, 50 typed overlay
operations and 97 explicit semantic offset queries. Those operations and the
word/move families make the generated assembly intentionally customasm-only;
cc65 remains a portability gate for the frontend implementation, not an
encoder for the Phase-B game.

Two forced production builds produced identical binary, symbol, converted
label, readmemh, generated-assembly and source-map files:

| Artifact | SHA-256 |
| --- | --- |
| `build/celeste.bin` | `e57a8ea4112c6f16086d6a618254214c453d464d4de9ce19bfa03ac608f53da6` |
| `build/celeste.sym` | `d2f6ad71aa5740081afc15084ec08c4c6749e2dff9a7124611926e3da339c117` |
| `build/celeste.lbl` | `29015032ee036fb4b83734c54470ae6c925622b492db45ef52585cdfa63dcec3` |
| `rtl/ram.hex` | `042958a505c344fa6610f8cfc29702744b09843cf555e5fd9fee52cd5ed2a64a` |
| `build/inlay/celeste.asm` | `c320cfbc8d6978db8e074991f8883af1bc462858f6c7d3655e9862a2d6141f1b` |
| `build/inlay/celeste.map.json` | `d6bb4847ee6b7814ed31037a9af494de3af6eb5249c37015f353aa033ecade4c` |

The converted label file contains 1,290 labels. Final acceptance requires the
strict C89/C99/C++11, cc65 and undefined-behavior frontend gates; full Inlay
unit/module/conformance tests; strict OpenSpec validation; forced customasm
artifact determinism; and all boot, gameplay, framebuffer and PSG trace
checkpoints.

## Measurements

These host-only measurements use 20 warm runs on the current development
machine. They describe algorithm/table pressure, not target-console speed:

| Input | Median | Min | Source | Structs | Fields | Locations | Operations | Names | Tokens |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Celeste fixture | 4.209 ms | 3.702 ms | 1,824 B | 4 | 36 | 1 | 9 | 320 B | 76 |
| Synthetic mixed source | 8.217 ms | 7.820 ms | 25,850 B | 120 | 960 | 120 | 120 | 1,879 B | 2,040 |

Both use the fixed 158,296-byte default workspace reservation. Re-run
`python3 tools/inlay/measure_inlay.py` to refresh the host measurement.

## Deferred work

The current slice does not implement user-defined calling conventions,
stack-passed inputs, aggregate-by-value inputs or returns, whole-aggregate
copies, automatic pool allocation, dynamic dispatch, general clobber analysis
or automatic register allocation. The
implemented `console6502` convention, frame locations and invocation planner
are target-owned and deliberately bounded.

Native opcode emission is also deferred. Before it is added, one canonical ISA
description must generate or feed both host validation/lowering rules and the
future in-console encoder tables. A second handwritten opcode table would
create exactly the drift this frontend is intended to eliminate.

The checked-in Celeste port keeps residual raw target sequences visible where
the adopted typed and custom operations do not preserve their register, flag,
volatility or displacement contracts. The completed audit has four bounded
categories:

- 129 dynamic `(pObj|pOth),y` accesses whose runtime-selected displacement
  cannot be represented by a compile-time typed field path;
- 9 offset materialisations with an inline `inlay-exception`: two
  following-flag dependencies, six variable update operands and one
  wrapping add/mask update (the nine mask exceptions were retired by
  bitwise compile-time operators and typed `and`/`ora` mask operands; the
  three pre-decrement observations by `decz`);
- four raw high-byte slices for the fixed numeric object-pool base and eight
  low/high slices in the opaque generated room pointer table;
- target-bound physical aliases for non-accumulator MMIO transfers,
  page-strided bulk buffers, write-only overlay blits and structure-of-arrays
  effect storage.

Conformance freezes those exception counts, rejects any newly eligible legacy
field sequence and rejects raw procedure-address slicing elsewhere. Split
lifecycle dispatch tables use semantic `low(...)`/`high(...)` declarations;
the reset vectors use target-sized `data codeptr` declarations.
