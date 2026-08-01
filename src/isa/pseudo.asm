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
; Counted accumulator shifts and rotates (redesign-celeste-for-inlay task 10.9)
;
; `asl a, 3` is exactly three accumulator `asl` instructions: same bytes, same
; carry chain, same final flags. This buys NO bytes at all - it is a source
; legibility slice, and `make pseudo-check` asserts the ROM is bit-identical
; across the migration. The measurement must not credit it with a saving.
;
; Contract: identical to repeating the instruction N times. Rotates feed each
; repetition's carry output into the next. Accepted range is 1..8.
;
; WHY THE SPELLING IS `asl a, N` AND NOT `asl N`
;
; Because `asl N` is not implementable here - it SILENTLY MISCOMPILES.
; `asl {zaddr: u8}` in nmos6502.asm already matches a bare expression, so
; `asl 3` matches both it and any counted rule. customasm 0.14.1 resolves that
; by preferring the SMALLER encoding without warning: with a 3-repetition rule
; in scope, `asl 3` assembles to `06 03` - a read-modify-write of zero page
; address 3 - not to three shifts. Verified against customasm v0.14.1. The
; explicit `a` operand is what makes the counted form unambiguous, and it
; matches the `asl a` accumulator spelling nmos6502.asm already carries.
;
; WHY THE COUNTS ARE WRITTEN OUT ONE BY ONE
;
; The compact encoding `0x0a0a0a0a0a0a0a0a`64[8 * n - 1 : 0]` works for 1..8
; but ZERO-EXTENDS above it: `asl a, 9` emits `00` (BRK) followed by eight
; shifts, silently. Enumerating the counts makes the accepted range structural
; - an out-of-range count matches no rule and fails to assemble - instead of
; depending on a slice bound that degrades quietly.
; ---------------------------------------------------------------------------
#ruledef pseudo_counted_shift
{
    asl a, 1 => 0x0a
    asl a, 2 => 0x0a @ 0x0a
    asl a, 3 => 0x0a @ 0x0a @ 0x0a
    asl a, 4 => 0x0a @ 0x0a @ 0x0a @ 0x0a
    asl a, 5 => 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a
    asl a, 6 => 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a
    asl a, 7 => 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a
    asl a, 8 => 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a @ 0x0a

    lsr a, 1 => 0x4a
    lsr a, 2 => 0x4a @ 0x4a
    lsr a, 3 => 0x4a @ 0x4a @ 0x4a
    lsr a, 4 => 0x4a @ 0x4a @ 0x4a @ 0x4a
    lsr a, 5 => 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a
    lsr a, 6 => 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a
    lsr a, 7 => 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a
    lsr a, 8 => 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a @ 0x4a

    rol a, 1 => 0x2a
    rol a, 2 => 0x2a @ 0x2a
    rol a, 3 => 0x2a @ 0x2a @ 0x2a
    rol a, 4 => 0x2a @ 0x2a @ 0x2a @ 0x2a
    rol a, 5 => 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a
    rol a, 6 => 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a
    rol a, 7 => 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a
    rol a, 8 => 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a @ 0x2a

    ror a, 1 => 0x6a
    ror a, 2 => 0x6a @ 0x6a
    ror a, 3 => 0x6a @ 0x6a @ 0x6a
    ror a, 4 => 0x6a @ 0x6a @ 0x6a @ 0x6a
    ror a, 5 => 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a
    ror a, 6 => 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a
    ror a, 7 => 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a
    ror a, 8 => 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a @ 0x6a
}

; ---------------------------------------------------------------------------
; add-isa-width-suffixes: operand width as a mnemonic suffix.
;
; A bare mnemonic is the 8-bit form and a trailing `w` is the little-endian
; zero-page pair, matching `addw`/`subw`/`cmpw` - the spelling this ISA already
; uses for width. Nothing existing moves.
;
; WHY NOT `asr.b` / `asr.w`, WHICH IS WHERE THIS STARTED
;
; The m68k dotted form assembles perfectly well in raw customasm. It cannot be
; used here because `.` is the Inlay frontend's MEMBER SEPARATOR - the same dot
; in `Fixed.word1` and `CelesteObject.core` - so at statement position a dotted
; mnemonic is lexically indistinguishable from a qualified name. Inlay resolves
; `asr.w Fixed.word1` as a namespace reference and emits
; `__inlay_q3_asr1_w __inlay_q5_Fixed5_word1`, which then fails to assemble.
; Teaching the frontend to except a mnemonic whitelist would make `.` mean one
; thing at statement start and another everywhere else - positional ambiguity,
; which is exactly the failure the counted-shift block above exists to avoid.
;
; The suffix is still a distinct token, so it cannot collide with an addressing
; mode the way `asl N` collides with `asl {zaddr: u8}`.
;
; The convention governs THIS FILE only. `addw`/`subw`/`cmpw`/`ldab`/`stab` are
; decode rows in rtl/cpu6502_decode.sv and keep the spelling the hardware uses.
;
; Arithmetic shift right is the operation that earned the axis. The 6502 has no
; ASR, so all three corpora open-code one; counted as a single instruction with
; two widths it occurs 9 times across celeste and breakout, which clears gate
; G3. Counted as two instructions, 7 and 2, both would fail it.
;
; CONTRACTS - and the two widths do NOT get the same one.
;
;   asr     EXACT. `cmp #$80` puts the sign in C and `ror` rotates it back into
;           bit 7. N is the preserved sign, Z is set when the result is zero, C
;           is the bit shifted out, V is untouched - precisely what a hardware
;           `ASR A` would leave, so neither form refines the other. Verified
;           over all 256 accumulator values x both carries x both overflows.
;           Clobbers A, which is the result.
;
;   asrw    WEAKER THAN ITS HARDWARE FORM, like addw16 below.
;             clobbers A - it must load the high byte to test the sign, where
;                          hardware would preserve A under purity rule P2;
;             Z AND N ARE UNDEFINED - the expansion leaves them from the LOW
;                          byte, the last `ror` executed, while hardware would
;                          set them from the 16-bit result.
;           Do not branch on the result of asrw without re-testing it.
; ---------------------------------------------------------------------------
#ruledef pseudo_width
{
    ; signed halve, accumulator                                          -> ASR
    asr => asm { cmp #$80
                   ror }

    ; and the counted form, composing with the counted-shift block above
    asr a, 1 => asm { cmp #$80
                        ror }
    asr a, 2 => asm { cmp #$80
                        ror
                        cmp #$80
                        ror }
    asr a, 3 => asm { cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror }
    asr a, 4 => asm { cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror }
    asr a, 5 => asm { cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror }
    asr a, 6 => asm { cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror }
    asr a, 7 => asm { cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror }
    asr a, 8 => asm { cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror
                        cmp #$80
                        ror }

    ; signed halve, zero-page pair                                     -> ASR.W
    asrw {loc: u8} => {
        hi = loc + 1
        asm { lda {hi}
              cmp #$80
              ror {hi}
              ror {loc} }
    }
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
