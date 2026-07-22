// Scanline sprite compositor / PPU: renders up to MAX_SPRITES instances of a
// shared 8x8 pattern, each at a configurable depth of 1-4 bpp with its own
// palette base and X/Y flips. While line N is displayed, the engine walks the
// sprite list and composites line N+1 into the back bank of a BRAM line
// buffer.
//
// FPGA-space design (v2): the line buffer is 20 lanes x 32 bits (8 pixels x
// 4bpp) in block RAM, double-banked by an address bit. A sprite row lands in
// at most two adjacent lanes, so a blit is a 2-word read-modify-write (4
// cycles) using a 64-bit window shifter - this replaces the v1 design's two
// 160-bit flip-flop buffers and 160-bit dynamic OR-shifter, which did not
// scale to 4bpp. Priority is painter's order: later list entries overdraw
// earlier ones; pixel value 0 is transparent.
//
// Timing contract: pixels are >=4 system clocks wide (hpos advances at the
// pixel rate, the module clocks at the system rate). The display side issues
// one line-buffer read per pixel; the engine gets the read port on the
// remaining cycles.
//
// Register map ($400x, CPU and DMA share it):
//   $0-$7  pattern rows of the plane selected by $E (bit 0 = leftmost pixel)
//   $8     list index
//   $9     staged X
//   $A     staged Y
//   $B     flags - write commits the staged entry and increments the index:
//          bit0 xflip, bit1 yflip, bits3:2 bpp-1, bits7:4 palette base
//          (pixel color = palette base + pixel value, mod 16)
//   $C     active sprite count
//   $D     frame counter (read-only, increments on vsync)
//   $E     pattern plane select (0-3)
module sprite_compositor(input bit clk, input bit reset,
              input bit cs, input bit rw, input logic [3:0] addr, input logic [7:0] di, output logic [7:0] dout,
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
  localparam LANES = H_DISPLAY / 8;  // 32-bit words per line

  // Pattern planes: 4 planes x 8 rows, plane p row r at index {p, r}.
  // Register-based so the engine reads all four planes combinationally.
  logic [7:0] planes[0:31];
  initial $readmemb("./rtl/sprite_pattern.bin", planes);

  // Sprite list: {pal[3:0], bppm1[1:0], yflip, xflip, y[6:0], x[7:0]}
  logic [22:0] list[0:MAX_SPRITES-1];
  logic [7:0]  sp_index;
  logic [7:0]  sp_count;
  logic [7:0]  stage_x;
  logic [6:0]  stage_y;
  logic [1:0]  plane_sel;

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
  typedef enum logic [2:0] { E_IDLE, E_CLEAR, E_SCAN, E_RD1, E_WR0, E_WR1 } estate_t;
  estate_t est;

  logic [7:0]  scan_i;
  logic [4:0]  clear_i;
  logic [22:0] entry_q;
  logic        entry_valid;
  logic        w0_wait, w1_wait;
  logic [31:0] old_w0, old_w1;
  logic [6:0]  line_y;

  wire [7:0] count_eff = (sp_count > MAX_SPRITES[7:0]) ? MAX_SPRITES[7:0] : sp_count;

  // Entry decode and row fetch, combinational from the held entry
  wire [7:0] e_x     = entry_q[7:0];
  wire [6:0] e_y     = entry_q[14:8];
  wire       e_xf    = entry_q[15];
  wire       e_yf    = entry_q[16];
  wire [1:0] e_bppm1 = entry_q[18:17];
  wire [3:0] e_pal   = entry_q[22:19];
  wire [6:0] dy      = line_y - e_y;
  wire       hit     = (dy < 7'd8) && entry_valid;
  wire [2:0] rowi    = dy[2:0] ^ {3{e_yf}};
  wire [7:0] p0 = planes[{2'd0, rowi}];
  wire [7:0] p1 = planes[{2'd1, rowi}];
  wire [7:0] p2 = planes[{2'd2, rowi}];
  wire [7:0] p3 = planes[{2'd3, rowi}];
  wire [3:0] bmask = {e_bppm1 == 2'd3, e_bppm1 >= 2'd2, e_bppm1 >= 2'd1, 1'b1};

  // Per-pixel color and opacity for the 8-pixel row (after flips/bpp/palette)
  logic [31:0] packed32;
  logic [7:0]  opq8;
  always_comb begin
    for (int j = 0; j < 8; j++) begin
      logic [2:0] jj;
      logic [3:0] pix;
      jj = e_xf ? 3'd7 - j[2:0] : j[2:0];
      pix = {p3[jj], p2[jj], p1[jj], p0[jj]} & bmask;
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
    else if (est == E_SCAN && hit)
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
        clear_i <= 0;
        scan_i <= 0;
        entry_valid <= 0;
        w0_wait <= 0;
        w1_wait <= 0;
        est <= E_CLEAR;
      end else begin
        case (est)
          E_CLEAR: begin
            clear_i <= clear_i + 1;
            if (clear_i == LANES[4:0] - 1)
              est <= E_SCAN;
          end

          E_SCAN: begin
            if (hit) begin
              // Hold the entry and start the 2-word read-modify-write; the
              // read of word0 goes out this cycle unless the display owns
              // the port
              if (!disp_slot) begin
                w0_wait <= 1;
                est <= E_RD1;
              end
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
            // merged word1 is written this cycle; resume the scan
            entry_q <= list[scan_i[6:0]];
            if (scan_i < count_eff) begin
              entry_valid <= 1;
              scan_i <= scan_i + 1;
            end else
              entry_valid <= 0;
            est <= E_SCAN;
          end

          default: ;  // E_IDLE waits for line_start
        endcase
      end
    end
  end

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
      plane_sel <= 0;
      frame_count <= 0;
      vsync_q <= 0;
    end else begin
      vsync_q <= vsync;
      if (vsync && !vsync_q)
        frame_count <= frame_count + 1;

      if (reg_write) begin
        case (reg_addr)
          4'h8: sp_index <= reg_data;
          4'h9: stage_x <= reg_data;
          4'hA: stage_y <= reg_data[6:0];
          4'hB: begin
            list[sp_index[6:0]] <= {reg_data[7:2], reg_data[1], reg_data[0], stage_y, stage_x};
            sp_index <= sp_index + 1;
          end
          4'hC: sp_count <= reg_data;
          4'hE: plane_sel <= reg_data[1:0];
          4'hD, 4'hF: ;  // read-only / unmapped
          default: planes[{plane_sel, reg_addr[2:0]}] <= reg_data;
        endcase
      end else if (cs && !rw) begin
        case (addr)
          4'h8: dout <= sp_index;
          4'hC: dout <= sp_count;
          4'hD: dout <= frame_count;
          4'hE: dout <= {6'b0, plane_sel};
          4'h9, 4'hA, 4'hB, 4'hF: dout <= 8'h00;
          default: dout <= planes[{plane_sel, addr[2:0]}];
        endcase
      end
    end
  end
endmodule
