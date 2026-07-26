; Inlay Celeste entry point.
;
; The generated compatibility aliases below make this layout authoritative for
; the existing Celeste sources while those sources remain readable as ordinary
; customasm. The build supplies celeste_body.asm and celeste_memmap.asm beside
; the translated output; they contain the unmodified game body and memory map
; with only the former O_* definition block removed.

struct Fixed8_8 packed
    fraction : u8
    integer : i8
end

struct Hitbox packed
    x : i8
    y : i8
    w : u8
    h : u8
end

struct HairNode packed
    x : Fixed8_8
    y : Fixed8_8
end

struct CelesteObject packed
    kind : u8
    sprite : u8
    x : i8
    y : i8
    speed_x : Fixed8_8
    speed_y : Fixed8_8
    remainder_x : Fixed8_8
    remainder_y : Fixed8_8
    hitbox : Hitbox
    flip : u8
    flags : u8
    state : u8
    delay : u8
    dash_jumps : u8
    grace : u8
    jump_buffer : u8
    dash_time : u8
    dash_effect : u8
    player_bits : u8
    sprite_offset : u8
    dash_target_x : Fixed8_8
    dash_target_y : Fixed8_8
    dash_accel_x : Fixed8_8
    dash_accel_y : Fixed8_8
    target_x : i8
    target_y : i8
    hair : HairNode[5]
    reserved : u8[7]
end

static_assert CelesteObject.size == 64
static_assert CelesteObject.hitbox.x.offset == 12
static_assert CelesteObject.hitbox.y.offset == 13
static_assert CelesteObject.hitbox.w.offset == 14
static_assert CelesteObject.hitbox.h.offset == 15
static_assert CelesteObject.hair.offset == 37
static_assert CelesteObject.hair.count == 5
static_assert CelesteObject.hair.stride == 4

location pObj : ptr CelesteObject
location pOth : ptr CelesteObject
pool objects : CelesteObject[16] at OBJPOOL table obj_lo, obj_hi

static_assert objects.count == 16
static_assert objects.stride == 64
static_assert objects.size == 1024

#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"
#include "../../src/isa/pseudo.asm"
#include "../../src/isa/memmap.asm"

O_TYPE = __la_13_CelesteObject__4_kind__offset
O_SPR = __la_13_CelesteObject__6_sprite__offset
O_X = __la_13_CelesteObject__1_x__offset
O_Y = __la_13_CelesteObject__1_y__offset
O_SPDX = __la_13_CelesteObject__7_speed_x__offset
O_SPDY = __la_13_CelesteObject__7_speed_y__offset
O_REMX = __la_13_CelesteObject__11_remainder_x__offset
O_REMY = __la_13_CelesteObject__11_remainder_y__offset
O_HBX = __la_13_CelesteObject__6_hitbox__1_x__offset
O_HBY = __la_13_CelesteObject__6_hitbox__1_y__offset
O_HBW = __la_13_CelesteObject__6_hitbox__1_w__offset
O_HBH = __la_13_CelesteObject__6_hitbox__1_h__offset
O_FLIP = __la_13_CelesteObject__4_flip__offset
O_FLAGS = __la_13_CelesteObject__5_flags__offset
O_STATE = __la_13_CelesteObject__5_state__offset
O_DELAY = __la_13_CelesteObject__5_delay__offset
O_DJUMP = __la_13_CelesteObject__10_dash_jumps__offset
O_GRACE = __la_13_CelesteObject__5_grace__offset
O_JBUF = __la_13_CelesteObject__11_jump_buffer__offset
O_DASHT = __la_13_CelesteObject__9_dash_time__offset
O_DASHE = __la_13_CelesteObject__11_dash_effect__offset
O_PBITS = __la_13_CelesteObject__11_player_bits__offset
O_SPROFF = __la_13_CelesteObject__13_sprite_offset__offset
O_DTX = __la_13_CelesteObject__13_dash_target_x__offset
O_DTY = __la_13_CelesteObject__13_dash_target_y__offset
O_DAX = __la_13_CelesteObject__12_dash_accel_x__offset
O_DAY = __la_13_CelesteObject__12_dash_accel_y__offset
O_TGTX = __la_13_CelesteObject__8_target_x__offset
O_TGTY = __la_13_CelesteObject__8_target_y__offset
O_HAIR = __la_13_CelesteObject__4_hair__offset
O_SIZE = __la_13_CelesteObject__size

include "modules/celeste_body.inlay.asm"
