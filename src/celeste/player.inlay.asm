; Celeste - the player, the spawn animation, smoke and the room title
;
; State that remains live across the split procedures belongs to Player's
; explicit physical scratch block at $50-$5f. It is neither a hidden virtual
; value nor a procedure-local frame with the wrong lifetime.
namespace Player
    export init
    export update
    export draw
; 8.8 constants. Every one of them is the cart's own number, rounded to 1/256.
    max_run = $0100   ; 1
    accel_ground = $009A   ; 0.6
    accel_air = $0066   ; 0.4
    accel_ice = $000D   ; 0.05
    deceleration = $0026   ; 0.15
    max_fall = $0200   ; 2
    fall_slide = $0066   ; 0.4
    gravity = $0036   ; 0.21
    gravity_half = $001B   ; 0.105, the <=0.15 apex case
    y_epsilon = $0026   ; 0.15
    jump_speed = $FE00   ; -2
    wall_jump = $0200   ; maxrun + 1
    dash_full = $0500   ; 5
    dash_half = $0389   ; 5 * sqrt(2)/2 = 3.5355
    dash_target = $0200   ; 2
    dash_target_up = $0180   ; 2 * 0.75, when dashing upward
    dash_accel = $0180   ; 1.5
    dash_accel_diag = $010F
    bit_jump = $01
    bit_dash = $02
    bit_ground = $04
; Player-owned persistent scratch, deliberately shared by update subprocedures.
    input = $50
    ground = $51
    ice = $52
    jump_edge = $53
    dash_edge = $54
    maxrun = $55
    accel = $56
    decel_word = $58
    maxfall = $5A
    grav = $5C
    vinput = $5E
    wall = $5F
; Player.init
proc init using console6502
    self : ptr CelesteObject in pObj
begin
    lda #1                      ; hitbox = {1,3,6,5}
    sta [pObj + CelesteObject.core.hitbox.x]
    lda #3
    sta [pObj + CelesteObject.core.hitbox.y]
    lda #6
    sta [pObj + CelesteObject.core.hitbox.w]
    lda #5
    sta [pObj + CelesteObject.core.hitbox.h]
    lda max_djump
    sta [pObj + CelesteObject.payload.player.dash_jumps]
    lda #1
    sta [pObj + CelesteObject.core.sprite]
    jmp Player.create_hair
; Player.update
end
proc update using console6502
    self : ptr CelesteObject in pObj
begin
    lda pause_player
    beq .go
    ret
.go:
    jmp Player.sample_input
end
; Input: self in pObj. Output: Player.input. Clobbers: A.
proc sample_input using console6502
    self : ptr CelesteObject in pObj
begin
    tbz btn, #BTN_R, .noright  ; input = right and 1 or (left and -1 or 0)
    lda #1
    bne .haveinput
.noright:
    tbz btn, #BTN_L, .noinput
    lda #$FF
    bne .haveinput
.noinput:
    lda #0
.haveinput:
    sta Player.input
    jmp Player.environment
end
; Input: self in pObj. Outputs: owned ground/ice/edge/grace state.
; Clobbers: A, X, Y and collision scratch.
proc environment using console6502
    self : ptr CelesteObject in pObj
begin
    lda #0                      ; spikes collide
    sta c_ox
    sta c_oy
    jsr obj_box
    jsr spikes_at
    beq .nospike
    jmp Player.kill
.nospike:
    lda [pObj + CelesteObject.core.y]  ; port's positions are signed bytes, so the
    bmi .notbottom              ; test moves 8 pixels up rather than wrapping
    cmp #121                    ; into "above the room", which is next_room -
    bcc .notbottom              ; and the sign has to be tested BEFORE the
    jmp Player.kill             ; compare, not from its flags.
.notbottom:
    mov c_ox, #0
    mov c_oy, #1
    jsr is_solid
    sta Player.ground
    mov c_ox, #0
    mov c_oy, #1
    jsr is_ice
    sta Player.ice
    lda Player.ground              ; landing smoke
    beq .nosmoke
    mov y, offset CelesteObject.payload.player.player_bits ; inlay-exception: mask constant remains target-owned
    lda (pObj), y
    and #Player.bit_ground
    bne .nosmoke
    lda [pObj + CelesteObject.core.x]
    pha
    lda [pObj + CelesteObject.core.y]
    add #4
    tax
    pla
    jsr Objects.spawn_smoke
