; ------------------------------------------------------------------------------
; Celeste - the player, the spawn animation, smoke and the room title
;
; player_update is a transliteration of the cart's update(), in its order, with
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
    .define MAXRUN             $0100   ; 1
    .define ACCEL_GROUND       $009A   ; 0.6
    .define ACCEL_AIR          $0066   ; 0.4
    .define ACCEL_ICE          $000D   ; 0.05
    .define DECCEL             $0026   ; 0.15
    .define MAXFALL            $0200   ; 2
    .define MAXFALL_SLIDE      $0066   ; 0.4
    .define GRAVITY            $0036   ; 0.21
    .define GRAVITY_HALF       $001B   ; 0.105, the <=0.15 apex case
    .define SPDY_EPSILON       $0026   ; 0.15
    .define JUMP_SPD           $FE00   ; -2
    .define WALLJUMP_SPD       $0200   ; maxrun + 1
    .define D_FULL             $0500   ; 5
    .define D_HALF             $0389   ; 5 * sqrt(2)/2 = 3.5355
    .define DASH_TARGET        $0200   ; 2
    .define DASH_TARGET_UP     $0180   ; 2 * 0.75, when dashing upward
    .define DASH_ACCEL         $0180   ; 1.5
    .define DASH_ACCEL_DIAG    $010F   ; 1.5 * sqrt(2)/2 = 1.0607
    .define SPAWN_GRAV         $0080   ; 0.5
    .define SPAWN_SPD          $FC00   ; -4
    .define SMOKE_SPDY         $FFE6   ; -0.1

    .define PB_JUMP            $01
    .define PB_DASH            $02
    .define PB_GROUND          $04

; ------------------------------------------------------------------------------
; player_init
; ------------------------------------------------------------------------------
player_init:
    lda #1                      ; hitbox = {1,3,6,5}
    ldy #O_HBX
    sta (pObj),y
    lda #3
    ldy #O_HBY
    sta (pObj),y
    lda #6
    ldy #O_HBW
    sta (pObj),y
    lda #5
    ldy #O_HBH
    sta (pObj),y
    lda max_djump
    ldy #O_DJUMP
    sta (pObj),y
    lda #1
    ldy #O_SPR
    sta (pObj),y
    jmp create_hair

; ------------------------------------------------------------------------------
; player_update
; ------------------------------------------------------------------------------
player_update:
    lda pause_player
    beq @go
    rts
@go:
    lda btn                     ; input = right and 1 or (left and -1 or 0)
    and #BTN_R
    beq @noright
    lda #1
    bne @haveinput
@noright:
    lda btn
    and #BTN_L
    beq @noinput
    lda #$FF
    bne @haveinput
@noinput:
    lda #0
@haveinput:
    sta p_input

    lda #0                      ; spikes collide
    sta c_ox
    sta c_oy
    jsr obj_box
    jsr spikes_at
    beq @nospike
    jmp kill_player
@nospike:

    ldy #O_Y                    ; bottom death. The cart tests y > 128; the
    lda (pObj),y                ; port's positions are signed bytes, so the
    bmi @notbottom              ; test moves 8 pixels up rather than wrapping
    cmp #121                    ; into "above the room", which is next_room -
    bcc @notbottom              ; and the sign has to be tested BEFORE the
    jmp kill_player             ; compare, not from its flags.
@notbottom:

    lda #0                      ; on_ground = is_solid(0,1)
    sta c_ox
    lda #1
    sta c_oy
    jsr is_solid
    sta p_onground

    lda #0                      ; on_ice = is_ice(0,1)
    sta c_ox
    lda #1
    sta c_oy
    jsr is_ice
    sta p_onice

    lda p_onground              ; landing smoke
    beq @nosmoke
    ldy #O_PBITS
    lda (pObj),y
    and #PB_GROUND
    bne @nosmoke
    ldy #O_X
    lda (pObj),y
    pha
    ldy #O_Y
    lda (pObj),y
    clc
    adc #4
    tax
    pla
    jsr spawn_smoke
@nosmoke:

    lda btn                     ; jump = btn(jump) and not p_jump
    and #BTN_JUMP
    beq @nojumpheld
    ldy #O_PBITS
    lda (pObj),y
    and #PB_JUMP
    bne @jumpheld
    lda #1
    sta p_jump
    ldy #O_PBITS
    lda (pObj),y
    ora #PB_JUMP
    sta (pObj),y
    jmp @jbuf
