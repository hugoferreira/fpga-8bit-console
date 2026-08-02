; ------------------------------------------------------------------------------
; Celeste rooms 0..9 - stage-2 content objects
;
; These are the cart's object families reached by the first ten-room campaign.
; They use the same pool, method tables, collision receiver and cart sprite ids
; as the stage-1 engine; no room-specific gameplay code lives in the loader.
; ------------------------------------------------------------------------------

namespace Berries
    export clear
    export collected
    export take

bit_mask:
    #d8 $01, $02, $04, $08, $10, $20, $40, $80

proc clear using console6502
begin
    lda #0
    ldx #3
.loop:
    sta [berries.bits[x]]
    dex
    bpl .loop
    ret
end

; A/Z says whether the current level's strawberry has already been collected.
; Levels 0..31 fit in the four-byte persistent bitset.
proc collected using console6502
begin
    lda [game.level]
    cmp #32
    bcs .no
    pha
    and #7
    tax
    lda bit_mask, x
    sta Machine.t6
    pla
    lsr a, 3
    tax
    lda [berries.bits[x]]
    and Machine.t6
    ret
.no:
    lda #0
    ret
end

proc collect using console6502
begin
    lda [game.level]
    cmp #32
    bcs .done
    pha
    and #7
    tax
    lda bit_mask, x
    sta Machine.t6
    pla
    lsr a, 3
    tax
    lda [berries.bits[x]]
    ora Machine.t6
    sta [berries.bits[x]]
.done:
    ret
end

; Collect the receiver after Collision.object has left the player in
; Machine.other. The life-up allocation intentionally reuses the just-freed slot.
proc take using console6502
    self : ptr CelesteObject in Machine.object
begin
    mov y, offset CelesteObject.payload.player.dash_jumps
    lda [game.max_dash_jumps]
    sta (Machine.other), y
    mov [game.sfx_timer], #20
    lda #13
    jsr Audio.sfx
    jsr collect
    lda [Machine.object.core.x]
    sta Objects.spawn_x
    lda [Machine.object.core.y]
    sta Objects.spawn_y
    jsr Objects.destroy
    mov Objects.spawn_type, #ObjectKind.lifeup
    jmp Objects.allocate
end
end

; A compact signed two-pixel sine used for fruit/balloon hovering. The original
; uses PICO-8 sin(); sixteen phases preserve the motion without runtime multiply.
cel_bob:
    #d8 0, 1, 1, 2, 2, 2, 1, 1, 0, $FF, $FF, $FE, $FE, $FE, $FF, $FF

namespace Spring
    export init
    export update
    export draw

proc init using console6502
begin
    lda #0
    sta [Machine.object.payload.extra.state]
    sta [Machine.object.payload.extra.timer]
    sta [Machine.object.payload.extra.value]
    ret
end

proc update using console6502
begin
    lda [Machine.object.payload.extra.timer]
    beq .visible
    dec [Machine.object.payload.extra.timer]
    bne .done
    lda #18
    sta [Machine.object.core.sprite]
    ret
.visible:
    lda [Machine.object.payload.extra.value]
    beq .contact
    dec [Machine.object.payload.extra.value]
    bne .done
    lda #18
    sta [Machine.object.core.sprite]
.contact:
    mov Collision.type, #ObjectKind.player
    mov Collision.offset_x, #0
    mov Collision.offset_y, #0
    jsr Collision.object
    beq .done
    mov y, offset CelesteObject.core.speed_y.integer
    lda (Machine.other), y
    bmi .done
    lda [Machine.object.core.y]
    sub #4
    mov y, offset CelesteObject.core.y
    sta (Machine.other), y
    lda #0
    mov y, offset CelesteObject.core.speed_x.fraction
    sta (Machine.other), y
    iny
    sta (Machine.other), y
    mov y, offset CelesteObject.core.speed_y.fraction
    sta (Machine.other), y
    lda #$FD                    ; -3.0 px/frame
    iny
    sta (Machine.other), y
    mov y, offset CelesteObject.payload.player.dash_jumps
    lda [game.max_dash_jumps]
    sta (Machine.other), y
    lda #19
    sta [Machine.object.core.sprite]
    lda #10
    sta [Machine.object.payload.extra.value]
    lda [Machine.object.core.x]
    pha
    lda [Machine.object.core.y]
    tax
    pla
    jsr Objects.spawn_smoke
    lda #8
    jmp Audio.guarded_sfx
