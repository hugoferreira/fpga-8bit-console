; ------------------------------------------------------------------------------
; Celeste - the sprite list, the hair, and the overlay
;
; Three layers, split by what each can express:
;   * tiles     - the room, scrolled by the camera, in the cart's own colours
;   * sprites   - the player, the hair blobs and smoke, staged in SCREEN space
;   * overlay   - 1bpp, above everything, unscrolled: the HUD and the room title
;
; Sprites are screen-space, so every one of them has camera_y subtracted and
; the screen shake added. That split is the reason the shake is applied here
; rather than through the camera registers: the camera moves the tile layer
; only, and shaking the terrain out from under a stationary player would be
; worse than not shaking at all.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; draw_frame: the cart's _draw, minus the effects it has no primitives for.
; ------------------------------------------------------------------------------
draw_frame:
    jsr flash_palette
    jsr camera_update
    jsr ovl_begin

    lda #0
    sta nspr
    jsr is_title                ; the cart draws no clouds on the title screen
    beq @nosky
    jsr fx_draw_clouds
@nosky:
    lda nspr                    ; everything staged so far is background
    sta SPR_SPLIT
    lda #1                      ; clouds leave a repeat count staged; the
    sta SPR_REP                 ; player, hair and smoke are single cells

    lda #0
    sta obj_slot
@loop:
    lda obj_slot
    jsr obj_ptr
    ldy #O_TYPE
    lda (pObj),y
    beq @next
    tax
    lda type_draw_lo-1,x
    sta pFn
    lda type_draw_hi-1,x
    sta pFn+1
    ora pFn
    beq @next
    jsr call_fn
@next:
    inc obj_slot
    lda obj_slot
    cmp #OBJ_MAX
    bne @loop

    jsr fx_draw_particles       ; in front of everything, title screen included
    lda nspr
    sta SPR_COUNT
    jmp ovl_end

; ------------------------------------------------------------------------------
; flash_palette: the cart's start-game flash.
;
;   pal(6,c) pal(12,c) pal(13,c) pal(5,c) pal(1,c) pal(7,c)
;
; is a screen-wide recolour of the six colours the title art is drawn in, and
; the console has exactly that: a 16-entry screen palette at $4020 applied to
; every displayed pixel, overlay included. So this is one of the few places the
; port does what the cart does by the same mechanism rather than an equivalent
; one. Clobbers A, X.
; ------------------------------------------------------------------------------
flash_palette:
    lda start_game
    beq @ident                  ; not flashing at all

    lda start_game_flash        ; c = 10, 7, 2, 1 or 0 as the flash decays
    bmi @black                  ; past zero: c = 0
    cmp #11
    bcc @mid
                                ; > 10: white for five frames in every ten.
    lda frames                  ; frames is 0..29, so one subtract of 20 and
    cmp #20                     ; one of 10 is the whole of `frames % 10`
    bcc @lt20
    sec
    sbc #20
    jmp @lt10
@lt20:
    cmp #10
    bcc @lt10
    sec
    sbc #10
@lt10:
    cmp #5
    bcc @white
                                ; the cart's c = 10, which is "no pal() call at
                                ; all" - and since it calls pal() every frame,
                                ; that means the IDENTITY palette, not whatever
                                ; the previous frame left behind.
@ident:
    ldx #5
@identloop:
    ldy flash_slot,x
    tya
    sta SPR_SPAL,y              ; entry n holds n
    dex
    bpl @identloop
    rts

@white:
    lda #7
    bne @apply
@mid:
    lda start_game_flash
    cmp #6
    bcs @two
    cmp #1
    bcs @one
@black:
    lda #0
    beq @apply
@two:
    lda #2
    bne @apply
@one:
    lda #1
@apply:
    ldx #5
@set:
    ldy flash_slot,x
    sta SPR_SPAL,y
    dex
    bpl @set
    rts

; The six colours the cart recolours: pal(6) pal(12) pal(13) pal(5) pal(1) pal(7)
flash_slot:
    .byte 6, 12, 13, 5, 1, 7

