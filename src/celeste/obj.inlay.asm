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

; The current pool declaration accepts target identifiers for its address
; tables, not qualified semantic labels. Keep these two target-boundary names
; global until qualified pool strategies are implemented.
obj_lo:
    #d8 $00, $40, $80, $C0, $00, $40, $80, $C0
    #d8 $00, $40, $80, $C0, $00, $40, $80, $C0
obj_hi:
    #d8 (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8]
    #d8 ((OBJPOOL+$100))[15:8], ((OBJPOOL+$100))[15:8], ((OBJPOOL+$100))[15:8], ((OBJPOOL+$100))[15:8]
    #d8 ((OBJPOOL+$200))[15:8], ((OBJPOOL+$200))[15:8], ((OBJPOOL+$200))[15:8], ((OBJPOOL+$200))[15:8]
    #d8 ((OBJPOOL+$300))[15:8], ((OBJPOOL+$300))[15:8], ((OBJPOOL+$300))[15:8], ((OBJPOOL+$300))[15:8]

namespace Objects
    export pointer
    export clear
    export allocate
    export dispatch
    export spawn_smoke
    export destroy
    export update_all
    export draw_all

; ------------------------------------------------------------------------------
; pointer: pObj = the record for slot A. Clobbers A, X.
; ------------------------------------------------------------------------------
proc pointer using console6502
    result : ptr CelesteObject return in pObj
    slot : u8 in a
begin
    address result, objects[a]
    ret
end

; ------------------------------------------------------------------------------
; Per-type method tables, indexed by type id - 1. A zero entry means the type
; does not define that method, which is the cart's `if type.update ~= nil`.
; ------------------------------------------------------------------------------
type_tile:
    #d8 0, TILE_SPAWN, 0, 0
type_init_lo:
    data u8 low(Player.init), low(Spawn.init), low(Smoke.init), low(Title.init)
type_init_hi:
    data u8 high(Player.init), high(Spawn.init), high(Smoke.init), high(Title.init)
type_update_lo:
    data u8 low(Player.update), low(Spawn.update), low(Smoke.update), low(Title.update)
type_update_hi:
    data u8 high(Player.update), high(Spawn.update), high(Smoke.update), high(Title.update)
type_draw_lo:
    data u8 low(Player.draw), low(Spawn.draw), low(Smoke.draw), low(Title.draw)
type_draw_hi:
    data u8 high(Player.draw), high(Spawn.draw), high(Smoke.draw), high(Title.draw)

; ------------------------------------------------------------------------------
; clear: empty the pool. Inputs: none. Returns: none. Clobbers: A, X, Y.
; ------------------------------------------------------------------------------
proc clear using console6502
begin
    lda #0
    ldx #OBJ_MAX-1
.slot:
    txa
    pha
    jsr Objects.pointer
    lda #0
    sta [pObj + CelesteObject.core.kind]
    pla
    tax
    dex
    bpl .slot
    ret
end

; ------------------------------------------------------------------------------
; allocate: kind/x/y are fixed physical inputs. Slot and receiver are returned;
; slot is $FF if the pool is full. Clobbers A, X, Y, t0 and pObj.
; ------------------------------------------------------------------------------
proc allocate using console6502
    kind : ObjectKind in spawn_type
    x_position : i8 in spawn_x
    y_position : i8 in spawn_y
    slot : u8 return in spawn_slot
    result : ptr CelesteObject return in pObj
begin
    ldx #0
.find:
    txa
    jsr Objects.pointer
    lda [pObj + CelesteObject.core.kind]
    beq .found
    inx
    cpx #OBJ_MAX
    bne .find
    lda #$FF                    ; pool full: the cart has no such case, this
    sta spawn_slot              ; console does. Dropping the object is the only
    rts                         ; option that cannot corrupt the list.
.found:
    stx spawn_slot

    mov y, #CelesteObject.size-1 ; a fresh record starts empty, so every field
    lda #0                      ; the type does not set reads as the cart's nil
.clear:
    sta (pObj), y
    dey
    bpl .clear

    lda spawn_type
    sta [pObj + CelesteObject.core.kind]
    tax
    lda Objects.type_tile-1, x   ; obj.spr = type.tile
    sta [pObj + CelesteObject.core.sprite]
    lda spawn_x
    sta [pObj + CelesteObject.core.x]
    lda spawn_y
    sta [pObj + CelesteObject.core.y]

    lda #8                      ; the cart's default hitbox {0,0,8,8}
    sta [pObj + CelesteObject.core.hitbox.w]
    sta [pObj + CelesteObject.core.hitbox.h]
    lda #F_COLLIDEABLE|F_SOLIDS
    mov y, offset CelesteObject.core.flags
    sta (pObj), y

    lda spawn_type              ; type.init(this)
    tax
    lda Objects.type_init_lo-1, x
    sta pFn
    lda Objects.type_init_hi-1, x
    sta pFn+1
    ora pFn
    beq .noinit
    jsr Objects.dispatch
