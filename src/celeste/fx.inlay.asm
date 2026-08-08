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
    export burst
    export draw_burst
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
    burst_count = 8

; ------------------------------------------------------------------------------
; init: seed both from the hardware LFSR. Clobbers A, X.
; ------------------------------------------------------------------------------
proc init using console6502 naked
begin
    ldx #cloud_count-1
.cloud:
    lda [video.random]                 ; x = rnd(128)
    and #$7F
    sta [effects.cloud_x_high[x]]
    lda #0
    sta [effects.cloud_x_low[x]]
    lda [video.random]                 ; y = rnd(128)
    and #$7F
    sta [effects.cloud_y[x]]
    lda [video.random]                 ; w = 4..7 cells, the cart's 32..64 pixels
    and #3
    add #4
    sta [effects.cloud_width[x]]
    lda [video.random]                 ; spd = 1 + rnd(4), in 8.8
    and #3
    add #1
    sta [effects.cloud_speed_high[x]]
    lda [video.random]
    sta [effects.cloud_speed_low[x]]
    dex
    bpl .cloud

    ldx #particle_count-1
.part:
    lda [video.random]                 ; x = rnd over the full 160 columns:
    cmp #160                    ; the title shows all of them, gameplay
    bcc .xok                    ; clips at 128 like the cart's screen
    sub #160
.xok:
    sta [effects.particle_x_high[x]]
    lda [video.random]
    sta [effects.particle_x_low[x]]
    lda [video.random]
    and #$7F
    sta [effects.particle_y_high[x]]
    lda [video.random]
    sta [effects.particle_y_low[x]]
    lda [video.random]                 ; spd = 0.25 + rnd(3), in 8.8
    and #3
    sta [effects.particle_speed_high[x]]
    lda [video.random]
    ora #$40
    sta [effects.particle_speed_low[x]]
    lda [video.random]                 ; the cart's c = 6 + flr(0.5 + rnd(1))
    and #1
    beq .grey
    lda #Gfx.palette_7
    bne .setcol
.grey:
    lda #Gfx.palette_6
.setcol:
    ; attribute bit 0 rides along as the size: the cart's s = flr(rnd(5)/4)
    ; makes one flake in five the 2x2 dot, the rest single pixels. The
    ; stager masks the bit back out of the hardware attribute.
    pha
    lda [video.random]
    and #15
    cmp #3
    pla
    bcs .speck
    ora #1
.speck:
    sta [effects.particle_attribute[x]]
    lda [video.random]
    sta [effects.particle_offset[x]]
    dex
    bpl .part
    lda #0
    sta [dead_burst.timer]
    ret
end

; ------------------------------------------------------------------------------
; burst: start the cart's dead_particles - eight fragments radiating from the
; kill point at 3 px/frame for ten frames. All eight share one timer; the
; per-direction 8.8 speeds are the constants below. Clobbers A, X, t3, t4.
; ------------------------------------------------------------------------------
proc burst using console6502 naked
    center_x : u8 in a
    center_y : u8 in x
begin
    sta Machine.t3
    stx Machine.t4
    ldx #burst_count-1
.seed:
    lda Machine.t3
    sta [dead_burst.x_high[x]]
    lda Machine.t4
    sta [dead_burst.y_high[x]]
    lda #0
    sta [dead_burst.x_low[x]]
    sta [dead_burst.y_low[x]]
    dex
    bpl .seed
    lda #10
    sta [dead_burst.timer]
    ret
end

; sin/cos of dir/8 turns, times 3, in 8.8: the cart's fragment velocities.
burst_sx_low:
    #d8 $00, $E1, $00, $E1, $00, $1F, $00, $1F
burst_sx_high:
    #d8 $00, $FD, $FD, $FD, $00, $02, $03, $02
burst_sy_low:
    #d8 $00, $1F, $00, $E1, $00, $E1, $00, $1F
burst_sy_high:
    #d8 $03, $02, $00, $FD, $FD, $FD, $00, $02

; ------------------------------------------------------------------------------
; update: the cart moves both inside _draw; the port moves them here, which
; is the same 30 Hz tick. Clobbers A, X, Y, t0.
; ------------------------------------------------------------------------------
proc update using console6502 naked
begin
    mov Machine.t0, #133        ; particle respawn bound: past the playfield
    jsr Room.title              ; in play, past the full 160 on the title
    bne .bounded
    mov Machine.t0, #165
.bounded:
    ldx #cloud_count-1
.cloud:
    lda [effects.cloud_x_low[x]]                 ; x += spd
    clc
    adc [effects.cloud_speed_low[x]]
    sta [effects.cloud_x_low[x]]
    lda [effects.cloud_x_high[x]]
    adc [effects.cloud_speed_high[x]]
    sta [effects.cloud_x_high[x]]

    ; The cart's `if c.x > 128 then c.x = -c.w`. x is one byte here, so "past
    ; the right edge" and "off the left, drifting back on" are BOTH negative-
    ; looking values and have to be told apart: a cloud is at most 64 px wide,
    ; so anything at or above 192 is still entering from the left.
    cmp #129
    bcc .nextcloud
    cmp #192
    bcs .nextcloud
    lda [effects.cloud_width[x]]                  ; -w cells, in pixels
    asl a, 3
    eor #$FF
    add #1
    sta [effects.cloud_x_high[x]]
    lda #0
    sta [effects.cloud_x_low[x]]
    lda [video.random]
    and #$7F
    cmp #120
    bcc .keepy
    lda #119
