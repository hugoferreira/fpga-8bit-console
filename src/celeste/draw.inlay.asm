; ------------------------------------------------------------------------------
; Celeste - the sprite list, the hair, and the overlay
;
; Three layers, split by what each can express:
;   * tiles     - the room, scrolled by the camera, in the cart's own colours
;   * sprites   - the player, the hair blobs and smoke, staged in SCREEN space
;   * overlay   - 1bpp, above everything, unscrolled: the HUD and the room title
;
; Sprites are screen-space, so every one of them has camera_y subtracted and
; the screen shake added. That split is the reason the shake is applied here
; rather than through the camera registers: the camera moves the tile layer
; only, and shaking the terrain out from under a stationary player would be
; worse than not shaking at all.
; ------------------------------------------------------------------------------
namespace Draw
    export frame
    export sprite
    export object
    export hair_create
    export hair_color
    export hair_draw
    export overlay_init
    export overlay_dirty
    export room_title
    location overlay_pointer : u16 at $16
    location pen_x : u8 at $60
    location pen_y : u8 at $61
    location character : u8 at $62
    location bits : u8 at $63
    location row : u8 at $64
    location count : u8 at $65
    location index : u8 at $66
    location hair_index : u8 at $67
    location hair_color_value : u8 at $68
    location hair_last_x : u16 at $6a
    location hair_last_y : u16 at $6c
    location hair_head_x : u16 at $6e
    location hair_head_y : u16 at $70
    overlay_stride = OverlayFramebuffer.size / 120
    hair_nodes = CelesteObject.payload.hair.hair.count

; ------------------------------------------------------------------------------
; frame: the cart's _draw, minus the effects it has no primitives for.
; ------------------------------------------------------------------------------
frame:
    jsr Draw.palette
    jsr Room.camera
    jsr Draw.overlay_begin

    mov [game.sprite_count], #0
    jsr Room.title              ; the cart draws no clouds on the title screen
    beq .nosky
    jsr Fx.draw_clouds
.nosky:
    lda [game.sprite_count]                    ; everything staged so far is background
    sta [video.split]
    mov [video.repeat], #1  ; player, hair and smoke are single cells

    jsr Objects.draw_all

    jsr Fx.draw_particles       ; in front of everything, title screen included
    lda [game.sprite_count]
    sta [video.sprite_count]
    jmp Draw.overlay_end

; ------------------------------------------------------------------------------
; palette: the cart's start-game flash.
;
;   pal(6,c) pal(12,c) pal(13,c) pal(5,c) pal(1,c) pal(7,c)
;
; is a screen-wide recolour of the six colours the title art is drawn in, and
; the console has exactly that: a 16-entry screen palette at $4020 applied to
; every displayed pixel, overlay included. So this is one of the few places the
; port does what the cart does by the same mechanism rather than an equivalent
; one. Clobbers A, X.
; ------------------------------------------------------------------------------
palette:
    lda [game.start_game]
    beq .ident                  ; not flashing at all

    lda [game.start_game_flash]        ; c = 10, 7, 2, 1 or 0 as the flash decays
    bmi .black                  ; past zero: c = 0
    cmp #11
    bcc .mid
                                ; > 10: white for five frames in every ten.
    cblt [game.frames], #20, .lt20  ; frames is 0..29, so one subtract of 20 and one of 10 is the whole of `frames % 10`
    sub #20
    jmp .lt10
.lt20:
    cmp #10
    bcc .lt10
    sub #10
.lt10:
    cmp #5
    bcc .white
                                ; the cart's c = 10, which is "no pal() call at
                                ; all" - and since it calls pal() every frame,
                                ; that means the IDENTITY palette, not whatever
                                ; the previous frame left behind.
.ident:
    ldx #5
.identloop:
    ldy Draw.palette_slots, x
    tya
    sta [video.screen_palette[y]] ; entry n holds n
    dex
    bpl .identloop
    rts

