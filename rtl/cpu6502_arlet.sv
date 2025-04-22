/*
 * SystemVerilog model of 6502 CPU.
 *
 * (C) Arlet Ottens, <arlet@c-scape.nl>
 * SystemVerilog modernization: Hugo Sereno, <bytter@gmail.com>
 *
 * Feel free to use this code in any project (commercial or not), as long as you
 * keep this message, and the copyright notice. This code is provided "as is", 
 * without any warranties of any kind. 
 * 
 */

/* CASEX is used throughout the CPU core logic - suppress warnings */
/* verilator lint_off CASEX */
/* verilator lint_off CASEOVERLAP */
/* verilator lint_off CASEINCOMPLETE */

// Include shared definitions
`include "rtl/cpu6502_defs.sv"

// Register selection
typedef enum {
    SEL_A = 0,
    SEL_S = 1,
    SEL_X = 2, 
    SEL_Y = 3
} reg_sel_t;

// CPU State Machine States
typedef enum {
    ABS0   = 0,  // ABS     - fetch LSB      
    ABS1   = 1,  // ABS     - fetch MSB
    ABSX0  = 2,  // ABS, X  - fetch LSB and send to ALU (+X)
    ABSX1  = 3,  // ABS, X  - fetch MSB and send to ALU (+Carry)
    ABSX2  = 4,  // ABS, X  - Wait for ALU (only if needed)
    BRA0   = 5,  // Branch  - fetch offset and send to ALU (+PC[7:0])
    BRA1   = 6,  // Branch  - fetch opcode, and send PC[15:8] to ALU 
    BRA2   = 7,  // Branch  - fetch opcode (if page boundary crossed)
    BRK0   = 8,  // BRK/IRQ - push PCH, send S to ALU (-1)
    BRK1   = 9,  // BRK/IRQ - push PCL, send S to ALU (-1)
    BRK2   = 10, // BRK/IRQ - push P, send S to ALU (-1)
    BRK3   = 11, // BRK/IRQ - write S, and fetch @ fffe
    DECODE = 12, // IR is valid, decode instruction, and write prev reg
    FETCH  = 13, // fetch next opcode, and perform prev ALU op
    INDX0  = 14, // (ZP,X)  - fetch ZP address, and send to ALU (+X)
    INDX1  = 15, // (ZP,X)  - fetch LSB at ZP+X, calculate ZP+X+1
    INDX2  = 16, // (ZP,X)  - fetch MSB at ZP+X+1
    INDX3  = 17, // (ZP,X)  - fetch data 
    INDY0  = 18, // (ZP),Y  - fetch ZP address, and send ZP to ALU (+1)
    INDY1  = 19, // (ZP),Y  - fetch at ZP+1, and send LSB to ALU (+Y) 
    INDY2  = 20, // (ZP),Y  - fetch data, and send MSB to ALU (+Carry)
    INDY3  = 21, // (ZP),Y) - fetch data (if page boundary crossed)
    JMP0   = 22, // JMP     - fetch PCL and hold
    JMP1   = 23, // JMP     - fetch PCH
    JMPI0  = 24, // JMP IND - fetch LSB and send to ALU for delay (+0)
    JMPI1  = 25, // JMP IND - fetch MSB, proceed with JMP0 state
    JSR0   = 26, // JSR     - push PCH, save LSB, send S to ALU (-1)
    JSR1   = 27, // JSR     - push PCL, send S to ALU (-1)
    JSR2   = 28, // JSR     - write S
    JSR3   = 29, // JSR     - fetch MSB
    PULL0  = 30, // PLP/PLA - save next op in IRHOLD, send S to ALU (+1)
    PULL1  = 31, // PLP/PLA - fetch data from stack, write S
    PULL2  = 32, // PLP/PLA - prefetch op, but don't increment PC
    PUSH0  = 33, // PHP/PHA - send A to ALU (+0)
    PUSH1  = 34, // PHP/PHA - write A/P, send S to ALU (-1)
    READ   = 35, // Read memory for read/modify/write (INC, DEC, shift)
    REG    = 36, // Read register for reg-reg transfers
    RTI0   = 37, // RTI     - send S to ALU (+1)
    RTI1   = 38, // RTI     - read P from stack 
    RTI2   = 39, // RTI     - read PCL from stack
    RTI3   = 40, // RTI     - read PCH from stack
    RTI4   = 41, // RTI     - read PCH from stack
    RTS0   = 42, // RTS     - send S to ALU (+1)
    RTS1   = 43, // RTS     - read PCL from stack 
    RTS2   = 44, // RTS     - write PCL to ALU, read PCH 
    RTS3   = 45, // RTS     - load PC and increment
    WRITE  = 46, // Write memory for read/modify/write 
    ZP0    = 47, // Z-page  - fetch ZP address
    ZPX0   = 48, // ZP, X   - fetch ZP, and send to ALU (+X)
    ZPX1   = 49  // ZP, X   - load from memory
} cpu_state_t;

// Definition of alu_op_t is shared between files
// we redefine it locally from macros
typedef logic [3:0] alu_op_t;

module cpu(
    input  logic        clk,          // CPU clock 
    input  logic        reset,        // Reset signal
    output logic [15:0] AB,           // Address bus
    input  logic [7:0]  DI,           // Data in, read bus
    output logic [7:0]  DO,           // Data out, write bus
    output logic        WE,           // Write enable
    input  logic        IRQ,          // Interrupt request
    input  logic        NMI,          // Non-maskable interrupt request
    input  logic        RDY           // Ready signal. Pauses CPU when RDY=0 
);

/*
 * internal signals
 */

logic [15:0] PC;         // Program Counter 
logic [7:0]  ABL;        // Address Bus Register LSB
logic [7:0]  ABH;        // Address Bus Register MSB
logic [7:0]  ADD;        // Adder Hold Register (registered in ALU)

logic [7:0]  DIHOLD;     // Hold for Data In
logic        DIHOLD_valid;
logic [7:0]  DIMUX;      // Data Input Multiplexer

logic [7:0]  IRHOLD;     // Hold for Instruction register 
logic        IRHOLD_valid; // Valid instruction in IRHOLD

logic [7:0]  AXYS[4];    // A, X, Y and S register file

logic        C = 1'b0;   // Carry flag (init at zero to avoid X's in ALU sim)
logic        Z = 1'b0;   // Zero flag
logic        I = 1'b0;   // Interrupt flag
logic        D = 1'b0;   // Decimal flag
logic        V = 1'b0;   // Overflow flag
logic        N = 1'b0;   // Negative flag
logic        AZ;         // ALU Zero flag
logic        AV;         // ALU overflow flag
logic        AN;         // ALU negative flag
logic        HC;         // ALU half carry

logic [7:0]  AI;         // ALU Input A
logic [7:0]  BI;         // ALU Input B
logic [7:0]  IR;         // Instruction register
logic        CI;         // Carry In
logic        CO;         // Carry Out 
logic [7:0]  PCH, PCL;   // PC high and low bytes

assign PCH = PC[15:8];
assign PCL = PC[7:0];

logic        NMI_edge = 1'b0; // Captured NMI edge

reg_sel_t    regsel;     // Select A, X, Y or S register
logic [7:0]  regfile;    // Selected register output

assign regfile = AXYS[regsel];

// CPU status flags combined into processor status byte
logic [7:0] P;
assign P = { N, V, 2'b11, D, I, Z, C };

/*
 * define some signals for watching in simulator output
 */

`ifdef SIM
logic [7:0] A, X, Y, S; // Register aliases for simulation

