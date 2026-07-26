; ------------------------------------------------------------------------------
; Celeste - collision against the tile map
;
; The cart reads the map with mget() inside tile_flag_at. This console's tilemap
; window is WRITE-ONLY, so load_room keeps the live room's 256 tile ids in RAM
; and `mget` is an indexed load out of a page-aligned array: the row is y<<4 and
; the column is x, so the index is one byte and never needs a pointer.
;
; Everything here is called from move_x/move_y, so nothing in this file may
; touch t0, t1 or t2 - those hold the step and the loop counter of the caller.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; is_solid / is_ice: the object at pObj, offset by c_ox/c_oy. Returns A = 0 for
; clear, non-zero for hit; the Z flag is the answer.
;
; The cart's is_solid also consults fall_floor, fake_wall and platform objects.
; None of those types exists in stage 1, so those three checks are absent rather
; than stubbed - dead code would be counted by the corpus metrics as if it were
; real. They come back with the types, in stage 2.
; ------------------------------------------------------------------------------
is_solid:
    mov c_mask, #FLAG_SOLID
    jsr obj_box
    jmp tile_flag_at

is_ice:
    mov c_mask, #FLAG_ICE
    jsr obj_box
    jmp tile_flag_at

; ------------------------------------------------------------------------------
; obj_box: c_x/c_y/c_w/c_h = the object's hitbox, displaced by c_ox/c_oy.
; spikes_at wants the same box, so it is a routine rather than a prologue.
; Clobbers A, Y.
; ------------------------------------------------------------------------------
obj_box:
    lda [pObj + CelesteObject.core.x]
    offset y, CelesteObject.core.hitbox.x
    clc
    adc (pObj), y
    add c_ox
    sta c_x

    lda [pObj + CelesteObject.core.y]
    offset y, CelesteObject.core.hitbox.y
    clc
    adc (pObj), y
    add c_oy
    sta c_y

    lda [pObj + CelesteObject.core.hitbox.w]
    sta c_w
    lda [pObj + CelesteObject.core.hitbox.h]
    sta c_h
    rts

; ------------------------------------------------------------------------------
; tile_flag_at: is any tile overlapping the box c_x,c_y,c_w,c_h flagged c_mask?
; Returns A/Z. Clobbers A, X, Y, t3..t5, c_i, c_j, c_i1, c_j1.
; ------------------------------------------------------------------------------
tile_flag_at:
    jsr box_tiles
    bcc .miss                   ; the box does not touch the room at all

    lda c_j
    sta t3
.row:
    lda t3                      ; the row base: j * 16, one shift short of free
    asl
    asl
    asl
    asl
    sta t4
    lda c_i
    sta t5
.col:
    lda t4
    add t5
    tay
    lda ROOMTILES, y             ; mget
    tay
    lda tile_flags, y
    and c_mask
    bne .hit
    inc t5
    lda t5
    cmp c_i1
    bcc .col
    beq .col
    inc t3
    lda t3
    cmp c_j1
    bcc .row
    beq .row
.miss:
    lda #0
    rts
.hit:
    rts

; ------------------------------------------------------------------------------
; box_tiles: turn the pixel box in c_x/c_y/c_w/c_h into the inclusive tile range
; c_i..c_i1, c_j..c_j1, clamped to the room. Carry clear if the box misses the
; room entirely. Clobbers A.
;
; The cart writes max(0,flr(x/8)) and min(15,(x+w-1)/8) inline in three places;
; here it is one routine because the alternative was three copies of the same
; sign handling. flr() on a negative pixel coordinate is the whole reason this
; is not just three shifts.
; ------------------------------------------------------------------------------
box_tiles:
    lda c_x                     ; i0 = max(0, x >> 3)
    jsr floor8
    bpl .i0
    lda #0
.i0:
    sta c_i

    lda c_x                     ; i1 = min(15, (x + w - 1) >> 3)
    add c_w
    bvs .i1max                  ; signed overflow: off the right edge
    sub #1
    bmi .miss                   ; the whole box is left of the room
    jsr floor8
    cmp #16
    bcc .i1
.i1max:
    lda #15
.i1:
    sta c_i1
    cmp c_i
    bcc .miss

    lda c_y                     ; and the same vertically
    jsr floor8
    bpl .j0
    lda #0
.j0:
    sta c_j

    lda c_y
    add c_h
    bvs .j1max
    sub #1
    bmi .miss
    jsr floor8
    cmp #16
    bcc .j1
