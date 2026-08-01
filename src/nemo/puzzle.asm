; ------------------------------------------------------------------------------
; NEMO - puzzle loading and the bitmap stream decode
;
; The cart stores solutions as 7 bits per character against a 128-entry
; alphabet, because PICO-8 strings are the only data store it has, and decodes
; lazily into a cache (data_decode / pz_decoded, cart lines 215-243, 276-280).
;
; This port keeps the decode at runtime but drops the 7-bit alphabet, which
; only ever existed to survive being a Lua string literal: tools/p8_nemo.py
; emits 8-bit-packed rows, two bytes each, bit 7 = column 0. That ordering is
; deliberate - it lets the expansion shift cells out of the high end straight
; into the carry.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; puzzle_load: load puzzle pz_idx. Sets pz_w/pz_h, builds ROWOFF, expands the
; solution bitmap, positions the grid, clears the board and derives the clues.
; Clobbers everything.
; ------------------------------------------------------------------------------
puzzle_load:
    ldx pz_idx
    lda nemo_w,x
    sta pz_w
    lda nemo_h,x
    sta pz_h
    jsr grid_setup

    ; Grid is bottom-right anchored: left = GRID_R - w*CELL_PX.
    lda pz_w
    sta mulA
    lda #CELL_PX
    sta mulB
    jsr mul8
    lda #GRID_R
    sec
    sbc mulR
    sta grid_x

    lda pz_h
    sta mulA
    lda #CELL_PX
    sta mulB
    jsr mul8
    lda #GRID_B
    sec
    sbc mulR
    sta grid_y

    jsr bitmap_expand
    jsr board_clear
    jsr clues_derive

    lda #0
    sta is_clear
    sta cur_x
    sta cur_y
    jsr match_all
    inc dirty
    rts

; ------------------------------------------------------------------------------
; bitmap_expand: expand puzzle pz_idx's packed bitmap into SOLUTION as one
; cell byte per cell.
;
; pSrc walks the bitmap forwards and is never rewound - the row stride in the
; SOURCE is NEMO_ROW_BYTES (2, shiftable) while the row stride in the
; DESTINATION is pz_w (not shiftable), which is why the destination goes
; through ROWOFF and the source does not.
; Clobbers everything except pz_*.
; ------------------------------------------------------------------------------
bitmap_expand:
    ; pSrc = nemo_bitmaps + pz_idx * (MAX_DIM * NEMO_ROW_BYTES)   [30 bytes]
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

    lda #0
    sta t2                      ; row
@row:
    ldx #>SOLUTION
    lda t2
    jsr row_ptr                 ; pRow = SOLUTION row base

    ldy #0
    lda (pSrc),y                ; first byte of the row: columns 0..7
    sta t5
    iny
    lda (pSrc),y                ; second byte: columns 8..14
    sta t6

    ldy #0                      ; destination column
@col:
    cpy #8
    bcc @lo
    asl t6                      ; columns 8..14 come out of the second byte
    jmp @bit
@lo:
    asl t5                      ; MSB first, so column order is preserved
@bit:
    lda #CELL_EMPTY
    bcc @put
    lda #CELL_FILL
@put:
    sta (pRow),y
    iny
    cpy pz_w
    bne @col

    ; advance the source by one packed row
    lda pSrc
    clc
    adc #NEMO_ROW_BYTES
    sta pSrc
    bcc @nc
    inc pSrc+1
@nc:
    inc t2
    lda t2
    cmp pz_h
    bne @row
    rts

; ------------------------------------------------------------------------------
; progress_get / progress_set: 50 completion bits, 7 bytes at PROGRESS.
; This is the whole of the cart's cartdata()/dget/dset save system - 50 bits.
; It lives in RAM and is lost on power-off; see docs/hardware-gaps.md.
; ------------------------------------------------------------------------------
; A = puzzle index -> Z clear if completed. Clobbers A, X, Y, t0.
progress_get:
    jsr progress_bit
    and PROGRESS,x
    rts

; A = puzzle index -> set its bit. Clobbers A, X, Y, t0.
progress_set:
    jsr progress_bit
    ora PROGRESS,x
    sta PROGRESS,x
    rts

; A = index -> X = byte, A = mask.
progress_bit:
    pha
    lsr
    lsr
    lsr
    tax                         ; byte = index / 8
    pla
    and #7
    tay
    lda bitmask,y
    rts

bitmask:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

progress_clear:
    lda #0
    ldx #6
@l: sta PROGRESS,x
    dex
    bpl @l
    rts