assign A = AXYS[SEL_A];  // Accumulator
assign X = AXYS[SEL_X];  // X register
assign Y = AXYS[SEL_Y];  // Y register 
assign S = AXYS[SEL_S];  // Stack pointer 
`endif

/*
 * instruction decoder/sequencer
 */

cpu_state_t state;

/*
 * control signals
 */

logic        PC_inc;             // Increment PC
logic [15:0] PC_temp;            // Intermediate value of PC 

reg_sel_t    src_reg;            // Source register index
reg_sel_t    dst_reg;            // Destination register index

logic        index_y;            // If set, then Y is index reg rather than X 
logic        load_reg;           // Loading a register (A, X, Y, S) in this instruction
logic        inc;                // Increment
logic        write_back;         // Set if memory is read/modified/written 
logic        load_only;          // LDA/LDX/LDY instruction
logic        store;              // Doing store (STA/STX/STY)
logic        adc_sbc;            // Doing ADC/SBC
logic        compare;            // Doing CMP/CPY/CPX
logic        shift;              // Doing shift/rotate instruction
logic        rotate;             // Doing rotate (no shift)
logic        backwards;          // Backwards branch
logic        cond_true;          // Branch condition is true
logic [2:0]  cond_code;          // Condition code bits from instruction
logic        shift_right;        // Instruction ALU shift/rotate right 
logic        alu_shift_right;    // Current cycle shift right enable
alu_op_t     op;                 // Main ALU operation for instruction
alu_op_t     alu_op;             // Current cycle ALU operation 
logic        adc_bcd;            // ALU should do BCD style carry 
logic        adj_bcd;            // Results should be BCD adjusted

/* 
 * Some flip flops to remember we're doing special instructions. These
 * get loaded at the DECODE state, and used later
 */
logic bit_ins;            // Doing BIT instruction
logic plp;                // Doing PLP instruction
logic php;                // Doing PHP instruction 
logic clc;                // Clear carry
logic sec;                // Set carry
logic cld;                // Clear decimal
logic sed;                // Set decimal
logic cli;                // Clear interrupt
logic sei;                // Set interrupt
logic clv;                // Clear overflow 
logic brk;                // Doing BRK
logic res;                // In reset

`ifdef SIM

/*
 * easy to read names in simulator output
 */
string statename;

always_comb begin
    case(state)
        DECODE: statename = "DECODE";
        REG:    statename = "REG";
        ZP0:    statename = "ZP0";
        ZPX0:   statename = "ZPX0";
        ZPX1:   statename = "ZPX1";
        ABS0:   statename = "ABS0";
        ABS1:   statename = "ABS1";
        ABSX0:  statename = "ABSX0";
        ABSX1:  statename = "ABSX1";
        ABSX2:  statename = "ABSX2";
        INDX0:  statename = "INDX0";
        INDX1:  statename = "INDX1";
        INDX2:  statename = "INDX2";
        INDX3:  statename = "INDX3";
        INDY0:  statename = "INDY0";
        INDY1:  statename = "INDY1";
        INDY2:  statename = "INDY2";
        INDY3:  statename = "INDY3";
        default: statename = "OTHER";
    endcase

