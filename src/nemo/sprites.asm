; ------------------------------------------------------------------------------
; NEMO - the cursor as a hardware sprite
;
; The cart's spritesheet is nearly empty - twelve small UI glyphs and a box, and
; nothing else, because it draws procedurally. So there is no sprite art to
; port. There is still a good reason to use the sprite list: the cursor.
;
; Drawing the cursor into the overlay meant the whole 2400-byte shadow had to be
; redrawn and re-blitted every time it blinked or moved. As a sprite it costs
; five register writes per frame and the overlay only changes when a cell does.
;
; Patterns are bitplanes, 8 bytes per sheet slot, so a 1bpp sprite is one slot.
; The pattern is horizontally symmetric, which sidesteps having to know which
; end of the byte the compositor calls pixel zero.
; ------------------------------------------------------------------------------

    .define CURSOR_SLOT        0
    .define BLOCK_SLOT         8       ; 2bpp -> slots 8 and 9
    .define BLOCK_FLAGS        $04     ; 2bpp, base 0 -> colours 1..3
    .define LOGO_Y             16      ; top of the wordmark, pixels
    .define LOGO_PX            2*8     ; left edge = logo_x tiles
    .define CURSOR_FLAGS       $70     ; base 7 -> colour 8 (red), 1bpp.
                                       ; Red rather than white so the cursor is
                                       ; unmistakable against the white grid.

cursor_gfx:
    .byte $C3, $81, $00, $00, $00, $00, $81, $C3   ; corner brackets

; ------------------------------------------------------------------------------
; The wordmark block, 2bpp in two planes at slots 8-9. Values are 1 = black
; outline, 2 = orange body, 3 = yellow highlight - the same design palette the
; tile layer uses, so the draw palette serves both.
;
; The block occupies columns 0..6 and rows 0..6; the checkered drop shadow lives
; in the last column and row of the SAME pattern. Blocks sit on an 8-pixel pitch,
; so one sprite carries a block and its shadow and nothing overlaps - which is
; why the shadow does not need sprites or tiles of its own.
; ------------------------------------------------------------------------------
block_gfx:
    ; plane 0 (value bit 0): outline (1) and highlight (3), plus the shadow
    .byte $7F, $7F, $41, $41, $41, $41, $7F, $AA
    ; plane 1 (value bit 1): body (2) and highlight (3)
    .byte $00, $3E, $3E, $3E, $3E, $3E, $00, $00

; ------------------------------------------------------------------------------
; The NEMO wordmark, as a block grid. Four letters three blocks wide with a
; block of gap: 15 columns, 5 rows. The letterforms are the same 3x5 shapes as
; the overlay font, so the wordmark and the labels share a typeface.
;
;   ##. ### #.# ###
;   #.# #.. ### #.#
;   #.# ##. ### #.#
;   #.# #.. #.# #.#
;   #.# ### #.# ###
;
; The cart draws these on a 6-pixel pitch, which an 8-pixel tile grid cannot
; express - and they move independently, which tiles cannot do at all. So the
; wordmark is re-laid on an 8-pixel pitch and drawn as one sprite per block.
;
; Two bytes per row, bit 0 = leftmost block.
; ------------------------------------------------------------------------------
logo_w = 15
logo_h = 5
logo_bits:
    .byte $73, $75              ; row 0
    .byte $15, $57              ; row 1
    .byte $35, $57              ; row 2
    .byte $15, $55              ; row 3
    .byte $75, $75              ; row 4

; Vertical bob, in pixels. Each block reads this at a phase derived from its own
; row and column, so the wordmark ripples rather than moving as a slab - which is
; what the cart does.
bob_tab:
    .byte 0, 0, 1, 2, 3, 3, 3, 2, 1, 0, 0, 0, 1, 1, 0, 0

; ------------------------------------------------------------------------------
; sprites_init: upload the cursor pattern to sheet slot 0.
; Clobbers A, X.
; ------------------------------------------------------------------------------
sprites_init:
    lda #0
    sta SPR_SHADDR_LO
    sta SPR_SHADDR_HI
    ldx #0
