; ------------------------------------------------------------------------------
; NEMO - Puzzle Pack II, ported to this console
; ------------------------------------------------------------------------------
; Original cart (c) mooon, published on the PICO-8 BBS (thread pid=109965),
; cart revision 1.01 (2022-09-19). Its music is from Gruber's "Pico-8 Tunes
; Volume 1" and its 18 music patterns and 22 sound effects are used here as the
; cart shipped them.
;
; This 6502 game code is an original implementation written for this hardware.
; The puzzle designs and the audio image come from the cart and are extracted by
; tools/p8_nemo.py and tools/p8_audio.py. See docs/corpora.md for the full
; attribution and the list of deliberate divergences from the original.
;
; This program exists as an ISA-calibration corpus (openspec add-nemo-corpus):
; a program with no frame-budget pressure, so that plumbing attributable to the
; instruction set can be told apart from plumbing that is really
; hand-optimisation. It is written to be ordinary hand-written 6502, not to
; show the ISA in a good or a bad light.
; ------------------------------------------------------------------------------

.segment "CODE"

    .include "memmap.asm"

    .define ST_SELECT          0
    .define ST_PLAY            1
    .define ST_CLEAR           2

; ------------------------------------------------------------------------------
reset:
    sei
    cld
    ldx #$FF
    txs

    ; Three layers, each doing what it is good at: the tilemap carries colour
    ; (the green field, the wordmark blocks, the black bars), the overlay carries
    ; everything on a 6-pixel or 4-pixel grid that tiles cannot express (the
    ; puzzle grid, clue digits, all text), and one sprite carries the cursor.
    jsr tiles_init              ; sets SPR_CTRL and the overlay colour
    jsr render_init
    jsr sprites_init
    jsr sound_init
    jsr obj_init
    jsr progress_clear
    jsr ovl_clear

    ; The puzzle listens for its own cell-change and win events, the way the
    ; cart's puzzle registers handlers on itself.
    lda #<on_cell_changed
    sta t4
    lda #>on_cell_changed
    sta t5
    lda #0
    sta t6
    lda #EV_CELL_CHANGED
    jsr ev_on

    lda #<on_puzzle_clear
    sta t4
    lda #>on_puzzle_clear
    sta t5
    lda #0
    sta t6
    lda #EV_PUZZLE_CLEAR
    jsr ev_on

    lda #<on_cursor_moved
    sta t4
    lda #>on_cursor_moved
    sta t5
    lda #0
    sta t6
    lda #EV_CURSOR_MOVED
    jsr ev_on

    lda #0
    sta pz_idx
    sta cur_x
    sta cur_y
    sta cur_blink
    sta btn
    sta is_clear
    lda #ST_SELECT
    sta state
    lda #1
    sta dirty

    lda #MUS_MENU
    jsr music_play

; ------------------------------------------------------------------------------
main_loop:
    lda SPR_FRAME               ; wait for vsync
@wf: cmp SPR_FRAME
    beq @wf

    jsr input_read
    jsr sprites_frame           ; the wordmark animates, so this runs every frame

    lda state
    cmp #ST_SELECT
    beq do_select
    cmp #ST_PLAY
    beq do_play
    jmp do_clear

; ------------------------------------------------------------------------------
do_select:
    jsr sel_update
    lda dirty
    beq @done
    jsr sel_draw
    jsr ovl_blit
@done:
    jmp main_loop

; ------------------------------------------------------------------------------
do_play:
    jsr cursor_move
    jsr cell_edit
    lda dirty
    beq @done
    jsr draw_board
    jsr ovl_blit
@done:
    jmp main_loop

; ------------------------------------------------------------------------------
do_clear:
    lda dirty
    beq @input
    jsr draw_board
    jsr ovl_blit
@input:
    lda btnedge
    and #BTN_O|BTN_X
    beq @done
    lda #ST_SELECT
    sta state
    inc dirty
    lda #MUS_MENU
    jsr music_play
@done:
    jmp main_loop

; ------------------------------------------------------------------------------
; Event handlers
; ------------------------------------------------------------------------------

; on_cursor_moved: the cart plays sfx 3 on a move and sfx 4 when the move was
; refused at an edge. cursor_move leaves the outcome in t0.
on_cursor_moved:
    lda t0
    beq @blocked
    lda #SFX_MOVE
    jmp sfx_play
@blocked:
    lda #SFX_BLOCKED
    jmp sfx_play

; on_puzzle_clear: stop for the win music and let draw_board redraw once with
; the cursor gone and every clue strip cleared.
on_puzzle_clear:
    lda #ST_CLEAR
    sta state
    inc dirty
    lda #0
    sta SPR_COUNT
    lda #MUS_CLEAR
    jmp music_play

; ------------------------------------------------------------------------------
    .include "tiles.asm"
    .include "grid.asm"
    .include "puzzle.asm"
    .include "clues.asm"
    .include "render.asm"
    .include "scene.asm"
    .include "sprites.asm"
    .include "sound.asm"
    .include "obj.asm"
    .include "input.asm"
    .include "select.asm"
    .include "puzzles.asm"
    .include "audio.asm"

; ------------------------------------------------------------------------------
nmi_handler:
irq_handler:
    rti

.segment "VECTORS"
    .word nmi_handler
    .word reset
    .word irq_handler
