; ------------------------------------------------------------------------------
; NEMO - puzzle select
;
; The cart's selector is a horizontally scrolling strip of 50 boxes, each with
; a preview decoded on demand (cart lines 1248-1364). This port keeps the
; on-demand preview - which is the interesting part, because it reads the
; packed bitmap straight out of the data table without expanding it into a cell
; array - and shows one puzzle at a time instead of a scrolling strip.
; Recorded as a divergence in docs/corpora.md.
; ------------------------------------------------------------------------------

    .define PREV_X             124     ; preview origin, 2x scale, up to 30x30
    .define PREV_Y             74

txt_title:   .byte "PUZZLE PACK II", 0
txt_by:      .byte "BY MOOON", 0
txt_press:   .byte "PRESS X TO PLAY", 0
txt_music:   .byte "MUSIC BY GRUBER", 0
txt_size:    .byte "SIZE", 0

; ------------------------------------------------------------------------------
; sel_bg: the green field plus the two black bars, in tiles.
; Clobbers everything.
; ------------------------------------------------------------------------------
sel_bg:
    lda #T_SOLID
    sta t3
    lda #A_GREEN
    sta t4
    jsr map_fill

    ; black banner behind the subtitle, and a black footer bar
    lda #T_SOLID
    sta t3
    lda #A_BLACK
    sta t4
    lda #7
    sta t2
    jsr @bar
    lda #14
    sta t2
    jmp @bar
@bar:
    lda #0
    sta t1
@l: lda #T_SOLID
    sta t3
    lda #A_BLACK
    sta t4
    jsr map_put
    inc t1
    lda t1
    cmp #MAP_COLS
    bne @l
    rts

; ------------------------------------------------------------------------------
; sel_draw: the title and puzzle-select screen.
; Clobbers everything.
; ------------------------------------------------------------------------------
sel_draw:
    jsr sel_bg
    jsr ovl_clear

    lda #34                     ; subtitle, on the banner
    sta t1
    lda #58
    sta t2
    ldx #<txt_title
    ldy #>txt_title
    jsr ovl_text_at

    lda #4                      ; author, top left
    sta t1
    lda #4
    sta t2
    ldx #<txt_by
    ldy #>txt_by
    jsr ovl_text_at

    lda #30                     ; footer credit
    sta t1
    lda #114
    sta t2
    ldx #<txt_music
    ldy #>txt_music
    jsr ovl_text_at

    lda #26                     ; call to action
    sta t1
    lda #106
    sta t2
    ldx #<txt_press
    ldy #>txt_press
    jsr ovl_text_at

    jsr sel_boxes

    ; grid size, under the strip on the left
    lda #6
    sta t1
    lda #98
    sta t2
    ldx pz_idx
    lda nemo_w,x
    jsr draw_dec2
    lda #GLY_BAR
    jsr glyph_at
    lda t1
    clc
    adc #3
    sta t1
    ldx pz_idx
    lda nemo_h,x
    jsr draw_dec2

    jmp sel_preview

; ------------------------------------------------------------------------------
; sel_boxes: the puzzle-box strip.
;
; The cart shows a horizontally scrolling row of 50 numbered boxes with the
; selected one highlighted and tethered by a line to "PRESS X TO PLAY". Three
; boxes fit here, so the strip is a window on the list centred on the selection:
; the previous puzzle, the current one, the next.
;
; The highlight is an orange tile fill (colour lives in the tile layer) and the
; outline and number are overlay pixels (the overlay is the only layer that can
; place a 4-pixel glyph). So a box is drawn in two layers.
;
; Box geometry: 3 cells wide and tall, so 24x24 pixels, at tile rows 9..11.
; ------------------------------------------------------------------------------
BOX_ROW  = 9
BOX_W    = 3
BOX_H    = 3

; tile column of each of the three boxes
box_cols:
    .byte 3, 8, 13

sel_boxes:
    lda #0
    sta box_i
@l:
    ; which puzzle does this slot show? centre slot is pz_idx.
    lda pz_idx
    clc
    adc box_i
    sec
    sbc #1
    sta box_n                   ; puzzle number for this slot
    bmi @empty                  ; before the first puzzle: leave the slot empty
    cmp #NEMO_COUNT
    bcc @draw                   ; past the last
@empty:
    jmp @next                   ; the box body is too long for a branch
@draw:

    ldx box_i
    lda box_cols,x
    sta box_x
    lda #BOX_ROW
    sta box_y

    ; the selected slot gets an orange field behind it
    lda box_i
    cmp #1
    bne @plain
    lda box_x
    sta t1
    lda box_y
    sta t2
    lda #BOX_W
    sta t5
    lda #BOX_H
    sta t6
    lda #T_SOLID
    sta t3
    lda #A_ORANGE
    sta t4
    jsr map_box
