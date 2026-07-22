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
    .define SPR_SHADDR_LO      $4000  ; Sheet upload address, low byte
    .define SPR_SHADDR_HI      $4001  ; Sheet upload address, high 3 bits
    .define SPR_SHDATA         $4002  ; Sheet data (write stores + addr++)
    .define SPR_CAMX           $4003  ; Tilemap camera X
    .define SPR_CAMY           $4004  ; Tilemap camera Y
    .define SPR_CTRL           $4005  ; Control: bit0 tilemap, bit1 overlay
    .define SPR_OVLCOL         $4006  ; Overlay color (4 bits)
    .define OVL                $E000  ; Overlay bitmap window (write-only)
    .define SPR_INDEX          $4008  ; List index
    .define SPR_X              $4009  ; Staged X
    .define SPR_Y              $400A  ; Staged Y
    .define SPR_FLAGS          $400B  ; bit0 xflip, bit1 yflip; write commits + index++
    .define SPR_COUNT          $400C  ; Active sprite count
    .define SPR_FRAME          $400D  ; Frame counter (read-only, +1 per vsync)
    .define SPR_BASE           $400E  ; Staged pattern base (plane-slot addr)

    .define NSPR               128    ; Number of sprites
    .define MAX_X              152    ; 160 - 8
    .define MAX_Y              112    ; 120 - 8

    ; Tilemap window (write-only): cell low bytes = pattern base,
    ; cell high bytes = {pal[3:0], bpp-1[1:0], yflip, xflip}
    .define MAP_LO             $F000
    .define MAP_HI             $F200

    ; Runtime tables (one page each, above the program image)
    .define xpos    $0900
    .define ypos    $0A00
    .define dirs    $0B00  ; bit0: 1=moving left, bit1: 1=moving up

    ; Zero page
    .define camx    $04
    .define camdx   $05
    .define camy    $06
    .define camdy   $07
    .define tmp     $08
    .define rowr    $09
    .define ptr     $0A    ; and $0B
    .define dotx    $0C
    .define doty    $0D
    .define dotdx   $0E
    .define dotdy   $0F

; Program starts here at $0300 (see memory.cfg)
start:
    ; Clear the whole tilemap (both byte planes, 512 cells each)
    ldx #0
    lda #0
clear_map:
    sta MAP_LO,x
    sta MAP_LO+256,x
    sta MAP_HI,x
    sta MAP_HI+256,x
    inx
    bne clear_map

    ; Decorate the world: 2bpp diamond tiles on the (tx+ty)%8==0 diagonals.
    ; For cell byte X of either page, tx = X&31 and ty%8 = X>>5, so the
    ; same loop body serves both halves of the map.
decor_page0:
    ldx #0
@loop:
    txa
    and #31
    sta tmp
    txa
    lsr
    lsr
    lsr
    lsr
    lsr                ; A = ty & 7
    tay
    clc
    adc tmp
    and #7
    bne @next
    lda paltbl4,y      ; {pal, bpp-1=1, no flips} by tile row
    sta MAP_HI,x
    lda #5             ; diamond pattern base
    sta MAP_LO,x
@next:
    inx
    bne @loop
decor_page1:
    ldx #0
@loop:
    txa
    and #31
    sta tmp
    txa
    lsr
    lsr
    lsr
    lsr
    lsr
    tay
    clc
    adc tmp
    and #7
    bne @next
    lda paltbl4,y
    sta MAP_HI+256,x
    lda #5
    sta MAP_LO+256,x
@next:
    inx
    bne @loop

    ; Text banner living in the world at tile row 2, column 2: font glyphs
    ; sit in sheet slots 128-255, so base = charcode | $80
    ldx #0
write_text:
    lda text,x
    ora #$80
    sta MAP_LO+66,x
    lda #$60           ; palette 6 -> glyph color 7 (white)
    sta MAP_HI+66,x
    inx
    cpx #17
    bne write_text

    ; Camera starts at the origin drifting down-right
    lda #0
    sta camx
    sta camy
    lda #1
    sta camdx
    sta camdy

    ; --- Overlay: clear all 2560 bytes ---
    ldx #0
    lda #0
clear_ovl:
    sta OVL,x
    sta OVL+$100,x
    sta OVL+$200,x
    sta OVL+$300,x
    sta OVL+$400,x
    sta OVL+$500,x
    sta OVL+$600,x
    sta OVL+$700,x
    sta OVL+$800,x
    sta OVL+$900,x
    inx
    bne clear_ovl

    ; Box border: solid top and bottom rows, single-pixel sides
    ldx #0
    lda #$FF
border_h:
    sta OVL,x          ; row 0
    sta OVL+2380,x     ; row 119
    inx
    cpx #20
    bne border_h
    lda #<(OVL+20)     ; rows 1-118
    sta ptr
    lda #>(OVL+20)
    sta ptr+1
    ldx #118
