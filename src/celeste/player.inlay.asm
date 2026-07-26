; ------------------------------------------------------------------------------
; Celeste - the player, the spawn animation, smoke and the room title
;
; Player.update is a transliteration of the cart's update(), in its order, with
; its constants. It is deliberately NOT reorganised into something a 6502 would
; prefer: the corpus exists to measure what this shape costs on this ISA, and
; rewriting it into flat byte arithmetic would measure the rewrite instead.
;
; Its `local`s are file-scope bytes (p_input, p_onground, ...) because the 6502
; has nowhere else to put them. That is exactly the observation
; add-isa-frame-pointer is built on, and here it is not an argument from
; absence: these twelve bytes are live across four jsr calls each.
; ------------------------------------------------------------------------------

; 8.8 constants. Every one of them is the cart's own number, rounded to 1/256.
    MAXRUN = $0100   ; 1
    ACCEL_GROUND = $009A   ; 0.6
    ACCEL_AIR = $0066   ; 0.4
    ACCEL_ICE = $000D   ; 0.05
    DECCEL = $0026   ; 0.15
    MAXFALL = $0200   ; 2
    MAXFALL_SLIDE = $0066   ; 0.4
    GRAVITY = $0036   ; 0.21
    GRAVITY_HALF = $001B   ; 0.105, the <=0.15 apex case
    SPDY_EPSILON = $0026   ; 0.15
    JUMP_SPD = $FE00   ; -2
    WALLJUMP_SPD = $0200   ; maxrun + 1
    D_FULL = $0500   ; 5
    D_HALF = $0389   ; 5 * sqrt(2)/2 = 3.5355
    DASH_TARGET = $0200   ; 2
    DASH_TARGET_UP = $0180   ; 2 * 0.75, when dashing upward
    DASH_ACCEL = $0180   ; 1.5
    DASH_ACCEL_DIAG = $010F   ; 1.5 * sqrt(2)/2 = 1.0607
    SPAWN_GRAV = $0080   ; 0.5
    SPAWN_SPD = $FC00   ; -4
    SMOKE_SPDY = $FFE6   ; -0.1

    PB_JUMP = $01
    PB_DASH = $02
    PB_GROUND = $04

; ------------------------------------------------------------------------------
; Player.init
; ------------------------------------------------------------------------------
proc Player.init using console6502
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
    jmp create_hair

; ------------------------------------------------------------------------------
; Player.update
; ------------------------------------------------------------------------------
end

proc Player.update using console6502
    self : ptr CelesteObject in pObj
begin
    lda pause_player
    beq .go
    rts
.go:
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
    sta p_input

    lda #0                      ; spikes collide
    sta c_ox
    sta c_oy
    jsr obj_box
    jsr spikes_at
    beq .nospike
    jmp kill_player
.nospike:

    lda [pObj + CelesteObject.core.y]  ; port's positions are signed bytes, so the
    bmi .notbottom              ; test moves 8 pixels up rather than wrapping
    cmp #121                    ; into "above the room", which is next_room -
    bcc .notbottom              ; and the sign has to be tested BEFORE the
    jmp kill_player             ; compare, not from its flags.
.notbottom:

    mov c_ox, #0
    mov c_oy, #1
    jsr is_solid
    sta p_onground

    mov c_ox, #0
    mov c_oy, #1
    jsr is_ice
    sta p_onice

    lda p_onground              ; landing smoke
    beq .nosmoke
    lda [pObj + CelesteObject.payload.player.player_bits]
    and #PB_GROUND
    bne .nosmoke
    lda [pObj + CelesteObject.core.x]
    pha
    offset y, CelesteObject.core.y
    lda (pObj), y
    add #4
    tax
    pla
    jsr spawn_smoke
.nosmoke:

    tbz btn, #BTN_JUMP, .nojumpheld  ; jump = btn(jump) and not p_jump
    lda [pObj + CelesteObject.payload.player.player_bits]
    and #PB_JUMP
    bne .jumpheld
    mov p_jump, #1
    offset y, CelesteObject.payload.player.player_bits
    lda (pObj), y
    ora #PB_JUMP
    sta (pObj), y
    jmp .jbuf
