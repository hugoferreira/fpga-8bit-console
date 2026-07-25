; ------------------------------------------------------------------------------
; Celeste - 8.8 fixed-point helpers
;
; The cart is PICO-8 16.16. Every speed and acceleration in the game fits in
; 8.8 signed (the fastest thing in it is a dash at 5 px/frame), so that is what
; the port uses: one integer byte, one fraction byte, little-endian like the
; 6502's own words.
;
; NOTE for the corpus. These routines are the 16-bit add chains that
; add-isa-word-ops says exist in real programs and could not find in breakout.
; They are not written to make the case: appr() is the cart's own helper, and
; obj_move's rounding is the cart's own move(). No general multiply appears in
; stage 1 at all - the two irrational dash constants (5*sqrt(2)/2 and 1.5*
; sqrt(2)/2) are selected from a table rather than computed, which is what a
; 6502 programmer would do and is worth contrasting with nemo's single mul8.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; cmp16: signed compare w0 against w1. Returns N=1 iff w0 < w1, N=0 otherwise
; (including equal). Clobbers A only.
; ------------------------------------------------------------------------------
cmp16:
    lda w0
    cmp w1
    lda w0+1
    sbc w1+1
    bvc @done
    eor #$80                    ; overflow: the sign bit lies, flip it back
@done:
    rts

; ------------------------------------------------------------------------------
; add16 / sub16: w0 += w1 / w0 -= w1. Clobbers A.
; ------------------------------------------------------------------------------
add16:
    lda w0
    clc
    adc w1
    sta w0
    lda w0+1
    adc w1+1
    sta w0+1
    rts

sub16:
    lda w0
    sec
    sbc w1
    sta w0
    lda w0+1
    sbc w1+1
    sta w0+1
    rts

; ------------------------------------------------------------------------------
; neg16: w0 = -w0. Clobbers A.
; ------------------------------------------------------------------------------
neg16:
    lda #0
    sec
    sbc w0
    sta w0
    lda #0
    sbc w0+1
    sta w0+1
    rts

; ------------------------------------------------------------------------------
; abs16: w0 = |w0|. Clobbers A.
; ------------------------------------------------------------------------------
abs16:
    lda w0+1
    bmi neg16
    rts

; ------------------------------------------------------------------------------
; sign16: A = 1, $FF or 0 for the sign of w0. Clobbers A.
; ------------------------------------------------------------------------------
sign16:
    lda w0+1
    bmi @neg
    ora w0
    beq @zero
    lda #1
    rts
@neg:
    lda #$FF
    rts
@zero:
    lda #0
    rts

; ------------------------------------------------------------------------------
; appr: w0 = appr(w0, w1, w2) - the cart's own helper, moving val toward target
; by at most amount:
;
;   val > target and max(val - amount, target) or min(val + amount, target)
;
; Clobbers A.
; ------------------------------------------------------------------------------
appr:
    jsr cmp16
    bmi @up                     ; val < target: approach from below
@down:
    lda w0                      ; val -= amount
    sec
    sbc w2
    sta w0
    lda w0+1
    sbc w2+1
    sta w0+1
    jsr cmp16
    bpl @done                   ; still >= target, keep it
    jmp @clamp
@up:
    lda w0                      ; val += amount
    clc
    adc w2
    sta w0
    lda w0+1
    adc w2+1
    sta w0+1
    jsr cmp16
    bmi @done                   ; still < target, keep it
@clamp:
    lda w1
    sta w0
    lda w1+1
    sta w0+1
@done:
    rts

; ------------------------------------------------------------------------------
; Object field access. The pool is 64 bytes per record, so every field is
; reachable with a constant Y through (pObj),Y - which is the struct walk
; add-isa-pointer-ops is scored on.
;
; obj_ldw: w0 = the 16-bit field at offset Y.
; obj_stw: the 16-bit field at offset Y = w0.
; Both clobber A and Y.
; ------------------------------------------------------------------------------
obj_ldw:
    lda (pObj),y
    sta w0
    iny
    lda (pObj),y
    sta w0+1
    rts

obj_stw:
    lda w0
    sta (pObj),y
    iny
    lda w0+1
    sta (pObj),y
    rts

; ------------------------------------------------------------------------------
; obj_ldw1 / obj_stw1: the same, through w1. Two entry points rather than a
; pointer-to-a-pointer, because the caller always knows which register it means.
; ------------------------------------------------------------------------------
obj_ldw1:
    lda (pObj),y
    sta w1
    iny
    lda (pObj),y
    sta w1+1
    rts

; ------------------------------------------------------------------------------
; setw0 / setw1 / setw2: load a constant into a word register. A = low byte,
; X = high byte. Saves four bytes and a lot of noise at every call site.
; ------------------------------------------------------------------------------
setw0:
    sta w0
    stx w0+1
    rts

setw1:
    sta w1
    stx w1+1
    rts

setw2:
    sta w2
    stx w2+1
    rts