@jumpheld:
    lda #0
    sta p_jump
    jmp @jbufdec
@nojumpheld:
    lda #0
    sta p_jump
    ldy #O_PBITS
    lda (pObj),y
    and #<~PB_JUMP
    sta (pObj),y
@jbufdec:
    ldy #O_JBUF
    lda (pObj),y
    beq @dashedge
    sec
    sbc #1
    sta (pObj),y
    jmp @dashedge
@jbuf:
    lda #4
    ldy #O_JBUF
    sta (pObj),y

@dashedge:
    lda btn                     ; dash = btn(dash) and not p_dash
    and #BTN_DASH
    beq @nodashheld
    ldy #O_PBITS
    lda (pObj),y
    and #PB_DASH
    bne @dashheld
    lda #1
    sta p_dash
    ldy #O_PBITS
    lda (pObj),y
    ora #PB_DASH
    sta (pObj),y
    jmp @grace
@dashheld:
    lda #0
    sta p_dash
    jmp @grace
@nodashheld:
    lda #0
    sta p_dash
    ldy #O_PBITS
    lda (pObj),y
    and #<~PB_DASH
    sta (pObj),y

@grace:
    lda p_onground
    beq @airborne
    lda #6
    ldy #O_GRACE
    sta (pObj),y
    ldy #O_DJUMP                ; refill the dash on landing
    lda (pObj),y
    cmp max_djump
    bcs @gracedone
    lda #54
    jsr psfx
    lda max_djump
    ldy #O_DJUMP
    sta (pObj),y
    jmp @gracedone
@airborne:
    ldy #O_GRACE
    lda (pObj),y
    beq @gracedone
    sec
    sbc #1
    sta (pObj),y
@gracedone:

    ldy #O_DASHE                ; dash_effect_time -= 1
    lda (pObj),y
    sec
    sbc #1
    sta (pObj),y

    ldy #O_DASHT                ; if dash_time > 0 then ... else move
    lda (pObj),y
    beq @move
    jmp @dashing
@move:
    jmp player_move
@dashing:
    sec
    sbc #1
    sta (pObj),y

    ldy #O_X                    ; a smoke puff per dash frame
    lda (pObj),y
    pha
    ldy #O_Y
    lda (pObj),y
    tax
    pla
    jsr spawn_smoke

    ldy #O_SPDX                 ; spd.x = appr(spd.x, dash_target.x, dash_accel.x)
    jsr obj_ldw
    ldy #O_DTX
    jsr obj_ldw1
    ldy #O_DAX
    lda (pObj),y
    sta w2
    iny
    lda (pObj),y
    sta w2+1
    jsr appr
    ldy #O_SPDX
    jsr obj_stw

    ldy #O_SPDY
    jsr obj_ldw
    ldy #O_DTY
    jsr obj_ldw1
    ldy #O_DAY
    lda (pObj),y
    sta w2
    iny
    lda (pObj),y
    sta w2+1
    jsr appr
    ldy #O_SPDY
    jsr obj_stw
    jmp player_anim

; ------------------------------------------------------------------------------
; The cart's `else` branch: run, gravity, wall slide, jump, dash.
; ------------------------------------------------------------------------------
player_move:
    lda #<MAXRUN                ; maxrun = 1, accel/deccel by surface
    sta p_maxrun
    lda #<ACCEL_GROUND
    sta p_accel
    lda #>ACCEL_GROUND
    sta p_accel+1
    lda #<DECCEL
    sta p_deccel
    lda #>DECCEL
    sta p_deccel+1

    lda p_onground
    bne @grounded
    lda #<ACCEL_AIR
    sta p_accel
    lda #>ACCEL_AIR
    sta p_accel+1
    jmp @run
@grounded:
    lda p_onice
    beq @run
    lda #<ACCEL_ICE
    sta p_accel
    lda #>ACCEL_ICE
    sta p_accel+1

@run:
    lda #<MAXRUN                ; if abs(spd.x) > maxrun then decelerate
    ldx #>MAXRUN
    jsr setw0
    ldy #O_SPDX
    jsr obj_ldw1
    lda w1+1
    bpl @absdone
    lda #0                      ; w1 = abs(spd.x), inline because neg16 works
    sec                         ; on w0 and w0 is holding maxrun
    sbc w1
    sta w1
    lda #0
    sbc w1+1
    sta w1+1