.jumpheld:
    mov p_jump, #0
    jmp .jbufdec
.nojumpheld:
    mov p_jump, #0
    offset y, CelesteObject.payload.player.player_bits
    lda (pObj), y
    and #<!PB_JUMP
    sta (pObj), y
.jbufdec:
    offset y, CelesteObject.payload.player.jump_buffer
    lda (pObj), y
    beq .dashedge
    sub #1
    sta (pObj), y
    jmp .dashedge
.jbuf:
    lda #4
    sta [pObj + CelesteObject.payload.player.jump_buffer]

.dashedge:
    tbz btn, #BTN_DASH, .nodashheld  ; dash = btn(dash) and not p_dash
    lda [pObj + CelesteObject.payload.player.player_bits]
    and #PB_DASH
    bne .dashheld
    mov p_dash, #1
    offset y, CelesteObject.payload.player.player_bits
    lda (pObj), y
    ora #PB_DASH
    sta (pObj), y
    jmp .grace
.dashheld:
    mov p_dash, #0
    jmp .grace
.nodashheld:
    mov p_dash, #0
    offset y, CelesteObject.payload.player.player_bits
    lda (pObj), y
    and #<!PB_DASH
    sta (pObj), y

.grace:
    lda p_onground
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
    offset y, CelesteObject.payload.player.grace
    lda (pObj), y
    beq .gracedone
    sub #1
    sta (pObj), y
.gracedone:

    offset y, CelesteObject.payload.player.dash_effect                ; dash_effect_time -= 1
    lda (pObj), y
    sub #1
    sta (pObj), y

    offset y, CelesteObject.payload.player.dash_time                ; if dash_time > 0 then ... else move
    lda (pObj), y
    beq .move
    jmp .dashing
.move:
    jmp player_move
.dashing:
    sub #1
    sta (pObj), y

    lda [pObj + CelesteObject.core.x]                    ; a smoke puff per dash frame
    pha
    offset y, CelesteObject.core.y
    lda (pObj), y
    tax
    pla
    jsr spawn_smoke

    offset y, CelesteObject.core.speed_x                 ; spd.x = appr(spd.x, dash_target.x, dash_accel.x)
    jsr obj_ldw
    offset y, CelesteObject.payload.player.dash_target_x
    jsr obj_ldw1
    offset y, CelesteObject.payload.player.dash_accel_x.fraction
    lda (pObj), y
    sta w2
    iny
    lda (pObj), y
    sta w2+1
    jsr appr
    offset y, CelesteObject.core.speed_x
    jsr obj_stw

    offset y, CelesteObject.core.speed_y
    jsr obj_ldw
    offset y, CelesteObject.payload.player.dash_target_y
    jsr obj_ldw1
    offset y, CelesteObject.payload.player.dash_accel_y.fraction
    lda (pObj), y
    sta w2
    iny
    lda (pObj), y
    sta w2+1
    jsr appr
    offset y, CelesteObject.core.speed_y
    jsr obj_stw
    jmp player_anim

; ------------------------------------------------------------------------------
; The cart's `else` branch: run, gravity, wall slide, jump, dash.
; ------------------------------------------------------------------------------
end

player_move:
    mov p_maxrun, #<MAXRUN
    mov p_accel, #<ACCEL_GROUND
    mov p_accel+1, #>ACCEL_GROUND
    mov p_deccel, #<DECCEL
    mov p_deccel+1, #>DECCEL

    lda p_onground
    bne .grounded
    mov p_accel, #<ACCEL_AIR
    mov p_accel+1, #>ACCEL_AIR
    jmp .run
.grounded:
    lda p_onice
    beq .run
    mov p_accel, #<ACCEL_ICE
    mov p_accel+1, #>ACCEL_ICE

