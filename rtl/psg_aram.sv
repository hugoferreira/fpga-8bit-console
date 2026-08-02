// PICO-8 audio RAM ($3100-$42ff) with an auto-incrementing upload port and
// one synchronous read port shared by the sequencer and wavetable renderer.

`ifndef PSG_ARAM_SV
`define PSG_ARAM_SV

/* verilator lint_off DECLFILENAME */
module psg_aram_core(input  bit          clk,
                     input  bit          reset,

                     input  bit          cs,
                     input  bit          rw,
                     input  logic [7:0]  addr,
                     input  logic [7:0]  di,

                     // Diagnostic CPU read of the current upload address. This
                     // borrows the synchronous read port; cpu_q is valid one
                     // clock later and the upload address auto-increments.
                     input  bit          cpu_rd,
                     output wire [7:0]   cpu_q,

                     input  logic [12:0] seq_addr,

                     input  logic        syn_rd,
                     input  logic [12:0] syn_addr,
                     input  logic        syn_freeze,
                     input  logic        seq_hold,
                     output logic [7:0]  seq_q,
                     output logic        seq_frozen);

  logic [7:0]  aram[0:4607];
  logic [15:0] wraddr;
  logic        replay;

  // CPU accesses use PICO-8 addresses; the memory itself is zero-based.  The
  // upload base is page-aligned, so only the five-bit page number subtracts.
  wire [4:0]  up_page = wraddr[12:8] - 5'd17;
  wire [12:0] up_idx = {up_page, wraddr[7:0]};
  wire        up_valid =
      (wraddr[15:12] == 4'h3 && |wraddr[11:8]) ||
      (wraddr[15:12] == 4'h4 && !(|wraddr[11:10]) &&
       wraddr[9:8] != 2'b11);
  assign cpu_q = seq_q;

  // A synthesis or diagnostic read replaces the sequencer address for one
  // cycle. The sequencer stays frozen through the following replay cycle.
  assign seq_frozen = cpu_rd | syn_rd | replay;

  // Sequencer reads are issued one state before they are consumed.  An
  // ordinary freeze therefore holds the registered RAM output: the held
  // state's current seq_addr already names the following byte.  A synthesis
  // borrow still replaces that output, so its replay cycle forcibly reissues
  // the held sequencer address before the output is held again.
  wire aram_rd = !syn_freeze &&
      (cpu_rd | syn_rd | replay | !seq_hold);
  wire [12:0] aram_addr = cpu_rd ? up_idx
      : (syn_rd ? syn_addr : seq_addr);

  always_ff @(posedge clk) begin
    if (aram_rd)
      seq_q <= aram[aram_addr];
    if (reset) begin
      replay <= 0;
    end else if (!syn_freeze) begin
      replay <= cpu_rd | syn_rd;
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      wraddr <= 16'h3100;
    end else if (cs && rw) begin
      case (addr)
        8'h00: wraddr[7:0] <= di;
        8'h01: wraddr[15:8] <= di;
        8'h02: begin
          if (up_valid)
            aram[up_idx] <= di;
          wraddr <= wraddr + 1;
        end
        default: ;
      endcase
    end else if (cpu_rd && !syn_freeze) begin
      wraddr <= wraddr + 1'b1;
    end
  end

endmodule
/* verilator lint_on DECLFILENAME */

// The accepted PSG keeps the historical always-running synthesis-borrow
// state.  The full executor instantiates psg_aram_core directly so an external
// hold can freeze the borrowed byte and its pending sequencer replay together.
module psg_aram (input  bit          clk,
                 input  bit          reset,

                 input  bit          cs,
                 input  bit          rw,
                 input  logic [7:0]  addr,
                 input  logic [7:0]  di,

                 // Diagnostic CPU read of the current upload address. This
                 // borrows the existing synchronous read port; cpu_q is valid
                 // one clock later and the address auto-increments.
                 input  bit          cpu_rd,
                 output wire [7:0]   cpu_q,

                 input  logic [12:0] seq_addr,

                 input  logic        syn_rd,
                 input  logic [12:0] syn_addr,
                 input  logic        seq_hold,
                 output logic [7:0]  seq_q,
                 output logic        seq_frozen);

  psg_aram_core u_core(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di),
    .cpu_rd(cpu_rd), .cpu_q(cpu_q),
    .seq_addr(seq_addr), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .syn_freeze(1'b0), .seq_hold(seq_hold),
    .seq_q(seq_q), .seq_frozen(seq_frozen));

endmodule

`endif
