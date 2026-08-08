; ------------------------------------------------------------------------------
; Celeste top-level state machine
;
; This namespace owns title/play transitions, clock, freeze/restart sequencing
; and one complete game frame. Persistent values remain in the typed GameState
; overlay; these procedures require no hidden stack locals.
; ------------------------------------------------------------------------------

namespace Game using console6502
    export run
    export frame
    location frames : u8 at $30
    location seconds : u8 at $31
    location minutes : u8 at $32
    location deaths : u8 at $33
    location max_dash_jumps : u8 at $34
    location freeze : u8 at $35
    location shake : u8 at $36
    location shake_x : i8 at $37
    location shake_y : i8 at $38
    location will_restart : u8 at $39
    location restart_delay : u8 at $3a
    location room_slot : u8 at $3b
    location room_bank : u8 at $3c
    location level : u8 at $3d
    location camera_y : u8 at $3e
    location has_key : u8 at $3f
    location buttons : u8 at $40
    location previous_buttons : u8 at $41
    location pressed_buttons : u8 at $42
    location sfx_timer : u8 at $43
    location music_timer : u8 at $44
    location has_dashed : u8 at $45
    location pause_player : u8 at $46
    location sprite_count : u8 at $47
    location overlay_dirty : u8 at $48
    location hud_seconds : u8 at $49
    location next_channel : u8 at $4a
    location start_game : u8 at $4c
    location start_game_flash : i8 at $4d

; Inputs: none. Returns: never. Frame locals: none. Clobbers: all game-visible
; volatile state.
proc run
begin
    jsr Room.init
    jsr Draw.overlay_init
    jsr Audio.init
    jsr Fx.init
    jsr Objects.clear
    jsr Berries.clear

    lda #0
    sta [game.frames]
    sta [game.seconds]
    sta [game.minutes]
    sta [game.deaths]
    sta [game.freeze]
    sta [game.shake]
    sta [game.shake_x]
    sta [game.shake_y]
    sta [game.will_restart]
    sta [game.restart_delay]
    sta [game.sfx_timer]
    sta [game.music_timer]
    sta [game.has_dashed]
    sta [game.has_key]
    sta [game.pause_player]
    sta [game.buttons]
    sta [game.previous_buttons]
    mov [game.max_dash_jumps], #1

    jsr show_title
.loop:
    jsr frame
    jmp .loop
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A, X, Y and
; subsystem-declared volatile scratch.
proc frame
begin
    jsr Platform.wait_frame     ; PICO-8 _update is 30 Hz; the display is 60,
    jsr Draw.overlay_phase      ; so one game frame spans two display frames.
    jsr Platform.wait_frame     ; The first of them is otherwise idle, so it
    jsr Platform.sample_input   ; absorbs one overlay rebuild phase; a tick
    jsr update                  ; misses its boundary only when update+draw
    jsr Draw.frame              ; alone overrun a display frame.
    ret
end

; Inputs: none. Returns: by tail transfer. Frame locals: none. Clobbers: A.
proc show_title
begin
    lda #0
    sta [game.frames]
    sta [game.deaths]
    sta [game.start_game]
    sta [game.start_game_flash]
    mov [game.max_dash_jumps], #1
    lda #Audio.music_title
    jsr Audio.music
    lda #0                      ; slot 0 is the title room, level 31
    jmp Room.load
end

; Inputs: none. Returns: by tail transfer. Frame locals: none. Clobbers: A.
proc begin_play
begin
    lda #0
    sta [game.frames]
    sta [game.seconds]
    sta [game.minutes]
    sta [game.music_timer]
    sta [game.start_game]
    lda #Audio.music_climb
    jsr Audio.music
    lda #1                      ; slot 1 is the first playing room
    jmp Room.load
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A, X, Y and
; subsystem-declared volatile scratch.
proc update
begin
    inc [game.frames]                  ; frames = (frames + 1) % 30
    cblt [game.frames], #30, .clock
    mov [game.frames], #0

    cbge [game.level], #30, .clock     ; the clock stops in the last room
    inc [game.seconds]
    cblt [game.seconds], #60, .clock
    mov [game.seconds], #0
    inc [game.minutes]
.clock:

    lda [game.music_timer]
    beq .nomusictimer
    dec [game.music_timer]
    bne .nomusictimer
    lda #Audio.music_orb
    jsr Audio.music
.nomusictimer:

    lda [game.sfx_timer]
    beq .nosfxtimer
    dec [game.sfx_timer]
.nosfxtimer:

    lda [game.freeze]                  ; dash freeze skips the whole update
    beq .nofreeze
    dec [game.freeze]
    ret
.nofreeze:

    lda [game.shake]
    beq .noshake
    dec [game.shake]
    lda [game.shake]
    beq .noshake
    lda [video.random]          ; the cart's camera(-2+rnd(5)): five offsets
    and #7                      ; per axis, folded from eight random states
    cmp #5
    bcc .xr
    sub #5
.xr:
    sub #2
    sta [game.shake_x]
    lda [video.random]
    and #7
    cmp #5
    bcc .yr
    sub #5
.yr:
    sub #2
    sta [game.shake_y]
    jmp .restart
.noshake:
    lda #0
    sta [game.shake_x]
    sta [game.shake_y]

.restart:
    lda [game.will_restart]
    beq .objects
    lda [game.restart_delay]
    beq .objects
    dec [game.restart_delay]
    bne .objects
    mov [game.will_restart], #0
    jsr Room.restart
    ret

.objects:
    jsr Fx.update
    jsr Objects.update_all
    jmp title_tick
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A.
proc title_tick
begin
    jsr Room.title
    beq .title
    ret
.title:
    lda [game.start_game]
    bne .flashing

    tbz [game.buttons], #Platform.Input.jump|Platform.Input.dash, .done
    jsr Audio.stop
    mov [game.start_game_flash], #50
    mov [game.start_game], #1
    lda #38
    jmp Audio.sfx

.flashing:
    dec [game.start_game_flash]
    lda [game.start_game_flash]
    bpl .done
    cmp #<(-29)
    bcs .done
    jmp begin_play
.done:
    ret
end
end
