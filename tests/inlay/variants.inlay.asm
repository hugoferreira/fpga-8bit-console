enum ObjectKind : u8
    player = 1
    actor = ObjectKind.player
    balloon = 2
end

enum SignedEdge : i8
    minimum = -128
    maximum = 127
end

struct Pair
    lo : u8
    hi : u8
end

struct ExplicitPair packed
    lo : u8
    hi : u8
end

struct HeaderView
    kind : ObjectKind at 0
    flags : u8 at 17
end

struct MotionView
    x : i8 at 2
    y : i8 at 3
    vx : i8 at 6
    vy : i8 at 7
end

struct AlignedShape aligned(4)
    a : u8
    b : u16
    c : u8
end

union ObjectPayload
    byte : u8
    pair : Pair
end

union RoundedPayload aligned(4)
    bytes : u8[5]
    pair : Pair
end

struct ObjectView
    kind : ObjectKind
    payload : ObjectPayload
end

overlay header : HeaderView at OBJECT_RAM
overlay motion : MotionView at OBJECT_RAM
overlay object : ObjectView at OBJECT_RAM

static_assert ObjectKind.player == 1
static_assert ObjectKind.actor == ObjectKind.player
static_assert SignedEdge.minimum == -128
static_assert Pair.size == ExplicitPair.size
static_assert Pair.align == ExplicitPair.align
static_assert HeaderView.kind.offset == 0
static_assert HeaderView.flags.offset == 17
static_assert HeaderView.size == 18
static_assert MotionView.x.offset == 2
static_assert MotionView.vy.offset == 7
static_assert MotionView.size == 8
static_assert AlignedShape.a.offset == 0
static_assert AlignedShape.b.offset == 2
static_assert AlignedShape.c.offset == 4
static_assert AlignedShape.size == 8
static_assert AlignedShape.align == 4
static_assert ObjectPayload.byte.offset == 0
static_assert ObjectPayload.pair.hi.offset == 1
static_assert ObjectPayload.size == 2
static_assert RoundedPayload.size == 8
static_assert RoundedPayload.align == 4
static_assert ObjectView.payload.pair.hi.offset == 2

#include "../../src/isa/nmos6502.asm"

#bankdef variants { #addr 0x0400, #size 0x0100, #outp 0 }
#bank variants

start:
    lda [header + HeaderView.kind]
    sta [motion + MotionView.vy]
    lda [object + ObjectView.payload.pair.hi]
    rts

OBJECT_RAM = $8000
