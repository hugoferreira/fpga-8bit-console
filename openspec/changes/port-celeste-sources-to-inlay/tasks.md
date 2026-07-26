## 1. Separate production and oracle

- [x] 1.1 Relocate the complete direct customasm Celeste corpus to the test-only reference tree
- [x] 1.2 Verify the relocated oracle still assembles to the established 65,536-byte digest
- [x] 1.3 Replace the mixed production tree with the exact flat `.inlay.asm` module set

## 2. Complete the Inlay graph

- [x] 2.1 Make `main.inlay.asm` semantically include every handwritten module and explicitly include only the four allowlisted opaque data/declaration modules
- [x] 2.2 Preserve all 66 typed field operations and the structured `obj_ptr` in production modules
- [x] 2.3 Update graphics, room and audio generation workflows to emit Inlay-named assets

## 3. Integrate and enforce

- [x] 3.1 Point the normal build and dependency tracking exclusively at the production Inlay corpus
- [x] 3.2 Point metrics, tests and documentation at the new production paths
- [x] 3.3 Add exact module-set and no-legacy-dependency conformance checks
- [x] 3.4 Retain full reference comparison, first-byte diagnostics, ROM size and golden digest checks

## 4. Verify

- [x] 4.1 Run strict OpenSpec validation and the complete Inlay suite
- [x] 4.2 Run the complete Celeste functional suite against the production Inlay image
- [x] 4.3 Force a normal Celeste build and verify its binary, symbols, labels, map and readmemh outputs
- [x] 4.4 Search the repository for stale production references to the former mixed source paths