//always @( PC )
//      $display( "%t, PC:%04x IR:%02x A:%02x X:%02x Y:%02x S:%02x C:%d Z:%d V:%d N:%d P:%02x", $time, PC, IR, A, X, Y, S, C, Z, V, N, P );

`endif

/*
 * Program Counter Increment/Load. First calculate the base value in
 * PC_temp.
 */
always_comb begin
    case(state)
        DECODE:         if((~I & IRQ) | NMI_edge)
                            PC_temp = {ABH, ABL};
                        else
                            PC_temp = PC;

        JMP1,
        JMPI1,
        JSR3,
        RTS3,           
        RTI4:           PC_temp = {DIMUX, ADD};
                        
        BRA1:           PC_temp = {ABH, ADD};

        BRA2:           PC_temp = {ADD, PCL};

        BRK2:           PC_temp = res ? 16'hfffc : 
                                 NMI_edge ? 16'hfffa : 16'hfffe;

        default:        PC_temp = PC;
    endcase
end

/*
 * Determine whether we need PC_temp, or PC_temp + 1
 */
always_comb begin
    case(state)
        DECODE:         if((~I & IRQ) | NMI_edge)
                            PC_inc = 0;
                        else
                            PC_inc = 1;

        ABS0,
        ABSX0,
        FETCH,
        BRA0,
        BRA2,
        BRK3,
        JMPI1,
        JMP1,
        RTI4,
        RTS3:           PC_inc = 1;

        BRA1:           PC_inc = CO ^~ backwards;

        default:        PC_inc = 0;
    endcase
end

/* 
 * Set new PC
 */
always_ff @(posedge clk) 
    if(RDY) begin
        PC <= PC_temp + {{15{1'b0}}, PC_inc};
        
        // Only print PC changes during reset or when accessing key areas
        if (PC != PC_temp + {{15{1'b0}}, PC_inc}) begin
            if (res || state <= BRK3 || 
                PC_temp == 16'h0300 || PC_temp == 16'hFFFC)
                $display("CPU: PC change: %04X -> %04X, State: %d, res=%d", 
                          PC, PC_temp + {{15{1'b0}}, PC_inc}, state, res);
        end
    end

/*
 * Address Generator 
 */

localparam logic [7:0] ZEROPAGE  = 8'h00;
localparam logic [7:0] STACKPAGE = 8'h01;

always_comb begin
    case(state)
        ABSX1,
        INDX3,
        INDY2,
        JMP1,
        JMPI1,
        RTI4,
        ABS1:           AB = {DIMUX, ADD};

        BRA2,
        INDY3,
        ABSX2:          AB = {ADD, ABL};

        BRA1:           AB = {ABH, ADD};

        JSR0,
        PUSH1,
        RTS0,
        RTI0,
        BRK0:           AB = {STACKPAGE, regfile};

        BRK1,
        JSR1,
        PULL1,
        RTS1,
        RTS2,
        RTI1,
        RTI2,
        RTI3,
        BRK2:           AB = {STACKPAGE, ADD};
        
        INDY1,
        INDX1,
        ZPX1,
        INDX2:          AB = {ZEROPAGE, ADD};

        ZP0,
        INDY0:          AB = {ZEROPAGE, DIMUX};

        REG,
        READ,
        WRITE:          AB = {ABH, ABL};

        default:        AB = PC;
    endcase
end

/*
 * ABH/ABL pair is used for registering previous address bus state.
 * This can be used to keep the current address, freeing up the original
 * source of the address, such as the ALU or DI.
 */
always_ff @(posedge clk)
    if(state != PUSH0 && state != PUSH1 && RDY && 
       state != PULL0 && state != PULL1 && state != PULL2)
    begin
        ABL <= AB[7:0];
        ABH <= AB[15:8];
    end

/*
 * Data Out MUX 
 */
always_comb begin
    case(state)
        WRITE:   DO = ADD;

        JSR0,
        BRK0:    DO = PCH;

        JSR1,
        BRK1:    DO = PCL;

        PUSH1:   DO = php ? P : ADD;

        BRK2:    DO = (IRQ | NMI_edge) ? (P & 8'b1110_1111) : P;

        default: DO = regfile;
    endcase
end

/*
 * Write Enable Generator
 */
always_comb begin
    case(state)
        BRK0,   // writing to stack or memory
        BRK1,
        BRK2,
        JSR0,
        JSR1,
        PUSH1,
        WRITE:   WE = 1;

        INDX3,  // only if doing a STA, STX or STY
        INDY3,
        ABSX2,
        ABS1,
        ZPX1,
        ZP0:     WE = store;

        default: WE = 0;
    endcase
end

/*
 * Register file, contains A, X, Y and S (stack pointer) registers. At each
 * cycle only 1 of those registers needs to be accessed, so they combined
 * in a small memory, saving resources.
 */

// Set when register file is written
logic write_register;

always_comb begin
    case(state)
        DECODE: write_register = load_reg & ~plp;

        PULL1, 
        RTS2, 
        RTI3,
        BRK3,
        JSR0,
        JSR2:  write_register = 1;

        default: write_register = 0;
    endcase
end

/*
 * BCD adjust logic
 */
always_ff @(posedge clk)
    adj_bcd <= adc_sbc & D;     // '1' when doing a BCD instruction

logic [3:0] ADJL;
logic [3:0] ADJH;

// adjustment term to be added to ADD[3:0] based on the following
// adj_bcd: '1' if doing ADC/SBC with D=1
// adc_bcd: '1' if doing ADC with D=1
// HC     : half carry bit from ALU
always @* begin
    casex( {adj_bcd, adc_bcd, HC} )
         3'b0xx: ADJL = 4'd0;   // no BCD instruction
         3'b100: ADJL = 4'd10;  // SBC, and digital borrow
         3'b101: ADJL = 4'd0;   // SBC, but no borrow
         3'b110: ADJL = 4'd0;   // ADC, but no carry
         3'b111: ADJL = 4'd6;   // ADC, and decimal/digital carry
    endcase
end

// adjustment term to be added to ADD[7:4] based on the following
// adj_bcd: '1' if doing ADC/SBC with D=1
// adc_bcd: '1' if doing ADC with D=1
// CO     : carry out bit from ALU
always @* begin
    casex( {adj_bcd, adc_bcd, CO} )
         3'b0xx: ADJH = 4'd0;   // no BCD instruction
         3'b100: ADJH = 4'd10;  // SBC, and digital borrow
         3'b101: ADJH = 4'd0;   // SBC, but no borrow
         3'b110: ADJH = 4'd0;   // ADC, but no carry
         3'b111: ADJH = 4'd6;   // ADC, and decimal/digital carry
    endcase
end

/*
 * Write to a register. Usually this is the (BCD corrected) output of the
 * ALU, but in case of the JSR0 we use the S register to temporarily store
 * the PCL. This is possible, because the S register itself is stored in
 * the ALU during those cycles.
 */
always_ff @(posedge clk)
    if(write_register & RDY)
        AXYS[regsel] <= (state == JSR0) ? DIMUX : {ADD[7:4] + ADJH, ADD[3:0] + ADJL};

/*
 * Register select logic. This determines which of the A, X, Y or
 * S registers will be accessed. 
 */
always @(*) begin
    case(state)
        INDY1,
        INDX0,
        ZPX0,
        ABSX0:  regsel = index_y ? SEL_Y : SEL_X;

        DECODE: regsel = dst_reg; 

        BRK0,
        BRK3,
        JSR0,
        JSR2,
        PULL0,
        PULL1,
        PUSH1,
        RTI0,
        RTI3,
        RTS0,
        RTS2:  regsel = SEL_S;
        
        default: regsel = src_reg; 
    endcase
end

/*
 * ALU
 */
ALU ALU(
    .clk(clk),
    .op(alu_op),
    .right(alu_shift_right),
    .AI(AI),
    .BI(BI),
    .CI(CI),
    .BCD(adc_bcd & (state == FETCH)),
    .CO(CO),
    .OUT(ADD),
    .V(AV),
    .Z(AZ),
    .N(AN),
    .HC(HC),
    .RDY(RDY)
);

/*
 * Select current ALU operation
 */
always @(*) begin
    case(state)
        READ:   alu_op = op;

        BRA1:   alu_op = backwards ? `OP_SUB : `OP_ADD; 

        FETCH,
        REG:    alu_op = op; 

        DECODE,
        ABS1:   alu_op = `OP_ADD; // Default to ADD for don't care states

        PUSH1,
        BRK0,
        BRK1,
        BRK2,
        JSR0,
        JSR1:   alu_op = `OP_SUB;

        default: alu_op = `OP_ADD;
    endcase
