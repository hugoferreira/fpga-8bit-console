#include "../isa/nmos6502.asm"
#include "../isa/ext_core.asm"
#include "../isa/memmap.asm"

; ------------------------------------------------------------------------------
; Celeste Classic, ported to this console
; ------------------------------------------------------------------------------
; Original cart (c) Matt Thorson and Noel Berry, published on the PICO-8 BBS
; (thread tid=2145), the "Fixed for P8 v0.1.2" revision, cart 15133.
;
; This 6502 game code is an original implementation written for this hardware.
; The art, the room layouts, the tile flags and the audio image come from the
; cart and are extracted by tools/p8_celeste.py and tools/p8_audio.py. See
; docs/corpora.md for the full attribution and the list of divergences.
;
; This program exists as an ISA-calibration corpus (openspec add-celeste-corpus):
; breakout has no 16-bit arithmetic and few pointers, and nemo has pointers but
; no physics, so neither can score add-isa-word-ops on a pattern count. This one
; can: an object list with per-type dispatch, and sub-pixel movement that
; accumulates a 16-bit remainder per axis per object per frame. It is written to
; be ordinary hand-written 6502, transliterating the cart's structure rather
; than redesigning it, because a redesign would measure the redesign.
;
; Deliberate divergences from the original, all forced by the hardware:
;
;   * VERTICAL CAMERA. A Celeste room is 128 lines and this display is 120, so
;     the camera follows the player through the missing 8. The cart's camera is
;     static per room. Everything else about a room is pixel-exact.
;   * STAGE 1 ONLY. The player, its spawn animation, smoke and the room title.
;     The other eleven object types, the effects (clouds, particles, the death
;     burst) and the title screen are stage 2; see the change's tasks.md.
;   * THREE ROOMS, cycled. They were chosen for tile-flag variety rather than
;     adjacency - see inventory.md - so next_room walks a table.
;   * NO SCREEN-SPACE EFFECTS. The console has no line, circle or rectangle
;     primitive. The hair became blob sprites; the clouds, the particles and
;     the black panel behind the room title are simply absent.
;   * 30 Hz LOGIC. The cart defines _update, which PICO-8 runs at 30 fps. The
;     display runs at 60 and the game updates every second vsync, so the
;     physics constants are the cart's own numbers rather than halved ones.
; ------------------------------------------------------------------------------

#bank ram
#addr 0x0300

    #include "memmap.asm"

; ------------------------------------------------------------------------------
reset:
    sei
    cld
    ldx #$FF
    txs

    jsr sheet_upload
    jsr palette_upload
    jsr room_init
    jsr ovl_init
    jsr sound_init
    jsr fx_init
    jsr obj_init

    lda #0
    sta frames
    sta seconds
    sta minutes
    sta deaths
    sta freeze
    sta shake
    sta shake_x
    sta shake_y
    sta will_restart
    sta delay_restart
    sta sfx_timer
    sta music_timer
    sta has_dashed
    sta pause_player
    sta btn
    sta btnprev
    mov max_djump, #1

    jsr title_screen

main_loop:
    jsr wait_frame              ; the cart's _update is 30 Hz; this display is
    jsr wait_frame              ; 60, so a game frame is two of them
    jsr read_buttons
    jsr update_frame
    jsr draw_frame
    jmp main_loop

; ------------------------------------------------------------------------------
; title_screen / begin_game - the cart's two entry points, in its order.
; ------------------------------------------------------------------------------
title_screen:
    lda #0
    sta frames
    sta deaths
    sta start_game
    sta start_game_flash
    mov max_djump, #1
    lda #MUS_TITLE
    jsr music_play
    lda #0                      ; slot 0 is the title room, level 31
    jmp load_room

begin_game:
    lda #0
    sta frames
    sta seconds
    sta minutes
    sta music_timer
    sta start_game
    lda #MUS_CLIMB
    jsr music_play
    lda #1                      ; slot 1 is the first playing room
    jmp load_room

wait_frame:
    lda SPR_FRAME
.wait:
    cmp SPR_FRAME
    beq .wait
    rts

read_buttons:
    lda btn
    sta btnprev
    lda SPR_BTN
    sta btn
    rts