.white:
    lda #7
    bne .apply
.mid:
    cbge [game.start_game_flash], #6, .two
    cmp #1
    bcs .one
.black:
    lda #0
    beq .apply
.two:
    lda #2
    bne .apply
.one:
    lda #1
.apply:
    ldx #5
.set:
    ldy Draw.palette_slots, x
    sta [video.screen_palette[y]]
    dex
    bpl .set
    rts

; The six colours the cart recolours: pal(6) pal(12) pal(13) pal(5) pal(1) pal(7)
palette_slots:
    #d8 6, 12, 13, 5, 1, 7

; ------------------------------------------------------------------------------
; sprite: A = pattern base, t3 = attributes, t4 = screen x, t5 = screen y.
; Sprites outside the visible band are dropped rather than clamped: SPR_Y is
; seven bits, so a negative y would reappear at the bottom of the screen.
; Horizontally there is nothing to do - the compositor's x is 8-bit and wraps,
; and the clip rectangle already cuts the row at the playfield edge.
; Clobbers A, X, Y.
; ------------------------------------------------------------------------------
sprite:
    ldx [game.sprite_count]
    cpx #128
    bcs .drop
    ldy Machine.t5
    bmi .drop
    cpy #120
    bcs .drop
    stx [video.sprite_index]
    sta [video.sprite_base]
    lda Machine.t4
    sta [video.sprite_x]
    sty [video.sprite_y]
    lda Machine.t3
    sta [video.sprite_flags]               ; the write commits the staged entry
    inc [game.sprite_count]
.drop:
    rts

; ------------------------------------------------------------------------------
; object: the cart's spr(this.spr, this.x, this.y, 1,1, flip.x, flip.y).
;
; The cart's sprite numbers survive in the object's sprite field, so the
; game logic reads the way the Lua does; the translation to a sheet slot is one
; place, here. Two families is all stage 1 has - the player's seven frames and
; smoke's three.
; ------------------------------------------------------------------------------
; ca65 .if -> #assert below: SPR_SMOKE_STRIDE != 1
; "smoke frames are no longer adjacent; object needs a multiply"
;

object:
    mov y, offset CelesteObject.core.sprite
    lda (Machine.object), y
    beq .done                   ; the cart's `elseif obj.spr > 0`
    cmp #29
    bcs .smoke
    tax                         ; the player's frames are no longer a fixed
    lda Gfx.player_slots-1, x    ; stride apart: bpp is chosen per pattern, so
    pha                         ; the generator emits their slots as a table
    lda #Gfx.player_attr
    jmp .flip
.smoke:
    sub #29
    add #Gfx.smoke_first
    pha
    lda #Gfx.smoke_attr
.flip:
    mov y, offset CelesteObject.core.flip
    ora (Machine.object), y
    sta Machine.t3
    jsr Draw.position
    pla
    jmp Draw.sprite
.done:
    rts

; ------------------------------------------------------------------------------
; position: t4/t5 = where the object at pObj lands on screen this frame.
; Clobbers A, Y.
; ------------------------------------------------------------------------------
position:
    lda [Machine.object.core.x]
    add [game.shake_x]
    sta Machine.t4
    lda [Machine.object.core.y]
    sub [game.camera_y]
    add [game.shake_y]
    sta Machine.t5
    rts

; ------------------------------------------------------------------------------
; The hair.
;
; The cart draws five circfill()s that chase the player's neck, and recolours
; them with pal(8,...) to show how many dashes are left. This console has no
; circle primitive, so each node is a 1bpp blob sprite - and because a sprite
; entry carries its own 4-bit palette base, the recolour is free: base 7 paints
; colour 8, base 6 paints 7, base 11 paints 12.
;
; Divergence: the cart chases at (last - h)/1.5 per frame. A 6502 divide by 1.5
; is a multiply by 2/3; here the node moves (d>>1) + (d>>3) = 0.625d instead of
; 0.667d, which is two shifts and an add. The trail is imperceptibly tighter.
; ------------------------------------------------------------------------------
hair_create:
    lda [Machine.object.core.x]
    sta Machine.t3
    lda [Machine.object.core.y]
    sta Machine.t4
    mov y, offset CelesteObject.payload.hair.hair
    ldx #Draw.hair_nodes