.run:
    lda #<MAXRUN                ; if abs(spd.x) > maxrun then decelerate
    ldx #>MAXRUN
    jsr setw0
    offset y, CelesteObject.core.speed_x
    jsr obj_ldw1
    lda w1+1
    bpl .absdone
    ldab #$0000  ; w1 = abs(spd.x), inline because neg16 works
    subw w1
    stab w1
.absdone:
    jsr cmp16                   ; N set: maxrun < abs(spd.x)
    bpl .accelerate

    offset y, CelesteObject.core.speed_x                 ; spd.x = appr(spd.x, sign(spd.x)*maxrun, deccel)
    jsr obj_ldw
    lda w0+1
    bmi .decelneg
    lda #<MAXRUN
    ldx #>MAXRUN
    jsr setw1
    jmp .decel
.decelneg:
    lda #<(-MAXRUN & $FFFF)
    ldx #>(-MAXRUN & $FFFF)
    jsr setw1
.decel:
    lda p_deccel
    ldx p_deccel+1
    jsr setw2
    jsr appr
    offset y, CelesteObject.core.speed_x
    jsr obj_stw
    jmp .facing

.accelerate:                    ; spd.x = appr(spd.x, input*maxrun, accel)
    offset y, CelesteObject.core.speed_x
    jsr obj_ldw
    lda p_input
    beq .targetzero
    bmi .targetneg
    lda #<MAXRUN
    ldx #>MAXRUN
    jsr setw1
    jmp .doaccel
.targetneg:
    lda #<(-MAXRUN & $FFFF)
    ldx #>(-MAXRUN & $FFFF)
    jsr setw1
    jmp .doaccel
.targetzero:
    lda #0
    tax
    jsr setw1
.doaccel:
    lda p_accel
    ldx p_accel+1
    jsr setw2
    jsr appr
    offset y, CelesteObject.core.speed_x
    jsr obj_stw

.facing:
    offset y, CelesteObject.core.speed_x.fraction                 ; if spd.x != 0 then flip.x = spd.x < 0
    lda (pObj), y
    iny
    ora (pObj), y
    beq .gravity
    lda [pObj + CelesteObject.core.speed_x.integer]
    bmi .faceleft
    offset y, CelesteObject.core.flip
    lda (pObj), y
    and #$FE
    sta (pObj), y
    jmp .gravity
.faceleft:
    offset y, CelesteObject.core.flip
    lda (pObj), y
    ora #$01
    sta (pObj), y

.gravity:
    mov p_maxfall, #<MAXFALL
    mov p_maxfall+1, #>MAXFALL
    mov p_gravity, #<GRAVITY
    mov p_gravity+1, #>GRAVITY

    offset y, CelesteObject.core.speed_y                 ; if abs(spd.y) <= 0.15 then gravity *= 0.5
    jsr obj_ldw
    jsr abs16
    lda #<SPDY_EPSILON
    ldx #>SPDY_EPSILON
    jsr setw1
    jsr cmp16                   ; N set: abs(spd.y) < 0.15
    bmi .halfgrav
    cbne w0, #<SPDY_EPSILON, .slide  ; the cart's test is <=, so catch equality too
    cbne w0+1, #>SPDY_EPSILON, .slide
.halfgrav:
    mov p_gravity, #<GRAVITY_HALF
    mov p_gravity+1, #>GRAVITY_HALF

.slide:                         ; wall slide
    lda p_input
    beq .fall
    sta c_ox
    mov c_oy, #0
    jsr is_solid
    beq .fall
    lda p_input
    sta c_ox
    mov c_oy, #0
    jsr is_ice
    bne .fall

    mov p_maxfall, #<MAXFALL_SLIDE
    mov p_maxfall+1, #>MAXFALL_SLIDE

    lda [video + VideoRegisters.random]                 ; if rnd(10) < 2 then a puff off the wall
    cmp #51
    bcs .fall
    lda [pObj + CelesteObject.core.x]
    add p_input  ; x + input*6, by adding input six times rather
    add p_input
    add p_input
    add p_input
    add p_input
    add p_input
    pha
    offset y, CelesteObject.core.y
    lda (pObj), y
    tax
    pla
    jsr spawn_smoke

