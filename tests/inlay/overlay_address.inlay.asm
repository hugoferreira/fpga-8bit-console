struct TileMap packed
    patterns : u8[512]
    attributes : u8[512]
end

struct HeaderView
    kind : u8 at 0
    flags : u8 at 17
end

struct GameState
    frames : u8 at 0
    flags : u8 at 9
end

location destination : u16 at $1a
location cursor : ptr TileMap at $10

overlay tile_map : TileMap at TILE_RAM
overlay header : HeaderView at OBJECT_RAM
overlay game : GameState at $0030
overlay video : HeaderView at $4000 volatile

static_assert TileMap.attributes.offset == 512
static_assert HeaderView.flags.offset == 17

#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"

#bankdef overlay_address { #addr 0x0400, #size 0x0100, #outp 0 }
#bank overlay_address

start:
    address destination, tile_map.patterns
    address destination, tile_map.attributes
    address cursor, header.flags
    inc [game + GameState.frames]
    dec [game + GameState.frames]
    and [game + GameState.flags], #$fe
    ora [game + GameState.flags], #1
    cmp [video + HeaderView.flags]
    rts

TILE_RAM = $f000
OBJECT_RAM = $8000
