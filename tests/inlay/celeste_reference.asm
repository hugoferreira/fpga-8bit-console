#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"

#bankdef conformance { #addr 0x0400, #size 0x0100, #outp 0 }
#bank conformance

pObj = 0x10

player_init:
    lda #0
    sta (pObj), #4
    sta (pObj), #5
    lda #0xF9
    sta (pObj), #12
    sta (pObj), #13
    lda #6
    sta (pObj), #14
    sta (pObj), #15
    lda #1
    sta (pObj), #20
    lda #3
    sta (pObj), #1
    lda (pObj), #18
    rts