.nosmoke:
    tbz btn, #BTN_JUMP, .nojumpheld  ; jump = btn(jump) and not Player.jump_edge
    mov y, offset CelesteObject.payload.player.player_bits ; inlay-exception: complemented target constant
    lda (pObj), y
    and #Player.bit_jump
    bne .jumpheld
    mov Player.jump_edge, #1
    mov y, offset CelesteObject.payload.player.player_bits ; inlay-exception: mask constant remains target-owned
    lda (pObj), y
    ora #Player.bit_jump
    sta (pObj), y
    jmp .jbuf
.jumpheld:
    mov Player.jump_edge, #0
    jmp .jbufdec
.nojumpheld:
    mov Player.jump_edge, #0
    mov y, offset CelesteObject.payload.player.player_bits ; inlay-exception: complemented target constant
    lda (pObj), y
    and #<!Player.bit_jump
    sta (pObj), y
.jbufdec:
    mov y, offset CelesteObject.payload.player.jump_buffer ; inlay-exception: branch observes pre-decrement value
    lda (pObj), y
    beq .dashedge
    sub #1
    sta (pObj), y
    jmp .dashedge
.jbuf:
    lda #4
    sta [pObj + CelesteObject.payload.player.jump_buffer]
.dashedge:
    tbz btn, #BTN_DASH, .nodashheld  ; dash = btn(dash) and not Player.dash_edge
    mov y, offset CelesteObject.payload.player.player_bits ; inlay-exception: mask constant remains target-owned
    lda (pObj), y
    and #Player.bit_dash
    bne .dashheld
    mov Player.dash_edge, #1
    mov y, offset CelesteObject.payload.player.player_bits ; inlay-exception: complemented target constant
    lda (pObj), y
    ora #Player.bit_dash
    sta (pObj), y
    jmp .grace
.dashheld:
    mov Player.dash_edge, #0
    jmp .grace
.nodashheld:
    mov Player.dash_edge, #0
    mov y, offset CelesteObject.payload.player.player_bits ; inlay-exception: complemented target constant
    lda (pObj), y
    and #<!Player.bit_dash
    sta (pObj), y
.grace:
    lda Player.ground
    beq .airborne
    lda #6
    sta [pObj + CelesteObject.payload.player.grace]
    lda [pObj + CelesteObject.payload.player.dash_jumps]
    cmp max_djump
    bcs .gracedone
    lda #54
    jsr psfx
    lda max_djump
    sta [pObj + CelesteObject.payload.player.dash_jumps]
    jmp .gracedone
.airborne:
    mov y, offset CelesteObject.payload.player.grace ; inlay-exception: branch observes pre-decrement value
    lda (pObj), y
    beq .gracedone
    sub #1
    sta (pObj), y
.gracedone:
    jmp Player.active_dash
end
; Input: self in pObj and owned environment state. Returns through either
; Player.horizontal or Player.animation. Clobbers: A, X, Y and w0-w2.
proc active_dash using console6502
    self : ptr CelesteObject in pObj
begin
    dec [pObj + CelesteObject.payload.player.dash_effect] ; dash_effect_time -= 1
    mov y, offset CelesteObject.payload.player.dash_time
    lda (pObj), y                ; if dash_time > 0 then ... else move
    beq .move
    jmp .dashing
.move:
    jmp Player.horizontal
.dashing:
    sub #1
    sta (pObj), y
    lda [pObj + CelesteObject.core.x]                    ; a smoke puff per dash frame
    pha
    lda [pObj + CelesteObject.core.y]
    tax
    pla
    jsr Objects.spawn_smoke
    mov y, offset CelesteObject.core.speed_x                 ; spd.x = Fixed.approach(spd.x, dash_target.x, dash_accel.x)
    jsr Fixed.load_object
    mov y, offset CelesteObject.payload.player.dash_target_x
    jsr Fixed.load_object_target
    mov y, offset CelesteObject.payload.player.dash_accel_x.fraction
    lda (pObj), y
    sta w2
    iny
    lda (pObj), y
    sta w2+1
    jsr Fixed.approach
    mov y, offset CelesteObject.core.speed_x
    jsr Fixed.store_object
    mov y, offset CelesteObject.core.speed_y
    jsr Fixed.load_object
    mov y, offset CelesteObject.payload.player.dash_target_y
    jsr Fixed.load_object_target
    mov y, offset CelesteObject.payload.player.dash_accel_y.fraction
    lda (pObj), y
    sta w2
    iny
    lda (pObj), y
    sta w2+1
    jsr Fixed.approach
    mov y, offset CelesteObject.core.speed_y
    jsr Fixed.store_object
    jmp Player.animation