.j1max:
    lda #15
.j1:
    sta c_j1
    cmp c_j
    bcc .miss

    sec
    rts
.miss:
    clc
    rts

; ------------------------------------------------------------------------------
; floor8: A = A >> 3, arithmetic, so that a negative pixel coordinate floors
; the way Lua's flr() does rather than truncating toward zero. Clobbers A.
; ------------------------------------------------------------------------------
floor8:
    cmp #$80                    ; carry = the sign bit
    ror
    cmp #$80
    ror
    cmp #$80
    ror
    rts

; ------------------------------------------------------------------------------
; spikes_at: the cart's spikes_at for the player's box, using the player's own
; speed signs. Four tile ids, each with its own edge test - which is the
; mask-and-branch-on-memory shape add-isa-test-and-branch is scored on, in the
; one place in the program where it is genuinely dense.
;
; Returns A/Z. Clobbers A, X, Y, t3..t7 and the c_* box.
; ------------------------------------------------------------------------------
spikes_at:
    jsr box_tiles
    bcc .miss

    lda c_j
    sta t3
.row:
    lda t3
    asl
    asl
    asl
    asl
    sta t4
    lda c_i
    sta t5
.col:
    lda t4
    add t5
    tay
    lda ROOMTILES, y
    ldx #0
.which:
    cmp spike_tile, x
    beq .found
    inx
    cpx #4
    bne .which
    jmp .next
.found:
    mov pFn, spike_test_lo + x
    lda spike_test_hi, x
    sta pFn+1
    jsr call_fn
    bne .hit
.next:
    inc t5
    lda t5
    cmp c_i1
    bcc .col
    beq .col
    inc t3
    lda t3
    cmp c_j1
    bcc .row
    beq .row
.miss:
    lda #0
.hit:
    rts

spike_tile:
    #d8 TILE_SPIKE_D, TILE_SPIKE_U, TILE_SPIKE_R, TILE_SPIKE_L
spike_test_lo:
    #d8 (spike_down)[7:0], (spike_up)[7:0], (spike_right)[7:0], (spike_left)[7:0]
spike_test_hi:
    #d8 (spike_down)[15:8], (spike_up)[15:8], (spike_right)[15:8], (spike_left)[15:8]

; tile 17, pointing down: ((y+h-1)%8 >= 6 or y+h == j*8+8) and yspd >= 0
spike_down:
    offset y, CelesteObject.core.speed_y.integer
    lda (pObj), y
    bmi .no
    lda c_y
    add c_h
    sta t6                      ; y + h
    sub #1
    and #7
    cmp #6
    bcs .yes
    lda t3                      ; j*8 + 8
    asl
    asl
    asl
    add #8
    cmp t6
    beq .yes
.no:
    lda #0
    rts
.yes:
    lda #1
    rts

; tile 27, pointing up: y%8 <= 2 and yspd <= 0
spike_up:
    offset y, CelesteObject.core.speed_y.integer
    lda (pObj), y
    bmi .maybe
    lda [pObj + CelesteObject.core.speed_y.fraction]  ; high byte: +0.004 is still moving down
    offset y, CelesteObject.core.speed_y.integer
    ora (pObj), y
    bne .no
.maybe:
    lda c_y
    and #7
    cmp #3
    bcc .yes
.no:
    lda #0
    rts
.yes:
    lda #1
    rts

; tile 43, pointing right: x%8 <= 2 and xspd <= 0
spike_right:
    offset y, CelesteObject.core.speed_x.integer
    lda (pObj), y
    bmi .maybe
    lda [pObj + CelesteObject.core.speed_x.fraction]
    offset y, CelesteObject.core.speed_x.integer
    ora (pObj), y
    bne .no
.maybe:
    lda c_x
    and #7
    cmp #3
    bcc .yes
.no:
    lda #0
    rts
.yes:
    lda #1
    rts

; tile 59, pointing left: ((x+w-1)%8 >= 6 or x+w == i*8+8) and xspd >= 0
spike_left:
    offset y, CelesteObject.core.speed_x.integer
    lda (pObj), y
    bmi .no
    lda c_x
    add c_w
    sta t6
    sub #1
    and #7
    cmp #6
    bcs .yes
    lda t5
    asl
    asl
    asl
    add #8
    cmp t6
    beq .yes
.no:
    lda #0
    rts
.yes:
    lda #1
    rts
