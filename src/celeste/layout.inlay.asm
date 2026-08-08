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
    spring = 5
    balloon = 6
    fall_floor = 7
    fruit = 8
    fly_fruit = 9
    lifeup = 10
    fake_wall = 11
    key = 12
    chest = 13
    platform = 14
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

; Stage-2 objects use disjoint interpretations of the same compact state slots.
; Keeping one variant avoids multiplying qualified layout names while retaining
; typed signed start positions/direction for the routines that need them.
struct Extra packed
    state : u8
    timer : u8
    start_x : i8
    start_y : i8
    phase : u8
    value : i8
    reserved : u8[40]
end

union ObjectPayload
    player : PlayerPayload
    spawn : SpawnPayload
    smoke : SmokePayload
    title : TitlePayload
    hair : HairPayload
    extra : Extra
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
    row_color_index : u8 at 56
    row_color_data : u8 at 57
    sprite_control : u8 at 58
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

; Page-shaped alternatives describe the actual indexed absolute accesses used
; by the 6502 bulk copier. They are non-owning views of the same 2,400 bytes.
struct OverlayFramebufferPages packed
    page0 : u8[256] at 0
    page1 : u8[256] at 256
    page2 : u8[256] at 512
    page3 : u8[256] at 768
    page4 : u8[256] at 1024
    page5 : u8[256] at 1280
    page6 : u8[256] at 1536
    page7 : u8[256] at 1792
    page8 : u8[256] at 2048
    page9 : u8[96] at 2304
end

struct RoomTileBuffer packed
    cells : u8[256]
end

; Live-object index. kinds mirrors each pool slot's core.kind so a type scan
; reads a flat table instead of dereferencing every record; counts holds the
; number of live objects per kind (indexed by ObjectKind, entry 0 unused) so a
; scan for an absent kind is one load. Maintained at the pool's three
; kind-write sites only: Objects.clear, Objects.allocate, Objects.destroy.
struct ObjectIndex packed
    kinds : u8[16]
    counts : u8[16]
end

; The cart's dead_particles: eight fragments radiating from the killed player.
; All eight spawn together and age together, so one timer serves the set; the
; per-direction speeds are constants indexed by particle number.
struct DeadBurst packed
    x_low : u8[8]
    x_high : u8[8]
    y_low : u8[8]
    y_high : u8[8]
    timer : u8
end

struct OverlayRowPointers
    low : u8[120] at 0
    high : u8[120] at 128
end

struct BerryBits packed
    bits : u8[4]
end

; Effects are intentionally structure-of-arrays. Each 32-byte component keeps
; the physical X index and the established gaps for the 17/25 live entries.
struct FxStorage packed
    cloud_x_low : u8[32] at $000
    cloud_x_high : u8[32] at $020
    cloud_y : u8[32] at $040
    cloud_width : u8[32] at $060
    cloud_speed_low : u8[32] at $080
    cloud_speed_high : u8[32] at $0a0
    particle_x_low : u8[32] at $0c0
    particle_x_high : u8[32] at $0e0
    particle_y_low : u8[32] at $100
    particle_y_high : u8[32] at $120
    particle_speed_low : u8[32] at $140
    particle_speed_high : u8[32] at $160
    particle_attribute : u8[32] at $180
    particle_offset : u8[32] at $1a0
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
    game_state : u8[32] at 48
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
    has_key : u8 at 15
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
overlay framebuffer_pages : OverlayFramebufferPages at $e000 volatile
overlay tile_map : TileMap at $f000
overlay zero_page : ZeroPageWorking at $0000
overlay game : GameState at $0030
overlay room_tiles : RoomTileBuffer at $5400
overlay overlay_rows : OverlayRowPointers at $5500
overlay berries : BerryBits at $55f8
overlay overlay_shadow : OverlayFramebuffer at $6000
overlay overlay_shadow_pages : OverlayFramebufferPages at $6000
overlay effects : FxStorage at $5600
overlay object_index : ObjectIndex at $57c0
overlay dead_burst : DeadBurst at $57e0

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
static_assert CelesteObject.payload.extra.state.offset == 18
static_assert CelesteObject.payload.extra.start_y.offset == 21
static_assert CelesteObject.payload.extra.value.offset == 23
static_assert VideoRegisters.random.offset == 15
static_assert VideoRegisters.split.offset == 54
static_assert VideoRegisters.size == 59
static_assert $4000 + VideoRegisters.row_color_index.offset == $4038
static_assert $4000 + VideoRegisters.row_color_data.offset == $4039
static_assert $4000 + VideoRegisters.sprite_control.offset == $403A
static_assert PsgRegisters.channels.offset == 16
static_assert PsgRegisters.channel_rows.offset == 20
static_assert PsgRegisters.channel_lengths.offset == 24
static_assert PsgRegisters.music.offset == 32
static_assert PsgRegisters.size == 35
static_assert TileMap.patterns.offset == 0
static_assert TileMap.attributes.offset == 512
static_assert TileMap.size == 1024
static_assert OverlayFramebuffer.size == 2400
static_assert OverlayFramebufferPages.page9.offset == 2304
static_assert OverlayFramebufferPages.page9.count == 96
static_assert OverlayFramebufferPages.size == 2400
static_assert RoomTileBuffer.size == 256
static_assert OverlayRowPointers.high.offset == 128
static_assert OverlayRowPointers.size == 248
static_assert BerryBits.size == 4
static_assert FxStorage.cloud_x_high.offset == $020
static_assert FxStorage.particle_x_low.offset == $0c0
static_assert FxStorage.particle_offset.offset == $1a0
static_assert FxStorage.size == $1c0
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
static_assert $5600 + FxStorage.cloud_x_low.offset == $5600
static_assert $5600 + FxStorage.particle_offset.offset == $57a0
static_assert $5600 + FxStorage.size == $57c0
static_assert $6000 + OverlayFramebufferPages.page9.offset == $6900
static_assert $e000 + OverlayFramebufferPages.page9.offset == $e900
static_assert $0030 + GameState.frames.offset == $0030
static_assert $0030 + GameState.camera_y.offset == $003e
static_assert $0030 + GameState.buttons.offset == $0040
static_assert $0030 + GameState.start_game_flash.offset == $004d

