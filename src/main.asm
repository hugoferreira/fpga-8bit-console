.segment "CODE"
    ; ------------------------------------------------------------------------------
    ; BREAKOUT HERO - port of Krystman's PICO-8 cart to this console
    ; ------------------------------------------------------------------------------
    ; Original game (c) Krystman / Lazy Devs Academy (PICO-8 BBS cart 53976).
    ; Level layouts and paddle/ball art come from the cart; this 6502 game
    ; code is an original implementation written for this hardware.
    ;
    ; Arena: tile cols 1 and 13 are walls, bricks in an 11-wide grid at tile
    ; cols 2-12, rows 2-11. Interior pixels x 16..103, top y 16, open bottom.
    ; Right side (cols 14+) is the HUD. Ball and paddle are sprites; bricks
    ; are tilemap cells; messages use the 4x6 overlay font.

    ; PPU registers
    .define SPR_SHADDR_LO      $4000
    .define SPR_SHADDR_HI      $4001
    .define SPR_SHDATA         $4002
    .define SPR_CTRL           $4005
    .define SPR_OVLCOL         $4006
    .define SPR_BTN            $4007
    .define SPR_INDEX          $4008
    .define SPR_X              $4009
    .define SPR_Y              $400A
    .define SPR_FLAGS          $400B
    .define SPR_COUNT          $400C
    .define SPR_FRAME          $400D
    .define SPR_BASE           $400E
    .define SPR_PALT           $4034

    .define MAP_LO             $F000
    .define MAP_HI             $F200
    .define OVL                $E000

    ; Buttons
    .define BTN_L              $01
    .define BTN_R              $02
    .define BTN_X              $20

    ; Geometry
    .define ARENA_L            16     ; interior left edge
    .define ARENA_R            104    ; interior right edge (exclusive)
    .define ARENA_T            16     ; interior top edge
    .define PAD_Y              106    ; paddle sprite y
    .define PAD_MIN            16
    .define PAD_MAX            91     ; 13px paddle in the 88px interior
    .define BALL_DEATH         118

    ; Game states
    .define ST_SERVE           0
    .define ST_PLAY            1
    .define ST_OVER            2

    ; Zero page
    .define ballx   $04    ; 8.8: frac, int
    .define bally   $06
    .define bvx     $08    ; signed 8.8
    .define bvy     $0A
    .define padx    $0C
    .define state   $0D
    .define lives   $0E
    .define level   $0F    ; 0-based
    .define score0  $10    ; BCD, low digits first
    .define score1  $11
    .define score2  $12
    .define bricksn $13
    .define tmp     $14
    .define tmp2    $15
    .define btn     $16
    .define btnprev $17
    .define blink   $18
    .define ptr     $19    ; and $1A
    .define rowv    $1B
    .define colv    $1C
    .define hitr    $1D
    .define hitc    $1E
    .define tmp3    $1F
    .define servedx $20
    .define ptr2    $22    ; and $23

    ; Brick shadow map: 10 rows x 11 cols
    .define shadow  $0C00

; ------------------------------------------------------------------------------
start:
    ; Upload game patterns to sheet slots 0-39 (font at 128+ is preloaded)
    lda #0
    sta SPR_SHADDR_LO
    sta SPR_SHADDR_HI
    ldx #0
@gfx1:
    lda gfx_data,x
    sta SPR_SHDATA
    inx
    bne @gfx1
    ldx #0
@gfx2:
    lda gfx_data+256,x
    sta SPR_SHDATA
    inx
    cpx #64
    bne @gfx2

    ; Clear the whole tilemap and overlay
    ldx #0
    lda #0
@clrmap:
    sta MAP_LO,x
    sta MAP_LO+256,x
    sta MAP_HI,x
    sta MAP_HI+256,x
    inx
    bne @clrmap
    ldx #0
    lda #0
