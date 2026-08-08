; ------------------------------------------------------------------------------
; Celeste - collision against the tile map
;
; The cart reads the map with mget() inside tile_flag_at. This console's tilemap
; window is WRITE-ONLY, so load_room keeps the live room's 256 tile ids in RAM
; and `mget` is an indexed load out of a page-aligned array: the row is y<<4 and
; the column is x, so the index is one byte and never needs a pointer.
;
; Everything here is called from Objects.step_x/step_y, so nothing here may
; touch t0, t1 or t2 - those hold the step and the loop counter of the caller.
; ------------------------------------------------------------------------------
namespace Collision
    export offset_x
    export offset_y
    location x : u8 at $22
    location y : u8 at $23
    location width : u8 at $24
    location height : u8 at $25
    location mask : u8 at $26
    location offset_x : i8 at $27
    location offset_y : i8 at $28
    location type : u8 at $29
    location remaining : u8 at $2a
    location column : u8 at $2b
    location row : u8 at $2c
    location last_column : u8 at $2d
    location last_row : u8 at $2e
    export solid
    export ice
    export box
    export object
    export spikes
; ------------------------------------------------------------------------------
; is_solid / is_ice: the object at pObj, offset by c_ox/c_oy. Returns A = 0 for
; clear, non-zero for hit; the Z flag is the answer.
;
; The cart's is_solid also consults fall_floor, fake_wall and platform objects.
; None of those types exists in stage 1, so those three checks are absent rather
; than stubbed - dead code would be counted by the corpus metrics as if it were
; real. They come back with the types, in stage 2.
; ------------------------------------------------------------------------------
solid:
    mov mask, #Room.flag_solid
    jsr box
    jsr flags
    bne .hit

    ; A platform only catches downward motion when the receiver was not already
    ; overlapping it at the undisplaced position.
    lda offset_y
    beq .objects
    bmi .objects
    sta last_row
    mov type, #ObjectKind.platform
    mov offset_y, #0
    jsr object
    sta mask
    lda last_row
    sta offset_y
    lda mask
    bne .objects
    jsr object
    bne .hit
.objects:
    mov type, #ObjectKind.fall_floor
    jsr object
    bne .hit
    mov type, #ObjectKind.fake_wall
    jsr object
.hit:
    rts
ice:
    mov mask, #Room.flag_ice
    jsr box
    jmp flags
; ------------------------------------------------------------------------------
; obj_box: c_x/c_y/c_w/c_h = the object's hitbox, displaced by c_ox/c_oy.
; spikes_at wants the same box, so it is a routine rather than a prologue.
; Clobbers A, Y.
; ------------------------------------------------------------------------------
box:
    lda [Machine.object.core.x]
    mov y, offset CelesteObject.core.hitbox.x
    clc
    adc (Machine.object), y
    add offset_x
    sta Collision.x
    lda [Machine.object.core.y]
    mov y, offset CelesteObject.core.hitbox.y
    clc
    adc (Machine.object), y
    add offset_y
    sta Collision.y
    lda [Machine.object.core.hitbox.w]
    sta width
    lda [Machine.object.core.hitbox.h]
    sta height
    rts

; ------------------------------------------------------------------------------
; object: collide the receiver against another live object of `type`, displaced
; by offset_x/offset_y. Returns A/Z and leaves Machine.other pointing at the hit.
; Coordinates are biased by 32 before unsigned comparisons so the room's small
; negative edge positions retain signed ordering without 16-bit boxes.
; Clobbers A, X, Y, t3..t7, remaining and Machine.other.
;
; The scan reads object_index rather than the records: an absent kind returns
; before the box is even built (solid() probes platform, fall_floor and
; fake_wall on every call, and most rooms hold none of them), a non-matching
; slot costs one flat table load instead of a pointer setup plus an indirect
; kind load, and the loop stops after the last live instance of the kind -
; the fall floors' per-tick player probes stop at the player's slot.
; ------------------------------------------------------------------------------
object:
    ldx type
    lda [object_index.counts[x]]
    bne .some
    rts                         ; A = 0, Z set: no object of this kind is live
