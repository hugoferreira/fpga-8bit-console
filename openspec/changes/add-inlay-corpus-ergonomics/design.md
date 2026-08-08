# Design: corpus-driven Inlay ergonomics

Revision 2. Revision 1 was reviewed adversarially; the 24 findings are folded
in below. Material corrections: `decz` is a branch form (the fallthrough
contract failed the spawn-delay site), `method_table` keys rows by enum value
over a declared domain (declaration-order emission broke the `-1,x` bias and
aliased members), the `invoke` planner gains an explicit ordering contract and
elision rules (it never had overlap analysis to extend), inline-expansion
labels stay dot-local (a qualified label would reset customasm's local-label
scope mid-procedure), and the evidence table is regenerated from scripted
counts.

## Context

Inlay's Phase-B slice was accepted against the Celeste port, which makes that
port the language's first complete corpus: every place the semantic surface
was insufficient is visible either as a frozen exception, a residual raw
access, an unused feature, or a repeated raw idiom. The counts below are
scripted against current production source (6,972 lines, 109 procedures, 16
modules); each row records its generating command so stage metrics can be
diffed against it.

| Observation | Count | Command (in `src/celeste/`) |
| --- | ---: | --- |
| `invoke` statements | 0 | `grep -h '^\s*invoke' *.inlay.asm \| wc -l` |
| adjacent split-immediate pairs (`lda #<k` then `ld[xy] #>k` within 2 lines) | 22 | scripted (see change notes) |
| non-complement `lda #<` sites | 31 | `grep -h 'lda #<' *.inlay.asm \| grep -v '#<!' \| wc -l` |
| `#<!` complemented-mask sites | 9 | `grep -h '#<!' *.inlay.asm \| wc -l` |
| `jsr Fixed.*` sites (player) | 57 (43) | `grep -h 'jsr Fixed\.' *.inlay.asm \| wc -l` |
| `jsr Objects.spawn_smoke` sites | 16 | `grep -h 'jsr Objects.spawn_smoke\|jsr spawn_smoke' *.inlay.asm \| wc -l` |
| `inlay-exception` sites (frozen) | 21 | `grep -h 'inlay-exception' *.inlay.asm \| wc -l` |
| residual raw `(pObj\|pOth),y` accesses (frozen) | 129 | conformance inventory |
| pure `jmp`-forwarder procedures | 6 | player.inlay.asm:742-797 |
| parallel `ObjectKind`-indexed tables | 5 | obj.inlay.asm (`type_tile`, `type_hide`, init/update/draw lo+hi) |
| `using console6502` clauses | 109 | `grep -hc 'using console6502' *.inlay.asm` |
| `export` header lines | 178 | `grep -h '^ *export ' *.inlay.asm \| wc -l` |

(`marker_tile`/`marker_kind` are a linear-search pair keyed by cart tile id,
not an enum-indexed table; they are out of scope — see Non-Goals.)

Three structural facts explain most of these numbers:

1. **No immediate can reach a word location.** `ldw`/`stw` require a declared
   two-unit location; `mov` moves bytes. Every 8.8 constant travels as two
   byte immediates through `A`/`X` into a setter procedure
   (`Fixed.set_value`/`set_target`/`set_amount` exist for no other reason),
   and every word-field constant store is spelled as two `sta (p),y` with a
   manual `iny`.

2. **A call costs 3 bytes; abstraction costs a call.** `jsr Fixed.load_object`
   is smaller than the open-coded typed `ldw`, so the port routes compile-time
   field offsets through shared bodies where the offset becomes runtime `Y` —
   inflating the residual raw-access count — while short idioms
   (pre-decrement observation, bit set/clear, word-zero tests) are open-coded
   at every site because naming them would cost a `jsr`/`rts` and a clobber
   contract. There is no zero-cost naming mechanism.

3. **`invoke`'s source kinds miss the game's actual argument shapes.** The
   game passes 16-bit constants, object fields, and coordinates with small
   constant offsets; `invoke` binds byte immediates and physical locations.
   With its natural argument kinds missing, tail transfers unsupported, and
   its scratch area (`t0`-`t7`) doubling as the game's own hand-allocated
   cross-call scratch, no call site preferred it.

The frozen exception audit has four categories; three map onto missing forms:

- "complemented target constant" / "mask constant remains target-owned"
  (9 sites): the compile-time grammar has no bitwise operators, so `#<!x`
  cannot be a typed operand.