; ------------------------------------------------------------------------------
; stage_sprite: A = pattern base, t3 = attributes, t4 = screen x, t5 = screen y.
; Sprites outside the visible band are dropped rather than clamped: SPR_Y is
; seven bits, so a negative y would reappear at the bottom of the screen.
; Horizontally there is nothing to do - the compositor's x is 8-bit and wraps,
; and the clip rectangle already cuts the row at the playfield edge.
; Clobbers A, X, Y.
; ------------------------------------------------------------------------------
stage_sprite:
    ldx nspr
    cpx #128
    bcs @drop
    ldy t5
    bmi @drop
    cpy #120
    bcs @drop
    stx SPR_INDEX
    sta SPR_BASE
    lda t4
    sta SPR_X
    sty SPR_Y
    lda t3
    sta SPR_FLAGS               ; the write commits the staged entry
    inc nspr
@drop:
    rts

; ------------------------------------------------------------------------------
; draw_obj_sprite: the cart's spr(this.spr, this.x, this.y, 1,1, flip.x, flip.y).
;
; The cart's sprite numbers survive into the port as the object's O_SPR, so the
; game logic reads the way the Lua does; the translation to a sheet slot is one
; place, here. Two families is all stage 1 has - the player's seven frames and
; smoke's three.
; ------------------------------------------------------------------------------
.if SPR_SMOKE_STRIDE <> 1
.error "smoke frames are no longer adjacent; draw_obj_sprite needs a multiply"
.endif

draw_obj_sprite:
    ldy #O_SPR
    lda (pObj),y
    beq @done                   ; the cart's `elseif obj.spr > 0`
    cmp #29
    bcs @smoke
    tax                         ; the player's frames are no longer a fixed
    lda player_slot-1,x         ; stride apart: bpp is chosen per pattern, so
    pha                         ; the generator emits their slots as a table
    lda #SPR_PLAYER_ATTR
    jmp @flip
@smoke:
    sec
    sbc #29
    clc
    adc #SPR_SMOKE_FIRST
    pha
    lda #SPR_SMOKE_ATTR
@flip:
    ldy #O_FLIP
    ora (pObj),y
    sta t3
    jsr obj_screen_pos
    pla
    jmp stage_sprite
@done:
    rts

; ------------------------------------------------------------------------------
; obj_screen_pos: t4/t5 = where the object at pObj lands on screen this frame.
; Clobbers A, Y.
; ------------------------------------------------------------------------------
obj_screen_pos:
    ldy #O_X
    lda (pObj),y
    clc
    adc shake_x
    sta t4
    ldy #O_Y
    lda (pObj),y
    sec
    sbc camera_y
    clc
    adc shake_y
    sta t5
    rts

; ------------------------------------------------------------------------------
; The hair.
;
; The cart draws five circfill()s that chase the player's neck, and recolours
; them with pal(8,...) to show how many dashes are left. This console has no
; circle primitive, so each node is a 1bpp blob sprite - and because a sprite
; entry carries its own 4-bit palette base, the recolour is free: base 7 paints
; colour 8, base 6 paints 7, base 11 paints 12.
;
; Divergence: the cart chases at (last - h)/1.5 per frame. A 6502 divide by 1.5
; is a multiply by 2/3; here the node moves (d>>1) + (d>>3) = 0.625d instead of
; 0.667d, which is two shifts and an add. The trail is imperceptibly tighter.
; ------------------------------------------------------------------------------
create_hair:
    ldy #O_X
    lda (pObj),y
    sta t3
    ldy #O_Y
    lda (pObj),y
    sta t4
    ldy #O_HAIR
    ldx #HAIR_NODES
@node:
    lda #0
    sta (pObj),y
    iny
    lda t3
    sta (pObj),y
    iny
    lda #0
    sta (pObj),y
    iny
    lda t4
    sta (pObj),y
    iny
    dex
    bne @node
    rts

; set_hair_color: A = djump, as the cart's set_hair_color(djump). Leaves the
; sprite attribute byte in hair_col.
; The blob is one plane, so its colour is entirely the sprite entry's palette
; base - and which base reaches which colour is now a property of the generated
; draw palette, not of arithmetic. The generator emits the four the cart can
; ask for.
set_hair_color:
    cmp #1
    beq @red
    cmp #2
    beq @flash
    lda #PAL_ATTR_12           ; no dash left: blue
    jmp @done
@red:
    lda #PAL_ATTR_8
    jmp @done
@flash:
    ldx frames                  ; 7 + flr((frames/3)%2)*4, without a divide
    lda hair_flash,x