.done:
    ret
end

proc draw using console6502
begin
    jmp Draw.object
end
end

namespace Ball
    export init
    export update
    export draw

proc init using console6502
begin
    lda [Machine.object.core.y]
    sta [Machine.object.payload.extra.start_y]
    lda [video.random]
    sta [Machine.object.payload.extra.phase]
    lda #$FF
    sta [Machine.object.core.hitbox.x]
    lda #$FF
    sta [Machine.object.core.hitbox.y]
    lda #10
    sta [Machine.object.core.hitbox.w]
    lda #10
    sta [Machine.object.core.hitbox.h]
    ret
end

proc update using console6502
begin
    lda [Machine.object.core.sprite]
    beq .waiting
    lda [Machine.object.payload.extra.phase]
    add #3
    sta [Machine.object.payload.extra.phase]
    lsr a, 4
    tax
    lda cel_bob, x
    mov y, offset CelesteObject.payload.extra.start_y
    clc
    adc (Machine.object), y
    sta [Machine.object.core.y]
    mov Collision.type, #ObjectKind.player
    mov Collision.offset_x, #0
    mov Collision.offset_y, #0
    jsr Collision.object
    beq .done
    mov y, offset CelesteObject.payload.player.dash_jumps
    lda (Machine.other), y
    cmp [game.max_dash_jumps]
    bcs .done
    lda [game.max_dash_jumps]
    sta (Machine.other), y
    lda #6
    jsr Audio.guarded_sfx
    lda [Machine.object.core.x]
    pha
    lda [Machine.object.core.y]
    tax
    pla
    jsr Objects.spawn_smoke
    lda #0
    sta [Machine.object.core.sprite]
    lda #60
    sta [Machine.object.payload.extra.timer]
    ret
.waiting:
    lda [Machine.object.payload.extra.timer]
    beq .restore
    dec [Machine.object.payload.extra.timer]
    bne .done
.restore:
    lda #7
    jsr Audio.guarded_sfx
    lda [Machine.object.core.x]
    pha
    lda [Machine.object.core.y]
    tax
    pla
    jsr Objects.spawn_smoke
    lda #22
    sta [Machine.object.core.sprite]
.done:
    ret
end

proc draw using console6502
begin
    lda [Machine.object.core.sprite]
    beq .done
    lda [Machine.object.payload.extra.phase]
    lsr a, 5
    and #3
    cmp #3
    bcc .frame
    lda #0
.frame:
    add #13
    pha
    lda [Machine.object.core.x]
    sta Machine.t4
    lda [Machine.object.core.y]
    add #6
    sta Machine.t5
    mov Machine.t6, #0
    pla
    jsr Draw.cart_sprite
    jmp Draw.object
.done:
    ret
end
end

namespace Floor
    export init
    export update
    export draw

proc init using console6502
begin
    lda #0
    sta [Machine.object.payload.extra.state]
    sta [Machine.object.payload.extra.timer]
    ret
end

proc break using console6502
begin
    lda [Machine.object.payload.extra.state]
    bne .done
    lda #1
    sta [Machine.object.payload.extra.state]
    lda #15
    sta [Machine.object.payload.extra.timer]
    lda #15
    jsr Audio.guarded_sfx
    lda [Machine.object.core.x]
    pha
    lda [Machine.object.core.y]
    tax
    pla
    jsr Objects.spawn_smoke
.done:
    ret
