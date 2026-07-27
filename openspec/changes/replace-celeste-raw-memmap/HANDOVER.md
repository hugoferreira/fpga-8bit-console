## Completion — migration finished

`src/celeste/memmap.inlay.asm` is deleted. Every subsystem (sections 6.2–6.10)
was migrated to typed overlays, scoped locations and scoped constants, one
ownership group at a time, each re-checked against the frozen ROM
`e57a8ea4112c6f16086d6a618254214c453d464d4de9ce19bfa03ac608f53da6` (8.4). Two
clean builds are byte-deterministic across assembly, source map and ROM (8.3);
the full Inlay core/module/host/conformance suite (8.1), strict
C89/C99/C++11/UBSan/cc65 portability (8.2), and the Celeste functional /
framebuffer / PSG-trace / resource suites (8.5) all pass.

### Counts (8.7)

- **Legacy aliases:** 142 retired; **1 reviewed retention** — `OBJPOOL` (the
  object-pool base, consumed by the pool strategy's raw `obj_lo`/`obj_hi` target
  tables), declared in `layout.inlay.asm`.
- **Typed Celeste operands:** 207 fixed-overlay operations, 89 object-pointer
  field operations; 129 reviewed raw object indirects; 0 legacy offset setups.
- **Compiler workspace:** 188,768 bytes (host profile, 256-location capacity).
- The temporary alias-freeze gate is now a **permanent deny-list**
  (`tools/inlay/check_celeste_memmap_migration.py`): it rejects any handwritten
  module that reintroduces a retired alias as a bare `NAME = VALUE` definition.

### Frontend capabilities added to finish the migration (8.6)

- **Overlay address materialization** — `address DEST, overlay.field` and
  `address DEST, overlay` (qualified DEST) into a pointer-width location.
- **Fixed-overlay operations** — byte load/store, `cmp`, `inc`/`dec`/`and`/`ora`
  RMW, register loads/stores (`ldx`/`ldy`/`stx`/`sty`), accumulator logic
  (`and`/`ora`/`add`/`sub`), store-immediate/`mov` (incl. indexed
  memory-to-memory), and `cbeq`/`cbne`/`cblt`/`cbge`/`tbz`/`tbnz` compare/
  test-and-branch — qualified or unqualified inside the owner.
- **Page views + indexed arrays** — absolute indexed access with either X or Y,
  page fields past the first 256 bytes, and indexed carry arithmetic
  (`adc`/`sbc [overlay.field[x]]`) for the effects structure-of-arrays.
- **Enclosing-namespace resolution** — a bare name resolves lexically against
  the enclosing namespace chain (registers always win; siblings excluded).
- **Namespace-qualified operand bases** — `[Machine.object.core.x]` and
  qualified procedure return placements (`return in Fixed.left`).

### Predecessor integration (1.1)

Verified against the current frontend: **namespaces**, **`codeptr`** and
**target-default calling conventions** (a `proc` with no `using` clause
compiles) are integrated, and namespace **exports** resolve — the migration
uses all of them. The only unintegrated item is the predecessor's
*declaration-attached* `export` spelling (10.8); the detached `export NAME` form
was sufficient here and is used throughout. Bounded shift pseudo-ops (10.9) were
not needed by this corpus. The memory-map migration is therefore complete and
does not depend on the predecessor's two remaining open tasks.

---

## Handover — 2026-07-27 (historical, superseded by the completion note above)

This change is an intentionally build-clean checkpoint, not a completed
memory-map migration. Do not archive it yet.

### Accepted invariant

The frozen ROM remains:

`e57a8ea4112c6f16086d6a618254214c453d464d4de9ce19bfa03ac608f53da6`

The current frontend output assembles to that exact 65,536-byte image. The
generated assembly itself changed because fixed locations and additional
layout properties now emit semantic aliases; byte equivalence, not generated
text equivalence, is the acceptance criterion after this checkpoint.

### Completed foundation

- Frozen baseline, high-water measurements and 142-alias inventory.
- Temporary alias freeze gate:
  `python3 tools/inlay/check_celeste_memmap_migration.py`.
- Replayable immutable module graph with bounded module/edge/depth/per-module
  storage. No flattened source or expanded-line origin arrays remain.
- Direct source-id/original-line correlation in compiler passes and events.
- Deterministic >65,535-total-byte fixture and exact/one-past capacity tests.
- Strict C89/C99/C++11, UBSan and cc65 replay portability.
- Scalar, pointer and `codeptr` fixed locations, qualified procedure
  placement, overlap views and non-allocating target aliases.
- `FxStorage` structure-of-arrays view and explicit framebuffer/shadow page
  views.
- Initial private subsystem location declarations under `Machine`, `Game`,
  `Objects`, `Collision`, `Draw`, `Fx`, `Fixed`, `Room`, `Audio` and
  `Platform`.
- `memmap.inlay.asm` now enters through semantic `include`, proving the graph
  no longer has a total-source capacity ceiling.