@done:
    sta hair_col
    rts

; frames is 0..29 and the cart wants (frames/3) & 1. Thirty bytes is cheaper
; than a division by three, and the table is the specification.
hair_flash:
    .byte PAL_ATTR_7,PAL_ATTR_7,PAL_ATTR_7
    .byte PAL_ATTR_11,PAL_ATTR_11,PAL_ATTR_11
    .byte PAL_ATTR_7,PAL_ATTR_7,PAL_ATTR_7
    .byte PAL_ATTR_11,PAL_ATTR_11,PAL_ATTR_11
    .byte PAL_ATTR_7,PAL_ATTR_7,PAL_ATTR_7
    .byte PAL_ATTR_11,PAL_ATTR_11,PAL_ATTR_11
    .byte PAL_ATTR_7,PAL_ATTR_7,PAL_ATTR_7
    .byte PAL_ATTR_11,PAL_ATTR_11,PAL_ATTR_11
    .byte PAL_ATTR_7,PAL_ATTR_7,PAL_ATTR_7
    .byte PAL_ATTR_11,PAL_ATTR_11,PAL_ATTR_11

draw_hair:
    ldy #O_FLIP                 ; last.x = x + 4 - facing*2
    lda (pObj),y
    and #1
    beq @faceright
    lda #6
    bne @lastx
@faceright:
    lda #2
@lastx:
    ldy #O_X
    clc
    adc (pObj),y
    sta hair_lx+1
    lda #0
    sta hair_lx

    lda btn                     ; last.y = y + (btn(down) and 4 or 3)
    and #BTN_D
    beq @lastup
    lda #4
    bne @lasty
@lastup:
    lda #3
@lasty:
    ldy #O_Y
    clc
    adc (pObj),y
    sta hair_ly+1
    lda #$80                    ; the cart's last.y + 0.5
    sta hair_ly

    lda #0
    sta hair_i
    lda #O_HAIR
    sta d_n                     ; field offset of the node being moved
@node:
    ldy d_n                     ; h.x += (last.x - h.x) * 0.625
    jsr obj_ldw
    lda hair_lx
    sta w1
    lda hair_lx+1
    sta w1+1
    jsr hair_chase
    ldy d_n
    jsr obj_stw
    lda w0
    sta hair_hx
    lda w0+1
    sta hair_hx+1

    lda d_n
    clc
    adc #2
    tay
    jsr obj_ldw
    lda hair_ly
    sta w1
    lda hair_ly+1
    sta w1+1
    jsr hair_chase
    lda d_n
    clc
    adc #2
    tay
    jsr obj_stw
    lda w0
    sta hair_hy
    lda w0+1
    sta hair_hy+1

    lda hair_hx                 ; this node becomes the next one's target
    sta hair_lx
    lda hair_hx+1
    sta hair_lx+1
    lda hair_hy
    sta hair_ly
    lda hair_hy+1
    sta hair_ly+1

    lda hair_col                ; blob size: 2, 2, 1, 1, 1
    sta t3
    lda hair_i
    cmp #2
    bcs @small
    lda hair_hx+1
    sec
    sbc #2
    sta t4
    lda hair_hy+1
    sec
    sbc #2
    sta t5
    lda #SPR_HAIR_BIG
    jmp @plot
@small:
    lda hair_hx+1
    sec
    sbc #1
    sta t4
    lda hair_hy+1
    sec
    sbc #1
    sta t5
    lda #SPR_HAIR_SMALL
@plot:
    pha
    lda t4                      ; the hair is in world space like the object
    clc
    adc shake_x
    sta t4
    lda t5
    sec
    sbc camera_y
    clc
    adc shake_y
    sta t5
    pla
    jsr stage_sprite

    lda d_n
    clc
    adc #4
    sta d_n
    inc hair_i
    lda hair_i
    cmp #HAIR_NODES
    beq @done
    jmp @node                   ; the node loop is longer than a branch reaches
@done:
    rts