@absdone:
    jsr cmp16                   ; N set: maxrun < abs(spd.x)
    bpl @accelerate

    ldy #O_SPDX                 ; spd.x = appr(spd.x, sign(spd.x)*maxrun, deccel)
    jsr obj_ldw
    lda w0+1
    bmi @decelneg
    lda #<MAXRUN
    ldx #>MAXRUN
    jsr setw1
    jmp @decel
@decelneg:
    lda #<(-MAXRUN & $FFFF)
    ldx #>(-MAXRUN & $FFFF)
    jsr setw1
@decel:
    lda p_deccel
    ldx p_deccel+1
    jsr setw2
    jsr appr
    ldy #O_SPDX
    jsr obj_stw
    jmp @facing

@accelerate:                    ; spd.x = appr(spd.x, input*maxrun, accel)
    ldy #O_SPDX
    jsr obj_ldw
    lda p_input
    beq @targetzero
    bmi @targetneg
    lda #<MAXRUN
    ldx #>MAXRUN
    jsr setw1
    jmp @doaccel
@targetneg:
    lda #<(-MAXRUN & $FFFF)
    ldx #>(-MAXRUN & $FFFF)
    jsr setw1
    jmp @doaccel
@targetzero:
    lda #0
    tax
    jsr setw1
@doaccel:
    lda p_accel
    ldx p_accel+1
    jsr setw2
    jsr appr
    ldy #O_SPDX
    jsr obj_stw

@facing:
    ldy #O_SPDX                 ; if spd.x != 0 then flip.x = spd.x < 0
    lda (pObj),y
    iny
    ora (pObj),y
    beq @gravity
    ldy #O_SPDX+1
    lda (pObj),y
    bmi @faceleft
    ldy #O_FLIP
    lda (pObj),y
    and #$FE
    sta (pObj),y
    jmp @gravity
@faceleft:
    ldy #O_FLIP
    lda (pObj),y
    ora #$01
    sta (pObj),y

@gravity:
    lda #<MAXFALL
    sta p_maxfall
    lda #>MAXFALL
    sta p_maxfall+1
    lda #<GRAVITY
    sta p_gravity
    lda #>GRAVITY
    sta p_gravity+1

    ldy #O_SPDY                 ; if abs(spd.y) <= 0.15 then gravity *= 0.5
    jsr obj_ldw
    jsr abs16
    lda #<SPDY_EPSILON
    ldx #>SPDY_EPSILON
    jsr setw1
    jsr cmp16                   ; N set: abs(spd.y) < 0.15
    bmi @halfgrav
    lda w0                      ; the cart's test is <=, so catch equality too
    cmp #<SPDY_EPSILON
    bne @slide
    lda w0+1
    cmp #>SPDY_EPSILON
    bne @slide
@halfgrav:
    lda #<GRAVITY_HALF
    sta p_gravity
    lda #>GRAVITY_HALF
    sta p_gravity+1

@slide:                         ; wall slide
    lda p_input
    beq @fall
    sta c_ox
    lda #0
    sta c_oy
    jsr is_solid
    beq @fall
    lda p_input
    sta c_ox
    lda #0
    sta c_oy
    jsr is_ice
    bne @fall

    lda #<MAXFALL_SLIDE
    sta p_maxfall
    lda #>MAXFALL_SLIDE
    sta p_maxfall+1

    lda SPR_RND                 ; if rnd(10) < 2 then a puff off the wall
    cmp #51
    bcs @fall
    ldy #O_X
    lda (pObj),y
    clc
    adc p_input                 ; x + input*6, by adding input six times rather
    clc                         ; than multiplying: it is two bytes shorter
    adc p_input
    clc
    adc p_input
    clc
    adc p_input
    clc
    adc p_input
    clc
    adc p_input
    pha
    ldy #O_Y
    lda (pObj),y
    tax
    pla
    jsr spawn_smoke

@fall:
    lda p_onground
    bne @jump
    ldy #O_SPDY                 ; spd.y = appr(spd.y, maxfall, gravity)
    jsr obj_ldw
    lda p_maxfall
    ldx p_maxfall+1
    jsr setw1
    lda p_gravity
    ldx p_gravity+1
    jsr setw2
    jsr appr
    ldy #O_SPDY
    jsr obj_stw

