; Pseudo-instructions: the ISA we intend, expressed before the silicon exists.
;
; Every rule here expands, via customasm's `asm { }` blocks, into instructions
; the hardware already has. Writing `cbeq state, #ST_PLAY, .go` today emits the
; same six bytes `lda state / cmp #ST_PLAY / beq .go` always did. When
; add-isa-test-and-branch lands, one line in this file changes to the real
; opcode and the corpus does not change at all.
;
; WHY THIS FILE EXISTS
;
; The word ops were built the other way round: decode rows, RTL, tests, and
; only then a migration tool that found 6 sites in breakout and 12 in celeste -
; 36 and 58 bytes. That is a fine result for the effort, but nobody knew it was
; the result until the hardware was finished. A pseudo-op layer moves that
; measurement in front of the silicon: adopt the instruction in source, count
; the sites, project the saving from the proposed encoding, and only then
; decide whether it earns a decode row and its share of Fmax.
;
; It also makes the adoption itself provable. Because each expansion is exactly
; the byte sequence it replaces, migrating a corpus onto these rules must leave
; the binary BIT-IDENTICAL. That is a stronger check than any differential -
; `make pseudo-check` asserts it - and it needs no liveness analysis, because
; nothing about the emitted code has changed.
;
; THE CONTRACT, WHICH IS THE WHOLE POINT
;
; A pseudo-op and its eventual hardware form are NOT interchangeable in
; general. The contract each rule documents is the WEAKEST behaviour of the
; two, so code written against it is correct under either:
;
;   - the expansion below clobbers A and the N/Z/C flags;
;   - the hardware form is specified to preserve A, X, Y and every flag.
;
; The contract therefore says "clobbers A and the flags". Hardware that
; preserves more than promised is a refinement and breaks nothing. Code must
; never rely on the hardware's extra guarantee until the hardware is real -
; and when it is, that extra guarantee is what a LATER pass gets to exploit.
;
; Where neither implementation refines the other, the contract says so
; explicitly. `addw16` below is the example: the byte-pair expansion sets Z
; from the high half and the AB hardware sets it from both halves, so the
; contract can only promise that Z is undefined.

; ---------------------------------------------------------------------------
; add-isa-test-and-branch (PROPOSED - openspec/changes/add-isa-test-and-branch)
;
; Contract for every rule in this block:
;   reads    the named zero-page location
;   clobbers A, N, Z, C
;   preserves X, Y, V, and memory
;
; Projected hardware encoding: 4 bytes / 5-6 cycles against the 6 bytes /
; 8 cycles emitted here. tools/65x02/pseudo.txt carries those numbers so the
; projection can be scored without reading this comment.
; ---------------------------------------------------------------------------
#ruledef pseudo_testbranch
{
    ; compare a variable against a constant and branch      -> CBEQ/CBNE/CBLT/CBGE
    cbeq {v: u8}, #{k: u8}, {t: u16} => asm { lda {v}
                                              cmp #{k}
                                              beq {t} }
    cbne {v: u8}, #{k: u8}, {t: u16} => asm { lda {v}
                                              cmp #{k}
                                              bne {t} }
    cblt {v: u8}, #{k: u8}, {t: u16} => asm { lda {v}
                                              cmp #{k}
                                              bcc {t} }
    cbge {v: u8}, #{k: u8}, {t: u16} => asm { lda {v}
                                              cmp #{k}
                                              bcs {t} }

    ; test a bit mask and branch                                   -> TBZ/TBNZ
    tbz  {v: u8}, #{m: u8}, {t: u16} => asm { lda {v}
                                              and #{m}
                                              beq {t} }
    tbnz {v: u8}, #{m: u8}, {t: u16} => asm { lda {v}
                                              and #{m}
                                              bne {t} }
}

