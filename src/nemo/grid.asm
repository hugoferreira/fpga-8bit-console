; ------------------------------------------------------------------------------
; NEMO - grid state and variable-stride addressing
;
; The cart indexes cells as (i-1)*pz_w+j, with pz_w read at runtime from the
; puzzle table. Widths across the 50 puzzles are 7,9,10,11,12,13,14,15 - not
; one is a power of two, so no shift reaches the stride and it cannot be
; strength-reduced at assembly time either.
;
; RECORDED DECISION (task 3.2). Writing this the way it wants to be written on
; a 6502, the general multiply disappears:
;
;   * A cell array is at most 15*15 = 225 bytes, so it fits inside one page,
;     and both arrays are page-aligned. A row's base is therefore a SINGLE
;     BYTE offset, not a 16-bit address.
;   * That byte table (ROWOFF) is built once per puzzle load by adding pz_w
;     fifteen times - repeated addition, no multiply.
;   * Every cell access is then pRow = {ROWOFF[y], >array} and lda (pRow),y
;     with x in Y. Zero multiplies, zero shifts, one indirect load.
;
; So the naive reading - "a non-power-of-two stride needs a multiply" - is
; WRONG once the code is written idiomatically. The demand this corpus places
; on a hardware multiplier is one w*h at puzzle load (mul8 below), and nothing
; per access. What it demands instead is cheap pointer setup and (zp),Y, which
; is add-isa-pointer-ops territory rather than add-math-coprocessor's.
;
; This is a finding, not a workaround, and it is reported as one.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; grid_setup: pz_w/pz_h are loaded; build ROWOFF and pz_cells.
; Clobbers A, X, Y, t0.
; ------------------------------------------------------------------------------
grid_setup:
    lda #0
    sta t0                      ; running offset
    ldx #0
@row:
    lda t0
    sta ROWOFF,x
    clc
    adc pz_w                    ; the "multiply", one add per row
    sta t0
    inx
    cpx #MAX_DIM
    bne @row

    lda pz_w                    ; pz_cells = w * h
    sta mulA
    lda pz_h
    sta mulB
    jsr mul8
    lda mulR
    sta pz_cells
    lda mulR+1
    sta pz_cells+1
    rts

; ------------------------------------------------------------------------------
; mul8: mulR(16) = mulA * mulB. Shift-and-add, 8 iterations.
; The only true multiply in the program; runs once per puzzle load.
; Clobbers A, X, mulA, mulB.
; ------------------------------------------------------------------------------
mul8:
    lda #0
    sta mulR
    sta mulR+1
    sta mulH                    ; the multiplicand is 16-bit: mulH:mulA
    ldx #8
@loop:
    lsr mulB                    ; test the low bit of the multiplier
    bcc @skip
    lda mulR
    clc
    adc mulA
    sta mulR
    lda mulR+1
    adc mulH
    sta mulR+1
@skip:
    asl mulA                    ; shift the whole 16-bit multiplicand left
    rol mulH
    dex
    bne @loop
    rts

; ------------------------------------------------------------------------------
; row_ptr: point pRow at row A of the page-aligned cell array whose high byte
; is in X. This is the whole of the "variable stride" cost at runtime.
; Clobbers A, Y.
; ------------------------------------------------------------------------------
row_ptr:
    tay
    lda ROWOFF,y
    sta pRow
    stx pRow+1
    rts

; ------------------------------------------------------------------------------
; board_get / solution_get: A = cell at (t1=x, t2=y). Clobbers A, X, Y.
; ------------------------------------------------------------------------------
board_get:
    ldx #>BOARD
    jmp getcell
solution_get:
    ldx #>SOLUTION
getcell:
    lda t2
    jsr row_ptr
    ldy t1
    lda (pRow),y
    rts

; ------------------------------------------------------------------------------
; board_set: board cell at (t1=x, t2=y) = t3. Clobbers A, X, Y.
; ------------------------------------------------------------------------------
board_set:
    ldx #>BOARD
    lda t2
    jsr row_ptr
    ldy t1
    lda t3
    sta (pRow),y
    rts

; ------------------------------------------------------------------------------
; board_clear: fill the whole board with CELL_EMPTY.
; Uses the full MAX_DIM*MAX_DIM extent, not pz_cells, so stale cells from a
; larger previous puzzle cannot show through.
; Clobbers A, X.
; ------------------------------------------------------------------------------
board_clear:
    lda #CELL_EMPTY
    ldx #0
@l: sta BOARD,x
    inx
    cpx #MAX_DIM*MAX_DIM
    bne @l
    rts

; ------------------------------------------------------------------------------
; col_gather: copy column t1 of the array whose page is X into COLBUF, so the
; column can be fed to run_lengths exactly like a row.
;
; This mirrors the cart's `for j=1,h do t[j]=data[j][i] end` (line 410) - the
; column is materialised rather than the run finder being taught to stride.
; Clobbers A, X, Y, t2, t4.
; ------------------------------------------------------------------------------
col_gather:
    stx t4                      ; array page
    lda #0
    sta t2                      ; row counter
@l:
    ldx t4
    lda t2
    jsr row_ptr
    ldy t1                      ; column index
    lda (pRow),y
    ldx t2
    sta COLBUF,x
    inc t2
    lda t2
    cmp pz_h
    bne @l
    rts