@jump:
    ldy #O_JBUF
    lda (pObj),y
    bne @wantjump
    jmp @dash
@wantjump:
    ldy #O_GRACE
    lda (pObj),y
    beq @walljump

    lda #1                      ; normal jump
    jsr psfx
    lda #0
    ldy #O_JBUF
    sta (pObj),y
    ldy #O_GRACE
    sta (pObj),y
    lda #<JUMP_SPD
    ldy #O_SPDY
    sta (pObj),y
    lda #>JUMP_SPD
    iny
    sta (pObj),y
    ldy #O_X
    lda (pObj),y
    pha
    ldy #O_Y
    lda (pObj),y
    clc
    adc #4
    tax
    pla
    jsr spawn_smoke
    jmp @dash

@walljump:                      ; wall_dir = is_solid(-3,0) and -1 or is_solid(3,0) and 1 or 0
    lda #$FD
    sta c_ox
    lda #0
    sta c_oy
    jsr is_solid
    beq @wallright
    lda #$FF
    sta p_walldir
    jmp @havewall
@wallright:
    lda #3
    sta c_ox
    lda #0
    sta c_oy
    jsr is_solid
    beq @dash
    lda #1
    sta p_walldir
@havewall:
    lda #2
    jsr psfx
    lda #0
    ldy #O_JBUF
    sta (pObj),y
    lda #<JUMP_SPD
    ldy #O_SPDY
    sta (pObj),y
    lda #>JUMP_SPD
    iny
    sta (pObj),y

    lda p_walldir               ; spd.x = -wall_dir * (maxrun + 1)
    bmi @wjright
    lda #<(-WALLJUMP_SPD & $FFFF)
    ldx #>(-WALLJUMP_SPD & $FFFF)
    jmp @wjset
@wjright:
    lda #<WALLJUMP_SPD
    ldx #>WALLJUMP_SPD
@wjset:
    ldy #O_SPDX
    sta (pObj),y
    txa
    iny
    sta (pObj),y

    lda p_walldir               ; the puff, unless the wall is ice
    asl
    asl
    clc
    adc p_walldir               ; wall_dir * 5 ... the cart tests ice at *3
    sta c_ox                    ; and puffs at *6; close enough is not enough,
    lda p_walldir               ; so both are spelled out
    asl
    clc
    adc p_walldir
    sta c_ox                    ; wall_dir * 3
    lda #0
    sta c_oy
    jsr is_ice
    bne @dash
    ldy #O_X
    lda (pObj),y
    clc
    adc p_walldir
    clc
    adc p_walldir
    clc
    adc p_walldir
    clc
    adc p_walldir
    clc
    adc p_walldir
    clc
    adc p_walldir
    pha
    ldy #O_Y
    lda (pObj),y
    tax
    pla
    jsr spawn_smoke

@dash:
    lda p_dash
    beq @nodash
    ldy #O_DJUMP
    lda (pObj),y
    bne @dodash
    lda #9                      ; out of dashes: a puff and a raspberry
    jsr psfx
    ldy #O_X
    lda (pObj),y
    pha
    ldy #O_Y
    lda (pObj),y
    tax
    pla
    jsr spawn_smoke
@nodash:
    jmp player_anim

@dodash:
    ldy #O_X
    lda (pObj),y
    pha
    ldy #O_Y
    lda (pObj),y
    tax
    pla
    jsr spawn_smoke

    ldy #O_DJUMP
    lda (pObj),y
    sec
    sbc #1
    sta (pObj),y
    lda #4
    ldy #O_DASHT
    sta (pObj),y
    lda #1
    sta has_dashed
    lda #10
    ldy #O_DASHE
    sta (pObj),y

    lda btn                     ; v_input
    and #BTN_U
    beq @notup
    lda #$FF
    bne @havev
@notup:
    lda btn
    and #BTN_D
    beq @nov
    lda #1
    bne @havev
@nov:
    lda #0
@havev:
    sta p_vinput

    lda p_input
    beq @vonly
    lda p_vinput
    beq @honly

    lda p_input                 ; diagonal: both axes at d_half
    ldx #<D_HALF
    ldy #>D_HALF
    jsr set_spdx_signed
    lda p_vinput
    ldx #<D_HALF
    ldy #>D_HALF
    jsr set_spdy_signed
    jmp @dashdone

