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
// Timing contract: pixels are >=4 system clocks wide (hpos advances at the
// pixel rate); the display side takes one line-buffer read slot per pixel.
//
// Register map ($400x, CPU and DMA share it):
//   $0  sheet address low          $8  list index
//   $1  sheet address high (3b)    $9  staged X
//   $2  sheet data (auto-inc)      $A  staged Y
//   $3  camera X                   $B  flags/commit (below)
//   $4  camera Y                   $C  active sprite count
//   $5  control: bit0 tilemap en   $D  frame counter (RO, +1 per vsync)
//                                  $E  staged pattern base
//   $B: bit0 xflip, bit1 yflip, bits3:2 bpp-1, bits7:4 palette base
//       (pixel color = palette base + pixel value, mod 16); writing commits
//       the staged X/Y/base and auto-increments the list index
//
// Tilemap window (map_cs, write-only): cell low bytes (pattern base) at
// offset $000-$1FF, cell high bytes (attributes) at $200-$3FF.
module sprite_compositor(input bit clk, input bit reset,
              input bit cs, input bit rw, input logic [3:0] addr, input logic [7:0] di, output logic [7:0] dout,
              input bit map_cs, input logic [9:0] map_addr,
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

  // Sprite sheet: plane slot s row r at byte {s, r}
  logic [7:0] sheet[0:SHEET_BYTES-1];
  initial $readmemb("./rtl/sprite_pattern.bin", sheet);
  logic [10:0] sheet_addr;   // CPU upload pointer

  // Sprite list: {pal[3:0], bppm1[1:0], yflip, xflip, base[7:0], y[6:0], x[7:0]}
  logic [30:0] list[0:MAX_SPRITES-1];
  logic [7:0]  sp_index;
  logic [7:0]  sp_count;
  logic [7:0]  stage_x;
  logic [6:0]  stage_y;
  logic [7:0]  stage_base;

  // Tilemap: 32x16 cells as two byte planes (low = base, high = attributes)
  logic [7:0] map_lo[0:511];
  logic [7:0] map_hi[0:511];
  logic [7:0] camera_x;
  logic [6:0] camera_y;
  logic       tiles_en;

  // Line buffer: 2 banks x LANES words of 8 pixels x 4bpp. Address bit 5
  // selects the bank, so a swap is a register toggle, not a buffer copy.
  logic [31:0] linebuf[0:63];
  logic        bank;    // bank being displayed; ~bank is composited

  // Frame counter for CPU-side vsync pacing
  logic [7:0] frame_count;
  logic       vsync_q;

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
  typedef enum logic [3:0] { E_IDLE, E_CLEAR, E_TMAP0, E_TMAP1, E_SCAN, E_FETCH, E_RD0, E_RD1, E_WR0, E_WR1 } estate_t;
  estate_t est;

  logic [7:0]  scan_i;
  logic [4:0]  clear_i;
  logic [30:0] entry_q;
  logic        entry_valid;
  logic        w0_wait, w1_wait;
  logic [31:0] old_w0, old_w1;
  logic [6:0]  line_y;

  // Per-line latched scroll state
  logic [7:0] camx_l;
  logic [6:0] wy_row;
  logic [4:0] tk;         // tile column cursor
  logic       tile_mode;
  wire [4:0]  tx0    = camx_l[7:3];
  wire [2:0]  xoff   = camx_l[2:0];
  wire [3:0]  ty     = wy_row[6:3];
  wire [2:0]  rowoff = wy_row[2:0];
  wire [7:0]  x_syn  = {tk, 3'b000} - {5'b0, xoff};
  wire [6:0]  y_syn  = line_y - {4'b0, rowoff};

  // Tile cell fetch (registered read, issued in E_TMAP0)
  wire [8:0] map_raddr = {ty, tx0 + tk};
  logic [7:0] map_rd_lo, map_rd_hi;
  always_ff @(posedge clk) begin
    map_rd_lo <= map_lo[map_raddr];
    map_rd_hi <= map_hi[map_raddr];
  end

  wire [7:0] count_eff = (sp_count > MAX_SPRITES[7:0]) ? MAX_SPRITES[7:0] : sp_count;

  // Entry decode, combinational from the held entry
  wire [7:0] e_x     = entry_q[7:0];
  wire [6:0] e_y     = entry_q[14:8];
  wire [7:0] e_base  = entry_q[22:15];
  wire       e_xf    = entry_q[23];
  wire       e_yf    = entry_q[24];
  wire [1:0] e_bppm1 = entry_q[26:25];
  wire [3:0] e_pal   = entry_q[30:27];
  wire [6:0] dy      = line_y - e_y;
  wire       hit     = (dy < 7'd8) && entry_valid;
  wire [2:0] rowi    = dy[2:0] ^ {3{e_yf}};
  wire [3:0] bmask   = {e_bppm1 == 2'd3, e_bppm1 >= 2'd2, e_bppm1 >= 2'd1, 1'b1};

  // Plane-row fetch pipeline: bpp reads from the sheet's dedicated read
  // port, address {base+p, rowi} - self-contained in the entry
  logic [7:0] prow[0:3];
  logic [2:0] fp;        // next plane to issue
  logic       fpend;     // a sheet read is in flight
  logic [1:0] fpidx;     // which plane it is for
  wire [10:0] sheet_eaddr = {e_base + {6'b0, fp[1:0]}, rowi};
  logic [7:0] sheet_rdata;
  always_ff @(posedge clk)
    sheet_rdata <= sheet[sheet_eaddr];

  // Per-pixel color and opacity for the 8-pixel row (after flips/bpp/palette)
  logic [31:0] packed32;
  logic [7:0]  opq8;
  always_comb begin
    for (int j = 0; j < 8; j++) begin
      logic [2:0] jj;
      logic [3:0] pix;
      jj = e_xf ? 3'd7 - j[2:0] : j[2:0];
      pix = {prow[3][jj], prow[2][jj], prow[1][jj], prow[0][jj]} & bmask;
      opq8[j] = |pix;
      packed32[j*4 +: 4] = e_pal + pix;
    end
  end

  // 64-bit window covering the two lanes the row can straddle
  wire [4:0]  lane   = e_x[7:3];
  wire [4:0]  lane1  = lane + 5'd1;
  wire [2:0]  off    = e_x[2:0];
  wire [63:0] data64 = {32'b0, packed32} << {off, 2'b00};
  wire [15:0] mask16 = {8'b0, opq8} << off;

  function automatic [31:0] merge(input [31:0] old, input [31:0] nw, input [7:0] m);
    for (int n = 0; n < 8; n++)
      merge[n*4 +: 4] = m[n] ? nw[n*4 +: 4] : old[n*4 +: 4];
  endfunction

  // Line buffer read port: display has priority, engine takes free cycles
  logic [5:0]  rd_addr;
  logic [31:0] rd_data;
  always_comb begin
    if (disp_slot)
      rd_addr = {bank, hpos[7:3]};
    else if (est == E_RD0)
      rd_addr = {~bank, lane};
    else if (est == E_RD1)
      rd_addr = {~bank, lane1};
    else
      rd_addr = 6'd0;
  end
  always_ff @(posedge clk)
    rd_data <= linebuf[rd_addr];

  // Line buffer write port: exclusively the engine's
  logic        wr_en;
  logic [5:0]  wr_addr;
  logic [31:0] wr_data;
  always_comb begin
    wr_en = 0;
    wr_addr = 6'd0;
    wr_data = 32'd0;
    case (est)
      E_CLEAR: begin
        wr_en = 1;
        wr_addr = {~bank, clear_i};
      end
      E_WR0: if (lane < LANES[4:0]) begin
        wr_en = 1;
        wr_addr = {~bank, lane};
        wr_data = merge(old_w0, data64[31:0], mask16[7:0]);
      end
      E_WR1: if (lane1 < LANES[4:0] && mask16[15:8] != 8'd0) begin
        wr_en = 1;
        wr_addr = {~bank, lane1};
        wr_data = merge(old_w1, data64[63:32], mask16[15:8]);
      end
      default: ;
    endcase
  end
  always_ff @(posedge clk)
    if (wr_en)
      linebuf[wr_addr] <= wr_data;

  // Display pipeline: read issued on the pixel's first clock, color
  // registered on the second (hpos is stable for the whole pixel)
  logic disp_rd_q;

  always_ff @(posedge clk) begin
    if (reset) begin
      est <= E_IDLE;
      bank <= 0;
      entry_valid <= 0;
      tile_mode <= 0;
      w0_wait <= 0;
      w1_wait <= 0;
      disp_rd_q <= 0;
      color <= 0;
      hpos_q <= 0;
    end else begin
      hpos_q <= hpos;

      // Display side
      disp_rd_q <= disp_slot;
      if (disp_rd_q)
        color <= rd_data[{2'b0, hpos[2:0]} * 4 +: 4];

      // The composed bank becomes the displayed bank during the sync pixel
      if (line_end)
        bank <= ~bank;

      // Engine
      if (line_start) begin
        line_y <= next_line;
        camx_l <= camera_x;
        wy_row <= camera_y + next_line;
        clear_i <= 0;
        tk <= 0;
        scan_i <= 0;
        entry_valid <= 0;
        tile_mode <= 0;
        w0_wait <= 0;
        w1_wait <= 0;
        est <= E_CLEAR;
      end else begin
        case (est)
          E_CLEAR: begin
            clear_i <= clear_i + 1;
            if (clear_i == LANES[4:0] - 1) begin
              tile_mode <= tiles_en;
              if (tiles_en)
                est <= E_TMAP0;
              else
                est <= E_SCAN;
            end
          end

          E_TMAP0: begin
            // Cell read for column tk goes out this cycle
            if (tk >= TILE_COLS[4:0]) begin
              tile_mode <= 0;
              entry_valid <= 0;
              est <= E_SCAN;
            end else
              est <= E_TMAP1;
          end

          E_TMAP1: begin
            tk <= tk + 1;
            if ({map_rd_hi, map_rd_lo} == 16'h0000)
              est <= E_TMAP0;   // empty cell, 2 cycles
            else begin
              // Synthesize a sprite entry for this tile and blit it through
              // the shared pipeline; y is chosen so dy lands on the tile row
              entry_q <= {map_rd_hi[7:4], map_rd_hi[3:2], map_rd_hi[1], map_rd_hi[0], map_rd_lo, y_syn, x_syn};
              entry_valid <= 1;
              prow[0] <= 0;
              prow[1] <= 0;
              prow[2] <= 0;
              prow[3] <= 0;
              fp <= 0;
              fpend <= 0;
              est <= E_FETCH;
            end
          end

          E_SCAN: begin
            if (hit) begin
              // Hold the entry and fetch its plane rows from the sheet
              prow[0] <= 0;
              prow[1] <= 0;
              prow[2] <= 0;
              prow[3] <= 0;
              fp <= 0;
              fpend <= 0;
              est <= E_FETCH;
            end else begin
              // Examine the next entry (1 per clock, pipelined)
              entry_q <= list[scan_i[6:0]];
              if (scan_i < count_eff) begin
                entry_valid <= 1;
                scan_i <= scan_i + 1;
              end else begin
                entry_valid <= 0;
                if (!entry_valid)
                  est <= E_IDLE;
              end
            end
          end

          E_FETCH: begin
            // Pipelined issue/capture: bpp reads, one per plane, then drain
            if (fpend)
              prow[fpidx] <= sheet_rdata;
            if (fp <= {1'b0, e_bppm1}) begin
              fpend <= 1;
              fpidx <= fp[1:0];
              fp <= fp + 1;
            end else begin
              fpend <= 0;
              if (!fpend)
                est <= E_RD0;
            end
          end

          E_RD0: begin
            // Issue the word0 read when the display isn't using the port
            if (!disp_slot) begin
              w0_wait <= 1;
              est <= E_RD1;
            end
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

          E_WR1: begin
            // merged word1 is written this cycle; go back for the next
            // tile column or the next list entry
            if (tile_mode)
              est <= E_TMAP0;
            else begin
              entry_q <= list[scan_i[6:0]];
              if (scan_i < count_eff) begin
                entry_valid <= 1;
                scan_i <= scan_i + 1;
              end else
                entry_valid <= 0;
              est <= E_SCAN;
            end
          end

          default: ;  // E_IDLE waits for line_start
        endcase
      end
    end
  end

  // ------------------------------------------------------------------
  // Tilemap CPU write port (write-only: the fetcher owns the read ports)
  // ------------------------------------------------------------------
  always_ff @(posedge clk)
    if (map_cs && rw && !map_addr[9])
      map_lo[map_addr[8:0]] <= di;
  always_ff @(posedge clk)
    if (map_cs && rw && map_addr[9])
      map_hi[map_addr[8:0]] <= di;

  // ------------------------------------------------------------------
  // Register interface - DMA writes win over CPU access
  // ------------------------------------------------------------------
  wire        reg_write = (dma_active && dma_write) || (cs && rw);
  wire [3:0]  reg_addr  = (dma_active && dma_write) ? dma_addr : addr;
  wire [7:0]  reg_data  = (dma_active && dma_write) ? dma_data : di;

  always_ff @(posedge clk) begin
    if (reset) begin
      sp_index <= 0;
      sp_count <= 0;
      sheet_addr <= 0;
      camera_x <= 0;
      camera_y <= 0;
      tiles_en <= 0;
      frame_count <= 0;
      vsync_q <= 0;
    end else begin
      vsync_q <= vsync;
      if (vsync && !vsync_q)
        frame_count <= frame_count + 1;

      if (reg_write) begin
        case (reg_addr)
          4'h0: sheet_addr[7:0] <= reg_data;
          4'h1: sheet_addr[10:8] <= reg_data[2:0];
          4'h2: begin
            sheet[sheet_addr] <= reg_data;
            sheet_addr <= sheet_addr + 1;
          end
          4'h3: camera_x <= reg_data;
          4'h4: camera_y <= reg_data[6:0];
          4'h5: tiles_en <= reg_data[0];
          4'h8: sp_index <= reg_data;
          4'h9: stage_x <= reg_data;
          4'hA: stage_y <= reg_data[6:0];
          4'hB: begin
            list[sp_index[6:0]] <= {reg_data[7:2], reg_data[1], reg_data[0], stage_base, stage_y, stage_x};
            sp_index <= sp_index + 1;
          end
          4'hC: sp_count <= reg_data;
          4'hE: stage_base <= reg_data;
          default: ;  // $6, $7, $D, $F: unmapped / read-only
        endcase
      end else if (cs && !rw) begin
        case (addr)
          4'h0: dout <= sheet_addr[7:0];
          4'h1: dout <= {5'b0, sheet_addr[10:8]};
          4'h3: dout <= camera_x;
          4'h4: dout <= {1'b0, camera_y};
          4'h5: dout <= {7'b0, tiles_en};
          4'h8: dout <= sp_index;
          4'hC: dout <= sp_count;
          4'hD: dout <= frame_count;
          4'hE: dout <= stage_base;
          default: dout <= 8'h00;
        endcase
      end
    end
  end
endmodule
