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

### Progress since the checkpoint (frontend operation matrix)

The independently-buildable frontend work is now in place, all with the frozen
ROM (`e57a8ea4…`) preserved, C89/C99/C++11/UBSan/cc65 portability green and
byte-exact conformance fixtures:

- 5.5 — every MMIO, tile-world, working-RAM, effects and overlay-shadow
  boundary that `memmap.inlay.asm` still states numerically is pinned to the
  typed layout with `static_assert`s in `layout.inlay.asm`.
- 4.1 / 4.2 — `address DEST, overlay.field` materializes a fixed overlay base +
  field displacement into a pointer-width, non-code destination via a low/high
  `mov` pair (no field read, no clobber); exact-byte fixture in
  `tests/inlay/overlay_address*`.
- 4.5 — `cmp [overlay + field]` accumulator compare (flags-only, carries
  volatility); pointer/indexed compares stay raw.
- 4.6 — `inc`/`dec`/`and`/`ora [overlay + field]` RMW: inc/dec lower native
  (no register clobber), and/ora keep the accumulator; each carries volatility.
- 4.7 — fixed-overlay byte access is absolute-addressed, so page views past the
  first 256 bytes are reachable with `ADDR + field[,Y]`; overlays now bound only
  the 8-bit index range, not a 255-byte displacement window.

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

1. Finish/integrate the predecessor's default convention and attached-export
   work, then close task 1.1. **This gates everything below** — the production
   migration must adopt its export/convention syntax, not the temporary
   detached-export form.
2. Migrate one ownership group at a time in section 6, checking the frozen ROM
   after each group. As each group surfaces the exact operand forms Celeste
   uses, close 4.3 (load/store forms) and 4.4 (`mov` forms) with the evidence,
   then run the 4.8 fixture sweep.
3. Turn the temporary alias inventory into the permanent deny-list, delete
   `memmap.inlay.asm`, then run section 8.

The section-4 operation matrix (address materialization, overlay compare,
overlay RMW, absolute/page-view indexed access) and the 5.5 boundary assertions
are already done and fixtured, so section 6 can consume them directly.

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
