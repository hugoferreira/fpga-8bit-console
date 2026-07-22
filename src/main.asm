.segment "CODE"
    ; ------------------------------------------------------------------------------
    ; 128-sprite compositor demo
    ; ------------------------------------------------------------------------------
    ; Streams a 128-entry sprite list to the scanline compositor every loop:
    ; each sprite moves 1px per update with edge bounce, and its X/Y flips
    ; follow the travel direction so the arrow points where it is going.
    ;
    ; System Memory Map
    ; $0000-$00FF: Zero Page   $0100-$01FF: Stack
    ; $0300-....:  Program     $FFFA-$FFFF: Vectors

    ; Sprite compositor registers ($400x)
    .define SPR_PATTERN        $4000  ; $4000-$4007 pattern rows
    .define SPR_INDEX          $4008  ; List index
    .define SPR_X              $4009  ; Staged X
    .define SPR_Y              $400A  ; Staged Y
    .define SPR_FLAGS          $400B  ; bit0 xflip, bit1 yflip; write commits + index++
    .define SPR_COUNT          $400C  ; Active sprite count
    .define SPR_FRAME          $400D  ; Frame counter (read-only, +1 per vsync)

    .define NSPR               128    ; Number of sprites
    .define MAX_X              152    ; 160 - 8
    .define MAX_Y              112    ; 120 - 8

    ; Text buffer
    .define CHAR_RAM           $F000
    .define ATTR_RAM           $F200
    .define COLOR_WHITE_ON_BLACK $0F

    ; Runtime tables (one page each, above the program image)
    .define xpos    $0900
    .define ypos    $0A00
    .define dirs    $0B00  ; bit0: 1=moving left, bit1: 1=moving up

; Program starts here at $0300 (see memory.cfg)
start:
    ; Clear the whole text screen: blank characters, black-on-black attributes
    ldx #0
    lda #$20
clear_chars:
    sta CHAR_RAM,x
    sta CHAR_RAM+256,x
    inx
    bne clear_chars
    lda #$00
clear_attrs:
    sta ATTR_RAM,x
    sta ATTR_RAM+256,x
    inx
    bne clear_attrs

    ; Banner text
    ldx #0
print_text:
    lda text,x
    beq text_done
    sta CHAR_RAM,x
    lda #COLOR_WHITE_ON_BLACK
    sta ATTR_RAM,x
    inx
    bne print_text
text_done:

    ; Program the shared 8x8 pattern through the CPU interface
    ldx #0
load_pattern:
    lda pattern,x
    sta SPR_PATTERN,x
    inx
    cpx #8
    bne load_pattern

    ; Copy initial positions and directions into the runtime tables
    ldx #0
load_tables:
    lda init_x,x
    sta xpos,x
    lda init_y,x
    sta ypos,x
    lda init_d,x
    sta dirs,x
    inx
    cpx #NSPR
    bne load_tables

    lda #NSPR
    sta SPR_COUNT

main_loop:
    ; Pace to the display: wait for the frame counter to change so each
    ; sprite moves exactly 1px per displayed frame
    lda SPR_FRAME
wait_frame:
    cmp SPR_FRAME
    beq wait_frame

    lda #0
    sta SPR_INDEX      ; Rewind the list index
    ldx #0
update:
    ; --- X axis ---
    lda dirs,x
    and #1
    bne @moving_left
    inc xpos,x         ; Moving right
    lda xpos,x
    cmp #MAX_X
    bcc @x_done
    lda dirs,x         ; Hit right edge: turn left
    ora #1
    sta dirs,x
    bne @x_done
@moving_left:
    dec xpos,x
    lda xpos,x
    bne @x_done
    lda dirs,x         ; Hit left edge: turn right
    and #$FE
    sta dirs,x
@x_done:
    ; --- Y axis ---
    lda dirs,x
    and #2
    bne @moving_up
    inc ypos,x         ; Moving down
    lda ypos,x
    cmp #MAX_Y
    bcc @y_done
    lda dirs,x         ; Hit bottom edge: turn up
    ora #2
    sta dirs,x
    bne @y_done
@moving_up:
    dec ypos,x
    lda ypos,x
    bne @y_done
    lda dirs,x         ; Hit top edge: turn down
    and #$FD
    sta dirs,x
