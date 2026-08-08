#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"

#bankdef conformance { #addr 0x0300, #size 0x0200, #outp 0 }
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
    sta pObj
    lda pOther+1
    sta pObj+1
    jsr pointer_callee
    rts

mixed_callee:
    rts

invoke_mixed:
    sta t0
    lda pOther
    sta pObj
    lda pOther+1
    sta pObj+1
    ldx t0
    jsr mixed_callee
    rts

observation_operations:
    lda (pWord), #2
    beq .idle
    sub #1
    sta (pWord), #2
.idle:
    ldy #0
    lda (pWord), y
    iny
    ora (pWord), y
    lda w0
    ora w0+1
    rts

word_moves:
    lda #$34
    sta w0
    lda #$12
    sta w0+1
    lda #$fe
    sta w0
    lda #$ff
    sta w0+1
    lda w0
    sta w1
    lda w0+1
    sta w1+1
    lda #$01
    sta (pWord), #0
    lda #$80
    sta (pWord), #1
    rts

inline_caller:
    lda (pWord), #2
    beq .ic1
    sub #1
    sta (pWord), #2
.ic1:
    lda (pWord), #2
    beq .ic2
    sub #1
    sta (pWord), #2
.ic2:
    rts

field_callee:
    rts

invoke_field_sources:
    lda (pWord), #2
    add #1
    sta t2
    lda #$34
    sta w0
    lda #$12
    sta w0+1
    jsr field_callee
    rts

register_callee:
    rts

invoke_register_fields:
    lda (pWord), #2
    add #4
    tax
    lda (pWord), #2
    jsr register_callee
    rts

invoke_tail_caller:
    lda #0
    sta w0
    lda #0
    sta w0+1
    mov t2, #3
    jmp field_callee

obj_lo:
    #d8 $00, $18, $30, $48
obj_hi:
    #d8 (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8], (OBJPOOL)[15:8]

OBJPOOL = $8000
pOther = $12
pWord = $14
w0 = $16
w1 = $18
REGS = $4100
t0 = $20
t1 = $21
t2 = $22
