## Context

The layout-aware assembler has reached the point where its implementation
shorthand, `laasm`, appears in commands, source suffixes, generated paths,
documentation and tests. Leaving those names in place would turn an accidental
codename into a public interface.

This change assigns the product name **Inlay Assembly**, shortened to
**Inlay**, and the description “Structured assembly, close to the metal.” It
changes public naming without changing the language, target description,
source-map schema, portable semantic core, generated instruction stream or
machine bytes.

The current implementation also exposes `la_` C identifiers and `__la_`
generated private symbols. Those are internal namespaces, not product names.
Renaming them would create ABI and fixture churn without helping users, so they
remain stable.

## Goals / Non-Goals

**Goals:**

- Establish one canonical public identity: Inlay Assembly, `inlay`, and
  `.inlay.asm`.
- Migrate repository-owned sources, generated paths, documentation, examples,
  tests and build labels to the canonical identity.
- Give existing `laasm` command users and `.la.asm` sources a deliberate,
  testable compatibility path.
- Preserve output formats, semantic behavior, deterministic lowering and ROM
  bytes across the rename.
- Make removal of compatibility names an explicit future decision.

**Non-Goals:**

- Changing Inlay syntax, semantics, layout rules, target descriptions or
  source-map schemas.
- Renaming the `la_` portable C API or `__la_` private generated symbols.
- Bumping language, target or source-map format versions.
- Removing legacy names in this change.
- Introducing a package manager, installer or new distribution mechanism.

## Decisions

### 1. Treat Inlay as a complete public naming contract

The formal language name is **Inlay Assembly** and prose may use **Inlay**.
The canonical executable is `inlay`, canonical source files end in
`.inlay.asm`, and user-facing help/version output identifies the tool as
Inlay. The tagline is “Structured assembly, close to the metal.”

Generated Celeste frontend artifacts move from `build/layout_aware/` to
`build/inlay/`. Generated Inlay sources use `.inlay.asm`; emitted customasm
continues to use `.asm`, and map files continue to use `.map.json`.

This is preferable to renaming only the binary because a partial rename would
leave users guessing whether `laasm`, “layout-aware assembly,” and Inlay are
different systems.

### 2. Make `inlay` canonical while keeping an observable compatibility command

The implementation is built as `build/inlay/inlay`. A generated compatibility
launcher remains available at `build/laasm/laasm`; it emits a concise
deprecation diagnostic to stderr and then runs the canonical command with the
same arguments.

The compatibility launcher must preserve exit status, signals, stdout and
generated files. In particular, diagnostics must never contaminate
machine-readable stdout such as `--stats`.

A launcher is used instead of teaching the semantic core about executable
names. It keeps compatibility policy at the host boundary and leaves the
portable library unchanged.

### 3. Accept both source suffixes without changing language semantics

`.inlay.asm` is canonical in documentation, generated sources, fixtures and
repository-owned modules. `.la.asm` remains accepted anywhere a source or
module path is accepted.

Suffixes are naming conventions rather than syntax modes: the frontend does not
infer different behavior from either suffix and does not rewrite requested
module names. A resolver still receives the exact logical name written by the
source. The legacy suffix remains supported until a separate OpenSpec change
removes it.

### 4. Preserve internal namespaces and serialized formats

The portable C API keeps the `la_` prefix, generated private symbols keep
`__la_`, and the existing language, target and source-map format versions do
not change. These identifiers and versions describe programmatic compatibility
rather than marketing.

Human-facing banners and generated comments may change from `laasm` to Inlay.
Source-map source names may reflect renamed `.inlay.asm` files. Those textual
changes are permitted, but semantic events, addresses, emitted instructions
and final ROM bytes must remain equivalent.

### 5. Verify the rename at public and artifact boundaries

Black-box tests cover canonical and compatibility commands, help/version text,
stderr deprecation behavior, clean JSON stdout, both suffixes and identical
exit behavior. Existing differential and golden tests continue to cover the
portable core. The Celeste build records byte identity before and after the
rename.

Repository searches are used as a migration gate. Remaining `laasm`,
`layout-aware assembly`, and `.la.asm` occurrences must be either the
compatibility implementation, historical migration notes, or explicitly
allowlisted internal identifiers.

## Risks / Trade-offs

- **Existing scripts may parse the old version banner.** The compatibility
  command warns on stderr, while structured stdout contracts remain unchanged.
  Human-readable version branding is intentionally allowed to change.
- **Two names can prolong migration.** Documentation and generated output use
  only Inlay; the old command is visibly deprecated, and its removal requires a
  separate reviewed change.
- **Renamed paths can leave stale artifacts.** Clean-build tests and explicit
  generated-path assertions prevent the old and new trees from being mixed.
- **Text output is not byte-for-byte identical.** Equivalence is defined at the
  semantic event, emitted instruction and ROM-byte boundaries; branding
  comments and logical source names may differ.
- **A shell launcher adds a host dependency.** The compatibility path is host
  tooling only, uses the repository's existing POSIX build environment, and
  executes the same canonical binary.

## Migration Plan

1. Add the canonical `inlay` build output and compatibility `laasm` launcher,
   then add black-box contract tests for both.
2. Rename repository-owned tool paths, sources, fixtures, modules,
   documentation and generated Celeste paths to Inlay.
3. Update build targets and measurements while retaining explicit aliases for
   established legacy entry points.
4. Run portable-core, module, source-map, CLI and Celeste equivalence tests,
   followed by a repository naming audit.
5. Remove the compatibility command and `.la.asm` acceptance only through a
   later OpenSpec change. Rolling back this change restores the old canonical
   paths while the unchanged core and formats keep generated programs
   compatible.

## Open Questions

None. The public name, command, suffix, compatibility boundary and preserved
internal prefixes are fixed by this change.