- "branch observes pre-decrement value" (4 sites): the typed `dec` observes
  the post-value; the cart's timers branch on the pre-value.
- "four raw high-byte slices for the fixed numeric object-pool base": the
  hand-written `obj_lo`/`obj_hi` tables — retired by pool-emitted tables
  (D7).
- "variable update operand" (6 sites): out of scope — a runtime operand is
  not a compile-time form (Non-Goals).

## Goals / Non-Goals

**Goals:**

- Close the expressible-but-not-expressed gap: every frozen exception
  category whose cause is a missing *compile-time* form gets that form.
- Provide a zero-cost naming primitive (`inline proc`) with rules strict
  enough that an expansion is exactly the bytes the author would have
  written.
- Make `invoke` safely adoptable: explicit marshalling order, identity-
  binding elision, overlap-only snapshotting, the two missing source kinds
  (word immediates, typed fields with optional constant displacement), and
  `invoke tail`.
- Replace hand-synchronized enum-indexed dispatch and pool address tables
  with generated, coverage-checked declarations.
- Reduce per-procedure boilerplate (`using`, `export`) with byte-identical
  output.
- Migrate Celeste at each stage; update the conformance inventory with
  per-stage expected movements (see D9 — not all counts move downward);
  keep every behavioral gate green.

**Non-Goals:**

- Runtime-variable displacements (`(pObj),y` with computed `Y`) stay raw;
  no addressing-mode invention.
- No register allocation, liveness analysis, or general clobber inference.
  Inline expansion checks declared contracts; it does not derive them.
- No automatic inlining decisions: `inline` is an explicit qualifier, never
  a frontend size heuristic.
- The "variable update operand" exceptions remain.
- Non-enum-keyed lookup tables (`marker_tile`/`marker_kind`) stay
  handwritten. A keyed-row search-table form is future work.
- No native encoding work; customasm v0.14.1 remains the backend.
- Byte-count parity is not a goal per stage. Cost deltas are measured and
  reported via `celeste_redesign_metrics.py`, as in Phase B.

## Decisions

### D1. Bitwise operators in compile-time expressions

Add unary `~` and binary `&`, `^`, `|`, `<<`, `>>`.

**Precedence**, tightest first, among themselves and the existing arithmetic:
unary (`-`, `!`, `~`); `* / %`; `+ -`; `<< >>`; `&`; `^`; `|`. Mixing rule,
stated separately: an operand of a comparison, equality, `&&` or `||`
operator that is itself a `&`, `^`, `|`, `<<` or `>>` expression must be
parenthesized, and vice versa; an unparenthesized mix is a diagnostic.
Arithmetic mixing is unrestricted — `$4000 + X.offset == $4038` (used ~40
times in layout assertions) is unaffected, and no existing `static_assert`
in the corpus mixes the two families.

**Result type and width**: a bitwise expression yields a plain
target-storage-unit integer, never an enum type, even when its operands are
enum members. A bitwise result bound to an N-unit operand is masked to N
units *at the operand*, and any range check (including the typed byte-update
"out-of-range mask" rejection) applies to the masked value — so
`and [p + T.flags], #~bit_jump` is legal with `bit_jump = $01`: `~$01`
masks to `$FE`. Contexts that mask: byte-update masks, `data u8`, byte
immediates, and each half of a word immediate. Contexts that reject
out-of-range instead: `movw`/`stw` 16-bit immediates (D3), enum member
values, explicit field offsets.

Existing raw sites that already compose masks with `|`
(player.inlay.asm:713 `#Platform.Input.left|Platform.Input.right`,
obj.inlay.asm:251 `#flag_collideable|flag_solids`) become frontend-evaluated
under the same rules and are part of stage A's migration list; their emitted
bytes must not change.

*Why not reuse `!`*: `!` is logical not in the existing grammar; overloading
it would silently change existing `static_assert` meanings.

### D2. `decz` and `tstw`

**`decz [p + T.field], label`** — a branch form, joining the `tbz`/`cbeq`
family, not a fallthrough op. Semantics: if the byte field is zero, branch to
`label` with the field unmodified; otherwise decrement the field and fall
through. On fallthrough, A holds the post-decrement value; other flags are
unspecified. Rationale (review finding 1): the corpus's three timer shapes
disagree about what follows —

- jump_buffer (player.inlay.asm:152-157) and grace (:196-200) converge
  immediately, either contract works;
