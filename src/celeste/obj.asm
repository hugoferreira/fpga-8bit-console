; ------------------------------------------------------------------------------
; Celeste - the object list, its dispatch, and move()
;
; RECORDED DECISION (task 3.1): the dispatch is a JUMP TABLE, not a chain of
; comparisons. The design left this open on purpose, because which one a
; programmer reaches for is itself evidence about the ISA. The reason it came
; out this way is worth stating: the cart's types are tables with optional
; init/update/draw members, and load_room already has to map a tile id to a
; type, so a table indexed by type id was the shape of the data before it was
; the shape of the code. A comparison chain would have meant writing the type
; ids out three more times.
;
; The cost is visible: every dispatch is two indexed loads, two zero-page
; stores and a `jmp (pFn)` - eight instructions of pure plumbing, of which the
; only useful one is the jump. That is add-isa-pointer-ops' case, measured
; rather than argued.
;
; The pool is 16 records of 64 bytes, page-aligned, so four records to a page.
; The slot -> address map is a 32-byte table rather than three shifts and an
; add; nemo reached the same conclusion for its row bases, for the same reason
; (the table is smaller AND faster than the arithmetic it replaces).
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; obj_ptr: pObj = the record for slot A. Clobbers A, X.
; ------------------------------------------------------------------------------
obj_ptr:
    tax
    mov pObj, obj_lo + x
    lda obj_hi, x
    sta pObj+1
    rts

obj_lo:
    #d8 $00, $40, $80, $C0, $00, $40, $80, $C0
    #d8 $00, $40, $80, $C0, $00, $40, $80, $C0
obj_hi:
    #d8 (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8]
    #d8 ((OBJPOOL+$100))[15:8], ((OBJPOOL+$100))[15:8], ((OBJPOOL+$100))[15:8], ((OBJPOOL+$100))[15:8]
    #d8 ((OBJPOOL+$200))[15:8], ((OBJPOOL+$200))[15:8], ((OBJPOOL+$200))[15:8], ((OBJPOOL+$200))[15:8]
    #d8 ((OBJPOOL+$300))[15:8], ((OBJPOOL+$300))[15:8], ((OBJPOOL+$300))[15:8], ((OBJPOOL+$300))[15:8]

; ------------------------------------------------------------------------------
; Per-type method tables, indexed by type id - 1. A zero entry means the type
; does not define that method, which is the cart's `if type.update ~= nil`.
; ------------------------------------------------------------------------------
type_tile:
    #d8 0, TILE_SPAWN, 0, 0
type_init_lo:
    #d8 (player_init)[7:0], (spawn_init)[7:0], (smoke_init)[7:0], (title_init)[7:0]
type_init_hi:
    #d8 (player_init)[15:8], (spawn_init)[15:8], (smoke_init)[15:8], (title_init)[15:8]
type_update_lo:
    #d8 (player_update)[7:0], (spawn_update)[7:0], (smoke_update)[7:0], (title_update)[7:0]
type_update_hi:
    #d8 (player_update)[15:8], (spawn_update)[15:8], (smoke_update)[15:8], (title_update)[15:8]
type_draw_lo:
    #d8 (player_draw)[7:0], (spawn_draw)[7:0], (smoke_draw)[7:0], (title_draw)[7:0]
type_draw_hi:
    #d8 (player_draw)[15:8], (spawn_draw)[15:8], (smoke_draw)[15:8], (title_draw)[15:8]

; ------------------------------------------------------------------------------
; obj_init: empty the pool. Clobbers A, X, Y.
; ------------------------------------------------------------------------------
obj_init:
    lda #0
    ldx #OBJ_MAX-1
.slot:
    txa
    pha
    jsr obj_ptr
    ldy #O_TYPE
    lda #0
    sta (pObj), y
    pla
    tax
    dex
    bpl .slot
    rts

; ------------------------------------------------------------------------------
; init_object: spawn_type/spawn_x/spawn_y in, spawn_slot out ($FF if the pool
; is full). pObj is left pointing at the new record. Clobbers A, X, Y, t0.
; ------------------------------------------------------------------------------
init_object:
    ldx #0
