## 1. Freeze the Phase-A baseline

- [x] 1.1 Verify the source-port and byte-preserving Celeste baselines are immutable and record their artifact paths before changing the production equivalence contract
- [x] 1.2 Record the Phase-A ROM digest, executable footprint, instruction count, symbol map and custom/pseudo-operation counts
- [x] 1.3 Record the 127 object-offset setups, 157 raw object-indirect accesses and mechanically eligible legacy instruction sequences with source locations
- [x] 1.4 Add deterministic framebuffer checkpoints for title, first-room play, HUD and room transition states
- [x] 1.5 Add deterministic PSG music/SFX command-trace checkpoints for the existing functional scenarios

## 2. Implement bounded namespaces

- [x] 2.1 Add bounded namespace, export and qualified-name records to the portable workspace and statistics
- [x] 2.2 Parse nested `namespace` blocks and enforce exact scope closing
- [x] 2.3 Implement lexical unqualified lookup and root-qualified lookup without suffix matching
- [x] 2.4 Enforce module-private defaults and explicit cross-module exports
- [x] 2.5 Emit collision-free length-prefixed target symbols and preserve canonical names in diagnostics and maps
- [x] 2.6 Add exact-capacity, one-past-capacity, shadowing, collision, privacy and local-label namespace tests
- [x] 2.7 Pass strict C89/C99/C++11 and cc65 portability after namespace support

## 3. Eliminate compatibility value plumbing

- [x] 3.1 Add qualified constant, enum-member and layout-property resolution in frontend-owned operands
- [x] 3.2 Add semantic low/high/full procedure-address data declarations and relocation events
- [x] 3.3 Add prefix layout-query operands and typed field-offset materialisation with target range and clobber validation
- [x] 3.4 Replace underscore-only qualified-procedure spelling with the collision-free target-symbol encoder
- [x] 3.5 Add focused customasm reference tests for qualified values, dispatch data and prefix layout-query materialisation

## 4. Add Celeste-evidenced typed operations

- [x] 4.1 Add typed word field load/store events with width, byte-order, physical-location and scratch contracts
- [x] 4.2 Add explicit physical word add, subtract and compare operations for the console6502 target
- [x] 4.3 Add typed byte increment, decrement and mask/update operations with volatility and clobber rules
- [x] 4.4 Add indexed byte access for fixed-overlay arrays
- [x] 4.5 Add exact lowering references, negative diagnostics and bounded-capacity tests for every new operation
- [x] 4.6 Extend conformance to reject mechanically eligible legacy sequences while supporting documented semantic exceptions

## 5. Purify layouts and memory ownership

- [x] 5.1 Move ISA/customasm rule inclusion out of `layout.inlay.asm` into the selected target prelude
- [x] 5.2 Replace every `T_*` use with qualified `ObjectKind` values and delete the compatibility type aliases
- [x] 5.3 Replace every `O_*` use with typed operations or explicit qualified offset materialisation and delete the compatibility offset aliases
- [x] 5.4 Expand video and PSG overlays to cover palette, sprite, clipping, upload, channel and music arrays
- [x] 5.5 Add nominal overlays for tile maps, overlay framebuffer, zero-page working locations and persistent game state
- [x] 5.6 Reduce `memmap.inlay.asm` to typed regions plus unavoidable bank/vector constants and assert the established addresses

## 6. Scope generated data and fixed-point services

- [x] 6.1 Extend the Celeste graphics generator to emit a `Gfx` namespace with an explicit public manifest
- [x] 6.2 Move cloud, particle and effects constants/helpers under `Fx` and export only its lifecycle/draw surface
- [x] 6.3 Create the `Fixed` namespace and migrate compare, sign, absolute-value and approach helpers
- [x] 6.4 Adopt `ldab`, `stab`, `addw`, `subw`, `cmpw`, `mov`, `add`, `sub` and branch pseudo-operations wherever their documented contracts match
- [x] 6.5 Verify generated assets remain deterministic and fixed-point behavior matches all Phase-A physics checkpoints

## 7. Redesign platform, game and main

- [x] 7.1 Move reset-time hardware initialization, frame waiting and input sampling into `Platform`
- [x] 7.2 Move title/play state, clock, freeze, restart and frame orchestration into `Game`
- [x] 7.3 Give platform and game routines explicit procedure parameters, returns, locals and clobber contracts
- [x] 7.4 Reduce `main.inlay.asm` to target/bank composition, module inclusion, reset/vector binding and entry into `Game.run`
- [x] 7.5 Pass boot, title transition, framebuffer and audio checkpoints after the main redesign

## 8. Redesign the object subsystem

- [x] 8.1 Move pool addressing, clearing, allocation and destruction under `Objects`
- [x] 8.2 Emit lifecycle dispatch metadata from qualified procedure addresses without backend symbol spellings
- [x] 8.3 Replace manual receiver save/restore in spawn paths with explicit frame or physical procedure contracts
- [x] 8.4 Rewrite object traversal and dispatch around typed pool and object-kind operations
- [x] 8.5 Rewrite fixed-point object movement with typed word transfers and custom word arithmetic
- [x] 8.6 Split collision-stepping helpers into scoped procedures with explicit physical state
- [x] 8.7 Pass object allocation, movement, collision, dispatch and resource checkpoints

## 9. Restructure object-kind behavior

- [ ] 9.1 Move all player constants and private helpers into `Player`
- [ ] 9.2 Split `Player.update` into explicit input, environment, horizontal, jump/dash, vertical and animation responsibilities where contracts permit
- [ ] 9.3 Replace file-scope player temporaries with justified frame locals or explicitly owned player scratch
- [ ] 9.4 Complete scoped procedure coverage for player drawing, hair, death and movement helpers
- [ ] 9.5 Scope spawn, smoke and title constants and helpers under their existing namespaces
- [ ] 9.6 Pass running, jump, dash, wall collision, death, smoke and animation checkpoints after each object-kind migration

## 10. Scope remaining subsystems

- [ ] 10.1 Move collision entry points and private geometry helpers under `Collision`
- [ ] 10.2 Move room loading, camera, transition and title helpers under `Room`
- [ ] 10.3 Move sprite, tile, overlay and text drawing APIs under `Draw`
- [ ] 10.4 Move PSG upload, channel allocation, SFX and music controls under `Audio`
- [ ] 10.5 Remove residual unqualified implementation constants and global helper labels from production modules
- [ ] 10.6 Audit and document every remaining raw target sequence that cannot use an adopted typed/custom operation

## 11. Final regression and measurements

- [ ] 11.1 Run strict OpenSpec validation and the complete Inlay portability/conformance suite
- [ ] 11.2 Run the complete Celeste functional, framebuffer and PSG trace suites against the redesigned image
- [ ] 11.3 Force the production customasm build and verify deterministic binary, symbols, labels and readmemh outputs
- [ ] 11.4 Confirm the image fits existing ROM/RAM maps and improves executable instruction count and manual offset setup over Phase A
- [ ] 11.5 Publish pre/post footprint, instruction, pointer-plumbing and custom-operation adoption measurements
- [ ] 11.6 Update Inlay/Celeste documentation with namespaces, module APIs, customasm-only output and the new regression contract