- spawn delay (:923-932) branches away on the zero case (`beq .land`) and
  does *more work* on the decrement path. A fallthrough contract publishing
  Z from the post-value would take the branch one frame early there.

The branch form serves all three with one contract, and a straight-line
6502 lowering (load / `beq` / decrement / store) implements it exactly.

**`tstw`** in two forms: `tstw [p + T.field]` and `tstw wordloc` (the
location form covers Fixed.sign-style tests over `word0`,
math.inlay.asm:110-113 and player.inlay.asm:918-922). Lowering: `lda low` /
`ora high`. Contract: Z set iff the two-unit value is zero; **N is
meaningless** — sites that currently get the sign for free from a bare
high-byte load must re-test if they adopt `tstw`, a ~2-byte cost per such
site recorded in the stage-B metrics expectation.

**Companion documentation fix**: the existing `inc`/`dec` typed updates get
their A-and-flags contract pinned in `docs/inlay.md` ("A = post-operation
value; N,Z from it") with the same 256-value reference-model test — the
corpus already load-bears on it (the Title banner fix,
player.inlay.asm:1093-1099) and `decz` must be specified against a defined
sibling.

*Why ops and not inline procs*: all of these take a field-path operand
resolved to a constant displacement; procedures cannot take field paths as
arguments.

### D3. Word immediates and word moves

Three forms:

- `movw wordloc, #expr16` — two immediate loads, two absolute stores;
  clobbers A and flags.
- `movw wordloc, wordloc` — location-to-location word copy through A;
  clobbers A and flags. Required because half the `Fixed.set_*` call sites
  pass runtime words (`accel`, `decel_word`, `maxfall`, `grav`), not
  constants; without this form the setters cannot be deleted.
- `stw [p + T.field], #expr16` — immediate through pointer displacement.

Immediates accept any compile-time expression including D1 operators;
`#-wall_jump` replaces the paired `#<(-wall_jump & $FFFF)` /
`#>(-wall_jump & $FFFF)` spellings whose halves must currently agree by
hand. Range rule: the value must fit 16 bits signed-or-unsigned (customasm's
`#d16` acceptance rule).

**Migration precondition** (review finding 8): `movw`'s destination must be
a declared two-unit location, but the Player scratch words are namespace
constants (`accel = $56`) addressed as `accel`/`accel+1`. Stage C first
converts `accel`, `decel_word`, `maxfall`, `grav` (and `Fixed`-adjacent
scratch as needed) to `location name : u16 at $xx` declarations and rewrites
their `+1` raw spellings. That rewrite is committed separately from the
`movw` adoption so the metrics snapshot attributes churn correctly.
`Fixed.set_value`/`set_target`/`set_amount` are deleted only after both
`movw` forms have replaced all their call sites.

*Alternative considered*: width inference on `mov` from the destination.
Rejected — the pseudo-op convention is that a bare mnemonic is the byte form
and trailing `w` marks 16 bits; silent width inference is the ambiguity
family documented with the `asl 3` case.

### D4. `inline proc`

Declaration: `proc name inline using console6502` with the existing member
grammar. Semantics:

- The body expands at each call site via `invoke` (D5). No standalone body
  or label is emitted; `low`/`high`/`codeptr` of an inline proc is an error.
- **Labels**: an inline body may contain only `.local` labels. Each
  expansion freshens them as dot-local names with a reserved suffix
  (`.__la_inl<N>_<name>`), so no new customasm label scope opens
  mid-procedure — a qualified (non-dot) label would reset the `.local`
  scope and detach the caller's own labels (review finding 5). A non-local
  label in an inline body is a diagnostic.
- `frame` members are rejected; `ret` is rejected (the body falls through).
- A tail `jmp` to a non-inline procedure is allowed, and is checked at each
  expansion site against the *enclosing* procedure's frame size: expansion
  into a procedure with frame size > 0 is rejected with a diagnostic naming
  both the inline proc and the call site (same rule as `invoke tail`, D5 —
  frame *size*, not frame mode, since `frame` is the default and almost all
  corpus procedures are default-frame with zero frame bytes).
- Inline-in-inline expansion is bounded at depth 8; recursion is an error.
- Placements may name caller-owned locations, and identity bindings elide
  (D5), so a well-declared inline proc expands to exactly the bytes the
  open-coded idiom used — the zero-cost property is checkable per site in
  the metrics snapshot.

**Named consumers** (review finding 13 — the stage commits to concrete
sites, with deltas measured, not assumed): the six `jmp`-forwarders
(`Player.create_hair`, `set_hair_color`, `draw_hair`,
`set_speed_x_signed`, `set_speed_y_signed`, and the `signed_word` entry
chain, player.inlay.asm:742-797), plus new zero-cost library procs
introduced by stages B/C migration where a raw idiom recurs but no typed op
fits. Inlining is *not* applied to `Fixed.load_object`/`store_object`-class
bodies where the call is smaller than the expansion; that choice stays with
the author per site.

**Bounded-model additions** (review finding 14): inline-proc count,
expansion-site count and expansion depth join the limits table with stable
diagnostic codes and exact-limit tests. Expansion multiplies existing
budgets — each expansion charges its body's operations against the 2,048
structured-operation limit and its lines against flattened source capacity.
Celeste currently sits at 65,394 of 65,534 flattened significant bytes, so
stage D starts with a measured headroom check and the migration's net
source-byte delta is tracked per commit (migrations that replace multi-line
rituals with one-line calls buy headroom; expansions spend it).

### D5. `invoke`: ordering contract, elision, new source kinds, tail

The current planner snapshots every physical source unconditionally and has
no overlap analysis (review findings 3, 4). This design specifies the
contract rather than extending an assumed one:

**Ordering contract**: (1) register-borne sources (`A`/`X`/`Y`) are saved to
scratch first — field reads clobber `A`, so this must precede them; (2)
typed-field sources are read into scratch or their destinations; (3)
destination writes happen last. A typed-field source takes a
read-dependency on its base pointer location: a binding that writes that
pointer (e.g. `self=Machine.other` alongside `x=[Machine.object.core.x]`)
is ordered after the read, or diagnosed when no safe order exists.

**Elision and overlap-only snapshotting**: a binding whose source location
equals its destination placement emits nothing and reserves no scratch
(`self=Machine.object` into `self : ptr … in Machine.object` is free).
Scratch is reserved only for bindings that actually conflict under the
ordering contract, not for every physical source. This is a prerequisite
for adoption: the scratch area *is* `Machine.t0`-`t7`, which the game uses
as hand-allocated cross-call scratch (216 references; live-across-call uses
documented at obj.inlay.asm:302, :133-154, :449-453). Every migrated call
site is audited against live `t*` values as a stage-E checklist item, and
the planner's per-site scratch usage appears in the source map so the audit
is mechanical.

**New source kinds**:
- 16-bit immediates binding to `u16` members placed in two-unit locations,
  lowering via D3 `movw`. A 16-bit immediate into a byte member stays an
  error.
- Typed-field sources `value=[self.core.speed_x]` for one- and two-unit
  leaves, with an optional constant byte displacement:
  `x_position=[self.core.x] + 4`. The displacement form is included because
  the corpus already answers the deferral question: 11 of 16 `spawn_smoke`
  sites compute `coordinate + small constant` (or `+ input*6`, which stays
  raw); a plain-field-only form would convert ~5 sites.

**`invoke tail`**: identical marshalling, final transfer emitted as `jmp`.
Rejected when the enclosing procedure's frame *size* is > 0 (not frame
mode — `frame` is the default and the `Player.update` chain of nine
default-frame zero-byte procedures is the primary consumer). Same rule and
diagnostic as raw `RTS` today.