end

/*
 * Determine shift right signal to ALU
 */
always @(*) begin
    if(state == FETCH || state == REG || state == READ)
        alu_shift_right = shift_right;
    else
        alu_shift_right = 0;
end

/*
 * Sign extend branch offset.  
 */
always @(posedge clk)
    if(RDY)
        backwards <= DIMUX[7];

/* 
 * ALU A Input MUX 
 */
always @(*) begin
    case(state)
        JSR1,
        RTS1,
        RTI1,
        RTI2,
        BRK1,
        BRK2,
        INDX1:  AI = ADD;

        REG,
        ZPX0,
        INDX0,
        ABSX0,
        RTI0,
        RTS0,
        JSR0,
        JSR2,
        BRK0,
        PULL0,
        INDY1,
        PUSH0,
        PUSH1:  AI = regfile;

        BRA0,
        READ:   AI = DIMUX;

        BRA1:   AI = ABH;       // don't use PCH in case we're 

        FETCH:  AI = load_only ? 0 : regfile;

        DECODE,
        ABS1:   AI = 8'h00;     // Default to 0 for don't care states

        default: AI = 0;
    endcase
end

/*
 * ALU B Input mux
 */
always_comb begin
    case(state)
        BRA1,
        RTS1,
        RTI0,
        RTI1,
        RTI2,
        INDX1,
        READ,
        REG,
        JSR0,
        JSR1,
        JSR2,
        BRK0,
        BRK1,
        BRK2,
        PUSH0, 
        PUSH1,
        PULL0,
        RTS0:  BI = 8'h00;
        
        BRA0:  BI = PCL;

        DECODE,
        ABS1:  BI = 8'h00;  // Default to 0 for don't care states

        default: BI = DIMUX;
    endcase
