; ------------------------------------------------------------------------------
; Celeste top-level state machine
;
; This namespace owns title/play transitions, clock, freeze/restart sequencing
; and one complete game frame. Persistent values remain in the typed GameState
; overlay; these procedures require no hidden stack locals.
; ------------------------------------------------------------------------------

namespace Game
    export run
    export frame

; Inputs: none. Returns: never. Frame locals: none. Clobbers: all game-visible
; volatile state.
proc run using console6502
begin
    jsr Room.init
    jsr Draw.overlay_init
    jsr Audio.init
    jsr Fx.init
    jsr Objects.clear

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

    jsr Game.show_title
.loop:
    jsr Game.frame
    jmp .loop
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A, X, Y and
; subsystem-declared volatile scratch.
proc frame using console6502
begin
    jsr Platform.wait_frame     ; PICO-8 _update is 30 Hz; the display is 60,
    jsr Platform.wait_frame     ; so one game frame spans two display frames
    jsr Platform.sample_input
    jsr Game.update
    jsr Draw.frame
    ret
end

; Inputs: none. Returns: by tail transfer. Frame locals: none. Clobbers: A.
proc show_title using console6502
begin
    lda #0
    sta frames
    sta deaths
    sta start_game
    sta start_game_flash
    mov max_djump, #1
    lda #MUS_TITLE
    jsr Audio.music
    lda #0                      ; slot 0 is the title room, level 31
    jmp Room.load
end

; Inputs: none. Returns: by tail transfer. Frame locals: none. Clobbers: A.
proc begin_play using console6502
begin
    lda #0
    sta frames
    sta seconds
    sta minutes
    sta music_timer
    sta start_game
    lda #MUS_CLIMB
    jsr Audio.music
    lda #1                      ; slot 1 is the first playing room
    jmp Room.load
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A, X, Y and
; subsystem-declared volatile scratch.
proc update using console6502
begin
    inc frames                  ; frames = (frames + 1) % 30
    cblt frames, #30, .clock
    mov frames, #0

    cbge level, #30, .clock     ; the clock stops in the last room
    inc seconds
    cblt seconds, #60, .clock
    mov seconds, #0
    inc minutes
.clock:

    lda music_timer
    beq .nomusictimer
    dec music_timer
    bne .nomusictimer
    lda #MUS_ORB
    jsr Audio.music
.nomusictimer:

    lda sfx_timer
    beq .nosfxtimer
    dec sfx_timer
.nosfxtimer:

    lda freeze                  ; dash freeze skips the whole update
    beq .nofreeze
    dec freeze
    ret
.nofreeze:

    lda shake
    beq .noshake
    dec shake
    lda shake
    beq .noshake
    lda [video + VideoRegisters.random]
    and #3
    sub #2
    sta shake_x
    lda [video + VideoRegisters.random]
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
    jsr Room.restart
    ret

.objects:
    jsr Fx.update
    jsr Objects.update_all
    jmp Game.title_tick
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A.
proc title_tick using console6502
begin
    jsr Room.title
    beq .title
    ret
.title:
    lda start_game
    bne .flashing

    tbz btn, #BTN_JUMP|BTN_DASH, .done
    jsr Audio.stop
    mov start_game_flash, #50
    mov start_game, #1
    lda #38
    jmp Audio.sfx

.flashing:
    dec start_game_flash
    lda start_game_flash
    bpl .done
    cmp #<(-29)
    bcs .done
    jmp Game.begin_play
.done:
    ret
end
end
