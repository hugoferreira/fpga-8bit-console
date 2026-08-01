; ------------------------------------------------------------------------------
; NEMO - audio
;
; The cart's audio RAM image uploads verbatim: 64 music patterns and 64 SFX
; records in PICO-8's runtime format, straight into the PSG's auto-increment
; port. No conversion, because the PSG holds the same layout.
;
; Event map, recovered from the cart's sfx()/music() call sites:
;
;   sfx 0  fill a cell          (cursor:show_eff_fill, line 885)
;          also puzzle start    (line 1234)
;   sfx 1  clear a cell         (cursor:show_eff_clear, line 889)
;   sfx 2  row/column completed (after update_matchdata, lines 737/742)
;   sfx 3  cursor moved         (line 832) and selector moved (line 1289)
;   sfx 4  move blocked         (show_eff_cant_move, line 838)
;   sfx 5  popup opened         (line 947)     - unused, no popups here
;   sfx 6  popup closed         (line 960)     - unused
;   music 0   menu              (home:show, line 1155)
;   music 13  playing           (puzzle:set_visible, line 266)
;   music 6   cleared           (on_clear, line 759)
;
; Every cart call is sfx(n,-1): PICO-8's auto channel pick. The PSG does not
; implement -1, so sfx_play does it in software - the same routine Breakout
; needed for the same reason (src/main.asm:2451).
; ------------------------------------------------------------------------------

; The SFX_* / MUS_* numbers live in memmap.asm - main.asm needs them first.

; ------------------------------------------------------------------------------
; sound_init: upload the cart's 4608-byte audio image to PICO-8 address $3100.
; Clobbers A, X, Y, pSrc.
; ------------------------------------------------------------------------------
sound_init:
    lda #$00
    sta PSG_ADDR_LO
    lda #$31
    sta PSG_ADDR_HI
    lda #<audio_data
    sta pSrc
    lda #>audio_data
    sta pSrc+1
    ldx #18                     ; 18 pages = 4608 bytes
    ldy #0
@up:
    lda (pSrc),y
    sta PSG_DATA
    iny
    bne @up
    inc pSrc+1
    dex
    bne @up
    ; The cart's own mask, as it passes it to music(): reserve channel 1 only.
    ; The mask no longer has to over-reserve to protect the song: sfx_play
    ; reads the channels the song actually occupies out of $21's high nibble
    ; and leaves them alone, whatever the mask says.
    lda #$02
    sta PSG_MUSMASK
    rts

; ------------------------------------------------------------------------------
; sfx_play: A = cart SFX number, played on an auto-picked channel.
;
; Takes the lowest channel that is idle, unreserved, and not carrying the song,
; so short sounds layer instead of cutting each other off. When none is free the
; sound is dropped rather than stolen from - see the note below.
; Clobbers A, X, Y.
; ------------------------------------------------------------------------------
sfx_play:
    tax                         ; keep the SFX number

    ; Off limits: channels that are reserved (low nibble of $21), channels the
    ; song is actually using (high nibble), and channels already playing.
    ;
    ; PICO-8 never faces this choice. Its four channels are tags on a pool of
    ; sixteen voices, so sfx(n,-1) always gets a voice of its own and music is
    ; untouchable (see docs/hardware-gaps.md). With four physical channels the
    ; closest that gets is: take a free one, and if there is none, drop the
    ; sound. Dropping a cursor beep is much closer to the original than
    ; stealing a channel out from under the music, which is what the previous
    ; round-robin steal did whenever the mask did not name that channel.
    lda PSG_MUSMASK
    sta sfx_busy                ; {owned, reserved}
    lsr
    lsr
    lsr
    lsr                         ; owned channels down into the low nibble
    ora sfx_busy
    ora PSG_STATUS              ; bits 0-3 = channel playing (or triggering)
    sta sfx_busy                ; only bits 0-3 are ever tested

    ldy #0
@find:
    lda bitmask,y
    and sfx_busy
    beq @go                     ; free, unreserved, and not the music's
    iny
    cpy #4
    bne @find
    rts                         ; nothing free: drop the sound
@go:
    txa
    sta PSG_CH,y
    rts

; ------------------------------------------------------------------------------
; music_play: A = pattern number. music_stop silences it.
; The cart fades these in over 1-2 seconds; the PSG's fade register takes 16 ms
; units, so 2000 ms is 125.
; Clobbers A.
; ------------------------------------------------------------------------------
; The cart fades music 0 and 13 over 2000 ms and music 6 over 1000 ms; the PSG's
; fade register is in 16 ms units.
music_play:
    pha
    cmp #MUS_CLEAR
    beq @short
    lda #125                    ; 2000 ms
    jmp @set
@short:
    lda #62                     ; 1000 ms
@set:
    sta PSG_FADE
    pla
    sta PSG_MUSIC
    rts

music_stop:
    lda #$80
    sta PSG_MUSIC
    rts
