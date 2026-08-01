## Frozen pre-change baseline

Captured on 2026-07-27 from the accepted Phase-B image before the semantic
memory-map migration.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `build/celeste.bin` | 65,536 | `e57a8ea4112c6f16086d6a618254214c453d464d4de9ce19bfa03ac608f53da6` |
| `build/celeste.sym` | — | `d2f6ad71aa5740081afc15084ec08c4c6749e2dff9a7124611926e3da339c117` |
| `build/celeste.lbl` | — | `29015032ee036fb4b83734c54470ae6c925622b492db45ef52585cdfa63dcec3` |
| `build/inlay/celeste.map.json` | 348,071 | `c3b1224f4213c68be5b4888109af4ffc715e10829297233cffd8c7119dbba552` |
| `build/inlay/celeste.asm` | 113,565 | `d862aa25c9483336c7cd5cee3201a4c5a34dab59265f49c032dd57d024058c49` |

The frontend reports 65,318 flattened semantic-source bytes, 3,519 semantic
lines, a maximum include depth of 2 and 117,848 bytes of module workspace.
Physical `src/celeste/*.inlay.asm` source totals 165,353 bytes.

| Semantic table | High-water |
| --- | ---: |
| name bytes | 5,201 |
| tokens | 329 |
| structs / unions / fields | 18 / 1 / 155 |
| enums / members | 2 / 8 |
| overlays | 9 |
| namespaces / exports | 14 / 88 |
| constants / labels | 60 / 72 |
| locations / pools | 84 / 1 |
| procedures / parameters / locals | 70 / 82 / 1 |
| operations | 407 |
| compiler workspace | 158,296 bytes |

Per-module physical byte counts are retained by
`tools/inlay/check_celeste_memmap_migration.py`; the compatibility module was
8,804 bytes at the freeze point.
