## 1. Public Model and Bounds

- [x] 1.1 Add bounded procedure, parameter, local and pool capacities to the
  portable API and workspace calculation.
- [x] 1.2 Add structured indexed, pool-address, procedure and frame-local
  events plus stable diagnostics.
- [x] 1.3 Preserve compatibility for existing direct operands and callers.

## 2. Indexed Operands

- [x] 2.1 Parse exactly one physical index on an array path component.
- [x] 2.2 Resolve constant displacement, array count, stride and byte leaf.
- [x] 2.3 Lower console6502 indexed loads and stores for strides 1, 2, 4 and 8
  with documented A/X/Y/stack effects.
- [x] 2.4 Test valid nested indexes and scalar, repeated-index, width, physical
  index and stride failures under strict C89.

## 3. Pools and Addresses

- [x] 3.1 Parse fixed typed pool declarations and expose count, stride and size.
- [x] 3.2 Parse typed pool-element address materialisation with physical source
  and destination locations.
- [x] 3.3 Lower the explicit console6502 low/high table strategy.
- [x] 3.4 Test pool capacity, layout, strategy, type and operand diagnostics.

## 4. Procedures and Frames

- [x] 4.1 Parse scoped procedures with default `frame`, explicit `naked`,
  physical parameters, `begin`, `end` and semantic `ret`.
- [x] 4.2 Resolve pointer parameter aliases only within their procedure.
- [x] 4.3 Lay out bounded scalar locals and reject locals in naked procedures.
- [x] 4.4 Lower console6502 frame allocation, local byte access and balanced
  epilogues while preserving A.
- [x] 4.5 Reject raw stack mutation and raw frame-bypassing returns when locals
  are active.
- [x] 4.6 Test scope, aliases, frame elision, naked mode, locals, balance,
  capacity and malformed procedure diagnostics.

## 5. Celeste Build-only Migration

- [x] 5.1 Declare the fixed Celeste object pool and its existing table strategy.
- [x] 5.2 Express generated `obj_ptr` as a procedure and typed pool address
  operation with an exact migration count.
- [x] 5.3 Add representative Celeste-shaped indexed field syntax to the
  focused generated fixture without changing owned Celeste sources or runtime
  bytes.

## 6. Equivalence and Integration

- [x] 6.1 Compare focused indexed, pool, frame and naked output with handwritten
  customasm byte for byte.
- [x] 6.2 Compare all 65,536 bytes of direct and structured Celeste ROMs.
- [x] 6.3 Run `make GAME=celeste hex`, `make test-celeste`,
  `make test-layout-asm`, `make test-ext` and `make test`.
- [x] 6.4 Compile and assemble the expanded portable core with cc65/ca65.
- [x] 6.5 Update language and corpus documentation with syntax, lowering,
  clobbers, limits and measured usage.
- [x] 6.6 Strictly validate the OpenSpec change and audit that no owned Celeste,
  ISA, RTL, memory-map or simulator source changed.
