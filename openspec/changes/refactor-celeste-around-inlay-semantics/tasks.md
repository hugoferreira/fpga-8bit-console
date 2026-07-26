All tasks below are Phase A and retain exact ROM equivalence. Custom-CPU-native
instruction selection, namespace design, compatibility-symbol removal and
whole-module redesign are tracked by the separate Phase B change.

## 1. Readable bounded modules

- [x] 1.1 Make module expansion remove semicolon comments outside quoted strings while retaining line origins
- [x] 1.2 Add exact, boundary and quoted-semicolon module tests
- [x] 1.3 Restore original comments and formatting in main, object, collision, player and draw modules

## 2. Honest object semantics

- [x] 2.1 Add object-kind and lifecycle enums
- [x] 2.2 Split the object record into an 18-byte core and 46-byte payload union with four variant views
- [x] 2.3 Rewrite typed field paths to name their owning variant and assert every established offset

## 3. Procedures and hardware views

- [x] 3.1 Convert all twelve object lifecycle dispatch targets to namespaced receiver procedures
- [x] 3.2 Preserve the existing parallel low/high dispatch tables and exact call behavior
- [x] 3.3 Add explicit-offset video and PSG layouts with fixed overlays
- [x] 3.4 Convert eligible direct MMIO loads and stores to typed overlay operands

## 4. Conformance and documentation

- [x] 4.1 Add readable-source and semantic construct manifest checks
- [x] 4.2 Count and report residual legacy offset setup and raw object-indirect accesses
- [x] 4.3 Update Inlay and Celeste documentation with the refactored model and deferred typed-index gap

## 5. Verification

- [x] 5.1 Run strict OpenSpec validation and the complete Inlay portability suite
- [x] 5.2 Run full-ROM direct-reference and golden-digest equivalence
- [x] 5.3 Run the complete Celeste functional suite and forced production build