.fall:
    lda p_onground
    bne .jump
    offset y, CelesteObject.core.speed_y                 ; spd.y = appr(spd.y, maxfall, gravity)
    jsr obj_ldw
    lda p_maxfall
    ldx p_maxfall+1
    jsr setw1
    lda p_gravity
    ldx p_gravity+1
    jsr setw2
    jsr appr
    offset y, CelesteObject.core.speed_y
    jsr obj_stw

.jump:
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
    lda #<JUMP_SPD
    offset y, CelesteObject.core.speed_y.fraction
    sta (pObj), y
    lda #>JUMP_SPD
    iny
    sta (pObj), y
    lda [pObj + CelesteObject.core.x]
    pha
    offset y, CelesteObject.core.y
    lda (pObj), y
    add #4
    tax
    pla
    jsr spawn_smoke
    jmp .dash

.walljump:                      ; wall_dir = is_solid(-3,0) and -1 or is_solid(3,0) and 1 or 0
    mov c_ox, #$FD
    mov c_oy, #0
    jsr is_solid
    beq .wallright
    mov p_walldir, #$FF
    jmp .havewall
.wallright:
    mov c_ox, #3
    mov c_oy, #0
    jsr is_solid
    beq .dash
    mov p_walldir, #1
.havewall:
    lda #2
    jsr psfx
    lda #0
    sta [pObj + CelesteObject.payload.player.jump_buffer]
    lda #<JUMP_SPD
    offset y, CelesteObject.core.speed_y.fraction
    sta (pObj), y
    lda #>JUMP_SPD
    iny
    sta (pObj), y

    lda p_walldir               ; spd.x = -wall_dir * (maxrun + 1)
    bmi .wjright
    lda #<(-WALLJUMP_SPD & $FFFF)
    ldx #>(-WALLJUMP_SPD & $FFFF)
    jmp .wjset
.wjright:
    lda #<WALLJUMP_SPD
    ldx #>WALLJUMP_SPD
.wjset:
    offset y, CelesteObject.core.speed_x.fraction
    sta (pObj), y
    txa
    iny
    sta (pObj), y

    lda p_walldir               ; the puff, unless the wall is ice
    asl
    asl
    add p_walldir  ; wall_dir * 5 ... the cart tests ice at *3
    sta c_ox                    ; and puffs at *6; close enough is not enough,
    lda p_walldir               ; so both are spelled out
    asl
    add p_walldir
    sta c_ox                    ; wall_dir * 3
    mov c_oy, #0
    jsr is_ice
    bne .dash
    lda [pObj + CelesteObject.core.x]
    add p_walldir
    add p_walldir
    add p_walldir
    add p_walldir
    add p_walldir
    add p_walldir
    pha
    offset y, CelesteObject.core.y
    lda (pObj), y
    tax
    pla
    jsr spawn_smoke

.dash:
    lda p_dash
    beq .nodash
    lda [pObj + CelesteObject.payload.player.dash_jumps]
    bne .dodash
    lda #9                      ; out of dashes: a puff and a raspberry
    jsr psfx
    lda [pObj + CelesteObject.core.x]
    pha
    offset y, CelesteObject.core.y
    lda (pObj), y
    tax
    pla
    jsr spawn_smoke
.nodash:
    jmp player_anim

.dodash:
    lda [pObj + CelesteObject.core.x]
    pha
    offset y, CelesteObject.core.y
    lda (pObj), y
    tax
    pla
    jsr spawn_smoke

    offset y, CelesteObject.payload.player.dash_jumps
    lda (pObj), y
    sub #1
    sta (pObj), y
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
    sta p_vinput

    lda p_input
    beq .vonly
    lda p_vinput
    beq .honly

    lda p_input                 ; diagonal: both axes at d_half
    ldx #<D_HALF
    ldy #>D_HALF
    jsr set_spdx_signed
    lda p_vinput
    ldx #<D_HALF
    ldy #>D_HALF
    jsr set_spdy_signed
    jmp .dashdone