@clrovl:
    sta OVL,x
    sta OVL+$100,x
    sta OVL+$200,x
    sta OVL+$300,x
    sta OVL+$400,x
    sta OVL+$500,x
    sta OVL+$600,x
    sta OVL+$700,x
    sta OVL+$800,x
    sta OVL+$900,x
    inx
    bne @clrovl

    ; Walls: top row 1 (cols 1-13), sides cols 1 and 13 (rows 1-14)
    ldx #1
@topwall:
    lda #36            ; wall pattern base
    sta MAP_LO+32,x    ; row 1 starts at cell 32
    lda #$0C           ; 4bpp, pal 0
    sta MAP_HI+32,x
    inx
    cpx #14
    bne @topwall
    ldx #1
@sidewall:
    lda rowmap_lo,x
    sta ptr
    lda rowmap_hi,x
    sta ptr+1
    ldy #1
    lda #36
    sta (ptr),y
    ldy #13
    sta (ptr),y
    lda ptr+1
    clc
    adc #2             ; MAP_HI page = MAP_LO page + $200
    sta ptr+1
    ldy #1
    lda #$0C
    sta (ptr),y
    ldy #13
    sta (ptr),y
    inx
    cpx #15
    bne @sidewall

    ; HUD labels (font tiles, white): SCORE / BALLS / LEVEL in col 14+
    ldx #0
@hud1:
    lda txt_score,x
    ora #$80
    sta MAP_LO+32+14,x     ; row 1
    lda #$60
    sta MAP_HI+32+14,x
    inx
    cpx #5
    bne @hud1
    ldx #0
@hud2:
    lda txt_balls,x
    ora #$80
    sta MAP_LO+128+14,x    ; row 4
    lda #$60
    sta MAP_HI+128+14,x
    inx
    cpx #5
    bne @hud2
    ldx #0
@hud3:
    lda txt_level,x
    ora #$80
    sta MAP_LO+224+14,x    ; row 7
    lda #$60
    sta MAP_HI+224+14,x
    inx
    cpx #5
    bne @hud3

    ; PPU on: tilemap + overlay, white overlay text
    lda #7
    sta SPR_OVLCOL
    lda #3
    sta SPR_CTRL

    jsr new_game

; ------------------------------------------------------------------------------
main_loop:
    lda SPR_FRAME
@wf: cmp SPR_FRAME
    beq @wf

    lda btn
    sta btnprev
    lda SPR_BTN
    sta btn
    inc blink

    lda state
    cmp #ST_PLAY
    bne @notplay
    jmp do_play
@notplay:
    cmp #ST_SERVE
    beq do_serve
    jmp do_over

; --- serve: ball rides the paddle, X launches ---------------------------------
do_serve:
    jsr move_paddle
    lda padx
    clc
    adc #4
    sta ballx+1
    lda #0
    sta ballx
    sta bally
    lda #98
    sta bally+1
    ; blink PRESS X
    lda blink
    and #$0F
    bne @noblk
    jsr msg_clear
    lda blink
    and #$10
    bne @noblk
    jsr msg_press
@noblk:
    lda btn
    and #BTN_X
    beq @done
    lda btnprev
    and #BTN_X
    bne @done
    jsr msg_clear
    lda #ST_PLAY
    sta state
    ; serve vector: dy = -1.25, dx = +/-0.75 alternating
    lda #$C0
    sta bvy
    lda #$FE
    sta bvy+1
    lda servedx
    eor #1
    sta servedx
    beq @sleft
    lda #$C0
    sta bvx
    lda #$00
    sta bvx+1
    jmp @done
@sleft:
    lda #$40
    sta bvx
    lda #$FF
    sta bvx+1
@done:
    jmp frame_end

; --- game over -----------------------------------------------------------------
do_over:
    lda btn
    and #BTN_X
    beq @done
    lda btnprev
    and #BTN_X
    bne @done
    jsr msg_clear
    jsr new_game
@done:
    jmp frame_end

