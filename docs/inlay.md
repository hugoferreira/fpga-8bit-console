# Inlay Assembly

Structured assembly, close to the metal.

## Status

The first bounded frontend slice is implemented, and Celeste's normal build
passes through it. The complete frontend-built Celeste ROM is byte-for-byte
identical to the prior direct-customasm ROM:

```text
size    65536 bytes
sha256  d85795e3daa7f1fbea0cef869efd554871f316c6196586dac3938e6340ae011a
```

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

The fixed-width primitive types are `u8`, `i8`, `u16` and `i16`. Pointer width
comes from the target and is two storage units for `console6502`. Layouts are
nominal. Forward nominal references are allowed; unknown types and recursive
by-value structure/union graphs are rejected. Pointer references do not create
a by-value cycle.

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

Expressions support decimal integer constants, parentheses, unary `-` and `!`,
`* / %`, `+ -`, comparisons, equality, `&&` and `||`, in that precedence
order. Available properties and values are:

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
from the pre-invocation state. The console6502 backend snapshots overlapping
sources into the bounded `t0` through `t7` scratch area, assigns `A`, `X`, `Y`
or an explicit pointer pair, then emits `JSR`. These scratch bytes and affected
argument locations are clobbered. Assembly fails when the required scratch
does not fit; naked procedures receive no implicit frame temporary. Raw `jsr`
lines remain ordinary target assembly and perform no marshalling.

Unsupported typed mnemonics, a base/root type mismatch, non-byte leaves,
multiple indexes, unsupported strides and displacements outside 0--255 are
errors. Raw target assembly remains the escape hatch when semantic typed
syntax is not wanted.

The keywords `callconv`, `object`, `interface` and `method_table` remain
recognised deferred features. `invoke` is implemented only for direct,
previously declared procedures; indirect and method-table invocation remains
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
| host-profile reserved workspace | 131,352 bytes |

Every bounded resource has a stable diagnostic code. Core tests exercise exact
limits and one-past-limit failures for the active tables. Diagnostics carry a
source id, line, column, length, two bounded arguments, actual value and limit;
formatting belongs to the platform shell.

The default module profile reserves up to 64 modules, 32,767 flattened bytes,
4,096 flattened lines and include depth 32. The Celeste host profile raises
the byte/line limits to 65,534 and 12,000. Its expanded input uses 42,240
bytes, 3,009 lines, six source views and depth 3; the module workspace
reservation is 117,848 bytes.

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

The generated header records language format 1 and target format 1. Source-map
format 2 is deterministic JSON containing a logical source table and a source
id on every ordered header, enum member, property, overlay, raw and
target-operation mapping.
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

Run full ROM equivalence followed by Celeste's functional suite:

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

`src/inlay/celeste.inlay.asm` is the Inlay game-entry template. It
declares the complete object shape, typed `pObj` and `pOth` locations, and all
legacy `O_*` compatibility symbols from generated properties. It also declares
the 16-record object pool and asserts its 64-byte stride and 1,024-byte size.

`tools/inlay/prepare_celeste_modules.py` creates build-only inputs beneath
`build/inlay/`:

- `celeste.inlay.asm`, copied from the source-owned template;
- `modules/celeste_body.inlay.asm`, a compact copy of the existing main body;
- compact `obj`, `collide`, `player` and `draw` copies in which eligible
  direct pointer operations use typed field paths;
- `celeste_memmap.asm`, with only the contiguous `O_TYPE` through `O_SIZE`
  block removed.

The preparation step validates the expected include structure and accepts only
numeric `O_*` assignments, comments and blank lines in the removed block. It
uses a closed `O_*` mapping, requires exactly 66 conversions, maps the two
fixed-point `+1` accesses to nested `.integer` fields, and fails on an
unfamiliar eligible direct form. Non-equivalent `(zp),y` sequences remain
unchanged. It additionally requires exactly one byte-identical migration of
`obj_ptr` to a `using console6502` procedure whose scalar input is
convention-assigned and whose pointer result uses `return in pObj`, plus the
typed pool `address` operation. Nothing under `src/celeste/` is modified.

The conformance gate independently:

1. extracts and validates every current `O_*` assignment;
2. compares it with the generated layout constant;
3. compares nine representative direct typed operations with handwritten bytes;
4. compares indexed load/store, pool address, conventions, returns, scalar,
   pointer and aggregate frames, and marshalled calls with handwritten bytes;
5. assembles both complete Celeste entries;
6. compares all 65,536 bytes;
7. runs the existing reset-vector game tests against the frontend image.

## Measurements

These host-only measurements use 20 warm runs on the current development
machine. They describe algorithm/table pressure, not target-console speed:

| Input | Median | Min | Source | Structs | Fields | Locations | Operations | Names | Tokens |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Celeste fixture | 4.209 ms | 3.702 ms | 1,824 B | 4 | 36 | 1 | 9 | 320 B | 76 |
| Synthetic mixed source | 8.217 ms | 7.820 ms | 25,850 B | 120 | 960 | 120 | 120 | 1,879 B | 2,040 |

Both use the fixed 110,488-byte default workspace reservation. Re-run
`python3 tools/inlay/measure_inlay.py` to refresh the host measurement.

## Deferred work

The current slice does not implement user-defined calling conventions,
stack-passed inputs, aggregate-by-value inputs or returns, whole-aggregate
copies, automatic pool allocation, unions, native-aligned layout, dynamic
dispatch, general clobber analysis or automatic register allocation. The
implemented `console6502` convention, frame locations and invocation planner
are target-owned and deliberately bounded.

Native opcode emission is also deferred. Before it is added, one canonical ISA
description must generate or feed both host validation/lowering rules and the
future in-console encoder tables. A second handwritten opcode table would
create exactly the drift this frontend is intended to eliminate.

The build-only Celeste migration now covers every eligible direct `pObj` and
`pOth` byte load/store. Migration of additional operand forms or corpora
remains separate work.