; The low/high-byte immediate forms, matching cpu6502_immediate_lohi in
; nmos6502.asm and ext_core_immediate_lohi in ext_core.asm. `cbne w0,
; #<SPDY_EPSILON, .slide` is how celeste compares against the half of a 16-bit
; constant, and without these rules the corpus simply does not assemble.
#ruledef pseudo_testbranch_lohi
{
    cbeq {v: u8}, #<{k: u16}, {t: u16} => {
        kk = k[7:0]
        asm { lda {v}
              cmp #{kk}
              beq {t} }
    }
    cbeq {v: u8}, #>{k: u16}, {t: u16} => {
        kk = k[15:8]
        asm { lda {v}
              cmp #{kk}
              beq {t} }
    }
    cbne {v: u8}, #<{k: u16}, {t: u16} => {
        kk = k[7:0]
        asm { lda {v}
              cmp #{kk}
              bne {t} }
    }
    cbne {v: u8}, #>{k: u16}, {t: u16} => {
        kk = k[15:8]
        asm { lda {v}
              cmp #{kk}
              bne {t} }
    }
    cblt {v: u8}, #<{k: u16}, {t: u16} => {
        kk = k[7:0]
        asm { lda {v}
              cmp #{kk}
              bcc {t} }
    }
    cblt {v: u8}, #>{k: u16}, {t: u16} => {
        kk = k[15:8]
        asm { lda {v}
              cmp #{kk}
              bcc {t} }
    }
    cbge {v: u8}, #<{k: u16}, {t: u16} => {
        kk = k[7:0]
        asm { lda {v}
              cmp #{kk}
              bcs {t} }
    }
    cbge {v: u8}, #>{k: u16}, {t: u16} => {
        kk = k[15:8]
        asm { lda {v}
              cmp #{kk}
              bcs {t} }
    }
    tbz {v: u8}, #<{k: u16}, {t: u16} => {
        kk = k[7:0]
        asm { lda {v}
              and #{kk}
              beq {t} }
    }
    tbz {v: u8}, #>{k: u16}, {t: u16} => {
        kk = k[15:8]
        asm { lda {v}
              and #{kk}
              beq {t} }
    }
    tbnz {v: u8}, #<{k: u16}, {t: u16} => {
        kk = k[7:0]
        asm { lda {v}
              and #{kk}
              bne {t} }
    }
    tbnz {v: u8}, #>{k: u16}, {t: u16} => {
        kk = k[15:8]
        asm { lda {v}
              and #{kk}
              bne {t} }
    }
}

; ---------------------------------------------------------------------------
; The zero test, split out because it is a DIFFERENT trade.
;
; `lda v / beq t` is already 4 bytes, and the proposed `CBEQ zp, #0, rel` is
; also 4. So this buys no space at all - only the accumulator and a cycle. It
; is kept separate so the measurement does not quietly credit the slice with a
; saving it does not make: 46 sites in breakout at zero bytes each.
; ---------------------------------------------------------------------------
#ruledef pseudo_testzero
{
    bzero  {v: u8}, {t: u16} => asm { lda {v}
                                      beq {t} }
    bnzero {v: u8}, {t: u16} => asm { lda {v}
                                      bne {t} }
}

; ---------------------------------------------------------------------------
; add-isa-word-ops, in its pre-hardware form. Not used by the corpus, which is
; already on the real instructions - it is here as the worked example of a
; contract where neither side refines the other.
;
; Contract:
;   clobbers A (high half of the result), B, N, C, V
;   Z IS UNDEFINED - the expansion sets it from the high half, the AB hardware
;                    from both halves. Verified: 0x0010 + 0x0002 leaves Z=1
;                    under the expansion and Z=0 under ADDW.
; ---------------------------------------------------------------------------
#ruledef pseudo_word
{
    addw16 {dst: u8}, {src: u8} => {
        dsthi = dst + 1
        srchi = src + 1
        asm { lda {dst}
              clc
              adc {src}
              sta {dst}
              lda {dsthi}
              adc {srchi}
              sta {dsthi} }
    }
}
