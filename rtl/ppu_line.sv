// PPU line buffer: two banks of LANES words, 8 pixels x 4bpp each.
//
// The engine composites line N+1 into the back bank while line N is displayed
// out of the front one, and the swap is a register toggle rather than a copy -
// address bit 5 selects the bank, so the two banks are one array.
//
// This module owns which bank is which, so nothing outside it has to. Both
// sides address the buffer by LANE and get the right bank: the display always
// reads the front, the engine always reads and writes the back.
//
// The single read port is shared, and the arbitration is the whole reason this
// is a module rather than two arrays: **the display wins**. It has to - the
// beam cannot wait - so the engine takes the clocks the display leaves, which
// is what `E_RD0`/`E_RD1` stall on. Measured across the three ports, that
// costs between 1.00 and 8.04 clocks of a 483-clock line (see the change's
// design.md); the alternative, a second port, costs a block RAM the PPU does
// not have spare.
// There is no LANES parameter: a bank is a full 32 words because the bank IS
// address bit 5, and how many of them a line covers is the engine's business,
// not the buffer's.
module ppu_line(input bit clk, input bit reset,
                // Display side: reads the front bank, always wins
                input  logic       disp_slot,
                input  logic [4:0] disp_lane,
                input  logic       line_end,      // swap at the sync pixel
                // Engine side: reads and writes the back bank
                input  logic       eng_rd,
                input  logic [4:0] eng_rlane,
                input  logic       eng_we,
                input  logic [4:0] eng_wlane,
                input  logic [31:0] eng_wdata,
                // Registered read data, one clock after the request
                output logic [31:0] rd_data,
                output logic        bank);

  logic [31:0] linebuf[0:63];

  logic [5:0] rd_addr;
  always_comb begin
    if (disp_slot)   rd_addr = {bank, disp_lane};
    else if (eng_rd) rd_addr = {~bank, eng_rlane};
    else             rd_addr = 6'd0;
  end
  always_ff @(posedge clk)
    rd_data <= linebuf[rd_addr];

  // Write port: exclusively the engine's, always into the back bank
  always_ff @(posedge clk)
    if (eng_we)
      linebuf[{~bank, eng_wlane}] <= eng_wdata;

  // The composed bank becomes the displayed bank during the sync pixel
  always_ff @(posedge clk)
    if (reset)
      bank <= 0;
    else if (line_end)
      bank <= ~bank;
endmodule
