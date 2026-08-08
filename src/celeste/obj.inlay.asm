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
    export spawn_marker
    export dispatch
    export spawn_smoke
    export destroy
    export update_all
    export draw_all
    export flag_collideable
    export flag_solids
    export slot_count
    export slot
    export spawn_type
    export spawn_x
    export spawn_y
    export spawn_slot
    slot_count = objects.count
    flag_collideable = $01
    flag_solids = $02
    location slot : u8 at $1c
    location free_slot : u8 at $1d
    location spawn_type : u8 at $1e
    location spawn_x : u8 at $1f
    location spawn_y : u8 at $20
    location spawn_slot : u8 at $21

; ------------------------------------------------------------------------------
; pointer: pObj = the record for slot A. Clobbers A, X.
; ------------------------------------------------------------------------------
proc pointer using console6502
    result : ptr CelesteObject return in Machine.object
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
    #d8 0, Room.tile_spawn, 0, 0, 18, 22, 23, 26, 28, 0, 64, 8, 20, 0
type_init_lo:
    data u8 low(Player.init), low(Spawn.init), low(Smoke.init), low(Title.init)
    data u8 low(Spring.init), low(Ball.init), low(Floor.init), low(Fruit.init)
    data u8 low(Fly.init), low(Life.init), low(noop), low(noop), low(Chest.init), low(Mover.init)
type_init_hi:
    data u8 high(Player.init), high(Spawn.init), high(Smoke.init), high(Title.init)
    data u8 high(Spring.init), high(Ball.init), high(Floor.init), high(Fruit.init)
    data u8 high(Fly.init), high(Life.init), high(noop), high(noop), high(Chest.init), high(Mover.init)
type_update_lo:
    data u8 low(Player.update), low(Spawn.update), low(Smoke.update), low(Title.update)
    data u8 low(Spring.update), low(Ball.update), low(Floor.update), low(Fruit.update)
    data u8 low(Fly.update), low(Life.update), low(Wall.update), low(Key.update)
    data u8 low(Chest.update), low(Mover.update)
type_update_hi:
    data u8 high(Player.update), high(Spawn.update), high(Smoke.update), high(Title.update)
    data u8 high(Spring.update), high(Ball.update), high(Floor.update), high(Fruit.update)
    data u8 high(Fly.update), high(Life.update), high(Wall.update), high(Key.update)
    data u8 high(Chest.update), high(Mover.update)
type_draw_lo:
    data u8 low(Player.draw), low(Spawn.draw), low(Smoke.draw), low(Title.draw)
    data u8 low(Spring.draw), low(Ball.draw), low(Floor.draw), low(Fruit.draw)
    data u8 low(Fly.draw), low(Life.draw), low(Wall.draw), low(Key.draw)
    data u8 low(Chest.draw), low(Mover.draw)
type_draw_hi:
    data u8 high(Player.draw), high(Spawn.draw), high(Smoke.draw), high(Title.draw)
    data u8 high(Spring.draw), high(Ball.draw), high(Floor.draw), high(Fruit.draw)
    data u8 high(Fly.draw), high(Life.draw), high(Wall.draw), high(Key.draw)
    data u8 high(Chest.draw), high(Mover.draw)

; Marker tiles present in playable rooms 0-9. Animation-only sprite ids do not
; appear here; the generator's content manifest owns those art dependencies.
marker_tile:
    #d8 1, 8, 11, 12, 18, 20, 22, 23, 26, 28, 64
marker_kind:
    #d8 2, 12, 14, 14            ; spawn, key, platform left/right
    #d8 5, 13, 6, 7              ; spring, chest, balloon, fall floor
    #d8 8, 9, 11                 ; fruit, flying fruit, fake wall
type_hide:
    #d8 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 0

proc noop using console6502 naked
begin
    ret
end