.some:
    sta remaining
    jsr box
    lda Collision.x
    add #32
    sta Machine.t3              ; receiver left
    add width
    sta Machine.t5              ; receiver right
    lda Collision.y
    add #32
    sta Machine.t4              ; receiver top
    add height
    sta Machine.t6              ; receiver bottom

    ldx #0
.candidate:
    lda [object_index.kinds[x]]
    cmp type
    bne .next
    lda obj_lo, x
    sta Machine.other
    lda obj_hi, x
    sta Machine.other+1
    cmp Machine.object+1
    bne .kind_ready
    lda Machine.other
    cmp Machine.object
    beq .consume                ; the receiver itself: spend its count
.kind_ready:
    mov y, offset CelesteObject.core.flags
    lda (Machine.other), y
    and #Objects.flag_collideable
    beq .consume

    mov y, offset CelesteObject.core.x
    lda (Machine.other), y
    mov y, offset CelesteObject.core.hitbox.x
    clc
    adc (Machine.other), y
    add #32
    cmp Machine.t5
    bcs .consume
    sta Machine.t7              ; other left
    mov y, offset CelesteObject.core.hitbox.w
    clc
    adc (Machine.other), y
    cmp Machine.t3
    bcc .consume
    beq .consume

    mov y, offset CelesteObject.core.y
    lda (Machine.other), y
    mov y, offset CelesteObject.core.hitbox.y
    clc
    adc (Machine.other), y
    add #32
    cmp Machine.t6
    bcs .consume
    sta Machine.t7              ; other top
    mov y, offset CelesteObject.core.hitbox.h
    clc
    adc (Machine.other), y
    cmp Machine.t4
    bcc .consume
    beq .consume
    lda #1
    rts
.consume:
    dec remaining
    beq .none                   ; every live instance of the kind is behind us
.next:
    inx
    cpx #Objects.slot_count
    bne .candidate
.none:
    lda #0
    rts
; ------------------------------------------------------------------------------
; tile_flag_at: is any tile overlapping the box c_x,c_y,c_w,c_h flagged c_mask?
; Returns A/Z. Clobbers A, X, Y, t3..t5, c_i, c_j, c_i1, c_j1.
; ------------------------------------------------------------------------------
flags:
    jsr tiles
    bcc .miss                   ; the box does not touch the room at all
    lda row
    sta Machine.t3
.row:
    lda Machine.t3                      ; the row base: j * 16, one shift short of free
    asl a, 4
    sta Machine.t4
    lda column
    sta Machine.t5
.col:
    lda Machine.t4
    add Machine.t5
    tay
    lda [room_tiles.cells[y]] ; mget
    tay
    lda tile_flags, y
    and mask
    bne .hit
    inc Machine.t5
    lda Machine.t5
    cmp last_column
    bcc .col
    beq .col
    inc Machine.t3
    lda Machine.t3
    cmp last_row
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
tiles:
    lda Collision.x                     ; i0 = max(0, x >> 3)
    jsr floor
    bpl .i0
    lda #0
.i0:
    sta column
    lda Collision.x                     ; i1 = min(15, (x + w - 1) >> 3)
    add width
    bvs .i1max                  ; signed overflow: off the right edge
    sub #1
    bmi .miss                   ; the whole box is left of the room
    jsr floor
    cmp #16
    bcc .i1
.i1max:
    lda #15
.i1:
    sta last_column
    cmp column
    bcc .miss
    lda Collision.y                     ; and the same vertically
    jsr floor
    bpl .j0
    lda #0
.j0:
    sta row
    lda Collision.y
    add height
    bvs .j1max
    sub #1
    bmi .miss
    jsr floor
    cmp #16
    bcc .j1
.j1max:
    lda #15