**`invoke` of an inline proc** marshals bindings into the declared
placements under the same ordering/elision rules, then splices the body in
place of the `jsr`. With identity elision, an inline proc whose placements
are the caller's own locations marshals nothing.

### D6. `method_table` — value-keyed over a declared domain

```asm
method_table lifecycle : ObjectKind[player .. mover] -> init, update, draw
    player = Player
    spawn  = Spawn
    ...
    key.init = absent
end
```

Rules (rewritten per review finding 2):

- **Rows are keyed by enum member value over an explicit inclusive domain**,
  not by declaration order. The emitted table has
  `high(domain) - low(domain) + 1` rows per column; the base bias is derived
  from `low(domain)` and published as a queryable property
  (`lifecycle.bias`), so the consumer's `-1, x` indexing derives from the
  declaration instead of a hand-written literal. `ObjectKind.free = 0`
  simply lies outside the domain — no forced row, no silent shift.
- Enum members with duplicate values inside the domain are rejected
  (aliases like `actor = ObjectKind.player` cannot generate two rows).
- Coverage is total over the domain: every value in range must be assigned
  or explicitly marked `absent`, so adding an `ObjectKind` inside the
  domain without updating the table is a diagnostic.
- `absent` is legal **only for code-pointer columns**, where it emits the
  zero entry the dispatch guard (`ora`/`beq`) tests. Value (`u8`) columns
  require an explicit value for every row — in the corpus's `type_hide`,
  zero is a meaningful value ("not hidden"), not an absence, and coverage
  checking must not conflate them.
