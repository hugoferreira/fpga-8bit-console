; ------------------------------------------------------------------------------
; NEMO - cursor movement and cell editing
;
; The cart wires input through its event bus (cursor:move emits, the puzzle
; listens); this port does the same, so a cell edit fans out through ev_emit
; rather than calling the match update directly.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; input_read: sample buttons, derive newly-pressed edges into btnedge.
; Clobbers A.
; ------------------------------------------------------------------------------
input_read:
    lda btn
    sta btnprev
    lda SPR_BTN
    sta btn
    eor btnprev                 ; changed bits
    and btn                     ; ...that are now set
    sta btnedge
    inc cur_blink
    rts

; ------------------------------------------------------------------------------
; cursor_move: apply the direction edges, clamped to the grid.
;
; The cart wraps at the edges (cursor:move, line 817) via a cant-move effect;
; clamping is the simpler equivalent and it keeps the cursor inside a puzzle
; whose width changes between loads.
; Clobbers everything.
; ------------------------------------------------------------------------------
cursor_move:
    lda #0
    sta t0                      ; did we move?

    lda btnedge
    and #BTN_L
    beq @nl
    lda cur_x
    beq @nl
    dec cur_x
    inc t0
@nl:
    lda btnedge
    and #BTN_R
    beq @nr
    lda cur_x
    clc
    adc #1
    cmp pz_w
    bcs @nr
    sta cur_x
    inc t0
@nr:
    lda btnedge
    and #BTN_U
    beq @nu
    lda cur_y
    beq @nu
    dec cur_y
    inc t0
@nu:
    lda btnedge
    and #BTN_D
    beq @nd
    lda cur_y
    clc
    adc #1
    cmp pz_h
    bcs @nd
    sta cur_y
    inc t0
@nd:
    ; The event fires whether or not the cursor actually moved: t0 carries the
    ; outcome, and the cart distinguishes them (sfx 3 moved, sfx 4 refused).
    lda btnedge
    and #BTN_L|BTN_R|BTN_U|BTN_D
    beq @done
    lda #EV_CURSOR_MOVED
    jsr ev_emit
    lda t0
    beq @done
    inc dirty                   ; only a real move changes the screen
@done:
    rts

; ------------------------------------------------------------------------------
; cell_edit: O toggles filled, X toggles marked.
;
; Toggling rather than setting is what makes the two buttons independent: X on
; a filled cell clears it to marked, O on a marked cell fills it, and pressing
; the same button twice always returns to empty.
; Clobbers everything.
; ------------------------------------------------------------------------------
cell_edit:
    lda btnedge
    and #BTN_O
    beq @tryx
    lda #CELL_FILL
    jmp @toggle
@tryx:
    lda btnedge
    and #BTN_X
    beq @done
    lda #CELL_MARK
@toggle:
    sta t6                      ; requested value
    lda cur_x
    sta t1
    lda cur_y
    sta t2
    jsr board_get
    cmp t6
    bne @set
    lda #CELL_EMPTY             ; already that value -> clear it
    jmp @store
@set:
    lda t6
@store:
    sta t3
    lda cur_x
    sta t1
    lda cur_y
    sta t2
    jsr board_set

    lda t3                      ; what we stored: 0 clear, 1 fill, 2 mark
    beq @sclear
    lda #SFX_FILL
    jmp @snd
@sclear:
    lda #SFX_CLEAR
@snd:
    jsr sfx_play

    lda #EV_CELL_CHANGED
    jsr ev_emit
    inc dirty
@done:
    rts

; ------------------------------------------------------------------------------
; on_cell_changed: the event handler the puzzle registers. Re-derives only the
; cursor's row and column, then announces a win if the board now matches.
; Clobbers everything.
; ------------------------------------------------------------------------------
on_cell_changed:
    ; Remember whether the cursor's row and column were already satisfied, so a
    ; newly-completed line can be announced (the cart's sfx 2).
    ldx cur_y
    lda MATCH_H,x
    sta m_prevh
    ldx cur_x
    lda MATCH_V,x
    sta m_prevv

    jsr match_cursor

    ldx cur_y
    lda MATCH_H,x
    beq @novline
    lda m_prevh
    bne @novline
    lda #SFX_LINE
    jsr sfx_play
    jmp @winchk
@novline:
    ldx cur_x
    lda MATCH_V,x
    beq @winchk
    lda m_prevv
    bne @winchk
    lda #SFX_LINE
    jsr sfx_play
@winchk:
    lda is_clear
    beq @done
    lda pz_idx
    jsr progress_set
    lda #EV_PUZZLE_CLEAR
    jsr ev_emit
@done:
    rts