; hair_chase: w0 += (w1 - w0) * 0.625, as two shifts and an add.
hair_chase:
    lda w1                      ; d = target - h
    sec
    sbc w0
    sta w2
    lda w1+1
    sbc w0+1
    sta w2+1

    lda w2                      ; w1 = d >> 1
    sta w1
    lda w2+1
    sta w1+1
    jsr asr_w1

    jsr asr_w2                  ; w2 = d >> 3
    jsr asr_w2
    jsr asr_w2

    lda w0
    clc
    adc w1
    sta w0
    lda w0+1
    adc w1+1
    sta w0+1
    lda w0
    clc
    adc w2
    sta w0
    lda w0+1
    adc w2+1
    sta w0+1
    rts

asr_w1:
    lda w1+1
    cmp #$80                    ; carry = the sign bit, so the shift is signed
    ror w1+1
    ror w1
    rts

asr_w2:
    lda w2+1
    cmp #$80
    ror w2+1
    ror w2
    rts

; ------------------------------------------------------------------------------
; The overlay: a 2400-byte shadow, because the hardware bitmap is write-only
; and the text has to be composed before it can be shown. Only rebuilt when
; something in it changed, which for this program is once a second.
; ------------------------------------------------------------------------------
ovl_init:
    lda #<OVLSHADOW
    sta pDst
    lda #>OVLSHADOW
    sta pDst+1
    ldx #0
@row:
    lda pDst
    sta OVLROW_LO,x
    lda pDst+1
    sta OVLROW_HI,x
    lda pDst
    clc
    adc #OVL_STRIDE
    sta pDst
    bcc @norow
    inc pDst+1
@norow:
    inx
    cpx #120
    bne @row
    jsr ovl_clear
    jmp ovl_mark_dirty

ovl_mark_dirty:
    lda #1
    sta ovl_dirty
    rts

ovl_clear:
    lda #0
    ldx #0
@page:
    sta OVLSHADOW+$000,x
    sta OVLSHADOW+$100,x
    sta OVLSHADOW+$200,x
    sta OVLSHADOW+$300,x
    sta OVLSHADOW+$400,x
    sta OVLSHADOW+$500,x
    sta OVLSHADOW+$600,x
    sta OVLSHADOW+$700,x
    sta OVLSHADOW+$800,x
    inx
    bne @page
@tail:
    sta OVLSHADOW+$900,x
    inx
    cpx #96
    bne @tail
    rts

; ovl_begin: decide whether this frame has to rebuild the overlay, and if so
; clear it and lay down the parts that are not an object's business.
ovl_begin:
    ldx #0                      ; a live room title redraws every frame
@find:
    txa
    jsr obj_ptr
    ldy #O_TYPE
    lda (pObj),y
    cmp #T_TITLE
    beq @yes
    inx
    cpx #OBJ_MAX
    bne @find
    jmp @check
@yes:
    jsr ovl_mark_dirty
@check:
    lda seconds                 ; and so does the clock, once a second
    cmp hud_secs
    beq @nochange
    sta hud_secs
    jsr ovl_mark_dirty
@nochange:
    lda ovl_dirty
    beq @done
    jsr ovl_clear
    jsr is_title                ; the title screen carries credits, not a HUD
    bne @hud
    jmp title_credits
@hud:
    jsr hud_draw
@done:
    rts

ovl_end:
    lda ovl_dirty
    bne @blit
    rts
@blit:
    lda #0
    sta ovl_dirty
    ldx #0
@page:
    lda OVLSHADOW+$000,x
    sta OVL+$000,x
    lda OVLSHADOW+$100,x
    sta OVL+$100,x
    lda OVLSHADOW+$200,x
    sta OVL+$200,x
    lda OVLSHADOW+$300,x
    sta OVL+$300,x
    lda OVLSHADOW+$400,x
    sta OVL+$400,x
    lda OVLSHADOW+$500,x
    sta OVL+$500,x
    lda OVLSHADOW+$600,x
    sta OVL+$600,x
    lda OVLSHADOW+$700,x
    sta OVL+$700,x
    lda OVLSHADOW+$800,x
    sta OVL+$800,x
    inx
    bne @page
@tail:
    lda OVLSHADOW+$900,x
    sta OVL+$900,x
    inx
    cpx #96
    bne @tail
    rts