.honly:
    lda p_input
    ldx #<D_FULL
    ldy #>D_FULL
    jsr set_spdx_signed
    lda #0
    ldx #0
    ldy #0
    jsr set_spdy_signed
    jmp .dashdone

.vonly:
    lda p_vinput
    beq .neutral
    lda #0
    ldx #0
    ldy #0
    jsr set_spdx_signed
    lda p_vinput
    ldx #<D_FULL
    ldy #>D_FULL
    jsr set_spdy_signed
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
    ldx #<MAXRUN
    ldy #>MAXRUN
    jsr set_spdx_signed
    lda #0
    ldx #0
    ldy #0
    jsr set_spdy_signed

.dashdone:
    lda #3
    jsr psfx
    mov freeze, #2
    mov shake, #6

    offset y, CelesteObject.core.speed_x                 ; dash_target = 2 * sign(spd), dash_accel = 1.5
    jsr obj_ldw
    jsr sign16
    ldx #<DASH_TARGET
    ldy #>DASH_TARGET
    jsr signed_word
    offset y, CelesteObject.payload.player.dash_target_x
    jsr obj_stw

    offset y, CelesteObject.core.speed_y
    jsr obj_ldw
    jsr sign16
    ldx #<DASH_TARGET
    ldy #>DASH_TARGET
    jsr signed_word
    offset y, CelesteObject.payload.player.dash_target_y
    jsr obj_stw

    offset y, CelesteObject.core.speed_y.fraction                 ; if spd.y < 0 then dash_target.y *= 0.75
    lda (pObj), y
    iny
    ora (pObj), y
    beq .yzero
    lda [pObj + CelesteObject.core.speed_y.integer]
    bpl .ynonzero
    lda #<(-DASH_TARGET_UP & $FFFF)
    offset y, CelesteObject.payload.player.dash_target_y.fraction
    sta (pObj), y
    lda #>(-DASH_TARGET_UP & $FFFF)
    iny
    sta (pObj), y
.ynonzero:
    lda #<DASH_ACCEL_DIAG       ; spd.y != 0: dash_accel.x *= sqrt(2)/2
    ldx #>DASH_ACCEL_DIAG
    jmp .setax
.yzero:
    lda #<DASH_ACCEL
    ldx #>DASH_ACCEL
.setax:
    offset y, CelesteObject.payload.player.dash_accel_x.fraction
    sta (pObj), y
    txa
    iny
    sta (pObj), y

    offset y, CelesteObject.core.speed_x.fraction                 ; spd.x != 0: dash_accel.y *= sqrt(2)/2
    lda (pObj), y
    iny
    ora (pObj), y
    beq .xzero
    lda #<DASH_ACCEL_DIAG
    ldx #>DASH_ACCEL_DIAG
    jmp .setay
.xzero:
    lda #<DASH_ACCEL
    ldx #>DASH_ACCEL
.setay:
    offset y, CelesteObject.payload.player.dash_accel_y.fraction
    sta (pObj), y
    txa
    iny
    sta (pObj), y

; ------------------------------------------------------------------------------
; Animation, the level exit, and the ground latch.
; ------------------------------------------------------------------------------
player_anim:
    offset y, CelesteObject.payload.player.sprite_offset               ; spr_off += 0.25, in quarter frames
    lda (pObj), y
    add #1
    and #15
    sta (pObj), y

    lda p_onground
    bne .onground
    lda p_input                 ; airborne: 5 against a wall, 3 otherwise
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
    offset y, CelesteObject.core.speed_x.fraction                 ; standing still, or no key held: frame 1
    lda (pObj), y
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

    offset y, CelesteObject.core.y                    ; if y < -4 then next_room()
    lda (pObj), y
    bpl .stay
    cmp #$FC
    bcs .stay
    jsr next_room
    rts
.stay:
    lda [pObj + CelesteObject.payload.player.player_bits]
    and #<!PB_GROUND
    ldy p_onground
    beq .nolatch
    ora #PB_GROUND