end

proc update using console6502
begin
    lda [Machine.object.payload.extra.state]
    beq .idle
    cmp #1
    beq .shaking
    dec [Machine.object.payload.extra.timer]
    beq .reappear
    ret
.reappear:
    mov Collision.type, #ObjectKind.player
    mov Collision.offset_x, #0
    mov Collision.offset_y, #0
    jsr Collision.object
    bne .hold
    lda #0
    sta [Machine.object.payload.extra.state]
    lda #23
    sta [Machine.object.core.sprite]
    lda [Machine.object.core.flags]
    ora #Objects.flag_collideable
    sta [Machine.object.core.flags]
    lda #7
    jsr Audio.guarded_sfx
    lda [Machine.object.core.x]
    pha
    lda [Machine.object.core.y]
    tax
    pla
    jmp Objects.spawn_smoke
.hold:
    lda #1
    sta [Machine.object.payload.extra.timer]
    ret
.shaking:
    dec [Machine.object.payload.extra.timer]
    beq .fall
    ret
.fall:
    lda #2
    sta [Machine.object.payload.extra.state]
    lda #60
    sta [Machine.object.payload.extra.timer]
    lda #0
    sta [Machine.object.core.sprite]
    lda [Machine.object.core.flags]
    and #<!Objects.flag_collideable
    sta [Machine.object.core.flags]
    ret
.idle:
    mov Collision.type, #ObjectKind.player
    mov Collision.offset_x, #0
    mov Collision.offset_y, #$FF
    jsr Collision.object
    beq .left
    jmp break
.left:
    mov Collision.offset_x, #$FF
    mov Collision.offset_y, #0
    jsr Collision.object
    beq .right
    jmp break
.right:
    mov Collision.offset_x, #1
    jsr Collision.object
    beq .done
    jmp break
.done:
    ret
end

proc draw using console6502
begin
    lda [Machine.object.payload.extra.state]
    cmp #2
    beq .done
    cmp #1
    bne .base
    lda [Machine.object.payload.extra.timer]
    cmp #11
    bcs .base
    cmp #6
    bcs .middle
    lda #25
    bne .set
.middle:
    lda #24
    bne .set
.base:
    lda #23
.set:
    sta [Machine.object.core.sprite]
    jmp Draw.object
.done:
    ret
end
end

namespace Fruit
    export init
    export update
    export draw

proc init using console6502
begin
    lda [Machine.object.core.y]
    sta [Machine.object.payload.extra.start_y]
    lda #0
    sta [Machine.object.payload.extra.phase]
    ret
end

proc update using console6502
begin
    mov Collision.type, #ObjectKind.player
    mov Collision.offset_x, #0
    mov Collision.offset_y, #0
    jsr Collision.object
    beq .hover
    jmp Berries.take
.hover:
    lda [Machine.object.payload.extra.phase]
    add #4
    sta [Machine.object.payload.extra.phase]
    lsr a, 4
    tax
    lda cel_bob, x
    mov y, offset CelesteObject.payload.extra.start_y
    clc
    adc (Machine.object), y
    sta [Machine.object.core.y]
    ret
end

proc draw using console6502
begin
    jmp Draw.object
end
end

namespace Fly
    export init
    export update
    export draw
    fly_target = $FC80          ; -3.5
    fly_accel = $0040           ; 0.25

proc init using console6502
begin
    lda [Machine.object.core.y]
    sta [Machine.object.payload.extra.start_y]
    lda #$40
    sta [Machine.object.payload.extra.phase]
    lda #0
    sta [Machine.object.payload.extra.state]
    lda #8
    sta [Machine.object.payload.extra.timer]
    lda [Machine.object.core.flags]
    and #<!Objects.flag_solids
    sta [Machine.object.core.flags]
    ret
end

proc update using console6502
begin
    lda [Machine.object.payload.extra.state]
    bne .flying
    lda [game.has_dashed]
    beq .hover
    lda #1
    sta [Machine.object.payload.extra.state]
    jmp .collect