end

/*
 * ALU CI (carry in) mux
 */
always_comb begin
    case(state)
        INDY2,
        BRA1,
        ABSX1:  CI = CO;

        DECODE,
        ABS1:   CI = 0;  // Default to 0 for don't care states

        READ,
        REG:    CI = rotate ? C :
                     shift ? 0 : inc;

        FETCH:  CI = rotate  ? C : 
                     compare ? 1 : 
                     (shift | load_only) ? 0 : C;

        PULL0,
        RTI0,
        RTI1,
        RTI2,
        RTS0,
        RTS1,
        INDY0,
        INDX1:  CI = 1; 

        default: CI = 0;
    endcase
end

/*
 * Processor Status Register update
 */

/*
 * Update C flag when doing ADC/SBC, shift/rotate, compare
 */
always_ff @(posedge clk) begin
    if(shift && state == WRITE) 
        C <= CO;
    else if(state == RTI2)
        C <= DIMUX[0];
    else if(~write_back && state == DECODE) begin
        if(adc_sbc | shift | compare)
            C <= CO;
        else if(plp)
            C <= ADD[0];
        else begin
            if(sec) C <= 1;
            if(clc) C <= 0;
        end
    end
end

/*
 * Update Z, N flags when writing A, X, Y, Memory, or when doing compare
 */
always_ff @(posedge clk) begin
    if(state == WRITE) 
        Z <= AZ;
    else if(state == RTI2)
        Z <= DIMUX[1];
    else if(state == DECODE) begin
        if(plp)
            Z <= ADD[1];
        else if((load_reg & (regsel != SEL_S)) | compare | bit_ins)
            Z <= AZ;
    end
end

always_ff @(posedge clk) begin
    if(state == WRITE)
        N <= AN;
    else if(state == RTI2)
        N <= DIMUX[7];
    else if(state == DECODE) begin
        if(plp)
            N <= ADD[7];
        else if((load_reg & (regsel != SEL_S)) | compare)
            N <= AN;
    end else if(state == FETCH && bit_ins) 
        N <= DIMUX[7];
end

/*
 * Update I flag
 */
always_ff @(posedge clk) begin
    if(state == BRK3)
        I <= 1;
    else if(state == RTI2)
        I <= DIMUX[2];
    else if(state == REG) begin
        if(sei) I <= 1;
        if(cli) I <= 0;
    end else if(state == DECODE)
        if(plp) I <= ADD[2];
end

/*
 * Update D flag
 */
always_ff @(posedge clk) begin
    if(state == RTI2)
        D <= DIMUX[3];
    else if(state == DECODE) begin
        if(sed) D <= 1;
        if(cld) D <= 0;
        if(plp) D <= ADD[3];
    end
end

/*
 * Update V flag
 */
always_ff @(posedge clk) begin
    if(state == RTI2) 
        V <= DIMUX[6];
    else if(state == DECODE) begin
        if(adc_sbc) V <= AV;
        if(clv)     V <= 0;
        if(plp)     V <= ADD[6];
    end else if(state == FETCH && bit_ins) 
        V <= DIMUX[6];
end

/*
 * Instruction decoder
 */

/*
 * IR register/mux. Hold previous DI value in IRHOLD in PULL0 and PUSH0
 * states. In these states, the IR has been prefetched, and there is no
 * time to read the IR again before the next decode.
 */
always_ff @(posedge clk) begin
    if(reset)
        IRHOLD_valid <= 0;
    else if(RDY) begin
        if(state == PULL0 || state == PUSH0) begin
            IRHOLD <= DIMUX;
            IRHOLD_valid <= 1;
        end else if(state == DECODE)
            IRHOLD_valid <= 0;
    end
end

assign IR = (IRQ & ~I) | NMI_edge ? 8'h00 :
                      IRHOLD_valid ? IRHOLD : DIMUX;

always_ff @(posedge clk)
    if(RDY)
        DIHOLD <= DI;

assign DIMUX = ~RDY ? DIHOLD : DI;

/*
 * Microcode state machine
 */
