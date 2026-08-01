; ------------------------------------------------------------------------------
; NEMO - overlay rendering
;
; Everything is drawn into a RAM shadow of the 1bpp overlay and blitted when
; something changed. The overlay window is write-only (reads return 0), so a
; shadow is the only way to read-modify-write a byte - and a nonogram changes
; a handful of pixels per input, so redrawing from scratch every frame would be
; pure waste.
;
; Note the contrast with grid.asm: the overlay's row stride is 20, which IS
; reachable by shifting (16+4), so OVLROW could have been computed inline. It
; is a table anyway, because a table is one indexed load and the shift-add is
; six instructions - and the row address is needed per plotted pixel.
; ------------------------------------------------------------------------------

    .define GLY_BAR            GLY_BAR_OFF   ; the 1-pixel-wide '1', cart-style

; ------------------------------------------------------------------------------
; render_init: build the overlay row-address table by repeated addition.
; Clobbers A, X, Y, t0, t1.
; ------------------------------------------------------------------------------
render_init:
    lda #1                      ; glyphs draw at 1:1 unless a caller scales up.
    sta gly_scale               ; leaving this zero silently draws nothing at all
    lda #<OVLSHADOW
    sta t0
    lda #>OVLSHADOW
    sta t1
    ldx #0
@l:
    lda t0
    sta OVLROW_LO,x
    lda t1
    sta OVLROW_HI,x
    lda t0
    clc
    adc #OVL_STRIDE
    sta t0
    bcc @nc
    inc t1
@nc:
    inx
    cpx #120
    bne @l
    rts

; ------------------------------------------------------------------------------
; ovl_clear: blank the shadow. 2400 bytes over ten pages.
; Clobbers A, X.
; ------------------------------------------------------------------------------
ovl_clear:
    lda #0
    ldx #0
@l:
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
    bne @l
    ; the tenth page is only $60 bytes long
    ldx #$5F
@t: sta OVLSHADOW+$900,x
    dex
    bpl @t
    rts

; ------------------------------------------------------------------------------
; ovl_blit: shadow -> overlay window, then clear the dirty flag.
; Clobbers A, X.
; ------------------------------------------------------------------------------
ovl_blit:
    ldx #0
@l:
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
    bne @l
    ldx #$5F
@t: lda OVLSHADOW+$900,x
    sta OVL+$900,x
    dex
    bpl @t
    lda #0
    sta dirty
    rts

; ------------------------------------------------------------------------------
; ovl_plot: set the pixel at (t1 = x, t2 = y) in the shadow.
; Silently ignores anything off-screen, so callers may clip lazily.
; Clobbers A, X, Y, pDst.
; ------------------------------------------------------------------------------
ovl_plot:
    lda t2
    cmp #120
    bcs @out
    lda t1
    cmp #160
    bcs @out

    ldx t2
    lda OVLROW_LO,x
    sta pDst
    lda OVLROW_HI,x
    sta pDst+1

    lda t1
    lsr
    lsr
    lsr
    tay                         ; byte within the row = x/8
    lda t1
    and #7
    tax
    lda bitmask,x               ; bit 0 is the LEFTMOST pixel
    ora (pDst),y
    sta (pDst),y
@out:
    rts

; ------------------------------------------------------------------------------
; ovl_hline / ovl_vline: t1 = x, t2 = y, t3 = length, t4 = step.
; A step of 1 draws solid, 2 draws the cart's dotted look.
; Clobbers A, X, Y, t1/t2 advance, pDst.
; ------------------------------------------------------------------------------
ovl_hline:
    ldx t3
    beq @done
@l: jsr ovl_plot
    lda t1
    clc
    adc t4
    sta t1
    dec t3
    bne @l
@done:
    rts

ovl_vline:
    ldx t3
    beq @done
@l: jsr ovl_plot
    lda t2
    clc
    adc t4
    sta t2
    dec t3
    bne @l
@done:
    rts

; ------------------------------------------------------------------------------
; ovl_box: 5x5 solid block at (t1, t2) - a filled cell.
; Clobbers A, X, Y, t1..t6, pDst.
; ------------------------------------------------------------------------------
ovl_box:
    lda t1
    sta t5
    lda t2
    sta t6
    ldx #5
@row:
    stx t0
    lda t5
    sta t1
    lda #5
    sta t3
    lda #1
    sta t4
    jsr ovl_hline
    inc t6
    lda t6
    sta t2
    ldx t0
    dex
    bne @row
    rts

; ------------------------------------------------------------------------------
; ovl_dot: 2x2 dot centred in a cell - the "marked as empty" annotation.
; Clobbers A, X, Y, t1..t4, pDst.
; ------------------------------------------------------------------------------
ovl_dot:
    lda #2
    sta t3
    lda #1
    sta t4
    jsr ovl_hline
    inc t2
    lda t1
    sec
    sbc #2
    sta t1
    lda #2
    sta t3
    lda #1
    sta t4
    jmp ovl_hline