; ------------------------------------------------------------------------------
; spawn_marker: A is a cart marker tile; spawn_x/spawn_y are its pixel position.
; Unknown markers are ignored. Objects hidden after this room's strawberry has
; been collected follow the cart's `if_not_fruit` rule.
; ------------------------------------------------------------------------------
proc spawn_marker using console6502
begin
    sta Machine.t7
    ldx #0
.find:
    cmp marker_tile, x
    beq .found
    inx
    cpx #11
    bne .find
    ret
.found:
    lda marker_kind, x
    sta spawn_type
    tax
    lda type_hide-1, x
    beq .allocate
    jsr Berries.collected
    bne .done
.allocate:
    jsr allocate
    lda spawn_slot
    bmi .done
    lda Machine.t7
    cmp #11
    beq .left
    cmp #12
    bne .done
    lda #1
    bne .platform
.left:
    lda #$FF
.platform:
    sta [Machine.object.payload.extra.value]
    jsr Mover.configure
.done:
    ret
end

; ------------------------------------------------------------------------------
; clear: empty the pool. Inputs: none. Returns: none. Clobbers: A, X, Y.
; ------------------------------------------------------------------------------
proc clear using console6502
begin
    lda #0
    ldx #slot_count-1
.slot:
    txa
    pha
    jsr pointer
    lda #0
    sta [Machine.object.core.kind]
    pla
    tax
    lda #0
    sta [object_index.kinds[x]]
    dex
    bpl .slot
    ldx #15
    lda #0
.counts:
    sta [object_index.counts[x]]
    dex
    bpl .counts
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
    result : ptr CelesteObject return in Machine.object
begin
    ldx #0
.find:
    txa
    jsr pointer
    lda [Machine.object.core.kind]
    beq .found
    inx
    cpx #slot_count
    bne .find
    lda #$FF                    ; pool full: the cart has no such case, this
    sta spawn_slot              ; console does. Dropping the object is the only
    rts                         ; option that cannot corrupt the list.
.found:
    stx spawn_slot

    mov y, #CelesteObject.size-1 ; a fresh record starts empty, so every field
    lda #0                      ; the type does not set reads as the cart's nil
.clear:
    sta (Machine.object), y
    dey
    bpl .clear

    lda spawn_type
    sta [Machine.object.core.kind]
    tax
    lda [object_index.counts[x]]
    add #1
    sta [object_index.counts[x]]
    ldx spawn_slot
    lda spawn_type
    sta [object_index.kinds[x]]
    tax
    lda type_tile-1, x   ; obj.spr = type.tile
    sta [Machine.object.core.sprite]
    lda spawn_x
    sta [Machine.object.core.x]
    lda spawn_y
    sta [Machine.object.core.y]

    lda #8                      ; the cart's default hitbox {0,0,8,8}
    sta [Machine.object.core.hitbox.w]
    sta [Machine.object.core.hitbox.h]
    lda #flag_collideable|flag_solids
    mov y, offset CelesteObject.core.flags
    sta (Machine.object), y

    lda spawn_type              ; type.init(this)
    tax
    lda type_init_lo-1, x
    sta Machine.function
    lda type_init_hi-1, x
    sta Machine.function+1
    ora Machine.function
    beq .noinit
    jsr dispatch
.noinit:
    ret
end

; ------------------------------------------------------------------------------
; dispatch: jmp (pFn) as a subroutine, so the method's rts returns to our
; caller. Input: pFn. Receiver: pObj. Clobbers: callee-defined.
; ------------------------------------------------------------------------------
proc dispatch using console6502 naked
begin
    jmp (Machine.function)
end

; ------------------------------------------------------------------------------
; spawn_smoke: the cart's object constructor for smoke, used eight times in
; the player alone. The caller's receiver is an explicit frame local rather
; than a handwritten hardware-stack convention.
; ------------------------------------------------------------------------------
proc spawn_smoke using console6502
    self : ptr CelesteObject in Machine.object
    x_position : i8 in a
    y_position : i8 in x
    saved_self : ptr CelesteObject in frame
