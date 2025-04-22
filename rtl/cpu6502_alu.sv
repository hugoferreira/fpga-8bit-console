/*
 * SystemVerilog ALU for 6502 CPU.
 *
 * AI and BI are 8 bit inputs. Result in OUT.
 * CI is Carry In.
 * CO is Carry Out.
 *
 * op[3:0] is defined as follows:
 *
 * 0011   AI + BI
 * 0111   AI - BI
 * 1011   AI + AI
 * 1100   AI | BI
 * 1101   AI & BI
 * 1110   AI ^ BI
 * 1111   AI
 *
 */

// ALU operation codes
`include "rtl/cpu6502_defs.sv"

module ALU(
    input  logic        clk,
    input  logic        right,    // Shift right enable
    input  logic [3:0]  op,       // Operation
    input  logic [7:0]  AI,       // A input
    input  logic [7:0]  BI,       // B input
    input  logic        CI,       // Carry in
    input  logic        BCD,      // BCD style carry
    input  logic        RDY,      // Ready signal
    output logic [7:0]  OUT,      // Result output
    output logic        CO,       // Carry out
    output logic        V,        // Overflow flag
    output logic        Z,        // Zero flag
    output logic        N,        // Negative flag
    output logic        HC        // Half carry
);

// Internal state registers
logic AI7;         // Store MSB of AI
logic BI7;         // Store MSB of temp_BI
logic [8:0] temp_logic;  // Result of logic operation
logic [7:0] temp_BI;     // Modified B input
logic [4:0] temp_l;      // Lower nibble + carry
logic [4:0] temp_h;      // Upper nibble + carry
logic [8:0] temp;        // Combined result
logic adder_CI;          // Carry input for adder

// Compute the carry input for adder
assign adder_CI = (right || (op[3:2] == 2'b11)) ? 1'b0 : CI;

// Combined temporary result
assign temp = {temp_h, temp_l[3:0]};

// BCD related carry signals
logic HC9, CO9, temp_HC;

// HC9 is the half carry bit when doing BCD add
assign HC9 = BCD & (temp_l[3:1] >= 3'd5);

// CO9 is the carry-out bit when doing BCD add
assign CO9 = BCD & (temp_h[3:1] >= 3'd5);

// Combined half carry bit
assign temp_HC = temp_l[4] | HC9;

// Flag calculation
assign V = AI7 ^ BI7 ^ CO ^ N;
assign Z = ~|OUT;

// Calculate the logic operations (combinational)
always @(*) begin
    case(op[1:0])
        2'b00: temp_logic = {1'b0, AI} | {1'b0, BI};    // OR
        2'b01: temp_logic = {1'b0, AI} & {1'b0, BI};    // AND
        2'b10: temp_logic = {1'b0, AI} ^ {1'b0, BI};    // XOR
        2'b11: temp_logic = {1'b0, AI};         // Pass A
    endcase

    if(right)
        temp_logic = {AI[0], CI, AI[7:1]}; // Right shift/rotate
end

// Process the B input based on operation (combinational)
always @(*) begin
    case(op[3:2])
        2'b00: temp_BI = BI;            // A+B
        2'b01: temp_BI = ~BI;           // A-B
        2'b10: temp_BI = temp_logic[7:0];    // A+A - truncate to 8 bits
        2'b11: temp_BI = '0;            // A+0
    endcase
end

// Perform the addition as 2 separate nibbles (combinational)
always @(*) begin
    temp_l = temp_logic[3:0] + temp_BI[3:0] + {4'b0000, adder_CI};
    temp_h = temp_logic[8:4] + temp_BI[7:4] + {4'b0000, temp_HC};
end

// Update output flags (sequential)
always @(posedge clk) begin
    if(RDY) begin
        AI7 <= AI[7];
        BI7 <= temp_BI[7];
        OUT <= temp[7:0];
        CO  <= temp[8] | CO9;
        N   <= temp[7];
        HC  <= temp_HC;
    end
end

endmodule