; ------------------------------------------------------------------------------
; Celeste Classic, ported to this console
;
; This is the composition root: target rules, memory/layout declarations,
; subsystem modules and reset-vector binding. Runtime orchestration belongs to
; Game; hardware startup and services belong to Platform.
; ------------------------------------------------------------------------------

#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"
#include "../../src/isa/pseudo.asm"
#include "../../src/isa/memmap.asm"

include "layout.inlay.asm"

#bank ram
#addr 0x0300


include "gfx.inlay.asm"
    #include "../../src/celeste/audio.inlay.asm"

include "math.inlay.asm"
include "obj.inlay.asm"
include "collide.inlay.asm"
include "player.inlay.asm"
include "content.inlay.asm"
include "room.inlay.asm"
include "draw.inlay.asm"
include "fx.inlay.asm"
include "sound.inlay.asm"
include "platform.inlay.asm"
include "game.inlay.asm"

; Room payloads are cold data and the ten-room campaign no longer fits beside
; executable code below the $4000 MMIO window. Keep them in the free RAM image
; immediately above the overlay shadow instead; room loading already uses a
; 16-bit source pointer, so this changes placement rather than behaviour.
#addr 0x6a00
    #include "../../src/celeste/rooms.inlay.asm"

; Stable test/debug aliases do not own implementation bodies.
reset = Platform.reset
main_loop = Game.frame

#bank vec
    data codeptr Platform.reset ; NMI
    data codeptr Platform.reset ; RESET
    data codeptr Platform.reset ; IRQ
