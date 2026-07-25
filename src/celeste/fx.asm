; ------------------------------------------------------------------------------
; Celeste - the background: clouds behind the terrain, particles in front
;
; The cart draws both with rectfill() into PICO-8's framebuffer. This console
; has no rectangle primitive and its one framebuffer layer (the overlay) is
; 1bpp, single-colour and composited ABOVE everything - so it can carry the HUD
; or the clouds, not both.
;
; The sprite list solves it instead, because the list is ORDERED: the
; behind-split register ($4036) partitions it, and entries below the split
; composite BEFORE the tile layer. So clouds are staged first and come out
; behind the terrain; particles are staged last and come out in front. No
; hardware change, no framebuffer, and the compositor walks the list exactly
; once either way.
;
; THE CART'S COUNTS, EXACTLY. A first cut of this used 12 clouds and 16
; particles instead of the cart's 17 and 25, because a cloud is a RUN of 8x8
; cells and the cart's counts came to 133 entries - over the 128-entry list
; before the player existed. That is what motivated the compositor's repeat
; field ($4037, hardware-gaps entry 10): one entry now blits its row across up
; to eight cells, so a cloud costs ONE entry whatever its width.
;
;   17 clouds  = 17 entries   (was 102)
;   25 particles = 25 entries
;   player + hair = 6 entries
;                   -----------
;                   48 of 128
;
; The scanline was never the constraint - the engine scans one entry per clock
; and a 1bpp hit costs eight, leaving room for about thirty on a line - and now
; the list is not either.
; ------------------------------------------------------------------------------

    .define CLOUD_N            17
    .define PART_N             25

; ------------------------------------------------------------------------------
; fx_init: seed both from the hardware LFSR. Clobbers A, X.
; ------------------------------------------------------------------------------
fx_init:
    ldx #CLOUD_N-1
@cloud:
    lda SPR_RND                 ; x = rnd(128)
    and #$7F
    sta CL_XH,x
    lda #0
    sta CL_XL,x
    lda SPR_RND                 ; y = rnd(128)
    and #$7F
    sta CL_Y,x
    lda SPR_RND                 ; w = 4..7 cells, the cart's 32..64 pixels
    and #3
    clc
    adc #4
    sta CL_W,x
    lda SPR_RND                 ; spd = 1 + rnd(4), in 8.8
    and #3
    clc
    adc #1
    sta CL_SH,x
    lda SPR_RND
    sta CL_SL,x
    dex
    bpl @cloud

    ldx #PART_N-1
@part:
    lda SPR_RND
    and #$7F
    sta PA_XH,x
    lda SPR_RND
    sta PA_XL,x
    lda SPR_RND
    and #$7F
    sta PA_YH,x
    lda SPR_RND
    sta PA_YL,x
    lda SPR_RND                 ; spd = 0.25 + rnd(3), in 8.8
    and #3
    sta PA_SH,x
    lda SPR_RND
    ora #$40
    sta PA_SL,x
    lda SPR_RND                 ; the cart's c = 6 + flr(0.5 + rnd(1))
    and #1
    beq @grey
    lda #PAL_ATTR_7
    bne @setcol
@grey:
    lda #PAL_ATTR_6
@setcol:
    sta PA_ATTR,x
    lda SPR_RND
    sta PA_OFF,x
    dex
    bpl @part
    rts

; ------------------------------------------------------------------------------
; fx_update: the cart moves both inside _draw; the port moves them here, which
; is the same 30 Hz tick. Clobbers A, X, Y, t0.
; ------------------------------------------------------------------------------
fx_update:
    ldx #CLOUD_N-1
@cloud:
    lda CL_XL,x                 ; x += spd
    clc
    adc CL_SL,x
    sta CL_XL,x
    lda CL_XH,x
    adc CL_SH,x
    sta CL_XH,x

    ; The cart's `if c.x > 128 then c.x = -c.w`. x is one byte here, so "past
    ; the right edge" and "off the left, drifting back on" are BOTH negative-
    ; looking values and have to be told apart: a cloud is at most 64 px wide,
    ; so anything at or above 192 is still entering from the left.
    cmp #129
    bcc @nextcloud
    cmp #192
    bcs @nextcloud
    lda CL_W,x                  ; -w cells, in pixels
    asl
    asl
    asl
    eor #$FF
    clc
    adc #1
    sta CL_XH,x
    lda #0
    sta CL_XL,x
    lda SPR_RND
    and #$7F
    cmp #120
    bcc @keepy
    lda #119
@keepy:
    sta CL_Y,x
@nextcloud:
    dex
    bpl @cloud

    ldx #PART_N-1
@part:
    lda PA_XL,x                 ; x += spd
    clc
    adc PA_SL,x
    sta PA_XL,x
    lda PA_XH,x
    adc PA_SH,x
    sta PA_XH,x

    lda PA_OFF,x                ; off += spd/32, capped at the cart's 0.05
    clc
    adc #13
    sta PA_OFF,x
    lsr                         ; y += sin(off), from a 16-step table
    lsr
    lsr
    lsr
    tay
    lda PA_YL,x
    clc
    adc sin16_lo,y
    sta PA_YL,x
    lda PA_YH,x
    adc sin16_hi,y
    sta PA_YH,x

    lda PA_XH,x                 ; if x > 132 then x = -4, y = rnd(128); same
    cmp #133                    ; two-sided test as the clouds above
    bcc @nextpart
    cmp #192
    bcs @nextpart
    lda #$FC
    sta PA_XH,x
    lda SPR_RND
    and #$7F
    sta PA_YH,x
@nextpart:
    dex
    bpl @part
    rts

; sin(off) over a full turn, 8.8 signed. The cart adds sin() straight to y, so
; a particle bobs one pixel either way as it drifts.
sin16_lo:
    .byte $00,$62,$B5,$ED,$00,$ED,$B5,$62,$00,$9E,$4B,$13,$00,$13,$4B,$9E
sin16_hi:
    .byte $00,$00,$00,$00,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF

; ------------------------------------------------------------------------------
; fx_draw_clouds: staged FIRST, so that everything here lands below the
; behind-split and composites before the tile layer. Clobbers A, X, Y, t3..t6.
; ------------------------------------------------------------------------------
fx_draw_clouds:
    ldx #0
@cloud:
    stx t6
    lda CL_Y,x                  ; clouds do not scroll with the camera: they
    sec                         ; are sky, and the cart's camera never moves
    sbc camera_y
    sta t5
    lda #PAL_ATTR_1
    sta t3
    lda CL_XH,x
    sta t4
    lda CL_W,x                  ; the whole cloud is ONE entry: the compositor
    sta SPR_REP                 ; repeats the fetched row across its cells
    lda #SPR_SOLID
    jsr stage_sprite
    ldx t6
    inx
    cpx #CLOUD_N
    bne @cloud
    rts

; ------------------------------------------------------------------------------
; fx_draw_particles: staged LAST, above the split, so they sit in front of the
; terrain and the player - which is where the cart draws them, and is what
; puts the stars on the title screen. Clobbers A, X, Y, t3..t6.
; ------------------------------------------------------------------------------
fx_draw_particles:
    lda #1                      ; back to single cells for everything else
    sta SPR_REP
    ldx #0
@part:
    stx t6
    lda PA_ATTR,x
    sta t3
    lda PA_XH,x
    sta t4
    lda PA_YH,x
    sec
    sbc camera_y
    sta t5
    lda #SPR_DOT
    jsr stage_sprite
    ldx t6
    inx
    cpx #PART_N
    bne @part
    rts