- Column emission: code-pointer columns emit split `low`/`high` tables
  under generated qualified names (`Objects.lifecycle.init_lo`, …); `u8`
  columns emit one table each. The generated-name shape and
  qualified-label-plus-offset indexed operands (`lifecycle.init_lo + bias,
  x` style) get lowering-reference tests before the stage lands (review
  finding 21).
- Migration is byte-compared: generated tables must equal the handwritten
  ones before the handwritten ones are deleted. Note: today's tables have
  *no* zero entries — kinds without an init use `noop` (obj.inlay.asm:84).
  Migrating `noop` rows to `absent` changes those bytes and is behavioral
  only because of the existing `ora`/`beq` guard; that step is its own
  commit with the functional gates as acceptance, or the rows stay `= noop`.

The dispatch control flow stays handwritten; this generates the data.
`marker_tile`/`marker_kind` are out of scope (Non-Goals) — they are a
linear-search pair keyed by cart tile id, a different shape.

### D7. Pool-emitted tables and namespace defaults

`pool` gains an emitting form:
`pool objects : CelesteObject[16] at OBJPOOL emit table Objects.slot_lo, Objects.slot_hi`
generates the low/high address-byte tables from base, stride and count —
the same 32 bytes handwritten today at obj.inlay.asm:27-34. This retires
the frozen "four raw high-byte slices for the fixed numeric object-pool
base" exception category outright. Qualified table names resolve through
the same generated-name machinery as D6, covered by the same
qualified-label-plus-offset lowering references. The non-emitting
`table a, b` form remains for pre-existing tables.

`namespace X using console6502` sets the default convention for procedures
declared inside; per-proc `using` overrides. `export` becomes a declaration
qualifier (`proc init export using …`, `location slot : u8 export at …`);
header `export` lists remain valid. Both are pure source-shape changes:
their acceptance gate is a ROM-digest-identical forced build (the counted-
shift precedent), and they land as their own stage (F0) so their large
source churn (109 `using` clauses, 178 export lines) never contaminates a
byte-attribution snapshot.

### D8. Metrics, conformance and bounded-model registration

Every new op (`decz`, `tstw`, `movw`, immediate `stw`) registers in
`CUSTOM_OPS` in `celeste_redesign_metrics.py` and the matching conformance
tuple *in the same commit that introduces the op* — the annotated parser
drops unknown mnemonics from `executableBytes`, so an unregistered op makes
a migration report savings it did not make. Inline expansions publish an
expansion-site count in the metrics snapshot (the `countedShiftSites`
precedent) so byte-neutral adoptions stay visible.

New bounded resources join the workspace-contract table with stable
diagnostic codes and exact-limit/one-past-limit tests: inline procs,
inline expansion sites, inline expansion depth, method tables, method-table
rows and columns.

### D9. Stage order and inventory movement

Order: **A → B → C → D → E → F0 → F1.**

- A (bitwise) and B (`decz`/`tstw`) delete exception categories early and
  de-risk the conformance re-freeze workflow.
- C (word immediates/moves) is the largest line-count reduction and a
  dependency of E's word-immediate bindings.
- D (inline procs) precedes E because `invoke`-of-inline splicing and the
  elision rules are one mechanism, specified and tested together.
- F0 (`using`/`export` defaults) is byte-neutral, gated on a
  digest-identical build; it sits after the byte-moving stages so its
  source churn never shares a snapshot with them, and before F1 only for
  review convenience.
- F1 (method_table, pool tables) goes last because it changes generated
  data bytes.

"Re-freeze counts monotonically downward" (revision 1) was wrong. The
per-stage expected movements of the conformance inventory:

| Stage | exceptions (21) | residual raw `,y` (129) | typed ops (89) | offset queries (97) | other |
| --- | --- | --- | --- | --- | --- |
| A | −9 (masks) | — | +9 | — | — |
| B | −4 (pre-decrement) | −~8 (word-zero tests) | +12-16 | −~4 | `tstw` N-retest bytes |
| C | — | −~15 (word-field constant stores) | +~20 | −~10 | `Fixed.set_*` deleted |
| D | — | — | — | — | expansion-site count appears |
| E | — | −~10 (marshalling) | — | −~6 | per-site scratch audit |
| F0 | — | — | — | — | ROM digest identical |
| F1 | −4 (pool high-byte slices) | — | — | — | table bytes byte-compared |

