; Directed test for add-isa-core-ergonomics. The 65x02 suite cannot cover these
; instructions - it predates them - so this is their conformance net.
;
; Runs from $0400. Every check falls through on success and branches to `fail`
; on error; `fail` records the check number in $00FF and then spins on a `jmp *`,
; which is what the harness detects - the same convention Dormann's test uses.
;
;   make test-ext
;
; Verified to be able to fail: inverting one comparison makes it stop at that
; check's own trap rather than at `pass`.

#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"

#bankdef prog { #addr 0x0400, #size 0x0400, #outp 0 }
#bank prog

    ; ---- MOV zp, #imm : writes memory, touches nothing else ----
start:
    lda #0xAA
    ldx #0xBB
    ldy #0xCC
    mov 0x12, #0x01          ; the operand the ADD zp / SUB zp checks use
    sec                      ; a flag that MOV must not disturb
    mov 0x10, #0x5A
    lda 0x10
    cmp #0x5A
    bne fail1
    bcc fail1                ; carry must survive MOV
    lda #0xAA                ; and A/X/Y must be untouched
    cmp #0xAA
    bne fail1
    cpx #0xBB
    bne fail1
    cpy #0xCC
    bne fail1

    ; ---- MOV abs, #imm ----
    mov 0x0300, #0x37
    lda 0x0300
    cmp #0x37
    bne fail2

    ; ---- MOV zp, abs,X : the indexed table read ----
    ldx #3
    mov 0x11, table + x
    lda 0x11
    cmp #0x33                ; table+3
    bne fail3

    ; ---- ADD #imm : carry-free, and it must IGNORE the incoming carry ----
    sec
    lda #0x10
    add #0x01
    cmp #0x11                ; 0x11, not 0x12: the set carry is ignored
    bne fail4

    ; ---- ADD zp, and the carry it produces ----
    lda #0xFF
    add 0x12                 ; 0xFF + 0x01
    bcc fail5                ; must carry out
    cmp #0x00
    bne fail5

    ; ---- SUB #imm : borrow-free ----
    clc                      ; a clear carry would borrow on sbc
    lda #0x10
    sub #0x01
    cmp #0x0F                ; 0x0F, not 0x0E
    bne fail6

    ; ---- SUB zp, and the borrow it produces ----
    lda #0x00
    sub 0x12                 ; 0x00 - 0x01
    bcs fail7                ; must borrow
    cmp #0xFF
    bne fail7

    ; ---- LDA (zp),#d and STA (zp),#d : field access without Y ----
    mov 0x20, #<obj           ; pObj -> obj
    mov 0x21, #>obj
    ldy #0x77                 ; Y must survive
    lda (0x20), #2            ; obj+2
    cmp #0x22
    bne fail8
    cpy #0x77
    bne fail8
    lda #0x99
    sta (0x20), #1            ; write obj+1
    lda (0x20), #1
    cmp #0x99
    bne fail8
    ; the displacement must carry into the pointer's high byte
    mov 0x22, #0xFE
    mov 0x23, #0x06           ; pSrc -> 0x06FE
    lda (0x22), #3            ; 0x06FE + 3 = 0x0701, crossing the page
    cmp #0x5C
    bne fail9

    jmp word_checks

; The failure handlers sit in the middle: the test outgrew the +/-127 byte
; branch range, and every check has to be able to reach them.
fail1: lda #1
    jmp fail
fail2: lda #2
    jmp fail
fail3: lda #3
    jmp fail
fail4: lda #4
    jmp fail
fail5: lda #5
    jmp fail
fail6: lda #6
    jmp fail
fail7: lda #7
    jmp fail
fail8: lda #8
    jmp fail
fail9: lda #9
    jmp fail
fail10: lda #10
    jmp fail
fail11: lda #11
    jmp fail
fail12: lda #12
    jmp fail
fail13: lda #13
    jmp fail
fail14: lda #14
fail:
    sta 0x00FF               ; which check failed