; --- play ----------------------------------------------------------------------
do_play:
    jsr move_paddle

    ; ball position += velocity (16-bit signed adds)
    lda ballx
    clc
    adc bvx
    sta ballx
    lda ballx+1
    adc bvx+1
    sta ballx+1
    lda bally
    clc
    adc bvy
    sta bally
    lda bally+1
    adc bvy+1
    sta bally+1

    ; walls (ball box is sprite+2 .. sprite+5)
    lda ballx+1
    cmp #ARENA_L-1
    bcs @notleft
    lda #ARENA_L-1
    sta ballx+1
    jsr negx
@notleft:
    lda ballx+1
    cmp #ARENA_R-7
    bcc @notright
    lda #ARENA_R-7
    sta ballx+1
    jsr negx
@notright:
    lda bally+1
    cmp #ARENA_T-1
    bcs @nottop
    lda #ARENA_T-1
    sta bally+1
    jsr negy
@nottop:

    ; death?
    lda bally+1
    cmp #BALL_DEATH
    bcc @alive
    dec lives
    jsr draw_hud
    lda lives
    beq @gameover
    lda #ST_SERVE
    sta state
    lda #0
    sta blink
    jmp frame_end
@gameover:
    lda #ST_OVER
    sta state
    jsr msg_over
    lda #124
    sta bally+1            ; park the dead ball off-screen
    jmp frame_end
@alive:

    ; paddle bounce (moving down, box bottom in paddle band, x overlap)
    lda bvy+1
    bmi @nopad
    lda bally+1
    cmp #PAD_Y-4
    bcc @nopad
    cmp #PAD_Y+2
    bcs @nopad
    lda ballx+1
    sec
    sbc padx
    clc
    adc #6                 ; 0..19 when overlapping
    cmp #20
    bcs @nopad
    lsr
    lsr                    ; zone 0..4
    cmp #5
    bcc @zok
    lda #4
@zok:
    tay
    lda bvx+1
    sta tmp3               ; remember travel direction
    lda zone_vx_lo,y
    sta bvx
    lda zone_vx_hi,y
    sta bvx+1
    lda zone_vy_lo,y
    sta bvy
    lda zone_vy_hi,y
    sta bvy+1
    cpy #2
    bne @nopad
    lda tmp3               ; center zone keeps horizontal direction
    bpl @nopad
    jsr negx
@nopad:

    ; --- brick collisions: probe ahead of the ball center on each axis ---
    lda ballx+1
    clc
    adc #3
    sta tmp                ; cx
    lda bally+1
    clc
    adc #3
    sta tmp2               ; cy
    ; horizontal probe (cx +/- 3, cy)
    lda tmp
    ldy bvx+1
    bmi @hneg
    clc
    adc #3
    jmp @hgo
@hneg:
    sec
    sbc #3
@hgo:
    tax
    ldy tmp2
    jsr probe_brick
    bcc @noh
    jsr brick_hit
    jsr negx
@noh:
    ; vertical probe (cx, cy +/- 3)
    lda tmp2
    ldy bvy+1
    bmi @vneg
    clc
    adc #3
    jmp @vgo
@vneg:
    sec
    sbc #3
@vgo:
    tay
    ldx tmp
    jsr probe_brick
    bcc @nov
    jsr brick_hit
    jsr negy
@nov:

    ; level cleared?
    lda bricksn
    bne @go
    ldx level
    inx
    cpx #15
    bcc @lv
    ldx #0
@lv:
    stx level
    jsr build_level
    jsr draw_hud
    lda #ST_SERVE
    sta state
@go:
    jmp frame_end

; ------------------------------------------------------------------------------
; probe_brick: X = pixel x, Y = pixel y -> C set if a brick cell is there.
; Cell coords left in hitr/hitc.
probe_brick:
    txa
    sec
    sbc #ARENA_L
    bcc @miss
    lsr
    lsr
    lsr
    cmp #11
    bcs @miss
    sta hitc
    tya
    sec
    sbc #ARENA_T
    bcc @miss
    lsr
    lsr
    lsr
    cmp #10
    bcs @miss
    sta hitr
    tax
    lda times11,x
    clc
    adc hitc
    tay
    lda shadow,y
    beq @miss
    sec
    rts
