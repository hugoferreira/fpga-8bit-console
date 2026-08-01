; ------------------------------------------------------------------------------
; NEMO - the tile layer: colour, the logo and text
;
; The overlay is 1bpp with a single colour register, which is why the first cut
; of this port was white-on-black. Colour lives in the tile and sprite layers,
; so the presentation moved here and the overlay kept only what it is actually
; good at: the 6-pixel puzzle grid and the clue digits.
;
; A tile cell is two bytes in separate planes: MAP_LO holds the pattern slot and
; MAP_HI holds {palette base[7:4], bpp-1[3:2], yflip[1], xflip[0]} - the same
; layout as a sprite list entry, because the compositor synthesises a sprite
; entry per tile. A cell whose two bytes are both zero is skipped entirely, so
; slot 0 is left unused and the solid tile lives at slot 1.
;
; The compositor computes colour as `palette base + pixel value`, which alone
; cannot reach an arbitrary set of colours. The draw palette ($4010-$401F)
; remaps the result, so a tile's post-base colour is really an index into a
; small design palette:
;
;   post-base 1 ->  0  black (outlines)   post-base 3 -> 10  yellow (highlight)
;   post-base 2 ->  9  orange (body)      post-base 5 ->  3  dark green (field)
;
; So a 2bpp block tile with base 0 reaches black, orange and yellow at once,
; while a 1bpp solid with base 4 paints the green field and the same solid with
; base 15 paints black (15+1 wraps to 0).
;
; Pixel value 0 stays transparent, which is what lets the green field show
; through everything drawn over it.
; ------------------------------------------------------------------------------

    .define MAP_LO             $F000
    .define MAP_HI             $F200
    .define MAP_STRIDE         32      ; cells per world row
    .define MAP_COLS           20      ; cells actually on screen
    .define MAP_ROWS           15
    .define SPR_DPAL           $4010

    .define T_SOLID            1       ; 1bpp, all ones
    .define T_CHECK            2       ; 1bpp, 50% checker
    .define T_BLOCK            4       ; 2bpp, occupies slots 4..5

; Attributes. The compositor computes `palette base + pixel value`, so a 1bpp
; tile (value 1) with base b lands on colour b+1; the draw palette then remaps
; that. Hence green from base 4 and black from base 15 (15+1 wraps to 0).
    .define A_GREEN            $40     ; solid, base 4 -> colour 5 -> green
    .define A_BLACK            $F0     ; solid, base 15 -> colour 0 -> black
    .define A_BLOCK            $04     ; 2bpp, base 0 -> colours 1..3
    .define A_ORANGE           $80     ; solid, base 8 -> colour 9 -> orange
    .define A_SHADOW           $F0     ; checker, base 15 -> colour 0 -> black

; ------------------------------------------------------------------------------
; Tile patterns. The font already lives in the sheet at slot 128 + ASCII
; (rtl/sprite_pattern.bin), so only these few need uploading.
; ------------------------------------------------------------------------------
tile_gfx:
    ; slot 1: solid
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    ; slot 2: checker, for the logo's drop shadow
    .byte $AA, $55, $AA, $55, $AA, $55, $AA, $55
    ; slot 3: unused padding so the block starts at slot 4
    .byte $00, $00, $00, $00, $00, $00, $00, $00
    ; slots 4-5: the logo block, 2bpp in two planes, bit 0 = leftmost pixel.
    ; Pixel values: 1 = black outline, 2 = orange body, 3 = yellow highlight.
    ; Row 0 and row 7 are all outline; row 1 is the highlight; rows 2-6 body.
    ; plane 0 (value bit 0): set for values 1 and 3
    .byte $FF, $FF, $81, $81, $81, $81, $81, $FF
    ; plane 1 (value bit 1): set for values 2 and 3
    .byte $00, $7E, $7E, $7E, $7E, $7E, $7E, $00

; The design palette: post-base tile colour -> real PICO-8 colour.
;   1 -> black outlines      2 -> orange body     3 -> yellow highlight
;   5 -> the green field      0 -> black
draw_pal:
    .byte 0, 0, 9, 10, 4, 3, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15

; ------------------------------------------------------------------------------
; tiles_init: upload the tile patterns, install the draw palette, enable the
; tile layer alongside the overlay.
; Clobbers A, X.
; ------------------------------------------------------------------------------
tiles_init:
    lda #8                      ; sheet byte address of slot 1
    sta SPR_SHADDR_LO
    lda #0
    sta SPR_SHADDR_HI
    ldx #0
