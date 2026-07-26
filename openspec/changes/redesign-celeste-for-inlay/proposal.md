## Why

The byte-preserving Celeste refactor proved that Inlay can describe the
existing representation, but it intentionally retained the program's
transliterated structure, global symbol conventions and much of its manual
6502 plumbing. Celeste should now become a native demonstration of Inlay and
the custom CPU rather than a customasm-compatible spelling of the old source.

## What Changes

- **BREAKING** Permit the production Celeste ROM, symbols and instruction
  addresses to change; replace complete-image equality with behavioral,
  visual, audio and resource regression gates.
- **BREAKING** Make customasm the required downstream assembler for Celeste
  because the redesigned program deliberately uses custom-CPU instructions and
  pseudo-operations that ca65 cannot encode.
- Add first-class namespaces with nested declarations, qualified references,
  module visibility and deterministic target-symbol lowering.
- Add semantic operations needed to remove compatibility layout constants:
  typed field-offset materialisation, word loads/stores/arithmetic, typed
  read-modify-write forms and indexed fixed-overlay access.
- Remove the `T_*` and `O_*` compatibility block from
  `layout.inlay.asm`; keep that module limited to types, overlays, locations,
  pools and assertions.
- Scope generated graphics and effects constants and expose only their public
  assets and entry points.
- Turn fixed-point math into a namespaced library that uses custom word
  operations directly instead of global scratch conventions where practical.
- Replace most raw addresses in `memmap.inlay.asm` with typed RAM and MMIO
  overlays, including arrays and game-state views.
- Redesign `obj.inlay.asm` around a scoped object-pool API, typed dispatch
  metadata and explicit lifecycle procedures.
- Split and restructure player, spawn, smoke and title behavior into scoped
  procedures with declared physical parameters and locals.
- Rebuild `main.inlay.asm` around explicit platform startup, game state and
  title/play state transitions instead of preserving the transliterated label
  order.
- Record pre/post ROM size, instruction count, cycle pressure, pointer
  plumbing and custom-operation adoption.
- Keep the portable Inlay frontend in C suitable for a future in-console port;
  only the generated game assembly becomes customasm-only.

## Capabilities

### New Capabilities

- `inlay-namespaces`: Namespace declarations, nested qualified names,
  visibility, lookup, collision rules and deterministic target spelling.
- `celeste-inlay-native-redesign`: The module architecture, custom-CPU
  adoption, compatibility-symbol removal and regression requirements for the
  redesigned Celeste program.

### Modified Capabilities

- `layout-aware-assembly`: Add typed offset values, word field operations,
  typed read-modify-write operations and indexed fixed-overlay lowering.
- `celeste-layout-aware-build`: Replace the production byte-equivalence
  contract with a recorded Phase-A baseline plus behavioral and resource
  acceptance gates for the customasm-only Phase-B image.

## Impact

The Inlay parser, semantic records, target-operation boundary, customasm host
emitter, limits, diagnostics and conformance fixtures change. Most files under
`src/celeste/` are reorganized or rewritten, and Celeste build/test targets
gain custom-op and behavioral/resource gates. The historical direct-customasm
corpus and Phase-A digest remain immutable baselines, but no longer prescribe
Phase-B bytes.

The portable C frontend and its cc65 compilation smoke test remain required.
The ca65 assembly-equivalence fixture remains useful for architecture-neutral
frontend subsets, but ca65 is not a supported assembler for the redesigned
Celeste output.
