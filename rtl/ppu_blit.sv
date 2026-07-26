// PPU blit datapath: fetched plane rows and a cell position in, two
// line-buffer words out.
//
// This was the compositor's longest combinational path, and nextpnr named it
// as such: entry register -> `bmask` -> eight parallel draw-palette lookups ->
// a 64-bit shift by the sub-lane offset -> merge under the opacity and clip
// masks -> line-buffer write data, all in one clock. It is three pipeline
// stages now, and **the latency is free**: the engine spends two clocks
// (`E_RD0`, `E_RD1`) reading the line-buffer words this cell will merge into,
// and the datapath had nothing to do during them. The stages fill exactly
// that gap, so an entry still costs the same number of clocks - which the
// per-line accounting in rtl/ppu_golden_tb.sv asserts, because a deeper
// pipeline that spent the line budget it was meant to protect would be a
// worse design, not a better one.
//
// The three stages carry no valid bit and no enable. They do not need one:
// the values they hold are stable for as long as the entry is, and the FSM
// cannot reach `E_WR0` in fewer than two clocks from the end of the fetch.
//
// The path, in order:
//
//   1. Decode. Eight pixels, each `bpp` bits gathered across the plane rows,
//      LSB-first so bit j of plane p is pixel j. `bmask` drops the planes the
//      entry does not have; xflip reverses j.
//   2. Palette and opacity. The colour is `pal + value` **mod 16** - a 4-bit
//      add, which is the register map's promise - then through the draw
//      palette. Opacity is the transparency mask indexed by the raw value,
//      before the palette, so `$34/$35` select pixel VALUES and not colours.
//      -- stage 1 register --
//   3. Align, and clip. A row starts at any pixel, so it straddles at most two
//      lanes: shift the 32-bit row into a 64-bit window by the sub-lane
//      offset, and shift the 8-bit opacity mask the same way. The clip
//      rectangle becomes a 16-bit mask over the same window, computed from the
//      lane in 8-bit arithmetic so the wrapped left-edge partial tile clips
//      correctly with no extra logic.
//      -- stage 2 register --
//   4. Merge. The two masks together choose old or new per pixel, straight
//      into the line-buffer write data. This is now a 4-bit-wide 2:1 mux and
//      nothing else, which is why the path that used to end here no longer
//      dominates.
//
// The draw palette lives here because this is what reads it: eight lookups per
// composited row, against the screen palette's one per displayed pixel in
// ppu_display. Only the register file's readback port leaves the module.
module ppu_blit #(parameter LANES = 20)
                 (input bit clk, input bit reset,
                  // Draw palette: written from the register file, read here
                  input  logic       dpal_we,
                  input  logic [3:0] dpal_waddr,
                  input  logic [3:0] dpal_wdata,
                  input  logic [3:0] dpal_raddr,
                  output logic [3:0] dpal_rdata,
                  // The entry being blitted, and where this cell of it goes
                  input  logic [7:0] prow0, prow1, prow2, prow3,
                  input  logic       e_xf,
                  input  logic [1:0] e_bppm1,
                  input  logic [3:0] e_pal,
                  input  logic [7:0] cell_x,
                  input  logic [6:0] line_y,
                  // Draw state
                  input  logic [15:0] palt_t,
                  input  logic [7:0]  clip_x0, clip_x1,
                  input  logic [6:0]  clip_y0, clip_y1,
                  // The two line-buffer words this cell touches
                  input  logic [31:0] old_w0, old_w1,
                  output logic [4:0]  lane, lane1,
                  output logic        w0_valid,
                  output logic [31:0] w0_data,
                  output logic        w1_valid,
                  output logic [31:0] w1_data);

  logic [3:0] dpal[0:15];
  always_ff @(posedge clk)
    if (reset)
      for (int k = 0; k < 16; k++)
        dpal[k] <= k[3:0];
    else if (dpal_we)
      dpal[dpal_waddr] <= dpal_wdata;
  assign dpal_rdata = dpal[dpal_raddr];

  wire [3:0] bmask = {e_bppm1 == 2'd3, e_bppm1 >= 2'd2, e_bppm1 >= 2'd1, 1'b1};

  // ---- stage 1: per-pixel colour and opacity for the 8-pixel row ----
  logic [31:0] packed32;
  logic [7:0]  opq8;
  always_comb begin
    for (int j = 0; j < 8; j++) begin
      logic [2:0] jj;
      logic [3:0] pix;
      logic [3:0] pidx;
      jj = e_xf ? 3'd7 - j[2:0] : j[2:0];
      pix = {prow3[jj], prow2[jj], prow1[jj], prow0[jj]} & bmask;
      // A 4-bit add on purpose: the register map says "palette base + pixel
      // value, mod 16". Keeping pidx a 4-bit variable keeps the wrap.
      pidx = e_pal + pix;
      opq8[j] = ~palt_t[pix];
      packed32[j*4 +: 4] = dpal[pidx];
    end
  end

  logic [31:0] packed32_q;
  logic [7:0]  opq8_q;
  always_ff @(posedge clk) begin
    packed32_q <= packed32;
    opq8_q <= opq8;
  end

  // ---- stage 2: align into the 64-bit window, and clip ----
  //
  // The window covers the two lanes the row can straddle. The blit works from
  // cell_x - the position of the cell being WRITTEN - rather than from the
  // entry's own x, so a repeated entry steps right without re-fetching.
  //
  // `lane` and `lane1` stay combinational: they address the line-buffer reads
  // in E_RD0/E_RD1 as well as the writes, and cell_x only changes at the end
  // of E_WR1, so their registered and unregistered values agree at every
  // clock either is used.
  assign lane  = cell_x[7:3];
  assign lane1 = lane + 5'd1;
  wire [2:0]  off    = cell_x[2:0];
  wire [63:0] data64 = {32'b0, packed32_q} << {off, 2'b00};
  wire [15:0] mask16 = {8'b0, opq8_q} << off;

  // Clip mask over the same window: pixel k sits at screen x = {lane,000}+k
  // in 8-bit arithmetic, which also clips the wrapped left-edge partial tile
  wire line_in_clip = (line_y >= clip_y0) && (line_y <= clip_y1);
  logic [15:0] clipm;
  always_comb
    for (int k = 0; k < 16; k++) begin
      logic [7:0] xk;
      xk = {lane, 3'b000} + k[7:0];
      clipm[k] = line_in_clip && (xk >= clip_x0) && (xk <= clip_x1);
    end

  logic [63:0] data64_q;
  logic [15:0] mask16_q, clipm_q;
  always_ff @(posedge clk) begin
    data64_q <= data64;
    mask16_q <= mask16;
    clipm_q  <= clipm;
  end

  // ---- stage 3: merge, into the line-buffer write data ----
  function automatic [31:0] merge(input [31:0] old, input [31:0] nw, input [7:0] m);
    for (int n = 0; n < 8; n++)
      merge[n*4 +: 4] = m[n] ? nw[n*4 +: 4] : old[n*4 +: 4];
  endfunction

  assign w0_valid = lane < LANES[4:0];
  assign w0_data  = merge(old_w0, data64_q[31:0], mask16_q[7:0] & clipm_q[7:0]);
  // The second word is skipped outright when nothing lands in it, which is the
  // common case for a cell that happens to be lane-aligned
  assign w1_valid = (lane1 < LANES[4:0]) && ((mask16_q[15:8] & clipm_q[15:8]) != 8'd0);
  assign w1_data  = merge(old_w1, data64_q[63:32], mask16_q[15:8] & clipm_q[15:8]);
endmodule