; The cart's `else` branch: run, gravity, wall slide, jump, dash.
end
proc horizontal using console6502
    self : ptr CelesteObject in pObj
begin
    mov Player.maxrun, #<Player.max_run
    mov Player.accel, #<Player.accel_ground
    mov Player.accel+1, #>Player.accel_ground
    mov Player.decel_word, #<Player.deceleration
    mov Player.decel_word+1, #>Player.deceleration
    lda Player.ground
    bne .grounded
    mov Player.accel, #<Player.accel_air
    mov Player.accel+1, #>Player.accel_air
    jmp .run
.grounded:
    lda Player.ice
    beq .run
    mov Player.accel, #<Player.accel_ice
    mov Player.accel+1, #>Player.accel_ice
.run:
    lda #<Player.max_run                ; if abs(spd.x) > maxrun then decelerate
    ldx #>Player.max_run
    jsr Fixed.set_value
    mov y, offset CelesteObject.core.speed_x
    jsr Fixed.load_object_target
    lda w1+1
    bpl .absdone
    ldab #$0000  ; w1 = abs(spd.x), inline because Fixed.negate works
    subw w1
    stab w1
.absdone:
    jsr Fixed.compare                   ; N set: maxrun < abs(spd.x)
    bpl .accelerate
    mov y, offset CelesteObject.core.speed_x                 ; spd.x = Fixed.approach(spd.x, sign(spd.x)*maxrun, deccel)
    jsr Fixed.load_object
    lda w0+1
    bmi .decelneg
    lda #<Player.max_run
    ldx #>Player.max_run
    jsr Fixed.set_target
    jmp .decel
.decelneg:
    lda #<(-Player.max_run & $FFFF)
    ldx #>(-Player.max_run & $FFFF)
    jsr Fixed.set_target
.decel:
    lda Player.decel_word
    ldx Player.decel_word+1
    jsr Fixed.set_amount
    jsr Fixed.approach
    mov y, offset CelesteObject.core.speed_x
    jsr Fixed.store_object
    jmp .facing
.accelerate:                    ; spd.x = Fixed.approach(spd.x, input*maxrun, accel)
    mov y, offset CelesteObject.core.speed_x
    jsr Fixed.load_object
    lda Player.input
    beq .targetzero
    bmi .targetneg
    lda #<Player.max_run
    ldx #>Player.max_run
    jsr Fixed.set_target
    jmp .doaccel
.targetneg:
    lda #<(-Player.max_run & $FFFF)
    ldx #>(-Player.max_run & $FFFF)
    jsr Fixed.set_target
    jmp .doaccel
.targetzero:
    lda #0
    tax
    jsr Fixed.set_target
.doaccel:
    lda Player.accel
    ldx Player.accel+1
    jsr Fixed.set_amount
    jsr Fixed.approach
    mov y, offset CelesteObject.core.speed_x
    jsr Fixed.store_object
.facing:
    mov y, offset CelesteObject.core.speed_x.fraction
    lda (pObj), y                 ; if spd.x != 0 then flip.x = spd.x < 0
    iny
    ora (pObj), y
    beq .done
    lda [pObj + CelesteObject.core.speed_x.integer]
    bmi .faceleft
    mov y, offset CelesteObject.core.flip ; inlay-exception: following flags feed control flow
    lda (pObj), y
    and #$FE
    sta (pObj), y
    jmp .done
.faceleft:
    mov y, offset CelesteObject.core.flip ; inlay-exception: following flags feed control flow
    lda (pObj), y
    ora #$01
    sta (pObj), y
.done:
    jmp Player.vertical
end
; Input: self and owned environment state. Updates vertical speed/wall slide.
; Clobbers: A, X, Y, w0-w2 and collision scratch.
proc vertical using console6502
    self : ptr CelesteObject in pObj
