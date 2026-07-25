/*
 * 6502 instruction decode table.
 *
 * One row per opcode: addressing mode, operation, register operand,
 * destination. The flag-write set is derived from the operation by `fwset`
 * rather than repeated per row - it is a property of the operation, and
 * writing it 151 times is 151 chances to write it wrong.
 *
 * This is the file an ISA slice edits. Adding an instruction is adding a row
 * here, and occasionally an addressing mode to `amode_t` plus its sequence in
 * `cpu6502_core.sv`. Nothing else in the core pattern-matches on opcode bits.
 *
 * Rows are in opcode order so the table can be diffed against
 * `tools/65x02/opcodes.txt` (and, when it lands, `docs/opcodes.md`) line by
 * line. The 105 opcodes with no row here decode to AM_TRAP: the core stops and
 * names the opcode and PC rather than executing undocumented behaviour.
 *
 * Hugo Sereno, <bytter@gmail.com>
 */

`ifndef CPU6502_DECODE_SV
`define CPU6502_DECODE_SV

// Addressing modes. The first twelve are the conventional ones; the rest are
// instructions whose sequence is peculiar enough to own a mode.
typedef enum logic [4:0] {
    AM_IMP,      // implied - the operand is a register
    AM_ACC,      // accumulator
    AM_IMM,      // #imm
    AM_ZP,       // zp
    AM_ZPX,      // zp,X
    AM_ZPY,      // zp,Y
    AM_ABS,      // abs
    AM_ABSX,     // abs,X
    AM_ABSY,     // abs,Y
    AM_INDX,     // (zp,X)
    AM_INDY,     // (zp),Y
    AM_REL,      // branch
    AM_PUSH,     // PHA, PHP
    AM_PULL,     // PLA, PLP
    AM_JSR,
    AM_RTS,
    AM_RTI,
    AM_BRK,
    AM_JMPA,     // JMP abs
    AM_JMPI,     // JMP (abs)
    AM_TRAP      // no row: undefined opcode
} amode_t;

// Operations. Deliberately one entry per architectural operation rather than
// per encoding, so the ALU is a case over this and not over instruction bits.
typedef enum logic [4:0] {
    OP_PASS,     // result = operand (loads, transfers, stores)
    OP_ORA, OP_AND, OP_EOR,
    OP_ADC, OP_SBC, OP_CMP, OP_BIT,
    OP_ASL, OP_LSR, OP_ROL, OP_ROR,
    OP_INC, OP_DEC,
    OP_CLC, OP_SEC, OP_CLI, OP_SEI, OP_CLV, OP_CLD, OP_SED,
    OP_NOP,
    OP_BRA       // branch: the operation is the condition test
} aluop_t;

// The register operand. For AM_IMP and AM_ACC it is also the second operand,
// which is what makes INX (R_X, OP_INC, D_X) and ASL A (R_A, OP_ASL, D_A) fall
// out of the same three fields as ORA zp (R_A, OP_ORA, D_A).
typedef enum logic [2:0] { R_NONE, R_A, R_X, R_Y, R_S, R_P } rsel_t;
typedef enum logic [2:0] { D_NONE, D_A, D_X, D_Y, D_S, D_P, D_MEM } dsel_t;

// Flag-write set, {N, V, D, I, Z, C}.
localparam logic [5:0] FW_NONE = 6'b000000;
localparam logic [5:0] FW_N    = 6'b100000;
localparam logic [5:0] FW_V    = 6'b010000;
localparam logic [5:0] FW_D    = 6'b001000;
localparam logic [5:0] FW_I    = 6'b000100;
localparam logic [5:0] FW_Z    = 6'b000010;
localparam logic [5:0] FW_C    = 6'b000001;

typedef struct packed {
    amode_t  am;
    aluop_t  op;
    rsel_t   ra;
    dsel_t   dst;
    logic [5:0] fw;
} dec_t;