.hover:
    lda [Machine.object.payload.extra.phase]
    add #5
    sta [Machine.object.payload.extra.phase]
    lsr a, 4
    tax
    lda cel_bob, x
    asr
    mov y, offset CelesteObject.payload.extra.start_y
    clc
    adc (Machine.object), y
    sta [Machine.object.core.y]
    jmp .collect
.flying:
    lda [Machine.object.payload.extra.timer]
    beq .speed
    dec [Machine.object.payload.extra.timer]
    bne .speed
    mov [game.sfx_timer], #20
    lda #14
    jsr Audio.sfx
.speed:
    mov y, offset CelesteObject.core.speed_y
    jsr Fixed.load_object
    lda #<fly_target
    ldx #>fly_target
    jsr Fixed.set_target
    lda #<fly_accel
    ldx #>fly_accel
    jsr Fixed.set_amount
    jsr Fixed.approach
    mov y, offset CelesteObject.core.speed_y
    jsr Fixed.store_object
    lda [Machine.object.core.y]
    cmp #$F0
    bcc .collect
    cmp #$80
    bcs .gone
.collect:
    mov Collision.type, #ObjectKind.player
    mov Collision.offset_x, #0
    mov Collision.offset_y, #0
    jsr Collision.object
    beq .not_collected
    jmp Berries.take
.not_collected:
    ret
.gone:
    jmp Objects.destroy
end

proc draw using console6502
begin
    lda [Machine.object.payload.extra.state]
    bne .body
    lda [Machine.object.payload.extra.phase]
    lsr a, 5
    and #3
    cmp #3
    bcc .wing
    lda #0
.wing:
    add #45
    pha
    lda [Machine.object.core.x]
    sub #6
    sta Machine.t4
    lda [Machine.object.core.y]
    sub #2
    sta Machine.t5
    mov Machine.t6, #1
    pla
    pha
    jsr Draw.cart_sprite
    lda [Machine.object.core.x]
    add #6
    sta Machine.t4
    lda [Machine.object.core.y]
    sub #2
    sta Machine.t5
    mov Machine.t6, #0
    pla
    jsr Draw.cart_sprite
.body:
    jmp Draw.object
end
end

namespace Life
    export init
    export update
    export draw

proc init using console6502
begin
    lda #30
    sta [Machine.object.payload.extra.timer]
    lda #0
    sta [Machine.object.payload.extra.phase]
    lda #26
    sta [Machine.object.core.sprite]
    lda [Machine.object.core.x]
    sub #2
    sta [Machine.object.core.x]
    lda [Machine.object.core.y]
    sub #4
    sta [Machine.object.core.y]
    lda #$C0
    sta [Machine.object.core.speed_y.fraction]
    lda #$FF
    sta [Machine.object.core.speed_y.integer]
    lda [Machine.object.core.flags]
    and #<!Objects.flag_solids
    sta [Machine.object.core.flags]
    ret
end

proc update using console6502
begin
    dec [Machine.object.payload.extra.timer]
    beq .gone
    inc [Machine.object.payload.extra.phase]
    ret
.gone:
    jmp Objects.destroy
end

proc draw using console6502
begin
    jmp Draw.object
end
end

namespace Wall
    export update
    export draw

proc update using console6502
begin
    lda #$FF
    sta [Machine.object.core.hitbox.x]
    lda #$FF
    sta [Machine.object.core.hitbox.y]
    lda #18
    sta [Machine.object.core.hitbox.w]
    lda #18
    sta [Machine.object.core.hitbox.h]
    mov Collision.type, #ObjectKind.player
    mov Collision.offset_x, #0
    mov Collision.offset_y, #0
    jsr Collision.object
    bne .player
    jmp .restore
.player:
    mov y, offset CelesteObject.payload.player.dash_effect
    lda (Machine.other), y
    bne .break
    jmp .restore
