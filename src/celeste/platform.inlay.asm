; ------------------------------------------------------------------------------
; Celeste platform boundary
;
; Hardware startup and frame/input services live here. Procedures have no
; hidden inputs or frame locals; comments state the physical clobber contract
; that Inlay cannot yet encode.
; ------------------------------------------------------------------------------

namespace Platform
    export reset
    export wait_frame
    export sample_input
    namespace Input
        left = $01
        right = $02
        up = $04
        down = $08
        jump = $10
        dash = $20
    end

; Inputs: reset machine state. Returns: never; transfers to Game.run.
; Frame locals: none. Clobbers: A, X, Y, pSrc, t0, t1 and hardware upload
; state. Naked because no valid caller frame exists at reset.
proc reset using console6502 naked
begin
    sei
    cld
    ldx #$FF
    txs
    jsr Platform.upload_sheet
    jsr Platform.upload_palette
    jmp Game.run
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: flags.
proc wait_frame using console6502
begin
    lda [video + VideoRegisters.frame]
.wait:
    cmp [video + VideoRegisters.frame]
    beq .wait
    ret
end

; Inputs: none. Returns: buttons in A. Frame locals: none. Clobbers: A.
proc sample_input using console6502
    buttons : u8 return in a
begin
    lda [game + GameState.buttons]
    sta [game + GameState.previous_buttons]
    lda [video + VideoRegisters.buttons]
    sta [game + GameState.buttons]
    ret
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A, X.
proc upload_palette using console6502
begin
    ldx #15
.entry:
    lda Gfx.draw_palette, x
    sta [video + VideoRegisters.draw_palette[x]]
    dex
    bpl .entry
    ret
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A, Y, pSrc,
; t0, t1 and sheet upload state.
proc upload_sheet using console6502
begin
    lda #0
    sta [video + VideoRegisters.sheet_address_low]
    sta [video + VideoRegisters.sheet_address_high]
    lda #<Gfx.sheet
    sta pSrc
    lda #>Gfx.sheet
    sta pSrc+1
    lda #<Gfx.upload_bytes
    sta t0
    lda #>Gfx.upload_bytes
    sta t1
    ldy #0
.byte:
    lda (pSrc), y
    sta [video + VideoRegisters.sheet_data]
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
    ret
end
end
