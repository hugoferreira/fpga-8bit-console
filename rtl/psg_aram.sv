// PSG audio RAM: PICO-8's $3100-$42FF image (music patterns 0..255, SFX
// records 256..4607), the auto-incrementing upload port that fills it, and
// the ONE shared read port every consumer goes through.
//
// The port contract, which is the reason this is a module and not an array:
// the sequencer owns the read port except on the one cycle per sample per
// wavetable voice that the synthesis walk borrows it. A borrow overwrites
// the byte the sequencer was waiting on, so the sequencer freezes for that
// cycle and for one more while the address it issued last is replayed. That
// is what `seq_frozen` exports. There is exactly one unconditional read of
// `aram`, which is what keeps it inferring as block RAM rather than logic.
`ifndef PSG_ARAM_SV
`define PSG_ARAM_SV

module psg_aram (input  bit          clk,
                 input  bit          reset,
                 // CPU upload port: $00/$01 address lo/hi, $02 data (auto-inc)
                 input  bit          cs,
                 input  bit          rw,
                 input  logic [7:0]  addr,
                 input  logic [7:0]  di,
                 // The sequencer's request, valid every cycle it is not frozen
                 input  logic [12:0] seq_addr,
                 // The synthesis walk's borrow
                 input  logic        syn_rd,
                 input  logic [12:0] syn_addr,
                 output logic [7:0]  seq_q,
                 output logic        seq_frozen);

  logic [7:0]  aram[0:4607];
  logic [15:0] wraddr;
  logic [12:0] last_addr;
  logic        replay;

  assign seq_frozen = syn_rd | replay;

  wire [12:0] aram_addr = syn_rd ? syn_addr : replay ? last_addr : seq_addr;

  always_ff @(posedge clk) begin
    seq_q <= aram[aram_addr];
    if (reset) begin
      replay <= 0;
      last_addr <= 0;
    end else begin
      replay <= syn_rd;              // a borrow costs a replay cycle
      if (!seq_frozen) last_addr <= seq_addr;
    end
  end

  // The upload port takes PICO-8 addresses, so cart bytes go in unchanged.
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
