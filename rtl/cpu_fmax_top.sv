/*
 * Synthesis-only harness for measuring one CPU core's Fmax and area.
 *
 * Not part of the console. `rtl/top.sv` does not reach this, and it exists
 * because the whole chip cannot currently be placed (see docs/cpu-core.md
 * section "The memory model does not fit on-chip"), so a whole-design timing
 * number is not available to compare cores with.
 *
 * The core is wired to a small synchronous-read RAM with the same timing as
 * `rtl/ram_async.sv` - address presented in cycle N, data on DI in cycle N+1 -
 * so the path this change is about (read data -> next address -> memory
 * address port) is present and real. 2 KB fits BRAM comfortably on an hx8k,
 * which the console's 64 KB map does not.
 *
 * The memory arbiter is deliberately NOT in the loop: this measures the core,
 * so that a difference between two runs is a difference between two cores.
 * The arbiter's mux sits on the same path in the real chip and adds to both.
 *
 *   make cpu-fmax SST_CORE=arlet
 *   make cpu-fmax SST_CORE=v2
 *
 * Hugo Sereno, <bytter@gmail.com>
 */

`ifdef SST_CORE_V2
  `include "cpu6502_core.sv"
`else
  `include "cpu6502_arlet.sv"
  `include "cpu6502_alu.sv"
`endif

/* verilator lint_off DECLFILENAME */

module cpu_fmax_top (
    input  logic clk,
    input  logic rst,
    input  logic rdy_in,
    input  logic din_bit,
    output logic probe
);

    localparam int AW = 11;      // 2 KB

    logic [15:0] ab;
    logic [7:0]  di, dout;
    logic        we;

    // Synchronous-read RAM, matching ram_async.sv: the read register updates
    // only on a read cycle, and the data is available the cycle after the
    // address is presented.
    logic [7:0] mem [0:(1<<AW)-1];
    logic [7:0] rdata;

    always_ff @(posedge clk) begin
        if (we) mem[ab[AW-1:0]] <= dout ^ {7'b0, din_bit};
        else    rdata <= mem[ab[AW-1:0]];
    end
    assign di = rdata;

`ifdef SST_CORE_V2
    cpu6502_core u_cpu (
        .clk(clk), .reset(rst),
        .AB(ab), .DI(di), .DO(dout), .WE(we),
        .IRQ(1'b0), .NMI(1'b0), .RDY(rdy_in),
        .dbg_pc(), .dbg_a(), .dbg_x(), .dbg_y(), .dbg_s(), .dbg_p(),
        .dbg_sync(), .dbg_trap(), .dbg_trap_ir(), .dbg_trap_pc()
    );
`else
    cpu u_cpu (
        .clk(clk), .reset(rst),
        .AB(ab), .DI(di), .DO(dout), .WE(we),
        .IRQ(1'b0), .NMI(1'b0), .RDY(rdy_in)
    );
`endif

    // Reduce every core output to one pin so nothing is trimmed away, and so
    // the comparison is not distorted by differing I/O counts.
    always_ff @(posedge clk) probe <= ^{ab, dout, we};

endmodule

/* verilator lint_on DECLFILENAME */
