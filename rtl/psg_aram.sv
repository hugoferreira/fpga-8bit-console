// PICO-8 audio RAM ($3100-$42ff) with an auto-incrementing upload port and
// one synchronous read port shared by the sequencer and wavetable renderer.

`ifndef PSG_ARAM_SV
`define PSG_ARAM_SV

module psg_aram (input  bit          clk,
                 input  bit          reset,

                 input  bit          cs,
                 input  bit          rw,
                 input  logic [7:0]  addr,
                 input  logic [7:0]  di,

                 input  logic [12:0] seq_addr,

                 input  logic        syn_rd,
                 input  logic [12:0] syn_addr,
                 output logic [7:0]  seq_q,
                 output logic        seq_frozen);

  logic [7:0]  aram[0:4607];
  logic [15:0] wraddr;
  logic [12:0] last_addr;
  logic        replay;

  // A synthesis read replaces the sequencer address for one cycle. The next
  // cycle reissues the last accepted sequencer address.
  assign seq_frozen = syn_rd | replay;

  wire [12:0] aram_addr = syn_rd ? syn_addr : replay ? last_addr : seq_addr;

  always_ff @(posedge clk) begin
    seq_q <= aram[aram_addr];
    if (reset) begin
      replay <= 0;
      last_addr <= 0;
    end else begin
      replay <= syn_rd;
      if (!seq_frozen) last_addr <= seq_addr;
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

`endif