begin
    mov Player.maxfall, #<Player.max_fall
    mov Player.maxfall+1, #>Player.max_fall
    mov Player.grav, #<Player.gravity
    mov Player.grav+1, #>Player.gravity
    mov y, offset CelesteObject.core.speed_y                 ; if abs(spd.y) <= 0.15 then gravity *= 0.5
    jsr Fixed.load_object
    jsr Fixed.absolute
    lda #<Player.y_epsilon
    ldx #>Player.y_epsilon
    jsr Fixed.set_target
    jsr Fixed.compare                   ; N set: abs(spd.y) < 0.15
    bmi .halfgrav
    cbne w0, #<Player.y_epsilon, .slide  ; the cart's test is <=, so catch equality too
    cbne w0+1, #>Player.y_epsilon, .slide
.halfgrav:
    mov Player.grav, #<Player.gravity_half
    mov Player.grav+1, #>Player.gravity_half
.slide:                         ; wall slide
    lda Player.input
    beq .fall
    sta c_ox
    mov c_oy, #0
    jsr is_solid
    beq .fall
    lda Player.input
    sta c_ox
    mov c_oy, #0
    jsr is_ice
    bne .fall
    mov Player.maxfall, #<Player.fall_slide
    mov Player.maxfall+1, #>Player.fall_slide
    lda [video + VideoRegisters.random]                 ; if rnd(10) < 2 then a puff off the wall
    cmp #51
    bcs .fall
    lda [pObj + CelesteObject.core.x]
    add Player.input  ; x + input*6, by adding input six times rather
    add Player.input
    add Player.input
    add Player.input
    add Player.input
    add Player.input
    pha
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    tax
    pla
    jsr Objects.spawn_smoke
.fall:
    lda Player.ground
    bne .done
    mov y, offset CelesteObject.core.speed_y                 ; spd.y = Fixed.approach(spd.y, maxfall, gravity)
    jsr Fixed.load_object
    lda Player.maxfall
    ldx Player.maxfall+1
    jsr Fixed.set_target
    lda Player.grav
    ldx Player.grav+1
    jsr Fixed.set_amount
    jsr Fixed.approach
    mov y, offset CelesteObject.core.speed_y
    jsr Fixed.store_object
.done:
    jmp Player.jump_dash
end
; Input: self and owned input/environment state. Performs jump and dash
; transitions. Clobbers: A, X, Y, w0-w2 and collision scratch.
proc jump_dash using console6502
    self : ptr CelesteObject in pObj
begin
    lda [pObj + CelesteObject.payload.player.jump_buffer]
    bne .wantjump
    jmp .dash
.wantjump:
    lda [pObj + CelesteObject.payload.player.grace]
    beq .walljump
    lda #1                      ; normal jump
    jsr psfx
    lda #0
    sta [pObj + CelesteObject.payload.player.jump_buffer]
    sta [pObj + CelesteObject.payload.player.grace]
    lda #<Player.jump_speed
    mov y, offset CelesteObject.core.speed_y.fraction
    sta (pObj), y
    lda #>Player.jump_speed
    iny
    sta (pObj), y
    lda [pObj + CelesteObject.core.x]
    pha
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    add #4
    tax
    pla
    jsr Objects.spawn_smoke
    jmp .dash
.walljump:                      ; wall_dir = is_solid(-3,0) and -1 or is_solid(3,0) and 1 or 0
    mov c_ox, #$FD
    mov c_oy, #0
    jsr is_solid
    beq .wallright
    mov Player.wall, #$FF
    jmp .havewall
.wallright:
    mov c_ox, #3
    mov c_oy, #0
    jsr is_solid
    beq .dash
    mov Player.wall, #1
.havewall:
    lda #2
    jsr psfx
    lda #0
    sta [pObj + CelesteObject.payload.player.jump_buffer]
    lda #<Player.jump_speed
    mov y, offset CelesteObject.core.speed_y.fraction
    sta (pObj), y
    lda #>Player.jump_speed
    iny
    sta (pObj), y
    lda Player.wall               ; spd.x = -wall_dir * (maxrun + 1)
    bmi .wjright
    lda #<(-Player.wall_jump & $FFFF)
    ldx #>(-Player.wall_jump & $FFFF)
    jmp .wjset
.wjright:
    lda #<Player.wall_jump
    ldx #>Player.wall_jump