.node:
    lda #0
    sta (Machine.object), y
    iny
    lda Machine.t3
    sta (Machine.object), y
    iny
    lda #0
    sta (Machine.object), y
    iny
    lda Machine.t4
    sta (Machine.object), y
    iny
    dex
    bne .node
    rts

; set_hair_color: A = djump, as the cart's set_hair_color(djump). Leaves the
; sprite attribute byte in hair_col.
; The blob is one plane, so its colour is entirely the sprite entry's palette
; base - and which base reaches which colour is now a property of the generated
; draw palette, not of arithmetic. The generator emits the four the cart can
; ask for.
hair_color:
    cmp #1
    beq .red
    cmp #2
    beq .flash
    lda #Gfx.palette_12        ; no dash left: blue
    jmp .done
.red:
    lda #Gfx.palette_8
    jmp .done
.flash:
    ldx [game.frames]                  ; 7 + flr((frames/3)%2)*4, without a divide
    lda Draw.hair_palette, x
.done:
    sta Draw.hair_color_value
    rts

; frames is 0..29 and the cart wants (frames/3) & 1. Thirty bytes is cheaper
; than a division by three, and the table is the specification.
hair_palette:
    #d8 Gfx.palette_7, Gfx.palette_7, Gfx.palette_7
    #d8 Gfx.palette_11, Gfx.palette_11, Gfx.palette_11
    #d8 Gfx.palette_7, Gfx.palette_7, Gfx.palette_7
    #d8 Gfx.palette_11, Gfx.palette_11, Gfx.palette_11
    #d8 Gfx.palette_7, Gfx.palette_7, Gfx.palette_7
    #d8 Gfx.palette_11, Gfx.palette_11, Gfx.palette_11
    #d8 Gfx.palette_7, Gfx.palette_7, Gfx.palette_7
    #d8 Gfx.palette_11, Gfx.palette_11, Gfx.palette_11
    #d8 Gfx.palette_7, Gfx.palette_7, Gfx.palette_7
    #d8 Gfx.palette_11, Gfx.palette_11, Gfx.palette_11

hair_draw:
    lda [Machine.object.core.flip]
    and #1
    beq .faceright
    lda #6
    bne .lastx
.faceright:
    lda #2
.lastx:
    mov y, offset CelesteObject.core.x
    clc
    adc (Machine.object), y
    sta Draw.hair_last_x+1
    mov Draw.hair_last_x, #0

    tbz [game.buttons], #Platform.Input.down, .lastup  ; last.y = y + (btn(down) and 4 or 3)
    lda #4
    bne .lasty
.lastup:
    lda #3
.lasty:
    mov y, offset CelesteObject.core.y
    clc
    adc (Machine.object), y
    sta Draw.hair_last_y+1
    mov Draw.hair_last_y, #$80

    mov Draw.hair_index, #0
    mov Draw.count, #CelesteObject.payload.hair.hair.offset
.node:
    ldy Draw.count                     ; h.x += (last.x - h.x) * 0.625
    jsr Fixed.load_object
    ldab Draw.hair_last_x
    stab Fixed.word1
    jsr Draw.hair_chase
    ldy Draw.count
    jsr Fixed.store_object
    ldab Fixed.word0
    stab Draw.hair_head_x

    lda Draw.count
    add #2
    tay
    jsr Fixed.load_object
    ldab Draw.hair_last_y
    stab Fixed.word1
    jsr Draw.hair_chase
    lda Draw.count
    add #2
    tay
    jsr Fixed.store_object
    ldab Fixed.word0
    stab Draw.hair_head_y

    ldab Draw.hair_head_x  ; this node becomes the next one's target
    stab Draw.hair_last_x
    ldab Draw.hair_head_y
    stab Draw.hair_last_y

    lda Draw.hair_color_value                ; blob size: 2, 2, 1, 1, 1
    sta Machine.t3
    cbge Draw.hair_index, #2, .small
    lda Draw.hair_head_x+1
    sub #2
    sta Machine.t4
    lda Draw.hair_head_y+1
    sub #2
    sta Machine.t5
    lda #Gfx.hair_big
    jmp .plot
