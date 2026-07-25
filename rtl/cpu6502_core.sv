/*
 * 6502 core, rebuilt around a decode table.
 *
 * See docs/cpu-core.md. In short:
 *
 *   - The decode is `rtl/cpu6502_decode.sv`, one row per opcode. Nothing here
 *     pattern-matches on instruction bits except the branch condition, which
 *     is three bits of the opcode by construction.
 *   - The sequencer is a state per *addressing-mode step*, not per T-state.
 *     There are no dummy cycles: no read-modify-write dummy write, no
 *     un-indexed zero-page read, no page-cross penalty, no dummy stack access.
 *   - Cycle counts are therefore at or below NMOS everywhere, and well below it
 *     on implied instructions (1), pulls (2) and RTS (3).
 *
 * == The bus, and why the address is combinational ==
 *
 * `rtl/ram_async.sv` has a registered read port: the address presented in cycle
 * N is answered on DI in cycle N+1. So a core that registers its address pays a
 * second cycle on every data-dependent address - compute, present, receive -
 * and gets it back only by overlapping instructions, which is what phase 4 of
 * this change is for.
 *
 * Until that measurement exists, this core keeps one access per cycle and
 * attacks the critical path by making the DI -> AB route *narrow* instead: at
 * most an 8-bit adder and a small mux, against the 12-arm AB mux, DIMUX and
 * arbiter mux the previous core routed a byte through. Every address that does
 * not depend on DI comes straight from a register.
 *
 * == Cycle model ==
 *
 * In state S during cycle k, `ab` is what this cycle asks memory for, and `di`
 * is the answer to what the *previous* cycle asked. So each state consumes the
 * byte its predecessor requested and requests the byte its successor will
 * consume. The last step of every instruction requests the next opcode, which
 * S_DECODE then consumes - so S_DECODE is exactly the retire point the
 * conformance harness looks for.
 *
 * Hugo Sereno, <bytter@gmail.com>
 */

