; Memory map, replacing src/memory.cfg (ld65 MEMORY/SEGMENTS config).
;
; ZP and STACK carry no code or data of their own (zero-page variables are
; declared as raw addresses via `NAME = 0x..`, not through a ZEROPAGE
; segment) but must still appear, zero-filled, in the final image.

#bankdef zp    { #addr 0x0000, #size 0x0100, #outp 0 }
#bankdef stack { #addr 0x0100, #size 0x0100 }
#bankdef ram   { #addr 0x0200, #size 0xfdfa, #outp 8 * 0x0200 }
#bankdef vec   { #addr 0xfffa, #size 0x0006, #outp 8 * 0xfffa }
