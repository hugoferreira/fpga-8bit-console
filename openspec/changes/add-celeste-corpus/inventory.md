# Celeste Classic — systems inventory and hardware fit

Written before porting, from the cart's own Lua. Task 1.3 exists because the
nemo port found two assumptions in its own proposal that the source contradicted;
the same check is run here, and it found three.

## The cart

| | |
| --- | --- |
| Thread | `https://www.lexaloffle.com/bbs/?tid=2145` |
| Cart | `cposts/1/15133.p8.png`, "Celeste (Fixed for P8 v0.1.2)" |
| Authors | Matt Thorson and Noel Berry, posted by `noel` 2015-10-08 |
| Extracted | `tools/p8_unpack.py` → 26589 chars of Lua, 128 gfx rows, 63 sfx, 64 music patterns |
| Local copy | `~/Stuff/carts/celeste-15133.p8.png` (carts are not committed) |

The BBS thread is the "Fixed for P8 v0.1.2" revision, which is the one the
proposal anticipated.

## Systems, and where each one lands

| Cart system | Lines | Port |
| --- | --- | --- |
| `init_object` / `objects` / `types`, per-type `init`/`update`/`draw` | 959-1064 | object pool + dispatch (`obj.asm`) |
| `obj.move` → `move_x`/`move_y`, `rem` sub-pixel accumulation | 1010-1057 | 8.8 fixed point (`move.asm`) — **the word-ops idiom** |
| `is_solid`, `is_ice`, `solid_at`, `ice_at`, `tile_flag_at`, `tile_at` | 978-989, 1393-1414 | `collide.asm`, flag table indexed by tile id |
| `spikes_at` — four tile ids, each with its own edge and speed-sign test | 1416-1432 | `collide.asm` |
| `player` update: input, grace, jbuffer, djump, dash, wall jump, wall slide, ice accel, animation | 118-327 | `player.asm` |
| `player_spawn` 3-state entry animation | 361-413 | `player.asm` |
| `smoke` | 563-580 | `objects.asm` |
| `room_title` | 928-954 | overlay text |
| `load_room` scans 16x16 tiles and spawns by tile id | 1118-1151 | `room.asm` |
| `next_room` / `restart_room` / `level_index` | 1095-1116 | `room.asm` |
| `_update`: freeze, shake, delayed restart, foreach-update | 1156-1220 | `main.asm` |
| `_draw`: layered map draws (flags 4 / 2 / 8), object draw order | 1224-1348 | tile layer + sprite list |
| `appr`, `sign`, `clamp`, `maybe` | 1374-1391 | `math.asm` |
| clouds, particles, dead particles, hair | 74-96, 336-359 | see divergences |

### Stage 1 scope, as the proposal defines it

`player`, `player_spawn`, `smoke`, `room_title` — four types through the same
dispatch — plus collision, `move`, the object list, room load/transition and the
camera. The remaining eleven types (`spring`, `balloon`, `fall_floor`, `fruit`,
`fly_fruit`, `fake_wall`, `key`, `chest`, `platform`, `message`, `big_chest`,
`orb`, `flag`, `lifeup`) are stage 2.

## Findings that change the plan

### 1. The tilemap window is write-only, so the port needs its own `mget`

`sprite_compositor.sv` exposes the map as `map_cs` **write-only** at `$F000`
(pattern) and `$F200` (attributes). `tile_at` is called from `tile_flag_at`,
which the player calls up to six times per frame, so the room's 256 tile ids
have to live in RAM as well as in the map window. That is not a cost the
proposal accounted for, but it is small: one 256-byte array, written once per
`load_room`.

It also means `mget` is a plain indexed load rather than an MMIO read, which
makes `tile_flag_at`'s inner loop cheaper than the cart's — worth noting when
its idiom counts are read.

### 2. The HUD moves to the overlay, which frees the whole tile world

The proposal put the HUD in the 32 columns to the right of the 128-wide
playfield. That works, but it wastes the tile world: 32x16 cells = 256x128
pixels is **exactly two rooms**, and the room-transition slide wants both
resident at once. The overlay is screen-space, 160x120, and does not scroll with
the camera, so the HUD sits there instead and the tile layer carries only rooms.
Same conclusion breakout and nemo reached for their text, for a different reason.

### 3. Screen shake cannot be done with the camera alone

`camera(-2+rnd(5),-2+rnd(5))` shakes everything. The console's camera registers
(`$4003`/`$4004`) scroll **the tile layer only** — sprites are staged in screen
space and the overlay is composited above both. Shaking with the camera would
slide the terrain out from under the player.