Current replay measurements are approximately 140 KiB of physical semantic
module source using 4,728 bytes of module workspace. The compiler workspace is
188,248 bytes with the host profile's 256-location capacity.

### Progress since the checkpoint (operation matrix + MMIO/state/const migration)

All the following landed with the frozen ROM (`e57a8ea4…`) preserved after
every commit, C89/C99/C++11/UBSan/cc65 portability green, byte-exact
conformance fixtures, and the overlay-operation count tracked (now 203).

Production migration completed — sections 6.2 through 6.6:

- 6.2 — every video/PSG operand now reads `[video + VideoRegisters.*]` /
  `[psg + PsgRegisters.*]`; no raw `SPR_`/`PSG_` operand remains.
- 6.3 — all 135 game-state operands now read `[game + GameState.*]`.
- 6.4 — input masks are `Platform.Input.*`, music/fade are `Audio.*`.
- 6.5 — room geometry, camera limits and tile identifiers are `Room.*`.
- 6.6 — object capacity/flags are `Objects.*`; OBJ_MAX/HAIR_NODES derive from
  `objects.count` / `CelesteObject.payload.hair.hair.count` via namespace
  constants (raw pool/field queries only resolve inside `mov`/`cmp`, so they
  are wrapped in `Objects.slot_count` / `Draw.hair_nodes`).

Frontend operation matrix (the forms the migration needed):

- 4.1 / 4.2 — `address DEST, overlay.field` materialization (low/high `mov`).
- 4.3 — overlay byte load/store plus `ldx`/`ldy`/`stx`/`sty`, `and`/`ora`/
  `add`/`sub` accumulator forms, and absolute indexed access with X or Y.
- 4.4 — `mov [overlay+field], SRC` (immediate or `table + x`), memory-to-memory
  rejected.
- 4.5 — `cmp [overlay+field]` accumulator compare.
- 4.6 — `inc`/`dec`/`and`/`ora [overlay+field]` RMW with volatility.
- 4.7 — page views past 256 bytes via absolute indexed addressing.
- Compare/test-and-branch `cbeq/cbne/cblt/cble/cbgt/cbge/tbz/tbnz
  [overlay+field], …` (BRANCH_OVERLAY_DISP), tail passed through `emit_scoped_raw`
  so scoped constants in the tail resolve.
- 5.5 — every numeric region boundary pinned to the typed layout.

**RESOLVED (commit `inlay: parse qualified return-placement locations`).** Only
gap 1 below was real. The one-line return-branch change (`la_read_identifier` →
`la_read_qualified_identifier`, ~line 2232) is landed. Gap 2 was a
**misdiagnosis**: qualified placement *resolution* already works, because a
`location left : u16 at $08` inside `namespace Fixed` is interned with its
qualified name `Fixed.left`, and `la_find_location_text` matches on exactly that
name — no namespace-aware split is needed. The earlier "multi-module failure"
was the flawed repro referencing `Fixed.left` before declaring it (a placement
to an *undeclared* qualified location correctly fails with `member-placement …
(declared qualified location)`). Verified: declaring `Fixed.left/right/out` and
placing both a parameter (`in Fixed.left`) and a return (`return in Fixed.left`)
in the full Celeste build resolves and keeps the ROM at `e57a8ea4`. **6.7 is now
mechanical**: declare each owner location, then place params/returns there
(qualified across modules, or unqualified inside the owning namespace via the
enclosing-namespace resolver). Do NOT add a `la_find_location_qualified` helper.

Historical diagnosis (kept for context; gap 2 does not apply):

**Blocker for the remaining scratch migration (6.7+) — qualified placement
resolution.** Three 6.7 attempts were reverted diagnosing this; the migration is
mechanical *except* for procedure placement clauses, which the frontend does not
yet fully resolve to a typed location. Two frontend gaps, both in
`tools/inlay/inlay_core.c`, must be closed first:

1. **Return-placement parse** (~line 2229): the `return in …` branch reads the
   placement with `la_read_identifier` (unqualified), so `result : … return in
   Machine.object` is rejected with `member-role: return [in PHYSICAL]`. The
   parameter branch already uses `la_read_qualified_identifier`; making the
   return branch symmetric is a one-line change (verified: it parses and keeps
   the ROM at e57a8ea4, but is inert without gap 2).
2. **Placement resolution** (~line 2942): `la_find_location_text` matches a
   location by its *simple* name, so a qualified placement `in Fixed.left`
   never resolves (it searches for a location literally named "Fixed.left")
   and fails with `member-placement: … (declared qualified location)`. This
   needs a namespace-aware lookup that splits `Fixed.left` into namespace
   `Fixed` + name `left` and matches on the location's `namespace_handle`. It
   applies to *both* parameter and return placements — the parameter case only
   appeared to work earlier because a return-parse error aborted the run before
   resolution.

Celeste's receiver procs (`obj.inlay.asm` `pointer`/`allocate`) and the `Fixed`
load/store procs place params/returns at `pObj`/`w0`/`spawn_*` (raw physical
aliases). Everything else in 6.7 — operands, and the `sta w0` / `(pObj), y` /
`+1` forms — migrates cleanly (unqualified inside the owning namespace via
scoped-raw mangling, qualified elsewhere; skip struct-field and
`location`/`namespace` lines).

