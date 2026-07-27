; ------------------------------------------------------------------------------
; Celeste - audio
;
; The cart's audio RAM image uploads verbatim: 64 music patterns and 63 SFX in
; PICO-8's runtime format, straight into the PSG's auto-increment port, because
; the PSG holds the same layout. tools/p8_audio.py extracts it.
;
; Stage-1 call sites, from the cart's own code:
;   sfx 0  death          sfx 1  jump          sfx 2  wall jump
;   sfx 3  dash           sfx 4  spawn start   sfx 5  spawn land
;   sfx 9  dash refused   sfx 54 dash refilled
;   music 0  the climb (the cart starts it in begin_game with mask 7)
;
; The cart passes channel mask 7 to music(), reserving channels 0-2, and unlike
; nemo's cart that number is honest - its patterns use exactly those three. So
; the mask is the cart's, not a corrected one.
; ------------------------------------------------------------------------------
namespace Audio
    export init
    export sfx
    export guarded_sfx
    export music
    export fade
    export stop
    location address_low : u8 at $4100
    location address_high : u8 at $4101
    location music_mask : u8 at $4121
    location fade_units : u8 at $4122
    music_title = 40
    music_climb = 0
    music_orb = 10
    music_stop = $80
    fade_500ms = 31

init:
    mov [psg + PsgRegisters.address_low], #$00
    mov [psg + PsgRegisters.address_high], #$31
    mov pSrc, #<audio_data
    mov pSrc+1, #>audio_data
    ldx #18                     ; 18 pages = 4608 bytes
    ldy #0
.up:
    lda (pSrc), y
    sta [psg + PsgRegisters.data]
    iny
    bne .up
    inc pSrc+1
    dex
    bne .up

    mov [psg + PsgRegisters.music_mask], #$07
    lda #0
    sta nextch
    rts

; ------------------------------------------------------------------------------
; sfx_play: A = the cart's SFX number, on an auto-picked channel.
;
; Every call in the cart is sfx(n) with no channel, which is PICO-8's -1: the
; lowest channel that is neither playing nor reserved. The PSG does not
; implement -1, so it is done here - the same routine breakout and nemo each
; needed, for the same reason. Clobbers A, X, Y, t0.
; ------------------------------------------------------------------------------
sfx:
    tax
    lda [psg + PsgRegisters.music_mask]
    and #$0F
    cmp #$0F
    beq .none                   ; music owns every channel: drop the sound

    lda [psg + PsgRegisters.status]
    ora PSG_MUSMASK
    sta t0
    ldy #0
.find:
    lda Audio.channel_bits, y
    and t0
    beq .go
    iny
    cpy #4
    bne .find
.steal:
    lda nextch                  ; all busy: round-robin, skipping the music's
    add #1
    and #3
    sta nextch
    tay
    lda Audio.channel_bits, y
    and PSG_MUSMASK
    bne .steal
.go:
    txa
    sta [psg + PsgRegisters.channels[y]]
.none:
    rts

channel_bits:
    #d8 $01, $02, $04, $08

; ------------------------------------------------------------------------------
; psfx: the cart's psfx(n) - play unless a scripted sound is holding the
; channel budget. Clobbers A, X, Y, t0.
; ------------------------------------------------------------------------------
guarded_sfx:
    ldx sfx_timer
    bne .skip
    jmp Audio.sfx
.skip:
    rts

; ------------------------------------------------------------------------------
; music_play: A = pattern number, or MUS_STOP. No fade.
;
; The PSG applies $22 to the NEXT music start, so a fade has to be cleared
; before an unfaded call or it inherits the last one - which is how the title
; theme ended up fading in behind a cut that was supposed to be instant.
; Clobbers A.
; ------------------------------------------------------------------------------
music:
    ldx #0
    ; fall through

; music_fade: A = pattern (or MUS_STOP), X = fade length in 16 ms units.
; Clobbers A.
fade:
    stx PSG_FADE
    sta [psg + PsgRegisters.music]
    rts

stop:
    lda #MUS_STOP
    jmp Audio.music
end