Resolution: the shake offset is added to each sprite's staged X/Y as the list is
rebuilt, which happens every frame anyway, so it costs one add per sprite. The
overlay HUD stays still. Recorded as a divergence rather than a hardware gap:
the hardware can express it, the program just has to apply it in two places.

## Hardware fit

| Cart | Console | Fit |
| --- | --- | --- |
| 128x128 screen | 160x120 | 32 columns spare; **8 lines short** — camera Y follow, per the design |
| 16x16-tile room | 32x16-cell tile world | two rooms resident, as the design predicted |
| 16-colour palette | `rtl/palette888.bin` **is** the PICO-8 palette | 4bpp art with palette base 0 is pixel-exact |
| `pal(8,c)` hair recolour | 4-bit palette base per sprite entry | hair blob is 1bpp; base picks the colour |
| `fget(tile,flag)` | no attribute bits free in a map cell | CPU-side 256-byte flag table |
| `circfill`, `line`, `rectfill` | none | hair and dust become sprites; clouds/particles are stage 2 |

### Sprite sheet budget — the binding constraint

The sheet is 2KB: 256 slots of one 8x8 bitplane each, so a 4bpp tile costs 4
slots and there are **64 four-colour-plane patterns in total**, shared between
tiles and sprites. Measured over the three chosen rooms:

| | slots |
| --- | --- |
| 47 distinct terrain tiles, 4bpp | 188 |
| player, 7 frames, 4bpp (colours 0,1,3,7,8,15) | 28 |
| smoke, 3 frames, 1bpp (colour 7 only) | 3 |
| hair blobs, two radii, 1bpp | 2 |
| **total** | **221 / 256** |

Stage 1 fits. Stage 2 does not, and the lever is documented rather than taken:
most terrain tiles use three colours or fewer, so a 2bpp encoding at 2 slots per
tile halves the terrain cost — at the price of routing those tiles through the
draw palette, which the 4bpp player art needs to keep as identity for values
0,1,3,7,8,15. The other ten draw-palette entries are free, so the trick works;
it is just not needed yet.

## Stage-1 room selection (task 1.4)

Chosen for tile-flag variety, not progression order:

| Level | room | Why |
| --- | --- | --- |
| 0 | (0,0) | The game's actual first room and its entry point. Plain solid terrain, one spike orientation. Baseline. |
| 11 | (3,1) "old site" | The only substantial **ice** room in the game: 9 ice tiles against 19 solid, with ice adjacent to ordinary ground, so the ice-accel and wall-slide branches interact rather than being reachable in isolation. |
| 20 | (4,2) | **All four spike orientations** (17, 27, 43, 59) against only 9 solid tiles, so spike geometry is exercised where solid collision is not doing the work. |

Together: 47 distinct terrain tiles, 25 solid, 9 ice, all four spike
orientations. `player_spawn` is in all three.

**Divergence.** The cart's `next_room` walks the level index in order, so these
three are not neighbours. The port keeps a table of the resident rooms and cycles
through it, which preserves the transition machinery — load, slide, camera
reset — while letting the room set be chosen for what it measures. Level index
is still reported per room, so `room_title` shows the original's "1100 m".

## Fixed-point plan

The cart is PICO-8 16.16. The port uses **8.8 signed** — one integer byte, one
fraction byte — which covers every constant in the game:

| Cart | 8.8 | Cart | 8.8 |
| --- | --- | --- | --- |
| `maxrun` 1 | $0100 | `gravity` 0.21 | $0036 |
| `accel` 0.6 | $009A | `maxfall` 2 | $0200 |
| ground `deccel` 0.15 | $0026 | jump `spd.y` -2 | $FE00 |
| air `accel` 0.4 | $0066 | dash `d_full` 5 | $0500 |
| ice `accel` 0.05 | $000D | dash `d_half` 3.5355 | $0389 |
| wall-slide `maxfall` 0.4 | $0066 | `dash_accel` 1.5 | $0180 |

Speeds stay inside ±8 px/frame, so the integer byte never overflows. `move()`'s
`rem.x += spd.x; amount = flr(rem.x + 0.5); rem.x -= amount` becomes a literal
16-bit add, a rounding add of $0080, and a 16-bit subtract — three chains per
axis per object per frame. This is the pattern `add-isa-word-ops` could not find
in breakout, and it is not manufactured for the gate: it is what the original
does.

## Audio

63 of 64 SFX and 64 music patterns are present in the cart. The PSG takes a
verbatim cart audio image (nemo does this), so the sound in stage 1 costs a
`p8_audio.py` run plus the `psfx` call sites. Stage 1 wires only the sounds its
four types raise: death (0), jump (1), wall jump (2), dash (3), spawn (4, 5),
djump refill (54), and the title music.
