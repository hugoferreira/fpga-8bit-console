## 1. Unified Member Model

- [x] 1.1 Add bounded procedure-member roles, placement kinds, convention
  handles and invocation-binding capacities to the portable API and workspace
  calculation.
- [x] 1.2 Replace separate parameter/local parsing with canonical
  `name : type` member parsing for input, `in frame` and `return` roles.
- [x] 1.3 Reject noncanonical qualifier orders and the provisional
  `local name : type` form with stable migration diagnostics.
- [x] 1.4 Test exact and one-past limits, duplicate names, illegal role
  combinations, incomplete types and naked frame locations under strict C89.

## 2. Conventions and Returns

- [x] 2.1 Add target-owned convention metadata and parse
  `proc Name using Convention` without adding user-defined conventions.
- [x] 2.2 Resolve omitted console6502 scalar inputs to A, X and Y in
  declaration order while preserving explicit placements.
- [x] 2.3 Resolve scalar returns to A, require explicit pointer placement and
  publish all resolved locations in semantic events and diagnostics.
- [x] 2.4 Test unknown conventions, exhausted location classes, unplaced
  pointers, procedures without conventions and explicit-override behavior.
- [x] 2.5 Verify return aliases generate no value movement and semantic `ret`
  retains existing frame and target-return lowering.

## 3. Typed Frame Locations

- [x] 3.1 Lay out scalar, pointer and complete packed-aggregate `in frame`
  members with bounded size, target alignment and published offsets.
- [x] 3.2 Replace `[local name]` byte syntax with typed frame-location operands
  using the declared member name.
- [x] 3.3 Add deterministic physical-to-frame and frame-to-physical pointer
  moves that copy every pointer storage unit and report clobbers.
- [x] 3.4 Resolve qualified byte fields relative to packed aggregate frame
  locations without implementing whole-aggregate copies.
- [x] 3.5 Test frame layout, pointer byte order, nested field offsets,
  stack-mutation rejection, frame elision and unsupported copy forms.

## 4. Invocation and Parallel Assignment

- [x] 4.1 Parse bounded single-statement
  `invoke Callee, name=value` forms, including trailing-comma continuation,
  and retain raw target calls as uninterpreted assembly.
- [x] 4.2 Validate declared callees, complete input coverage, duplicate or
  unknown bindings, source types and supported immediate/physical values.
- [x] 4.3 Build a deterministic parallel-copy plan from the pre-invocation
  machine state.
- [x] 4.4 Model exchange, target scratch and bounded frame-temporary choices,
  including frame-size and clobber metadata.
- [x] 4.5 Reject unsatisfied scratch requirements and overlapping invocation
  in naked code when no target-native exchange is legal.
- [x] 4.6 Test direct placement, immediates, swapped inputs, longer cycles,
  frame temporaries, naked failures and capacity limits.

## 5. Console6502 Lowering and Equivalence

- [x] 5.1 Add structured console6502 events and host lowering for convention
  assignments, typed pointer frame moves, aggregate-local fields and calls.
- [x] 5.2 Add focused unified-declaration, return, pointer-local and invocation
  fixtures with handwritten customasm references.
- [x] 5.3 Compare focused instruction and data bytes exactly, including every
  scratch or frame-temporary sequence used for parallel assignment.
- [x] 5.4 Preserve deterministic generated customasm and source-map output
  across sufficient capacity profiles.

## 6. Celeste Build-only Migration

- [x] 6.1 Change the generated `obj_ptr` declaration to
  `using console6502`, convention-assigned scalar input and
  `return in pObj`.
- [x] 6.2 Keep exact migration counts and verify that the generated `obj_ptr`
  instructions remain byte-identical.
- [x] 6.3 Keep frame-copy and invocation examples in focused fixtures unless
  an existing Celeste sequence has an exact lowering.
- [x] 6.4 Compare all 65,536 direct and frontend-built Celeste ROM bytes.

## 7. Integration and Documentation

- [x] 7.1 Update the language and corpus examples with the unified grammar,
  convention defaults, return aliases, frame addressing, invocation syntax,
  scratch policy and clobbers.
- [x] 7.2 Run `make GAME=celeste hex`, `make test-celeste`,
  `make test-layout-asm`, `make test-ext` and `make test`.
- [x] 7.3 Run strict C89 and UBSan tests and compile/assemble the expanded
  portable core with cc65/ca65.
- [x] 7.4 Strictly validate the OpenSpec change and audit that no owned
  Celeste, ISA, RTL, memory-map or simulator source changed.
