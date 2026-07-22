// Scanline sprite compositor: renders up to MAX_SPRITES instances of one
// shared 8x8 1bpp pattern. While line N is displayed from the front line
// buffer, the engine walks the sprite list (one entry per clock, pipelined)
// and composites line N+1 into the back buffer. X flip is a reversed bit
// order on the fetched row, Y flip is an XOR on the row index - both free.
//
// Register map ($400x, CPU and DMA share it):
//   $0-$7  pattern rows (bit 0 = leftmost pixel)
//   $8     list index
//   $9     staged X
//   $A     staged Y
//   $B     flags {bit1: yflip, bit0: xflip} - write commits the staged
//          entry at the current index and auto-increments the index
//   $C     active sprite count
//   $D     frame counter (read-only, increments on vsync) - poll for a
//          change to pace one game-loop update per displayed frame
module sprite_compositor(input bit clk, input bit reset,
              input bit cs, input bit rw, input logic [3:0] addr, input logic [7:0] di, output logic [7:0] dout,
              input logic [7:0] hpos, input logic [6:0] vpos, input bit vsync, input bit hsync,
              output bit pixel,
              // DMA interface
              input logic dma_active,
              input logic dma_write,
              input logic [3:0] dma_addr,
              input logic [7:0] dma_data);

  parameter H_DISPLAY = 160;
  parameter V_DISPLAY = 120;
  parameter MAX_SPRITES = 128;

  // Shared pattern, register-based so the scan engine reads it combinationally
  logic [7:0] pattern[0:7];
  initial $readmemb("./rtl/sprite_pattern.bin", pattern);

  // Sprite list: {yflip, xflip, y[6:0], x[7:0]}
  logic [16:0] list[0:MAX_SPRITES-1];
  logic [7:0]  sp_index;
  logic [7:0]  sp_count;
  logic [7:0]  stage_x;
  logic [6:0]  stage_y;

  // Double-buffered scanline, 1bpp
  logic [H_DISPLAY-1:0] front_buf;
  logic [H_DISPLAY-1:0] back_buf;

  // Frame counter for CPU-side vsync pacing
  logic [7:0] frame_count;
  logic       vsync_q;

  // Scan engine state
  logic [7:0]  scan_i;
  logic [16:0] entry_q;
  logic        entry_valid;
  logic        busy;
  logic [6:0]  line_y;

  // The line being composited (one ahead of the beam). >= so the vertical
  // sync line (vpos == V_DISPLAY) also composes line 0 instead of clobbering
  // the buffer with an empty out-of-range line right before it displays.
  wire [6:0] next_line = (vpos >= V_DISPLAY - 1) ? 7'd0 : vpos + 7'd1;

  // Entry decode and row fetch, all combinational
  wire [7:0] entry_x = entry_q[7:0];
  wire [6:0] entry_y = entry_q[14:8];
  wire       xflip   = entry_q[15];
  wire       yflip   = entry_q[16];
  wire [6:0] dy      = line_y - entry_y;
  wire       row_hit = dy < 7'd8;
  wire [7:0] row     = pattern[dy[2:0] ^ {3{yflip}}];
  wire [7:0] row_bits = xflip ? {row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7]} : row;

  wire [7:0] count_eff = (sp_count > MAX_SPRITES[7:0]) ? MAX_SPRITES[7:0] : sp_count;

  always_ff @(posedge clk) begin
    if (reset) begin
      busy <= 0;
      entry_valid <= 0;
      back_buf <= '0;
      front_buf <= '0;
      pixel <= 0;
    end else begin
      // Display side: front buffer races the beam, back buffer swaps in at line end
      pixel <= front_buf[hpos];
      if (hpos == H_DISPLAY - 1)
        front_buf <= back_buf;

      // Compositing side
      if (hpos == 8'd0) begin
        back_buf <= '0;
        line_y <= next_line;
        scan_i <= 0;
        entry_valid <= 0;
        busy <= 1;
      end else if (busy) begin
        // Stage 2: blit the entry fetched last cycle
        if (entry_valid && row_hit)
          back_buf <= back_buf | ({{H_DISPLAY-8{1'b0}}, row_bits} << entry_x);
        // Stage 1: fetch the next entry
        if (scan_i < count_eff) begin
          entry_q <= list[scan_i[6:0]];
          entry_valid <= 1;
          scan_i <= scan_i + 1;
        end else begin
          if (!entry_valid)
            busy <= 0;
          entry_valid <= 0;
        end
      end
    end
  end

  // Register interface - DMA writes win over CPU access
  wire        reg_write = (dma_active && dma_write) || (cs && rw);
  wire [3:0]  reg_addr  = (dma_active && dma_write) ? dma_addr : addr;
  wire [7:0]  reg_data  = (dma_active && dma_write) ? dma_data : di;

  always_ff @(posedge clk) begin
    if (reset) begin
      sp_index <= 0;
      sp_count <= 0;
      frame_count <= 0;
      vsync_q <= 0;
    end else begin
      vsync_q <= vsync;
      if (vsync && !vsync_q)
        frame_count <= frame_count + 1;
    end

    if (!reset) begin
      if (reg_write) begin
        case (reg_addr)
          4'h8: sp_index <= reg_data;
          4'h9: stage_x <= reg_data;
          4'hA: stage_y <= reg_data[6:0];
          4'hB: begin
            list[sp_index[6:0]] <= {reg_data[1], reg_data[0], stage_y, stage_x};
            sp_index <= sp_index + 1;
          end
          4'hC: sp_count <= reg_data;
          4'hD, 4'hE, 4'hF: ;  // read-only / unmapped
          default: pattern[reg_addr[2:0]] <= reg_data;
        endcase
      end else if (cs && !rw) begin
        case (addr)
          4'h8: dout <= sp_index;
          4'hC: dout <= sp_count;
          4'hD: dout <= frame_count;
          4'h9, 4'hA, 4'hB, 4'hE, 4'hF: dout <= 8'h00;
          default: dout <= pattern[addr[2:0]];
        endcase
      end
    end
  end
endmodule
