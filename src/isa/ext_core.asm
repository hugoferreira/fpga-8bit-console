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
    mov <{zaddr: u8}, {addr: u16}, x => 0x23 @ zaddr @ $le(addr)
    mov  {zaddr: u8}, {addr: u16}, x => 0x23 @ zaddr @ $le(addr)

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