@up:
    lda tile_gfx,x
    sta SPR_SHDATA
    inx
    cpx #40                     ; slots 1..5
    bne @up

    ldx #0
@pal:
    lda draw_pal,x
    sta SPR_DPAL,x
    inx
    cpx #16
    bne @pal

    lda #$03                    ; bit0 tilemap, bit1 overlay
    sta SPR_CTRL
    lda #7                      ; the overlay carries all text: white
    sta SPR_OVLCOL
    rts

; ------------------------------------------------------------------------------
; map_ptr: pDst = MAP_LO + t2*MAP_STRIDE + t1, so pDst+$200 is the attribute.
; Clobbers A.
; ------------------------------------------------------------------------------
; The three lsr's below each shift a bit into carry, so the carry out of the
; low-byte add has to be stashed first rather than left for `adc #>MAP_LO` to
; pick up. Getting this wrong put every row with bit 2 set eight rows further
; down, which is exactly how it failed the first time.
map_ptr:
    lda t2
    asl                         ; t2 * 32, low 8 bits
    asl
    asl
    asl
    asl
    clc
    adc t1
    sta pDst
    lda #0
    adc #0                      ; carry out of the low byte
    sta t0
    lda t2
    lsr                         ; t2 >> 3: the high bits of t2 * 32
    lsr
    lsr
    clc
    adc t0
    adc #>MAP_LO
    sta pDst+1
    rts

; ------------------------------------------------------------------------------
; map_put: cell (t1, t2) = pattern t3, attribute t4.
; Clobbers A, Y.
; ------------------------------------------------------------------------------
map_put:
    jsr map_ptr
    ldy #0
    lda t3
    sta (pDst),y
    lda pDst+1
    clc
    adc #2                      ; the attribute plane is $200 higher
    sta pDst+1
    lda t4
    sta (pDst),y
    rts

; ------------------------------------------------------------------------------
; map_box: fill the t5 x t6 cell rectangle at (t1, t2) with pattern t3, attr t4.
; Clobbers everything except t3..t6.
; ------------------------------------------------------------------------------
map_box:
    lda t1
    sta mb_x
    lda t2
    sta mb_y
    lda #0
    sta mb_i
@row:
    lda #0
    sta mb_n
@col:
    lda mb_x
    clc
    adc mb_n
    sta t1
    lda mb_y
    clc
    adc mb_i
    sta t2
    jsr map_put
    inc mb_n
    lda mb_n
    cmp t5
    bne @col
    inc mb_i
    lda mb_i
    cmp t6
    bne @row
    rts

; ------------------------------------------------------------------------------
; map_fill: every on-screen cell = pattern t3, attribute t4.
; Clobbers everything except t3/t4.
; ------------------------------------------------------------------------------
map_fill:
    lda #0
    sta t2
@row:
    lda #0
    sta t1
@col:
    jsr map_put
    inc t1
    lda t1
    cmp #MAP_COLS
    bne @col
    inc t2
    lda t2
    cmp #MAP_ROWS
    bne @row
    rts

; ------------------------------------------------------------------------------
; map_clear: blank every cell, including the off-screen columns, so nothing from
; a previous screen survives a mode change.
; Clobbers A, X, Y, pDst.
; ------------------------------------------------------------------------------
map_clear:
    lda #<MAP_LO
    sta pDst
    lda #>MAP_LO
    sta pDst+1
    ldx #4                      ; 4 pages covers both planes ($F000-$F3FF)
    lda #0
    ldy #0
@l: sta (pDst),y
    iny
    bne @l
    inc pDst+1
    dex
    bne @l
    rts

; ------------------------------------------------------------------------------
; There is deliberately no tile-based text routine here. The sheet does carry a
; 1bpp font at slot 128 + ASCII, but it is 8x8 and a PICO-8 port wants a 4x6
; look, and an 8-pixel tile grid cannot place a 4-pixel glyph. Text therefore
; goes through the overlay framebuffer (render.asm ovl_text) - the same answer
; Breakout arrived at. The cost is that the overlay has one colour register for
; the whole screen, so every label is white.
; ------------------------------------------------------------------------------