@honly:
    lda p_input
    ldx #<D_FULL
    ldy #>D_FULL
    jsr set_spdx_signed
    lda #0
    ldx #0
    ldy #0
    jsr set_spdy_signed
    jmp @dashdone

@vonly:
    lda p_vinput
    beq @neutral
    lda #0
    ldx #0
    ldy #0
    jsr set_spdx_signed
    lda p_vinput
    ldx #<D_FULL
    ldy #>D_FULL
    jsr set_spdy_signed
    jmp @dashdone

@neutral:                       ; no direction held: the cart dashes at 1 px/frame
    ldy #O_FLIP                 ; in the facing direction, not at d_full
    lda (pObj),y
    and #$01
    beq @neutralright
    lda #$FF
    jmp @neutralset
@neutralright:
    lda #1
@neutralset:
    ldx #<MAXRUN
    ldy #>MAXRUN
    jsr set_spdx_signed
    lda #0
    ldx #0
    ldy #0
    jsr set_spdy_signed

@dashdone:
    lda #3
    jsr psfx
    lda #2
    sta freeze
    lda #6
    sta shake

    ldy #O_SPDX                 ; dash_target = 2 * sign(spd), dash_accel = 1.5
    jsr obj_ldw
    jsr sign16
    ldx #<DASH_TARGET
    ldy #>DASH_TARGET
    jsr signed_word
    ldy #O_DTX
    jsr obj_stw

    ldy #O_SPDY
    jsr obj_ldw
    jsr sign16
    ldx #<DASH_TARGET
    ldy #>DASH_TARGET
    jsr signed_word
    ldy #O_DTY
    jsr obj_stw

    ldy #O_SPDY                 ; if spd.y < 0 then dash_target.y *= 0.75
    lda (pObj),y
    iny
    ora (pObj),y
    beq @yzero
    ldy #O_SPDY+1
    lda (pObj),y
    bpl @ynonzero
    lda #<(-DASH_TARGET_UP & $FFFF)
    ldy #O_DTY
    sta (pObj),y
    lda #>(-DASH_TARGET_UP & $FFFF)
    iny
    sta (pObj),y
@ynonzero:
    lda #<DASH_ACCEL_DIAG       ; spd.y != 0: dash_accel.x *= sqrt(2)/2
    ldx #>DASH_ACCEL_DIAG
    jmp @setax
@yzero:
    lda #<DASH_ACCEL
    ldx #>DASH_ACCEL
@setax:
    ldy #O_DAX
    sta (pObj),y
    txa
    iny
    sta (pObj),y

    ldy #O_SPDX                 ; spd.x != 0: dash_accel.y *= sqrt(2)/2
    lda (pObj),y
    iny
    ora (pObj),y
    beq @xzero
    lda #<DASH_ACCEL_DIAG
    ldx #>DASH_ACCEL_DIAG
    jmp @setay
@xzero:
    lda #<DASH_ACCEL
    ldx #>DASH_ACCEL
@setay:
    ldy #O_DAY
    sta (pObj),y
    txa
    iny
    sta (pObj),y

; ------------------------------------------------------------------------------
; Animation, the level exit, and the ground latch.
; ------------------------------------------------------------------------------
player_anim:
    ldy #O_SPROFF               ; spr_off += 0.25, in quarter frames
    lda (pObj),y
    clc
    adc #1
    and #15
    sta (pObj),y

    lda p_onground
    bne @onground
    lda p_input                 ; airborne: 5 against a wall, 3 otherwise
    sta c_ox
    lda #0
    sta c_oy
    jsr is_solid
    beq @air
    lda #5
    jmp @setspr
@air:
    lda #3
    jmp @setspr
@onground:
    lda btn
    and #BTN_D
    beq @notdown
    lda #6
    jmp @setspr
@notdown:
    lda btn
    and #BTN_U
    beq @notup
    lda #7
    jmp @setspr
@notup:
    ldy #O_SPDX                 ; standing still, or no key held: frame 1
    lda (pObj),y
    iny
    ora (pObj),y
    beq @still
    lda btn
    and #BTN_L|BTN_R
    beq @still
    ldy #O_SPROFF               ; 1 + spr_off % 4
    lda (pObj),y
    lsr
    lsr
    clc
    adc #1
    jmp @setspr
@still:
    lda #1
@setspr:
    ldy #O_SPR
    sta (pObj),y

    ldy #O_Y                    ; if y < -4 then next_room()
    lda (pObj),y
    bpl @stay
    cmp #$FC
    bcs @stay
    jsr next_room
    rts