.break:
    mov y, offset CelesteObject.core.speed_x.integer
    lda (Machine.other), y
    bmi .bounce_right
    lda #$80
    mov y, offset CelesteObject.core.speed_x.fraction
    sta (Machine.other), y
    lda #$FE                    ; -1.5
    iny
    sta (Machine.other), y
    jmp .vertical
.bounce_right:
    lda #$80
    mov y, offset CelesteObject.core.speed_x.fraction
    sta (Machine.other), y
    lda #1                     ; +1.5
    iny
    sta (Machine.other), y
.vertical:
    lda #$80
    mov y, offset CelesteObject.core.speed_y.fraction
    sta (Machine.other), y
    lda #$FE
    iny
    sta (Machine.other), y
    lda #$FF
    mov y, offset CelesteObject.payload.player.dash_time
    sta (Machine.other), y
    mov [game.sfx_timer], #20
    lda #16
    jsr Audio.sfx
    lda [Machine.object.core.x]
    sta Machine.t6
    lda [Machine.object.core.y]
    sta Machine.t7
    jsr Objects.destroy
    lda Machine.t6
    ldx Machine.t7
    jsr Objects.spawn_smoke
    lda Machine.t6
    add #8
    ldx Machine.t7
    jsr Objects.spawn_smoke
    lda Machine.t6
    ldx Machine.t7
    inx
    inx
    inx
    inx
    inx
    inx
    inx
    inx
    jsr Objects.spawn_smoke
    lda Machine.t6
    add #8
    ldx Machine.t7
    inx
    inx
    inx
    inx
    inx
    inx
    inx
    inx
    jsr Objects.spawn_smoke
    lda Machine.t6
    add #4
    sta Objects.spawn_x
    lda Machine.t7
    add #4
    sta Objects.spawn_y
    mov Objects.spawn_type, #ObjectKind.fruit
    jmp Objects.allocate
.restore:
    lda #0
    sta [Machine.object.core.hitbox.x]
    sta [Machine.object.core.hitbox.y]
    lda #16
    sta [Machine.object.core.hitbox.w]
    lda #16
    sta [Machine.object.core.hitbox.h]
    ret
end

proc draw using console6502
begin
    lda [Machine.object.core.x]
    sta Machine.t4
    lda [Machine.object.core.y]
    sta Machine.t5
    mov Machine.t6, #0
    lda #64
    jsr Draw.cart_sprite
    lda [Machine.object.core.x]
    add #8
    sta Machine.t4
    lda [Machine.object.core.y]
    sta Machine.t5
    lda #65
    jsr Draw.cart_sprite
    lda [Machine.object.core.x]
    sta Machine.t4
    lda [Machine.object.core.y]
    add #8
    sta Machine.t5
    lda #80
    jsr Draw.cart_sprite
    lda [Machine.object.core.x]
    add #8
    sta Machine.t4
    lda [Machine.object.core.y]
    add #8
    sta Machine.t5
    lda #81
    jmp Draw.cart_sprite
end
end

namespace Key
    export update
    export draw

proc update using console6502
begin
    lda [game.frames]
    cmp #15
    bcc .nine
    lda #10
    bne .sprite
.nine:
    lda #9
.sprite:
    sta [Machine.object.core.sprite]
    mov Collision.type, #ObjectKind.player
    mov Collision.offset_x, #0
    mov Collision.offset_y, #0
    jsr Collision.object
    beq .done
    lda #23
    jsr Audio.sfx
    mov [game.sfx_timer], #10
    mov [game.has_key], #1
    jmp Objects.destroy
.done:
    ret
end

proc draw using console6502
begin
    jmp Draw.object
end
end

namespace Chest
    export init
    export update
    export draw

proc init using console6502
begin
    lda [Machine.object.core.x]
    sub #4
    sta [Machine.object.core.x]
    sta [Machine.object.payload.extra.start_x]
    lda #20
    sta [Machine.object.payload.extra.timer]
    ret