; ------------------------------------------------------------------------------
; Digit font: 3 wide, 5 tall, one byte per row, bit 0 = leftmost pixel.
; GLY_BAR is the cart's 1-pixel '1' (draw_num, cart line 479-487), which is
; what makes eight clue numbers fit in a 34-pixel strip.
; ------------------------------------------------------------------------------
; Glyphs 0-9 then A-Z, five rows each, bit 0 = leftmost pixel.
; The letters come from the 4x6 overlay font Breakout already uses
; (src/main.asm font46); J, Q and Z were missing there and are added.
glyphfont:
    .byte $07, $05, $05, $05, $07   ; 0
    .byte $02, $03, $02, $02, $07   ; 1
    .byte $07, $04, $07, $01, $07   ; 2
    .byte $07, $04, $07, $04, $07   ; 3
    .byte $05, $05, $07, $04, $04   ; 4
    .byte $07, $01, $07, $04, $07   ; 5
    .byte $07, $01, $07, $05, $07   ; 6
    .byte $07, $04, $04, $04, $04   ; 7
    .byte $07, $05, $07, $05, $07   ; 8
    .byte $07, $05, $07, $04, $07   ; 9
    .byte $02, $05, $07, $05, $05   ; A
    .byte $03, $05, $03, $05, $03   ; B
    .byte $07, $01, $01, $01, $07   ; C
    .byte $03, $05, $05, $05, $03   ; D
    .byte $07, $01, $03, $01, $07   ; E
    .byte $07, $01, $03, $01, $01   ; F
    .byte $07, $01, $05, $05, $07   ; G
    .byte $05, $05, $07, $05, $05   ; H
    .byte $07, $02, $02, $02, $07   ; I
    .byte $04, $04, $04, $05, $07   ; J
    .byte $05, $05, $03, $05, $05   ; K
    .byte $01, $01, $01, $01, $07   ; L
    .byte $05, $07, $07, $05, $05   ; M
    .byte $03, $05, $05, $05, $05   ; N
    .byte $07, $05, $05, $05, $07   ; O
    .byte $03, $05, $03, $01, $01   ; P
    .byte $07, $05, $05, $07, $04   ; Q
    .byte $03, $05, $03, $05, $05   ; R
    .byte $07, $01, $07, $04, $07   ; S
    .byte $07, $02, $02, $02, $02   ; T
    .byte $05, $05, $05, $05, $07   ; U
    .byte $05, $05, $05, $05, $02   ; V
    .byte $05, $05, $07, $07, $05   ; W
    .byte $05, $05, $02, $05, $05   ; X
    .byte $05, $05, $02, $02, $02   ; Y
    .byte $07, $04, $02, $01, $07   ; Z
    ; glyph 36, immediately after the table: the 1-pixel-wide bar the cart uses
    ; for '1' in clue strips, which is what makes eight numbers fit in 34 pixels.
    .byte $01, $01, $01, $01, $01   ; bar, at offset 36*5 = 180
GLY_BAR_OFF = 180

; digit n -> offset into glyphfont (digits are the first ten glyphs)
glyphdig:
    .byte 0, 5, 10, 15, 20, 25, 30, 35, 40, 45

; offset into glyphfont for a character; 255 = not renderable
GLY_NONE = 255

; ------------------------------------------------------------------------------
; glyph_off: A = ASCII -> A = offset into glyphfont, or GLY_NONE.
; Clobbers A.
; ------------------------------------------------------------------------------
glyph_off:
    cmp #'0'
    bcc @none
    cmp #'9'+1
    bcs @alpha
    sec
    sbc #'0'
    jmp @scale
@alpha:
    cmp #'A'
    bcc @none
    cmp #'Z'+1
    bcs @none
    sec
    sbc #'A'
    clc
    adc #10
@scale:
    sta t0                      ; index * 5
    asl
    asl
    clc
    adc t0
    rts
@none:
    lda #GLY_NONE
    rts

; ------------------------------------------------------------------------------
; ovl_text: draw the NUL-terminated string at pSrc from (t1, t2), advancing 4
; pixels per character. Unrenderable characters advance without drawing, so a
; space just leaves a gap.
;
; Text lives in the overlay rather than the tile layer because the tile font is
; 8x8 and a PICO-8 port wants a 4x6 look; Breakout settled this the same way.
; The cost is that the overlay has one colour register for the whole screen.
; Clobbers everything except pSrc.
; ------------------------------------------------------------------------------
ovl_text:
    ldy #0
    sty txt_i
@l:
    ldy txt_i
    lda (pSrc),y
    beq @done
    jsr glyph_off
    cmp #GLY_NONE
    beq @adv
    jsr glyph_at
@adv:
    lda t1
    clc
    adc #4
    sta t1
    inc txt_i
    jmp @l
@done:
    rts

; ------------------------------------------------------------------------------
; ovl_text_at: X/Y = string address, t1/t2 = pixel position.
; ------------------------------------------------------------------------------
ovl_text_at:
    stx pSrc
    sty pSrc+1
    jmp ovl_text