@miss:
    clc
    rts

; ------------------------------------------------------------------------------
; brick_hit: damage the cell at (hitr, hitc)
brick_hit:
    ldx hitr
    lda times11,x
    clc
    adc hitc
    tay
    ldx shadow,y           ; X = type code
    sed                    ; score += points[type] (BCD)
    lda score0
    clc
    adc type_pts,x
    sta score0
    lda score1
    adc #0
    sta score1
    lda score2
    adc #0
    sta score2
    cld
    lda type_next,x
    sta shadow,y
    pha
    bne @tile              ; still standing (damaged or indestructible)
    cpx #4
    beq @tile
    dec bricksn
@tile:
    ; rewrite the map cell at row hitr+2, col hitc+2
    ldx hitr
    lda rowmap2_lo,x
    sta ptr2
    lda rowmap2_hi,x
    sta ptr2+1
    pla
    tax                    ; X = new type
    ldy hitc
    iny
    iny
    lda type_tile,x
    sta (ptr2),y           ; MAP_LO
    lda ptr2+1
    clc
    adc #2
    sta ptr2+1
    lda type_hi,x
    sta (ptr2),y           ; MAP_HI
    jsr draw_hud
    rts

; ------------------------------------------------------------------------------
negx:
    sec
    lda #0
    sbc bvx
    sta bvx
    lda #0
    sbc bvx+1
    sta bvx+1
    rts
negy:
    sec
    lda #0
    sbc bvy
    sta bvy
    lda #0
    sbc bvy+1
    sta bvy+1
    rts

; ------------------------------------------------------------------------------
move_paddle:
    lda btn
    and #BTN_L
    beq @notl
    lda padx
    sec
    sbc #3
    cmp #PAD_MIN
    bcs @stl
    lda #PAD_MIN
@stl:
    sta padx
@notl:
    lda btn
    and #BTN_R
    beq @notr
    lda padx
    clc
    adc #3
    cmp #PAD_MAX
    bcc @str
    lda #PAD_MAX
@str:
    sta padx
@notr:
    rts

; ------------------------------------------------------------------------------
frame_end:
    ; stream sprites: ball + two paddle halves
    lda #0
    sta SPR_INDEX
    lda ballx+1
    sta SPR_X
    lda bally+1
    sta SPR_Y
    lda #0
    sta SPR_BASE
    lda #$0C               ; 4bpp, pal 0
    sta SPR_FLAGS
    lda padx
    sta SPR_X
    lda #PAD_Y
    sta SPR_Y
    lda #4
    sta SPR_BASE
    lda #$0C
    sta SPR_FLAGS
    lda padx
    clc
    adc #5
    sta SPR_X
    lda #PAD_Y
    sta SPR_Y
    lda #8
    sta SPR_BASE
    lda #$0C
    sta SPR_FLAGS
    lda #3
    sta SPR_COUNT
    jmp main_loop

; ------------------------------------------------------------------------------
new_game:
    lda #0
    sta score0
    sta score1
    sta score2
    sta level
    sta servedx
    lda #3
    sta lives
    lda #52
    sta padx
    jsr build_level
    jsr draw_hud
    lda #ST_SERVE
    sta state
    rts

; ------------------------------------------------------------------------------
; build_level: unpack level_data[level] into the shadow map and the tilemap
build_level:
    ldy #109
    lda #0
@cs: sta shadow,y
    dey
    bpl @cs
    ; clear brick region rows 2-11, cols 2-12
    ldx #0
@clrrow:
    lda rowmap2_lo,x
    sta ptr2
    lda rowmap2_hi,x
    sta ptr2+1
    lda #0
    ldy #12
@cc: sta (ptr2),y
    dey
    cpy #1
    bne @cc
    lda ptr2+1
    clc
    adc #2
    sta ptr2+1
    lda #0
    ldy #12
