#include "../../src/isa/nmos6502.asm"

#bankdef variants { #addr 0x0400, #size 0x0100, #outp 0 }
#bank variants

start:
    lda OBJECT_RAM + 0
    sta OBJECT_RAM + 7
    lda OBJECT_RAM + 2
    rts

OBJECT_RAM = $8000