.nolatch:
    sta [pObj + CelesteObject.payload.player.player_bits]
    rts

; ------------------------------------------------------------------------------
; set_spdx_signed / set_spdy_signed: spd = A * {X,Y}, where A is -1, 0 or 1.
; The cart writes `input * d_full`; with a sign for a multiplier that is a
; select, not a multiply.
; ------------------------------------------------------------------------------
set_spdx_signed:
    jsr signed_word
    offset y, CelesteObject.core.speed_x
    jmp obj_stw

set_spdy_signed:
    jsr signed_word
    offset y, CelesteObject.core.speed_y
    jmp obj_stw

; signed_word: w0 = A * {X,Y} for A in {-1, 0, 1}. Clobbers A.
signed_word:
    stx w0
    sty w0+1
    cmp #0
    beq .zero
    bpl .done
    jmp neg16
.zero:
    sta w0
    sta w0+1
.done:
    rts

; ------------------------------------------------------------------------------
; kill_player. The cart carries on updating the player it just destroyed - Lua
; keeps the table alive - and this port returns instead. Nothing in stage 1 can
; tell the difference: everything after the spike test either reads state that
; is about to be thrown away, or spawns smoke that a restart clears.
; ------------------------------------------------------------------------------
kill_player:
    mov sfx_timer, #12
    lda #0
    jsr sfx_play
    inc deaths
    mov shake, #10
    jsr destroy_object
    mov will_restart, #1
    lda #15
    sta delay_restart
    rts

; ------------------------------------------------------------------------------
; Player.draw: clamp into the room, then hair, then the player.
; ------------------------------------------------------------------------------
proc Player.draw using console6502
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
    offset y, CelesteObject.core.speed_x.fraction
    sta (pObj), y
    iny
    sta (pObj), y
.inside:
    lda [pObj + CelesteObject.payload.player.dash_jumps]
    jsr set_hair_color
    jsr draw_hair
    jmp draw_obj_sprite

; ------------------------------------------------------------------------------
; player_spawn - the cart's three-state entry animation.
; ------------------------------------------------------------------------------
end

proc Spawn.init using console6502
    self : ptr CelesteObject in pObj
begin
    lda #4
    jsr sfx_play
    lda #3
    sta [pObj + CelesteObject.core.sprite]
    lda [pObj + CelesteObject.core.x]
    sta [pObj + CelesteObject.payload.spawn.target_x]
    lda [pObj + CelesteObject.core.y]
    sta [pObj + CelesteObject.payload.spawn.target_y]

    lda #127                    ; the cart starts at y = 128, one past what a
    sta [pObj + CelesteObject.core.y]  ; screen either way
    lda #<SPAWN_SPD
    offset y, CelesteObject.core.speed_y.fraction
    sta (pObj), y
    lda #>SPAWN_SPD
    iny
    sta (pObj), y
    offset y, CelesteObject.core.flags                ; solids = false
    lda (pObj), y
    and #<!F_SOLIDS
    sta (pObj), y
    jmp create_hair

end

proc Spawn.update using console6502
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
    offset y, CelesteObject.core.y
    lda (pObj), y
    cmp t3
    bcs .done
    lda #1
    sta [pObj + CelesteObject.payload.spawn.phase]
    lda #3
    offset y, CelesteObject.payload.player.delay
    sta (pObj), y
.done:
    rts

.falling:
    offset y, CelesteObject.core.speed_y                 ; spd.y += 0.5
    jsr obj_ldw
    lda #<SPAWN_GRAV
    ldx #>SPAWN_GRAV
    jsr setw1
    jsr add16
    offset y, CelesteObject.core.speed_y
    jsr obj_stw

    lda w0+1                    ; the hover: while delay lasts, spd.y is held
    bmi .done2                  ; at zero each time it goes positive
    lda w0
    ora w0+1
    beq .done2
    offset y, CelesteObject.payload.player.delay
    lda (pObj), y
    beq .land
    sub #1
    sta (pObj), y
    lda #0
    offset y, CelesteObject.core.speed_y.fraction
    sta (pObj), y
    iny
    sta (pObj), y
