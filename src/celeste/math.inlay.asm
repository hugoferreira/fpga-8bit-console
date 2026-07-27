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
; They are not written to make the case: approach() is the cart's own helper,
; obj_move's rounding is the cart's own move(). No general multiply appears in
; stage 1 at all - the two irrational dash constants (5*sqrt(2)/2 and 1.5*
; sqrt(2)/2) are selected from a table rather than computed, which is what a
; 6502 programmer would do and is worth contrasting with nemo's single mul8.
; ------------------------------------------------------------------------------

namespace Fixed
    export compare
    export add
    export subtract
    export negate
    export absolute
    export sign
    export approach
    export load_object
    export store_object
    export load_object_target
    export set_value
    export set_target
    export set_amount

; ------------------------------------------------------------------------------
; compare: signed compare w0 against w1. Returns N=1 iff w0 < w1, N=0 otherwise
; (including equal). Clobbers A only.
; ------------------------------------------------------------------------------
proc compare using console6502 naked
    left : u16 in w0
    right : u16 in w1
begin
    lda w0
    cmp w1
    lda w0+1
    sbc w1+1
    bvc .done
    eor #$80                    ; overflow: the sign bit lies, flip it back
.done:
    ret
end

; ------------------------------------------------------------------------------
; add / subtract: w0 += w1 / w0 -= w1. Clobbers A.
; ------------------------------------------------------------------------------
proc add using console6502 naked
    value : u16 in w0
    amount : u16 in w1
begin
    ldab w0
    addw w1
    stab w0
    ret
end

proc subtract using console6502 naked
    value : u16 in w0
    amount : u16 in w1
begin
    ldab w0
    subw w1
    stab w0
    ret
end

; ------------------------------------------------------------------------------
; negate: w0 = -w0. Clobbers A.
; ------------------------------------------------------------------------------
proc negate using console6502 naked
    value : u16 in w0
begin
    ldab #$0000
    subw w0
    stab w0
    ret
end

; ------------------------------------------------------------------------------
; absolute: w0 = |w0|. Clobbers A.
; ------------------------------------------------------------------------------
proc absolute using console6502 naked
    value : u16 in w0
begin
    lda w0+1
    bmi Fixed.negate
    ret
end

; ------------------------------------------------------------------------------
; sign: A = 1, $FF or 0 for the sign of w0. Clobbers A.
; ------------------------------------------------------------------------------
proc sign using console6502 naked
    value : u16 in w0
    result : u8 return in a
begin
    lda w0+1
    bmi .neg
    ora w0
    beq .zero
    lda #1
    ret
.neg:
    lda #$FF
    ret
.zero:
    lda #0
    ret
end

; ------------------------------------------------------------------------------
; approach: w0 = approach(w0, w1, w2), moving value toward target
; by at most amount:
;
;   val > target and max(val - amount, target) or min(val + amount, target)
;
; Clobbers A.
; ------------------------------------------------------------------------------
proc approach using console6502 naked
    value : u16 in w0
    target : u16 in w1
    amount : u16 in w2
begin
    jsr Fixed.compare
    bmi .up                     ; val < target: approach from below
.down:
    ldab w0  ; val -= amount
    subw w2
    stab w0
    jsr Fixed.compare
    bpl .done                   ; still >= target, keep it
    jmp .clamp
.up:
    ldab w0  ; val += amount
    addw w2
    stab w0
    jsr Fixed.compare
    bmi .done                   ; still < target, keep it
.clamp:
    ldab w1
    stab w0
.done:
    ret
end

; ------------------------------------------------------------------------------
; Object field access. The pool is 64 bytes per record, so every field is
; reachable with a constant Y through (pObj),Y - which is the struct walk
; add-isa-pointer-ops is scored on.
;
; load_object: w0 = the 16-bit field at offset Y.
; store_object: the 16-bit field at offset Y = w0.
; Both clobber A and Y.
; ------------------------------------------------------------------------------
proc load_object using console6502 naked
    value : u16 return in w0
begin
    lda (pObj), y
    sta w0
    iny
    lda (pObj), y
    sta w0+1
    ret
end

proc store_object using console6502 naked
    value : u16 in w0
begin
    lda w0
    sta (pObj), y
    iny
    lda w0+1
    sta (pObj), y
    ret
end

; ------------------------------------------------------------------------------
; load_object_target: the same load through w1. Separate entry points avoid a
; pointer-to-a-pointer, because the caller always knows which register it means.
; ------------------------------------------------------------------------------
proc load_object_target using console6502 naked
    target : u16 return in w1
begin
    lda (pObj), y
    sta w1
    iny
    lda (pObj), y
    sta w1+1
    ret
end

; ------------------------------------------------------------------------------
; set_value / set_target / set_amount: load a constant into a word register.
; A is the low byte and X the high byte.
; ------------------------------------------------------------------------------
proc set_value using console6502 naked
    low : u8 in a
    high : u8 in x
    value : u16 return in w0
begin
    sta w0
    stx w0+1
    ret
end

proc set_target using console6502 naked
    low : u8 in a
    high : u8 in x
    target : u16 return in w1
begin
    sta w1
    stx w1+1
    ret
end

proc set_amount using console6502 naked
    low : u8 in a
    high : u8 in x
    amount : u16 return in w2
begin
    sta w2
    stx w2+1
    ret
end
end
