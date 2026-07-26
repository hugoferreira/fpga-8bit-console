; add-isa-core-ergonomics: the accumulator toll booth and the carry ceremony.
;
; Column $x3 low half, per the allocation policy in docs/opcodes.md. Every
; instruction here satisfies the purity rules: no preconditions, and none
; clobbers a register that is not its own result.
;
;   MOV   writes memory from an immediate or an indexed table read, touching
;         no register and no flag at all. That is the point: `lda #k / sta v`
;         costs A, and A is the scarcest thing on this machine.
;   ADD   ADC with the carry forced to 0; SUB is SBC with the borrow forced.
;         Binary only - these are for addresses and counters, where a decimal
;         adjust is never wanted. ADC/SBC keep decimal for the BCD score.
;   TRAP  raises the diagnostic trap with an immediate tag and continues.
;
; Cycle counts are this core's, not NMOS's; see docs/opcodes.md.

#ruledef ext_core
{
    ; --- MOV: memory written without passing through A -----------------
    ; 3 bytes / 4 cycles, replacing `lda #k / sta zp`   (4 bytes / 5 cycles)
    mov <{zaddr: u8}, #{imm: i8}  => 0x03 @ zaddr @ imm
    mov  {zaddr: u8}, #{imm: i8}  => 0x03 @ zaddr @ imm

    ; 4 bytes / 5 cycles, replacing `lda #k / sta abs` (5 bytes / 6 cycles)
    mov  {addr: u16}, #{imm: i8}  => 0x13 @ $le(addr) @ imm

    ; 4 bytes / 6 cycles, replacing `lda abs,x / sta zp` (5 bytes / 7 cycles)
    ;
    ; Written `mov dst, table + x` rather than `mov dst, table, x`: with a
    ; two-operand mnemonic a third comma reads as a third operand, and the
    ; index is not one - it is part of the source address. customasm treats
    ; `+ x` as a syntactic marker here, not an expression, so `table + x`
    ; assembles to the indexed opcode and not to an addition.
    mov <{zaddr: u8}, {addr: u16} + x => 0x23 @ zaddr @ $le(addr)
    mov  {zaddr: u8}, {addr: u16} + x => 0x23 @ zaddr @ $le(addr)

    ; --- ADD / SUB: the carry is in the opcode, not in a preceding clc --
    add #{imm:  i8} => 0x33 @ imm      ; 2/2, replacing clc/adc #k  (3/4)
    add <{zaddr: u8} => 0x43 @ zaddr   ; 2/3, replacing clc/adc zp  (3/5)
    add  {zaddr: u8} => 0x43 @ zaddr
    sub #{imm:  i8} => 0x53 @ imm      ; 2/2, replacing sec/sbc #k  (3/4)
    sub <{zaddr: u8} => 0x63 @ zaddr   ; 2/3, replacing sec/sbc zp  (3/5)
    sub  {zaddr: u8} => 0x63 @ zaddr

    ; --- TRAP: a named failure instead of silent corruption ------------
    trap #{imm: u8} => 0x73 @ imm
}

; The low/high-byte immediate forms, matching cpu6502_immediate_lohi in
; nmos6502.asm. `mov ptr, #<table` is how a pointer gets initialised, and it is
; the single most common MOV site in the corpus.
#ruledef ext_core_immediate_lohi
{
    mov <{zaddr: u8}, #<{v: u16} => 0x03 @ zaddr @ v[7:0]
    mov <{zaddr: u8}, #>{v: u16} => 0x03 @ zaddr @ v[15:8]
    mov  {zaddr: u8}, #<{v: u16} => 0x03 @ zaddr @ v[7:0]
    mov  {zaddr: u8}, #>{v: u16} => 0x03 @ zaddr @ v[15:8]
    mov  {addr: u16}, #<{v: u16} => 0x13 @ $le(addr) @ v[7:0]
    mov  {addr: u16}, #>{v: u16} => 0x13 @ $le(addr) @ v[15:8]

    add #<{v: u16} => 0x33 @ v[7:0]
    add #>{v: u16} => 0x33 @ v[15:8]
    sub #<{v: u16} => 0x53 @ v[7:0]
    sub #>{v: u16} => 0x53 @ v[15:8]
}

; add-isa-pointer-ops: `obj.field` without spending Y on the field offset.
;
; `ldy #O_Y / lda (pObj), y` is what a Lua table access costs on a 6502 - two
; instructions, one of them purely to name the field. 239 of the 252 pointer
; accesses across breakout and celeste are a load or a store through that
; idiom, and 156 of them go through a single pointer. Written `(ptr), #disp`
; because the displacement is part of the address, not a separate operand.
#ruledef ext_ptr
{
    ; 3 bytes / 6 cycles, replacing `ldy #d / lda (zp),y`  (4 bytes / 7 cycles)
    lda ({zaddr: u8}), #{disp: u8} => 0x8B @ zaddr @ disp
    sta ({zaddr: u8}), #{disp: u8} => 0x9B @ zaddr @ disp
}

; add-isa-word-ops: AB, a 16-bit accumulator.
;
; A is the high byte and B the low. A is the high byte because the corpus reads
; a high half alone 192 times across 33 distinct 16-bit variables - the integer
; part of an 8.8 value - and every existing 8-bit instruction already operates
; on A. So after `ldab ballx`, `sta screenx` stores the integer part with no
; transfer, and the fractional half sits in B where nothing else disturbs it.
;
; Memory operands are little-endian pairs, matching how the corpus already
; stores 16-bit values: `ldab foo` reads foo as the low byte and foo+1 as high.
;
; The replaced sequence, hand-written today, is
;   lda foo / add bar / sta foo / lda foo+1 / adc bar+1 / sta foo+1
; at 12 bytes and 18 cycles. `ldab foo / addw bar / stab foo` is 6 and 12.
#ruledef ext_word
{
    ldab <{zaddr: u8}      => 0x83 @ zaddr        ; 2 bytes / 4 cycles
    ldab  {zaddr: u8}      => 0x83 @ zaddr
    stab <{zaddr: u8}      => 0x93 @ zaddr        ; 2 / 4
    stab  {zaddr: u8}      => 0x93 @ zaddr
    ldab #{v: i32}         => 0xA3 @ v[7:0] @ v[15:8]   ; 3 / 3
    addw <{zaddr: u8}      => 0xB3 @ zaddr        ; 2 / 4
    addw  {zaddr: u8}      => 0xB3 @ zaddr
    subw <{zaddr: u8}      => 0xC3 @ zaddr        ; 2 / 4
    subw  {zaddr: u8}      => 0xC3 @ zaddr
    cmpw <{zaddr: u8}      => 0xD3 @ zaddr        ; 2 / 4
    cmpw  {zaddr: u8}      => 0xD3 @ zaddr
    addw #{v: i32}         => 0xE3 @ v[7:0] @ v[15:8]   ; 3 / 3
    subw #{v: i32}         => 0xF3 @ v[7:0] @ v[15:8]   ; 3 / 3
}
