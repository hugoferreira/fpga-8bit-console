// PPU sprite scan: the display list, and the per-line walk that turns it into
// a stream of entries in composite order.
//
// The list is 128 entries of {behind, rep[2:0], pal[3:0], bppm1[1:0], yflip,
// xflip, base[7:0], y[6:0], x[7:0]}, committed one at a time by a write to
// $0B. This module examines one entry per clock, holds the ones that
// intersect the line being composited, and hands them downstream.
//
// An entry composites BEHIND the tile layer when its index is below the
// behind-split ($36) OR its own behind bit (staged through $3A) is set; the
// split alone reproduces the original partition exactly. While no committed
// entry carries the bit (`behind_any`, cleared when $0C rewrites the count),
// the walk is the original single pass over a partitioned list - the same
// clocks, the same cursor. Once a bit-carrying entry exists, both passes
// walk the whole list and filter on the predicate, one scan clock per entry
// per pass; that price bought the 128-entry stress line past its budget, so
// it is only paid when the feature is actually in use.
//
// Together with ppu_map this is the pair the change set out to separate: two
// producers of one entry stream, sharing everything downstream of them. What
// used to make that hard was a single `entry_q` register written by both.
module ppu_scan #(parameter MAX_SPRITES = 128)
                 (input bit clk, input bit reset,
                  // Commit port from the register file ($0B)
                  input  logic        list_we,
                  input  logic [6:0]  list_waddr,
                  input  logic [34:0] list_wdata,
                  // Configuration
                  input  logic        count_we,     // $0C rewrite: new list
                  input  logic [7:0]  sp_count,
                  input  logic [7:0]  bsplit,
                  input  logic [6:0]  line_y,
                  // Walk control
                  input  logic        line_start,   // rewind for a new line
                  input  logic        advance,      // examine the next entry
                  input  logic        next_pass,    // behind pass -> front pass
                  // Results
                  output logic [34:0] entry,
                  output logic        valid,
                  output logic        hit,          // entry intersects line_y
                  output logic        exhausted,    // nothing left in this pass
                  output logic        front_pass);  // 0 = behind, 1 = front

  logic [34:0] list[0:MAX_SPRITES-1];
  logic        behind_any;
  always_ff @(posedge clk) begin
    if (list_we)
      list[list_waddr] <= list_wdata;
    if (reset || count_we)
      behind_any <= 0;
    else if (list_we && list_wdata[34])
      behind_any <= 1;
  end

  logic [7:0] scan_i;
  logic [7:0] entry_i;         // index of the entry in `entry`, for the split

  wire [7:0] count_eff  = (sp_count > MAX_SPRITES[7:0]) ? MAX_SPRITES[7:0] : sp_count;
  wire [7:0] limA       = (bsplit > count_eff) ? count_eff : bsplit;
  wire [7:0] scan_limit = (front_pass || behind_any) ? count_eff : limA;

  wire [6:0] e_y = entry[14:8];
  wire [6:0] dy  = line_y - e_y;
  wire behind = entry[34] || (entry_i < bsplit);
  assign hit = (dy < 7'd8) && valid && (behind != front_pass);

  // Out of entries AND the last one has already been dealt with. The two
  // conditions are one clock apart: `valid` falls on the clock the cursor
  // reaches the limit, and the pass ends on the next.
  assign exhausted = (scan_i >= scan_limit) && !valid;

  always_ff @(posedge clk)
    if (reset) begin
      scan_i <= 0;
      entry_i <= 0;
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
        entry_i <= scan_i;
        if (scan_i < scan_limit) begin
          valid <= 1;
          scan_i <= scan_i + 1;
        end else
          valid <= 0;
      end
      // With no behind-bit entries the front pass continues from the split,
      // exactly the original walk; otherwise it re-walks the list from the
      // top, filtering on the predicate's other polarity.
      if (next_pass) begin
        front_pass <= 1;
        if (behind_any) begin
          scan_i <= 0;
          valid <= 0;
        end
      end
    end
endmodule