.small:
    lda Draw.hair_head_x+1
    sub #1
    sta Machine.t4
    lda Draw.hair_head_y+1
    sub #1
    sta Machine.t5
    lda #Gfx.hair_small
.plot:
    pha
    lda Machine.t4                      ; the hair is in world space like the Draw.object
    add [game.shake_x]
    sta Machine.t4
    lda Machine.t5
    sub [game.camera_y]
    add [game.shake_y]
    sta Machine.t5
    pla
    jsr Draw.sprite

    lda Draw.count
    add #4
    sta Draw.count
    inc Draw.hair_index
    cbeq Draw.hair_index, #Draw.hair_nodes, .done
    jmp .node                   ; the node loop is longer than a branch reaches
.done:
    rts

; hair_chase: w0 += (w1 - w0) * 0.625, as two shifts and an add.
hair_chase:
    ldab Fixed.word1  ; d = target - h
    subw Fixed.word0
    stab Fixed.word2

    ldab Fixed.word2  ; w1 = d >> 1
    stab Fixed.word1
    jsr Draw.asr_w1

    jsr Draw.asr_w2                  ; w2 = d >> 3
    jsr Draw.asr_w2
    jsr Draw.asr_w2

    ldab Fixed.word0
    addw Fixed.word1
    stab Fixed.word0
    ldab Fixed.word0
    addw Fixed.word2
    stab Fixed.word0
    rts

asr_w1:
    lda Fixed.word1+1
    cmp #$80                    ; carry = the sign bit, so the shift is signed
    ror Fixed.word1+1
    ror Fixed.word1
    rts

asr_w2:
    lda Fixed.word2+1
    cmp #$80
    ror Fixed.word2+1
    ror Fixed.word2
    rts

; ------------------------------------------------------------------------------
; The overlay: a 2400-byte shadow, because the hardware bitmap is write-only
; and the text has to be composed before it can be shown. Only rebuilt when
; something in it changed, which for this program is once a second.
; ------------------------------------------------------------------------------
overlay_init:
    address Machine.destination, overlay_shadow.pixels
    ldx #0
.row:
    lda Machine.destination
    sta [overlay_rows.low[x]]
    lda Machine.destination+1
    sta [overlay_rows.high[x]]
    lda Machine.destination
    add #overlay_stride
    sta Machine.destination
    bcc .norow
    inc Machine.destination+1
.norow:
    inx
    cpx #120
    bne .row
    jsr Draw.overlay_clear
    jmp Draw.overlay_dirty

overlay_dirty:
    lda #1
    sta [game.overlay_dirty]
    rts

overlay_clear:
    lda #0
    ldx #0
.page:
    sta [overlay_shadow_pages.page0[x]]
    sta [overlay_shadow_pages.page1[x]]
    sta [overlay_shadow_pages.page2[x]]
    sta [overlay_shadow_pages.page3[x]]
    sta [overlay_shadow_pages.page4[x]]
    sta [overlay_shadow_pages.page5[x]]
    sta [overlay_shadow_pages.page6[x]]
    sta [overlay_shadow_pages.page7[x]]
    sta [overlay_shadow_pages.page8[x]]
    inx
    bne .page
.tail:
    sta [overlay_shadow_pages.page9[x]]
    inx
    cpx #96
    bne .tail
    rts

