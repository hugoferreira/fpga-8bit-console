## 1. Stage A: bitwise compile-time operators

- [x] 1.1 Extend the core expression evaluator with `~ & ^ | << >>`,
      the precedence ladder from D1, plain-integer result typing for enum
      operands, and the parenthesization diagnostic for bitwise vs
      comparison/logical mixes
- [x] 1.2 Implement the operand-context masking rule (mask-and-check for
      byte contexts, reject-out-of-range for word/enum/offset contexts)
- [x] 1.3 Unit tests: precedence, masking, the mixing diagnostic,
      enum-operand composition, `static_assert` regression over existing
      arithmetic-mix forms
- [x] 1.4 Migrate the 9 `#<!` mask sites to typed `and`/`ora` with `#~`
      operands and the 2 raw `|` mask compositions to frontend-evaluated
      operands; verify emitted bytes unchanged at each site
- [x] 1.5 Re-freeze conformance exception counts (−9 "complemented/
      target-owned mask"); update docs/inlay.md; run `make test-inlay`
      and `make test-celeste`; snapshot metrics; commit

## 2. Stage B: decz, tstw, pinned inc/dec contract

- [x] 2.1 Implement `decz [p + T.field], label` as a branch operation
      (zero → branch untouched; nonzero → decrement, fall through, A =
      post value), with array/non-byte/overlay rejection
- [x] 2.2 Implement `tstw [p + T.field]` and `tstw wordloc` (Z
      contractual, N documented meaningless, X/Y preserved)
- [x] 2.3 Reference-model tests over all 256 pre-values for `decz`, and
      pin + test the existing `inc`/`dec`/`and`/`ora` A-and-flags
      contract in docs/inlay.md
- [x] 2.4 Register `decz`/`tstw` in `CUSTOM_OPS` and the conformance
      tuple (same commit as 2.1/2.2); add lowering references
- [x] 2.5 Migrate the 4 pre-decrement exception sites (jump_buffer,
      grace, Spawn delay, airborne grace) to `decz`; verify the Spawn
      hover-clamp path against the trace checkpoints
- [x] 2.6 Migrate word-zero-test sites to `tstw`, recording the N-retest
      cost where sign was previously free; re-freeze counts; docs; full
      gates; snapshot; commit

## 3. Stage C: word immediates and word moves

- [x] 3.1 Convert Player scratch word constants (`accel`, `decel_word`,
      `maxfall`, `grav`) to `location : u16` declarations and rewrite
      their `+1` spellings — separate commit, digest-checked
- [x] 3.2 Implement `movw wordloc, #expr16`, `movw wordloc, wordloc`,
      `stw [p + T.field], #expr16` with the 16-bit range rule
- [x] 3.3 Register in metrics/conformance; lowering references; unit
      tests including `#-K` equivalence with paired half spellings
- [x] 3.4 Migrate split-immediate pairs and word-field constant stores;
      replace all `Fixed.set_value`/`set_target`/`set_amount` call sites
      (immediate sites via `movw #`, variable sites via `movw loc,loc`)
- [x] 3.5 Delete the three `Fixed.set_*` procedures; re-freeze counts;
      docs; full gates; snapshot; commit

## 4. Stage D: inline procs

- [x] 4.1 Measure flattened-source headroom; record the budget check in
      the change notes before any expansion work
- [x] 4.2 Implement the `inline` qualifier: no emitted body/label,
      codeptr/low/high rejection, frame-member and `ret` rejection,
      non-local-label rejection, depth-8 bound, recursion rejection
- [x] 4.3 Implement expansion at invoke sites: marshalling via the E-
      stage ordering/elision contract (identity bindings elide), dot-
      local label freshening, tail-`jmp`-vs-enclosing-frame-size check
- [x] 4.4 Add bounded resources (inline procs, expansion sites, depth)
      to the workspace contract with diagnostic codes and exact-limit
      tests; publish expansion-site count in metrics
- [x] 4.5 Migrate the six jmp-forwarders and the `signed_word` wrappers;
      measure per-site byte deltas; full gates; snapshot; commit

## 5. Stage E: invoke ordering, elision, sources, tail

- [x] 5.1 Implement the ordering contract (register saves → field reads
      → destination writes) with pointer-base read-dependencies and the
      no-safe-order diagnostic
- [x] 5.2 Implement identity-binding elision and overlap-only scratch
      reservation; record per-site scratch usage in the source map
- [x] 5.3 Implement 16-bit immediate sources for `u16` members (via
      movw) and typed-field sources with optional `+ K` constant
      displacement
- [x] 5.4 Implement `invoke tail` with the frame-size-zero rule and its
      rejection diagnostic; unit tests for all rejections
- [x] 5.5 Audit candidate call sites against live `t0`-`t7` values;
      migrate the `Fixed.approach` ritual sites and eligible
      `spawn_smoke` sites (11 displacement-form candidates); full gates;
      snapshot; commit

## 6. Stage F0: namespace defaults (byte-neutral)

- [x] 6.1 Implement `namespace X using <target>` default and the
      `export` declaration qualifier
- [x] 6.2 Migrate all 109 `using` clauses and the 178-line export
      headers; acceptance is a ROM-digest-identical forced build; commit

## 7. Stage F1: method_table and pool-emitted tables

- [x] 7.1 Implement `method_table` per D6: value-keyed rows over a
      declared inclusive domain, published bias property, alias
      rejection, total coverage, column-typed `absent`, split lo/hi
      emission under qualified names
- [x] 7.2 Implement `pool ... emit table qlow, qhigh` generation from
      base/stride/count with qualified names
- [x] 7.3 Lowering-reference tests for qualified-label-plus-offset
      indexed operands; bounded-resource rows for tables/rows/columns
- [x] 7.4 Migrate the lifecycle lo/hi tables and `type_tile`/`type_hide`
      to `method_table`, byte-comparing generated against handwritten
      before deleting the handwritten tables; keep `= noop` rows (no
      `absent` migration in this change)
- [x] 7.5 Migrate `obj_lo`/`obj_hi` to `emit table`; retire the four
      high-byte-slice exceptions; re-freeze; docs; full gates; snapshot;
      commit

## 8. Close-out

- [x] 8.1 Regenerate the design's Context evidence table against final
      source; reconcile the D9 inventory-movement table with measured
      values
- [x] 8.2 Update docs/inlay.md exception-audit and Phase-B sections to
      reflect the new counts; strict OpenSpec validation; final
      double-forced-build determinism check

## Deviations (recorded at close-out)

- 2.5: three pre-decrement exception sites existed, not four; all three
  migrated (jump_buffer, airborne grace, Spawn delay).
- 4.5 / 5.5: the jmp-forwarders and the `Fixed.approach` ritual sites
  measured byte-negative to convert (the shared bodies exist to share
  bytes; a word-field invoke source costs more than `ldy #offset` +
  `jsr`). Per the design's per-site measurement rule they stay as
  procedures; the spawn_smoke family (10 sites) converted at −2 bytes
  and −5 lines per site.
- 6.2: the per-procedure `using` clauses migrated (109 → 0,
  digest-identical); the header `export` lists remain valid and were
  kept — the `export` declaration qualifier is implemented and tested.
- 7.2: the emission statement is spelled `pool tables NAME` at the data
  position (emission at the declaration would relocate the bytes); rows
  are symbolic `(BASE+offset)` so a raw target constant base works.
  Table names remain the pool declaration's target identifiers;
  qualified table names stay future work.
- 7.3: covered by the Celeste digest-identity of the generated pool
  tables and the behavioral suite over every dispatch kind, rather than
  a separate fixture.