border_v:
    ldy #0
    lda #$01
    sta (ptr),y
    ldy #19
    lda #$80
    sta (ptr),y
    lda ptr
    clc
    adc #20
    sta ptr
    bcc @nc
    inc ptr+1
@nc:
    dex
    bne border_v

    ; 4x6-font banner at pixel row 8, x = 16: two glyphs pack per overlay
    ; byte (even glyph in bits 0-3, odd in bits 4-7), so a 4px text pitch
    ; needs no cross-byte shifting - this is what the tile grid cannot do
    lda #<(OVL+8*20+2)
    sta ptr
    lda #>(OVL+8*20+2)
    sta ptr+1
    lda #0
    sta rowr
text_row:
    ldx #0
text_pair:
    txa
    asl
    tay
    lda txtoff+1,y     ; odd glyph of the pair -> high nibble
    clc
    adc rowr
    tay
    lda font46,y
    asl
    asl
    asl
    asl
    sta tmp
    txa
    asl
    tay
    lda txtoff,y       ; even glyph -> low nibble
    clc
    adc rowr
    tay
    lda font46,y
    ora tmp
    pha
    txa
    tay
    pla
    sta (ptr),y
    inx
    cpx #6
    bne text_pair
    lda ptr
    clc
    adc #20
    sta ptr
    bcc @nc2
    inc ptr+1
@nc2:
    inc rowr
    lda rowr
    cmp #6
    bne text_row

    ; Bouncing dot starts mid-box
    lda #80
    sta dotx
    lda #60
    sta doty
    lda #1
    sta dotdx
    sta dotdy

    ; Upload the sprite sheet (8 plane slots = 64 bytes) through the
    ; auto-incrementing sheet port
    lda #0
    sta SPR_SHADDR_LO
    sta SPR_SHADDR_HI
    ldx #0
load_sheet:
    lda pattern,x
    sta SPR_SHDATA
    inx
    cpx #64
    bne load_sheet

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
    lda #10
    sta SPR_OVLCOL     ; Overlay draws in yellow
    lda #3
    sta SPR_CTRL       ; Enable tilemap + overlay

main_loop:
    ; Pace to the display: wait for the frame counter to change so each
    ; sprite moves exactly 1px per displayed frame
    lda SPR_FRAME
wait_frame:
    cmp SPR_FRAME
    beq wait_frame

    ; Drift the camera with edge bounce: x over 0..96, y over 0..8
    lda camx
    clc
    adc camdx
    sta camx
    beq @flipx
    cmp #96
    bne @xdone
@flipx:
    lda #0
    sec
    sbc camdx
    sta camdx
@xdone:
    lda camy
    clc
    adc camdy
    sta camy
    beq @flipy
    cmp #8
    bne @ydone
@flipy:
    lda #0
    sec
    sbc camdy
    sta camdy
@ydone:
    lda camx
    sta SPR_CAMX
    lda camy
    sta SPR_CAMY

    ; Move the overlay dot: erase, bounce over x 9..150 / y 20..110, redraw
    ldy doty
    lda rowtab_lo,y
    sta ptr
    lda rowtab_hi,y
    sta ptr+1
    lda dotx
    lsr
    lsr
    lsr
    tay
    lda #0
    sta (ptr),y
    lda dotx
    clc
    adc dotdx
    sta dotx
    cmp #9
    beq @dflipx
    cmp #150
    bne @dxdone
@dflipx:
    lda #0
    sec
    sbc dotdx
    sta dotdx
@dxdone:
    lda doty
    clc
    adc dotdy
    sta doty
    cmp #20
    beq @dflipy
    cmp #110
    bne @dydone
@dflipy:
    lda #0
    sec
    sbc dotdy
    sta dotdy
@dydone:
    ldy doty
    lda rowtab_lo,y
    sta ptr
    lda rowtab_hi,y
    sta ptr+1
    lda dotx
    and #7
    tay
    lda bittab,y
    sta tmp
    lda dotx
    lsr
    lsr
    lsr
    tay
    lda tmp
    sta (ptr),y

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
    lda init_b,x       ; This sprite's pattern base in the sheet
    sta SPR_BASE
    lda dirs,x
    eor #3             ; Arrow points along travel: flip when moving right/down
    and #3
    ora init_f,x       ; Static per-sprite bits: palette base and bpp
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
    .byte "SCROLLING TILEMAP", 0

paltbl4:
    ; {pal[3:0], bpp-1=1, no flips} for each tile row mod 8
    .byte $84, $24, $A4, $44, $C4, $54, $34, $04

font46:
    .byte $07, $05, $05, $05, $07, $00, $05, $05, $05, $05, $02, $00, $07, $01, $03, $01
    .byte $07, $00, $03, $05, $03, $05, $05, $00, $01, $01, $01, $01, $07, $00, $02, $05
    .byte $07, $05, $05, $00, $05, $05, $02, $02, $02, $00, $00, $00, $00, $00, $00, $00
    .byte $05, $05, $07, $04, $04, $00, $05, $05, $02, $05, $05, $00, $07, $01, $07, $05
    .byte $07, $00, $01, $01, $01, $00, $01, $00
