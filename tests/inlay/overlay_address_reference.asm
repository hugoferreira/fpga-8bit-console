; Independent oracle for fixed-overlay address materialization.
;
; Each `address DEST, overlay.field` must lower to a low/high `mov` immediate
; pair writing the absolute overlay base + field displacement into the
; destination pointer, clobbering no registers. The immediates below are the
; resolved bytes: tile_map is $f000 (patterns +0, attributes +512 = $f200) and
; header is $8000 (flags +17 = $8011).

#include "../../src/isa/nmos6502.asm"
#include "../../src/isa/ext_core.asm"
#include "../../src/isa/pseudo.asm"

#bankdef overlay_address { #addr 0x0400, #size 0x0100, #outp 0 }
#bank overlay_address

start:
    mov $1a, #$00
    mov $1b, #$f0
    mov $1a, #$00
    mov $1b, #$f2
    mov $10, #$11
    mov $11, #$80
; Fixed-overlay byte updates: inc/dec are native single-instruction RMW that
; clobber no register; and/ora need the accumulator. game is $0030 (frames +0,
; flags +9 = $0039).
    inc $30
    dec $30
    lda $39
    and #$fe
    sta $39
    lda $39
    ora #$01
    sta $39
; Fixed-overlay accumulator compare against volatile MMIO: video is $4000
; (HeaderView.flags +17 = $4011); cmp reads memory and sets flags only.
    cmp $4011
; Page-view indexed access: each 256-byte page is reached by absolute indexed
; addressing with no hidden scratch. framebuffer is $e000, so page0 is $e000
; and page9 (offset 2304) is $e900; Y selects the byte within the page.
    lda $e000, y
    sta $e900, y
; Register loads/stores, accumulator logic and arithmetic against fixed overlay
; fields: game is $0030 (frames +0, flags +9 = $0039).
    stx $30
    sty $30
    ldx $30
    ldy $30
    and $39
    ora $39
    add $39
    sub $39
    mov $30, #7
; X-indexed absolute access and indexed carry arithmetic through a page array.
    sta $e000, x
    adc $e000, x
    sbc $e000, x
; Compare/test-and-branch pseudo-ops keep the same expansion as the raw form.
spin:
    cblt $30, #5, spin
    tbz $39, #1, spin
    rts
