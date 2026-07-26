// PPU display path: line-buffer read, overlay mix, screen palette, pixel out.
//
// Everything downstream of the engine. The engine has already composited this
// line into the back bank of the line buffer; this module walks the front bank
// at the pixel rate, mixes the overlay over it, maps the result through the
// screen palette and emits the 4-bit colour.
//
// This is the module `docs/hardware-gaps.md` entries 8 and 9 land in - overlay
// blit modes and overlay layer priority are both changes to the mix below, and
// neither of them should have to touch the engine FSM. The interface is
// deliberately narrow for that reason: a pixel from the line buffer, the
// overlay's own storage, and the registers that describe how to combine them.
//
// Overlay: 160x120 1bpp, byte = y*20 + x/8, bit 0 = leftmost pixel. Write-only
// from the CPU; the display owns the read port. Mixed ABOVE tiles and sprites
// at display time, which is why it costs no compositing clocks at all.
//
// Timing: the line-buffer read is issued on the pixel's first clock (by
// ppu_line, from `disp_slot`), the data and the overlay byte are registered on
// the second, and the colour is registered from them - so a pixel needs three
// system clocks, which is the contract rtl/top_simulator.sv's divide-by-3 and
// the golden testbench's PCLK both implement.
module ppu_display(input bit clk, input bit reset,
                   // Beam position and the display's line-buffer slot
                   input  logic [7:0]  hpos,
                   input  logic [6:0]  vpos,
                   input  logic        disp_slot,
                   input  logic [31:0] rd_data,      // front bank, one clock late
                   // Overlay CPU write port
                   input  bit          ovl_cs,
                   input  bit          rw,
                   input  logic [11:0] ovl_addr,
                   input  logic [7:0]  di,
                   input  logic        ovl_en,
                   input  logic [3:0]  ovl_color,
                   // Screen palette: written from the register file, read here
                   input  logic        spal_we,
                   input  logic [3:0]  spal_waddr,
                   input  logic [3:0]  spal_wdata,
                   input  logic [3:0]  spal_raddr,   // register readback
                   output logic [3:0]  spal_rdata,
                   output logic [3:0]  color);

  // Screen palette: remaps every displayed pixel, the overlay included
  logic [3:0] spal[0:15];
  always_ff @(posedge clk)
    if (reset)
      for (int k = 0; k < 16; k++)
        spal[k] <= k[3:0];
    else if (spal_we)
      spal[spal_waddr] <= spal_wdata;
  assign spal_rdata = spal[spal_raddr];

  // Overlay bitmap. Sized to 2560 bytes for a clean bound; 2400 are live.
  logic [7:0] ovl[0:2559];

  // The overlay byte for the current lane is fetched in parallel with the
  // line-buffer read (own block RAM, own port); y*20 is (y<<4) + (y<<2), so
  // the address is adder-only.
  wire [11:0] ovl_daddr = {1'b0, vpos, 4'b0} + {3'b0, vpos, 2'b0} + {7'b0, hpos[7:3]};
  logic [7:0] ovl_rdata;
  always_ff @(posedge clk)
    ovl_rdata <= ovl[ovl_daddr];

  always_ff @(posedge clk)
    if (ovl_cs && rw && ovl_addr < 12'd2560)
      ovl[ovl_addr] <= di;

  // Display pipeline: read issued on the pixel's first clock, colour
  // registered on the second (hpos is stable for the whole pixel)
  logic disp_rd_q;
  always_ff @(posedge clk)
    if (reset) begin
      disp_rd_q <= 0;
      color <= 0;
    end else begin
      disp_rd_q <= disp_slot;
      if (disp_rd_q) begin
        if (ovl_en && ovl_rdata[hpos[2:0]])
          color <= spal[ovl_color];
        else
          color <= spal[rd_data[{2'b0, hpos[2:0]} * 4 +: 4]];
      end
    end
endmodule
