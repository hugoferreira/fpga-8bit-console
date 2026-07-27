## Handover — 2026-07-27

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

**Caveat for the remaining scratch migration (6.7+) — proc return placement.**
Two 6.7 attempts were reverted after hitting this. A procedure **parameter**
accepts a qualified typed-location placement (`self : ptr O in Machine.object`
compiles); a procedure **return** placement does not — `result : … return in
Machine.object` is rejected with `error[member-role]: return [in PHYSICAL]`, and
the same happens for a same-namespace qualified name. Celeste's receiver procs
in `obj.inlay.asm` (`pointer`, `allocate`) and the `Fixed` load/store procs use
`return in pObj` / `return in w0`, i.e. the raw physical alias as the return
slot. Those return placements therefore cannot move to a typed location without
either (a) a frontend change letting `return in` name a typed location, or
(b) leaving those specific return slots as reviewed physical names. Resolve this
before mass-migrating `w0`/`pObj`/`spawn_*`: operands and parameter placements
migrate cleanly (unqualified inside the owning namespace, qualified elsewhere),
but the handful of `return in <alias>` clauses need a decision first.

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
