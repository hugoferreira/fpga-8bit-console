## 1. Freeze prerequisites and baseline

- [ ] 1.1 Verify `redesign-celeste-for-inlay` has integrated declaration-site exports, target-default conventions, namespaces and `codeptr`
- [x] 1.2 Record the accepted pre-change Celeste ROM, symbol and source-map digests
- [x] 1.3 Record per-module bytes, total physical bytes, flattened high-water and semantic-table high-waters
- [x] 1.4 Generate a checked alias inventory from `memmap.inlay.asm`, grouped by MMIO, shared locations, subsystem scratch, state, constants and fixed storage
- [x] 1.5 Add a temporary gate that prevents unrecorded legacy aliases or raw represented-region addresses during migration

## 2. Replace flattened module expansion

- [x] 2.1 Define the replayable immutable source-view and dependency-edge records in bounded caller workspace
- [x] 2.2 Discover the deterministic include graph with an explicit stack without copying module source bytes
- [x] 2.3 Add a module cursor that reports source id, original line and bytes directly to each compiler pass
- [x] 2.4 Replay declaration, resolution, validation and emission passes over the same graph while retaining shared semantic tables
- [x] 2.5 Adapt legacy single-stream input as a bounded replayable one-module graph
- [x] 2.6 Remove flattened-byte and expanded-line storage from the module workspace and statistics contract
- [x] 2.7 Preserve missing, duplicate and cyclic include diagnostics at their original source locations
- [x] 2.8 Add exact-capacity and one-past tests for modules, dependency edges, include depth, per-module bytes and semantic records
- [x] 2.9 Add a deterministic fixture whose total module source exceeds 65,535 bytes and verify byte-identical host output across capacity profiles
- [x] 2.10 Pass strict C89/C99/C++11, UBSan and cc65 portability for the replayable module implementation

## 3. Generalize typed physical locations

- [x] 3.1 Extend location records with scalar/pointer/code-pointer kind, storage width and optional fixed physical address
- [x] 3.2 Parse `location NAME : TYPE at ADDRESS` while retaining backend-bound locations without `at`
- [x] 3.3 Resolve namespaced location declarations and qualified procedure `in LOCATION` placement
- [x] 3.4 Emit deterministic target aliases for fixed locations without allocating or initializing storage
- [x] 3.5 Preserve declared scalar, pointer and code-pointer widths through invocation snapshots and assignments
- [x] 3.6 Permit explicit overlapping location views without inferring ownership, liveness or preservation
- [x] 3.7 Add positive, negative, exact-address, overlap, visibility, width and capacity fixtures

## 4. Extend fixed-overlay semantics

- [x] 4.1 Add semantic `address DESTINATION, OVERLAY.field` resolution and target events
- [x] 4.2 Add console6502 address-materialization lowering with exact relocation and clobber fixtures
- [ ] 4.3 Extend fixed-overlay byte load/store to every evidenced accumulator and physical-index form
- [ ] 4.4 Add registered fixed-overlay `mov` forms and reject unsupported memory-to-memory combinations
- [ ] 4.5 Add accumulator compare and the evidenced compare/test-and-branch overlay forms with exact flag contracts
- [ ] 4.6 Add fixed-overlay `inc`, `dec`, `and` and `ora` RMW events with volatility metadata
- [ ] 4.7 Support explicit page-view arrays and unit-stride indexed access without hidden scratch
- [ ] 4.8 Add exact customasm and machine-byte references plus negative width, volatility, index, scratch and clobber tests for every operation

## 5. Declare complete typed storage views

- [x] 5.1 Add `FxStorage` with explicitly offset cloud and particle arrays matching `$5600` through `$57bf`
- [x] 5.2 Add linear and explicit page views for the `$6000` overlay shadow and `$e000` write-only framebuffer
- [x] 5.3 Declare typed fixed locations for shared calling-convention state under `Machine`
- [x] 5.4 Declare subsystem-owned fixed locations for `Fixed`, `Objects`, `Collision`, `Draw`, `Fx`, `Room`, `Audio`, `Platform` and `Game`
- [x] 5.5 Add compile-time assertions for every MMIO, zero-page, RAM, effects, page and region boundary formerly stated numerically
- [x] 5.6 Verify all overlapping location and overlay views describe existing bytes and emit no storage

## 6. Migrate Celeste ownership by subsystem

- [x] 6.1 Convert `memmap.inlay.asm` from raw `#include` to semantic inclusion after replayable modules provide sufficient capacity
- [ ] 6.2 Migrate video and PSG operands to `VideoRegisters` and `PsgRegisters` overlays
- [ ] 6.3 Migrate persistent clock, room, input, restart, audio and HUD state to the `GameState` overlay
- [ ] 6.4 Move input masks to `Platform.Input` and music/fade values to `Audio`
- [ ] 6.5 Move room geometry, camera limits and tile identifiers to `Room`
- [ ] 6.6 Move object capacity and flags to `Objects` and derive pool/hair counts through layout queries
- [ ] 6.7 Move fixed-point word locations and shared receiver/dispatch locations to their declared physical owners
- [ ] 6.8 Move collision, drawing, hair and loader scratch to their owning namespaces
- [ ] 6.9 Migrate cloud and particle operations to the indexed `FxStorage` overlay
- [ ] 6.10 Migrate room tiles, row pointers, overlay shadow and framebuffer copies to typed linear/page views
- [ ] 6.11 Run complete 65,536-byte ROM equivalence after each ownership group

## 7. Delete the compatibility surface

- [ ] 7.1 Replace every remaining derivable address, capacity, stride and offset with a typed declaration or compile-time query
- [ ] 7.2 Review and annotate every irreducible raw memory operation with its flag, volatility, page or clobber reason
- [ ] 7.3 Remove the raw memory-map include from `main.inlay.asm`
- [ ] 7.4 Delete `src/celeste/memmap.inlay.asm`
- [ ] 7.5 Enable the permanent legacy-alias and represented-region raw-address deny-list
- [ ] 7.6 Confirm no handwritten Celeste language module is consumed through raw `#include`

## 8. Final validation and documentation

- [ ] 8.1 Run strict OpenSpec validation and the complete Inlay core/module/host/conformance suite
- [ ] 8.2 Run strict frontend portability under C89, C99, C++11, UBSan and cc65
- [ ] 8.3 Force two clean Celeste builds and compare assembly, source map, ROM, symbols, labels and readmemh deterministically
- [ ] 8.4 Verify the final ROM matches the frozen pre-change digest byte for byte
- [ ] 8.5 Run the complete Celeste functional, framebuffer, PSG trace and resource regression suites
- [ ] 8.6 Document replayable modules, fixed locations, overlay address materialization, page views and the removed compatibility file
- [ ] 8.7 Publish pre/post source-workspace and legacy-alias counts