begin
    sta spawn_x
    stx spawn_y
    mov spawn_type, #ObjectKind.smoke
    mov [saved_self], self
    jsr allocate
    mov self, [saved_self]
    ret
end

; ------------------------------------------------------------------------------
; destroy: free the record pObj points at and unindex it. The slot is derived
; from the pointer (four page-aligned records per page), so callers that hold
; only the receiver need not know its slot. A second destroy of the same
; record is a no-op rather than a count underflow. Clobbers A, X, Y, t3 -
; the chest and player-death sites carry x/y across this call in t6/t7.
; ------------------------------------------------------------------------------
proc destroy using console6502
    self : ptr CelesteObject in Machine.object
begin
    mov y, offset CelesteObject.core.kind
    lda (Machine.object), y
    beq .freed
    tax
    lda [object_index.counts[x]]
    sub #1
    sta [object_index.counts[x]]
    lda Machine.object+1        ; slot = (page - pool base page) * 4
    sub #(OBJPOOL >> 8)
    asl a, 2
    sta Machine.t3
    lda Machine.object          ;      + (low byte >> 6)
    lsr a, 6
    add Machine.t3
    tax
    lda #0
    sta [object_index.kinds[x]]
    sta [Machine.object.core.kind]
.freed:
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
    mov slot, #0
.loop:
    ldx slot                ; dead slots skip without touching the record
    lda [object_index.kinds[x]]
    beq .next
    lda slot
    jsr pointer

    jsr move            ; obj.move(obj.spd.x, obj.spd.y)

    lda slot                ; the object may have been destroyed by its own
    jsr pointer         ; move (nothing in stage 1 does, but reloading
    lda [Machine.object.core.kind] ; cheaper than proving it cannot)
    beq .next
    tax
    lda type_update_lo-1, x
    sta Machine.function
    lda type_update_hi-1, x
    sta Machine.function+1
    ora Machine.function
    beq .next
    jsr dispatch
.next:
    inc slot
    cbne slot, #slot_count, .loop
    ret
end

; ------------------------------------------------------------------------------
; draw_all: traverse live records and dispatch each draw lifecycle method.
; Inputs: none. Returns: none. Clobbers: A, X, Y, pObj, pFn and obj_slot.
; ------------------------------------------------------------------------------
proc draw_all using console6502
begin
    mov slot, #0
.loop:
    ldx slot                ; dead slots skip without touching the record
    lda [object_index.kinds[x]]
    beq .next
    lda slot
    jsr pointer
    lda [Machine.object.core.kind]
    tax
    lda type_draw_lo-1, x
    sta Machine.function
    lda type_draw_hi-1, x
    sta Machine.function+1
    ora Machine.function
    beq .next
    jsr dispatch
.next:
    inc slot
    cbne slot, #slot_count, .loop
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
    self : ptr CelesteObject in Machine.object
    value : u16 in Fixed.word0
    operand : u16 in Fixed.word1
begin
    ; A truly stationary object cannot change position or motion state here.
    ; Avoid the fixed-point work and, more importantly, the zero-distance
    ; solid checks: room 3 has twelve fall floors, and each otherwise scans the
    ; object pool against the other floors once per axis despite never moving.
    mov y, offset CelesteObject.core.speed_x.fraction
    lda (Machine.object), y
    iny
    ora (Machine.object), y
    iny
    ora (Machine.object), y
    iny
    ora (Machine.object), y
    iny
    ora (Machine.object), y
    iny
    ora (Machine.object), y
    iny
    ora (Machine.object), y
    iny
    ora (Machine.object), y
    bne .moving
    ret