spin:
    jmp spin                 ; a TRUE self-loop: the harness detects `jmp *`,
                             ; the same convention Dormann's test uses. A
                             ; two-instruction loop is never noticed.

word_checks:
    ; ---- AB, the 16-bit accumulator ----
    ldab #0x1234              ; A = 0x12 (high), B = 0x34 (low)
    cmp #0x12                 ; the high half is in A, usable directly
    bne fail10
    stab 0x30
    lda 0x30
    cmp #0x34                 ; little-endian: low byte at zp
    bne fail10
    lda 0x31
    cmp #0x12
    bne fail10

    ; add with a carry out of the low half into the high
    ldab #0x00FF
    addw #0x0001
    cmp #0x01                 ; 0x00FF + 1 = 0x0100
    bne fail11
    stab 0x30
    lda 0x30
    bne fail11                ; low half must be 0

    ; a 16-bit add against memory, the sequence this slice exists to replace
    mov 0x32, #0x11
    mov 0x33, #0x22           ; word at 0x32 = 0x2211
    ldab #0x1100
    addw 0x32
    cmp #0x33                 ; 0x1100 + 0x2211 = 0x3311
    bne fail12
    stab 0x30
    lda 0x30
    cmp #0x11
    bne fail12

    ; subtract, and the Z flag spanning both halves
    ldab #0x2211
    subw 0x32                 ; 0x2211 - 0x2211 = 0
    bne fail13                ; Z must be set across BOTH bytes
    ldab #0x2212
    subw 0x32
    beq fail13                ; and clear when only the low half differs

    ; compare leaves AB alone
    ldab #0x2211
    cmpw 0x32
    bne fail14
    cmp #0x22
    bne fail14

    ; ---- XBA : exchange the halves of AB ----
    ; A genuine exchange, not a copy: both halves must move.
    ldab #0x1234             ; A = 0x12, B = 0x34
    xba
    cmp #0x34                ; new A is the old B
    bne fail15
    stab 0x30
    lda 0x30
    cmp #0x12                ; new B is the old A
    bne fail15

    ; ...so twice is the identity
    ldab #0xC37E
    xba
    xba
    cmp #0xC3
    bne fail16
    stab 0x30
    lda 0x30
    cmp #0x7E
    bne fail16

    ; the idiom this exists for: an interrupt handler preserving BOTH halves
    ; across a body that destroys them. 0x38, not 0x31: `stab 0x30` writes B at
    ; 0x30 and A at 0x31, so parking the stack pointer there loses it.
    tsx
    stx 0x38                 ; S before
    ldab #0xBEEF             ; A = 0xBE, B = 0xEF
    pha                      ; save A
    xba
    pha                      ; save B - the exchange is what makes it reachable
    ldab #0x0000             ; the "handler" destroys both halves
    pla                      ; A = old B
    xba                      ; ...into B, where it belongs
    pla                      ; A = old A
    cmp #0xBE
    bne fail17               ; A came back
    stab 0x30
    lda 0x30
    cmp #0xEF
    bne fail17               ; and so did B
    tsx
    cpx 0x38
    bne fail17               ; the idiom is stack-neutral

    ; N and Z come from the NEW A, which is the old B
    ldab #0xFF00             ; B = 0x00
    xba
    beq xba_zero_ok
    jmp fail18
xba_zero_ok:
    ldab #0x0080             ; B = 0x80
    xba
    bpl fail18

pass:
    jmp pass

; These four sit here, not with fail1..fail14 above, because a branch from the
; XBA checks cannot reach that far back.
fail15: lda #15
    jmp fail
fail16: lda #16
    jmp fail
fail17: lda #17
    jmp fail
fail18: lda #18
    jmp fail


table:
    #d8 0x00, 0x11, 0x22, 0x33, 0x44

obj:
    #d8 0x11, 0x00, 0x22, 0x33

; a byte at 0x0701, to prove the displacement carries into the pointer's high
; byte rather than wrapping inside the page
#addr 0x0701
    #d8 0x5C
