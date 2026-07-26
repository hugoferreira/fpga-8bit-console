## Why

The layout-aware assembly language and its host tool are currently identified
only by the implementation shorthand `laasm`, which is difficult to say,
remember, or present as a language. Naming the language now prevents the
temporary codename, executable name, and `.la.asm` suffix from becoming
permanent public contracts through further adoption.

## What Changes

- Name the language **Inlay Assembly**, with **Inlay** as the short form and
  “Structured assembly, close to the metal.” as its descriptive tagline.
- Make `inlay` the canonical host command and `.inlay.asm` the canonical source
  suffix.
- Rename user-visible generated paths, diagnostics, version output,
  documentation, examples, measurements, build variables and test labels from
  `laasm` or “layout-aware assembly” to Inlay where they identify the product.
- Preserve the existing language format, target format, source-map format,
  syntax, semantics and generated machine bytes.
- Keep `laasm` as a temporary compatibility command that forwards to `inlay`
  with a deprecation diagnostic; existing `.la.asm` inputs remain accepted
  during the same compatibility period.
- Retain `la_` on the portable C API and generated private symbols because it
  is an internal ABI prefix rather than the public language name.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `layout-aware-assembly`: Establish the canonical Inlay language, command,
  source suffix, version output and compatibility contract.
- `layout-aware-modules`: Establish `.inlay.asm` as the canonical module-name
  suffix while accepting legacy `.la.asm` module names during migration.
- `celeste-layout-aware-build`: Rename the generated Celeste Inlay entry,
  modules, paths and build-facing labels without changing its ROM.

## Impact

The implementation will affect `tools/laasm/`, its eventual renamed tool
directory or compatibility wrapper, layout source and fixtures, generated build
paths, Makefile variables and targets, layout-aware documentation, OpenSpec
requirements, and Celeste frontend preparation. Tests must prove command
compatibility, deterministic source maps, strict portability and byte-identical
Celeste output throughout the rename.
