; ------------------------------------------------------------------------------
; NEMO - clue derivation, match tracking and win detection
;
; Mirrors the cart's update_puzzle_numbers / data_to_nums / update_matchdata /
; check_is_clear (lines 393-415, 622-666, 1385).
;
; Every routine here is a nested loop over a 2D grid accumulating run lengths,
; with several live temporaries per row - the shape that add-isa-frame-pointer
; exists for, and the reason those temporaries are hand-allocated globals here
; exactly as they are in src/main.asm.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; run_lengths: walk t7 cells starting at (pRow),0 and write the lengths of
; consecutive CELL_FILL runs into RUNBUF, count into n_runs.
;
; A row of all-empty produces zero runs; the cart represents that as a single
; {0} for display (line 494) but keeps the count at zero for matching, and so
; does this.
; Clobbers A, Y, t0, n_runs.
; ------------------------------------------------------------------------------
run_lengths:
    lda #0
    sta n_runs
    sta t0                      ; current run length
    ldy #0
@l:
    lda (pRow),y
    cmp #CELL_FILL
    beq @fill
    jsr run_flush               ; anything else ends a run
    jmp @next
@fill:
    inc t0
@next:
    iny
    cpy t7
    bne @l
    jsr run_flush               ; a run touching the far edge still counts
    rts

; Emit t0 as a run if non-zero, then reset it. Clobbers A, X.
run_flush:
    lda t0
    beq @none
    ldx n_runs
    sta RUNBUF,x
    inc n_runs
    lda #0
    sta t0
@none:
    rts

; ------------------------------------------------------------------------------
; runs_store: copy RUNBUF/n_runs into the clue table at pClue as
; [0]=count, [1..]=runs.
; Clobbers A, X, Y.
; ------------------------------------------------------------------------------
runs_store:
    ldy #0
    lda n_runs
    sta (pClue),y
    ldx #0
@l:
    cpx n_runs
    beq @done
    lda RUNBUF,x
    iny
    sta (pClue),y
    inx
    jmp @l
@done:
    rts

; ------------------------------------------------------------------------------
; clue_ptr: pClue = base(t4:t5) + index A * CLUE_STRIDE.
; CLUE_STRIDE is 16, so this is a shift, not a multiply - the clue tables were
; given a power-of-two stride precisely so they would not need ROWOFF.
; Clobbers A, X.
; ------------------------------------------------------------------------------
; Indices are 0..14, so index*16 <= 224 and never leaves the byte - no carry
; out of the shifts to propagate.
clue_ptr:
    asl
    asl
    asl
    asl
    clc
    adc t4
    sta pClue
    lda t5
    adc #0
    sta pClue+1
    rts

; ------------------------------------------------------------------------------
; is_definite: A = 1 if the runs in RUNBUF plus one gap each exactly fill t7
; cells, else 0. The cart's is_definite (line 395): sum(runs) + count-1 == span
; means the row has no slack, so it can be coloured as solvable outright.
; Clobbers A, X, t0.
; ------------------------------------------------------------------------------
is_definite:
    lda n_runs
    beq @no                     ; an empty row has slack by definition
    sec
    sbc #1                      ; count-1 gaps
    sta t0
    ldx #0
@l:
    cpx n_runs
    beq @sum
    lda t0
    clc
    adc RUNBUF,x
    sta t0
    inx
    jmp @l
@sum:
    lda t0
    cmp t7
    bne @no
    lda #1
    rts
@no:
    lda #0
    rts

; ------------------------------------------------------------------------------
; clues_derive: fill CLUE_H / CLUE_V and DEFINITE_H / DEFINITE_V from
; SOLUTION. Called once per puzzle load.
; Clobbers everything.
; ------------------------------------------------------------------------------
clues_derive:
    ; --- rows ---
    lda #0
    sta t2
@rows:
    ldx #>SOLUTION
    lda t2
    jsr row_ptr
    lda pz_w
    sta t7
    jsr run_lengths

    lda #<CLUE_H
    sta t4
    lda #>CLUE_H
    sta t5
    lda t2
    jsr clue_ptr
    jsr runs_store

    jsr is_definite
    ldx t2
    sta DEFINITE_H,x

    inc t2
    lda t2
    cmp pz_h
    bne @rows

    ; --- columns ---
    lda #0
    sta t3