@y_done:
    ; --- Stream this entry to the compositor ---
    lda xpos,x
    sta SPR_X
    lda ypos,x
    sta SPR_Y
    lda dirs,x
    eor #3             ; Arrow points along travel: flip when moving right/down
    and #3
    sta SPR_FLAGS      ; Commit, index auto-increments
    inx
    cpx #NSPR
    bne update

    inc $F12           ; Heartbeat for debugging
    jmp main_loop

; ------------------------------------------------------------------------------
; Data
; ------------------------------------------------------------------------------
text:
    .byte "128 SPRITES 1 SHAPE", 0

pattern:
    .byte $01, $03, $07, $0F, $1F, $13, $21, $40

init_x:
    .byte $4E, $3D, $18, $91, $8D, $65, $8F, $35, $64, $75, $05, $00, $49, $23, $32, $51
    .byte $55, $48, $1E, $32, $39, $4C, $71, $02, $03, $27, $7B, $69, $6D, $62, $6C, $96
    .byte $5D, $7B, $4C, $5B, $4D, $33, $23, $2F, $73, $32, $81, $41, $91, $48, $96, $83
    .byte $3D, $4E, $52, $64, $31, $62, $45, $34, $4B, $35, $2F, $52, $5D, $57, $18, $40
    .byte $45, $81, $50, $7D, $05, $81, $57, $69, $83, $48, $05, $93, $69, $36, $92, $15
    .byte $8D, $63, $1E, $0E, $28, $38, $49, $3D, $53, $23, $23, $74, $64, $3D, $24, $22
    .byte $1D, $16, $5C, $17, $2C, $37, $93, $3A, $03, $4E, $59, $7D, $38, $4C, $8E, $4F
    .byte $45, $49, $6A, $4F, $58, $95, $55, $5F, $1B, $19, $17, $8E, $8C, $53, $6F, $14
init_y:
    .byte $3B, $54, $3B, $2A, $09, $0C, $02, $37, $42, $17, $15, $58, $07, $15, $03, $1B
    .byte $66, $06, $0B, $11, $40, $0A, $0F, $2B, $65, $31, $3D, $17, $25, $1A, $57, $56
    .byte $10, $67, $4C, $39, $16, $37, $1B, $0E, $37, $1A, $16, $16, $13, $20, $4B, $62
    .byte $6A, $69, $0C, $00, $4C, $14, $58, $21, $4A, $63, $0E, $66, $42, $25, $40, $4D
    .byte $45, $1A, $4C, $18, $23, $32, $64, $65, $6C, $2D, $57, $05, $10, $2A, $34, $29
    .byte $1F, $5B, $5D, $0F, $19, $2F, $40, $68, $6E, $56, $0F, $35, $4E, $10, $09, $14
    .byte $09, $1D, $2D, $56, $60, $1D, $5D, $0C, $21, $0F, $37, $54, $5D, $05, $2D, $1F
    .byte $34, $4E, $3E, $5E, $46, $3A, $09, $1F, $43, $69, $10, $53, $4B, $6B, $31, $0B
init_d:
    .byte $00, $00, $01, $01, $00, $00, $01, $01, $02, $02, $03, $03, $02, $02, $03, $03
    .byte $00, $00, $01, $01, $00, $00, $01, $01, $02, $02, $03, $03, $02, $02, $03, $03
    .byte $00, $00, $01, $01, $00, $00, $01, $01, $02, $02, $03, $03, $02, $02, $03, $03
    .byte $00, $00, $01, $01, $00, $00, $01, $01, $02, $02, $03, $03, $02, $02, $03, $03
    .byte $00, $00, $01, $01, $00, $00, $01, $01, $02, $02, $03, $03, $02, $02, $03, $03
    .byte $00, $00, $01, $01, $00, $00, $01, $01, $02, $02, $03, $03, $02, $02, $03, $03
    .byte $00, $00, $01, $01, $00, $00, $01, $01, $02, $02, $03, $03, $02, $02, $03, $03
    .byte $00, $00, $01, $01, $00, $00, $01, $01, $02, $02, $03, $03, $02, $02, $03, $03


; ------------------------------------------------------------------------------
; Interrupt Handlers
; ------------------------------------------------------------------------------
nmi_handler:
    rti

irq_handler:
    rti

; ------------------------------------------------------------------------------
; Interrupt vectors
; ------------------------------------------------------------------------------
.segment "VECTORS"
    .word $0000   ; NMI vector - not used
    .word $0300   ; RESET vector - points to program start
    .word $0000   ; IRQ vector - not used
