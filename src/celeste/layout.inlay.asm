; Celeste Classic's authoritative object and memory layouts.

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
    channel_rows : u8[4] at 20
    channel_lengths : u8[4] at 24
    music : u8 at 32
    music_mask : u8 at 33
    fade : u8 at 34
end

; Fixed storage regions. Several views intentionally overlap: game is the
; persistent-state portion of zero_page, while overlay_shadow mirrors the
; write-only framebuffer.
struct TileMap packed
    patterns : u8[512]
    attributes : u8[512]
end

struct OverlayFramebuffer packed
    pixels : u8[2400]
end

struct RoomTileBuffer packed
    cells : u8[256]
end

struct OverlayRowPointers
    low : u8[120] at 0
    high : u8[120] at 128
end

struct ZeroPageWorking
    scratch : u8[8] at 0
    words : u16[3] at 8
    object_pointer : u16 at 16
    other_pointer : u16 at 18
    function_pointer : u16 at 20
    overlay_pointer : u16 at 22
    source_pointer : u16 at 24
    destination_pointer : u16 at 26
    object_slot : u8 at 28
    object_free : u8 at 29
    spawn_type : u8 at 30
    spawn_x : u8 at 31
    spawn_y : u8 at 32
    spawn_slot : u8 at 33
    collision_x : u8 at 34
    collision_y : u8 at 35
    collision_w : u8 at 36
    collision_h : u8 at 37
    collision_mask : u8 at 38
    collision_offset_x : i8 at 39
    collision_offset_y : i8 at 40
    collision_type : u8 at 41
    collision_hit : u8 at 42
    collision_i : u8 at 43
    collision_j : u8 at 44
    collision_i1 : u8 at 45
    collision_j1 : u8 at 46
    game_state : u8[30] at 48
    player_scratch : u8[16] at 80
    drawing_scratch : u8[18] at 96
end

struct GameState
    frames : u8 at 0
    seconds : u8 at 1
    minutes : u8 at 2
    deaths : u8 at 3
    max_dash_jumps : u8 at 4
    freeze : u8 at 5
    shake : u8 at 6
    shake_x : i8 at 7
    shake_y : i8 at 8
    will_restart : u8 at 9
    restart_delay : u8 at 10
    room_slot : u8 at 11
    room_bank : u8 at 12
    level : u8 at 13
    camera_y : u8 at 14
    buttons : u8 at 16
    previous_buttons : u8 at 17
    pressed_buttons : u8 at 18
    sfx_timer : u8 at 19
    music_timer : u8 at 20
    has_dashed : u8 at 21
    pause_player : u8 at 22
    sprite_count : u8 at 23
    overlay_dirty : u8 at 24
    hud_seconds : u8 at 25
    next_channel : u8 at 26
    room_load_index : u8 at 27
    start_game : u8 at 28
    start_game_flash : i8 at 29
end

overlay video : VideoRegisters at $4000 volatile
overlay psg : PsgRegisters at $4100 volatile
overlay framebuffer : OverlayFramebuffer at $e000 volatile
overlay tile_map : TileMap at $f000
overlay zero_page : ZeroPageWorking at $0000
overlay game : GameState at $0030
overlay room_tiles : RoomTileBuffer at $5400
overlay overlay_rows : OverlayRowPointers at $5500
overlay overlay_shadow : OverlayFramebuffer at $6000

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
static_assert PsgRegisters.channel_rows.offset == 20
static_assert PsgRegisters.channel_lengths.offset == 24
static_assert PsgRegisters.music.offset == 32
static_assert PsgRegisters.size == 35
static_assert TileMap.patterns.offset == 0
static_assert TileMap.attributes.offset == 512
static_assert TileMap.size == 1024
static_assert OverlayFramebuffer.size == 2400
static_assert RoomTileBuffer.size == 256
static_assert OverlayRowPointers.high.offset == 128
static_assert OverlayRowPointers.size == 248
static_assert ZeroPageWorking.object_pointer.offset == $10
static_assert ZeroPageWorking.game_state.offset == $30
static_assert ZeroPageWorking.player_scratch.offset == $50
static_assert ZeroPageWorking.drawing_scratch.offset == $60
static_assert ZeroPageWorking.size == $72
static_assert GameState.buttons.offset == $10
static_assert GameState.start_game_flash.offset == $1d
static_assert GameState.size == $1e
static_assert $4000 + VideoRegisters.draw_palette.offset == $4010
static_assert $4000 + VideoRegisters.screen_palette.offset == $4020
static_assert $4000 + VideoRegisters.clip_x0.offset == $4030
static_assert $4000 + VideoRegisters.repeat.offset == $4037
static_assert $4100 + PsgRegisters.channels.offset == $4110
static_assert $4100 + PsgRegisters.channel_rows.offset == $4114
static_assert $4100 + PsgRegisters.channel_lengths.offset == $4118
static_assert $4100 + PsgRegisters.music.offset == $4120
static_assert $0030 + GameState.frames.offset == $0030
static_assert $0030 + GameState.camera_y.offset == $003e
static_assert $0030 + GameState.buttons.offset == $0040
static_assert $0030 + GameState.start_game_flash.offset == $004d

location pObj : ptr CelesteObject
location pOth : ptr CelesteObject
pool objects : CelesteObject[16] at OBJPOOL table obj_lo, obj_hi

static_assert objects.count == 16
static_assert objects.stride == 64
static_assert objects.size == 1024