.find:
    txa
    jsr obj_ptr
    ldy #O_TYPE
    lda (pObj), y
    beq .found
    inx
    cpx #OBJ_MAX
    bne .find
    lda #$FF                    ; pool full: the cart has no such case, this
    sta spawn_slot              ; console does. Dropping the object is the only
    rts                         ; option that cannot corrupt the list.
.found:
    stx spawn_slot

    ldy #O_SIZE-1               ; a fresh record starts empty, so every field
    lda #0                      ; the type does not set reads as the cart's nil
.clear:
    sta (pObj), y
    dey
    bpl .clear

    lda spawn_type
    sta (pObj), #O_TYPE
    tax
    lda type_tile-1, x           ; obj.spr = type.tile
    sta (pObj), #O_SPR
    lda spawn_x
    sta (pObj), #O_X
    lda spawn_y
    sta (pObj), #O_Y

    lda #8                      ; the cart's default hitbox {0,0,8,8}
    sta (pObj), #O_HBW
    sta (pObj), #O_HBH
    lda #F_COLLIDEABLE|F_SOLIDS
    ldy #O_FLAGS
    sta (pObj), y

    lda spawn_type              ; type.init(this)
    tax
    lda type_init_lo-1, x
    sta pFn
    lda type_init_hi-1, x
    sta pFn+1
    ora pFn
    beq .noinit
    jsr call_fn
.noinit:
    rts

; ------------------------------------------------------------------------------
; call_fn: jmp (pFn) as a subroutine, so the method's rts returns to our caller.
; ------------------------------------------------------------------------------
call_fn:
    jmp (pFn)

; ------------------------------------------------------------------------------
; spawn_at: init_object(spawn_type, spawn_x, spawn_y) from inside another
; object's update, keeping the caller's pObj. The cart gets this for free
; because every object is a closure over its own `this`; here it is four stack
; operations, and forgetting them once cost an afternoon.
; ------------------------------------------------------------------------------
spawn_at:
    lda pObj
    pha
    lda pObj+1
    pha
    jsr init_object
    pla
    sta pObj+1
    pla
    sta pObj
    rts

; ------------------------------------------------------------------------------
; spawn_smoke: the cart's init_object(smoke, x, y), which appears eight times in
; the player alone. A = x, X = y.
; ------------------------------------------------------------------------------
spawn_smoke:
    sta spawn_x
    stx spawn_y
    mov spawn_type, #T_SMOKE
    jmp spawn_at

; ------------------------------------------------------------------------------
; destroy_object: free the record pObj points at. Clobbers A, Y.
; ------------------------------------------------------------------------------
destroy_object:
    lda #0
    ldy #O_TYPE
    sta (pObj), y
    rts

; ------------------------------------------------------------------------------
; obj_update_all: the cart's foreach(objects, ...) - move by the object's own
; speed, then run its update. Clobbers everything.
;
; Slot order is spawn order, which is the cart's list order for every case that
; matters here (nothing in stage 1 depends on two objects updating in a
; particular order relative to each other).
; ------------------------------------------------------------------------------
obj_update_all:
    mov obj_slot, #0