; overlay_begin: decide whether this frame has to rebuild the overlay, and if so
; clear it and lay down the parts that are not an object's business.
overlay_begin:
    ldx #0                      ; a live room title redraws every frame
.find:
    txa
    jsr Objects.pointer
    lda [Machine.object.core.kind]
    cmp #ObjectKind.title
    beq .yes
    inx
    cpx #Objects.slot_count
    bne .find
    jmp .check
.yes:
    jsr Draw.overlay_dirty
.check:
    lda [game.seconds]                 ; and so does the clock, once a second
    cmp [game.hud_seconds]
    beq .nochange
    sta [game.hud_seconds]
    jsr Draw.overlay_dirty
.nochange:
    lda [game.overlay_dirty]
    beq .done
    jsr Draw.overlay_clear
    jsr Room.title              ; the title screen carries credits, not a HUD
    bne .hud
    jmp Draw.title_credits
.hud:
    jsr Draw.hud
.done:
    rts

overlay_end:
    lda [game.overlay_dirty]
    bne .blit
    rts
.blit:
    mov [game.overlay_dirty], #0
    ldx #0
.page:
    lda [overlay_shadow_pages.page0[x]]
    sta [framebuffer_pages.page0[x]]
    lda [overlay_shadow_pages.page1[x]]
    sta [framebuffer_pages.page1[x]]
    lda [overlay_shadow_pages.page2[x]]
    sta [framebuffer_pages.page2[x]]
    lda [overlay_shadow_pages.page3[x]]
    sta [framebuffer_pages.page3[x]]
    lda [overlay_shadow_pages.page4[x]]
    sta [framebuffer_pages.page4[x]]
    lda [overlay_shadow_pages.page5[x]]
    sta [framebuffer_pages.page5[x]]
    lda [overlay_shadow_pages.page6[x]]
    sta [framebuffer_pages.page6[x]]
    lda [overlay_shadow_pages.page7[x]]
    sta [framebuffer_pages.page7[x]]
    lda [overlay_shadow_pages.page8[x]]
    sta [framebuffer_pages.page8[x]]
    inx
    bne .page
.tail:
    lda [overlay_shadow_pages.page9[x]]
    sta [framebuffer_pages.page9[x]]
    inx
    cpx #96
    bne .tail
    rts

; ------------------------------------------------------------------------------
; Text. A 3x5 font in a 4x6 cell, which is the proportion PICO-8's own font
; has; breakout and nemo both reached the same place for the same reason, which
; is that the sheet's 8x8 font is twice the size a PICO-8 port wants.
;
; Strings are glyph indices rather than ASCII - 0-9 are the digits, 10-35 the
; letters, 36 a colon, 37 a space - so there is no character translation at
; runtime and no font hole to check for.
; ------------------------------------------------------------------------------
    glyph_colon = 36
    glyph_space = 37
    glyph_plus = 38
    glyph_end = $FF

char:
    sta Draw.character
    asl
    asl
    add Draw.character  ; glyph * 5
    tax
    mov Draw.row, #0
.row:
    mov Draw.bits, Draw.font + x
    mov Draw.count, #0
    tbz Draw.pen_x, #7, .placed
    tay
.shift:
    asl Draw.bits
    rol Draw.count
    dey
    bne .shift
.placed:
    lda Draw.pen_y
    add Draw.row
    tay
    lda [overlay_rows.low[y]]
    sta overlay_pointer
    lda [overlay_rows.high[y]]
    sta overlay_pointer+1
    lda Draw.pen_x
    lsr
    lsr
    lsr
    tay
    lda (overlay_pointer), y
    ora Draw.bits
    sta (overlay_pointer), y
    iny
    lda (overlay_pointer), y
    ora Draw.count
    sta (overlay_pointer), y
    inx
    inc Draw.row
    cbne Draw.row, #5, .row
    lda Draw.pen_x
    add #4
    sta Draw.pen_x
    rts

