; ------------------------------------------------------------------------------
; NEMO - drawing the puzzle: grid, cells, cursor, clues, HUD
;
; Every loop counter here lives in its own zero-page byte rather than in
; t0..t7, because ovl_box / ovl_hline / glyph_at clobber t1..t6. That is the
; whole of the globals-as-locals tax in one place, and it is why this module
; declares nine bytes of pen and counter state in memmap.asm.
; ------------------------------------------------------------------------------

; Cell index -> pixel offset. A third table standing in for a multiply, this
; one by the constant 6. Sixteen bytes against six instructions per use, and
; the grid walk needs it twice per cell.
x6:
    .byte 0, 6, 12, 18, 24, 30, 36, 42, 48, 54, 60, 66, 72, 78, 84, 90

; ------------------------------------------------------------------------------
; draw_board: the whole playfield into the overlay shadow.
; Clobbers everything.
; ------------------------------------------------------------------------------
draw_board:
    lda #T_SOLID                ; green field under the grid
    sta t3
    lda #A_GREEN
    sta t4
    jsr map_fill
    jsr ovl_clear
    jsr draw_gridlines
    jsr draw_cells
    jsr draw_clues_h
    jsr draw_clues_v
    jmp draw_hud

; ------------------------------------------------------------------------------
; draw_gridlines: dotted cell boundaries, the cart's draw_dotline look.
; Runs for w+1 / h+1 boundaries so the far edges are closed.
; Clobbers everything.
; ------------------------------------------------------------------------------
draw_gridlines:
    lda #0
    sta d_row
@h:
    ldx pz_w
    lda x6,x
    lsr                         ; dots = (w*6)/2
    sta t3
    lda #2
    sta t4
    lda grid_x
    sta t1
    ldx d_row
    lda x6,x
    clc
    adc grid_y
    sta t2
    jsr ovl_hline
    inc d_row
    lda d_row
    cmp pz_h
    beq @h
    bcc @h

    lda #0
    sta d_col
@v:
    ldx pz_h
    lda x6,x
    lsr
    sta t3
    lda #2
    sta t4
    ldx d_col
    lda x6,x
    clc
    adc grid_x
    sta t1
    lda grid_y
    sta t2
    jsr ovl_vline
    inc d_col
    lda d_col
    cmp pz_w
    beq @v
    bcc @v
    rts

; ------------------------------------------------------------------------------
; draw_cells: a 5x5 block for CELL_FILL, a 2x2 dot for CELL_MARK.
;
; pRow survives ovl_box and ovl_dot (they touch t0..t6 and pDst only), so the
; row pointer is established once per row and the column index is re-loaded
; from d_col each cell because Y does not survive.
; Clobbers everything.
; ------------------------------------------------------------------------------
draw_cells:
    lda #0
    sta d_row
@row:
    ldx #>BOARD
    lda d_row
    jsr row_ptr
    lda #0
    sta d_col
@col:
    ldy d_col
    lda (pRow),y
    sta d_val
    beq @next

    ldy d_col                   ; cell pixel origin
    lda x6,y
    clc
    adc grid_x
    sta d_px
    ldy d_row
    lda x6,y
    clc
    adc grid_y
    sta d_py

    lda d_val
    cmp #CELL_MARK
    beq @mark

    lda d_px                    ; filled: 5x5 inset by one pixel
    clc
    adc #1
    sta t1
    lda d_py
    clc
    adc #1
    sta t2
    jsr ovl_box
    jmp @next
@mark:
    lda d_px                    ; marked: 2x2 dot near the centre
    clc
    adc #3
    sta t1
    lda d_py
    clc
    adc #2
    sta t2
    jsr ovl_dot
@next:
    inc d_col
    lda d_col
    cmp pz_w
    bne @col

    inc d_row
    lda d_row
    cmp pz_h
    bne @row
    rts

; ------------------------------------------------------------------------------
; The cursor used to be drawn here as an overlay outline. It is a hardware
; sprite now (sprites.asm): moving or blinking it no longer dirties the overlay,
; so a 2400-byte redraw and blit per blink became five register writes.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; draw_clues_h: row clues, horizontally to the right of the grid.
;
; A row whose runs already match is not drawn at all. The cart greys it out;
; with one bit of colour available, dropping it is the honest equivalent and it
; doubles as the "this row is finished" signal.
; Clobbers everything.
; ------------------------------------------------------------------------------
draw_clues_h:
    lda #0
    sta d_row