; ------------------------------------------------------------------------------
; Text. A 3x5 font in a 4x6 cell, which is the proportion PICO-8's own font
; has; breakout and nemo both reached the same place for the same reason, which
; is that the sheet's 8x8 font is twice the size a PICO-8 port wants.
;
; Strings are glyph indices rather than ASCII - 0-9 are the digits, 10-35 the
; letters, 36 a colon, 37 a space - so there is no character translation at
; runtime and no font hole to check for.
; ------------------------------------------------------------------------------
    .define G_COLON            36
    .define G_SPACE            37
    .define G_PLUS             38
    .define G_END              $FF

ovl_putc:
    sta d_ch
    asl
    asl
    clc
    adc d_ch                    ; glyph * 5
    tax
    lda #0
    sta d_row
@row:
    lda font3x5,x
    sta d_bits
    lda #0
    sta d_n
    lda d_x
    and #7
    beq @placed
    tay
@shift:
    asl d_bits
    rol d_n
    dey
    bne @shift
@placed:
    lda d_y
    clc
    adc d_row
    tay
    lda OVLROW_LO,y
    sta pOvl
    lda OVLROW_HI,y
    sta pOvl+1
    lda d_x
    lsr
    lsr
    lsr
    tay
    lda (pOvl),y
    ora d_bits
    sta (pOvl),y
    iny
    lda (pOvl),y
    ora d_n
    sta (pOvl),y
    inx
    inc d_row
    lda d_row
    cmp #5
    bne @row
    lda d_x
    clc
    adc #4
    sta d_x
    rts

; ovl_text: print the glyph string at pSrc, starting at (d_x, d_y).
ovl_text:
    ldy #0
@ch:
    lda (pSrc),y
    cmp #G_END
    beq @done
    sty d_i
    jsr ovl_putc
    ldy d_i
    iny
    bne @ch
@done:
    rts

; ovl_str: A/X = string address, then print it.
ovl_str:
    sta pSrc
    stx pSrc+1
    jmp ovl_text

; ovl_byte: print A as two decimal digits.
;
; The units digit is parked in t7, NOT in d_ch: ovl_putc's first instruction is
; `sta d_ch`, so anything left there is gone by the time the first digit has
; been drawn. That cost a clock reading of 00:00 that every unit test agreed
; with, because the tests read `seconds` and not the pixels.
ovl_byte:
    ldx #0
@tens:
    cmp #10
    bcc @units
    sec
    sbc #10
    inx
    jmp @tens
@units:
    sta t7
    txa
    jsr ovl_putc
    lda t7
    jmp ovl_putc

; ------------------------------------------------------------------------------
; The HUD, in the 32 columns to the right of the 128-wide playfield. The cart
; has no HUD at all - it draws the clock over the room for thirty frames when a
; room starts - so this is the port using space the original did not have.
; ------------------------------------------------------------------------------
hud_draw:
    lda #132
    sta d_x
    lda #4
    sta d_y
    lda #<str_time
    ldx #>str_time
    jsr ovl_str

    lda #130
    sta d_x
    lda #11
    sta d_y
    lda minutes
    jsr ovl_byte
    lda #G_COLON
    jsr ovl_putc
    lda seconds
    jsr ovl_byte

    lda #132
    sta d_x
    lda #22
    sta d_y
    lda #<str_dead
    ldx #>str_dead
    jsr ovl_str

    lda #138
    sta d_x
    lda #29
    sta d_y
    lda deaths
    jmp ovl_byte

; ------------------------------------------------------------------------------
; title_credits: the cart's three prints on the title screen.
;
;   print("x+c",58,80,5) print("matt thorson",42,96,5) print("noel berry",46,102,5)
;
; The cart draws them in colour 5; the overlay has one colour register, so they
; are white here - the same limitation nemo records for its labels. The font is
; 3x5 uppercase, so the names are capitalised.
; ------------------------------------------------------------------------------
title_credits:
    lda #58
    sta d_x
    lda #80
    sta d_y
    lda #<str_xc
    ldx #>str_xc
    jsr ovl_str

    lda #42
    sta d_x
    lda #96
    sta d_y
    lda #<str_thorson
    ldx #>str_thorson
    jsr ovl_str

    lda #46
    sta d_x
    lda #102
    sta d_y
    lda #<str_berry
    ldx #>str_berry
    jmp ovl_str