; ------------------------------------------------------------------------------
; gly_mul: A = A * gly_scale. The scale is 1..3 and A is at most 4, so repeated
; addition is both smaller and faster than a general multiply here.
; Clobbers A, X.
; ------------------------------------------------------------------------------
gly_mul:
    ldx gly_scale
    dex
    beq @done                   ; scale 1: nothing to do
    stx t8                      ; extra copies to add
    sta t9
@l: clc
    adc t9
    dec t8
    bne @l
@done:
    rts

; ------------------------------------------------------------------------------
; glyph_at: draw the 3x5 glyph at offset A into glyphfont, at (t1, t2), scaled
; by gly_scale. Clobbers A, X, Y, t0, t3..t9, pDst; preserves t1/t2.
; Clobbers A, X, Y, t0, t3..t6, pDst; preserves t1/t2.
; ------------------------------------------------------------------------------
glyph_at:
    tax
    stx t0                      ; font offset
    lda t1
    sta t5                      ; left edge
    lda t2
    sta t6                      ; top edge
    ldx #0                      ; glyph row
@row:
    cpx #5
    beq @done
    stx gly_row
    ldy t0
    lda glyphfont,y
    sta gly_bits                ; row bitmap, bit 0 = leftmost
    ldy #0
@bit:
    cpy #3
    beq @nextrow
    lsr gly_bits
    bcc @skip
    tya                         ; glyph column -> screen x
    jsr gly_mul
    clc
    adc t5
    sta t1
    lda gly_row                 ; glyph row -> screen y
    sty t7
    jsr gly_mul
    clc
    adc t6
    sta t2
    jsr ovl_blk
    ldy t7
@skip:
    iny
    jmp @bit
@nextrow:
    inc t0
    ldx gly_row
    inx
    jmp @row
@done:
    lda t5
    sta t1
    lda t6
    sta t2
    rts

; ------------------------------------------------------------------------------
; ovl_blk: a gly_scale x gly_scale filled block at (t1, t2) - one glyph pixel
; when scaled up. Scale 1 degenerates to a single plot.
; Clobbers A, X, Y, t8, t9, pDst.
; ------------------------------------------------------------------------------
ovl_blk:
    lda gly_scale
    cmp #1
    bne @big
    jmp ovl_plot                ; too far for a branch
@big:
    lda t1
    sta blk_x
    lda t2
    sta blk_y
    ldx gly_scale
@row:
    stx blk_n
    lda blk_x
    sta t1
    lda gly_scale
    sta t3
    lda #1
    sta t4
    jsr ovl_hline
    inc blk_y
    lda blk_y
    sta t2
    ldx blk_n
    dex
    bne @row
    rts

; ------------------------------------------------------------------------------
; ovl_rect: outline at (t1, t2), t5 wide, t6 tall.
; Clobbers A, X, Y, t1..t4, t8, t9, pDst.
; ------------------------------------------------------------------------------
ovl_rect:
    lda t1
    sta t8
    lda t2
    sta t9
    lda #1
    sta gly_scale
    lda t5
    sta t3
    lda #1
    sta t4
    jsr ovl_hline               ; top
    lda t8
    sta t1
    lda t9
    clc
    adc t6
    sta t2
    lda t5
    sta t3
    lda #1
    sta t4
    jsr ovl_hline               ; bottom
    lda t8
    sta t1
    lda t9
    sta t2
    lda t6
    sta t3
    lda #1
    sta t4
    jsr ovl_vline               ; left
    lda t8
    clc
    adc t5
    sta t1
    lda t9
    sta t2
    lda t6
    sta t3
    lda #1
    sta t4
    jmp ovl_vline               ; right

; ------------------------------------------------------------------------------
; draw_number: draw clue value A at (t1, t2); returns its width in A.
;
; The cart's compact rule, verbatim in effect: 1 is a bare vertical bar, a
; teen is a bar plus its ones digit, and 11 is two bars. Clue values never
; exceed 15 here, so nothing wider is needed.
; Clobbers A, X, Y, t0, t3..t7, pDst; preserves t1/t2.
; ------------------------------------------------------------------------------
draw_number:
    cmp #10
    bcs @teen
    cmp #1
    beq @one
    tax
    lda glyphdig,x
    jsr glyph_at
    lda #3
    rts
@one:
    lda #GLY_BAR
    jsr glyph_at
    lda #1
    rts
@teen:
    sec
    sbc #10
    sta t7                      ; ones digit
    lda t1
    pha                         ; preserve the caller's x
    lda #GLY_BAR
    jsr glyph_at                ; the tens digit is always 1, so a bar
    lda t1
    clc
    adc #2
    sta t1
    lda t7
    cmp #1
    beq @teenbar
    tax
    lda glyphdig,x
    jsr glyph_at
    pla
    sta t1
    lda #5
    rts
@teenbar:
    lda #GLY_BAR
    jsr glyph_at
    pla
    sta t1
    lda #3
    rts