`include "cpu6502_decode.sv"

/* verilator lint_off DECLFILENAME */

module cpu6502_core (
    input  logic        clk,
    input  logic        reset,
    output logic [15:0] AB,
    input  logic [7:0]  DI,
    output logic [7:0]  DO,
    output logic        WE,
    input  logic        IRQ,
    input  logic        NMI,
    input  logic        RDY,

    // ---- Test interface -----------------------------------------------
    // Architectural state, plus the two markers a per-instruction test suite
    // needs. Read-only and combinational, so leaving them unconnected costs
    // nothing: synthesis trims them. `dbg_pc` is the address the opcode being
    // decoded came from, and is only meaningful while `dbg_sync` is high.
    output logic [15:0] dbg_pc,
    output logic [7:0]  dbg_a,
    output logic [7:0]  dbg_x,
    output logic [7:0]  dbg_y,
    output logic [7:0]  dbg_s,
    output logic [7:0]  dbg_p,
    output logic        dbg_sync,     // this cycle decodes a fetched opcode
    output logic        dbg_trap,     // an undefined opcode stopped the core
    output logic [7:0]  dbg_trap_ir,
    output logic [15:0] dbg_trap_pc
);

    // ---- holding the data bus across a stall -------------------------
    //
    // The RAM's read port is registered and keeps clocking while the CPU is
    // stalled, so the byte answering the request issued one cycle ago is on DI
    // for exactly one cycle and is then overwritten by the answer to the
    // address the stalled core is still presenting. Without capturing it, RDY
    // silently corrupts the instruction in flight - which the 65x02 suite with
    // --stall demonstrates in 75% of cases.
    //
    // So: latch DI on the first stalled cycle, when it is still valid, and use
    // the latched copy for the rest of the stall and for the cycle that
    // resumes. This is gate T7's requirement that every access happen exactly
    // once, in order.
    logic [7:0] di_hold;
    logic       di_held;
    wire  [7:0] di_eff = di_held ? di_hold : DI;

    always_ff @(posedge clk) begin
        if (reset) begin
            di_held <= 1'b0;
            di_hold <= 8'h00;
        end else if (!RDY && !di_held) begin
            di_hold <= DI;          // still the answer to the pending request
            di_held <= 1'b1;
        end else if (RDY) begin
            di_held <= 1'b0;
        end
    end

    // ---- architectural state ----
    state_t      st, st_n;
    logic [15:0] pc, pc_n;
    logic [7:0]  a, a_n, x, x_n, y, y_n, s, s_n;
    logic        fn, fn_n, fv, fv_n, fd, fd_n;
    logic        fi, fi_n, fz, fz_n, fc, fc_n;

    // ---- working state ----
    logic [7:0]  ir, ir_n;      // the opcode under execution
    logic [7:0]  adl, adl_n;    // low byte of an address being assembled
    logic [7:0]  zpa, zpa_n;    // zero-page pointer address, for (zp,X)/(zp),Y
    logic        cy, cy_n;      // carry out of the index add
    logic [15:0] adr, adr_n;    // effective address, held for an RMW writeback
    logic        trapped, trapped_n;
    logic [7:0]  trap_ir, trap_ir_n;
    logic [15:0] trap_pc, trap_pc_n;

    // ---- decode ----
    //
    // Phase 2 measured the critical path of the previous arrangement: it began
    // at the memory read data and ran di_eff -> combinational decode -> ALU select
    // -> carry chain -> C flag, 14.12 ns of logic, and cost 13 MHz against the
    // core it replaced. The decode is now split in two.
    //
    //   dec_c  combinational decode of the byte arriving right now. Used ONLY
    //          in S_DECODE, and only to pick the next state and the register a
    //          push reads. Shallow: di_eff -> table -> a state mux.
    //   dec_r  the same row, registered. Everything that reaches the ALU, the
    //          flags or a store uses this, so those paths start at a flop.
    //
    // The price is that an implied instruction can no longer execute in the
    // cycle its opcode arrives, because its ALU control is not registered yet.
    // It gets S_IMP, and goes from 1 cycle to 2 - the same as NMOS. Measured
    // over the corpus that is 13.2% of instructions and moves static CPI from
    // 2.6234 to 2.7552, still well inside the 3.0334 of the core being replaced.
    dec_t dec_c;
    dec_t dec_r, dec_r_n;
    state_t dec_c_st1;
    cpu6502_decode u_dec (.ir(di_eff), .d(dec_c), .st1(dec_c_st1));

    wire is_store = (dec_r.dst == D_MEM) && (dec_r.op == OP_PASS);
    wire is_rmw   = (dec_r.dst == D_MEM) && (dec_r.op != OP_PASS);

    wire [7:0] p_byte = {fn, fv, 2'b11, fd, fi, fz, fc};

    logic [7:0] ra_val;
    always_comb begin
        case (dec_r.ra)
            R_A:     ra_val = a;
            R_X:     ra_val = x;
            R_Y:     ra_val = y;
            R_S:     ra_val = s;
            R_P:     ra_val = p_byte;
            default: ra_val = 8'h00;
        endcase
    end

    // The index register for an indexed mode.
    wire [7:0] idx = (dec_r.am == AM_ZPY || dec_r.am == AM_ABSY) ? y : x;

    // ---- ALU ----------------------------------------------------------
    //
    // One case over the operation, never over instruction bits. The BCD
    // adjust is inside this block, so it is computed from the pre-flop carry
    // and half carry and lands in the destination register on the same edge as
    // the binary result - not as adders hanging off an already-flopped sum.

    logic [7:0] opb;
    assign opb = (st == S_IMP) ? ra_val : di_eff;

    logic [7:0] alu_r;
    logic       alu_n, alu_v, alu_z, alu_c, alu_i, alu_d;

    // ADC, SBC and CMP all went through their own 9-bit adder. A 6502 needs
    // one: subtraction is addition of the inverted operand, and the three
    // differ only in whether the operand is inverted and what comes in as
    // carry.
    //
    //   ADC  invert 0, carry in C     sum = A + M + C
    //   SBC  invert 1, carry in C     sum = A + ~M + C   = A - M - (1-C)
    //   CMP  invert 1, carry in 1     sum = A + ~M + 1   = A - M
    //
    // Carry out is the carry flag directly in all three - for the subtracting
    // pair, "no borrow" is exactly "carry out set", so the inversion that used
    // to sit on `alu_c` goes away too.
    //
    // Overflow falls out of the same trick. ADC wants ~(A^M) and SBC wants
    // (A^M); with the inverted operand, ~(A ^ opb_eff) is the first when
    // invert is 0 and the second when it is 1, so one expression serves both.
    logic       add_inv, add_cin;
    logic [7:0] opb_eff;
    logic [8:0] sum;
    logic       ovf;
    assign opb_eff = opb ^ {8{add_inv}};
    assign sum     = {1'b0, ra_val} + {1'b0, opb_eff} + {8'd0, add_cin};
    assign ovf     = (~(ra_val ^ opb_eff) & (ra_val ^ sum[7:0]) & 8'h80) != 8'h00;

    // ADD and SUB are the same adder with the carry decided by the opcode
    // instead of by a preceding clc/sec - which is the whole point of them.
    always_comb begin
        add_inv = (dec_r.op == OP_SBC) || (dec_r.op == OP_CMP)
               || (dec_r.op == OP_SUB);
        case (dec_r.op)
            OP_CMP:  add_cin = 1'b1;
            OP_ADD:  add_cin = 1'b0;   // no carry in: clc is implied
            OP_SUB:  add_cin = 1'b1;   // no borrow in: sec is implied
            default: add_cin = fc;
        endcase
    end

    logic [5:0] dal, dal2, dah, dah2;
    logic [4:0] sal, sal2, sah, sah2;

    always_comb begin

        dal  = {2'b0, ra_val[3:0]} + {2'b0, opb[3:0]} + {5'b0, fc};
        dal2 = (dal > 6'd9) ? (dal + 6'd6) : dal;
        dah  = {2'b0, ra_val[7:4]} + {2'b0, opb[7:4]} + {5'b0, (dal2 > 6'd15)};
        dah2 = (dah > 6'd9) ? (dah + 6'd6) : dah;

        sal  = {1'b0, ra_val[3:0]} - {1'b0, opb[3:0]} - {4'b0, ~fc};
        sal2 = sal[4] ? (sal - 5'd6) : sal;
        sah  = {1'b0, ra_val[7:4]} - {1'b0, opb[7:4]} - {4'b0, sal[4]};
        sah2 = sah[4] ? (sah - 5'd6) : sah;

        // Defaults are OP_PASS: the operand straight through, N and Z from it.
        alu_r = opb;
        alu_n = opb[7];
        alu_z = (opb == 8'h00);
        alu_v = fv;
        alu_c = fc;
        alu_i = fi;
        alu_d = fd;

        case (dec_r.op)
            OP_ORA: begin alu_r = ra_val | opb; alu_n = alu_r[7]; alu_z = (alu_r == 0); end
            OP_AND: begin alu_r = ra_val & opb; alu_n = alu_r[7]; alu_z = (alu_r == 0); end
            OP_EOR: begin alu_r = ra_val ^ opb; alu_n = alu_r[7]; alu_z = (alu_r == 0); end

            OP_ADC: begin
                // Z comes from the binary sum in both modes, which is what NMOS
                // does and what the suite records. N and V in decimal mode are
                // undocumented and are not contractual.
                alu_z = (sum[7:0] == 8'h00);
                alu_v = ovf;
                if (fd) begin
                    alu_r = {dah2[3:0], dal2[3:0]};
                    alu_c = (dah2 > 6'd15);
                    alu_n = dah2[3];
                end else begin
                    alu_r = sum[7:0];
                    alu_c = sum[8];
                    alu_n = sum[7];
                end
            end

            OP_SBC: begin
                // Every flag is the binary result's, in both modes: on NMOS only
                // the result byte differs in decimal. Nothing here is masked.
                alu_n = sum[7];
                alu_z = (sum[7:0] == 8'h00);
                alu_v = ovf;
                alu_c = sum[8];
                alu_r = fd ? {sah2[3:0], sal2[3:0]} : sum[7:0];
            end

            // Binary only, by design: these are for addresses and counters,
            // where a decimal adjust is never wanted. ADC/SBC keep decimal.
            OP_ADD, OP_SUB: begin
                alu_r = sum[7:0];
                alu_n = sum[7];
                alu_z = (sum[7:0] == 8'h00);
                alu_v = ovf;
                alu_c = sum[8];
            end

            OP_CMP: begin
                alu_n = sum[7];
                alu_z = (sum[7:0] == 8'h00);
                alu_c = sum[8];
            end

            OP_BIT: begin
                alu_n = opb[7];
                alu_v = opb[6];
                alu_z = ((ra_val & opb) == 8'h00);
            end

            OP_ASL: begin alu_c = opb[7]; alu_r = {opb[6:0], 1'b0};
                          alu_n = alu_r[7]; alu_z = (alu_r == 0); end
            OP_LSR: begin alu_c = opb[0]; alu_r = {1'b0, opb[7:1]};
                          alu_n = alu_r[7]; alu_z = (alu_r == 0); end
            OP_ROL: begin alu_c = opb[7]; alu_r = {opb[6:0], fc};
                          alu_n = alu_r[7]; alu_z = (alu_r == 0); end
            OP_ROR: begin alu_c = opb[0]; alu_r = {fc, opb[7:1]};
                          alu_n = alu_r[7]; alu_z = (alu_r == 0); end

            OP_INC: begin alu_r = opb + 8'd1; alu_n = alu_r[7]; alu_z = (alu_r == 0); end
            OP_DEC: begin alu_r = opb - 8'd1; alu_n = alu_r[7]; alu_z = (alu_r == 0); end

            OP_CLC: alu_c = 1'b0;
            OP_SEC: alu_c = 1'b1;
            OP_CLI: alu_i = 1'b0;
            OP_SEI: alu_i = 1'b1;
            OP_CLV: alu_v = 1'b0;
            OP_CLD: alu_d = 1'b0;
            OP_SED: alu_d = 1'b1;
            default: ;
        endcase
    end

    // ---- branch condition ---------------------------------------------
    logic cond;
    always_comb begin
        case (ir[7:6])
            2'b00: cond = fn;
            2'b01: cond = fv;
            2'b10: cond = fc;
            default: cond = fz;
        endcase
        cond = (cond == ir[5]);
    end

    // ---- sequencer ----------------------------------------------------

    // PC control. In every arm of the sequencer that moves PC, the new PC is
    // the address bus plus one - because this core always drives AB with the
    // address it is about to consume, and PC trails it. Verified over all 16
    // arms that touch PC. So instead of ~20 arms each muxing a 16-bit
    // expression into `pc_n`, an arm says only *whether* PC moves, and one
    // incrementer does the work.
    //
    // BRK's decode cycle is the single exception: it advances PC while AB goes
    // to the stack, so it asks for the increment to come from PC instead.
    logic        pc_upd;      // PC moves this cycle
    logic        pc_from_pc;  // ... incrementing PC rather than the address bus
    logic        commit;      // write the ALU result and flags this cycle
    logic [15:0] ea;          // effective address, once fully assembled
    logic        ea_go;       // ... and it is ready this cycle
    logic [15:0] ab_c;
    logic [7:0]  do_c;
    logic        we_c;

    wire [7:0]  push_val = (dec_c.ra == R_P) ? p_byte : a;
    wire [15:0] brk_pc = pc + 16'd1;   // BRK pushes the byte after its signature

    always_comb begin
        st_n       = st;
        pc_upd     = 1'b0;
        pc_from_pc = 1'b0;
        a_n       = a;  x_n = x;  y_n = y;  s_n = s;
        fn_n     = fn; fv_n = fv; fd_n = fd;
        fi_n     = fi;  fz_n = fz; fc_n = fc;
        ir_n      = ir;
        adl_n     = adl;
        zpa_n     = zpa;
        cy_n      = cy;
        adr_n     = adr;
        trap_ir_n = trap_ir;
        trap_pc_n = trap_pc;
        trapped_n = trapped;
        dec_r_n   = dec_r;

        ab_c   = pc;
        do_c   = 8'h00;
        we_c   = 1'b0;
        commit = 1'b0;
        ea     = 16'h0000;
        ea_go  = 1'b0;

        case (st)
        // ---- reset: read the vector, start executing. No stack traffic. ----
        S_RST0: begin ab_c = 16'hFFFC; st_n = S_RST1; end
        S_RST1: begin adl_n = di_eff; ab_c = 16'hFFFD; st_n = S_RST2; end
        S_RST2: begin
            ab_c = {di_eff, adl};
            pc_upd = 1'b1;
            st_n = S_DECODE;
        end

        // ---- decode: di_eff is the opcode, PC already points past it ----
        S_DECODE: begin
            ir_n = di_eff;
            dec_r_n = dec_c;
            // The next state comes straight out of the table. The case below
            // only produces this cycle's side effects - the address it drives,
            // whether it writes, and what it does to S - so no logic sits
            // between the decode and the state register.
            st_n = dec_c_st1;
            case (dec_c.am)
                // Executes in S_IMP, one cycle later, so its ALU control comes
                // from a flop. The opcode fetch is issued here and re-issued
                // there: the same address twice, which costs nothing but a
                // cycle and keeps the access footprint unchanged.
                AM_IMP, AM_ACC: begin
                    ab_c = pc;
                end
                AM_IMM:  begin ab_c = pc; pc_upd = 1'b1;  end
                AM_ZP:   begin ab_c = pc; pc_upd = 1'b1;    end
                AM_ZPX,
                AM_ZPY:  begin ab_c = pc; pc_upd = 1'b1;   end
                AM_ABS,
                AM_JMPA,
                AM_JMPI: begin ab_c = pc; pc_upd = 1'b1;  end
                AM_ABSX,
                AM_ABSY: begin ab_c = pc; pc_upd = 1'b1; end
                AM_INDX: begin ab_c = pc; pc_upd = 1'b1; end
                AM_INDY: begin ab_c = pc; pc_upd = 1'b1; end
                AM_REL:  begin ab_c = pc; pc_upd = 1'b1; end
                AM_JSR:  begin ab_c = pc; pc_upd = 1'b1;  end

                AM_PUSH: begin
                    ab_c = {8'h01, s}; we_c = 1'b1; do_c = push_val;
                    s_n = s - 8'd1;
                end
                AM_PULL: begin
                    ab_c = {8'h01, s + 8'd1}; s_n = s + 8'd1;
                end
                AM_RTS:  begin
                    ab_c = {8'h01, s + 8'd1}; s_n = s + 8'd1;
                end
                AM_RTI:  begin
                    ab_c = {8'h01, s + 8'd1}; s_n = s + 8'd1;
                end
                AM_BRK:  begin
                    pc_upd = 1'b1; pc_from_pc = 1'b1;              // skip the signature byte
                    ab_c = {8'h01, s}; we_c = 1'b1; do_c = brk_pc[15:8];
                    s_n = s - 8'd1;
                end
                default: begin                  // AM_TRAP
                    // Inert, sticky and recoverable: the opcode and its address
                    // are latched and dbg_trap stays asserted, but the core
                    // continues as if the byte were a NOP. Halting here would
                    // be an unrecoverable state, which the spec forbids.
                    trap_ir_n  = di_eff;
                    trap_pc_n  = pc - 16'd1;
                    trapped_n  = 1'b1;
                    ab_c = pc; pc_upd = 1'b1;
                end
            endcase
        end

        // ---- operand address assembly ----
        S_ZP:  begin ea = {8'h00, di_eff};       ea_go = 1'b1; end
        S_ZPI: begin ea = {8'h00, di_eff + idx}; ea_go = 1'b1; end

        S_ABS0: begin adl_n = di_eff; ab_c = pc; pc_upd = 1'b1; st_n = S_ABS1; end
        S_ABS1: begin
            if (dec_r.am == AM_JMPA) begin
                ab_c = {di_eff, adl}; pc_upd = 1'b1; st_n = S_DECODE;
            end else if (dec_r.am == AM_JMPI) begin
                ab_c = {di_eff, adl}; adr_n = {di_eff, adl}; st_n = S_JMPI0;
            end else begin
                ea = {di_eff, adl}; ea_go = 1'b1;
            end
        end

        S_ABSI0: begin
            {cy_n, adl_n} = {1'b0, di_eff} + {1'b0, idx};
            ab_c = pc; pc_upd = 1'b1; st_n = S_ABSI1;
        end
        S_ABSI1: begin ea = {di_eff + {7'b0, cy}, adl}; ea_go = 1'b1; end

        S_INDX0: begin zpa_n = di_eff + x; ab_c = {8'h00, di_eff + x}; st_n = S_INDX1; end
        S_INDX1: begin adl_n = di_eff; ab_c = {8'h00, zpa + 8'd1}; st_n = S_INDX2; end
        S_INDX2: begin ea = {di_eff, adl}; ea_go = 1'b1; end

        S_INDY0: begin zpa_n = di_eff; ab_c = {8'h00, di_eff}; st_n = S_INDY1; end
        S_INDY1: begin
            {cy_n, adl_n} = {1'b0, di_eff} + {1'b0, y};
            ab_c = {8'h00, zpa + 8'd1}; st_n = S_INDY2;
        end
        S_INDY2: begin ea = {di_eff + {7'b0, cy}, adl}; ea_go = 1'b1; end

        // JMP (abs) crosses the page when the pointer ends in $FF. NMOS wraps
        // within the page; that bug is not reproduced here - see
        // docs/cpu-core.md.
        S_JMPI0: begin adl_n = di_eff; ab_c = adr + 16'd1; st_n = S_JMPI1; end
        S_JMPI1: begin
            ab_c = {di_eff, adl}; pc_upd = 1'b1; st_n = S_DECODE;
        end

        // ---- MOV: memory to memory, touching no register and no flag ----
        // The destination address is held in `adr` and the data comes straight
        // off the bus, so nothing passes through A.
        S_MOVZ0: begin
            adr_n = {8'h00, di_eff}; ab_c = pc; pc_upd = 1'b1; st_n = S_MOVZ1;
        end
        S_MOVZ1: begin
            ab_c = adr; we_c = 1'b1; do_c = di_eff; st_n = S_LAST;
        end

        S_MOVA0: begin adl_n = di_eff; ab_c = pc; pc_upd = 1'b1; st_n = S_MOVA1; end
        S_MOVA1: begin
            adr_n = {di_eff, adl}; ab_c = pc; pc_upd = 1'b1; st_n = S_MOVA2;
        end
        S_MOVA2: begin
            ab_c = adr; we_c = 1'b1; do_c = di_eff; st_n = S_LAST;
        end

        // MOV zp, abs,X - the indexed table read the corpus does 24 times.
        // No page-cross penalty, because this core has none anywhere.
        S_MVX0: begin zpa_n = di_eff; ab_c = pc; pc_upd = 1'b1; st_n = S_MVX1; end
        S_MVX1: begin
            {cy_n, adl_n} = {1'b0, di_eff} + {1'b0, x};
            ab_c = pc; pc_upd = 1'b1; st_n = S_MVX2;
        end
        S_MVX2: begin ab_c = {di_eff + {7'b0, cy}, adl}; st_n = S_MVX3; end
        S_MVX3: begin
            ab_c = {8'h00, zpa}; we_c = 1'b1; do_c = di_eff; st_n = S_LAST;
        end

        // ---- execute ----
        S_EXEC: begin
            commit = 1'b1;
            if (dec_r.op == OP_TRAP) begin
                trap_ir_n = di_eff;         // the immediate, not the opcode
                trap_pc_n = pc - 16'd2;
                trapped_n = 1'b1;
            end
            ab_c = pc; pc_upd = 1'b1; st_n = S_DECODE;
        end
        S_RMW: begin
            commit = 1'b1;                       // flags only: dst is D_MEM
            ab_c = adr; we_c = 1'b1; do_c = alu_r;
            st_n = S_LAST;
        end
        S_LAST: begin ab_c = pc; pc_upd = 1'b1; st_n = S_DECODE; end

        // Implied and accumulator instructions, one cycle after their opcode
        // arrived. Every ALU input here comes from a register.
        S_IMP: begin
            commit = 1'b1;
            ab_c = pc; pc_upd = 1'b1; st_n = S_DECODE;
        end

        S_PULL: begin
            if (dec_r.dst == D_P) begin
                {fn_n, fv_n, fd_n, fi_n, fz_n, fc_n} =
                    {di_eff[7], di_eff[6], di_eff[3], di_eff[2], di_eff[1], di_eff[0]};
            end else begin
                commit = 1'b1;
            end
            ab_c = pc; pc_upd = 1'b1; st_n = S_DECODE;
        end

        // ---- branches: 2 cycles whether taken or not, no page penalty ----
        S_BRANCH: begin
            if (cond) begin
                ab_c = pc + {{8{di_eff[7]}}, di_eff};
                pc_upd = 1'b1;
            end else begin
                ab_c = pc; pc_upd = 1'b1;
            end
            st_n = S_DECODE;
        end

        // ---- JSR / RTS / RTI / BRK ----
        S_JSR0: begin
            adl_n = di_eff;
            ab_c = {8'h01, s}; we_c = 1'b1; do_c = pc[15:8];
            s_n = s - 8'd1; st_n = S_JSR1;
        end
        S_JSR1: begin
            ab_c = {8'h01, s}; we_c = 1'b1; do_c = pc[7:0];
            s_n = s - 8'd1; st_n = S_JSR2;
        end
        S_JSR2: begin ab_c = pc; pc_upd = 1'b1; st_n = S_JSR3; end
        S_JSR3: begin
            ab_c = {di_eff, adl}; pc_upd = 1'b1; st_n = S_DECODE;
        end

        S_RTS0: begin
            adl_n = di_eff; ab_c = {8'h01, s + 8'd1}; s_n = s + 8'd1; st_n = S_RTS1;
        end
        S_RTS1: begin
            ab_c = {di_eff, adl} + 16'd1;
            pc_upd = 1'b1;
            st_n = S_DECODE;
        end

        S_RTI0: begin
            {fn_n, fv_n, fd_n, fi_n, fz_n, fc_n} =
                {di_eff[7], di_eff[6], di_eff[3], di_eff[2], di_eff[1], di_eff[0]};
            ab_c = {8'h01, s + 8'd1}; s_n = s + 8'd1; st_n = S_RTI1;
        end
        S_RTI1: begin
            adl_n = di_eff; ab_c = {8'h01, s + 8'd1}; s_n = s + 8'd1; st_n = S_RTI2;
        end
        S_RTI2: begin
            ab_c = {di_eff, adl}; pc_upd = 1'b1; st_n = S_DECODE;
        end

        S_BRK0: begin
            ab_c = {8'h01, s}; we_c = 1'b1; do_c = pc[7:0];
            s_n = s - 8'd1; st_n = S_BRK1;
        end
        S_BRK1: begin
            ab_c = {8'h01, s}; we_c = 1'b1; do_c = p_byte;  // B set, as BRK does
            s_n = s - 8'd1; fi_n = 1'b1; st_n = S_BRK2;
        end
        S_BRK2: begin ab_c = 16'hFFFE; st_n = S_BRK3; end
        S_BRK3: begin adl_n = di_eff; ab_c = 16'hFFFF; st_n = S_BRK4; end
        S_BRK4: begin
            ab_c = {di_eff, adl}; pc_upd = 1'b1; st_n = S_DECODE;
        end

        default: begin ab_c = pc; st_n = S_DECODE; end
        endcase

        // The operand access, shared by every addressing mode that assembles a
        // full effective address. This is the only place a store or an RMW
        // read is issued, so adding an addressing mode means producing `ea`,
        // not repeating this.
        if (ea_go) begin
            adr_n = ea;
            ab_c  = ea;
            if (is_store) begin
                we_c = 1'b1; do_c = ra_val; st_n = S_LAST;
            end else begin
                // Cast: iverilog will not take a ternary of two enum members.
                if (is_rmw) st_n = S_RMW; else st_n = S_EXEC;
            end
        end

        // One incrementer and a 2:1 mux, in place of the twenty-arm 16-bit mux
        // this used to be. Placed after the shared operand-access block, since
        // that block is the last thing that can move `ab_c`.
        pc_n = pc_upd ? ((pc_from_pc ? pc : ab_c) + 16'd1) : pc;

        if (commit) begin
            case (dec_r.dst)
                D_A: a_n = alu_r;
                D_X: x_n = alu_r;
                D_Y: y_n = alu_r;
                D_S: s_n = alu_r;
                default: ;                      // D_MEM, D_NONE: no register
            endcase
            if (dec_r.fw[5]) fn_n = alu_n;
            if (dec_r.fw[4]) fv_n = alu_v;
            if (dec_r.fw[3]) fd_n = alu_d;
            if (dec_r.fw[2]) fi_n = alu_i;
            if (dec_r.fw[1]) fz_n = alu_z;
            if (dec_r.fw[0]) fc_n = alu_c;
        end
    end

    // ---- registers ----------------------------------------------------
    // RDY holds everything, including the write: `we` is gated so a stalled
    // write is presented once, when the core is released, rather than
    // repeatedly while it waits.
    always_ff @(posedge clk) begin
        if (reset) begin
            st  <= S_RST0;
            pc  <= 16'h0000;
            a   <= 8'h00; x <= 8'h00; y <= 8'h00; s <= 8'hFD;
            fn <= 1'b0; fv <= 1'b0; fd <= 1'b0;
            fi  <= 1'b1; fz <= 1'b0; fc <= 1'b0;
            ir  <= 8'h00;
            adl <= 8'h00; zpa <= 8'h00; cy <= 1'b0; adr <= 16'h0000;
            trap_ir <= 8'h00; trap_pc <= 16'h0000; trapped <= 1'b0;
            dec_r <= '0;
        end else if (RDY) begin
            st  <= st_n;
            pc  <= pc_n;
            a   <= a_n; x <= x_n; y <= y_n; s <= s_n;
            fn <= fn_n; fv <= fv_n; fd <= fd_n;
            fi  <= fi_n; fz <= fz_n; fc <= fc_n;
            ir  <= ir_n;
            adl <= adl_n; zpa <= zpa_n; cy <= cy_n; adr <= adr_n;
            trap_ir <= trap_ir_n; trap_pc <= trap_pc_n;
            trapped <= trapped_n; dec_r <= dec_r_n;
        end
    end

    assign AB = ab_c;
    assign DO = do_c;
    assign WE = we_c & RDY;

    assign dbg_pc      = pc - 16'd1;
    assign dbg_a       = a;
    assign dbg_x       = x;
    assign dbg_y       = y;
    assign dbg_s       = s;
    assign dbg_p       = p_byte;
    assign dbg_sync    = (st == S_DECODE);
    assign dbg_trap    = trapped;
    assign dbg_trap_ir = trap_ir;
    assign dbg_trap_pc = trap_pc;

    // IRQ and NMI are accepted but not yet acted on: refactor-cpu-core task 5.x
    // adds the interrupt path, and 65x02 does not cover it at all.
    wire _unused = &{1'b0, IRQ, NMI, 1'b0};

endmodule

/* verilator lint_on DECLFILENAME */
