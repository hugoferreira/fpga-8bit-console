/*
 * Directed interrupt tests - refactor-cpu-core gate T3.
 *
 * The 65x02 conformance suite executes one instruction per case with both
 * interrupt lines low, so it says nothing at all about this path. Everything
 * that is known to work about IRQ/NMI entry, priority, masking, the vectors,
 * the B-flag distinction and RTI is known from here.
 *
 * The memory model matches rtl/ram_async.sv: a registered read port, so the
 * address presented in cycle N is answered on DI in cycle N+1. Programs are
 * installed directly into the array rather than loaded from a hex file, so a
 * case is a dozen lines rather than a build step. `load` fills memory and
 * holds reset; the case writes its program; `start` releases reset. Writing
 * the program after the core is already fetching would be a race with it.
 *
 * Hugo Sereno, <bytter@gmail.com>
 */

`ifndef SIMULATION
`define SIMULATION 1
`endif

`timescale 1ns/1ps

module cpu6502_irq_tb();

    bit         clk = 0;
    bit         reset = 1;
    bit         RDY = 1;
    bit         IRQ = 0;
    bit         NMI = 0;

    wire [15:0] AB;
    wire [7:0]  DO;
    wire        WE;

    wire [15:0] dbg_pc;
    wire [7:0]  dbg_a, dbg_x, dbg_y, dbg_s, dbg_p;
    wire        dbg_sync, dbg_trap;

    // ---- memory: registered read, ram_async semantics ----
    logic [7:0] mem [0:65535];
    logic [7:0] dout_r;
    always_ff @(posedge clk) begin
        if (WE) mem[AB] <= DO;
        else    dout_r  <= mem[AB];
    end
    wire [7:0] DI = dout_r;

    cpu6502_core dut (
        .clk(clk), .reset(reset),
        .AB(AB), .DI(DI), .DO(DO), .WE(WE), .WE_PEND(),
        .IRQ(IRQ), .NMI(NMI), .RDY(RDY),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_x(dbg_x), .dbg_y(dbg_y),
        .dbg_s(dbg_s), .dbg_p(dbg_p), .dbg_b(),
        .dbg_sync(dbg_sync), .dbg_trap(dbg_trap),
        .dbg_trap_ir(), .dbg_trap_pc()
    );

    always #5 clk = ~clk;

    localparam logic [7:0] OP_BRK = 8'h00, OP_RTI = 8'h40, OP_JMP = 8'h4C,
                           OP_CLI = 8'h58, OP_LDA = 8'hA9,
                           OP_NOP = 8'hEA, OP_WAI = 8'hCB;

    localparam logic [15:0] MAIN = 16'h0300, HIRQ = 16'h0400, HNMI = 16'h0500;

    int    failures = 0;
    string phase = "";

    task automatic ck(input bit good, input string what);
        if (!good) begin
            failures = failures + 1;
            $display("  FAIL  [%s] %s", phase, what);
        end
    endtask

    task automatic ck_eq16(input logic [15:0] got, exp, input string what);
        if (got !== exp) begin
            failures = failures + 1;
            $display("  FAIL  [%s] %s: got $%04X, expected $%04X",
                     phase, what, got, exp);
        end
    endtask

    task automatic ck_eq8(input logic [7:0] got, exp, input string what);
        if (got !== exp) begin
            failures = failures + 1;
            $display("  FAIL  [%s] %s: got $%02X, expected $%02X",
                     phase, what, got, exp);
        end
    endtask

    // A cycle boundary, sampled after the non-blocking updates have settled,
    // so what is read here is the state the edge produced.
    int cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    task automatic tick();
        begin @(posedge clk); #1; end
    endtask

    // Advance to the next instruction boundary. An interrupt entry is NOT one
    // - dbg_sync excludes it - so this lands on the handler's first opcode,
    // not on the byte the entry discarded.
    //
    // "Next" is by cycle number rather than "tick, then look", because
    // pulse_irq costs a clock and that clock is sometimes itself the boundary:
    // waking from WAI puts the core in S_DECODE on the very cycle the pulse is
    // driven, and a helper that stepped first would walk straight past it.
    // `limit` bounds the wait so a core that never retires fails the case
    // instead of hanging the run.
    int last_sync_cyc = -1;

    task automatic wait_sync(input int limit = 400);
        int n;
        begin
            n = 0;
            while (!(dbg_sync && cyc != last_sync_cyc) && n < limit) begin
                tick(); n = n + 1;
            end
            ck(dbg_sync, "no instruction boundary within the cycle limit");
            last_sync_cyc = cyc;
        end
    endtask

    task automatic pulse_irq();
        begin IRQ = 1; tick(); IRQ = 0; end
    endtask

    task automatic pulse_nmi();
        begin NMI = 1; tick(); NMI = 0; end
    endtask

    // ---- a fresh machine: vectors, handlers, reset held ----
    task automatic load(input string name);
        int i;
        begin
            phase = name;
            $display("== %s", name);
            for (i = 0; i < 65536; i = i + 1) mem[i] = OP_NOP;

            // Handlers: bare RTI. A case that needs more overwrites them.
            mem[HIRQ] = OP_RTI;
            mem[HNMI] = OP_RTI;

            mem[16'hFFFA] = HNMI[7:0];  mem[16'hFFFB] = HNMI[15:8];
            mem[16'hFFFC] = MAIN[7:0];  mem[16'hFFFD] = MAIN[15:8];
            mem[16'hFFFE] = HIRQ[7:0];  mem[16'hFFFF] = HIRQ[15:8];

            // A main loop that stays put, so "where is the core" is a question
            // about interrupts and not about falling off the end.
            mem[MAIN + 16'd16] = OP_JMP;
            mem[MAIN + 16'd17] = MAIN[7:0];
            mem[MAIN + 16'd18] = MAIN[15:8];

            reset = 1; IRQ = 0; NMI = 0; RDY = 1;
            repeat (4) tick();
        end
    endtask

    task automatic start();
        begin
            reset = 0;
            wait_sync();                   // through the reset vector fetch
            ck_eq16(dbg_pc, MAIN, "reset vector honoured");
        end
    endtask

    // The frame a three-push entry leaves behind, read straight out of memory.
    // S starts at $FD, so the pushes land at $01FD, $01FC, $01FB.
    task automatic check_frame(input logic [15:0] ret, input bit from_brk);
        begin
            ck_eq8(mem[16'h01FD], ret[15:8], "pushed PCH");
            ck_eq8(mem[16'h01FC], ret[7:0],  "pushed PCL");
            ck_eq8(dbg_s, 8'hFA, "S after three pushes");
            ck(mem[16'h01FB][4] == from_brk,
               from_brk ? "pushed P has B set (BRK)"
                        : "pushed P has B clear (hardware)");
            ck(mem[16'h01FB][5] == 1'b1, "pushed P has bit 5 set");
            ck(dbg_p[2] == 1'b1, "I is set on the handler's first cycle");
        end
    endtask

    initial begin
        $dumpfile("build/cpu6502_irq.vcd");
        $dumpvars(0, cpu6502_irq_tb);

        // ---------------------------------------------------------------
        load("IRQ is taken at the next boundary when I is clear");
        mem[MAIN] = OP_CLI;
        start();
        wait_sync();                       // CLI retires; I is now clear
        ck(dbg_p[2] === 1'b0, "CLI cleared I");
        // The request lands one cycle into the NOP at $0301, too late for that
        // boundary, so the entry is at the next one - and the NOP has retired.
        pulse_irq();
        wait_sync();
        ck_eq16(dbg_pc, HIRQ, "entered the IRQ handler");
        // The instruction at the return address has NOT run: it is the opcode
        // the entry fetched and discarded.
        check_frame(MAIN + 16'd2, 1'b0);
        wait_sync();                       // the handler's RTI
        ck_eq16(dbg_pc, MAIN + 16'd2, "RTI resumed at the interrupted opcode");
        ck(dbg_p[2] === 1'b0, "RTI restored I clear");
        ck_eq8(dbg_s, 8'hFD, "RTI unwound the frame");

        // ---------------------------------------------------------------
        load("IRQ is deferred while I is set, and taken after CLI");
        mem[MAIN + 16'd3] = OP_CLI;
        start();
        pulse_irq();                       // I is still set from reset
        wait_sync(); ck_eq16(dbg_pc, MAIN + 16'd1, "masked IRQ did not divert (1)");
        wait_sync(); ck_eq16(dbg_pc, MAIN + 16'd2, "masked IRQ did not divert (2)");
        wait_sync(); ck_eq16(dbg_pc, MAIN + 16'd3, "masked IRQ did not divert (3)");
        // $0303 is the CLI. Its own boundary is not diverted - I is still set
        // while it decodes - and the entry happens at the one after it.
        wait_sync();
        ck_eq16(dbg_pc, HIRQ, "the deferred IRQ is taken once I clears");
        check_frame(MAIN + 16'd4, 1'b0);

        // ---------------------------------------------------------------
        load("NMI is taken through $FFFA even with I set");
        start();
        pulse_nmi();
        wait_sync();
        ck_eq16(dbg_pc, HNMI, "entered the NMI handler");
        check_frame(MAIN + 16'd1, 1'b0);

        // ---------------------------------------------------------------
        load("NMI is edge triggered: a held line raises one interrupt");
        start();
        NMI = 1;                           // and stays high for the whole case
        wait_sync();
        ck_eq16(dbg_pc, HNMI, "first NMI taken");
        wait_sync();
        ck_eq16(dbg_pc, MAIN + 16'd1, "RTI returned with the line still high");
        wait_sync();
        ck_eq16(dbg_pc, MAIN + 16'd2, "no second entry from the same level");
        NMI = 0;

        // ---------------------------------------------------------------
        load("NMI outranks IRQ raised in the same cycle");
        mem[MAIN] = OP_CLI;
        start();
        wait_sync();                       // I clear
        IRQ = 1; NMI = 1; tick(); IRQ = 0; NMI = 0;
        wait_sync();
        ck_eq16(dbg_pc, HNMI, "NMI serviced first");
        // The NMI handler's RTI restores I clear, so the still-pending IRQ is
        // taken at the boundary the RTI returns to - no instruction of the
        // interrupted program runs in between.
        wait_sync();
        ck_eq16(dbg_pc, HIRQ, "IRQ serviced immediately afterwards");

        // ---------------------------------------------------------------
        load("BRK is distinguishable from a hardware interrupt");
        mem[MAIN]          = OP_BRK;
        mem[MAIN + 16'd1]  = 8'hFF;        // BRK's signature byte
        start();
        wait_sync();
        ck_eq16(dbg_pc, HIRQ, "BRK vectors through $FFFE too");
        // BRK pushes the address after its signature byte, and sets B.
        check_frame(MAIN + 16'd2, 1'b1);
        wait_sync();
        ck_eq16(dbg_pc, MAIN + 16'd2, "RTI returns past the signature byte");

        // ---------------------------------------------------------------
        load("entry preserves the register file");
        mem[MAIN]          = OP_CLI;
        mem[MAIN + 16'd1]  = OP_LDA;
        mem[MAIN + 16'd2]  = 8'h5A;
        start();
        wait_sync();                       // CLI
        wait_sync();                       // LDA #$5A
        ck_eq8(dbg_a, 8'h5A, "LDA loaded A");
        pulse_irq();
        wait_sync();
        ck_eq16(dbg_pc, HIRQ, "entered the handler");
        ck_eq8(dbg_a, 8'h5A, "A survived entry");
        ck_eq8(dbg_x, 8'h00, "X survived entry");
        ck_eq8(dbg_y, 8'h00, "Y survived entry");

        // ---------------------------------------------------------------
        // Why the pending latches sit outside the RDY gate: the console drives
        // IRQ with a one-clock vsync pulse, and vblank DMA can hold the core
        // across exactly that clock.
        load("a request that lands during an RDY stall is not lost");
        mem[MAIN] = OP_CLI;
        start();
        wait_sync();                       // I clear
        RDY = 0;
        repeat (3) tick();
        pulse_irq();                       // the whole pulse is inside the stall
        repeat (3) tick();
        RDY = 1;
        wait_sync();
        ck_eq16(dbg_pc, HIRQ, "the stalled request was remembered");
        check_frame(MAIN + 16'd1, 1'b0);

        // ---------------------------------------------------------------
        // WAI's two idioms. With I set the sleep is the service and no vector
        // is taken; with I clear the wake is followed straight into $FFFE.
        load("SEI+WAI wakes without vectoring");
        mem[MAIN]          = OP_WAI;
        start();
        repeat (8) tick();                 // the core is asleep in S_WAI
        pulse_irq();
        wait_sync();
        ck_eq16(dbg_pc, MAIN + 16'd1, "WAI resumed at the following instruction");
        ck_eq8(dbg_s, 8'hFD, "nothing was pushed");

        load("WAI with I clear wakes and then vectors");
        mem[MAIN]          = OP_CLI;
        mem[MAIN + 16'd1]  = OP_WAI;
        start();
        wait_sync();                       // CLI
        repeat (8) tick();                 // asleep, with I clear
        pulse_irq();
        wait_sync();
        ck_eq16(dbg_pc, HIRQ, "the wake is followed by the vector");
        check_frame(MAIN + 16'd2, 1'b0);

        // ---------------------------------------------------------------
        if (failures == 0)
            $display("\nall interrupt checks passed");
        else begin
            $display("\n%0d interrupt check(s) FAILED", failures);
            $fatal(1);
        end
        $finish;
    end

endmodule