@cur:
    lda cursor_gfx,x
    sta SPR_SHDATA
    inx
    cpx #8
    bne @cur

    lda #BLOCK_SLOT*8           ; sheet byte address of slot 8
    sta SPR_SHADDR_LO
    lda #0
    sta SPR_SHADDR_HI
    ldx #0
@blk:
    lda block_gfx,x
    sta SPR_SHDATA
    inx
    cpx #16
    bne @blk

    lda #0
    sta SPR_COUNT
    rts

; ------------------------------------------------------------------------------
; logo_sprites: emit one sprite per wordmark block, each bobbing on its own
; phase. Returns the number of entries staged in A.
;
; Sprites rather than tiles because the blocks move independently and by single
; pixels; an 8-pixel tile grid can express neither. 44 blocks plus the cursor is
; 45 of the 128 list entries.
; Clobbers everything.
; ------------------------------------------------------------------------------
logo_sprites:
    lda #0
    sta SPR_INDEX
    sta spr_n
    sta d_row
@row:
    lda #0
    sta d_col
@col:
    lda d_row                   ; two bytes per row of logo_bits
    asl
    sta t6
    lda d_col
    lsr
    lsr
    lsr
    clc
    adc t6
    tax
    lda logo_bits,x
    sta t7
    lda d_col
    and #7
    tax
    lda bitmask,x
    and t7
    beq @next

    lda d_col                   ; x = left edge + col*8
    asl
    asl
    asl
    clc
    adc #LOGO_PX
    sta SPR_X

    ; phase = frame/4 + col + row*3, so neighbours are out of step
    lda cur_blink
    lsr
    lsr
    clc
    adc d_col
    sta t5
    lda d_row
    asl
    clc
    adc d_row                   ; row*3
    clc
    adc t5
    and #15
    tax
    lda bob_tab,x
    sta t5

    lda d_row                   ; y = top + row*8 + bob
    asl
    asl
    asl
    clc
    adc #LOGO_Y
    clc
    adc t5
    sta SPR_Y

    lda #BLOCK_SLOT
    sta SPR_BASE
    lda #BLOCK_FLAGS
    sta SPR_FLAGS               ; commits and auto-increments the list index
    inc spr_n
@next:
    inc d_col
    lda d_col
    cmp #logo_w
    bne @col
    inc d_row
    lda d_row
    cmp #logo_h
    bne @row
    lda spr_n
    rts

; ------------------------------------------------------------------------------
; sprites_frame: build the whole sprite list for the current state, every frame.
; The menu's wordmark animates, so its entries are rebuilt continuously; during
; play the list is just the cursor.
; Clobbers everything.
; ------------------------------------------------------------------------------
sprites_frame:
    lda state
    cmp #ST_SELECT
    beq @menu
    jmp cursor_sprite
@menu:
    jsr logo_sprites
    sta SPR_COUNT
    rts

; ------------------------------------------------------------------------------
; cursor_sprite: place the cursor over the current cell, or withdraw it.
;
; The cell is 6x6 and the sprite is 8x8, so it sits one pixel out on each side
; and reads as a bracket around the cell rather than a box inside it.
; Clobbers A, X.
; ------------------------------------------------------------------------------
cursor_sprite:
    lda state
    cmp #ST_PLAY
    bne @off
    lda cur_blink
    and #$10                    ; ~16 frames on, 16 off
    bne @off

    lda #0
    sta SPR_INDEX
    ldx cur_x
    lda x6,x
    clc
    adc grid_x
    sec
    sbc #1
    sta SPR_X
    ldx cur_y
    lda x6,x
    clc
    adc grid_y
    sec
    sbc #1
    sta SPR_Y
    lda #CURSOR_SLOT
    sta SPR_BASE
    lda #CURSOR_FLAGS
    sta SPR_FLAGS               ; writing commits the staged entry
    lda #1
    sta SPR_COUNT
    rts
@off:
    lda #0
    sta SPR_COUNT
    rts