@row:
    ldx d_row
    lda MATCH_H,x
    bne @next

    lda #<CLUE_H
    sta t4
    lda #>CLUE_H
    sta t5
    lda d_row
    jsr clue_ptr
    ldy #0
    lda (pClue),y
    sta clue_n
    beq @next

    ldx pz_w                    ; pen: right of the grid, on the row's line
    lda x6,x
    clc
    adc grid_x
    clc
    adc #3
    sta clue_x
    ldx d_row
    lda x6,x
    clc
    adc grid_y
    clc
    adc #1
    sta clue_y

    lda #1
    sta clue_i
@num:
    lda clue_x
    sta t1
    lda clue_y
    sta t2
    ldy clue_i
    lda (pClue),y
    jsr draw_number             ; A = width consumed
    clc
    adc #2                      ; the cart's inter-number gap
    clc
    adc clue_x
    sta clue_x

    inc clue_i
    lda clue_n
    cmp clue_i
    bcs @num
@next:
    inc d_row
    lda d_row
    cmp pz_h
    bne @row
    rts

; ------------------------------------------------------------------------------
; draw_clues_v: column clues, stacked downward below the grid.
; Clobbers everything.
; ------------------------------------------------------------------------------
draw_clues_v:
    lda #0
    sta d_col
@col:
    ldx d_col
    lda MATCH_V,x
    bne @next

    lda #<CLUE_V
    sta t4
    lda #>CLUE_V
    sta t5
    lda d_col
    jsr clue_ptr
    ldy #0
    lda (pClue),y
    sta clue_n
    beq @next

    ldx d_col
    lda x6,x
    clc
    adc grid_x
    clc
    adc #2
    sta clue_x
    ldx pz_h
    lda x6,x
    clc
    adc grid_y
    clc
    adc #3
    sta clue_y

    lda #1
    sta clue_i
@num:
    lda clue_x
    sta t1
    lda clue_y
    sta t2
    ldy clue_i
    lda (pClue),y
    jsr draw_number
    lda clue_y
    clc
    adc #6
    sta clue_y

    inc clue_i
    lda clue_n
    cmp clue_i
    bcs @num
@next:
    inc d_col
    lda d_col
    cmp pz_w
    bne @col
    rts

; ------------------------------------------------------------------------------
; draw_hud: puzzle number and grid size in the bottom-right corner, where the
; cart draws its ">n" and "wxh" box.
; Clobbers everything.
; ------------------------------------------------------------------------------
draw_hud:
    lda #CLUE_H_X+4
    sta t1
    lda #CLUE_V_Y+4
    sta t2
    lda pz_idx
    clc
    adc #1                      ; 1-based on screen
    jsr draw_dec2

    lda #CLUE_H_X+4
    sta t1
    lda #CLUE_V_Y+12
    sta t2
    lda pz_w
    jsr draw_dec2
    lda #GLY_BAR                ; stands in for the cart's 'x' separator
    jsr glyph_at
    lda t1
    clc
    adc #3
    sta t1
    lda pz_h
    jmp draw_dec2

; ------------------------------------------------------------------------------
; draw_dec2: A = 0..99 as up to two digits at (t1, t2); advances t1 past them.
; Plain decimal, not the clue strip's compact bar form.
; d_val/d_px hold the digits because glyph_at clobbers t0..t7.
; Clobbers everything except t2.
; ------------------------------------------------------------------------------
draw_dec2:
    ldx #0
@tens:
    cmp #10
    bcc @ones
    sec
    sbc #10
    inx
    jmp @tens
@ones:
    sta d_val                   ; ones
    stx d_px                    ; tens
    cpx #0                      ; stx leaves the flags alone, so test X here
    beq @skiptens               ; no leading digit
    ldx d_px
    lda glyphdig,x
    jsr glyph_at
    lda t1
    clc
    adc #4
    sta t1
@skiptens:
    ldx d_val
    lda glyphdig,x
    jsr glyph_at
    lda t1
    clc
    adc #4
    sta t1
    rts