namespace Machine using console6502
    export t0
    export t1
    export t2
    export t3
    export t4
    export t5
    export t6
    export t7
    export object
    export other
    export function
    export source
    export destination
    location t0 : u8 at $00
    location t1 : u8 at $01
    location t2 : u8 at $02
    location t3 : u8 at $03
    location t4 : u8 at $04
    location t5 : u8 at $05
    location t6 : u8 at $06
    location t7 : u8 at $07
    location object : ptr CelesteObject at $10
    location other : ptr CelesteObject at $12
    location function : codeptr at $14
    location source : u16 at $18
    location destination : u16 at $1a
end

; The object pool base. The pool strategy and its obj_lo/obj_hi address tables
; consume a raw target address, so this one boundary constant is retained
; (reviewed) rather than derived; everything else formerly in memmap.inlay.asm
; is now a typed overlay, location or scoped constant.
OBJPOOL = $5000

; Temporary backend-bound spellings retained only for the typed pool strategy.
location pObj : ptr CelesteObject
location pOth : ptr CelesteObject
pool objects : CelesteObject[16] at OBJPOOL table obj_lo, obj_hi

static_assert objects.count == 16
static_assert objects.stride == 64
static_assert objects.size == 1024

; ------------------------------------------------------------------------------
; Region and boundary assertions
;
; Every physical boundary the compatibility memory map (memmap.inlay.asm) still
; states as a bare hexadecimal address is pinned here to the typed layout that
; owns it, so a struct edit that would silently move a hardware register, a RAM
; region or an effects component fails the build instead of the ROM.
; ------------------------------------------------------------------------------

; MMIO video register window (video overlay at $4000).
static_assert $4000 + VideoRegisters.control.offset == $4005
static_assert $4000 + VideoRegisters.overlay_color.offset == $4006
static_assert $4000 + VideoRegisters.sprite_index.offset == $4008
static_assert $4000 + VideoRegisters.sprite_y.offset == $400a
static_assert $4000 + VideoRegisters.frame.offset == $400d
static_assert $4000 + VideoRegisters.clip_x1.offset == $4032
static_assert $4000 + VideoRegisters.clip_y1.offset == $4033

; MMIO PSG register window (psg overlay at $4100).
static_assert $4100 + PsgRegisters.address_low.offset == $4100
static_assert $4100 + PsgRegisters.address_high.offset == $4101
static_assert $4100 + PsgRegisters.music_mask.offset == $4121
static_assert $4100 + PsgRegisters.fade.offset == $4122

; Tile-world region (tile_map overlay at $f000): patterns then attributes.
static_assert $f000 + TileMap.patterns.offset == $f000
static_assert $f000 + TileMap.attributes.offset == $f200

; Working-RAM region chain above the MMIO windows. Each region's end is the
; next region's base, so the whole $5000..$57c0 block is proven contiguous.
static_assert objects.count * objects.stride == $400
static_assert $5000 + objects.count * objects.stride == $5400
static_assert $5400 + RoomTileBuffer.size == $5500
static_assert $5500 + OverlayRowPointers.high.offset == $5580
static_assert $5500 + OverlayRowPointers.size == $55f8
static_assert $55f8 + BerryBits.size == $55fc
static_assert $5600 + FxStorage.size == $57c0
static_assert ObjectIndex.kinds.count == 16
static_assert ObjectIndex.counts.offset == 16
static_assert $57c0 + ObjectIndex.size == $57e0
static_assert DeadBurst.timer.offset == 32
static_assert $57e0 + DeadBurst.size == $5801
static_assert $5801 <= $6000

; Effects structure-of-arrays component boundaries (effects overlay at $5600).
static_assert $5600 + FxStorage.cloud_x_high.offset == $5620
static_assert $5600 + FxStorage.cloud_y.offset == $5640
static_assert $5600 + FxStorage.cloud_width.offset == $5660
static_assert $5600 + FxStorage.cloud_speed_low.offset == $5680
static_assert $5600 + FxStorage.cloud_speed_high.offset == $56a0
static_assert $5600 + FxStorage.particle_x_low.offset == $56c0
static_assert $5600 + FxStorage.particle_x_high.offset == $56e0
static_assert $5600 + FxStorage.particle_y_low.offset == $5700
static_assert $5600 + FxStorage.particle_y_high.offset == $5720
static_assert $5600 + FxStorage.particle_speed_low.offset == $5740
static_assert $5600 + FxStorage.particle_speed_high.offset == $5760
static_assert $5600 + FxStorage.particle_attribute.offset == $5780

; Overlay shadow framebuffer (overlay_shadow at $6000): 120 rows of 20 bytes.
static_assert OverlayFramebuffer.size == 120 * 20
static_assert $6000 + OverlayFramebuffer.size == $6960