; ------------------------------------------------------------------------------
; draw_room_title: the cart prints "old site" for room (3,1), "summit" for the
; last room, and (level+1)*100 .. " m" for everything else. The multiply by 100
; is not one: the last two digits are always "00", so only level+1 is printed.
;
; The cart draws a black panel behind the text with rectfill; the overlay has
; one colour and cannot, so the text sits directly over the room.
; ------------------------------------------------------------------------------
draw_room_title:
    lda level
    cmp #11
    beq @oldsite
    cmp #30
    beq @summit

    lda #52
    sta d_x
    lda #62
    sta d_y
    lda level
    clc
    adc #1
    jsr ovl_byte
    lda #0
    jsr ovl_putc
    lda #0
    jsr ovl_putc
    lda #G_SPACE
    jsr ovl_putc
    lda #22                     ; 'M'
    jmp ovl_putc

@oldsite:
    lda #48
    sta d_x
    lda #62
    sta d_y
    lda #<str_oldsite
    ldx #>str_oldsite
    jmp ovl_str

@summit:
    lda #52
    sta d_x
    lda #62
    sta d_y
    lda #<str_summit
    ldx #>str_summit
    jmp ovl_str

str_time:
    .byte 29,18,22,14, G_END            ; TIME
str_dead:
    .byte 13,14,10,13, G_END            ; DEAD
str_oldsite:
    .byte 24,21,13, G_SPACE, 28,18,29,14, G_END   ; OLD SITE
str_summit:
    .byte 28,30,22,22,18,29, G_END      ; SUMMIT
str_xc:
    .byte 33,38,12, G_END               ; X+C
str_thorson:
    .byte 22,10,29,29, G_SPACE, 29,17,24,27,28,24,23, G_END   ; MATT THORSON
str_berry:
    .byte 23,24,14,21, G_SPACE, 11,14,27,27,34, G_END         ; NOEL BERRY

; ------------------------------------------------------------------------------
; The font: 3 pixels wide in a 4-pixel cell, 5 rows, bit 0 leftmost - which is
; the overlay's own bit order, so a row is a literal picture of itself.
; ------------------------------------------------------------------------------
font3x5:
    .byte %010,%101,%101,%101,%010      ; 0
    .byte %010,%011,%010,%010,%111      ; 1
    .byte %011,%100,%010,%001,%111      ; 2
    .byte %011,%100,%010,%100,%011      ; 3
    .byte %101,%101,%111,%100,%100      ; 4
    .byte %111,%001,%011,%100,%011      ; 5
    .byte %110,%001,%011,%101,%010      ; 6
    .byte %111,%100,%010,%010,%010      ; 7
    .byte %010,%101,%010,%101,%010      ; 8
    .byte %010,%101,%110,%100,%011      ; 9
    .byte %010,%101,%111,%101,%101      ; A
    .byte %011,%101,%011,%101,%011      ; B
    .byte %110,%001,%001,%001,%110      ; C
    .byte %011,%101,%101,%101,%011      ; D
    .byte %111,%001,%011,%001,%111      ; E
    .byte %111,%001,%011,%001,%001      ; F
    .byte %110,%001,%101,%101,%110      ; G
    .byte %101,%101,%111,%101,%101      ; H
    .byte %111,%010,%010,%010,%111      ; I
    .byte %100,%100,%100,%101,%010      ; J
    .byte %101,%101,%011,%101,%101      ; K
    .byte %001,%001,%001,%001,%111      ; L
    .byte %101,%111,%111,%101,%101      ; M
    .byte %011,%101,%101,%101,%101      ; N
    .byte %010,%101,%101,%101,%010      ; O
    .byte %011,%101,%011,%001,%001      ; P
    .byte %010,%101,%101,%011,%110      ; Q
    .byte %011,%101,%011,%101,%101      ; R
    .byte %110,%001,%010,%100,%011      ; S
    .byte %111,%010,%010,%010,%010      ; T
    .byte %101,%101,%101,%101,%010      ; U
    .byte %101,%101,%101,%010,%010      ; V
    .byte %101,%101,%111,%111,%101      ; W
    .byte %101,%101,%010,%101,%101      ; X
    .byte %101,%101,%010,%010,%010      ; Y
    .byte %111,%100,%010,%001,%111      ; Z
    .byte %000,%010,%000,%010,%000      ; :
    .byte %000,%000,%000,%000,%000      ; space
    .byte %000,%010,%111,%010,%000      ; +
