// PPU tilemap: the cell store, and the per-line column walk that turns it into
// a stream of sprite entries.
//
// 32x16 cells of {pal[3:0], bppm1[1:0], yflip, xflip, base[7:0]}, wrapping over
// a 256x128-pixel world and scrolled by camera registers latched once per
// scanline. The important thing about this module is what it does NOT do: a
// tile is not drawn by tile logic. It is composited as a **synthesized sprite
// entry** at x = k*8 - (camera_x & 7), pushed through the same fetch and blit
// path as the sprite list - and the 8-bit x wraparound is what makes the
// partial left-edge tile work with no extra logic at all.
//
// That is the interface this module exists to make explicit: ppu_map and
// ppu_scan are two producers of the same entry stream, and everything
// downstream of them is shared. Cell $0000 is empty and skipped in two clocks.
//
// The walk used to cost a flat 43 clocks a scanline in every game measured -
// 21 columns at TWO clocks each, one to issue the cell read and one to act on
// it, plus the one that finds the end. It was the largest fixed cost in the
// engine and the only one that did not depend on the scene.
//
// It is one clock a column now. The read address is driven from the column
// cursor's NEXT value rather than its current one, so the read for column k+1
// is always already in flight while column k is being decided, and the state
// that existed only to wait for it is gone. It costs nothing: the address was
// combinational either way. Nor does it need a priming clock - the clock that
// resets the cursor is also the one that issues column 0's read.
module ppu_map #(parameter TILE_COLS = 21)
                (input bit clk, input bit reset,
                 // CPU write window: low bytes at $000-$1FF, high at $200-$3FF
                 input  bit          map_cs,
                 input  bit          rw,
                 input  logic [9:0]  map_addr,
                 input  logic [7:0]  di,
                 // Per-line scroll state, latched once at line_start
                 input  logic        line_start,
                 input  logic [7:0]  camera_x,
                 input  logic [6:0]  camera_y,
                 input  logic [6:0]  next_line,
                 input  logic [6:0]  line_y,
                 // Column walk
                 input  logic        tk_reset,   // begin the tile pass
                 input  logic        tk_step,    // this cell is decided, move on
                 output logic        at_end,     // no columns left
                 output logic        cell_empty, // the fetched cell is $0000
                 output logic [33:0] entry);     // this cell, as a sprite entry

  logic [7:0] map_lo[0:511];
  logic [7:0] map_hi[0:511];

  always_ff @(posedge clk)
    if (map_cs && rw && !map_addr[9])
      map_lo[map_addr[8:0]] <= di;
  always_ff @(posedge clk)
    if (map_cs && rw && map_addr[9])
      map_hi[map_addr[8:0]] <= di;

  // Latched scroll state and the column cursor
  logic [7:0] camx_l;
  logic [6:0] wy_row;
  logic [4:0] tk;

  wire [4:0] tx0    = camx_l[7:3];
  wire [2:0] xoff   = camx_l[2:0];
  wire [3:0] ty     = wy_row[6:3];
  wire [2:0] rowoff = wy_row[2:0];
  wire [6:0] y_syn  = line_y - {4'b0, rowoff};

  wire [7:0] x_syn = {tk, 3'b000} - {5'b0, xoff};
  assign at_end = tk >= TILE_COLS[4:0];

  // Cell read, one column ahead: the address is the cursor's next value, so
  // the data for the column being decided next clock is already in flight.
  wire [4:0] tk_next = (line_start || tk_reset) ? 5'd0 :
                       tk_step                  ? tk + 5'd1 : tk;
  wire [8:0] map_raddr = {ty, tx0 + tk_next};
  logic [7:0] map_rd_lo, map_rd_hi;
  always_ff @(posedge clk) begin
    map_rd_lo <= map_lo[map_raddr];
    map_rd_hi <= map_hi[map_raddr];
  end

  assign cell_empty = {map_rd_hi, map_rd_lo} == 16'h0000;

  // The synthesized entry. Combinational, and valid only while the cell read
  // is standing - the consumer latches it, which is what makes this a stream
  // rather than a shared register. y is chosen so that dy lands on the tile's
  // own row, and rep is 0 because a tile is always a single cell.
  assign entry = {3'd0, map_rd_hi[7:4], map_rd_hi[3:2], map_rd_hi[1],
                  map_rd_hi[0], map_rd_lo, y_syn, x_syn};

  always_ff @(posedge clk)
    if (reset) begin
      camx_l <= 0;
      wy_row <= 0;
      tk <= 0;
    end else if (line_start) begin
      camx_l <= camera_x;
      wy_row <= camera_y + next_line;
      tk <= 0;
    end else begin
      if (tk_reset) tk <= 0;
      else if (tk_step) tk <= tk + 1;
    end
endmodule
