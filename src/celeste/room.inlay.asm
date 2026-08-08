; ------------------------------------------------------------------------------
; Celeste - rooms: loading, transitions and the camera
;
; The tile world is 32x16 cells = 256x128 pixels, which is exactly two 16x16
; rooms side by side, so a room loads into the bank that is NOT on screen and
; the camera jumps to it when it is finished. Nothing is ever drawn half-built.
;
; The clip rectangle keeps tiles and sprites inside x 0..127. Without it the
; other bank's left edge would be visible in the 32 columns the HUD uses,
; because the tile layer wraps at 256 and the display is 160 wide.
; ------------------------------------------------------------------------------
namespace Room
    export init
    export title
    export load
    export next
    export restart
    export camera
    export tile_spawn
    export tile_spike_down
    export tile_spike_up
    export tile_spike_right
    export tile_spike_left
    export flag_solid
    export flag_ice
    location load_index : u8 at $4b
    width = 16
    height = 16
    map_stride = TileMap.patterns.count / height
    playfield_width = 128
    camera_y_max = 8
    title_level = 31
    tile_spawn = 1
    tile_spike_down = 17
    tile_spike_up = 27
    tile_spike_right = 43
    tile_spike_left = 59
    flag_solid = $01
    flag_ice = $10
; ------------------------------------------------------------------------------
; room_init: the parts of the tile layer that never change.
; ------------------------------------------------------------------------------
init:
    lda #0
    sta [video.clip_x0]
    sta [video.clip_y0]
    mov [video.clip_x1], #playfield_width-1
    mov [video.clip_y1], #119
    mov [video.control], #$03
    mov [video.overlay_color], #7  ; colour 7 everywhere it matters
    lda #1
    sta [game.room_bank]               ; load_room flips it, so the first room is 0
    rts
; ------------------------------------------------------------------------------
; is_title: Z set if the room on screen is the title screen, which is the
; cart's is_title() - level_index() == 31. Clobbers A.
; ------------------------------------------------------------------------------
title:
    lda [game.level]
    cmp #title_level
    rts
; ------------------------------------------------------------------------------
; load_room: A = index into the resident room table. Clobbers everything.
; ------------------------------------------------------------------------------
load:
    sta [game.room_slot]
    tax
    mov [game.level], room_levels + x
    mov [game.has_dashed], #0
    mov [game.has_key], #0
    mov Machine.source, room_ptr_lo + x
    mov Machine.source+1, room_ptr_hi + x
    jsr Objects.clear           ; the cart's foreach(objects, destroy)
    lda [game.room_bank]               ; load into the bank that is not on screen
    eor #1
    sta [game.room_bank]
    ldy #0                      ; the room's tile ids become this port's mget
.copy:
    lda (Machine.source), y
    sta [room_tiles.cells[y]]
    iny
    bne .copy
    address Machine.destination, tile_map.patterns
    lda [game.room_bank]
    beq .bank0
    lda Machine.destination
    add #16
    sta Machine.destination
.bank0:
    ldx #0                      ; X walks the 256 tile ids in order
    mov Machine.t6, #height
.row:
    ldy #0
.col:
    lda [room_tiles.cells[x]]
    stx Machine.t5
    tax
    lda Gfx.tile_base, x
    sta (Machine.destination), y
    lda Gfx.tile_attr, x
    inc Machine.destination+1                  ; the attribute plane is $200 higher
    inc Machine.destination+1
    sta (Machine.destination), y
    dec Machine.destination+1
    dec Machine.destination+1
    ldx Machine.t5
    inx
    iny
    cpy #width
    bne .col
    lda Machine.destination                    ; next cell row
    add #map_stride
    sta Machine.destination
    bcc .norow
    inc Machine.destination+1
.norow:
    dec Machine.t6
    bne .row
    ldx #0                      ; spawn every marker kind resident in the campaign
.spawn:
    lda [room_tiles.cells[x]]
    beq .nextspawn
    pha
    txa
    and #15
    asl a, 3
    sta Objects.spawn_x
    txa
    and #$F0
    lsr
    sta Objects.spawn_y
    stx [game.room_load_index]
    pla
    jsr Objects.spawn_marker
    ldx [game.room_load_index]