.wjset:
    mov y, offset CelesteObject.core.speed_x.fraction
    sta (pObj), y
    txa
    iny
    sta (pObj), y
    lda Player.wall               ; the puff, unless the wall is ice
    asl
    asl
    add Player.wall  ; wall_dir * 5 ... the cart tests ice at *3
    sta c_ox                    ; and puffs at *6; close enough is not enough,
    lda Player.wall               ; so both are spelled out
    asl
    add Player.wall
    sta c_ox                    ; wall_dir * 3
    mov c_oy, #0
    jsr is_ice
    bne .dash
    lda [pObj + CelesteObject.core.x]
    add Player.wall
    add Player.wall
    add Player.wall
    add Player.wall
    add Player.wall
    add Player.wall
    pha
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    tax
    pla
    jsr Objects.spawn_smoke
.dash:
    lda Player.dash_edge
    beq .nodash
    lda [pObj + CelesteObject.payload.player.dash_jumps]
    bne .dodash
    lda #9                      ; out of dashes: a puff and a raspberry
    jsr psfx
    lda [pObj + CelesteObject.core.x]
    pha
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    tax
    pla
    jsr Objects.spawn_smoke
.nodash:
    jmp Player.animation
.dodash:
    lda [pObj + CelesteObject.core.x]
    pha
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    tax
    pla
    jsr Objects.spawn_smoke
    dec [pObj + CelesteObject.payload.player.dash_jumps]
    lda #4
    sta [pObj + CelesteObject.payload.player.dash_time]
    mov has_dashed, #1
    lda #10
    sta [pObj + CelesteObject.payload.player.dash_effect]
    tbz btn, #BTN_U, .notup  ; v_input
    lda #$FF
    bne .havev
.notup:
    tbz btn, #BTN_D, .nov
    lda #1
    bne .havev
.nov:
    lda #0
.havev:
    sta Player.vinput
    lda Player.input
    beq .vonly
    lda Player.vinput
    beq .honly
    lda Player.input                 ; diagonal: both axes at d_half
    ldx #<Player.dash_half
    ldy #>Player.dash_half
    jsr Player.set_speed_x_signed
    lda Player.vinput
    ldx #<Player.dash_half
    ldy #>Player.dash_half
    jsr Player.set_speed_y_signed
    jmp .dashdone
.honly:
    lda Player.input
    ldx #<Player.dash_full
    ldy #>Player.dash_full
    jsr Player.set_speed_x_signed
    lda #0
    ldx #0
    ldy #0
    jsr Player.set_speed_y_signed
    jmp .dashdone
.vonly:
    lda Player.vinput
    beq .neutral
    lda #0
    ldx #0
    ldy #0
    jsr Player.set_speed_x_signed
    lda Player.vinput
    ldx #<Player.dash_full
    ldy #>Player.dash_full
    jsr Player.set_speed_y_signed
    jmp .dashdone
.neutral:                       ; no direction held: the cart dashes at 1 px/frame
    lda [pObj + CelesteObject.core.flip]
    and #$01
    beq .neutralright
    lda #$FF
    jmp .neutralset
.neutralright:
    lda #1
.neutralset:
    ldx #<Player.max_run
    ldy #>Player.max_run
    jsr Player.set_speed_x_signed
    lda #0
    ldx #0
    ldy #0
    jsr Player.set_speed_y_signed
.dashdone:
    lda #3
    jsr psfx
    mov freeze, #2
    mov shake, #6
    mov y, offset CelesteObject.core.speed_x                 ; dash_target = 2 * sign(spd), dash_accel = 1.5
    jsr Fixed.load_object
    jsr Fixed.sign
    ldx #<Player.dash_target
    ldy #>Player.dash_target
    jsr Player.signed_word
    mov y, offset CelesteObject.payload.player.dash_target_x
    jsr Fixed.store_object
    mov y, offset CelesteObject.core.speed_y
    jsr Fixed.load_object
    jsr Fixed.sign
    ldx #<Player.dash_target
    ldy #>Player.dash_target
    jsr Player.signed_word
    mov y, offset CelesteObject.payload.player.dash_target_y
    jsr Fixed.store_object
    mov y, offset CelesteObject.core.speed_y.fraction
    lda (pObj), y                 ; if spd.y < 0 then dash_target.y *= 0.75
    iny
    ora (pObj), y
    beq .yzero
    lda [pObj + CelesteObject.core.speed_y.integer]
    bpl .ynonzero
    lda #<(-Player.dash_target_up & $FFFF)
    mov y, offset CelesteObject.payload.player.dash_target_y.fraction
    sta (pObj), y
    lda #>(-Player.dash_target_up & $FFFF)
    iny
    sta (pObj), y
