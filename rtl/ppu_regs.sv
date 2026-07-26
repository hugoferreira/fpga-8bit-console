// PPU register file: $4000-$403F, the CPU/DMA port, and the readback mux.
//
// Everything here is configuration; nothing here is a datapath. The two
// memories the CPU writes through this port - the pattern sheet ($02) and the
// sprite list ($0B) - live with the engine blocks that read them, so this
// module exposes them as write strobes rather than owning the storage. That is
// the whole point of the split: a register is a fact about the CPU interface,
// while a memory is a fact about the pipeline stage that reads it.
//
// Register map (unchanged - this module is a lift, not a redesign):
//   $0  sheet address low          $8  list index
//   $1  sheet address high (3b)    $9  staged X
//   $2  sheet data (auto-inc)      $A  staged Y
//   $3  camera X                   $B  flags/commit
//   $4  camera Y                   $C  active sprite count
//   $5  control: bit0 tilemap en,  $D  frame counter (RO, +1 per vsync)
//       bit1 overlay en            $E  staged pattern base
//   $6  overlay color              $F  LFSR random byte (RO, free-running)
//   $7  buttons (RO)
//   $10-$1F draw palette           $30-$33 clip rectangle x0/y0/x1/y1
//   $20-$2F screen palette         $34/$35 transparency mask lo/hi
//   $36 behind-split               $37 staged repeat count, in cells
//
// The two palettes are handled the same way as the sheet and the list, and for
// the same reason: they are small memories, read by the blit (draw) and the
// display (screen) rather than by the CPU interface, so they live next to their
// readers and only their write port and one readback port come from here.
//
// This is not a stylistic preference - it is the only form that costs nothing.
// Measured, against a 1846 LUT4 baseline: passing them out as flat 64-bit
// vectors written by dynamic part-select is +140, keeping them as arrays here
// and flattening onto the port is +74, and flattening then unpacking again on
// the far side is +366 (the reads stop collapsing into mux trees). yosys does
// not accept an unpacked array port at all. A write strobe is +0.
module ppu_regs(input bit clk, input bit reset,
                input bit cs, input bit rw, input logic [5:0] addr,
                input logic [7:0] di, output logic [7:0] dout,
                input logic [7:0] btn,
                input bit vsync,
                // DMA interface (writes win over CPU access)
                input logic dma_active,
                input logic dma_write,
                input logic [3:0] dma_addr,
                input logic [7:0] dma_data,
                // Pattern sheet write port; the array lives in ppu_fetch
                output logic        sheet_we,
                output logic [10:0] sheet_waddr,
                output logic [7:0]  sheet_wdata,
                // Sprite list write port; the array lives in ppu_scan
                output logic        list_we,
                output logic [6:0]  list_waddr,
                output logic [33:0] list_wdata,
                // Configuration
                output logic [7:0]  camera_x,
                output logic [6:0]  camera_y,
                output logic        tiles_en,
                output logic        ovl_en,
                output logic [3:0]  ovl_color,
                output logic [7:0]  sp_count,
                output logic [7:0]  bsplit,
                // Palette write port and readback port; the arrays live with
                // the blit (draw) and the display (screen)
                output logic        pal_we,
                output logic        pal_sel,      // 0 = draw, 1 = screen
                output logic [3:0]  pal_addr,
                output logic [3:0]  pal_wdata,
                output logic [3:0]  pal_raddr,
                output logic        pal_rsel,
                input  logic [3:0]  pal_rdata,
                output logic [15:0] palt_t,
                output logic [7:0]  clip_x0,
                output logic [7:0]  clip_x1,
                output logic [6:0]  clip_y0,
                output logic [6:0]  clip_y1);

  parameter H_DISPLAY = 160;
  parameter V_DISPLAY = 120;

  logic [10:0] sheet_addr;   // CPU upload pointer, auto-incrementing
  logic [7:0]  sp_index;
  logic [7:0]  stage_x;
  logic [6:0]  stage_y;
  logic [7:0]  stage_base;
  logic [2:0]  stage_rep;
  logic [7:0]  frame_count;
  logic        vsync_q;
  logic [15:0] lfsr;         // free-running, taps 16/14/13/11


  // DMA writes win over CPU access
  wire        reg_write = (dma_active && dma_write) || (cs && rw);
  wire [5:0]  reg_addr  = (dma_active && dma_write) ? {2'b00, dma_addr} : addr;
  wire [7:0]  reg_data  = (dma_active && dma_write) ? dma_data : di;

  // The two memory write ports. Both are pure functions of the register write,
  // so the arrays can sit wherever their read port is.
  assign sheet_we    = reg_write && (reg_addr == 6'h02);
  assign sheet_waddr = sheet_addr;
  assign sheet_wdata = reg_data;

  // $10-$1F is the draw palette, $20-$2F the screen palette
  assign pal_we    = reg_write && (reg_addr[5:4] == 2'b01 || reg_addr[5:4] == 2'b10);
  assign pal_sel   = reg_addr[5];
  assign pal_addr  = reg_addr[3:0];
  assign pal_wdata = reg_data[3:0];
  assign pal_raddr = addr[3:0];
  assign pal_rsel  = addr[4];

  assign list_we    = reg_write && (reg_addr == 6'h0B);
  assign list_waddr = sp_index[6:0];
  assign list_wdata = {stage_rep, reg_data[7:2], reg_data[1], reg_data[0],
                       stage_base, stage_y, stage_x};

  always_ff @(posedge clk) begin
    if (reset) begin
      sp_index <= 0;
      sp_count <= 0;
      sheet_addr <= 0;
      camera_x <= 0;
      camera_y <= 0;
      tiles_en <= 0;
      ovl_en <= 0;
      ovl_color <= 0;
      frame_count <= 0;
      vsync_q <= 0;
      lfsr <= 16'hACE1;
      bsplit <= 0;
      stage_rep <= 0;
      palt_t <= 16'h0001;
      clip_x0 <= 0;
      clip_y0 <= 0;
      clip_x1 <= H_DISPLAY[7:0] - 1;
      clip_y1 <= V_DISPLAY[6:0] - 1;
    end else begin
      vsync_q <= vsync;
      if (vsync && !vsync_q)
        frame_count <= frame_count + 1;
      lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

      if (reg_write) begin
        case (reg_addr)
          6'h30: clip_x0 <= reg_data;
          6'h31: clip_y0 <= reg_data[6:0];
          6'h32: clip_x1 <= reg_data;
          6'h33: clip_y1 <= reg_data[6:0];
          6'h34: palt_t[7:0] <= reg_data;
          6'h35: palt_t[15:8] <= reg_data;
          6'h36: bsplit <= reg_data;
          6'h00: sheet_addr[7:0] <= reg_data;
          6'h01: sheet_addr[10:8] <= reg_data[2:0];
          6'h02: sheet_addr <= sheet_addr + 1;   // the byte goes out on sheet_we
          6'h03: camera_x <= reg_data;
          6'h04: camera_y <= reg_data[6:0];
          6'h05: begin
            tiles_en <= reg_data[0];
            ovl_en <= reg_data[1];
          end
          6'h06: ovl_color <= reg_data[3:0];
          6'h08: sp_index <= reg_data;
          6'h09: stage_x <= reg_data;
          6'h0A: stage_y <= reg_data[6:0];
          6'h0B: sp_index <= sp_index + 1;       // the entry goes out on list_we
          6'h0C: sp_count <= reg_data;
          6'h0E: stage_base <= reg_data;
          // Repeat count in CELLS: 0 and 1 both mean one cell, so the reset
          // value leaves every existing program unchanged. Clamped to 8.
          6'h37: stage_rep <= (reg_data == 8'd0)   ? 3'd0 :
                              (reg_data >= 8'd8)   ? 3'd7 :
                                                     reg_data[2:0] - 3'd1;
          default: ;  // $6, $7, $D, $F: unmapped / read-only
        endcase
      end else if (cs && !rw) begin
        casez (addr)
          6'h00: dout <= sheet_addr[7:0];
          6'h01: dout <= {5'b0, sheet_addr[10:8]};
          6'h03: dout <= camera_x;
          6'h04: dout <= {1'b0, camera_y};
          6'h05: dout <= {6'b0, ovl_en, tiles_en};
          6'h06: dout <= {4'b0, ovl_color};
          6'h07: dout <= btn;
          6'h08: dout <= sp_index;
          6'h0C: dout <= sp_count;
          6'h0D: dout <= frame_count;
          6'h0E: dout <= stage_base;
          6'h37: dout <= {5'd0, stage_rep} + 8'd1;
          // $10-$1F and $20-$2F. This arm matches $10-$1F only, and inside
          // that range addr[4] is always 1, so a DRAW palette read returns the
          // SCREEN entry and $20-$2F fall through to the default and read 0.
          // Both are wrong and both are preserved: refactor-ppu-core is
          // behaviour-preserving, and rtl/ppu_golden_tb.sv asserts it as it is.
          // Recorded in docs/hardware-gaps.md.
          6'b01????: dout <= {4'b0, pal_rdata};
          6'h30: dout <= clip_x0;
          6'h31: dout <= {1'b0, clip_y0};
          6'h32: dout <= clip_x1;
          6'h33: dout <= {1'b0, clip_y1};
          6'h34: dout <= palt_t[7:0];
          6'h35: dout <= palt_t[15:8];
          6'h36: dout <= bsplit;
          6'h0F: dout <= lfsr[7:0];
          default: dout <= 8'h00;
        endcase
      end
    end
  end
endmodule