@stay:
    ldy #O_PBITS                ; was_on_ground = on_ground
    lda (pObj),y
    and #<~PB_GROUND
    ldy p_onground
    beq @nolatch
    ora #PB_GROUND
@nolatch:
    ldy #O_PBITS
    sta (pObj),y
    rts

; ------------------------------------------------------------------------------
; set_spdx_signed / set_spdy_signed: spd = A * {X,Y}, where A is -1, 0 or 1.
; The cart writes `input * d_full`; with a sign for a multiplier that is a
; select, not a multiply.
; ------------------------------------------------------------------------------
set_spdx_signed:
    jsr signed_word
    ldy #O_SPDX
    jmp obj_stw

set_spdy_signed:
    jsr signed_word
    ldy #O_SPDY
    jmp obj_stw

; signed_word: w0 = A * {X,Y} for A in {-1, 0, 1}. Clobbers A.
signed_word:
    stx w0
    sty w0+1
    cmp #0
    beq @zero
    bpl @done
    jmp neg16
@zero:
    sta w0
    sta w0+1
@done:
    rts

; ------------------------------------------------------------------------------
; kill_player. The cart carries on updating the player it just destroyed - Lua
; keeps the table alive - and this port returns instead. Nothing in stage 1 can
; tell the difference: everything after the spike test either reads state that
; is about to be thrown away, or spawns smoke that a restart clears.
; ------------------------------------------------------------------------------
kill_player:
    lda #12
    sta sfx_timer
    lda #0
    jsr sfx_play
    inc deaths
    lda #10
    sta shake
    jsr destroy_object
    lda #1
    sta will_restart
    lda #15
    sta delay_restart
    rts

; ------------------------------------------------------------------------------
; player_draw: clamp into the room, then hair, then the player.
; ------------------------------------------------------------------------------
player_draw:
    ldy #O_X                    ; clamp(x, -1, 121)
    lda (pObj),y
    bmi @low
    cmp #122
    bcc @inside
    lda #121
    jmp @clamped
@low:
    cmp #$FF
    bcs @inside
    lda #$FF
@clamped:
    ldy #O_X
    sta (pObj),y
    lda #0                      ; and stop, as the cart does
    ldy #O_SPDX
    sta (pObj),y
    iny
    sta (pObj),y
@inside:
    ldy #O_DJUMP
    lda (pObj),y
    jsr set_hair_color
    jsr draw_hair
    jmp draw_obj_sprite

; ------------------------------------------------------------------------------
; player_spawn - the cart's three-state entry animation.
; ------------------------------------------------------------------------------
spawn_init:
    lda #4
    jsr sfx_play
    lda #3
    ldy #O_SPR
    sta (pObj),y
    ldy #O_X                    ; target = where the marker tile was
    lda (pObj),y
    ldy #O_TGTX
    sta (pObj),y
    ldy #O_Y
    lda (pObj),y
    ldy #O_TGTY
    sta (pObj),y

    lda #127                    ; the cart starts at y = 128, one past what a
    ldy #O_Y                    ; signed byte holds; one pixel lower is off
    sta (pObj),y                ; screen either way
    lda #<SPAWN_SPD
    ldy #O_SPDY
    sta (pObj),y
    lda #>SPAWN_SPD
    iny
    sta (pObj),y
    ldy #O_FLAGS                ; solids = false
    lda (pObj),y
    and #<~F_SOLIDS
    sta (pObj),y
    jmp create_hair

spawn_update:
    ldy #O_STATE
    lda (pObj),y
    beq @rising
    cmp #1
    beq @falling
    jmp @landing

@rising:                        ; if y < target.y + 16 then state = 1
    ldy #O_TGTY
    lda (pObj),y
    clc
    adc #16
    sta t3
    ldy #O_Y
    lda (pObj),y
    cmp t3
    bcs @done
    lda #1
    ldy #O_STATE
    sta (pObj),y
    lda #3
    ldy #O_DELAY
    sta (pObj),y
@done:
    rts

