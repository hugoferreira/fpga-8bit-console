// Shared 512x16 per-slot state store. The sample walk has priority over the
// tick sequencer on both the synchronous read address and the write port.

`ifndef PSG_STATE_MEM_SV
`define PSG_STATE_MEM_SV

module psg_state_mem (input  bit   clk,
                      input  bit   reset,

                      input  logic wlk_rd,
                      input  logic [PSG_VADR-1:0] wlk_ra,
                      input  logic wlk_we,
                      input  logic [PSG_VADR-1:0] wlk_wa,
                      input  logic [15:0] wlk_wd,

                      input  logic [PSG_VADR-1:0] etk_ra,
                      input  logic etk_we,
                      input  logic [PSG_VADR-1:0] etk_wa,
                      input  logic [15:0] etk_wd,

                      input  logic prun,
                      output logic state_replay,
                      output logic [15:0] state_q);

  logic [15:0] state_m[0:PSG_NV*PSG_VSTR-1];

  // Deterministic simulation state; this also maps to initialized iCE40 RAM.
  initial for (int i = 0; i < PSG_NV * PSG_VSTR; i++) state_m[i] = 16'h0000;

  logic [PSG_VADR-1:0] state_ra, state_wa;
  logic [15:0]         state_wd;
  logic                state_we;

  always_comb begin
    state_ra = wlk_rd ? wlk_ra : etk_ra;
    state_we = wlk_we | etk_we;
    state_wa = wlk_we ? wlk_wa : etk_wa;
    state_wd = wlk_we ? wlk_wd : etk_wd;
  end

  always_ff @(posedge clk) begin
    if (state_we)
      state_m[state_wa] <= state_wd;
    state_q <= state_m[state_ra];
  end

  // A sequencer read issued as prun begins is displaced by the walk's read.
  // state_replay holds the sequencer for the following reissue cycle.
  always_ff @(posedge clk) begin
    if (reset)
      state_replay <= 0;
    else
      state_replay <= prun;
  end

endmodule

`endif