.nextspawn:
    inx
    bne .spawn
    lda [game.room_bank]               ; show the bank we just filled
    beq .cam0
    lda #playfield_width
.cam0:
    sta Machine.t3
    jsr title              ; the cart draws the title room at x = -4 on its
    bne .notitle                ; 128 columns; this display has 160, so the
    lda Machine.t3                      ; title scrolls a further 16 right to centre
    sub #12                     ; the logo and opens the clip to the full
    sta Machine.t3              ; width. The 32 uncovered columns read the
    mov [video.clip_x1], #159   ; other, still-empty tile bank: blank.
    mov [video.overlay_color], #5  ; the cart prints the credits in colour 5
    jmp .cam
.notitle:
    mov [video.clip_x1], #playfield_width-1
    mov [video.overlay_color], #7  ; HUD, banner and lifeup are white
.cam:
    lda #0                      ; drop any per-row colour override a lifeup
    sta [video.row_color_index] ; left behind in the departed room
    ldx #120
.rowclear:
    sta [video.row_color_data]
    dex
    bne .rowclear
    lda Machine.t3
    sta [video.camera_x]
    lda #0
    sta [game.camera_y]
    sta [video.camera_y]
    jsr title              ; the cart shows no room title on the title
    beq .done                   ; screen: `if not is_title() then ... end`
    mov Objects.spawn_type, #ObjectKind.title
    lda #0
    sta Objects.spawn_x
    sta Objects.spawn_y
    jsr Objects.allocate
.done:
    jmp Draw.overlay_dirty
; ------------------------------------------------------------------------------
; next_room / restart_room
;
; The resident table is now title followed by playable levels 0..9, matching the
; cart's progression. Reaching the top of level 9 wraps to level 0 until the next
; campaign slice adds level 10.
; ------------------------------------------------------------------------------
next:
    ldx #0                      ; the cart's four music cues, keyed on the room
.cue:                           ; being LEFT - see the table below
    lda cue_level, x
    cmp [game.level]
    beq .play
    inx
    cpx #4
    bne .cue
    jmp .advance
.play:
    lda cue_music, x
    ldx #Audio.fade_500ms
    jsr Audio.fade
.advance:
    lda [game.room_slot]
    add #1
    cmp #ROOM_COUNT
    bcc .go
    lda #1                      ; wrap to the first PLAYING room: slot 0 is the
.go:                            ; title screen and is only reached from reset
    jmp load
; The cart's next_room() cues, by the level being left. All four are ported
; even though this room set only reaches two of them (11 and 20): they are
; data, not code, and the table is the same size either way.
;
;   level 10 = room (2,1)   level 11 = room (3,1), "old site"
;   level 20 = room (4,2)   level 29 = room (5,3)
cue_level:
    #d8 10, 11, 20, 29
cue_music:
    #d8 30, 20, 30, 30
restart:
    lda [game.room_slot]
    jmp load
; ------------------------------------------------------------------------------
; camera_update: the vertical follow that covers a 128-line room in a 120-line
; window. The cart's camera is static per room; this is the port's one
; unavoidable divergence from it, and it is 8 pixels wide.
; Clobbers A, X, Y.
; ------------------------------------------------------------------------------
camera:
    ldx #0
.find:
    txa
    jsr Objects.pointer
    lda [Machine.object.core.kind]
    cmp #ObjectKind.player
    beq .found
    cmp #ObjectKind.spawn
    beq .found
    inx
    cpx #Objects.slot_count
    bne .find
    rts                         ; no player: leave the camera where it is
.found:
    mov y, offset CelesteObject.core.y
    lda (Machine.object), y
    bmi .top                    ; above the room: show the top
    sub #56
    bcc .top
    cmp #camera_y_max
    bcc .set
    lda #camera_y_max
    jmp .set
.top:
    lda #0
.set:
    sta [game.camera_y]
    sta [video.camera_y]
    rts
end