.j1:
    sta last_row
    cmp row
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
floor:
    asr a, 3
    rts
; ------------------------------------------------------------------------------
; spikes_at: the cart's spikes_at for the player's box, using the player's own
; speed signs. Four tile ids, each with its own edge test - which is the
; mask-and-branch-on-memory shape add-isa-test-and-branch is scored on, in the
; one place in the program where it is genuinely dense.
;
; Returns A/Z. Clobbers A, X, Y, t3..t7 and the c_* box.
; ------------------------------------------------------------------------------
spikes:
    jsr tiles
    bcc .miss
    lda row
    sta Machine.t3
.row:
    lda Machine.t3
    asl a, 4
    sta Machine.t4
    lda column
    sta Machine.t5
.col:
    lda Machine.t4
    add Machine.t5
    tay
    lda [room_tiles.cells[y]]
    ldx #0
.which:
    cmp ids, x
    beq .found
    inx
    cpx #4
    bne .which
    jmp .next
.found:
    mov Machine.function, lo + x
    lda hi, x
    sta Machine.function+1
    jsr Objects.dispatch
    bne .hit
.next:
    inc Machine.t5
    lda Machine.t5
    cmp last_column
    bcc .col
    beq .col
    inc Machine.t3
    lda Machine.t3
    cmp last_row
    bcc .row
    beq .row
.miss:
    lda #0
.hit:
    rts
ids:
    #d8 Room.tile_spike_down, Room.tile_spike_up, Room.tile_spike_right, Room.tile_spike_left
lo:
    data u8 low(down), low(up), low(right), low(left)
hi:
    data u8 high(down), high(up), high(right), high(left)
; tile 17, pointing down: ((y+h-1)%8 >= 6 or y+h == j*8+8) and yspd >= 0
proc down using console6502 naked
begin
    mov y, offset CelesteObject.core.speed_y.integer
    lda (Machine.object), y
    bmi .no
    lda Collision.y
    add height
    sta Machine.t6                      ; y + h
    sub #1
    and #7
    cmp #6
    bcs .yes
    lda Machine.t3                      ; j*8 + 8
    asl a, 3
    add #8
    cmp Machine.t6
    beq .yes
.no:
    lda #0
    rts
.yes:
    lda #1
    rts
end
; tile 27, pointing up: y%8 <= 2 and yspd <= 0
proc up using console6502 naked
begin
    mov y, offset CelesteObject.core.speed_y.integer
    lda (Machine.object), y
    bmi .maybe
    lda [Machine.object.core.speed_y.fraction]  ; high byte: +0.004 is still moving down
    mov y, offset CelesteObject.core.speed_y.integer
    ora (Machine.object), y
    bne .no
.maybe:
    lda Collision.y
    and #7
    cmp #3
    bcc .yes
.no:
    lda #0
    rts
.yes:
    lda #1
    rts
end
; tile 43, pointing right: x%8 <= 2 and xspd <= 0
proc right using console6502 naked
begin
    mov y, offset CelesteObject.core.speed_x.integer
    lda (Machine.object), y
    bmi .maybe
    lda [Machine.object.core.speed_x.fraction]
    mov y, offset CelesteObject.core.speed_x.integer
    ora (Machine.object), y
    bne .no
.maybe:
    lda Collision.x
    and #7
    cmp #3
    bcc .yes
.no:
    lda #0
    rts
.yes:
    lda #1
    rts
end
; tile 59, pointing left: ((x+w-1)%8 >= 6 or x+w == i*8+8) and xspd >= 0
proc left using console6502 naked
begin
    mov y, offset CelesteObject.core.speed_x.integer
    lda (Machine.object), y
    bmi .no
    lda Collision.x
    add width
    sta Machine.t6
    sub #1
    and #7
    cmp #6
    bcs .yes
    lda Machine.t5
    asl a, 3
    add #8
    cmp Machine.t6
    beq .yes
.no:
    lda #0
    rts
.yes:
    lda #1
    rts
end
end
