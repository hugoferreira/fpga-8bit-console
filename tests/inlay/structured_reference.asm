#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"

#bankdef conformance { #addr 0x0300, #size 0x0100, #outp 0 }
#bank conformance

pObj = 0x10

indexed_load:
    txa
    asl
    asl
    add #7
    tay
    lda (pObj), y
    rts

indexed_store:
    pha
    txa
    tay
    pla
    sta (pObj), y
    rts

typed_operations:
    lda (pWord), #0
    sta w0
    lda (pWord), #1
    sta w0+1
    lda w0
    sta (pWord), #0
    lda w0+1
    sta (pWord), #1
    addw w0
    subw w0
    cmpw w0
    lda (pWord), #2
    add #1
    sta (pWord), #2
    lda (pWord), #2
    sub #1
    sta (pWord), #2
    lda (pWord), #2
    and #$fe
    sta (pWord), #2
    lda (pWord), #2
    ora #1
    sta (pWord), #2
    lda REGS + 0, y
    sta REGS + 0, y
    rts

object_at:
    tax
    mov pObj, obj_lo + x
    lda obj_hi, x
    sta pObj+1
    rts

framed:
    pha
    tsx
    sta $0101, x
    tsx
    lda $0101, x
    tsx
    inx
    txs
    rts

convention:
    rts

pointer_frame:
    pha
    pha
    tsx
    lda pObj
    sta $0102, x
    lda pObj+1
    sta $0101, x
    tsx
    lda $0102, x
    sta pObj
    lda $0101, x
    sta pObj+1
    tsx
    inx
    inx
    txs
    rts

aggregate_frame:
    pha
    pha
    pha
    pha
    tsx
    lda $0101, x
    tsx
    inx
    inx
    inx
    inx
    txs
    rts

callee:
    rts

invoke_swap:
    stx t0
    sta t1
    lda t0
    ldx t1
    jsr callee
    rts

invoke_continued:
    sty t0
    lda #5
    ldx t0
    jsr callee
    rts

callee3:
    rts

invoke_cycle:
    stx t0
    sty t1
    sta t2
    lda t0
    ldx t1
    ldy t2
    jsr callee3
    rts

pointer_callee:
    rts

invoke_pointer:
    lda pOther
    sta t0
    lda pOther+1
    sta t1
    lda t0
    sta pObj
    lda t1
    sta pObj+1
    jsr pointer_callee
    rts

mixed_callee:
    rts

invoke_mixed:
    sta t2
    lda pOther
    sta t0
    lda pOther+1
    sta t1
    lda t0
    sta pObj
    lda t1
    sta pObj+1
    ldx t2
    jsr mixed_callee
    rts

obj_lo:
    #d8 $00, $18, $30, $48
obj_hi:
    #d8 (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8]

OBJPOOL = $8000
pOther = $12
pWord = $14
w0 = $16
REGS = $4100
t0 = $20
t1 = $21
t2 = $22
