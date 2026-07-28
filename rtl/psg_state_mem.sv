// PSG scheduled record store: one 512x16 memory holding every per-slot
// record, with a fixed two-owner port contract.
//
//   word  0.. 9  tick/note state
//   word 10..23  oscillator state
//   word 24..27  sounding parameter bank 0
//   word 28..31  sounding parameter bank 1
//   word 32      the sequencer's note position
//
// Held as `name[NV]` flop arrays these fields cost a flop per bit AND an
// NV:1 mux per read, and the muxes are the larger half: measured across
// NV=2/4/8/16 the marginal cost of a slot was 379 LUT4 against 336 bits of
// state. As one memory with a synchronous read it infers an SB_RAM40_4K and
// the per-slot cost drops to roughly zero.
//
// PORT CONTRACT. Two owners, each presenting one read request and one write
// request, with the sample walk taking absolute priority. The tick engine is
// frozen for the complete sample walk, so the owners never contend in
// practice; the priority here is what makes that structural rather than a
// comment. Exactly one synchronous read site and one write site, which is
// the shape that lowers to a single simple-dual-port block RAM.
//
// state_replay lives here because it is the displaced read's re-issue
// signal: `prun` delayed one cycle, telling the sequencer that the
// synchronous word it asked for was taken by a sample and has to be asked
// for again.
//
// Reset: a block RAM cannot be cleared the way an array of flops can, so a
// record is garbage until the slot's first trigger. That is safe, and not by
// luck - K_ADV reads nothing from the record unless `trig_req` or `playing`
// is set, both of which are flops that reset to 0, and a trigger runs
// T_FL..T_LD which writes every field the note path can reach before it is
// read. The one field that would be dangerous, `ins_on`, is written by T_FL.
`ifndef PSG_STATE_MEM_SV
`define PSG_STATE_MEM_SV

module psg_state_mem (input  bit   clk,
                      input  bit   reset,
                      // Owner 1: the sample walk
                      input  logic wlk_rd,
                      input  logic [PSG_VADR-1:0] wlk_ra,
                      input  logic wlk_we,
                      input  logic [PSG_VADR-1:0] wlk_wa,
                      input  logic [15:0] wlk_wd,
                      // Owner 2: the tick engine and the V_LD/V_ST visit
                      input  logic [PSG_VADR-1:0] etk_ra,
                      input  logic etk_we,
                      input  logic [PSG_VADR-1:0] etk_wa,
                      input  logic [15:0] etk_wd,
                      // The displaced-read re-issue signal
                      input  logic prun,
                      output logic state_replay,
                      output logic [15:0] state_q);

  logic [15:0] state_m[0:PSG_NV*PSG_VSTR-1];
  // Simulation determinism, and a free BRAM init on iCE40. Without it
  // iverilog starts the record at X and the X leaks through the packing.
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

  // A sample owns the store for its complete bounded walk. Tick-first
  // ordering gives the 120 Hz microprogram an uncontested port on the
  // boundary where its result matters; ordinary trigger work can wait one
  // sample without changing any sample-visible state. One replay cycle
  // restores a synchronous V_LD word displaced when a sample began
  // mid-trigger.
  always_ff @(posedge clk) begin
    if (reset)
      state_replay <= 0;
    else
      state_replay <= prun;
  end

endmodule

`endif