Estimates marked `~` are sized during each stage's migration and frozen at
its commit; the direction is contractual, the magnitude is measured.

### Measured close-out (all stages landed)

Scripted against final production source. The conformance inventory moved
21 → 9 exceptions, 129 → 111 raw indirects (the pre-change baseline had
drifted to 178 before stage A; the stage-A→F trajectory was
178 → 163 → 147 → 115 → 111), 133 → 95 semantic offsets and
258 → 293 typed operations, with the "complemented target constant",
"mask constant remains target-owned", "branch observes pre-decrement
value" exception categories and the four-raw-high-byte-slice audit
category all retired. Remaining exceptions: two following-flag
dependencies, six variable-update operands, one wrapping add/mask update.

| Observation | Before | After |
| --- | ---: | ---: |
| `invoke` statements | 0 | 10 |
| `inlay-exception` sites | 21 | 9 |
| `jsr Fixed.*` sites | 57 | 41 |
| non-complement `lda #<` sites | 31 | 11 |
| `#<!` complement sites | 9 | 1 (accumulator-logic latch) |
| per-proc `using console6502` clauses | 109 | 0 (25 namespace defaults) |
| hand-synchronized `ObjectKind` tables | 5 | 0 (one `method_table`) |
| handwritten pool address tables | 2 | 0 (`pool tables`) |
| new `movw` / imm `stw` / `decz` / `tstw` sites | — | 24 / 19 / 3 / 7 |

Stage D's inline procs shipped with unit tests and byte-compared
expansion references but no Celeste conversions: the six jmp-forwarders
measured as byte-negative to inline (the shared bodies exist to share
bytes), which is the per-site measurement discipline the stage
committed to. F0 was digest-identical; F1's pool tables were
digest-identical, and the method_table's only byte movement was
`type_hide` relocating next to its siblings, accepted by the behavioral
gates.

## Risks / Trade-offs

- [Byte growth from inline adoption] → explicit qualifier, per-site
  adoption measured against the snapshot; identity-elision rule makes
  zero-cost checkable, not assumed.
- [Scratch collision destroys live `t*` values at migrated invoke sites] →
  overlap-only snapshotting plus per-site scratch usage in the source map;
  stage-E migration checklist audits each site against live `t*` uses.
- [Inline expansion resets label scope] → dot-local freshening only;
  non-local labels in inline bodies rejected.
- [Flattened-source headroom (~140 bytes) exhausted by expansions] →
  measured headroom check opens stage D; migrations that shrink source are
  sequenced before adoptions that spend it.
- [Flag-contract drift on `decz`/`tstw`/`inc`/`dec`] → contracts pinned in
  docs; 256-value reference-model tests, the `asr` precedent.
- [Unregistered ops corrupt metrics] → registration in the introducing
  commit; conformance fails on unknown mnemonics.
- [`invoke tail`/inline tail skipping frame epilogues] → frame-*size* rule
  checked per expansion site; unit tests for the rejection diagnostics.
- [Grammar ambiguity] → separate precedence table and mixing rule;
  unparenthesized bitwise/comparison mixes are diagnostics.
- [method_table migration changes dispatch-table bytes] → generated tables
  byte-compared against handwritten before deletion; `noop`→`absent` is an
  isolated, behavior-gated commit or not done.
- [ROM image changes at every byte-moving stage] → accepted; behavioral
  gates, double-forced-build determinism, and per-stage metrics snapshots
  are the acceptance surface, as Phase B established.

## Migration Plan

Each stage: implement core + host, unit tests, lowering references,
register metrics and bounded resources, migrate eligible Celeste sites,
update the conformance inventory per the D9 table, run `make test-inlay`
and `make test-celeste`, capture a metrics snapshot, then commit. Source
reshaping that is a precondition (C's scratch-word `location` conversion)
commits separately from the feature adoption it enables. Rollback is
per-stage revert; stages depend only backward.

## Open Questions

- Whether a keyed-row search-table form (the `marker_tile`/`marker_kind`
  shape: emit search array, value array, and a `.count`) is worth a future
  change. Out of scope here.
- Whether `invoke` displacement sources should ever allow non-constant
  terms (`+ input*6`). Not in this change; those sites stay raw.