@plain:
    ; outline, in pixels
    lda box_x
    asl
    asl
    asl                         ; tile col -> pixel x
    sta t1
    lda box_y
    asl
    asl
    asl
    sta t2
    lda #BOX_W*8-1
    sta t5
    lda #BOX_H*8-1
    sta t6
    jsr ovl_rect

    ; the number, at double size, roughly centred
    lda #2
    sta gly_scale
    lda box_x
    asl
    asl
    asl
    clc
    adc #6
    sta t1
    lda box_y
    asl
    asl
    asl
    clc
    adc #7
    sta t2
    lda box_n
    clc
    adc #1                      ; 1-based on screen
    jsr draw_dec2
    lda #1
    sta gly_scale

    ; a completed puzzle gets a bar under its number
    lda box_n
    jsr progress_get
    beq @next
    lda box_x
    asl
    asl
    asl
    clc
    adc #8
    sta t1
    lda box_y
    asl
    asl
    asl
    clc
    adc #19
    sta t2
    lda #8
    sta t3
    lda #1
    sta t4
    jsr ovl_hline
@next:
    inc box_i
    lda box_i
    cmp #3
    beq @strip_done
    jmp @l
@strip_done:

    ; tether from the selected box down towards the call to action
    lda #8*8+11
    sta t1
    lda #(BOX_ROW+BOX_H)*8
    sta t2
    lda #6
    sta t3
    lda #1
    sta t4
    jmp ovl_vline

; ------------------------------------------------------------------------------
; sel_preview: draw puzzle pz_idx's solution at 2x, straight from the packed
; bitmap. No cell array, no ROWOFF - the source stride here is 2 bytes, which
; is why this walk needs neither.
; Clobbers everything.
; ------------------------------------------------------------------------------
sel_preview:
    lda pz_idx
    sta mulA
    lda #MAX_DIM*NEMO_ROW_BYTES
    sta mulB
    jsr mul8
    lda mulR
    clc
    adc #<nemo_bitmaps
    sta pSrc
    lda mulR+1
    adc #>nemo_bitmaps
    sta pSrc+1

    ldx pz_idx
    lda nemo_w,x
    sta clue_n                  ; width
    lda nemo_h,x
    sta clue_i                  ; height

    lda #0
    sta d_row
@row:
    ldy #0
    lda (pSrc),y
    sta t5
    iny
    lda (pSrc),y
    sta t6

    lda #0
    sta d_col
@col:
    lda d_col
    cmp #8
    bcc @lo
    asl t6
    jmp @bit
@lo:
    asl t5
@bit:
    bcc @next

    lda d_col                   ; 2x2 block per set cell
    asl
    clc
    adc #PREV_X
    sta d_px
    lda d_row
    asl
    clc
    adc #PREV_Y
    sta d_py

    lda d_px
    sta t1
    lda d_py
    sta t2
    lda #2
    sta t3
    lda #1
    sta t4
    jsr ovl_hline
    lda d_px
    sta t1
    lda d_py
    clc
    adc #1
    sta t2
    lda #2
    sta t3
    lda #1
    sta t4
    jsr ovl_hline
@next:
    inc d_col
    lda d_col
    cmp clue_n
    bne @col

    lda pSrc
    clc
    adc #NEMO_ROW_BYTES
    sta pSrc
    bcc @nc
    inc pSrc+1
@nc:
    inc d_row
    lda d_row
    cmp clue_i
    bne @row
    rts

; ------------------------------------------------------------------------------
; sel_update: left/right change the selection, O or X starts it.
; Clobbers everything.
; ------------------------------------------------------------------------------
sel_update:
    lda btnedge
    and #BTN_L
    beq @nl
    lda pz_idx
    beq @nl
    dec pz_idx
    inc dirty
    lda #SFX_MOVE
    jsr sfx_play
@nl:
    lda btnedge
    and #BTN_R
    beq @nr
    lda pz_idx
    clc
    adc #1
    cmp #NEMO_COUNT
    bcs @nr
    sta pz_idx
    inc dirty
    lda #SFX_MOVE
    jsr sfx_play
@nr:
    lda btnedge
    and #BTN_O|BTN_X
    beq @done
    jsr puzzle_load
    lda #ST_PLAY
    sta state
    inc dirty
    lda #SFX_FILL               ; the cart's "x:play" sound
    jsr sfx_play
    lda #MUS_PLAY
    jsr music_play
@done:
    rts