.noinit:
    ret
end

; ------------------------------------------------------------------------------
; dispatch: jmp (pFn) as a subroutine, so the method's rts returns to our
; caller. Input: pFn. Receiver: pObj. Clobbers: callee-defined.
; ------------------------------------------------------------------------------
proc dispatch using console6502 naked
begin
    jmp (pFn)
end

; ------------------------------------------------------------------------------
; spawn_smoke: the cart's object constructor for smoke, used eight times in
; the player alone. The caller's receiver is an explicit frame local rather
; than a handwritten hardware-stack convention.
; ------------------------------------------------------------------------------
proc spawn_smoke using console6502
    self : ptr CelesteObject in pObj
    x_position : i8 in a
    y_position : i8 in x
    saved_self : ptr CelesteObject in frame
begin
    sta spawn_x
    stx spawn_y
    mov spawn_type, #ObjectKind.smoke
    mov [saved_self], self
    jsr Objects.allocate
    mov self, [saved_self]
    ret
end

; ------------------------------------------------------------------------------
; destroy: free the record pObj points at. Clobbers A, Y.
; ------------------------------------------------------------------------------
proc destroy using console6502
    self : ptr CelesteObject in pObj
begin
    lda #0
    sta [pObj + CelesteObject.core.kind]
    ret
end

; ------------------------------------------------------------------------------
; update_all: the cart's foreach(objects, ...) - move by the object's own
; speed, then run its update. Clobbers everything.
;
; Slot order is spawn order, which is the cart's list order for every case that
; matters here (nothing in stage 1 depends on two objects updating in a
; particular order relative to each other).
; ------------------------------------------------------------------------------
proc update_all using console6502
begin
    mov obj_slot, #0
.loop:
    lda obj_slot
    jsr Objects.pointer
    lda [pObj + CelesteObject.core.kind]
    beq .next

    jsr Objects.move            ; obj.move(obj.spd.x, obj.spd.y)

    lda obj_slot                ; the object may have been destroyed by its own
    jsr Objects.pointer         ; move (nothing in stage 1 does, but reloading
    lda [pObj + CelesteObject.core.kind] ; cheaper than proving it cannot)
    beq .next
    tax
    lda Objects.type_update_lo-1, x
    sta pFn
    lda Objects.type_update_hi-1, x
    sta pFn+1
    ora pFn
    beq .next
    jsr Objects.dispatch
.next:
    inc obj_slot
    cbne obj_slot, #OBJ_MAX, .loop
    ret
end

; ------------------------------------------------------------------------------
; draw_all: traverse live records and dispatch each draw lifecycle method.
; Inputs: none. Returns: none. Clobbers: A, X, Y, pObj, pFn and obj_slot.
; ------------------------------------------------------------------------------
proc draw_all using console6502
begin
    mov obj_slot, #0
.loop:
    lda obj_slot
    jsr Objects.pointer
    lda [pObj + CelesteObject.core.kind]
    beq .next
    tax
    lda Objects.type_draw_lo-1, x
    sta pFn
    lda Objects.type_draw_hi-1, x
    sta pFn+1
    ora pFn
    beq .next
    jsr Objects.dispatch
.next:
    inc obj_slot
    cbne obj_slot, #OBJ_MAX, .loop
    ret
end

; ------------------------------------------------------------------------------
; move: the cart's move(), one axis at a time.
;
;   rem.x += spd.x
;   amount = flr(rem.x + 0.5)
;   rem.x -= amount
;   step_x(amount, 0)
;
; In 8.8 the floor is free: flr() of a two's-complement 8.8 word IS its high
; byte, so the rounding is one 16-bit add of $0080 and the subtraction is one
; byte off the high half. Three 16-bit chains per axis, per object, per frame.
; Clobbers everything. t0 holds the integer step amount.
; ------------------------------------------------------------------------------
proc move using console6502
    self : ptr CelesteObject in pObj
    value : u16 in w0
    operand : u16 in w1