.done2:
    rts

.land:
    lda [pObj + CelesteObject.payload.spawn.target_y]
    sta t3
    offset y, CelesteObject.core.y
    lda (pObj), y
    cmp t3
    bcc .done2
    beq .done2
    lda t3
    sta [pObj + CelesteObject.core.y]
    lda #0
    offset y, CelesteObject.core.speed_x.fraction
    sta (pObj), y
    iny
    sta (pObj), y
    offset y, CelesteObject.core.speed_y.fraction
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
    offset y, CelesteObject.core.y
    lda (pObj), y
    add #4
    tax
    pla
    jsr spawn_smoke
    lda #5
    jmp sfx_play

.landing:
    offset y, CelesteObject.payload.player.delay
    lda (pObj), y
    sub #1
    sta (pObj), y
    pha
    lda #6
    offset y, CelesteObject.core.sprite
    sta (pObj), y
    pla
    bpl .stillhere

    lda [pObj + CelesteObject.core.x]
    sta spawn_x
    lda [pObj + CelesteObject.core.y]
    sta spawn_y
    jsr destroy_object
    mov spawn_type, #ObjectKind.player
    jmp init_object
.stillhere:
    rts

end

proc Spawn.draw using console6502
    self : ptr CelesteObject in pObj
begin
    lda max_djump
    jsr set_hair_color
    jsr draw_hair
    jmp draw_obj_sprite

; ------------------------------------------------------------------------------
; smoke
; ------------------------------------------------------------------------------
end

proc Smoke.init using console6502
    self : ptr CelesteObject in pObj
begin
    lda #29
    sta [pObj + CelesteObject.core.sprite]
    lda #<SMOKE_SPDY
    offset y, CelesteObject.core.speed_y.fraction
    sta (pObj), y
    lda #>SMOKE_SPDY
    iny
    sta (pObj), y

    lda [video + VideoRegisters.random]                 ; spd.x = 0.3 + rnd(0.2)
    and #$33
    add #$4D
    offset y, CelesteObject.core.speed_x.fraction
    sta (pObj), y
    lda #0
    iny
    sta (pObj), y

    lda [video + VideoRegisters.random]                 ; x += -1 + rnd(2), y likewise
    and #1
    sub #1
    offset y, CelesteObject.core.x
    clc
    adc (pObj), y
    sta (pObj), y
    lda [video + VideoRegisters.random]
    and #1
    sub #1
    offset y, CelesteObject.core.y
    clc
    adc (pObj), y
    sta (pObj), y

    lda [video + VideoRegisters.random]                 ; flip.x = maybe(), flip.y = maybe()
    and #3
    sta [pObj + CelesteObject.core.flip]
    offset y, CelesteObject.core.flags
    lda (pObj), y
    and #<!F_SOLIDS
    sta (pObj), y
    rts

end

proc Smoke.update using console6502
    self : ptr CelesteObject in pObj
begin
    offset y, CelesteObject.payload.player.sprite_offset               ; spr += 0.2 -> destroy after 15 frames
    lda (pObj), y
    add #1
    sta (pObj), y
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
    jmp destroy_object

end

proc Smoke.draw using console6502
    self : ptr CelesteObject in pObj
begin
    jmp draw_obj_sprite

; ------------------------------------------------------------------------------
; room_title. The cart does all of this in draw(), including the state changes,
; so the port does too - it is the only object whose update is nil.
; ------------------------------------------------------------------------------
end

proc Title.init using console6502
    self : ptr CelesteObject in pObj
begin
    lda #5
    sta [pObj + CelesteObject.payload.player.delay]
    rts

end

proc Title.update using console6502
    self : ptr CelesteObject in pObj
begin
    rts

end

proc Title.draw using console6502
    self : ptr CelesteObject in pObj
begin
    offset y, CelesteObject.payload.player.delay
    lda (pObj), y
    sub #1
    sta (pObj), y
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
    jmp destroy_object
end