always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
        state <= BRK0;
        $display("CPU: RESET triggered");
    end
    else if(RDY) begin
        // Save previous state for debugging during reset
        if (res || state <= BRK3) begin
            cpu_state_t prev_state = state;
            
            // Execute state machine transitions
            case(state)
                DECODE: 
                    casex(IR)
                        8'b0000_0000:   state <= BRK0;
                        8'b0010_0000:   state <= JSR0;
                        8'b0010_1100:   state <= ABS0;  // BIT abs
                        8'b0100_0000:   state <= RTI0;  // 
                        8'b0100_1100:   state <= JMP0;
                        8'b0110_0000:   state <= RTS0;
                        8'b0110_1100:   state <= JMPI0;
                        8'b0x00_1000:   state <= PUSH0;
                        8'b0x10_1000:   state <= PULL0;
                        8'b0xx1_1000:   state <= REG;   // CLC, SEC, CLI, SEI 
                        8'b1xx0_00x0:   state <= FETCH; // IMM
                        8'b1xx0_1100:   state <= ABS0;  // X/Y abs
                        8'b1xxx_1000:   state <= REG;   // DEY, TYA, ... 
                        8'bxxx0_0001:   state <= INDX0;
                        8'bxxx0_01xx:   state <= ZP0;
                        8'bxxx0_1001:   state <= FETCH; // IMM
                        8'bxxx0_1101:   state <= ABS0;  // even E column
                        8'bxxx0_1110:   state <= ABS0;  // even E column
                        8'bxxx1_0000:   state <= BRA0;  // odd 0 column
                        8'bxxx1_0001:   state <= INDY0; // odd 1 column
                        8'bxxx1_01xx:   state <= ZPX0;  // odd 4,5,6,7 columns
                        8'bxxx1_1001:   state <= ABSX0; // odd 9 column
                        8'bxxx1_11xx:   state <= ABSX0; // odd C, D, E, F columns
                        8'bxxxx_1010:   state <= REG;   // <shift> A, TXA, ...  NOP
                    endcase

                ZP0:     state <= write_back ? READ : FETCH;

                ZPX0:    state <= ZPX1;
                ZPX1:    state <= write_back ? READ : FETCH;

                ABS0:    state <= ABS1;
                ABS1:    state <= write_back ? READ : FETCH;

                ABSX0:   state <= ABSX1;
                ABSX1:   state <= (CO | store | write_back) ? ABSX2 : FETCH;
                ABSX2:   state <= write_back ? READ : FETCH;

                INDX0:   state <= INDX1;
                INDX1:   state <= INDX2;
                INDX2:   state <= INDX3;
                INDX3:   state <= FETCH;

                INDY0:   state <= INDY1;
                INDY1:   state <= INDY2;
                INDY2:   state <= (CO | store) ? INDY3 : FETCH;
                INDY3:   state <= FETCH;

                READ:    state <= WRITE;
                WRITE:   state <= FETCH;
                FETCH:   state <= DECODE;

                REG:     state <= DECODE;
                
                PUSH0:   state <= PUSH1;
                PUSH1:   state <= DECODE;

                PULL0:   state <= PULL1;
                PULL1:   state <= PULL2; 
                PULL2:   state <= DECODE;

                JSR0:    state <= JSR1;
                JSR1:    state <= JSR2;
                JSR2:    state <= JSR3;
                JSR3:    state <= FETCH; 

                RTI0:    state <= RTI1;
                RTI1:    state <= RTI2;
                RTI2:    state <= RTI3;
                RTI3:    state <= RTI4;
                RTI4:    state <= DECODE;

                RTS0:    state <= RTS1;
                RTS1:    state <= RTS2;
                RTS2:    state <= RTS3;
                RTS3:    state <= FETCH;

                BRA0:    state <= cond_true ? BRA1 : DECODE;
                BRA1:    state <= (CO ^ backwards) ? BRA2 : DECODE;
                BRA2:    state <= DECODE;

                JMP0:    state <= JMP1;
                JMP1:    state <= DECODE; 

                JMPI0:   state <= JMPI1;
                JMPI1:   state <= JMP0;

                BRK0:    state <= BRK1;
                BRK1:    state <= BRK2;
                BRK2:    state <= BRK3;
                BRK3:    state <= JMP0;
            endcase
            
            // Print key state transitions during reset
            if (prev_state != state)
                $display("CPU: Reset state transition: %d -> %d", prev_state, state);
        end
        else begin
            // Execute state machine transitions without debug
            case(state)
                DECODE: 
                    casex(IR)
                        8'b0000_0000:   state <= BRK0;
                        8'b0010_0000:   state <= JSR0;
                        8'b0010_1100:   state <= ABS0;  // BIT abs
                        8'b0100_0000:   state <= RTI0;  // 
                        8'b0100_1100:   state <= JMP0;
                        8'b0110_0000:   state <= RTS0;
                        8'b0110_1100:   state <= JMPI0;
                        8'b0x00_1000:   state <= PUSH0;
                        8'b0x10_1000:   state <= PULL0;
                        8'b0xx1_1000:   state <= REG;   // CLC, SEC, CLI, SEI 
                        8'b1xx0_00x0:   state <= FETCH; // IMM
                        8'b1xx0_1100:   state <= ABS0;  // X/Y abs
                        8'b1xxx_1000:   state <= REG;   // DEY, TYA, ... 
                        8'bxxx0_0001:   state <= INDX0;
                        8'bxxx0_01xx:   state <= ZP0;
                        8'bxxx0_1001:   state <= FETCH; // IMM
                        8'bxxx0_1101:   state <= ABS0;  // even E column
                        8'bxxx0_1110:   state <= ABS0;  // even E column
                        8'bxxx1_0000:   state <= BRA0;  // odd 0 column
                        8'bxxx1_0001:   state <= INDY0; // odd 1 column
                        8'bxxx1_01xx:   state <= ZPX0;  // odd 4,5,6,7 columns
                        8'bxxx1_1001:   state <= ABSX0; // odd 9 column
                        8'bxxx1_11xx:   state <= ABSX0; // odd C, D, E, F columns
                        8'bxxxx_1010:   state <= REG;   // <shift> A, TXA, ...  NOP
                    endcase

                ZP0:     state <= write_back ? READ : FETCH;

                ZPX0:    state <= ZPX1;
                ZPX1:    state <= write_back ? READ : FETCH;

                ABS0:    state <= ABS1;
                ABS1:    state <= write_back ? READ : FETCH;

                ABSX0:   state <= ABSX1;
                ABSX1:   state <= (CO | store | write_back) ? ABSX2 : FETCH;
                ABSX2:   state <= write_back ? READ : FETCH;

                INDX0:   state <= INDX1;
                INDX1:   state <= INDX2;
                INDX2:   state <= INDX3;
                INDX3:   state <= FETCH;

                INDY0:   state <= INDY1;
                INDY1:   state <= INDY2;
                INDY2:   state <= (CO | store) ? INDY3 : FETCH;
                INDY3:   state <= FETCH;

                READ:    state <= WRITE;
                WRITE:   state <= FETCH;
                FETCH:   state <= DECODE;

                REG:     state <= DECODE;
                
                PUSH0:   state <= PUSH1;
                PUSH1:   state <= DECODE;

                PULL0:   state <= PULL1;
                PULL1:   state <= PULL2; 
                PULL2:   state <= DECODE;

                JSR0:    state <= JSR1;
                JSR1:    state <= JSR2;
                JSR2:    state <= JSR3;
                JSR3:    state <= FETCH; 

                RTI0:    state <= RTI1;
                RTI1:    state <= RTI2;
                RTI2:    state <= RTI3;
                RTI3:    state <= RTI4;
                RTI4:    state <= DECODE;

                RTS0:    state <= RTS1;
                RTS1:    state <= RTS2;
                RTS2:    state <= RTS3;
                RTS3:    state <= FETCH;

                BRA0:    state <= cond_true ? BRA1 : DECODE;
                BRA1:    state <= (CO ^ backwards) ? BRA2 : DECODE;
                BRA2:    state <= DECODE;

                JMP0:    state <= JMP1;
                JMP1:    state <= DECODE; 

                JMPI0:   state <= JMPI1;
                JMPI1:   state <= JMP0;

                BRK0:    state <= BRK1;
                BRK1:    state <= BRK2;
                BRK2:    state <= BRK3;
                BRK3:    state <= JMP0;
            endcase
        end
    end