begin
    ldw value, [self + CelesteObject.core.remainder_x] ; rem.x += spd.x
    ldw operand, [self + CelesteObject.core.speed_x]
    ldab w0
    addw ab, operand
    stab w0
    stw [self + CelesteObject.core.remainder_x], value

    lda #$80                    ; amount = flr(rem.x + 0.5)
    ldx #$00
    jsr Fixed.set_target
    jsr Fixed.add
    lda w0+1
    sta t0

    mov y, offset CelesteObject.core.remainder_x.integer ; inlay-exception: variable update operand t0
    lda (pObj), y               ; rem.x -= amount, in the high half only
    sub t0
    sta (pObj), y

    jsr Objects.step_x

    ldw value, [self + CelesteObject.core.remainder_y] ; and the same for y
    ldw operand, [self + CelesteObject.core.speed_y]
    ldab w0
    addw ab, operand
    stab w0
    stw [self + CelesteObject.core.remainder_y], value

    lda #$80
    ldx #$00
    jsr Fixed.set_target
    jsr Fixed.add
    lda w0+1
    sta t0

    mov y, offset CelesteObject.core.remainder_y.integer ; inlay-exception: variable update operand t0
    lda (pObj), y
    sub t0
    sta (pObj), y

    jmp Objects.step_y
end

; ------------------------------------------------------------------------------
; prepare_step: turn signed amount t0 into step t1 and inclusive count t2.
; This physical helper is shared by both collision axes.
; ------------------------------------------------------------------------------
proc prepare_step using console6502 naked
    amount : i8 in t0
    step : i8 return in t1
    remaining : u8 return in t2
begin
    lda t0
    bmi .negative
    beq .zero
    mov t1, #1
    sta t2
    ret
.negative:
    mov t1, #$FF
    lda #0
    sub t0
    sta t2
    ret
.zero:
    sta t1
    sta t2
    ret
end

; ------------------------------------------------------------------------------
; step_x: step t0 pixels, stopping on solid ground. The cart's loop runs
; `for i = start, abs(amount)`, which is abs(amount)+1 iterations - so an
; unobstructed object travels one pixel further than its speed says. That is
; the original's behaviour, quirk included, and it is transliterated rather
; than corrected: the port is a reimplementation of this cart, not of the game
; it was trying to be. Clobbers A, X, Y, t1, t2.
; ------------------------------------------------------------------------------
proc step_x using console6502
    self : ptr CelesteObject in pObj
    amount : i8 in t0
begin
    lda [pObj + CelesteObject.core.flags]
    and #F_SOLIDS
    bne .solid

    mov y, offset CelesteObject.core.x ; inlay-exception: variable update operand t0
    lda (pObj), y                    ; not solid: x += amount, no collision at all
    add t0
    sta (pObj), y
    rts

.solid:
    jsr Objects.prepare_step

.loop:
    lda t1                      ; is_solid(step, 0)
    sta c_ox
    mov c_oy, #0
    jsr is_solid
    bne .blocked

    mov y, offset CelesteObject.core.x ; inlay-exception: variable update operand t1
    lda (pObj), y
    add t1
    sta (pObj), y

    dec t2                      ; inclusive loop: t2 counts down through zero
    bpl .loop
    rts

.blocked:
    lda #0                      ; spd.x = 0, rem.x = 0
    mov y, offset CelesteObject.core.speed_x.fraction
    sta (pObj), y
    iny
    sta (pObj), y
    mov y, offset CelesteObject.core.remainder_x.fraction
    sta (pObj), y
    iny
    sta (pObj), y
    ret
end

; ------------------------------------------------------------------------------
; step_y: the same, vertically. Clobbers A, X, Y, t1, t2.
; ------------------------------------------------------------------------------
proc step_y using console6502
    self : ptr CelesteObject in pObj
    amount : i8 in t0
begin
    lda [pObj + CelesteObject.core.flags]
    and #F_SOLIDS
    bne .solid

    mov y, offset CelesteObject.core.y ; inlay-exception: variable update operand t0
    lda (pObj), y
    add t0
    sta (pObj), y
    rts

.solid:
    jsr Objects.prepare_step

.loop:
    mov c_ox, #0
    lda t1
    sta c_oy
    jsr is_solid
    bne .blocked

    mov y, offset CelesteObject.core.y ; inlay-exception: variable update operand t1
    lda (pObj), y
    add t1
    sta (pObj), y

    dec t2
    bpl .loop
    rts

.blocked:
    lda #0
    mov y, offset CelesteObject.core.speed_y.fraction
    sta (pObj), y
    iny
    sta (pObj), y
    mov y, offset CelesteObject.core.remainder_y.fraction
    sta (pObj), y
    iny
    sta (pObj), y
    ret
end
end
