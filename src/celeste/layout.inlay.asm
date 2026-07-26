; Celeste Classic's authoritative object layout.
;
; Compatibility O_* names below are derived from this layout for
; target-specific indexed sequences that cannot yet be replaced without
; changing their instruction bytes.

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

enum ObjectKind : u8
    free = 0
    player = 1
    spawn = 2
    smoke = 3
    title = 4
end

enum SpawnPhase : u8
    rising = 0
    falling = 1
    landing = 2
end

struct ObjectCore packed
    kind : ObjectKind
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
end

struct PlayerPayload packed
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

struct SpawnPayload packed
    phase : SpawnPhase at 0
    delay : u8 at 1
    target_x : i8 at 17
    target_y : i8 at 18
    hair : HairNode[5] at 19
    reserved : u8[7] at 39
end

struct SmokePayload packed
    sprite_offset : u8 at 8
    reserved : u8 at 45
end

struct TitlePayload packed
    delay : i8 at 1
    reserved : u8 at 45
end

struct HairPayload packed
    hair : HairNode[5] at 19
    reserved : u8[7] at 39
end

union ObjectPayload
    player : PlayerPayload
    spawn : SpawnPayload
    smoke : SmokePayload
    title : TitlePayload
    hair : HairPayload
    raw : u8[46]
end

struct CelesteObject packed
    core : ObjectCore
    payload : ObjectPayload
end

; The console's memory-mapped video window. Explicit offsets retain the
; hardware gaps and the overlapping functional regions exactly as wired.
struct VideoRegisters
    sheet_address_low : u8 at 0
    sheet_address_high : u8 at 1
    sheet_data : u8 at 2
    camera_x : u8 at 3
    camera_y : u8 at 4
    control : u8 at 5
    overlay_color : u8 at 6
    buttons : u8 at 7
    sprite_index : u8 at 8
    sprite_x : u8 at 9
    sprite_y : u8 at 10
    sprite_flags : u8 at 11
    sprite_count : u8 at 12
    frame : u8 at 13
    sprite_base : u8 at 14
    random : u8 at 15
    draw_palette : u8[16] at 16
    screen_palette : u8[16] at 32
    clip_x0 : u8 at 48
    clip_y0 : u8 at 49
    clip_x1 : u8 at 50
    clip_y1 : u8 at 51
    split : u8 at 54
    repeat : u8 at 55
end

; The PSG is sparse: the upload/status registers, channel command bank and
; music controls are distinct views within one fixed register window.
struct PsgRegisters
    address_low : u8 at 0
    address_high : u8 at 1
    data : u8 at 2
    status : u8 at 3
    channels : u8[4] at 16
    music : u8 at 32
    music_mask : u8 at 33
    fade : u8 at 34
end

overlay video : VideoRegisters at SPR_SHADDR_LO
overlay psg : PsgRegisters at PSG_ADDR_LO

static_assert CelesteObject.size == 64
static_assert ObjectCore.size == 18
static_assert ObjectPayload.size == 46
static_assert CelesteObject.core.hitbox.x.offset == 12
static_assert CelesteObject.core.hitbox.y.offset == 13
static_assert CelesteObject.core.hitbox.w.offset == 14
static_assert CelesteObject.core.hitbox.h.offset == 15
static_assert CelesteObject.payload.player.dash_jumps.offset == 20
static_assert CelesteObject.payload.spawn.target_y.offset == 36
static_assert CelesteObject.payload.smoke.sprite_offset.offset == 26
static_assert CelesteObject.payload.title.delay.offset == 19
static_assert CelesteObject.payload.hair.hair.offset == 37
static_assert CelesteObject.payload.hair.hair.count == 5
static_assert CelesteObject.payload.hair.hair.stride == 4
static_assert VideoRegisters.random.offset == 15
static_assert VideoRegisters.split.offset == 54
static_assert VideoRegisters.size == 56
static_assert PsgRegisters.channels.offset == 16
static_assert PsgRegisters.music.offset == 32
static_assert PsgRegisters.size == 35

location pObj : ptr CelesteObject
location pOth : ptr CelesteObject
pool objects : CelesteObject[16] at OBJPOOL table obj_lo, obj_hi

static_assert objects.count == 16
static_assert objects.stride == 64
static_assert objects.size == 1024
