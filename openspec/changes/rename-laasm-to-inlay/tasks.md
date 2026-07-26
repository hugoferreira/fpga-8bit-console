## 1. Establish Rename Baselines

- [x] 1.1 Record the current language, target and source-map format versions
  and the Celeste semantic counts, emitted instruction stream and ROM hashes
  used to prove rename equivalence.
- [x] 1.2 Add black-box tests for the canonical `inlay` identity, exact tagline,
  help/version branding, `.inlay.asm` input and unchanged format versions.
- [x] 1.3 Add compatibility contract tests for `laasm`, including stderr-only
  deprecation, clean JSON stdout, forwarded failures and matching exit status.

## 2. Rename the Host Tool

- [x] 2.1 Move the tool's public source and test paths from `tools/laasm/` to
  `tools/inlay/`, updating includes and build references while preserving the
  portable `la_` C API and `__la_` generated-symbol namespace.
- [x] 2.2 Update host help, version output, diagnostics and generated branding
  comments to identify Inlay Assembly and use “Structured assembly, close to
  the metal.”
- [x] 2.3 Build the canonical host executable as `build/inlay/inlay` and add the
  `build/laasm/laasm` compatibility launcher that emits its deprecation only to
  stderr and faithfully executes `inlay`.
- [x] 2.4 Run the portable-core, host, CLI, source-map and strict C99/C++11
  suites through the renamed tool paths and fix any path-dependent failures.

## 3. Migrate Sources and Modules

- [x] 3.1 Rename repository-owned layout-aware entries, examples and fixtures
  from `.la.asm` to `.inlay.asm` and update every corresponding include,
  expected logical source name and test invocation.
- [x] 3.2 Update the host file adapter and module tests to accept both suffixes,
  preserve exact resolver names and prove suffix-only graph renames retain
  semantic events, instructions and source-map addresses.
- [x] 3.3 Verify legacy `.la.asm` entry and module graphs still translate
  successfully without selecting a different parser or lowering mode.

## 4. Migrate Build Integration

- [x] 4.1 After checking `docs/agent-coordination.md`, update the shared
  Makefile using its append-only protocol so canonical build variables, rules
  and dependencies use `inlay` and `build/inlay/` while intentional legacy
  aliases remain available.
- [x] 4.2 Update the Celeste frontend preparation to create
  `build/inlay/celeste.inlay.asm`, `.inlay.asm` modules,
  `build/inlay/celeste.asm` and the corresponding source map, and invoke the
  canonical `inlay` executable.
- [x] 4.3 Update measurements, CI commands and test labels from layout-aware or
  `laasm` product naming to Inlay without renaming the preserved internal
  namespaces or changing measurement definitions.
- [x] 4.4 Update repository documentation, examples and OpenSpec cross-
  references to use Inlay Assembly, `inlay` and `.inlay.asm`, documenting
  `laasm` and `.la.asm` only in the compatibility section.

## 5. Prove Compatibility and Equivalence

- [x] 5.1 Compare pre-rename and Inlay golden cases to confirm equivalent
  semantic events, instructions and maps apart from branding comments and
  renamed logical source strings.
- [x] 5.2 Build Celeste from a clean tree and confirm its binary and hexadecimal
  ROM payloads are byte-identical to the recorded baseline and all recorded
  semantic and size measurements are unchanged.
- [x] 5.3 Run the full repository test and metrics suites and verify established
  legacy make/CLI entry points still behave as documented.
- [x] 5.4 Audit repository occurrences of `laasm`, “layout-aware assembly” and
  `.la.asm`; reduce them to the compatibility implementation, historical
  migration material and explicitly documented `la_`/`__la_` internals.