; ------------------------------------------------------------------------------
; update_frame: the cart's _update(), in its order.
; ------------------------------------------------------------------------------
update_frame:
    inc frames                  ; frames = (frames + 1) % 30
    lda frames
    cmp #30
    bcc .clock
    mov frames, #0

    lda level                   ; the clock stops in the last room
    cmp #30
    bcs .clock
    inc seconds
    lda seconds
    cmp #60
    bcc .clock
    mov seconds, #0
    inc minutes
.clock:

    lda music_timer             ; the cart's music_timer: when it runs out the
    beq .nomusictimer           ; climb comes back. Only the orb sets it, so
    dec music_timer             ; nothing in stage 1 starts this countdown -
    bne .nomusictimer           ; the mechanism is here, its trigger is not
    lda #MUS_ORB
    jsr music_play
.nomusictimer:

    lda sfx_timer
    beq .nosfxtimer
    dec sfx_timer
.nosfxtimer:

    lda freeze                  ; the dash freeze: skip the whole update
    beq .nofreeze
    dec freeze
    rts
.nofreeze:

    lda shake
    beq .noshake
    dec shake
    lda shake
    beq .noshake
    lda SPR_RND                 ; -2 + rnd(5), on both axes
    and #3
    sub #2
    sta shake_x
    lda SPR_RND
    and #3
    sub #2
    sta shake_y
    jmp .restart
.noshake:
    lda #0
    sta shake_x
    sta shake_y

.restart:
    lda will_restart
    beq .objects
    lda delay_restart
    beq .objects
    dec delay_restart
    bne .objects
    mov will_restart, #0
    jsr restart_room
    rts

.objects:
    jsr fx_update
    jsr obj_update_all
    ; fall through to the title screen's state machine

; ------------------------------------------------------------------------------
; The cart's `if is_title()` tail of _update: wait for jump or dash, cut the
; music, flash, and hand over to begin_game 80 frames later.
; ------------------------------------------------------------------------------
title_tick:
    jsr is_title
    beq .title
    rts
.title:
    lda start_game
    bne .flashing

    lda btn                     ; btn(k_jump) or btn(k_dash)
    and #BTN_JUMP|BTN_DASH
    beq .done
    jsr music_stop              ; music(-1): cut, no fade
    mov start_game_flash, #50
    mov start_game, #1
    lda #38
    jmp sfx_play

.flashing:
    dec start_game_flash
    lda start_game_flash
    bpl .done                   ; still counting down through zero
    cmp #<(-29)                 ; start_game_flash <= -30
    bcs .done
    jmp begin_game
.done:
    rts

; ------------------------------------------------------------------------------
; The generated files come first: their .defines (sheet slot numbers, room
; count) are textual, so every user of them has to be assembled afterwards.
    #include "gfx.asm"
    #include "rooms.asm"
    #include "audio.asm"

    #include "math.asm"
    #include "obj.asm"
    #include "collide.asm"
    #include "player.asm"
    #include "room.asm"
    #include "draw.asm"
    #include "fx.asm"
    #include "sound.asm"


; ------------------------------------------------------------------------------
; palette_upload: install the generated draw palette.
;
; The sheet stores palette-relative pixel values rather than PICO-8 colour
; indices, which is what lets a three-colour tile cost two slots instead of
; four. Without this table the art is not merely miscoloured, it is nonsense -
; so it goes in before anything is drawn. See tools/p8_celeste.py.
; ------------------------------------------------------------------------------
palette_upload:
    ldx #15
.entry:
    lda draw_palette, x
    sta SPR_DPAL, x
    dex
    bpl .entry
    rts

; ------------------------------------------------------------------------------
; sheet_upload: push the cart's art into the sprite sheet through the
; auto-incrementing port at $4002.
; ------------------------------------------------------------------------------
sheet_upload:
    lda #0
    sta SPR_SHADDR_LO
    sta SPR_SHADDR_HI
    mov pSrc, #<celeste_sheet
    mov pSrc+1, #>celeste_sheet
    mov t0, #<SHEET_BYTES
    mov t1, #>SHEET_BYTES
    ldy #0
.byte:
    lda (pSrc), y
    sta SPR_SHDATA
    inc pSrc
    bne .nohi
    inc pSrc+1
.nohi:
    lda t0
    bne .low
    dec t1
.low:
    dec t0
    lda t0
    ora t1
    bne .byte
    rts

#bank vec
    #d8 (reset)[7:0], (reset)[15:8]                 ; NMI
    #d8 (reset)[7:0], (reset)[15:8]                 ; RESET
    #d8 (reset)[7:0], (reset)[15:8]                 ; IRQ
