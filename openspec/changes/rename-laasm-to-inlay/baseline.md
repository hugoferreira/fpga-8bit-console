## Pre-rename baseline

Recorded on 2026-07-26 before moving or editing the `laasm` implementation.

### Serialized formats

- Frontend version: `0.2`
- Language format: `1`
- Target format: `1`
- Source-map format: `2`
- Statistics format: `1`

### Celeste translation statistics

```json
{
  "format": 1,
  "sourceBytes": 42467,
  "nameBytes": 377,
  "tokens": 76,
  "structures": 4,
  "fields": 36,
  "locations": 4,
  "pools": 1,
  "procedures": 1,
  "parameters": 2,
  "locals": 0,
  "invokeBindings": 0,
  "expressionNodes": 3,
  "nesting": 2,
  "operations": 69,
  "workspaceBytes": 110488,
  "moduleBytes": 42467,
  "moduleLines": 3015,
  "moduleDepth": 3,
  "moduleWorkspaceBytes": 117848
}
```

### Celeste artifacts

- `build/celeste.bin`: 65,536 bytes, SHA-256
  `d85795e3daa7f1fbea0cef869efd554871f316c6196586dac3938e6340ae011a`
- `rtl/ram.hex`: 196,608 bytes, SHA-256
  `eb564afd5a180bb199414183066c4b5afce5d5d50050d28389c3f056578bccc0`
- Generated pre-rename customasm: SHA-256
  `18ea5ba8338eb250c5d8fa00644c460de2f9a34fb47b398fc943229713e34bb7`
- Generated pre-rename source map: SHA-256
  `94abb5d7c92895e45a78e0811d43abf9e1763c297ef7d968d29a51744e56f6ff`

The pre-rename conformance suite reported 9 fixture operations, 110,488
workspace bytes and the same 65,536-byte Celeste ROM hash above.