txtoff:
    .byte $00, $06, $0C, $12, $18, $1E, $24, $2A, $30, $36, $3C, $42
rowtab_lo:
    .byte $00, $14, $28, $3C, $50, $64, $78, $8C, $A0, $B4, $C8, $DC, $F0, $04, $18, $2C
    .byte $40, $54, $68, $7C, $90, $A4, $B8, $CC, $E0, $F4, $08, $1C, $30, $44, $58, $6C
    .byte $80, $94, $A8, $BC, $D0, $E4, $F8, $0C, $20, $34, $48, $5C, $70, $84, $98, $AC
    .byte $C0, $D4, $E8, $FC, $10, $24, $38, $4C, $60, $74, $88, $9C, $B0, $C4, $D8, $EC
    .byte $00, $14, $28, $3C, $50, $64, $78, $8C, $A0, $B4, $C8, $DC, $F0, $04, $18, $2C
    .byte $40, $54, $68, $7C, $90, $A4, $B8, $CC, $E0, $F4, $08, $1C, $30, $44, $58, $6C
    .byte $80, $94, $A8, $BC, $D0, $E4, $F8, $0C, $20, $34, $48, $5C, $70, $84, $98, $AC
    .byte $C0, $D4, $E8, $FC, $10, $24, $38, $4C
rowtab_hi:
    .byte $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E1, $E1, $E1
    .byte $E1, $E1, $E1, $E1, $E1, $E1, $E1, $E1, $E1, $E1, $E2, $E2, $E2, $E2, $E2, $E2
    .byte $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E3, $E3, $E3, $E3, $E3, $E3, $E3, $E3, $E3
    .byte $E3, $E3, $E3, $E3, $E4, $E4, $E4, $E4, $E4, $E4, $E4, $E4, $E4, $E4, $E4, $E4
    .byte $E5, $E5, $E5, $E5, $E5, $E5, $E5, $E5, $E5, $E5, $E5, $E5, $E5, $E6, $E6, $E6
    .byte $E6, $E6, $E6, $E6, $E6, $E6, $E6, $E6, $E6, $E6, $E7, $E7, $E7, $E7, $E7, $E7
    .byte $E7, $E7, $E7, $E7, $E7, $E7, $E7, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8
    .byte $E8, $E8, $E8, $E8, $E9, $E9, $E9, $E9
bittab:
    .byte $01, $02, $04, $08, $10, $20, $40, $80


pattern:
    ; Sheet image, one 8-byte plane slot per line: 4bpp arrow at base 0
    ; (planes 1-2 subsets of the silhouette), 1bpp disc at 4, 2bpp diamond
    ; at 5 (rim + inner), 1bpp cross at 7 - mixed footprints back to back
    .byte $01, $03, $07, $0F, $1F, $13, $21, $40
    .byte $00, $03, $00, $0F, $00, $13, $00, $40
    .byte $00, $00, $00, $00, $10, $10, $20, $40
    .byte $00, $00, $00, $00, $00, $00, $00, $00
    .byte $3C, $7E, $FF, $FF, $FF, $FF, $7E, $3C
    .byte $18, $3C, $7E, $FF, $FF, $7E, $3C, $18
    .byte $00, $18, $3C, $7E, $7E, $3C, $18, $00
    .byte $81, $42, $24, $18, $18, $24, $42, $81

init_f:
    .byte $8C, $80, $84, $80, $8C, $20, $24, $20, $8C, $A0, $A4, $A0, $8C, $40, $44, $40
    .byte $8C, $C0, $C4, $C0, $8C, $50, $54, $50, $8C, $30, $34, $30, $8C, $00, $04, $00
    .byte $8C, $80, $84, $80, $8C, $20, $24, $20, $8C, $A0, $A4, $A0, $8C, $40, $44, $40
    .byte $8C, $C0, $C4, $C0, $8C, $50, $54, $50, $8C, $30, $34, $30, $8C, $00, $04, $00
    .byte $8C, $80, $84, $80, $8C, $20, $24, $20, $8C, $A0, $A4, $A0, $8C, $40, $44, $40
    .byte $8C, $C0, $C4, $C0, $8C, $50, $54, $50, $8C, $30, $34, $30, $8C, $00, $04, $00
    .byte $8C, $80, $84, $80, $8C, $20, $24, $20, $8C, $A0, $A4, $A0, $8C, $40, $44, $40
    .byte $8C, $C0, $C4, $C0, $8C, $50, $54, $50, $8C, $30, $34, $30, $8C, $00, $04, $00
init_b:
    .byte $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07
    .byte $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07
    .byte $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07
    .byte $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07
    .byte $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07
    .byte $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07
    .byte $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07
    .byte $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07, $00, $04, $05, $07
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
