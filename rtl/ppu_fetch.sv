// PPU pattern fetch: the sprite sheet, the plane-row reads, and the cell
// cursor that lets one entry cover a run of cells.
//
// The sheet is 256 uniform 8-byte plane slots - one 8x8 bitplane each - in 2 KB
// of block RAM. Sprites and tiles both reference a pattern by plane-slot BASE
// address and the bpp field doubles as the footprint: `bpp` consecutive slots,
// plane p row r at byte {base+p, r}. Every fetch is therefore self-contained:
// no region config, no tables, no multiplies, just an address made of the
// entry's own fields.
//
// A fetch costs bpp+2 clocks: one issue per plane, pipelined against the
// registered read, plus one to drain the last one. Measured on the three ports
// that is 8.9-20.0 fetches and 42-60 clocks a scanline, 17-29% of the engine's
// time (see the change's design.md) - the single largest scene-dependent cost,
// which is why the reuse question is asked of this module and not another.
//
// The cell cursor is here for the same reason. `$37` lets one entry blit its
// ONE fetched row into several consecutive cells; `cell_x` walks right while
// the entry and its plane rows stand still, so a run of N costs one fetch
// rather than N.
module ppu_fetch #(parameter SHEET_BYTES = 2048)
                  (input bit clk, input bit reset,
                   // CPU upload port ($02, auto-incrementing)
                   input  logic        sheet_we,
                   input  logic [10:0] sheet_waddr,
                   input  logic [7:0]  sheet_wdata,
                   // Engine control
                   input  logic        line_start,  // a new scanline begins
                   input  logic        start,       // begin this entry
                   input  logic [7:0]  start_x,     // its first cell
                   input  logic [2:0]  start_rep,   // extra cells after it
                   input  logic        run,         // advance the plane reads
                   input  logic        next_cell,   // step to the next cell
                   // The entry's pattern address, sampled at `start`
                   input  logic [7:0]  start_base,
                   input  logic [2:0]  start_rowi,
                   input  logic [1:0]  start_bppm1,
                   // Results
                   output logic        done,        // all planes captured
                   output logic        more,        // cells left in this run
                   output logic        reused,      // this entry skipped its fetch
                   output logic [7:0]  cell_x,
                   output logic [7:0]  prow0, prow1, prow2, prow3);

  logic [7:0] sheet[0:SHEET_BYTES-1];
  initial $readmemb("./rtl/sprite_pattern.bin", sheet);
  always_ff @(posedge clk)
    if (sheet_we)
      sheet[sheet_waddr] <= sheet_wdata;

  logic [7:0] prow[0:3];
  logic [2:0] fp;        // next plane to issue
  logic       fpend;     // a sheet read is in flight
  logic [1:0] fpidx;     // which plane it is for
  logic [2:0] rcnt;      // cells still to go in this run

  // The fetch key: what `prow` currently holds. Latched at `start`, and the
  // basis of the reuse cache below.
  logic [7:0] k_base;
  logic [2:0] k_rowi;
  logic [1:0] k_bppm1;
  logic       k_valid;
  logic       skip;      // this entry reuses what prow already holds

  // Pattern reuse across consecutive entries. Measured before it was built
  // (see the change's design.md): consecutive entries want the SAME
  // (base, row, bpp) 94.8% of the time in nemo, 41.7% in breakout and 21.1%
  // in celeste - a tile pass is long runs of one cell, and a sprite scene is
  // not. When the key matches, prow already holds the answer and the whole
  // fetch is one clock instead of bpp+2.
  //
  // Two things invalidate it, and both have to be here rather than argued:
  //   - a CPU write to the sheet, which can land between two entries and
  //     would otherwise be ignored until the key changed;
  //   - the start of a scanline, because a fetch interrupted by an overrun
  //     leaves prow half-filled under a key that claims it is complete.
  wire reuse_hit = k_valid && (start_base == k_base) &&
                   (start_rowi == k_rowi) && (start_bppm1 == k_bppm1);
  assign reused = skip;

  // Registered read on the engine's own port, address self-contained in the
  // entry. Issued every clock; only the ones `run` asks for are captured.
  // (Declared after `fp` on purpose - iverilog rejects declaration after use
  // even where Verilator and yosys accept it.)
  wire [10:0] sheet_eaddr = {k_base + {6'b0, fp[1:0]}, k_rowi};
  logic [7:0] sheet_rdata;
  always_ff @(posedge clk)
    sheet_rdata <= sheet[sheet_eaddr];

  assign prow0 = prow[0];
  assign prow1 = prow[1];
  assign prow2 = prow[2];
  assign prow3 = prow[3];
  assign more  = rcnt != 3'd0;
  // Every plane issued and the last read drained - or nothing to do at all
  assign done  = skip || ((fp > {1'b0, k_bppm1}) && !fpend);

  always_ff @(posedge clk) begin
    if (reset) begin
      fp <= 0;
      fpend <= 0;
      rcnt <= 0;
      cell_x <= 0;
      k_valid <= 0;
      skip <= 0;
    end else if (start) begin
      fp <= 0;
      fpend <= 0;
      cell_x <= start_x;
      rcnt <= start_rep;
      k_base <= start_base;
      k_rowi <= start_rowi;
      k_bppm1 <= start_bppm1;
      k_valid <= 1;
      skip <= reuse_hit;
      if (!reuse_hit) begin
        prow[0] <= 0;
        prow[1] <= 0;
        prow[2] <= 0;
        prow[3] <= 0;
      end
    end else begin
      if (line_start || sheet_we)
        k_valid <= 0;
      if (run && !skip) begin
        // Pipelined issue/capture: bpp reads, one per plane, then drain
        if (fpend)
          prow[fpidx] <= sheet_rdata;
        if (fp <= {1'b0, k_bppm1}) begin
          fpend <= 1;
          fpidx <= fp[1:0];
          fp <= fp + 1;
        end else
          fpend <= 0;
      end
      // Step 8 pixels right and blit the SAME row again - prow still holds it
      if (next_cell) begin
        rcnt <= rcnt - 3'd1;
        cell_x <= cell_x + 8'd8;
      end
    end
  end
endmodule
