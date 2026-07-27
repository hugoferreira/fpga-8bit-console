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
    location load_index : u8 at $4b
    width = 16
    height = 16
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
    sta [video + VideoRegisters.clip_x0]
    sta [video + VideoRegisters.clip_y0]
    mov [video + VideoRegisters.clip_x1], #PLAYFIELD_W-1
    mov [video + VideoRegisters.clip_y1], #119
    mov [video + VideoRegisters.control], #$03
    mov [video + VideoRegisters.overlay_color], #7  ; colour 7 everywhere it matters
    lda #1
    sta room_bank               ; load_room flips it, so the first room is 0
    rts
; ------------------------------------------------------------------------------
; is_title: Z set if the room on screen is the title screen, which is the
; cart's is_title() - level_index() == 31. Clobbers A.
; ------------------------------------------------------------------------------
title:
    lda level
    cmp #TITLE_LEVEL
    rts
; ------------------------------------------------------------------------------
; load_room: A = index into the resident room table. Clobbers everything.
; ------------------------------------------------------------------------------
load:
    sta room_slot
    tax
    mov level, room_levels + x
    mov has_dashed, #0
    mov pSrc, room_ptr_lo + x
    mov pSrc+1, room_ptr_hi + x
    jsr Objects.clear           ; the cart's foreach(objects, destroy)
    lda room_bank               ; load into the bank that is not on screen
    eor #1
    sta room_bank
    ldy #0                      ; the room's tile ids become this port's mget
.copy:
    lda (pSrc), y
    sta [room_tiles + RoomTileBuffer.cells[y]]
    iny
    bne .copy
    mov pDst, #<MAP_LO
    mov pDst+1, #>MAP_LO
    lda room_bank
    beq .bank0
    lda pDst
    add #16
    sta pDst
.bank0:
    ldx #0                      ; X walks the 256 tile ids in order
    mov t6, #ROOM_H
.row:
    ldy #0
.col:
    lda ROOMTILES, x
    stx t5
    tax
    lda Gfx.tile_base, x
    sta (pDst), y
    lda Gfx.tile_attr, x
    inc pDst+1                  ; the attribute plane is $200 higher
    inc pDst+1
    sta (pDst), y
    dec pDst+1
    dec pDst+1
    ldx t5
    inx
    iny
    cpy #ROOM_W
    bne .col
    lda pDst                    ; next cell row
    add #MAP_STRIDE
    sta pDst
    bcc .norow
    inc pDst+1
.norow:
    dec t6
    bne .row
    ldx #0                      ; spawn the objects the marker tiles ask for
.spawn:
    lda ROOMTILES, x
    cmp #TILE_SPAWN
    bne .nextspawn
    txa
    and #15
    asl
    asl
    asl
    sta spawn_x
    txa
    and #$F0
    lsr
    sta spawn_y
    stx ld_i
    mov spawn_type, #ObjectKind.spawn
    jsr Objects.allocate
    ldx ld_i
.nextspawn:
    inx
    bne .spawn
    lda room_bank               ; show the bank we just filled
    beq .cam0
    lda #PLAYFIELD_W
.cam0:
    sta t3
    jsr Room.title              ; the cart draws the title room at x = -4:
    bne .notitle                ;   map(room.x*16, room.y*16, off, 0, 16, 16, 2)
    lda t3                      ; with off = -4. Scrolling the camera 4 to the
    add #4
    sta t3
    mov [video + VideoRegisters.clip_x1], #PLAYFIELD_W-5  ; does not appear in the gap that opens up
    jmp .cam
.notitle:
    mov [video + VideoRegisters.clip_x1], #PLAYFIELD_W-1
.cam:
    lda t3
    sta [video + VideoRegisters.camera_x]
    lda #0
    sta camera_y
    sta [video + VideoRegisters.camera_y]
    jsr Room.title              ; the cart shows no room title on the title
    beq .done                   ; screen: `if not is_title() then ... end`
    mov spawn_type, #ObjectKind.title
    lda #0
    sta spawn_x
    sta spawn_y
    jsr Objects.allocate
.done:
    jmp Draw.overlay_dirty
; ------------------------------------------------------------------------------
; next_room / restart_room
;
; The cart walks the level index in order. The three resident rooms were chosen
; for tile-flag variety rather than adjacency (see inventory.md), so the port
; cycles the table instead. Everything the transition exercises - unload, load
; into the far bank, camera flip, respawn - is the same either way.
; ------------------------------------------------------------------------------
next:
    ldx #0                      ; the cart's four music cues, keyed on the room
.cue:                           ; being LEFT - see the table below
    lda Room.cue_level, x
    cmp level
    beq .play
    inx
    cpx #4
    bne .cue
    jmp .advance
.play:
    lda Room.cue_music, x
    ldx #FADE_500MS
    jsr Audio.fade
.advance:
    lda room_slot
    add #1
    cmp #ROOM_COUNT
    bcc .go
    lda #1                      ; wrap to the first PLAYING room: slot 0 is the
.go:                            ; title screen and is only reached from reset
    jmp Room.load
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
    lda room_slot
    jmp Room.load
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
    lda [pObj + CelesteObject.core.kind]
    cmp #ObjectKind.player
    beq .found
    cmp #ObjectKind.spawn
    beq .found
    inx
    cpx #OBJ_MAX
    bne .find
    rts                         ; no player: leave the camera where it is
.found:
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    bmi .top                    ; above the room: show the top
    sub #56
    bcc .top
    cmp #CAM_Y_MAX
    bcc .set
    lda #CAM_Y_MAX
    jmp .set
.top:
    lda #0
.set:
    sta camera_y
    sta [video + VideoRegisters.camera_y]
    rts
end
