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

    #include "../../src/celeste/memmap.inlay.asm"

include "gfx.inlay.asm"
    #include "../../src/celeste/rooms.inlay.asm"
    #include "../../src/celeste/audio.inlay.asm"

include "math.inlay.asm"
include "obj.inlay.asm"
include "collide.inlay.asm"
include "player.inlay.asm"
include "room.inlay.asm"
include "draw.inlay.asm"
include "fx.inlay.asm"
include "sound.inlay.asm"
include "platform.inlay.asm"
include "game.inlay.asm"

; Stable test/debug aliases do not own implementation bodies.
reset = Platform.reset
main_loop = Game.frame

#bank vec
    #d8 (reset)[7:0], (reset)[15:8]                 ; NMI
    #d8 (reset)[7:0], (reset)[15:8]                 ; RESET
    #d8 (reset)[7:0], (reset)[15:8]                 ; IRQ
