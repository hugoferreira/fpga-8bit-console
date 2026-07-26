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
    mov 0x23, #0x04           ; pSrc -> 0x04FE
    lda (0x22), #3            ; 0x04FE + 3 = 0x0501, crossing the page
    cmp #0x5C
    bne fail9

pass:
    jmp pass

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
fail:
    sta 0x00FF               ; which check failed
spin:
    jmp spin                 ; a TRUE self-loop: the harness detects `jmp *`,
                             ; the same convention Dormann's test uses. A
                             ; two-instruction loop is never noticed.

table:
    #d8 0x00, 0x11, 0x22, 0x33, 0x44

obj:
    #d8 0x11, 0x00, 0x22, 0x33

; a byte at 0x0501, to prove the displacement carries into the pointer's high
; byte rather than wrapping inside the page
#addr 0x0501
    #d8 0x5C
