.segment "CODE"
    ; Simple test program that:
    ; 1. Reads from I/O address $4000
    ; 2. Decrements the value
    ; 3. Stores it back to $4000
    ; 4. Also stores to RAM at $F8EF
    ; 5. Adds a delay loop
    ; 6. Jumps back to start

start:
    nop             ; Padding
    nop             ; Padding
    nop             ; Padding
    
    lda $4000       ; Load from I/O
    sbc #$01        ; Subtract 1
    sta $4000       ; Store back to I/O
    sta $F8EF       ; Store to RAM
    
    ldy #$FF        ; Load Y with 255 for delay
delay:
    dey             ; Decrement Y
    bne delay       ; Loop until Y is 0
    
    jmp start       ; Jump back to start

    ; Fill rest of RAM with zeros
    .res $F00, $00  ; Fill up to 4KB with zeros 