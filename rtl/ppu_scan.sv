// PPU sprite scan: the display list, and the per-line walk that turns it into
// a stream of entries in composite order.
//
// The list is 128 entries of {rep[2:0], pal[3:0], bppm1[1:0], yflip, xflip,
// base[7:0], y[6:0], x[7:0]}, committed one at a time by a write to $0B. This
// module examines one entry per clock, holds the ones that intersect the line
// being composited, and hands them downstream.
//
// The behind-split ($36) is a partition, not a second pass: entries
// 0..split-1 are scanned first (they composite BEHIND the tile layer), then
// the tile pass runs, then the scan resumes at the split and runs to the end.
// The cursor is never rewound, so background sprites cost no extra scan
// clocks - which is why `scan_i` survives the pass change untouched and only
// the limit moves.
//
// Together with ppu_map this is the pair the change set out to separate: two
// producers of one entry stream, sharing everything downstream of them. What
// used to make that hard was a single `entry_q` register written by both.
module ppu_scan #(parameter MAX_SPRITES = 128)
                 (input bit clk, input bit reset,
                  // Commit port from the register file ($0B)
                  input  logic        list_we,
                  input  logic [6:0]  list_waddr,
                  input  logic [33:0] list_wdata,
                  // Configuration
                  input  logic [7:0]  sp_count,
                  input  logic [7:0]  bsplit,
                  input  logic [6:0]  line_y,
                  // Walk control
                  input  logic        line_start,   // rewind for a new line
                  input  logic        advance,      // examine the next entry
                  input  logic        next_pass,    // behind pass -> front pass
                  // Results
                  output logic [33:0] entry,
                  output logic        valid,
                  output logic        hit,          // entry intersects line_y
                  output logic        exhausted,    // nothing left in this pass
                  output logic        front_pass);  // 0 = behind, 1 = front

  logic [33:0] list[0:MAX_SPRITES-1];
  always_ff @(posedge clk)
    if (list_we)
      list[list_waddr] <= list_wdata;

  logic [7:0] scan_i;

  wire [7:0] count_eff  = (sp_count > MAX_SPRITES[7:0]) ? MAX_SPRITES[7:0] : sp_count;
  wire [7:0] limA       = (bsplit > count_eff) ? count_eff : bsplit;
  wire [7:0] scan_limit = front_pass ? count_eff : limA;

  wire [6:0] e_y = entry[14:8];
  wire [6:0] dy  = line_y - e_y;
  assign hit = (dy < 7'd8) && valid;

  // Out of entries AND the last one has already been dealt with. The two
  // conditions are one clock apart: `valid` falls on the clock the cursor
  // reaches the limit, and the pass ends on the next.
  assign exhausted = (scan_i >= scan_limit) && !valid;

  always_ff @(posedge clk)
    if (reset) begin
      scan_i <= 0;
      valid <= 0;
      front_pass <= 0;
    end else if (line_start) begin
      scan_i <= 0;
      valid <= 0;
      front_pass <= 0;
    end else begin
      if (advance) begin
        // One entry per clock, pipelined against the list read
        entry <= list[scan_i[6:0]];
        if (scan_i < scan_limit) begin
          valid <= 1;
          scan_i <= scan_i + 1;
        end else
          valid <= 0;
      end
      // The cursor deliberately stays where it is: the front pass continues
      // from the split rather than starting over.
      if (next_pass)
        front_pass <= 1;
    end
endmodule