@ch: sta (ptr2),y
    dey
    cpy #1
    bne @ch
    inx
    cpx #10
    bne @clrrow

    lda #0
    sta bricksn
    ldx level
    lda level_ptr_lo,x
    sta ptr
    lda level_ptr_hi,x
    sta ptr+1
    ldy #0
    lda (ptr),y            ; nrows
    sta rowv
    inc ptr
    bne @p0
    inc ptr+1
@p0:
    lda #0
    sta hitr
@rowloop:
    lda hitr
    cmp rowv
    bcs @done
    lda #0
    sta hitc
@colloop:
    ldy hitc
    lda (ptr),y            ; type code
    beq @next
    pha
    ldx hitr
    lda times11,x
    clc
    adc hitc
    tay
    pla
    sta shadow,y
    cmp #4                 ; 'i' is not destructible
    beq @place
    inc bricksn
@place:
    tax
    ldy hitr
    lda rowmap2_lo,y
    sta ptr2
    lda rowmap2_hi,y
    sta ptr2+1
    lda hitc
    clc
    adc #2
    tay
    lda type_tile,x
    sta (ptr2),y
    lda ptr2+1
    clc
    adc #2
    sta ptr2+1
    lda type_hi,x
    sta (ptr2),y
@next:
    inc hitc
    lda hitc
    cmp #11
    bne @colloop
    lda ptr
    clc
    adc #11
    sta ptr
    bcc @p1
    inc ptr+1
@p1:
    inc hitr
    jmp @rowloop
@done:
    rts

; ------------------------------------------------------------------------------
; draw_hud: score (6 digits), lives, level as font tiles
draw_hud:
    lda score2
    jsr bcd_two
    sta MAP_LO+64+14
    stx MAP_LO+64+15
    lda score1
    jsr bcd_two
    sta MAP_LO+64+16
    stx MAP_LO+64+17
    lda score0
    jsr bcd_two
    sta MAP_LO+64+18
    stx MAP_LO+64+19
    ldx #0
@attr:
    lda #$60
    sta MAP_HI+64+14,x
    inx
    cpx #6
    bne @attr
    lda lives
    and #$0F
    ora #$B0               ; font tile for '0' + digit
    sta MAP_LO+160+14
    lda #$60
    sta MAP_HI+160+14
    ldx level
    lda lvl_tens,x
    sta MAP_LO+256+14
    lda lvl_ones,x
    sta MAP_LO+256+15
    lda #$60
    sta MAP_HI+256+14
    sta MAP_HI+256+15
    rts
bcd_two:                   ; A = BCD byte -> A = tens font tile, X = ones
    pha
    and #$0F
    ora #$B0
    tax
    pla
    lsr
    lsr
    lsr
    lsr
    ora #$B0
    rts

; ------------------------------------------------------------------------------
; Overlay messages (4x6 font, two glyphs per byte, byte-aligned)
msg_press:
    lda #<(OVL+70*20+8)
    sta ptr
    lda #>(OVL+70*20+8)
    sta ptr+1
    ldx #<msg_press_t
    ldy #>msg_press_t
    lda #4
    jmp ovl_print
msg_over:
    lda #<(OVL+70*20+7)
    sta ptr
    lda #>(OVL+70*20+7)
    sta ptr+1
    ldx #<msg_over_t
    ldy #>msg_over_t
    lda #5
; ovl_print: ptr = overlay dest, X/Y = glyph-offset table, A = pair count
ovl_print:
    sta tmp3
    stx tmp
    sty tmp2
    lda #0
    sta rowv
@row:
    lda #0
    sta colv