Both frontend fixes were prototyped and then reverted: (1) the one-line
return-branch `la_read_qualified_identifier` change, and (2) a
`la_find_location_qualified` helper that splits `Fixed.left` into namespace
`Fixed` + leaf `left` and matches the leaf against each global location's simple
name (`locations[i].name`) with the prefix against that location's reconstructed
`namespace_handle` path, wired into the placement resolver (`la_resolve_layouts`,
the `la_find_location_text` call near the `member-placement` failure). Both pass
in **isolation** — a faithful standalone repro of the failing `Objects.move`
proc (`self : ptr … in Machine.object` + `value : u16 in Fixed.left` under
`using console6502`) resolves and keeps the ROM at e57a8ea4. But the **full
multi-module Celeste build still fails** on `Fixed.left` with `member-placement:
… (declared qualified location)`, so the resolver returns INVALID only in that
context. The remaining bug is therefore multi-module-specific (a location or
namespace-handle state difference between the single-file case and the module
replay), not the resolver algorithm itself — start the next 6.7 attempt by
instrumenting `la_find_location_qualified` in the module-replay path (note the
portable core has no `<stdio.h>`; surface diagnostics through the event/error
channel instead of `fprintf`).

### Deliberately unfinished

- `memmap.inlay.asm` still contains the legacy compatibility aliases. Its
  semantic inclusion currently passes those assignment lines through as raw
  target syntax.
- The new subsystem locations are private and mostly unused. Add exports only
  as cross-module migrations require them; the predecessor change intends to
  replace detached exports with declaration-site visibility.
- 4.3 (every evidenced accumulator/physical-index load-store form) and 4.4
  (registered fixed-overlay `mov`, memory-to-memory rejection) are intentionally
  left for the production migration, which surfaces the exact forms Celeste
  needs; guessing them ahead of section 6 would add unused operations. 4.8 is
  the final fixture-completeness sweep once 4.3/4.4 land.
- Production operands have not moved from the legacy names to typed overlays
  or scoped locations.
- Permanent legacy/raw-address deny-list, compatibility-file deletion,
  documentation and final regression tasks remain open.
- `sourceBytes` is zero for replay input in host statistics; consumers should
  use `moduleSourceBytes`. Rename/remove the legacy field when finalizing the
  statistics contract.

### Dependency note

`redesign-celeste-for-inlay` still has open tasks for target-default calling
conventions, declaration-attached exports and bounded shift pseudo-operations.
This change's production migration should follow those syntax decisions rather
than deepening the temporary detached-export form.

### Recommended continuation order

The section-4 operation matrix and 6.2–6.6 are done, so the remaining migration
is the scratch/array groups plus deletion and validation:

1. 6.7 — migrate `w0`/`w1`/`w2` to `Fixed.*`, the shared pointer/dispatch
   locations (`pObj`→`Machine.object`, `pOth`, `pFn`→`Machine.function`,
   `pSrc`/`pDst`→`Machine.source`/`destination`, `pOvl`→`Draw.overlay_pointer`,
   `obj_slot`/`obj_free`/`spawn_*`→`Objects.*`). Honor the same-namespace
   `in`-placement caveat above: unqualified inside the owning namespace,
   qualified elsewhere. Skip struct-field and `location`/`namespace` lines.
2. 6.8 — collision (`c_*`→`Collision.*`), drawing/hair (`d_*`, `hair_*`→`Draw.*`)
   and loader scratch to their namespaces.
3. 6.9 — cloud/particle arrays (`CL_*`, `PA_*`) to the indexed `effects`
   (`FxStorage`) overlay via the `[effects + FxStorage.field[x]]` form.
4. 6.10 — room tiles, row pointers, overlay shadow and framebuffer copies
   (`ROOMTILES`, `OVLROW_*`, `OVLSHADOW`, `MAP_*`) to typed linear/page views.
5. 4.8 fixture sweep, then section 7 (delete `memmap.inlay.asm`, enable the
   permanent deny-list) and section 8 (final validation).

Task 1.1 stays blocked on `redesign-celeste-for-inlay`; the exports added so far
use the temporary detached form and should adopt its declaration-attached syntax
once it lands.

Per-group workflow that worked: survey the raw operand forms, map names to the
owning namespace's declared locations/constants, migrate the code portion only
(skip comments/declarations), add `export` for cross-module names, rebuild and
confirm the ROM is still `e57a8ea4`, then update the conformance
overlay-operation count and any namespace export manifest before committing.

### Validation commands

```sh
python3 tools/inlay/check_celeste_memmap_migration.py
make test-inlay
make test-celeste
openspec validate replace-celeste-raw-memmap --strict
```

The checkout is shared with Nemo/PSG work. Preserve all unrelated dirty files
and continue observing `docs/agent-coordination.md`; this change did not edit
Nemo-owned paths or the four shared coordination files.
