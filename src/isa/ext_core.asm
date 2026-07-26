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