.ynonzero:
    lda #<Player.dash_accel_diag       ; spd.y != 0: dash_accel.x *= sqrt(2)/2
    ldx #>Player.dash_accel_diag
    jmp .setax
.yzero:
    lda #<Player.dash_accel
    ldx #>Player.dash_accel
.setax:
    mov y, offset CelesteObject.payload.player.dash_accel_x.fraction
    sta (pObj), y
    txa
    iny
    sta (pObj), y
    mov y, offset CelesteObject.core.speed_x.fraction
    lda (pObj), y                 ; spd.x != 0: dash_accel.y *= sqrt(2)/2
    iny
    ora (pObj), y
    beq .xzero
    lda #<Player.dash_accel_diag
    ldx #>Player.dash_accel_diag
    jmp .setay
.xzero:
    lda #<Player.dash_accel
    ldx #>Player.dash_accel
.setay:
    mov y, offset CelesteObject.payload.player.dash_accel_y.fraction
    sta (pObj), y
    txa
    iny
    sta (pObj), y
    jmp Player.animation
end
; Animation, the level exit, and the ground latch.
proc animation using console6502
    self : ptr CelesteObject in pObj
begin
    mov y, offset CelesteObject.payload.player.sprite_offset ; inlay-exception: wrapping add-and-mask update
    lda (pObj), y               ; spr_off += 0.25, in quarter frames
    add #1
    and #15
    sta (pObj), y
    lda Player.ground
    bne .onground
    lda Player.input                 ; airborne: 5 against a wall, 3 otherwise
    sta c_ox
    mov c_oy, #0
    jsr is_solid
    beq .air
    lda #5
    jmp .setspr
.air:
    lda #3
    jmp .setspr
.onground:
    tbz btn, #BTN_D, .notdown
    lda #6
    jmp .setspr
.notdown:
    tbz btn, #BTN_U, .notup
    lda #7
    jmp .setspr
.notup:
    mov y, offset CelesteObject.core.speed_x.fraction
    lda (pObj), y                 ; standing still, or no key held: frame 1
    iny
    ora (pObj), y
    beq .still
    tbz btn, #BTN_L|BTN_R, .still
    lda [pObj + CelesteObject.payload.player.sprite_offset]
    lsr
    lsr
    add #1
    jmp .setspr
.still:
    lda #1
.setspr:
    sta [pObj + CelesteObject.core.sprite]
    mov y, offset CelesteObject.core.y
    lda (pObj), y                    ; if y < -4 then next_room()
    bpl .stay
    cmp #$FC
    bcs .stay
    jsr next_room
    rts
.stay:
    lda [pObj + CelesteObject.payload.player.player_bits]
    and #<!Player.bit_ground
    ldy Player.ground
    beq .nolatch
    ora #Player.bit_ground
.nolatch:
    sta [pObj + CelesteObject.payload.player.player_bits]
    ret
end
; Player.set_speed_x_signed / Player.set_speed_y_signed: spd = A * {X,Y}, where A is -1, 0 or 1.
; The cart writes `input * d_full`; with a sign for a multiplier that is a
; select, not a multiply.
proc set_speed_x_signed using console6502 naked
    self : ptr CelesteObject in pObj
    sign : i8 in a
    low : u8 in x
    high : u8 in y
begin
    jsr Player.signed_word
    mov y, offset CelesteObject.core.speed_x
    jmp Fixed.store_object
end
proc set_speed_y_signed using console6502 naked
    self : ptr CelesteObject in pObj
    sign : i8 in a
    low : u8 in x
    high : u8 in y
begin
    jsr Player.signed_word
    mov y, offset CelesteObject.core.speed_y
    jmp Fixed.store_object
end
; Player.signed_word: w0 = A * {X,Y} for A in {-1, 0, 1}. Clobbers A.
proc signed_word using console6502 naked
    sign : i8 in a
    low : u8 in x
    high : u8 in y
    value : u16 return in w0
begin
    stx w0
    sty w0+1
    cmp #0
    beq .zero
    bpl .done
    jmp Fixed.negate
.zero:
    ldab #$0000
    stab w0
.done:
    ret
end
; Player owns the hair lifecycle surface; Draw provides the private staging
; implementation until the drawing subsystem is scoped in phase 10.
proc create_hair using console6502 naked
    self : ptr CelesteObject in pObj
