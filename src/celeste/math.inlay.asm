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
; Objects.move's rounding is the cart's own move(). No general multiply appears
; stage 1 at all - the two irrational dash constants (5*sqrt(2)/2 and 1.5*
; sqrt(2)/2) are selected from a table rather than computed, which is what a
; 6502 programmer would do and is worth contrasting with nemo's single mul8.
; ------------------------------------------------------------------------------

namespace Fixed using console6502
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
    export word0
    export word1
    export word2
    location word0 : u16 at $08
    location word1 : u16 at $0a
    location word2 : u16 at $0c

; ------------------------------------------------------------------------------
; compare: signed compare w0 against w1. Returns N=1 iff w0 < w1, N=0 otherwise
; (including equal). Clobbers A only.
; ------------------------------------------------------------------------------
proc compare naked
    left : u16 in word0
    right : u16 in word1
begin
    lda word0
    cmp word1
    lda word0+1
    sbc word1+1
    bvc .done
    eor #$80                    ; overflow: the sign bit lies, flip it back
.done:
    ret
end

; ------------------------------------------------------------------------------
; add / subtract: w0 += w1 / w0 -= w1. Clobbers A.
; ------------------------------------------------------------------------------
proc add naked
    value : u16 in word0
    amount : u16 in word1
begin
    ldab word0
    addw word1
    stab word0
    ret
end

proc subtract naked
    value : u16 in word0
    amount : u16 in word1
begin
    ldab word0
    subw word1
    stab word0
    ret
end

; ------------------------------------------------------------------------------
; negate: w0 = -w0. Clobbers A.
; ------------------------------------------------------------------------------
proc negate naked
    value : u16 in word0
begin
    ldab #$0000
    subw word0
    stab word0
    ret
end

; ------------------------------------------------------------------------------
; absolute: w0 = |w0|. Clobbers A.
; ------------------------------------------------------------------------------
proc absolute naked
    value : u16 in word0
begin
    lda word0+1
    bmi negate
    ret
end

; ------------------------------------------------------------------------------
; sign: A = 1, $FF or 0 for the sign of w0. Clobbers A.
; ------------------------------------------------------------------------------
proc sign naked
    value : u16 in word0
    result : u8 return in a
begin
    lda word0+1
    bmi .neg
    ora word0
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
proc approach naked
    value : u16 in word0
    target : u16 in word1
    amount : u16 in word2
begin
    jsr compare
    bmi .up                     ; val < target: approach from below
.down:
    ldab word0  ; val -= amount
    subw word2
    stab word0
    jsr compare
    bpl .done                   ; still >= target, keep it
    jmp .clamp
.up:
    ldab word0  ; val += amount
    addw word2
    stab word0
    jsr compare
    bmi .done                   ; still < target, keep it
.clamp:
    ldab word1
    stab word0
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
proc load_object naked
    value : u16 return in word0
begin
    lda (Machine.object), y
    sta word0
    iny
    lda (Machine.object), y
    sta word0+1
    ret
end

proc store_object naked
    value : u16 in word0
begin
    lda word0
    sta (Machine.object), y
    iny
    lda word0+1
    sta (Machine.object), y
    ret
end

; ------------------------------------------------------------------------------
; load_object_target: the same load through w1. Separate entry points avoid a
; pointer-to-a-pointer, because the caller always knows which register it means.
; ------------------------------------------------------------------------------
proc load_object_target naked
    target : u16 return in word1
begin
    lda (Machine.object), y
    sta word1
    iny
    lda (Machine.object), y
    sta word1+1
    ret
end
end