@pair:
    lda colv
    asl
    tay
    iny
    lda (tmp),y            ; odd glyph offset -> high nibble
    clc
    adc rowv
    tay
    lda font46,y
    asl
    asl
    asl
    asl
    sta hitr
    lda colv
    asl
    tay
    lda (tmp),y            ; even glyph offset -> low nibble
    clc
    adc rowv
    tay
    lda font46,y
    ora hitr
    ldy colv
    sta (ptr),y
    inc colv
    lda colv
    cmp tmp3
    bne @pair
    lda ptr
    clc
    adc #20
    sta ptr
    bcc @nc
    inc ptr+1
@nc:
    inc rowv
    lda rowv
    cmp #6
    bne @row
    rts

msg_clear:
    lda #<(OVL+68*20+5)
    sta ptr
    lda #>(OVL+68*20+5)
    sta ptr+1
    ldx #10
@r: lda #0
    ldy #10
@c: sta (ptr),y
    dey
    bpl @c
    lda ptr
    clc
    adc #20
    sta ptr
    bcc @n
    inc ptr+1
@n: dex
    bne @r
    rts

; ------------------------------------------------------------------------------
; Data
; ------------------------------------------------------------------------------
; brick types:   0    b    h    s    i    p   hdmg
type_tile:
    .byte  0,  12,  16,  24,  28,  32,  20
type_hi:
    .byte  0, $0C, $0C, $0C, $0C, $0C, $0C
type_pts:
    .byte  0, $10, $20, $30, $00, $50, $20
type_next:
    .byte  0,   0,   6,   0,   4,   0,   0

; paddle-english zones: (vx, vy) in signed 8.8
zone_vx_lo: .byte $C0, $40, $40, $C0, $40
zone_vx_hi: .byte $FE, $FF, $00, $00, $01
zone_vy_lo: .byte $40, $C0, $80, $C0, $40
zone_vy_hi: .byte $FF, $FE, $FE, $FE, $FF

times11:
    .byte 0, 11, 22, 33, 44, 55, 66, 77, 88, 99

rowmap_lo:
    .byte $00, $20, $40, $60, $80, $A0, $C0, $E0, $00, $20, $40, $60, $80, $A0, $C0, $E0
rowmap_hi:
    .byte $F0, $F0, $F0, $F0, $F0, $F0, $F0, $F0, $F1, $F1, $F1, $F1, $F1, $F1, $F1, $F1
rowmap2_lo:
    .byte $40, $60, $80, $A0, $C0, $E0, $00, $20, $40, $60
rowmap2_hi:
    .byte $F0, $F0, $F0, $F0, $F0, $F0, $F1, $F1, $F1, $F1

lvl_tens:
    .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B1,$B1,$B1,$B1,$B1,$B1
lvl_ones:
    .byte $B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$B0,$B1,$B2,$B3,$B4,$B5

txt_score: .byte "SCORE"
txt_balls: .byte "BALLS"
txt_level: .byte "LEVEL"

font46:
    .byte $02,$05,$07,$05,$05,$00   ; 0  A
    .byte $07,$01,$03,$01,$07,$00   ; 6  E
    .byte $07,$01,$05,$05,$07,$00   ; 12 G
    .byte $05,$07,$07,$05,$05,$00   ; 18 M
    .byte $07,$05,$05,$05,$07,$00   ; 24 O
    .byte $03,$05,$03,$01,$01,$00   ; 30 P
    .byte $03,$05,$03,$05,$05,$00   ; 36 R
    .byte $07,$01,$07,$04,$07,$00   ; 42 S
    .byte $05,$05,$05,$05,$02,$00   ; 48 V
    .byte $05,$05,$02,$05,$05,$00   ; 54 X
    .byte $00,$00,$00,$00,$00,$00   ; 60 space

msg_press_t:
    .byte 30, 36, 6, 42, 42, 60, 54, 60          ; PRESS X
msg_over_t:
    .byte 12, 0, 18, 6, 60, 24, 48, 6, 36, 60    ; GAME OVER

.include "breakout_data.asm"

; ------------------------------------------------------------------------------
nmi_handler:
    rti
irq_handler:
    rti

.segment "VECTORS"
    .word $0000
    .word $0300
    .word $0000