@cols:
    lda t3
    sta t1                      ; column index for col_gather
    ldx #>SOLUTION
    jsr col_gather
    lda #<COLBUF                ; run_lengths reads through pRow, so point it
    sta pRow                    ; at the gathered column
    lda #>COLBUF
    sta pRow+1
    lda pz_h
    sta t7
    jsr run_lengths

    lda #<CLUE_V
    sta t4
    lda #>CLUE_V
    sta t5
    lda t3
    jsr clue_ptr
    jsr runs_store

    jsr is_definite
    ldx t3
    sta DEFINITE_V,x

    inc t3
    lda t3
    cmp pz_w
    bne @cols
    rts

; ------------------------------------------------------------------------------
; runs_match: compare RUNBUF/n_runs against the clue at pClue.
; A = 1 on an exact match, else 0. Clobbers A, X, Y.
; ------------------------------------------------------------------------------
runs_match:
    ldy #0
    lda (pClue),y
    cmp n_runs
    bne @no
    ldx #0
@l:
    cpx n_runs
    beq @yes
    iny
    lda (pClue),y
    cmp RUNBUF,x
    bne @no
    inx
    jmp @l
@yes:
    lda #1
    rts
@no:
    lda #0
    rts

; ------------------------------------------------------------------------------
; match_row / match_col: recompute one row's or column's match flag from BOARD.
; Only CELL_FILL counts as filled, so CELL_MARK behaves as empty here - which
; is what makes marking a purely advisory annotation, as in the cart.
; A = the flag. Clobbers everything except pz_*.
; ------------------------------------------------------------------------------
; t2 = row index
match_row:
    ldx #>BOARD
    lda t2
    jsr row_ptr
    lda pz_w
    sta t7
    jsr run_lengths
    lda #<CLUE_H
    sta t4
    lda #>CLUE_H
    sta t5
    lda t2
    jsr clue_ptr
    jsr runs_match
    ldx t2
    sta MATCH_H,x
    rts

; t3 = column index
match_col:
    lda t3
    sta t1
    ldx #>BOARD
    jsr col_gather
    lda #<COLBUF
    sta pRow
    lda #>COLBUF
    sta pRow+1
    lda pz_h
    sta t7
    jsr run_lengths
    lda #<CLUE_V
    sta t4
    lda #>CLUE_V
    sta t5
    lda t3
    jsr clue_ptr
    jsr runs_match
    ldx t3
    sta MATCH_V,x
    rts

; ------------------------------------------------------------------------------
; match_all: recompute every row and column flag, then set is_clear.
; Clobbers everything.
; ------------------------------------------------------------------------------
match_all:
    lda #0
    sta t2
@r: jsr match_row
    inc t2
    lda t2
    cmp pz_h
    bne @r

    lda #0
    sta t3
@c: jsr match_col
    inc t3
    lda t3
    cmp pz_w
    bne @c

    jmp check_clear

; ------------------------------------------------------------------------------
; match_cursor: recompute only the row and column the cursor sits on. Called
; after a single cell edit, which cannot change any other row or column.
; Clobbers everything.
; ------------------------------------------------------------------------------
match_cursor:
    lda cur_y
    sta t2
    jsr match_row
    lda cur_x
    sta t3
    jsr match_col
    jmp check_clear

; ------------------------------------------------------------------------------
; check_clear: is_clear = 1 when every row and column flag is set.
;
; Matching all clues is the win condition, not equality with SOLUTION: a
; nonogram with an ambiguous solution is solved by any board that satisfies
; the clues, and the cart takes the same view (check_is_clear, line 649).
; Clobbers A, X.
; ------------------------------------------------------------------------------
check_clear:
    ldx #0
@r: cpx pz_h
    beq @cols
    lda MATCH_H,x
    beq @no
    inx
    jmp @r
@cols:
    ldx #0
@c: cpx pz_w
    beq @yes
    lda MATCH_V,x
    beq @no
    inx
    jmp @c
@yes:
    lda #1
    sta is_clear
    rts
@no:
    lda #0
    sta is_clear
    rts