begin
    jmp player_hair_create_impl
end
proc set_hair_color using console6502 naked
    dash_jumps : u8 in a
begin
    jmp player_hair_color_impl
end
proc draw_hair using console6502 naked
    self : ptr CelesteObject in pObj
begin
    jmp player_hair_draw_impl
end
; Player.kill. The cart carries on updating the player it just destroyed - Lua
; keeps the table alive - and this port returns instead. Nothing in stage 1 can
; tell the difference: everything after the spike test either reads state that
; is about to be thrown away, or spawns smoke that a restart clears.
proc kill using console6502
    self : ptr CelesteObject in pObj
begin
    mov sfx_timer, #12
    lda #0
    jsr sfx_play
    inc deaths
    mov shake, #10
    jsr Objects.destroy
    mov will_restart, #1
    lda #15
    sta delay_restart
    ret
end
; Player.draw: clamp into the room, then hair, then the player.
proc draw using console6502
    self : ptr CelesteObject in pObj
begin
    lda [pObj + CelesteObject.core.x]
    bmi .low
    cmp #122
    bcc .inside
    lda #121
    jmp .clamped
.low:
    cmp #$FF
    bcs .inside
    lda #$FF
.clamped:
    sta [pObj + CelesteObject.core.x]
    lda #0                      ; and stop, as the cart does
    mov y, offset CelesteObject.core.speed_x.fraction
    sta (pObj), y
    iny
    sta (pObj), y
.inside:
    lda [pObj + CelesteObject.payload.player.dash_jumps]
    jsr Player.set_hair_color
    jsr Player.draw_hair
    jmp draw_obj_sprite
; player_spawn - the cart's three-state entry animation.
end
end
namespace Spawn
    export init
    export update
    export draw
    gravity = $0080   ; 0.5
    speed = $FC00   ; -4
proc init using console6502
    self : ptr CelesteObject in pObj
begin
    lda #4
    jsr sfx_play
    lda #3
    sta [pObj + CelesteObject.core.sprite]
    lda [pObj + CelesteObject.core.x]
    sta [pObj + CelesteObject.payload.spawn.target_x]
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    sta [pObj + CelesteObject.payload.spawn.target_y]
    lda #127                    ; the cart starts at y = 128, one past what a
    sta [pObj + CelesteObject.core.y]  ; screen either way
    lda #<Spawn.speed
    mov y, offset CelesteObject.core.speed_y.fraction
    sta (pObj), y
    lda #>Spawn.speed
    iny
    sta (pObj), y
    mov y, offset CelesteObject.core.flags ; inlay-exception: complemented target constant
    lda (pObj), y                ; solids = false
    and #<!F_SOLIDS
    sta (pObj), y
    jmp Player.create_hair
end
proc update using console6502
    self : ptr CelesteObject in pObj
begin
    lda [pObj + CelesteObject.payload.spawn.phase]
    beq .rising
    cmp #1
    beq .falling
    jmp .landing
.rising:                        ; if y < target.y + 16 then state = 1
    lda [pObj + CelesteObject.payload.spawn.target_y]
    add #16
    sta t3
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    cmp t3
    bcs .done
    lda #1
    sta [pObj + CelesteObject.payload.spawn.phase]
    lda #3
    mov y, offset CelesteObject.payload.player.delay
    sta (pObj), y
.done:
    rts
.falling:
    mov y, offset CelesteObject.core.speed_y                 ; spd.y += 0.5
    jsr Fixed.load_object
    lda #<Spawn.gravity
    ldx #>Spawn.gravity
    jsr Fixed.set_target
    jsr Fixed.add
    mov y, offset CelesteObject.core.speed_y
    jsr Fixed.store_object
    lda w0+1                    ; the hover: while delay lasts, spd.y is held
    bmi .done2                  ; at zero each time it goes positive
    lda w0
    ora w0+1
    beq .done2
    mov y, offset CelesteObject.payload.player.delay ; inlay-exception: branch observes pre-decrement value
    lda (pObj), y
    beq .land
    sub #1
    sta (pObj), y
    lda #0
    mov y, offset CelesteObject.core.speed_y.fraction
    sta (pObj), y
    iny
    sta (pObj), y
.done2:
    rts
