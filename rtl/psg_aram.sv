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

  // A synthesis read replaces the sequencer address for one cycle. The
  // sequencer stays frozen through the following replay cycle.
  assign seq_frozen = syn_rd | replay;

  // Sequencer reads are issued one state before they are consumed.  An
  // ordinary freeze therefore holds the registered RAM output: the held
  // state's current seq_addr already names the following byte.  A synthesis
  // borrow still replaces that output, so its replay cycle forcibly reissues
  // the held sequencer address before the output is held again.
  wire aram_rd = !syn_freeze && (syn_rd | replay | !seq_hold);
  wire [12:0] aram_addr = syn_rd ? syn_addr : seq_addr;

  always_ff @(posedge clk) begin
    if (aram_rd)
      seq_q <= aram[aram_addr];
    if (reset) begin
      replay <= 0;
    end else if (!syn_freeze) begin
      replay <= syn_rd;
    end
  end

  // CPU writes use PICO-8 addresses; the memory itself is zero-based.
  wire [15:0] up_idx = wraddr - 16'h3100;

  always_ff @(posedge clk) begin
    if (reset) begin
      wraddr <= 16'h3100;
    end else if (cs && rw) begin
      case (addr)
        8'h00: wraddr[7:0] <= di;
        8'h01: wraddr[15:8] <= di;
        8'h02: begin
          if (up_idx < 16'd4608)
            aram[up_idx[12:0]] <= di;
          wraddr <= wraddr + 1;
        end
        default: ;
      endcase
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

                 input  logic [12:0] seq_addr,

                 input  logic        syn_rd,
                 input  logic [12:0] syn_addr,
                 input  logic        seq_hold,
                 output logic [7:0]  seq_q,
                 output logic        seq_frozen);

  psg_aram_core u_core(
    .clk(clk), .reset(reset),
    .cs(cs), .rw(rw), .addr(addr), .di(di),
    .seq_addr(seq_addr), .syn_rd(syn_rd), .syn_addr(syn_addr),
    .syn_freeze(1'b0), .seq_hold(seq_hold),
    .seq_q(seq_q), .seq_frozen(seq_frozen));

endmodule

`endif
