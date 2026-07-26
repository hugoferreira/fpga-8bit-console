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

#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"

#bankdef conformance { #addr 0x0400, #size 0x0100, #outp 0 }
#bank conformance

pObj = 0x10

player_init:
    lda #0
    sta [pObj + CelesteObject.speed_x.fraction]
    sta [pObj + CelesteObject.speed_x.integer]
    lda #0xF9
    sta [pObj + CelesteObject.hitbox.x]
    sta [pObj + CelesteObject.hitbox.y]
    lda #6
    sta [pObj + CelesteObject.hitbox.w]
    sta [pObj + CelesteObject.hitbox.h]
    lda #1
    sta [pObj + CelesteObject.dash_jumps]
    lda #3
    sta [pObj + CelesteObject.sprite]
    lda [pObj + CelesteObject.state]
    rts