.loop:
    lda obj_slot
    jsr obj_ptr
    ldy #O_TYPE
    lda (pObj), y
    beq .next

    jsr obj_move                ; obj.move(obj.spd.x, obj.spd.y)

    lda obj_slot                ; the object may have been destroyed by its own
    jsr obj_ptr                 ; move (nothing in stage 1 does, but reloading
    ldy #O_TYPE                 ; pObj is a byte cheaper than proving it cannot)
    lda (pObj), y
    beq .next
    tax
    lda type_update_lo-1, x
    sta pFn
    lda type_update_hi-1, x
    sta pFn+1
    ora pFn
    beq .next
    jsr call_fn
.next:
    inc obj_slot
    lda obj_slot
    cmp #OBJ_MAX
    bne .loop
    rts

; ------------------------------------------------------------------------------
; obj_move: the cart's move(), one axis at a time.
;
;   rem.x += spd.x
;   amount = flr(rem.x + 0.5)
;   rem.x -= amount
;   move_x(amount, 0)
;
; In 8.8 the floor is free: flr() of a two's-complement 8.8 word IS its high
; byte, so the rounding is one 16-bit add of $0080 and the subtraction is one
; byte off the high half. Three 16-bit chains per axis, per object, per frame.
; Clobbers everything. t0 holds the integer step amount.
; ------------------------------------------------------------------------------
obj_move:
    ldy #O_REMX                 ; rem.x += spd.x
    jsr obj_ldw
    ldy #O_SPDX
    jsr obj_ldw1
    jsr add16
    ldy #O_REMX
    jsr obj_stw

    lda #$80                    ; amount = flr(rem.x + 0.5)
    ldx #$00
    jsr setw1
    jsr add16
    lda w0+1
    sta t0

    ldy #O_REMX+1               ; rem.x -= amount, in the high half only
    lda (pObj), y
    sub t0
    sta (pObj), y

    jsr move_x

    ldy #O_REMY                 ; and the same for y
    jsr obj_ldw
    ldy #O_SPDY
    jsr obj_ldw1
    jsr add16
    ldy #O_REMY
    jsr obj_stw

    lda #$80
    ldx #$00
    jsr setw1
    jsr add16
    lda w0+1
    sta t0

    ldy #O_REMY+1
    lda (pObj), y
    sub t0
    sta (pObj), y

    jmp move_y

; ------------------------------------------------------------------------------
; move_x: step t0 pixels, stopping on solid ground. The cart's loop runs
; `for i = start, abs(amount)`, which is abs(amount)+1 iterations - so an
; unobstructed object travels one pixel further than its speed says. That is
; the original's behaviour, quirk included, and it is transliterated rather
; than corrected: the port is a reimplementation of this cart, not of the game
; it was trying to be. Clobbers A, X, Y, t1, t2.
; ------------------------------------------------------------------------------
move_x:
    lda (pObj), #O_FLAGS
    and #F_SOLIDS
    bne .solid

    ldy #O_X                    ; not solid: x += amount, no collision at all
    lda (pObj), y
    add t0
    sta (pObj), y
    rts

.solid:
    lda t0                      ; step = sign(amount), and the loop count
    bmi .neg
    beq .zero
    mov t1, #1
    lda t0
    sta t2
    jmp .loop
.neg:
    mov t1, #$FF
    sub t0
    mov t2, #0
    jmp .loop
.zero:
    sta t1                      ; step 0: the cart still runs one iteration,
    sta t2                      ; which can only zero an already-stuck speed

.loop:
    lda t1                      ; is_solid(step, 0)
    sta c_ox
    mov c_oy, #0
    jsr is_solid
    bne .blocked

    ldy #O_X
    lda (pObj), y
    add t1
    sta (pObj), y

    dec t2                      ; inclusive loop: t2 counts down through zero
    bpl .loop
    rts

.blocked:
    lda #0                      ; spd.x = 0, rem.x = 0
    ldy #O_SPDX
    sta (pObj), y
    iny
    sta (pObj), y
    ldy #O_REMX
    sta (pObj), y
    iny
    sta (pObj), y
    rts

; ------------------------------------------------------------------------------
; move_y: the same, vertically. Clobbers A, X, Y, t1, t2.
; ------------------------------------------------------------------------------
move_y:
    lda (pObj), #O_FLAGS
    and #F_SOLIDS
    bne .solid

    ldy #O_Y
    lda (pObj), y
    add t0
    sta (pObj), y
    rts

.solid:
    lda t0
    bmi .neg
    beq .zero
    mov t1, #1
    lda t0
    sta t2
    jmp .loop
.neg:
    mov t1, #$FF
    sub t0
    mov t2, #0
    jmp .loop
.zero:
    sta t1
    sta t2

.loop:
    mov c_ox, #0
    lda t1
    sta c_oy
    jsr is_solid
    bne .blocked

    ldy #O_Y
    lda (pObj), y
    add t1
    sta (pObj), y

    dec t2
    bpl .loop
    rts

.blocked:
    lda #0
    ldy #O_SPDY
    sta (pObj), y
    iny
    sta (pObj), y
    ldy #O_REMY
    sta (pObj), y
    iny
    sta (pObj), y
    rts
