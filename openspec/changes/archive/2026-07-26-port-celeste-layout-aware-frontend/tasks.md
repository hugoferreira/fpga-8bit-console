## 1. Authoritative Layout Entry

- [x] 1.1 Add the complete packed Celeste object model under `src/layout/`.
- [x] 1.2 Derive every legacy `O_*` compatibility symbol from generated layout
  properties.
- [x] 1.3 Assert size 64, hair offset 37, array metadata and nested hitbox
  offsets before emission.

## 2. Build-only Corpus Adaptation

- [x] 2.1 Generate a build-only main body with ISA and local includes adjusted
  for `build/layout_aware/`.
- [x] 2.2 Remove only the contiguous legacy object-offset block while
  preserving all other memory-map declarations.
- [x] 2.3 Fail preparation on unexpected include counts, block boundaries or
  declaration syntax.

## 3. Build Integration

- [x] 3.1 Add append-only Makefile rules for the host frontend, preparation and
  generated Celeste source map.
- [x] 3.2 Select the generated source for `GAME=celeste` while retaining the
  existing customasm outputs and label conversion.
- [x] 3.3 Add frontend and equivalence prerequisites to the non-production and
  Celeste test aggregates.

## 4. Equivalence and Functional Gates

- [x] 4.1 Compare representative direct, nested, load and store typed operands
  with a handwritten customasm reference at instruction-byte level.
- [x] 4.2 Strictly compare every represented layout offset with the current
  authoritative Celeste `O_*` block.
- [x] 4.3 Assemble direct and frontend entries with customasm v0.14.1 and compare
  all 65,536 ROM bytes.
- [x] 4.4 Run the existing reset-vector Celeste suite against the image produced
  by `make GAME=celeste hex`.

## 5. Completion

- [x] 5.1 Document the compatibility boundary, build commands, generated
  artifacts and equivalence result.
- [x] 5.2 Run the frontend aggregate and relevant existing assembler
  regressions.
- [x] 5.3 Audit the scoped diff to confirm no Celeste corpus, ISA, RTL,
  simulator or memory-map source was changed.
