/*
 * Shared definitions for the 6502 CPU and ALU.
 */
`ifndef CPU6502_DEFS_SV
`define CPU6502_DEFS_SV

// Define operation codes
`define OP_ADD 4'b0011
`define OP_SUB 4'b0111
`define OP_ROL 4'b1011
`define OP_OR  4'b1100
`define OP_AND 4'b1101
`define OP_EOR 4'b1110
`define OP_A   4'b1111

`endif 