@falling:
    ldy #O_SPDY                 ; spd.y += 0.5
    jsr obj_ldw
    lda #<SPAWN_GRAV
    ldx #>SPAWN_GRAV
    jsr setw1
    jsr add16
    ldy #O_SPDY
    jsr obj_stw

    lda w0+1                    ; the hover: while delay lasts, spd.y is held
    bmi @done2                  ; at zero each time it goes positive
    lda w0
    ora w0+1
    beq @done2
    ldy #O_DELAY
    lda (pObj),y
    beq @land
    sec
    sbc #1
    sta (pObj),y
    lda #0
    ldy #O_SPDY
    sta (pObj),y
    iny
    sta (pObj),y
@done2:
    rts

@land:
    ldy #O_TGTY                 ; if y > target.y then land
    lda (pObj),y
    sta t3
    ldy #O_Y
    lda (pObj),y
    cmp t3
    bcc @done2
    beq @done2
    lda t3
    ldy #O_Y
    sta (pObj),y
    lda #0
    ldy #O_SPDX
    sta (pObj),y
    iny
    sta (pObj),y
    ldy #O_SPDY
    sta (pObj),y
    iny
    sta (pObj),y
    lda #2
    ldy #O_STATE
    sta (pObj),y
    lda #5
    ldy #O_DELAY
    sta (pObj),y
    lda #5
    sta shake
    ldy #O_X
    lda (pObj),y
    pha
    ldy #O_Y
    lda (pObj),y
    clc
    adc #4
    tax
    pla
    jsr spawn_smoke
    lda #5
    jmp sfx_play

@landing:
    ldy #O_DELAY
    lda (pObj),y
    sec
    sbc #1
    sta (pObj),y
    pha
    lda #6
    ldy #O_SPR
    sta (pObj),y
    pla
    bpl @stillhere

    ldy #O_X                    ; hand over to the player proper
    lda (pObj),y
    sta spawn_x
    ldy #O_Y
    lda (pObj),y
    sta spawn_y
    jsr destroy_object
    lda #T_PLAYER
    sta spawn_type
    jmp init_object
@stillhere:
    rts

spawn_draw:
    lda max_djump
    jsr set_hair_color
    jsr draw_hair
    jmp draw_obj_sprite

; ------------------------------------------------------------------------------
; smoke
; ------------------------------------------------------------------------------
smoke_init:
    lda #29
    ldy #O_SPR
    sta (pObj),y
    lda #<SMOKE_SPDY
    ldy #O_SPDY
    sta (pObj),y
    lda #>SMOKE_SPDY
    iny
    sta (pObj),y

    lda SPR_RND                 ; spd.x = 0.3 + rnd(0.2)
    and #$33
    clc
    adc #$4D
    ldy #O_SPDX
    sta (pObj),y
    lda #0
    iny
    sta (pObj),y

    lda SPR_RND                 ; x += -1 + rnd(2), y likewise
    and #1
    sec
    sbc #1
    ldy #O_X
    clc
    adc (pObj),y
    sta (pObj),y
    lda SPR_RND
    and #1
    sec
    sbc #1
    ldy #O_Y
    clc
    adc (pObj),y
    sta (pObj),y

    lda SPR_RND                 ; flip.x = maybe(), flip.y = maybe()
    and #3
    ldy #O_FLIP
    sta (pObj),y
    ldy #O_FLAGS
    lda (pObj),y
    and #<~F_SOLIDS
    sta (pObj),y
    rts

smoke_update:
    ldy #O_SPROFF               ; spr += 0.2 -> destroy after 15 frames
    lda (pObj),y
    clc
    adc #1
    sta (pObj),y
    cmp #15
    bcs @gone
    ldy #O_SPROFF
    lda (pObj),y
    ldx #29
    cmp #5
    bcc @have
    inx
    cmp #10
    bcc @have
    inx
@have:
    txa
    ldy #O_SPR
    sta (pObj),y
    rts
@gone:
    jmp destroy_object

smoke_draw:
    jmp draw_obj_sprite

; ------------------------------------------------------------------------------
; room_title. The cart does all of this in draw(), including the state changes,
; so the port does too - it is the only object whose update is nil.
; ------------------------------------------------------------------------------
title_init:
    lda #5
    ldy #O_DELAY
    sta (pObj),y
    rts

title_update:
    rts

title_draw:
    ldy #O_DELAY
    lda (pObj),y
    sec
    sbc #1
    sta (pObj),y
    cmp #<(-30)
    beq @gone
    bpl @done
    cmp #<(-30)
    bcc @gone
@show:
    jsr draw_room_title
@done:
    rts
@gone:
    jmp destroy_object