end

proc update using console6502
begin
    lda [game.has_key]
    beq .done
    dec [Machine.object.payload.extra.timer]
    bne .shake
    mov [game.sfx_timer], #20
    lda #16
    jsr Audio.sfx
    lda [Machine.object.core.x]
    sta Objects.spawn_x
    lda [Machine.object.core.y]
    sub #4
    sta Objects.spawn_y
    jsr Objects.destroy
    mov Objects.spawn_type, #ObjectKind.fruit
    jmp Objects.allocate
.shake:
    lda [video.random]
    and #3
    sub #1
    mov y, offset CelesteObject.payload.extra.start_x
    clc
    adc (Machine.object), y
    sta [Machine.object.core.x]
.done:
    ret
end

proc draw using console6502
begin
    jmp Draw.object
end
end

namespace Mover
    export init
    export configure
    export update
    export draw
    platform_speed = $00A6      ; 0.65

proc init using console6502
begin
    lda [Machine.object.core.x]
    sub #4
    sta [Machine.object.core.x]
    sta [Machine.object.payload.extra.start_x]
    lda #16
    sta [Machine.object.core.hitbox.w]
    lda [Machine.object.core.flags]
    and #<!Objects.flag_solids
    sta [Machine.object.core.flags]
    ret
end

proc configure using console6502
begin
    lda [Machine.object.payload.extra.value]
    bmi .left
    lda #<platform_speed
    sta [Machine.object.core.speed_x.fraction]
    lda #>platform_speed
    sta [Machine.object.core.speed_x.integer]
    ret
.left:
    lda #<(-platform_speed & $FFFF)
    sta [Machine.object.core.speed_x.fraction]
    lda #>(-platform_speed & $FFFF)
    sta [Machine.object.core.speed_x.integer]
    ret
end

proc update using console6502
begin
    lda [Machine.object.payload.extra.value]
    bmi .moving_left
    lda [Machine.object.core.x]
    bpl .carry
    lda #$F0     ; +128 wrapped: resume at -16
    sta [Machine.object.core.x]
    jmp .carry
.moving_left:
    lda [Machine.object.core.x]
    bpl .carry
    cmp #$F0
    bcs .carry
    lda #127
    sta [Machine.object.core.x]
.carry:
    mov Collision.type, #ObjectKind.player
    mov Collision.offset_x, #0
    mov Collision.offset_y, #0
    jsr Collision.object
    bne .remember
    mov Collision.offset_y, #$FF
    jsr Collision.object
    beq .remember
    lda [Machine.object.core.x]
    mov y, offset CelesteObject.payload.extra.start_x
    sec
    sbc (Machine.object), y
    sta Machine.t7
    lda Machine.object
    sta Machine.source
    lda Machine.object+1
    sta Machine.source+1
    lda Machine.other
    sta Machine.object
    lda Machine.other+1
    sta Machine.object+1
    mov Collision.offset_y, #0
    lda Machine.t7
    sta Collision.offset_x
    jsr Collision.solid
    bne .restore
    mov y, offset CelesteObject.core.x
    lda (Machine.object), y
    add Machine.t7
    sta (Machine.object), y
.restore:
    lda Machine.source
    sta Machine.object
    lda Machine.source+1
    sta Machine.object+1
.remember:
    lda [Machine.object.core.x]
    sta [Machine.object.payload.extra.start_x]
    ret
end

proc draw using console6502
begin
    lda [Machine.object.core.x]
    sta Machine.t4
    lda [Machine.object.core.y]
    sub #1
    sta Machine.t5
    mov Machine.t6, #0
    lda #11
    jsr Draw.cart_sprite
    lda [Machine.object.core.x]
    add #8
    sta Machine.t4
    lda [Machine.object.core.y]
    sub #1
    sta Machine.t5
    lda #12
    jmp Draw.cart_sprite
end
end
