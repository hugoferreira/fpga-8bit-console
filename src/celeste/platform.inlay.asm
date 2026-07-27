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
        export left
        export right
        export up
        export down
        export jump
        export dash
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
    lda [video.frame]
.wait:
    cmp [video.frame]
    beq .wait
    ret
end

; Inputs: none. Returns: buttons in A. Frame locals: none. Clobbers: A.
proc sample_input using console6502
    buttons : u8 return in a
begin
    lda [game.buttons]
    sta [game.previous_buttons]
    lda [video.buttons]
    sta [game.buttons]
    ret
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A, X.
proc upload_palette using console6502
begin
    ldx #15
.entry:
    lda Gfx.draw_palette, x
    sta [video.draw_palette[x]]
    dex
    bpl .entry
    ret
end

; Inputs: none. Returns: none. Frame locals: none. Clobbers: A, Y, pSrc,
; t0, t1 and sheet upload state.
proc upload_sheet using console6502
begin
    lda #0
    sta [video.sheet_address_low]
    sta [video.sheet_address_high]
    lda #<Gfx.sheet
    sta Machine.source
    lda #>Gfx.sheet
    sta Machine.source+1
    lda #<Gfx.upload_bytes
    sta Machine.t0
    lda #>Gfx.upload_bytes
    sta Machine.t1
    ldy #0
.byte:
    lda (Machine.source), y
    sta [video.sheet_data]
    inc Machine.source
    bne .nohi
    inc Machine.source+1
.nohi:
    lda Machine.t0
    bne .low
    dec Machine.t1
.low:
    dec Machine.t0
    lda Machine.t0
    ora Machine.t1
    bne .byte
    ret
end
end