; text: print the glyph string at pSrc, starting at (d_x, d_y).
text:
    ldy #0
.ch:
    lda (Machine.source), y
    cmp #Draw.glyph_end
    beq .done
    sty Draw.index
    jsr Draw.char
    ldy Draw.index
    iny
    bne .ch
.done:
    rts

; string: A/X = string address, then print it.
string:
    sta Machine.source
    stx Machine.source+1
    jmp Draw.text

; byte: print A as two decimal digits.
;
; The units digit is parked in t7, NOT in d_ch: char's first instruction is
; `sta d_ch`, so anything left there is gone by the time the first digit has
; been drawn. That cost a clock reading of 00:00 that every unit test agreed
; with, because the tests read `seconds` and not the pixels.
byte:
    ldx #0
.tens:
    cmp #10
    bcc .units
    sub #10
    inx
    jmp .tens
.units:
    sta Machine.t7
    txa
    jsr Draw.char
    lda Machine.t7
    jmp Draw.char

; ------------------------------------------------------------------------------
; The HUD, in the 32 columns to the right of the 128-wide playfield. The cart
; has no HUD at all - it draws the clock over the room for thirty frames when a
; room starts - so this is the port using space the original did not have.
; ------------------------------------------------------------------------------
hud:
    mov Draw.pen_x, #132
    mov Draw.pen_y, #4
    lda #<Draw.str_time
    ldx #>Draw.str_time
    jsr Draw.string

    mov Draw.pen_x, #130
    mov Draw.pen_y, #11
    lda [game.minutes]
    jsr Draw.byte
    lda #Draw.glyph_colon
    jsr Draw.char
    lda [game.seconds]
    jsr Draw.byte

    mov Draw.pen_x, #132
    mov Draw.pen_y, #22
    lda #<Draw.str_dead
    ldx #>Draw.str_dead
    jsr Draw.string

    mov Draw.pen_x, #138
    mov Draw.pen_y, #29
    lda [game.deaths]
    jmp Draw.byte

; ------------------------------------------------------------------------------
; title_credits: the cart's three prints on the title screen.
;
;   print("x+c",58,80,5) print("matt thorson",42,96,5) print("noel berry",46,102,5)
;
; The cart draws them in colour 5; the overlay has one colour register, so they
; are white here - the same limitation nemo records for its labels. The font is
; 3x5 uppercase, so the names are capitalised.
; ------------------------------------------------------------------------------
title_credits:
    mov Draw.pen_x, #58
    mov Draw.pen_y, #80
    lda #<Draw.str_xc
    ldx #>Draw.str_xc
    jsr Draw.string

    mov Draw.pen_x, #42
    mov Draw.pen_y, #96
    lda #<Draw.str_thorson
    ldx #>Draw.str_thorson
    jsr Draw.string

    mov Draw.pen_x, #46
    mov Draw.pen_y, #102
    lda #<Draw.str_berry
    ldx #>Draw.str_berry
    jmp Draw.string

; ------------------------------------------------------------------------------
; room_title: the cart prints "old site" for room (3,1), "summit" for the
; last room, and (level+1)*100 .. " m" for everything else. The multiply by 100
; is not one: the last two digits are always "00", so only level+1 is printed.
;
; The cart draws a black panel behind the text with rectfill; the overlay has
; one colour and cannot, so the text sits directly over the room.
; ------------------------------------------------------------------------------
room_title:
    cbeq [game.level], #11, .oldsite
    cmp #30
    beq .summit

    mov Draw.pen_x, #52
    mov Draw.pen_y, #62
    lda [game.level]
    add #1
    jsr Draw.byte
    lda #0
    jsr Draw.char
    lda #0
    jsr Draw.char
    lda #Draw.glyph_space
    jsr Draw.char
    lda #22                     ; 'M'
    jmp Draw.char