.land:
    lda [pObj + CelesteObject.payload.spawn.target_y]
    sta t3
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    cmp t3
    bcc .done2
    beq .done2
    lda t3
    sta [pObj + CelesteObject.core.y]
    lda #0
    mov y, offset CelesteObject.core.speed_x.fraction
    sta (pObj), y
    iny
    sta (pObj), y
    mov y, offset CelesteObject.core.speed_y.fraction
    sta (pObj), y
    iny
    sta (pObj), y
    lda #2
    sta [pObj + CelesteObject.payload.spawn.phase]
    lda #5
    sta [pObj + CelesteObject.payload.spawn.delay]
    mov shake, #5
    lda [pObj + CelesteObject.core.x]
    pha
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    add #4
    tax
    pla
    jsr Objects.spawn_smoke
    lda #5
    jmp sfx_play
.landing:
    dec [pObj + CelesteObject.payload.player.delay]
    pha
    lda #6
    mov y, offset CelesteObject.core.sprite
    sta (pObj), y
    pla
    bpl .stillhere
    lda [pObj + CelesteObject.core.x]
    sta spawn_x
    mov y, offset CelesteObject.core.y
    lda (pObj), y
    sta spawn_y
    jsr Objects.destroy
    mov spawn_type, #ObjectKind.player
    jmp Objects.allocate
.stillhere:
    rts
end
proc draw using console6502
    self : ptr CelesteObject in pObj
begin
    lda max_djump
    jsr Player.set_hair_color
    jsr Player.draw_hair
    jmp draw_obj_sprite
; smoke
end
end
namespace Smoke
    export init
    export update
    export draw
    speed_y = $FFE6   ; -0.1
proc init using console6502
    self : ptr CelesteObject in pObj
begin
    lda #29
    sta [pObj + CelesteObject.core.sprite]
    lda #<Smoke.speed_y
    mov y, offset CelesteObject.core.speed_y.fraction
    sta (pObj), y
    lda #>Smoke.speed_y
    iny
    sta (pObj), y
    lda [video + VideoRegisters.random]                 ; spd.x = 0.3 + rnd(0.2)
    and #$33
    add #$4D
    mov y, offset CelesteObject.core.speed_x.fraction
    sta (pObj), y
    lda #0
    iny
    sta (pObj), y
    lda [video + VideoRegisters.random]                 ; x += -1 + rnd(2), y likewise
    and #1
    sub #1
    mov y, offset CelesteObject.core.x
    clc
    adc (pObj), y
    sta (pObj), y
    lda [video + VideoRegisters.random]
    and #1
    sub #1
    mov y, offset CelesteObject.core.y
    clc
    adc (pObj), y
    sta (pObj), y
    lda [video + VideoRegisters.random]                 ; flip.x = maybe(), flip.y = maybe()
    and #3
    sta [pObj + CelesteObject.core.flip]
    mov y, offset CelesteObject.core.flags ; inlay-exception: complemented target constant
    lda (pObj), y
    and #<!F_SOLIDS
    sta (pObj), y
    rts
end
proc update using console6502
    self : ptr CelesteObject in pObj
begin
    inc [pObj + CelesteObject.payload.player.sprite_offset] ; spr += 0.2 -> destroy after 15 frames
    cmp #15
    bcs .gone
    lda [pObj + CelesteObject.payload.smoke.sprite_offset]
    ldx #29
    cmp #5
    bcc .have
    inx
    cmp #10
    bcc .have
    inx
.have:
    txa
    sta [pObj + CelesteObject.core.sprite]
    rts
.gone:
    jmp Objects.destroy
end
proc draw using console6502
    self : ptr CelesteObject in pObj
begin
    jmp draw_obj_sprite
; room_title. The cart does all of this in draw(), including the state changes,
; so the port does too - it is the only object whose update is nil.
end
end
namespace Title
    export init
    export update
    export draw
proc init using console6502
    self : ptr CelesteObject in pObj
begin
    lda #5
    sta [pObj + CelesteObject.payload.player.delay]
    rts
end
proc update using console6502
    self : ptr CelesteObject in pObj
begin
    rts
end
proc draw using console6502
    self : ptr CelesteObject in pObj
begin
    dec [pObj + CelesteObject.payload.player.delay]
    cmp #<(-30)
    beq .gone
    bpl .done
    cmp #<(-30)
    bcc .gone
.show:
    jsr draw_room_title
.done:
    rts
.gone:
    jmp Objects.destroy
end
end
