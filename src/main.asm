.segment "CODE"
    ; ------------------------------------------------------------------------------
    ; System Memory Map
    ; ------------------------------------------------------------------------------
    ; $0000-$00FF: Zero Page (CPU registers and variables)
    ; $0100-$01FF: Stack Page (Hardware stack grows down from $01FF)
    ; $0200-$02FF: Reserved for system use
    ; $0300-$FFFA: Program code and data
    ; $FFFA-$FFFF: Interrupt vectors (NMI, RESET, IRQ/BRK)
    
    ; ------------------------------------------------------------------------------
    ; System Constants
    ; ------------------------------------------------------------------------------
    
    ; Screen Resolution Constants
    .define SCREEN_WIDTH       160    ; LCD width in pixels (320 / SCALE)
    .define SCREEN_HEIGHT      120    ; LCD height in pixels (240 / SCALE)
    .define SCALE              2      ; Scale factor for the screen
    
    ; Sprite Constants
    .define SPRITE_WIDTH       8      ; Sprite width in pixels
    .define SPRITE_HEIGHT      8      ; Sprite height in pixels
    .define SPRITE_X_REG       $4008  ; Sprite X position register
    .define SPRITE_Y_REG       $4009  ; Sprite Y position register
    
    ; Screen Boundaries
    .define LEFT_BOUNDARY      20     ; Left boundary for sprite bouncing
    .define RIGHT_BOUNDARY     132    ; Right boundary (160 - 8 - 20)
    .define TOP_BOUNDARY       20     ; Top boundary for sprite bouncing
    .define BOTTOM_BOUNDARY    92     ; Bottom boundary (120 - 8 - 20)
    
    ; Text Buffer Constants
    .define TEXT_COLUMNS       20     ; Number of text columns
    .define TEXT_ROWS          15     ; Number of text rows
    .define CHAR_RAM           $F000  ; Character data in text buffer
    .define ATTR_RAM           $F200  ; Attribute (color) data in text buffer
    
    ; Movement Constants
    .define X_STEP             1      ; Horizontal movement step size
    .define Y_STEP             1      ; Vertical movement step size
    
    ; Color Constants (BBBBFFFF format - background/foreground)
    .define COLOR_WHITE_ON_BLUE $1F   ; Blue background (1), white foreground (F)
    .define COLOR_WHITE_ON_BLACK $0F  ; Black background (0), white foreground (F)
    .define COLOR_GREEN_ON_BLACK $0A  ; Black background (0), green foreground (A)
    .define COLOR_RED_ON_BLACK   $0C  ; Black background (0), red foreground (C)
    
    ; Direction Constants
    .define DIR_RIGHT          0      ; Moving right
    .define DIR_LEFT           1      ; Moving left
    .define DIR_DOWN           0      ; Moving down
    .define DIR_UP             1      ; Moving up
    
    ; Zero page variables
    .define x_pos   $00     ; Current X position
    .define y_pos   $01     ; Current Y position
    .define x_dir   $02     ; X direction (0=right, 1=left)
    .define y_dir   $03     ; Y direction (0=down, 1=up)
    
; Program starts here at $0300 (see memory.cfg)    
start:
    ; Write "CPU RUNNING" to screen to verify the CPU is running
    lda #'C'
    sta CHAR_RAM+5      ; Character at position 5
    lda #'P'
    sta CHAR_RAM+6      ; Character at position 6
    lda #'U'
    sta CHAR_RAM+7      ; Character at position 7
    lda #' '
    sta CHAR_RAM+8      ; Character at position 8
    lda #'R'
    sta CHAR_RAM+9      ; Character at position 9
    lda #'U'
    sta CHAR_RAM+10     ; Character at position 10
    lda #'N'
    sta CHAR_RAM+11     ; Character at position 11
    
    ; Write welcome message to screen with proper attributes
    lda #'B'
    sta CHAR_RAM      ; Character at position 0
    lda #'A'
    sta CHAR_RAM+1    ; Character at position 1
    lda #'L'
    sta CHAR_RAM+2    ; Character at position 2
    lda #'L'
    sta CHAR_RAM+3    ; Character at position 3
    
    ; Set attributes for the text (white on blue)
    lda #COLOR_WHITE_ON_BLUE
    sta ATTR_RAM      ; Attribute for position 0
    sta ATTR_RAM+1    ; Attribute for position 1
    sta ATTR_RAM+2    ; Attribute for position 2
    sta ATTR_RAM+3    ; Attribute for position 3
    
    ; Initialize sprite position to middle of screen
    lda #80          ; Center X position
    sta x_pos
    sta SPRITE_X_REG
    
    lda #60          ; Center Y position
    sta y_pos
    sta SPRITE_Y_REG
    
    ; Initialize to move down-right
    lda #DIR_RIGHT
    sta x_dir
    lda #DIR_DOWN
    sta y_dir

    ; Add a marker in RAM to verify CPU is running
    lda #$DE
    sta $F10          ; Store marker at $F10
    lda #$AD
    sta $F11          ; Store marker at $F11