end

/*
 * Additional control signals
 */

always @(posedge clk)
     if( reset )
         res <= 1;
     else if( state == DECODE )
         res <= 0;

always @(posedge clk)
     if( state == DECODE && RDY )
        casex( IR )
                8'b0xx01010,    // ASLA, ROLA, LSRA, RORA
                8'b0xxxxx01,    // ORA, AND, EOR, ADC
                8'b100x10x0,    // DEY, TYA, TXA, TXS
                8'b1010xxx0,    // LDA/LDX/LDY 
                8'b10111010,    // TSX
                8'b1011x1x0,    // LDX/LDY
                8'b11001010,    // DEX
                8'b1x1xxx01,    // LDA, SBC
                8'bxxx01000:    // DEY, TAY, INY, INX
                                load_reg <= 1;

                default:        load_reg <= 0;
        endcase

always @(posedge clk)
     if( state == DECODE && RDY )
        casex( IR )
                8'b1110_1000,   // INX
                8'b1100_1010,   // DEX
                8'b101x_xx10:   // LDX, TAX, TSX
                                dst_reg <= SEL_X;

                8'b0x00_1000,   // PHP, PHA
                8'b1001_1010:   // TXS
                                dst_reg <= SEL_S;

                8'b1x00_1000,   // DEY, DEX
                8'b101x_x100,   // LDY
                8'b1010_x000:   // LDY #imm, TAY
                                dst_reg <= SEL_Y;

                default:        dst_reg <= SEL_A;
        endcase

always @(posedge clk)
     if( state == DECODE && RDY )
        casex( IR )
                8'b1011_1010:   // TSX 
                                src_reg <= SEL_S; 

                8'b100x_x110,   // STX
                8'b100x_1x10,   // TXA, TXS
                8'b1110_xx00,   // INX, CPX
                8'b1100_1010:   // DEX
                                src_reg <= SEL_X; 

                8'b100x_x100,   // STY
                8'b1001_1000,   // TYA
                8'b1100_xx00,   // CPY
                8'b1x00_1000:   // DEY, INY
                                src_reg <= SEL_Y;

                default:        src_reg <= SEL_A;
        endcase

always @(posedge clk) 
     if( state == DECODE && RDY )
        casex( IR )
                8'bxxx1_0001,   // INDY
                8'b10x1_x110,   // LDX/STX zpg/abs, Y
                8'bxxxx_1001:   // abs, Y
                                index_y <= 1;

                default:        index_y <= 0;
        endcase


