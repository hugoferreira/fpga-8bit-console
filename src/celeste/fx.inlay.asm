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

namespace Fx
    export init
    export update
    export draw_clouds
    export draw_particles
    location cloud_x_low : u8 at $5600
    location cloud_x_high : u8 at $5620
    location cloud_y : u8 at $5640
    location cloud_width : u8 at $5660
    location cloud_speed_low : u8 at $5680
    location cloud_speed_high : u8 at $56a0
    location particle_x_low : u8 at $56c0
    location particle_x_high : u8 at $56e0
    location particle_y_low : u8 at $5700
    location particle_y_high : u8 at $5720
    location particle_speed_low : u8 at $5740
    location particle_speed_high : u8 at $5760
    location particle_attribute : u8 at $5780
    location particle_offset : u8 at $57a0

    cloud_count = 17
    particle_count = 25

; ------------------------------------------------------------------------------
; init: seed both from the hardware LFSR. Clobbers A, X.
; ------------------------------------------------------------------------------
proc init using console6502 naked
begin
    ldx #Fx.cloud_count-1
.cloud:
    lda [video + VideoRegisters.random]                 ; x = rnd(128)
    and #$7F
    sta CL_XH, x
    lda #0
    sta CL_XL, x
    lda [video + VideoRegisters.random]                 ; y = rnd(128)
    and #$7F
    sta CL_Y, x
    lda [video + VideoRegisters.random]                 ; w = 4..7 cells, the cart's 32..64 pixels
    and #3
    add #4
    sta CL_W, x
    lda [video + VideoRegisters.random]                 ; spd = 1 + rnd(4), in 8.8
    and #3
    add #1
    sta CL_SH, x
    lda [video + VideoRegisters.random]
    sta CL_SL, x
    dex
    bpl .cloud

    ldx #Fx.particle_count-1
.part:
    lda [video + VideoRegisters.random]
    and #$7F
    sta PA_XH, x
    lda [video + VideoRegisters.random]
    sta PA_XL, x
    lda [video + VideoRegisters.random]
    and #$7F
    sta PA_YH, x
    lda [video + VideoRegisters.random]
    sta PA_YL, x
    lda [video + VideoRegisters.random]                 ; spd = 0.25 + rnd(3), in 8.8
    and #3
    sta PA_SH, x
    lda [video + VideoRegisters.random]
    ora #$40
    sta PA_SL, x
    lda [video + VideoRegisters.random]                 ; the cart's c = 6 + flr(0.5 + rnd(1))
    and #1
    beq .grey
    lda #Gfx.palette_7
    bne .setcol
.grey:
    lda #Gfx.palette_6
.setcol:
    sta PA_ATTR, x
    lda [video + VideoRegisters.random]
    sta PA_OFF, x
    dex
    bpl .part
    ret
end

; ------------------------------------------------------------------------------
; update: the cart moves both inside _draw; the port moves them here, which
; is the same 30 Hz tick. Clobbers A, X, Y, t0.
; ------------------------------------------------------------------------------
proc update using console6502 naked
begin
    ldx #Fx.cloud_count-1
.cloud:
    lda CL_XL, x                 ; x += spd
    clc
    adc CL_SL, x
    sta CL_XL, x
    lda CL_XH, x
    adc CL_SH, x
    sta CL_XH, x

    ; The cart's `if c.x > 128 then c.x = -c.w`. x is one byte here, so "past
    ; the right edge" and "off the left, drifting back on" are BOTH negative-
    ; looking values and have to be told apart: a cloud is at most 64 px wide,
    ; so anything at or above 192 is still entering from the left.
    cmp #129
    bcc .nextcloud
    cmp #192
    bcs .nextcloud
    lda CL_W, x                  ; -w cells, in pixels
    asl
    asl
    asl
    eor #$FF
    add #1
    sta CL_XH, x
    lda #0
    sta CL_XL, x
    lda [video + VideoRegisters.random]
    and #$7F
    cmp #120
    bcc .keepy
    lda #119
.keepy:
    sta CL_Y, x
.nextcloud:
    dex
    bpl .cloud

    ldx #Fx.particle_count-1
.part:
    lda PA_XL, x                 ; x += spd
    clc
    adc PA_SL, x
    sta PA_XL, x
    lda PA_XH, x
    adc PA_SH, x
    sta PA_XH, x

    lda PA_OFF, x                ; off += spd/32, capped at the cart's 0.05
    add #13
    sta PA_OFF, x
    lsr                         ; y += sin(off), from a 16-step table
    lsr
    lsr
    lsr
    tay
    lda PA_YL, x
    clc
    adc Fx.sin_low, y
    sta PA_YL, x
    lda PA_YH, x
    adc Fx.sin_high, y
    sta PA_YH, x

    lda PA_XH, x                 ; if x > 132 then x = -4, y = rnd(128); same
    cmp #133                    ; two-sided test as the clouds above
    bcc .nextpart
    cmp #192
    bcs .nextpart
    lda #$FC
    sta PA_XH, x
    lda [video + VideoRegisters.random]
    and #$7F
    sta PA_YH, x
.nextpart:
    dex
    bpl .part
    ret
end

; sin(off) over a full turn, 8.8 signed. The cart adds sin() straight to y, so
; a particle bobs one pixel either way as it drifts.
sin_low:
    #d8 $00, $62, $B5, $ED, $00, $ED, $B5, $62, $00, $9E, $4B, $13, $00, $13, $4B, $9E
sin_high:
    #d8 $00, $00, $00, $00, $01, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF

; ------------------------------------------------------------------------------
; draw_clouds: staged FIRST, so that everything here lands below the
; behind-split and composites before the tile layer. Clobbers A, X, Y, t3..t6.
; ------------------------------------------------------------------------------
proc draw_clouds using console6502 naked
begin
    ldx #0
.cloud:
    stx t6
    lda CL_Y, x                  ; clouds do not scroll with the camera: they
    sub camera_y
    sta t5
    mov t3, #Gfx.palette_1
    mov t4, CL_XH + x
    lda CL_W, x                  ; the whole cloud is ONE entry: the compositor
    sta [video + VideoRegisters.repeat]                 ; repeats the fetched row across its cells
    lda #Gfx.solid
    jsr Draw.sprite
    ldx t6
    inx
    cpx #Fx.cloud_count
    bne .cloud
    ret
end

; ------------------------------------------------------------------------------
; draw_particles: staged LAST, above the split, so they sit in front of the
; terrain and the player - which is where the cart draws them, and is what
; puts the stars on the title screen. Clobbers A, X, Y, t3..t6.
; ------------------------------------------------------------------------------
proc draw_particles using console6502 naked
begin
    mov [video + VideoRegisters.repeat], #1
    ldx #0
.part:
    stx t6
    mov t3, PA_ATTR + x
    mov t4, PA_XH + x
    lda PA_YH, x
    sub camera_y
    sta t5
    lda #Gfx.dot
    jsr Draw.sprite
    ldx t6
    inx
    cpx #Fx.particle_count
    bne .part
    ret
end
end