.oldsite:
    mov Draw.pen_x, #48
    mov Draw.pen_y, #62
    lda #<Draw.str_oldsite
    ldx #>Draw.str_oldsite
    jmp Draw.string

.summit:
    mov Draw.pen_x, #52
    mov Draw.pen_y, #62
    lda #<Draw.str_summit
    ldx #>Draw.str_summit
    jmp Draw.string

str_time:
    #d8 29, 18, 22, 14, Draw.glyph_end            ; TIME
str_dead:
    #d8 13, 14, 10, 13, Draw.glyph_end            ; DEAD
str_oldsite:
    #d8 24, 21, 13, Draw.glyph_space, 28, 18, 29, 14, Draw.glyph_end   ; OLD SITE
str_summit:
    #d8 28, 30, 22, 22, 18, 29, Draw.glyph_end      ; SUMMIT
str_xc:
    #d8 33, 38, 12, Draw.glyph_end               ; X+C
str_thorson:
    #d8 22, 10, 29, 29, Draw.glyph_space, 29, 17, 24, 27, 28, 24, 23, Draw.glyph_end   ; MATT THORSON
str_berry:
    #d8 23, 24, 14, 21, Draw.glyph_space, 11, 14, 27, 27, 34, Draw.glyph_end         ; NOEL BERRY

; ------------------------------------------------------------------------------
; The font: 3 pixels wide in a 4-pixel cell, 5 rows, bit 0 leftmost - which is
; the overlay's own bit order, so a row is a literal picture of itself.
; ------------------------------------------------------------------------------
font:
    #d8 %010, %101, %101, %101, %010      ; 0
    #d8 %010, %011, %010, %010, %111      ; 1
    #d8 %011, %100, %010, %001, %111      ; 2
    #d8 %011, %100, %010, %100, %011      ; 3
    #d8 %101, %101, %111, %100, %100      ; 4
    #d8 %111, %001, %011, %100, %011      ; 5
    #d8 %110, %001, %011, %101, %010      ; 6
    #d8 %111, %100, %010, %010, %010      ; 7
    #d8 %010, %101, %010, %101, %010      ; 8
    #d8 %010, %101, %110, %100, %011      ; 9
    #d8 %010, %101, %111, %101, %101      ; A
    #d8 %011, %101, %011, %101, %011      ; B
    #d8 %110, %001, %001, %001, %110      ; C
    #d8 %011, %101, %101, %101, %011      ; D
    #d8 %111, %001, %011, %001, %111      ; E
    #d8 %111, %001, %011, %001, %001      ; F
    #d8 %110, %001, %101, %101, %110      ; G
    #d8 %101, %101, %111, %101, %101      ; H
    #d8 %111, %010, %010, %010, %111      ; I
    #d8 %100, %100, %100, %101, %010      ; J
    #d8 %101, %101, %011, %101, %101      ; K
    #d8 %001, %001, %001, %001, %111      ; L
    #d8 %101, %111, %111, %101, %101      ; M
    #d8 %011, %101, %101, %101, %101      ; N
    #d8 %010, %101, %101, %101, %010      ; O
    #d8 %011, %101, %011, %001, %001      ; P
    #d8 %010, %101, %101, %011, %110      ; Q
    #d8 %011, %101, %011, %101, %101      ; R
    #d8 %110, %001, %010, %100, %011      ; S
    #d8 %111, %010, %010, %010, %010      ; T
    #d8 %101, %101, %101, %101, %010      ; U
    #d8 %101, %101, %101, %010, %010      ; V
    #d8 %101, %101, %111, %111, %101      ; W
    #d8 %101, %101, %010, %101, %101      ; X
    #d8 %101, %101, %010, %010, %010      ; Y
    #d8 %111, %100, %010, %001, %111      ; Z
    #d8 %000, %010, %000, %010, %000      ; :
    #d8 %000, %000, %000, %000, %000      ; space
    #d8 %000, %010, %111, %010, %000      ; +
end
