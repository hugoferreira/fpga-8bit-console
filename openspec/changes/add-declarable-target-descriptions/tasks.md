## 1. Description structure and digest harness

- [ ] 1.1 Define the description structure (machine facts, registers
      and roles, conventions, scratch, operation entries, frame model,
      strategies) and its bounded loading into the existing workspace
      model, with limits and stable diagnostic codes
- [ ] 1.2 Build the digest-identity harness: a forced Celeste build
      compared against the recorded pre-migration digest, wired into
      conformance so every later phase is gated on byte neutrality
- [ ] 1.3 Author the console6502 description skeleton carrying the
      facts `LaTarget` already declares (byte order, pointer units,
      displacement window, conventions, scratch prefix and units,
      capability set)

## 2. Registers, roles, conventions, scratch

- [ ] 2.1 Move register names and roles into the description; replace
      `la_slice_is_register` and every core register-name comparison
      with description lookups
- [ ] 2.2 Move the omitted-placement convention walk and scratch
      naming into description data; digest gate

## 3. Operation spellings and constraints

- [ ] 3.1 Replace the parser's hardcoded mnemonic dispatch with a
      spelling table from the description; unclaimed spellings fall
      through to raw
- [ ] 3.2 Express each operation's operand constraints (width, range,
      stride set, volatility) as declared predicates from the bounded
      vocabulary; identical diagnostics; digest gate

## 4. Lowering templates and contracts

- [ ] 4.1 Implement the template interpreter (slots, byte slices,
      parameter arithmetic, fresh labels, per-line conditionals) and
      move every typed-operation emitter case into console6502
      templates with declared clobber/flag contracts
- [ ] 4.2 Port the structured lowering references to key off
      description entries; digest gate

## 5. Frame model

- [ ] 5.1 Move prologue, epilogue, member-access and pointer-copy
      sequences into frame templates parameterized by size and offset;
      digest gate

## 6. Planner generalization

- [ ] 6.1 Derive marshalling order from dependency scheduling over
      declared defs and clobbers (memory reads clobber the accumulator
      role); verify the scheduler reproduces the current console6502
      order over the full corpus before enabling; digest gate

## 7. Strategies

- [ ] 7.1 Re-cut dispatch entries as one operation with a declared
      strategy (split low/high vs word-per-entry); keep the
      console6502 split strategy and all current surfaces; digest gate
- [ ] 7.2 Move `pool tables` emission to a declared strategy with the
      symbolic `(BASE+offset)` console6502 form; digest gate

## 8. Cross-check and close-out

- [ ] 8.1 Cross-validate description templates against the canonical
      ISA description: an emitted mnemonic the ISA description does
      not define fails the build
- [ ] 8.2 Sweep the core for residual target-named knowledge; document
      the description format in docs/inlay.md; final double
      forced-build determinism and digest check; strict OpenSpec
      validation