always @(posedge clk)
     if( state == DECODE && RDY )
        casex( IR )
                8'b100x_x1x0,   // STX, STY
                8'b100x_xx01:   // STA
                                store <= 1;

                default:        store <= 0;

        endcase

always @(posedge clk )
     if( state == DECODE && RDY )
        casex( IR )
                8'b0xxx_x110,   // ASL, ROL, LSR, ROR
                8'b11xx_x110:   // DEC/INC 
                                write_back <= 1;

                default:        write_back <= 0;
        endcase


always @(posedge clk )
     if( state == DECODE && RDY )
        casex( IR )
                8'b101x_xxxx:   // LDA, LDX, LDY
                                load_only <= 1;
                default:        load_only <= 0;
        endcase

always @(posedge clk )
     if( state == DECODE && RDY )
        casex( IR )
                8'b111x_x110,   // INC 
                8'b11x0_1000:   // INX, INY
                                inc <= 1;

                default:        inc <= 0;
        endcase

always @(posedge clk )
     if( (state == DECODE || state == BRK0) && RDY )
        casex( IR )
                8'bx11x_xx01:   // SBC, ADC
                                adc_sbc <= 1;

                default:        adc_sbc <= 0;
        endcase

always @(posedge clk )
     if( (state == DECODE || state == BRK0) && RDY )
        casex( IR )
                8'b011x_xx01:   // ADC
                                adc_bcd <= D;

                default:        adc_bcd <= 0;
        endcase

always @(posedge clk )
     if( state == DECODE && RDY )
        casex( IR )
                8'b0xxx_x110,   // ASL, ROL, LSR, ROR (abs, absx, zpg, zpgx)
                8'b0xxx_1010:   // ASL, ROL, LSR, ROR (acc)
                                shift <= 1;

                default:        shift <= 0;
        endcase

always @(posedge clk )
     if( state == DECODE && RDY )
        casex( IR )
                8'b11x0_0x00,   // CPX, CPY (imm/zp)
                8'b11x0_1100,   // CPX, CPY (abs)
                8'b110x_xx01:   // CMP 
                                compare <= 1;

                default:        compare <= 0;
        endcase

always @(posedge clk )
     if( state == DECODE && RDY )
        casex( IR )
                8'b01xx_xx10:   // ROR, LSR
                                shift_right <= 1;

                default:        shift_right <= 0; 
        endcase

always @(posedge clk )
     if( state == DECODE && RDY )
        casex( IR )
                8'b0x1x_1010,   // ROL A, ROR A
                8'b0x1x_x110:   // ROR, ROL 
                                rotate <= 1;

                default:        rotate <= 0; 
        endcase

always @(posedge clk )
     if( state == DECODE && RDY )
        casex( IR )
                8'b00xx_xx10:   // ROL, ASL
                                op <= `OP_ROL;

                8'b0010_x100:   // BIT zp/abs   
                                op <= `OP_AND;

                8'b01xx_xx10:   // ROR, LSR
                                op <= `OP_A;

                8'b1000_1000,   // DEY
                8'b1100_1010,   // DEX 
                8'b110x_x110,   // DEC 
                8'b11xx_xx01,   // CMP, SBC
                8'b11x0_0x00,   // CPX, CPY (imm, zpg)
                8'b11x0_1100:   op <= `OP_SUB;

                8'b010x_xx01,   // EOR
                8'b00xx_xx01:   // ORA, AND
                                begin
                                    // Create the appropriate logic operation based on IR bits
                                    case({2'b11, IR[6:5]})
                                        `OP_AND: op <= `OP_AND;
                                        `OP_OR:  op <= `OP_OR;
                                        `OP_EOR: op <= `OP_EOR;
                                        default: op <= `OP_ADD;
                                    endcase
                                end
                
                default:        op <= `OP_ADD; 
        endcase

always @(posedge clk )
     if( state == DECODE && RDY )
        casex( IR )
                8'b0010_x100:   // BIT zp/abs   
                                bit_ins <= 1;

                default:        bit_ins <= 0; 
        endcase

/*
 * special instructions
 */
always @(posedge clk )
     if( state == DECODE && RDY ) begin
        php <= (IR == 8'h08);
        clc <= (IR == 8'h18);
        plp <= (IR == 8'h28);
        sec <= (IR == 8'h38);
        cli <= (IR == 8'h58);
        sei <= (IR == 8'h78);
        clv <= (IR == 8'hb8);
        cld <= (IR == 8'hd8);
        sed <= (IR == 8'hf8);
        brk <= (IR == 8'h00);
     end

always @(posedge clk)
    if( RDY )
        cond_code <= IR[7:5];

always @*
    case( cond_code )
            3'b000: cond_true = ~N;
            3'b001: cond_true = N;
            3'b010: cond_true = ~V;
            3'b011: cond_true = V;
            3'b100: cond_true = ~C;
            3'b101: cond_true = C;
            3'b110: cond_true = ~Z;
            3'b111: cond_true = Z;
    endcase


logic NMI_1 = 0;          // delayed NMI signal

always @(posedge clk)
    NMI_1 <= NMI;

always @(posedge clk )
    if( NMI_edge && state == BRK3 )
        NMI_edge <= 0;
    else if( NMI & ~NMI_1 )
        NMI_edge <= 1;

endmodule