`endif

/* verilator lint_off DECLFILENAME */
module cpu6502_decode (
    input  logic [7:0] ir,
    output dec_t       d
);

    // The flag-write set is a property of the operation. TXS is the one case
    // that needs the destination too: a transfer into S writes no flags, while
    // the same OP_PASS into A, X or Y writes N and Z.
    function automatic logic [5:0] fwset(aluop_t op, dsel_t dst);
        case (op)
            OP_PASS: fwset = (dst == D_A || dst == D_X || dst == D_Y)
                             ? (FW_N | FW_Z) : FW_NONE;
            OP_ORA, OP_AND, OP_EOR,
            OP_INC, OP_DEC:              fwset = FW_N | FW_Z;
            OP_ADC, OP_SBC:              fwset = FW_N | FW_V | FW_Z | FW_C;
            OP_CMP:                      fwset = FW_N | FW_Z | FW_C;
            OP_BIT:                      fwset = FW_N | FW_V | FW_Z;
            OP_ASL, OP_LSR,
            OP_ROL, OP_ROR:              fwset = FW_N | FW_Z | FW_C;
            OP_CLC, OP_SEC:              fwset = FW_C;
            OP_CLI, OP_SEI:              fwset = FW_I;
            OP_CLV:                      fwset = FW_V;
            OP_CLD, OP_SED:              fwset = FW_D;
            default:                     fwset = FW_NONE;
        endcase
    endfunction

    // Built as one concatenation rather than field by field: yosys cannot
    // infer a width for a struct member assigned inside a function, and this
    // table has to synthesise, not just simulate. The order here is the field
    // order of dec_t.
    function automatic dec_t row(amode_t am, aluop_t op, rsel_t ra, dsel_t dst);
        row = dec_t'({am, op, ra, dst, fwset(op, dst)});
    endfunction

    always_comb begin
        unique case (ir)
        // ---- 0x ----
        8'h00: d = row(AM_BRK,  OP_NOP,  R_NONE, D_NONE);   // BRK
        8'h01: d = row(AM_INDX, OP_ORA,  R_A,    D_A);      // ORA (zp,X)
        8'h05: d = row(AM_ZP,   OP_ORA,  R_A,    D_A);      // ORA zp
        8'h06: d = row(AM_ZP,   OP_ASL,  R_NONE, D_MEM);    // ASL zp
        8'h08: d = row(AM_PUSH, OP_PASS, R_P,    D_NONE);   // PHP
        8'h09: d = row(AM_IMM,  OP_ORA,  R_A,    D_A);      // ORA #
        8'h0A: d = row(AM_ACC,  OP_ASL,  R_A,    D_A);      // ASL A
        8'h0D: d = row(AM_ABS,  OP_ORA,  R_A,    D_A);      // ORA abs
        8'h0E: d = row(AM_ABS,  OP_ASL,  R_NONE, D_MEM);    // ASL abs
        // ---- 1x ----
        8'h10: d = row(AM_REL,  OP_BRA,  R_NONE, D_NONE);   // BPL
        8'h11: d = row(AM_INDY, OP_ORA,  R_A,    D_A);      // ORA (zp),Y
        8'h15: d = row(AM_ZPX,  OP_ORA,  R_A,    D_A);      // ORA zp,X
        8'h16: d = row(AM_ZPX,  OP_ASL,  R_NONE, D_MEM);    // ASL zp,X
        8'h18: d = row(AM_IMP,  OP_CLC,  R_NONE, D_NONE);   // CLC
        8'h19: d = row(AM_ABSY, OP_ORA,  R_A,    D_A);      // ORA abs,Y
        8'h1D: d = row(AM_ABSX, OP_ORA,  R_A,    D_A);      // ORA abs,X
        8'h1E: d = row(AM_ABSX, OP_ASL,  R_NONE, D_MEM);    // ASL abs,X
        // ---- 2x ----
        8'h20: d = row(AM_JSR,  OP_NOP,  R_NONE, D_NONE);   // JSR abs
        8'h21: d = row(AM_INDX, OP_AND,  R_A,    D_A);      // AND (zp,X)
        8'h24: d = row(AM_ZP,   OP_BIT,  R_A,    D_NONE);   // BIT zp
        8'h25: d = row(AM_ZP,   OP_AND,  R_A,    D_A);      // AND zp
        8'h26: d = row(AM_ZP,   OP_ROL,  R_NONE, D_MEM);    // ROL zp
        8'h28: d = row(AM_PULL, OP_PASS, R_NONE, D_P);      // PLP
        8'h29: d = row(AM_IMM,  OP_AND,  R_A,    D_A);      // AND #
        8'h2A: d = row(AM_ACC,  OP_ROL,  R_A,    D_A);      // ROL A
        8'h2C: d = row(AM_ABS,  OP_BIT,  R_A,    D_NONE);   // BIT abs
        8'h2D: d = row(AM_ABS,  OP_AND,  R_A,    D_A);      // AND abs
        8'h2E: d = row(AM_ABS,  OP_ROL,  R_NONE, D_MEM);    // ROL abs
        // ---- 3x ----
        8'h30: d = row(AM_REL,  OP_BRA,  R_NONE, D_NONE);   // BMI
        8'h31: d = row(AM_INDY, OP_AND,  R_A,    D_A);      // AND (zp),Y
        8'h35: d = row(AM_ZPX,  OP_AND,  R_A,    D_A);      // AND zp,X
        8'h36: d = row(AM_ZPX,  OP_ROL,  R_NONE, D_MEM);    // ROL zp,X
        8'h38: d = row(AM_IMP,  OP_SEC,  R_NONE, D_NONE);   // SEC
        8'h39: d = row(AM_ABSY, OP_AND,  R_A,    D_A);      // AND abs,Y
        8'h3D: d = row(AM_ABSX, OP_AND,  R_A,    D_A);      // AND abs,X
        8'h3E: d = row(AM_ABSX, OP_ROL,  R_NONE, D_MEM);    // ROL abs,X
        // ---- 4x ----
        8'h40: d = row(AM_RTI,  OP_NOP,  R_NONE, D_NONE);   // RTI
        8'h41: d = row(AM_INDX, OP_EOR,  R_A,    D_A);      // EOR (zp,X)
        8'h45: d = row(AM_ZP,   OP_EOR,  R_A,    D_A);      // EOR zp
        8'h46: d = row(AM_ZP,   OP_LSR,  R_NONE, D_MEM);    // LSR zp
        8'h48: d = row(AM_PUSH, OP_PASS, R_A,    D_NONE);   // PHA
        8'h49: d = row(AM_IMM,  OP_EOR,  R_A,    D_A);      // EOR #
        8'h4A: d = row(AM_ACC,  OP_LSR,  R_A,    D_A);      // LSR A
        8'h4C: d = row(AM_JMPA, OP_NOP,  R_NONE, D_NONE);   // JMP abs
        8'h4D: d = row(AM_ABS,  OP_EOR,  R_A,    D_A);      // EOR abs
        8'h4E: d = row(AM_ABS,  OP_LSR,  R_NONE, D_MEM);    // LSR abs
        // ---- 5x ----
        8'h50: d = row(AM_REL,  OP_BRA,  R_NONE, D_NONE);   // BVC
        8'h51: d = row(AM_INDY, OP_EOR,  R_A,    D_A);      // EOR (zp),Y
        8'h55: d = row(AM_ZPX,  OP_EOR,  R_A,    D_A);      // EOR zp,X
        8'h56: d = row(AM_ZPX,  OP_LSR,  R_NONE, D_MEM);    // LSR zp,X
        8'h58: d = row(AM_IMP,  OP_CLI,  R_NONE, D_NONE);   // CLI
        8'h59: d = row(AM_ABSY, OP_EOR,  R_A,    D_A);      // EOR abs,Y
        8'h5D: d = row(AM_ABSX, OP_EOR,  R_A,    D_A);      // EOR abs,X
        8'h5E: d = row(AM_ABSX, OP_LSR,  R_NONE, D_MEM);    // LSR abs,X
        // ---- 6x ----
        8'h60: d = row(AM_RTS,  OP_NOP,  R_NONE, D_NONE);   // RTS
        8'h61: d = row(AM_INDX, OP_ADC,  R_A,    D_A);      // ADC (zp,X)
        8'h65: d = row(AM_ZP,   OP_ADC,  R_A,    D_A);      // ADC zp
        8'h66: d = row(AM_ZP,   OP_ROR,  R_NONE, D_MEM);    // ROR zp
        8'h68: d = row(AM_PULL, OP_PASS, R_NONE, D_A);      // PLA
        8'h69: d = row(AM_IMM,  OP_ADC,  R_A,    D_A);      // ADC #
        8'h6A: d = row(AM_ACC,  OP_ROR,  R_A,    D_A);      // ROR A
        8'h6C: d = row(AM_JMPI, OP_NOP,  R_NONE, D_NONE);   // JMP (abs)
        8'h6D: d = row(AM_ABS,  OP_ADC,  R_A,    D_A);      // ADC abs
        8'h6E: d = row(AM_ABS,  OP_ROR,  R_NONE, D_MEM);    // ROR abs
        // ---- 7x ----
        8'h70: d = row(AM_REL,  OP_BRA,  R_NONE, D_NONE);   // BVS
        8'h71: d = row(AM_INDY, OP_ADC,  R_A,    D_A);      // ADC (zp),Y
        8'h75: d = row(AM_ZPX,  OP_ADC,  R_A,    D_A);      // ADC zp,X
        8'h76: d = row(AM_ZPX,  OP_ROR,  R_NONE, D_MEM);    // ROR zp,X
        8'h78: d = row(AM_IMP,  OP_SEI,  R_NONE, D_NONE);   // SEI
        8'h79: d = row(AM_ABSY, OP_ADC,  R_A,    D_A);      // ADC abs,Y
        8'h7D: d = row(AM_ABSX, OP_ADC,  R_A,    D_A);      // ADC abs,X
        8'h7E: d = row(AM_ABSX, OP_ROR,  R_NONE, D_MEM);    // ROR abs,X
        // ---- 8x ----
        8'h81: d = row(AM_INDX, OP_PASS, R_A,    D_MEM);    // STA (zp,X)
        8'h84: d = row(AM_ZP,   OP_PASS, R_Y,    D_MEM);    // STY zp
        8'h85: d = row(AM_ZP,   OP_PASS, R_A,    D_MEM);    // STA zp
        8'h86: d = row(AM_ZP,   OP_PASS, R_X,    D_MEM);    // STX zp
        8'h88: d = row(AM_IMP,  OP_DEC,  R_Y,    D_Y);      // DEY
        8'h8A: d = row(AM_IMP,  OP_PASS, R_X,    D_A);      // TXA
        8'h8C: d = row(AM_ABS,  OP_PASS, R_Y,    D_MEM);    // STY abs
        8'h8D: d = row(AM_ABS,  OP_PASS, R_A,    D_MEM);    // STA abs
        8'h8E: d = row(AM_ABS,  OP_PASS, R_X,    D_MEM);    // STX abs
        // ---- 9x ----
        8'h90: d = row(AM_REL,  OP_BRA,  R_NONE, D_NONE);   // BCC
        8'h91: d = row(AM_INDY, OP_PASS, R_A,    D_MEM);    // STA (zp),Y
        8'h94: d = row(AM_ZPX,  OP_PASS, R_Y,    D_MEM);    // STY zp,X
        8'h95: d = row(AM_ZPX,  OP_PASS, R_A,    D_MEM);    // STA zp,X
        8'h96: d = row(AM_ZPY,  OP_PASS, R_X,    D_MEM);    // STX zp,Y
        8'h98: d = row(AM_IMP,  OP_PASS, R_Y,    D_A);      // TYA
        8'h99: d = row(AM_ABSY, OP_PASS, R_A,    D_MEM);    // STA abs,Y
        8'h9A: d = row(AM_IMP,  OP_PASS, R_X,    D_S);      // TXS
        8'h9D: d = row(AM_ABSX, OP_PASS, R_A,    D_MEM);    // STA abs,X
        // ---- Ax ----
        8'hA0: d = row(AM_IMM,  OP_PASS, R_NONE, D_Y);      // LDY #
        8'hA1: d = row(AM_INDX, OP_PASS, R_NONE, D_A);      // LDA (zp,X)
        8'hA2: d = row(AM_IMM,  OP_PASS, R_NONE, D_X);      // LDX #
        8'hA4: d = row(AM_ZP,   OP_PASS, R_NONE, D_Y);      // LDY zp
        8'hA5: d = row(AM_ZP,   OP_PASS, R_NONE, D_A);      // LDA zp
        8'hA6: d = row(AM_ZP,   OP_PASS, R_NONE, D_X);      // LDX zp
        8'hA8: d = row(AM_IMP,  OP_PASS, R_A,    D_Y);      // TAY
        8'hA9: d = row(AM_IMM,  OP_PASS, R_NONE, D_A);      // LDA #
        8'hAA: d = row(AM_IMP,  OP_PASS, R_A,    D_X);      // TAX
        8'hAC: d = row(AM_ABS,  OP_PASS, R_NONE, D_Y);      // LDY abs
        8'hAD: d = row(AM_ABS,  OP_PASS, R_NONE, D_A);      // LDA abs
        8'hAE: d = row(AM_ABS,  OP_PASS, R_NONE, D_X);      // LDX abs
        // ---- Bx ----
        8'hB0: d = row(AM_REL,  OP_BRA,  R_NONE, D_NONE);   // BCS
        8'hB1: d = row(AM_INDY, OP_PASS, R_NONE, D_A);      // LDA (zp),Y
        8'hB4: d = row(AM_ZPX,  OP_PASS, R_NONE, D_Y);      // LDY zp,X
        8'hB5: d = row(AM_ZPX,  OP_PASS, R_NONE, D_A);      // LDA zp,X
        8'hB6: d = row(AM_ZPY,  OP_PASS, R_NONE, D_X);      // LDX zp,Y
        8'hB8: d = row(AM_IMP,  OP_CLV,  R_NONE, D_NONE);   // CLV
        8'hB9: d = row(AM_ABSY, OP_PASS, R_NONE, D_A);      // LDA abs,Y
        8'hBA: d = row(AM_IMP,  OP_PASS, R_S,    D_X);      // TSX
        8'hBC: d = row(AM_ABSX, OP_PASS, R_NONE, D_Y);      // LDY abs,X
        8'hBD: d = row(AM_ABSX, OP_PASS, R_NONE, D_A);      // LDA abs,X
        8'hBE: d = row(AM_ABSY, OP_PASS, R_NONE, D_X);      // LDX abs,Y
        // ---- Cx ----
        8'hC0: d = row(AM_IMM,  OP_CMP,  R_Y,    D_NONE);   // CPY #
        8'hC1: d = row(AM_INDX, OP_CMP,  R_A,    D_NONE);   // CMP (zp,X)
        8'hC4: d = row(AM_ZP,   OP_CMP,  R_Y,    D_NONE);   // CPY zp
        8'hC5: d = row(AM_ZP,   OP_CMP,  R_A,    D_NONE);   // CMP zp
        8'hC6: d = row(AM_ZP,   OP_DEC,  R_NONE, D_MEM);    // DEC zp
        8'hC8: d = row(AM_IMP,  OP_INC,  R_Y,    D_Y);      // INY
        8'hC9: d = row(AM_IMM,  OP_CMP,  R_A,    D_NONE);   // CMP #
        8'hCA: d = row(AM_IMP,  OP_DEC,  R_X,    D_X);      // DEX
        8'hCC: d = row(AM_ABS,  OP_CMP,  R_Y,    D_NONE);   // CPY abs
        8'hCD: d = row(AM_ABS,  OP_CMP,  R_A,    D_NONE);   // CMP abs
        8'hCE: d = row(AM_ABS,  OP_DEC,  R_NONE, D_MEM);    // DEC abs
        // ---- Dx ----
        8'hD0: d = row(AM_REL,  OP_BRA,  R_NONE, D_NONE);   // BNE
        8'hD1: d = row(AM_INDY, OP_CMP,  R_A,    D_NONE);   // CMP (zp),Y
        8'hD5: d = row(AM_ZPX,  OP_CMP,  R_A,    D_NONE);   // CMP zp,X
        8'hD6: d = row(AM_ZPX,  OP_DEC,  R_NONE, D_MEM);    // DEC zp,X
        8'hD8: d = row(AM_IMP,  OP_CLD,  R_NONE, D_NONE);   // CLD
        8'hD9: d = row(AM_ABSY, OP_CMP,  R_A,    D_NONE);   // CMP abs,Y
        8'hDD: d = row(AM_ABSX, OP_CMP,  R_A,    D_NONE);   // CMP abs,X
        8'hDE: d = row(AM_ABSX, OP_DEC,  R_NONE, D_MEM);    // DEC abs,X
        // ---- Ex ----
        8'hE0: d = row(AM_IMM,  OP_CMP,  R_X,    D_NONE);   // CPX #
        8'hE1: d = row(AM_INDX, OP_SBC,  R_A,    D_A);      // SBC (zp,X)
        8'hE4: d = row(AM_ZP,   OP_CMP,  R_X,    D_NONE);   // CPX zp
        8'hE5: d = row(AM_ZP,   OP_SBC,  R_A,    D_A);      // SBC zp
        8'hE6: d = row(AM_ZP,   OP_INC,  R_NONE, D_MEM);    // INC zp
        8'hE8: d = row(AM_IMP,  OP_INC,  R_X,    D_X);      // INX
        8'hE9: d = row(AM_IMM,  OP_SBC,  R_A,    D_A);      // SBC #
        8'hEA: d = row(AM_IMP,  OP_NOP,  R_NONE, D_NONE);   // NOP
        8'hEC: d = row(AM_ABS,  OP_CMP,  R_X,    D_NONE);   // CPX abs
        8'hED: d = row(AM_ABS,  OP_SBC,  R_A,    D_A);      // SBC abs
        8'hEE: d = row(AM_ABS,  OP_INC,  R_NONE, D_MEM);    // INC abs
        // ---- Fx ----
        8'hF0: d = row(AM_REL,  OP_BRA,  R_NONE, D_NONE);   // BEQ
        8'hF1: d = row(AM_INDY, OP_SBC,  R_A,    D_A);      // SBC (zp),Y
        8'hF5: d = row(AM_ZPX,  OP_SBC,  R_A,    D_A);      // SBC zp,X
        8'hF6: d = row(AM_ZPX,  OP_INC,  R_NONE, D_MEM);    // INC zp,X
        8'hF8: d = row(AM_IMP,  OP_SED,  R_NONE, D_NONE);   // SED
        8'hF9: d = row(AM_ABSY, OP_SBC,  R_A,    D_A);      // SBC abs,Y
        8'hFD: d = row(AM_ABSX, OP_SBC,  R_A,    D_A);      // SBC abs,X
        8'hFE: d = row(AM_ABSX, OP_INC,  R_NONE, D_MEM);    // INC abs,X

        // The other 105 slots. Reserved for the ISA slices; until one claims a
        // slot, executing it is a named failure rather than silent corruption.
        default: d = row(AM_TRAP, OP_NOP, R_NONE, D_NONE);
        endcase
    end

endmodule
/* verilator lint_on DECLFILENAME */