.moving:
    ldw value, [self.core.remainder_x] ; rem.x += spd.x
    ldw operand, [self.core.speed_x]
    ldab Fixed.word0
    addw ab, operand
    stab Fixed.word0
    stw [self.core.remainder_x], value

    movw Fixed.word1, #$0080    ; amount = flr(rem.x + 0.5)
    jsr Fixed.add
    lda Fixed.word0+1
    sta Machine.t0

    mov y, offset CelesteObject.core.remainder_x.integer ; inlay-exception: variable update operand t0
    lda (Machine.object), y               ; rem.x -= amount, in the high half only
    sub Machine.t0
    sta (Machine.object), y

    jsr step_x

    ldw value, [self.core.remainder_y] ; and the same for y
    ldw operand, [self.core.speed_y]
    ldab Fixed.word0
    addw ab, operand
    stab Fixed.word0
    stw [self.core.remainder_y], value

    movw Fixed.word1, #$0080
    jsr Fixed.add
    lda Fixed.word0+1
    sta Machine.t0

    mov y, offset CelesteObject.core.remainder_y.integer ; inlay-exception: variable update operand t0
    lda (Machine.object), y
    sub Machine.t0
    sta (Machine.object), y

    jmp step_y
end

; ------------------------------------------------------------------------------
; prepare_step: turn signed amount t0 into step t1 and inclusive count t2.
; This physical helper is shared by both collision axes.
; ------------------------------------------------------------------------------
proc prepare_step using console6502 naked
    amount : i8 in Machine.t0
    step : i8 return in Machine.t1
    remaining : u8 return in Machine.t2
begin
    lda Machine.t0
    bmi .negative
    beq .zero
    mov Machine.t1, #1
    sta Machine.t2
    ret
.negative:
    mov Machine.t1, #$FF
    lda #0
    sub Machine.t0
    sta Machine.t2
    ret
.zero:
    sta Machine.t1
    sta Machine.t2
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
    self : ptr CelesteObject in Machine.object
    amount : i8 in Machine.t0
begin
    lda [Machine.object.core.flags]
    and #flag_solids
    bne .solid

    mov y, offset CelesteObject.core.x ; inlay-exception: variable update operand t0
    lda (Machine.object), y                    ; not solid: x += amount, no collision at all
    add Machine.t0
    sta (Machine.object), y
    rts

.solid:
    jsr prepare_step

.loop:
    lda Machine.t1                      ; is_solid(step, 0)
    sta Collision.offset_x
    mov Collision.offset_y, #0
    jsr Collision.solid
    bne .blocked

    mov y, offset CelesteObject.core.x ; inlay-exception: variable update operand t1
    lda (Machine.object), y
    add Machine.t1
    sta (Machine.object), y

    dec Machine.t2                      ; inclusive loop: t2 counts down through zero
    bpl .loop
    rts

.blocked:
    stw [Machine.object.core.speed_x], #0 ; spd.x = 0, rem.x = 0
    stw [Machine.object.core.remainder_x], #0
    ret
end

; ------------------------------------------------------------------------------
; step_y: the same, vertically. Clobbers A, X, Y, t1, t2.
; ------------------------------------------------------------------------------
proc step_y using console6502
    self : ptr CelesteObject in Machine.object
    amount : i8 in Machine.t0
begin
    lda [Machine.object.core.flags]
    and #flag_solids
    bne .solid

    mov y, offset CelesteObject.core.y ; inlay-exception: variable update operand t0
    lda (Machine.object), y
    add Machine.t0
    sta (Machine.object), y
    rts

.solid:
    jsr prepare_step

.loop:
    mov Collision.offset_x, #0
    lda Machine.t1
    sta Collision.offset_y
    jsr Collision.solid
    bne .blocked

    mov y, offset CelesteObject.core.y ; inlay-exception: variable update operand t1
    lda (Machine.object), y
    add Machine.t1
    sta (Machine.object), y

    dec Machine.t2
    bpl .loop
    rts

.blocked:
    stw [Machine.object.core.speed_y], #0
    stw [Machine.object.core.remainder_y], #0
    ret
end
end