.keepy:
    sta [effects.cloud_y[x]]
.nextcloud:
    dex
    bpl .cloud

    ldx #particle_count-1
.part:
    lda [effects.particle_x_low[x]]                 ; x += spd
    clc
    adc [effects.particle_speed_low[x]]
    sta [effects.particle_x_low[x]]
    lda [effects.particle_x_high[x]]
    adc [effects.particle_speed_high[x]]
    sta [effects.particle_x_high[x]]

    lda [effects.particle_offset[x]]                ; off += spd/32, capped at the cart's 0.05
    add #13
    sta [effects.particle_offset[x]]
    lsr a, 4                    ; y += sin(off), from a 16-step table
    tay
    lda [effects.particle_y_low[x]]
    clc
    adc sin_low, y
    sta [effects.particle_y_low[x]]
    lda [effects.particle_y_high[x]]
    adc sin_high, y
    sta [effects.particle_y_high[x]]

    lda [effects.particle_x_high[x]]                 ; if x > bound then x = -4, y = rnd(128);
    cmp Machine.t0              ; same two-sided test as the clouds above
    bcc .nextpart
    cmp #192
    bcs .nextpart
    lda #$FC
    sta [effects.particle_x_high[x]]
    lda [video.random]
    and #$7F
    sta [effects.particle_y_high[x]]
.nextpart:
    dex
    bpl .part

    lda [dead_burst.timer]      ; age the death burst and fly its fragments
    beq .noburst
    sub #1
    sta [dead_burst.timer]
    ldx #burst_count-1
.frag:
    lda [dead_burst.x_low[x]]
    clc
    adc burst_sx_low, x
    sta [dead_burst.x_low[x]]
    lda [dead_burst.x_high[x]]
    adc burst_sx_high, x
    sta [dead_burst.x_high[x]]
    lda [dead_burst.y_low[x]]
    clc
    adc burst_sy_low, x
    sta [dead_burst.y_low[x]]
    lda [dead_burst.y_high[x]]
    adc burst_sy_high, x
    sta [dead_burst.y_high[x]]
    dex
    bpl .frag
.noburst:
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
    stx Machine.t6
    lda [effects.cloud_y[x]]                  ; clouds do not scroll with the camera: they
    sub [game.camera_y]
    sta Machine.t5
    mov Machine.t3, #Gfx.palette_1
    mov Machine.t4, cloud_x_high + x
    lda [effects.cloud_width[x]]                  ; the whole cloud is ONE entry: the compositor
    sta [video.repeat]                 ; repeats the fetched row across its cells
    lda #Gfx.solid
    jsr Draw.sprite
    ldx Machine.t6
    inx
    cpx #cloud_count
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
    mov [video.repeat], #1
    ldx #0
.part:
    stx Machine.t6
    lda [effects.particle_attribute[x]]
    and #$F0                    ; strip the size bit before the hardware sees it
    sta Machine.t3
    mov Machine.t4, particle_x_high + x
    lda [effects.particle_y_high[x]]
    sub [game.camera_y]
    sta Machine.t5
    lda [effects.particle_attribute[x]]
    lsr a
    lda #Gfx.speck
    bcc .sized
    lda #Gfx.dot
.sized:
    jsr Draw.sprite
    ldx Machine.t6
    inx
    cpx #particle_count
    bne .part
    ret
end

; ------------------------------------------------------------------------------
; draw_burst: stage the death burst last, in front of everything, where the
; cart draws its dead particles. The cart's square has a t/5 radius in colour
; 14+t%2: the 4x4 blob carries the big half of the life, the dot the tail,
; alternating the two pinks by remaining time. Clobbers A, X, Y, t3..t6.
; ------------------------------------------------------------------------------
proc draw_burst using console6502 naked
begin
    lda [dead_burst.timer]
    bne .live
    ret
.live:
    mov [video.repeat], #1
    ldx #0
.frag:
    stx Machine.t6
    lda [dead_burst.timer]
    and #1
    beq .pink
    lda #Gfx.palette_15
    bne .colour
.pink:
    lda #Gfx.palette_14
.colour:
    sta Machine.t3
    lda [dead_burst.timer]
    cmp #5
    bcc .small
    lda [dead_burst.x_high[x]]
    sub #2
    sta Machine.t4
    lda [dead_burst.y_high[x]]
    sub #2
    sub [game.camera_y]
    sta Machine.t5
    lda #Gfx.blob
    bne .stage
.small:
    lda [dead_burst.x_high[x]]
    sta Machine.t4
    lda [dead_burst.y_high[x]]
    sub [game.camera_y]
    sta Machine.t5
    lda #Gfx.dot
.stage:
    jsr Draw.sprite
    ldx Machine.t6
    inx
    cpx #burst_count
    bne .frag
    ret
end
end