main_loop:
    ; Update the counter on screen to show program is running
    inc $F12
    lda $F12
    sta CHAR_RAM+20   ; Show counter on screen
    lda #COLOR_WHITE_ON_BLACK
    sta ATTR_RAM+20   ; Set attribute for counter

    ; === Simple X movement ===
    lda x_dir
    beq move_right
    
move_left:
    lda x_pos
    sec
    sbc #X_STEP       ; Move left by X_STEP pixels
    sta x_pos
    cmp #LEFT_BOUNDARY
    bcs x_done
    lda #DIR_RIGHT    ; Change direction to right
    sta x_dir
    jmp x_done
    
move_right:
    lda x_pos
    clc
    adc #X_STEP       ; Move right by X_STEP pixels
    sta x_pos
    cmp #RIGHT_BOUNDARY
    bcc x_done
    lda #DIR_LEFT     ; Change direction to left
    sta x_dir
    
x_done:
    ; === Simple Y movement ===
    lda y_dir
    beq move_down
    
move_up:
    lda y_pos
    sec
    sbc #Y_STEP       ; Move up by Y_STEP pixels
    sta y_pos
    cmp #TOP_BOUNDARY
    bcs y_done
    lda #DIR_DOWN     ; Change direction to down
    sta y_dir
    jmp y_done
    
move_down:
    lda y_pos
    clc
    adc #Y_STEP       ; Move down by Y_STEP pixels
    sta y_pos
    cmp #BOTTOM_BOUNDARY
    bcc y_done
    lda #DIR_UP       ; Change direction to up
    sta y_dir
    
y_done:
    ; Display "X=" and current position
    lda #'X'
    sta CHAR_RAM+40   ; Character at position 40
    lda #'='
    sta CHAR_RAM+41   ; Character at position 41
    
    ; Convert X position to ASCII numeral
    lda x_pos
    jsr byte_to_hex
    sta CHAR_RAM+42    ; Store high nibble at position 42
    stx CHAR_RAM+43    ; Store low nibble at position 43
    
    ; Set attributes for X position (green on black)
    lda #COLOR_GREEN_ON_BLACK
    sta ATTR_RAM+40
    sta ATTR_RAM+41
    sta ATTR_RAM+42
    sta ATTR_RAM+43
    
    ; Display "Y=" and current position
    lda #'Y'
    sta CHAR_RAM+45    ; Character at position 45
    lda #'='
    sta CHAR_RAM+46    ; Character at position 46
    
    ; Convert Y position to ASCII numeral
    lda y_pos
    jsr byte_to_hex
    sta CHAR_RAM+47    ; Store high nibble at position 47
    stx CHAR_RAM+48    ; Store low nibble at position 48
    
    ; Set attributes for Y position (red on black)
    lda #COLOR_RED_ON_BLACK
    sta ATTR_RAM+45
    sta ATTR_RAM+46
    sta ATTR_RAM+47
    sta ATTR_RAM+48
    
    ; Update sprite position in hardware
    lda x_pos
    sta SPRITE_X_REG   ; Update X position
    
    lda y_pos
    sta SPRITE_Y_REG   ; Update Y position
    
    ; Add delay to control speed
    ldx #$20           ; Reasonable delay for testing
delay:
    ldy #$20
inner_delay:
    dey
    bne inner_delay
    dex
    bne delay
    
    jmp main_loop      ; Repeat forever

; ------------------------------------------------------------------------------
; Utility subroutines
; ------------------------------------------------------------------------------

; Convert byte in A to two hex digits
; Returns: A = high nibble as hex char, X = low nibble as hex char
byte_to_hex:
    pha                  ; Save original value
    lsr                  ; Shift high nibble to low nibble
    lsr
    lsr
    lsr
    jsr nibble_to_hex    ; Convert high nibble
    pha                  ; Save high nibble ASCII
    pla                  ; Restore high nibble ASCII to A
    tax                  ; Save high nibble ASCII to X temporarily
    pla                  ; Restore original value
    and #$0F             ; Mask to keep only low nibble
    jsr nibble_to_hex    ; Convert low nibble
    pha                  ; Save low nibble ASCII
    txa                  ; Restore high nibble ASCII to A
    tax                  ; And store it in X
    pla                  ; Restore low nibble ASCII to A
    rts

; Convert nibble in A to hex digit
; Returns: A = hex character ('0'-'9', 'A'-'F')
nibble_to_hex:
    cmp #10              ; Check if 0-9 or A-F
    bcc @digit           ; If < 10, skip to digit
    adc #('A' - '0' - 10 - 1) ; Convert to A-F (carry is set)
@digit:
    adc #'0'             ; Convert to '0'-'9'
    rts

; ------------------------------------------------------------------------------
; Interrupt vectors
; ------------------------------------------------------------------------------
.segment "VECTORS"
    .word $0000          ; NMI vector (unused)
    .word start          ; Reset vector - points to the start of our program
    .word $0000          ; IRQ/BRK vector (unused) 