`include "ppu_regs.sv"
`include "ppu_line.sv"
`include "ppu_display.sv"
`include "ppu_blit.sv"
`include "ppu_fetch.sv"
`include "ppu_map.sv"
`include "ppu_scan.sv"
// PPU: scrolling tilemap layer + sprite compositor, both fed from a shared
// sprite sheet. While line N is displayed, the engine composites line N+1
// into the back bank of a BRAM line buffer: clear, then one pass of tile
// blits (if enabled), then the sprite list in painter's order. Pixel value 0
// is transparent at every stage.
//
// Sprite sheet: 256 uniform 8-byte plane slots (one 8x8 bitplane each) in
// 2KB of block RAM. Sprites AND tiles reference patterns by plane-slot BASE
// ADDRESS; the bpp field doubles as the footprint (bpp consecutive slots,
// plane p row r at byte {base+p, r}). Every fetch is self-contained: no
// region config, no tables, no multiplies.
//
// Tilemap: 32x16 cells of {pal[3:0], bppm1[1:0], yflip, xflip, base[7:0]},
// wrapping over a 256x128-pixel world, scrolled by camera registers latched
// once per scanline. A tile is composited as a synthesized sprite entry at
// x = k*8 - (camera_x & 7) through the SAME fetch/blit pipeline - the 8-bit
// x wraparound makes the partial left-edge tile work with no extra logic.
// Cell $0000 is empty and skipped.
//
// Line buffer: 20 lanes x 32 bits (8 pixels x 4bpp), double-banked by an
// address bit. A row straddles at most two lanes -> 2-word RMW blit.
// Timing contract: pixels are >=3 system clocks wide (hpos advances at the
// pixel rate); the display side takes one line-buffer read slot per pixel.
//
// Register map ($400x, CPU and DMA share it):
//   $0  sheet address low          $8  list index
//   $1  sheet address high (3b)    $9  staged X
//   $2  sheet data (auto-inc)      $A  staged Y
//   $3  camera X                   $B  flags/commit (below)
//   $4  camera Y                   $C  active sprite count
//   $5  control: bit0 tilemap en,  $D  frame counter (RO, +1 per vsync)
//       bit1 overlay en            $E  staged pattern base
//   $6  overlay color (4 bits, sampled per displayed pixel)
//   $7  buttons (read-only): bit0 left, 1 right, 2 up, 3 down, 4 O, 5 X
//   $F  LFSR random byte (read-only, free-running)
//   $36 behind-split: list entries 0..split-1 composite BEFORE the tile
//       layer (background sprites), entries split..count-1 after. 0 (the
//       reset value) keeps the whole list in front - no extra scan cost
//       either way, the list is partitioned, never scanned twice.
//   $37 staged repeat count, in CELLS (0 and 1 both mean one cell, so the
//       reset value is the old behaviour). A committed entry blits its ONE
//       fetched row into that many consecutive 8-pixel cells, which is what
//       a flat run - a cloud, a bar, a floor - actually is. It costs one list
//       entry instead of N, and one sheet fetch instead of N.
//   $B: bit0 xflip, bit1 yflip, bits3:2 bpp-1, bits7:4 palette base
//       (pixel color = palette base + pixel value, mod 16); writing commits
//       the staged X/Y/base and auto-increments the list index
//
// Draw state ($4010-$403F, identity/full-screen defaults at reset):
//   $10-$1F draw palette   - remaps the post-base color of tiles+sprites
//   $20-$2F screen palette - remaps every displayed pixel (overlay too)
//   $30-$33 clip rectangle x0/y0/x1/y1 (inclusive; tiles+sprites only)
//   $34/$35 transparency mask lo/hi - bit v makes pixel VALUE v transparent
//
// Tilemap window (map_cs, write-only): cell low bytes (pattern base) at
// offset $000-$1FF, cell high bytes (attributes) at $200-$3FF.
//
// Overlay (ovl_cs, write-only): 160x120 1bpp bitmap, byte = y*20 + x/8,
// bit 0 = leftmost pixel. Mixed ABOVE tiles and sprites at display time
// (zero compositing cost): set bit -> overlay color, clear bit -> below
// layers show through.
module sprite_compositor(input bit clk, input bit reset,
              input bit cs, input bit rw, input logic [5:0] addr, input logic [7:0] di, output logic [7:0] dout,
              input bit map_cs, input logic [9:0] map_addr,
              input logic [7:0] btn,
              input bit ovl_cs, input logic [11:0] ovl_addr,
              input logic [7:0] hpos, input logic [6:0] vpos, input bit vsync, input bit hsync,
              output logic [3:0] color,
              // DMA interface
              input logic dma_active,
              input logic dma_write,
              input logic [3:0] dma_addr,
              input logic [7:0] dma_data);

  parameter H_DISPLAY = 160;
  parameter V_DISPLAY = 120;
  parameter MAX_SPRITES = 128;
  parameter SHEET_SLOTS = 256;             // 8-byte plane slots
  localparam LANES = H_DISPLAY / 8;        // 32-bit words per line
  localparam SHEET_BYTES = SHEET_SLOTS * 8;
  localparam TILE_COLS = LANES + 1;        // visible tile columns per line

  // ------------------------------------------------------------------
  // Register file: $00-$3F, the CPU/DMA port and the readback mux, in
  // ppu_regs.sv. It owns no storage that the engine reads - the pattern sheet
  // and the sprite list stay next to their read ports here, and arrive as
  // write strobes.
  // ------------------------------------------------------------------
  logic        sheet_we;
  logic [10:0] sheet_waddr;
  logic [7:0]  sheet_wdata;
  logic        list_we;
  logic [6:0]  list_waddr;
  logic [33:0] list_wdata;
  logic [7:0]  camera_x;
  logic [6:0]  camera_y;
  logic        tiles_en;
  logic        ovl_en;
  logic [3:0]  ovl_color;
  logic [7:0]  sp_count;
  logic [7:0]  bsplit;
  logic        pal_we, pal_sel, pal_rsel;
  logic [3:0]  pal_addr, pal_wdata, pal_raddr, pal_rdata;
  logic [15:0] palt_t;       // bit v -> pixel value v is transparent
  logic [7:0]  clip_x0, clip_x1;
  logic [6:0]  clip_y0, clip_y1;

  ppu_regs #(.H_DISPLAY(H_DISPLAY), .V_DISPLAY(V_DISPLAY)) regs(
    .clk, .reset,
    .cs, .rw, .addr, .di, .dout, .btn, .vsync,
    .dma_active, .dma_write, .dma_addr, .dma_data,
    .sheet_we, .sheet_waddr, .sheet_wdata,
    .list_we, .list_waddr, .list_wdata,
    .camera_x, .camera_y, .tiles_en, .ovl_en, .ovl_color,
    .sp_count, .bsplit,
    .pal_we, .pal_sel, .pal_addr, .pal_wdata,
    .pal_raddr, .pal_rsel, .pal_rdata,
    .palt_t,
    .clip_x0, .clip_x1, .clip_y0, .clip_y1);

  // The two palettes live with their readers - the draw palette in ppu_blit,
  // the screen palette in ppu_display - so only the readback port comes back.
  logic [3:0] dpal_rdata, spal_rdata;
  assign pal_rdata = pal_rsel ? spal_rdata : dpal_rdata;

  // Line buffer: two banks of LANES words, in ppu_line.sv. `bank` is the one
  // being displayed; the engine writes ~bank.
  logic bank;

  // Pixel-phase tracking: hpos advances once per displayed pixel
  logic [7:0] hpos_q;
  wire hpos_changed = hpos != hpos_q;
  wire disp_slot  = hpos_changed && (hpos < H_DISPLAY[7:0]);
  wire line_start = hpos_changed && (hpos == 8'd0);
  wire line_end   = hpos_changed && (hpos == H_DISPLAY[7:0]);

  // The line being composited (one ahead of the beam). >= so the vertical
  // sync line also composes line 0 instead of clobbering it.
  wire [6:0] next_line = (vpos >= V_DISPLAY - 1) ? 7'd0 : vpos + 7'd1;

  // ------------------------------------------------------------------
  // Compositing engine
  // ------------------------------------------------------------------
  // E_TMAP is one state, not two: the tilemap read now runs a column ahead of
  // the walk, so there is nothing left to wait for. See ppu_map.sv.
  typedef enum logic [3:0] { E_IDLE, E_CLEAR, E_TMAP, E_SCAN, E_FETCH, E_RD0, E_RD1, E_WR0, E_WR1 } estate_t;
  estate_t est;

  logic [4:0]  clear_i;
  logic        w0_wait, w1_wait;
  logic [6:0]  line_y;
  logic        tile_mode;    // the entry in flight came from the tile pass

  // Declared up front because the producer control below is written in terms
  // of them: iverilog rejects use before declaration even where Verilator and
  // yosys accept it.
  logic        map_at_end, map_empty;
  logic [33:0] map_entry;
  logic [33:0] entry_q;      // the entry in flight, latched at fetch_start
  logic        scan_valid, scan_hit, scan_exhausted, scan_pass;
  logic [33:0] scan_entry;
  logic        fetch_done, fetch_more, fetch_reused;
  logic [7:0]  cell_x;
  logic [7:0]  prow0, prow1, prow2, prow3;
  logic [4:0]  lane, lane1;
  logic        w0_valid, w1_valid;
  logic [31:0] w0_data, w1_data;
  logic [31:0] old_w0, old_w1;
  logic        eng_rd;
  logic [4:0]  eng_rlane;
  logic        wr_en;
  logic [4:0]  wr_lane;
  logic [31:0] wr_data;
  logic [31:0] rd_data;

  // ------------------------------------------------------------------
  // Producer control. The tile pass is (re)started at line_start and again
  // when the behind pass runs out; the scan advances whenever it is looking
  // at an entry it is not going to composite.
  // ------------------------------------------------------------------
  wire tk_reset = (est == E_SCAN) && !scan_hit && scan_exhausted &&
                  !scan_pass && tiles_en && !line_start;
  wire tk_step  = (est == E_TMAP) && !map_at_end && !line_start;

  wire scan_advance = !line_start &&
                      (((est == E_SCAN) && !scan_hit) ||
                       ((est == E_WR1) && !fetch_more && !tile_mode));
  wire scan_next_pass = (est == E_SCAN) && !scan_hit && scan_exhausted &&
                        !scan_pass && !line_start;

  // ------------------------------------------------------------------
  // The two entry producers. Both feed the same fetch/blit path, which is the
  // interface this change exists to make explicit: the engine below sequences
  // them, and neither knows about the other.
  // ------------------------------------------------------------------
  ppu_map #(.TILE_COLS(TILE_COLS)) tmap(
    .clk, .reset,
    .map_cs, .rw, .map_addr, .di,
    .line_start, .camera_x, .camera_y, .next_line, .line_y,
    .tk_reset(tk_reset), .tk_step(tk_step),
    .at_end(map_at_end), .cell_empty(map_empty), .entry(map_entry));

  ppu_scan #(.MAX_SPRITES(MAX_SPRITES)) scan(
    .clk, .reset,
    .list_we, .list_waddr, .list_wdata,
    .sp_count, .bsplit, .line_y,
    .line_start,
    .advance(scan_advance), .next_pass(scan_next_pass),
    .entry(scan_entry), .valid(scan_valid), .hit(scan_hit),
    .exhausted(scan_exhausted), .front_pass(scan_pass));

  // Entry decode, combinational from the held entry
  wire [7:0] e_x     = entry_q[7:0];
  wire [6:0] e_y     = entry_q[14:8];
  wire [7:0] e_base  = entry_q[22:15];
  wire       e_xf    = entry_q[23];
  wire       e_yf    = entry_q[24];
  wire [1:0] e_bppm1 = entry_q[26:25];
  wire [3:0] e_pal   = entry_q[30:27];
  wire [2:0] e_rep   = entry_q[33:31];   // extra cells after the first
  wire [6:0] dy      = line_y - e_y;
  wire [2:0] rowi    = dy[2:0] ^ {3{e_yf}};


  // Pattern fetch and the cell cursor, in ppu_fetch.sv.
  //
  // A fetch starts from either producer of entries: a non-empty tile cell, or
  // a list entry that hits this line. The tile path is the awkward one -
  // The cell position comes from entry_next rather than entry_q, because at
  // the clock `start` is sampled entry_q has not been written yet. `e_base`,
  // `rowi` and `e_bppm1` need no such care: they are only read while `run` is
  // high, by which time the latch has landed.
  wire tile_start   = (est == E_TMAP) && !map_at_end && !map_empty;
  wire sprite_start = (est == E_SCAN) && scan_hit;
  wire fetch_start  = !line_start && (tile_start || sprite_start);

  // The producer/consumer boundary, and the one register that makes it a
  // stream: whichever producer offers an entry, the fetch/blit path latches it
  // once and works from the copy. Muxing the two producers' *registers* on the
  // consumer side instead was measured and it costs 10 MHz of Fmax - the list
  // memory's output register folds into ppu_scan's entry, so the mux lands
  // between a block RAM output and the blit rather than in front of a
  // flip-flop.
  wire [33:0] entry_next = tile_start ? map_entry : scan_entry;

  // The row index for the entry about to be latched: ppu_fetch samples its
  // pattern key at `start`, one clock before entry_q holds the entry.
  wire [6:0] dy_next   = line_y - entry_next[14:8];
  wire [2:0] rowi_next = dy_next[2:0] ^ {3{entry_next[24]}};
  always_ff @(posedge clk)
    if (fetch_start)
      entry_q <= entry_next;


  ppu_fetch #(.SHEET_BYTES(SHEET_BYTES)) fetch(
    .clk, .reset,
    .sheet_we, .sheet_waddr, .sheet_wdata,
    .start(fetch_start),
    // Latched on the same clock as entry_q, so both come from entry_next
    .line_start,
    .start_x(entry_next[7:0]),
    .start_rep(entry_next[33:31]),
    .run((est == E_FETCH) && !line_start),
    .next_cell((est == E_WR1) && fetch_more && !line_start),
    .start_base(entry_next[22:15]),
    .start_rowi(rowi_next),
    .start_bppm1(entry_next[26:25]),
    .done(fetch_done), .more(fetch_more), .reused(fetch_reused), .cell_x,
    .prow0, .prow1, .prow2, .prow3);

  ppu_blit #(.LANES(LANES)) blit(
    .clk, .reset,
    .dpal_we(pal_we && !pal_sel), .dpal_waddr(pal_addr), .dpal_wdata(pal_wdata),
    .dpal_raddr(pal_raddr), .dpal_rdata,
    .prow0, .prow1, .prow2, .prow3,
    .e_xf, .e_bppm1, .e_pal, .cell_x, .line_y,
    .palt_t, .clip_x0, .clip_x1, .clip_y0, .clip_y1,
    .old_w0, .old_w1,
    .lane, .lane1, .w0_valid, .w0_data, .w1_valid, .w1_data);

  // Line buffer requests. The engine addresses by lane and never sees which
  // bank it is on - ppu_line owns that, and gives the display the read port
  // whenever it wants one.
  always_comb begin
    eng_rd    = (est == E_RD0) || (est == E_RD1);
    eng_rlane = (est == E_RD1) ? lane1 : lane;
  end

  always_comb begin
    wr_en = 0;
    wr_lane = 5'd0;
    wr_data = 32'd0;
    case (est)
      E_CLEAR: begin
        wr_en = 1;
        wr_lane = clear_i;
      end
      E_WR0: if (w0_valid) begin
        wr_en = 1;
        wr_lane = lane;
        wr_data = w0_data;
      end
      E_WR1: if (w1_valid) begin
        wr_en = 1;
        wr_lane = lane1;
        wr_data = w1_data;
      end
      default: ;
    endcase
  end

  ppu_line lbuf(
    .clk, .reset,
    .disp_slot, .disp_lane(hpos[7:3]), .line_end,
    .eng_rd, .eng_rlane,
    .eng_we(wr_en), .eng_wlane(wr_lane), .eng_wdata(wr_data),
    .rd_data, .bank);

  ppu_display display(
    .clk, .reset,
    .hpos, .vpos, .disp_slot, .rd_data,
    .ovl_cs, .rw, .ovl_addr, .di, .ovl_en, .ovl_color,
    .spal_we(pal_we && pal_sel), .spal_waddr(pal_addr), .spal_wdata(pal_wdata),
    .spal_raddr(pal_raddr), .spal_rdata,
    .color);

  // ------------------------------------------------------------------
  // The engine sequencer. All that is left of the ten-state FSM: it decides
  // WHEN each stage runs, and no longer holds any of their state.
  //
  //   clear -> behind-pass scan -> tile pass -> front-pass scan -> idle
  //
  // with every entry either producer offers going through the same
  // fetch -> read -> read -> write -> write path.
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (reset) begin
      est <= E_IDLE;
      tile_mode <= 0;
      w0_wait <= 0;
      w1_wait <= 0;
      hpos_q <= 0;
    end else begin
      hpos_q <= hpos;

      if (line_start) begin
        line_y <= next_line;
        clear_i <= 0;
        tile_mode <= 0;
        w0_wait <= 0;
        w1_wait <= 0;
        // The cell cursor and the repeat counter are deliberately NOT cleared
        // here. They were, and it was dead code: the only path to the states
        // that read them runs through E_FETCH, and the only path into E_FETCH
        // is a `start`, which writes both.
        est <= E_CLEAR;
      end else begin
        case (est)
          E_CLEAR: begin
            clear_i <= clear_i + 1;
            if (clear_i == LANES[4:0] - 1)
              est <= E_SCAN;   // behind pass first (instant when split = 0)
          end

          // One clock per column. The cell for tk is already in hand - the
          // read runs a column ahead - so this state decides and moves on:
          // an empty cell costs one clock, and a non-empty one starts its
          // blit on the next.
          E_TMAP:
            if (map_at_end) begin
              tile_mode <= 0;
              est <= E_SCAN;
            end else if (!map_empty)
              est <= E_FETCH;

          E_SCAN:
            if (scan_hit)
              est <= E_FETCH;
            else if (scan_exhausted) begin
              if (!scan_pass) begin
                // behind pass done: tile layer next, then the front pass.
                // With tiles off, stay in E_SCAN and let the cursor carry on
                // from the split.
                if (tiles_en) begin
                  tile_mode <= 1;
                  est <= E_TMAP;
                end
              end else
                est <= E_IDLE;
            end

          E_FETCH:
            if (fetch_done)
              est <= E_RD0;

          E_RD0:
            // Issue the word0 read when the display isn't using the port
            if (!disp_slot) begin
              w0_wait <= 1;
              est <= E_RD1;
            end

          E_RD1: begin
            if (w0_wait) begin
              old_w0 <= rd_data;  // word0 arrives one cycle after its read
              w0_wait <= 0;
            end
            if (!disp_slot) begin
              w1_wait <= 1;
              est <= E_WR0;
            end
          end

          E_WR0: begin
            if (w1_wait) begin
              old_w1 <= rd_data;
              w1_wait <= 0;
            end
            // merged word0 is written this cycle (write port, see above)
            est <= E_WR1;
          end

          E_WR1:
            // merged word1 is written this cycle. If the entry has cells left
            // to go, ppu_fetch steps the cursor 8 pixels right and the SAME
            // row is blitted again - a run pays one sheet fetch, not one per
            // cell.
            if (fetch_more)
              est <= E_RD0;
            else if (tile_mode)
              est <= E_TMAP;
            else
              est <= E_SCAN;

          default: ;  // E_IDLE waits for line_start
        endcase
      end
    end
  end

endmodule
