`include "pll_gowin.v"

/**
 * Panel bring-up for the Tang Primer 20K + Dock with a MuseLab PMOD-TFTLCD
 * v1.1 on PMOD2. NOT the console - this exists to answer one question.
 *
 * By 2026-08-07 the board had proved, on hardware, that the 27 MHz input, the
 * rPLL, its /32 CLKOUTD, both user LEDs and the whole PMOD0 audio path work.
 * The panel stayed white through all of it. That leaves two candidates, and
 * they need separating before either is worth acting on:
 *
 *   1. the four PMOD2 balls do not reach the module, or
 *   2. they do, and rtl/lcd.sv's SPI framing is not what the panel accepts.
 *
 * Suspect 2 is structural rather than a slip. In lcd.sv the serialiser's `ordy`
 * is BOTH the panel's chip select and the clock of the state machine
 * (`always_ff @(posedge cs)`), so CS necessarily goes high between every byte.
 * Both plausible controllers say a high CSX resets the serial interface, which
 * would break exactly the multi-byte traffic the panel needs - CASET, RASET
 * and the pixel stream after RAMWR - while leaving single-byte commands like
 * SLPOUT and DISPON working. A panel that took DISPON and no pixels shows
 * uninitialised RAM, which is white.
 *
 * So this drives the same four pins with the simplest thing that could work:
 *
 *   * CS TIED LOW for the entire session. No per-byte deassertion anywhere.
 *   * SPI mode 0, MSB first, ~1.7 MHz, data changed on the falling edge and
 *     sampled by the panel on the rising one.
 *   * an init sequence restricted to commands ST7789 and ILI9341 agree on,
 *     with the 120 ms SLPOUT settle the datasheets ask for.
 *   * eight vertical colour bars, streamed forever.
 *
 * READING THE RESULT:
 *
 *   colour bars, leftmost RED     the pins are right and the panel is fine;
 *                                 lcd.sv's CS framing is the console's bug.
 *   colour bars, leftmost CYAN    same, but the controller is an ILI9341 and
 *                                 does not want the ST7789's INVON - drop
 *                                 0x21 from setup_st7789_565.hex.
 *   bars in the wrong place       MADCTL/geometry, not wiring.
 *   still white                   the four balls do not reach the module;
 *                                 suspect the PMOD2/PMOD3 assignment before
 *                                 anything else.
 *
 *   make tangprimer20k-lcdtest && make tangprimer20k-lcdtest-prog
 */
module top(input  bit clk,
           input  bit key1, input bit key2,
           output bit led_reset,
           output bit led_lock,
           output bit sda, output bit scl, output bit cs, output bit rs,
           output bit lcd_rst,
           output bit audio_pwm,
           output bit audio_pwm_r,
           output bit hp_bck, output bit hp_ws, output bit hp_din,
           output bit pa_en);

  localparam int W = 320, H = 240;

  wire pllclk, sysclk, pll_locked;      // sysclk = CLKOUTD = 14.0625 MHz
  pll_gowin pll0(.clock_in(clk), .clock_out(pllclk), .clock_div(sysclk),
                 .locked(pll_locked));

  // ---- the panel is never deselected -------------------------------------
  assign cs      = 1'b0;
  assign lcd_rst = 1'b1;                // module ties the panel's RESET to 3V3

  // ---- init table: only commands both controllers implement --------------
  // {rs, byte}; rs=0 command, rs=1 parameter.
  localparam int INIT_N = 18;
  function automatic logic [8:0] initrom(input int i);
    case (i)
      0:  initrom = 9'h011;             // SLPOUT   (then 120 ms)
      1:  initrom = 9'h03A;             // COLMOD
      2:  initrom = 9'h155;             //   16 bit/px - 0x55 on both parts
      3:  initrom = 9'h036;             // MADCTL
      4:  initrom = 9'h168;             //   landscape + BGR. Was 0x60 (RGB);
                                        //   the panel showed red as blue and
                                        //   blue as red, green/white/black
                                        //   unchanged - textbook BGR. Bit 3
                                        //   of MADCTL is the colour order.
      5:  initrom = 9'h02A;             // CASET
      6:  initrom = 9'h100;
      7:  initrom = 9'h100;
      8:  initrom = 9'h101;
      9:  initrom = 9'h13F;             //   0 .. 319
      10: initrom = 9'h02B;             // RASET
      11: initrom = 9'h100;
      12: initrom = 9'h100;
      13: initrom = 9'h100;
      14: initrom = 9'h1EF;             //   0 .. 239
      15: initrom = 9'h020;             // INVOFF - was INVON (0x21); see the colour note
      16: initrom = 9'h029;             // DISPON
      17: initrom = 9'h02C;             // RAMWR
      default: initrom = 9'h000;
    endcase
  endfunction

  // ---- byte shifter, SPI mode 0 ------------------------------------------
  logic [7:0] shreg;
  logic [3:0] nbit;
  logic       phase;                    // 0: drive data, sck low; 1: sck high
  logic       busy;
  logic       start;
  logic [8:0] tosend;

  always_ff @(posedge sysclk) begin
    if (!busy) begin
      scl <= 1'b0;
      if (start) begin
        shreg <= tosend[7:0];
        rs    <= tosend[8];
        nbit  <= 4'd8;
        phase <= 1'b0;
        busy  <= 1'b1;
        sda   <= tosend[7];
      end
    end else if (!phase) begin
      scl   <= 1'b1;                    // panel samples here; sda already set
      phase <= 1'b1;
    end else begin
      scl   <= 1'b0;
      phase <= 1'b0;
      nbit  <= nbit - 1'b1;
      if (nbit == 4'd1) busy <= 1'b0;
      else begin
        shreg <= {shreg[6:0], 1'b0};
        sda   <= shreg[6];
      end
    end
  end

  // ---- sequencer ---------------------------------------------------------
  // The wait ends on `&delay`, so the WIDTH is the delay: 22 bits is 2^22
  // counts, 298 ms at 14.0625 MHz. The panel needs 120 ms (~1,687,500 cycles).
  // The width tracks DYN_SDIV_SEL in rtl/pll_gowin.v - it was 20 bits at /32,
  // the same 298 ms, and leaving it there would have cut the wait to 75 ms.
  localparam int S_POR = 0, S_INIT = 1, S_WAIT = 2, S_PIX = 3;
  logic [1:0]  state = S_POR;
  logic [21:0] delay = 0;
  logic [4:0]  idx   = 0;
  logic [8:0]  x     = 0;
  logic [7:0]  y     = 0;
  logic        hi    = 1'b1;            // which byte of the pixel is next

  // FULL-SCREEN SOLID COLOURS, one per frame, ~0.7 s each.
  //
  // The bar pattern proved the panel works but left the colour mapping
  // ambiguous: sending black/blue/green/cyan/red showed
  // yellow/blue/magenta/cyan/white - two bars right and three wrong, which is
  // neither an inversion nor an R/B swap. Five samples of a mixed pattern are
  // not enough to solve that. One flat colour at a time is.
  //
  // Sent in this order, with INVON now removed:
  //     RED  GREEN  BLUE  WHITE  BLACK
  // Report what you actually see and the transform falls straight out:
  //   correct                     -> INVON was the whole problem (ILI9341)
  //   cyan/magenta/yellow/black/white -> still inverting; the panel needs
  //                                  INVON after all and something else is up
  //   red and blue exchanged      -> MADCTL's BGR bit, one bit in 0x36's param
  logic [2:0] colidx = 0;
  wire [15:0] pix = (colidx == 3'd0) ? 16'hF800    // red
                  : (colidx == 3'd1) ? 16'h07E0    // green
                  : (colidx == 3'd2) ? 16'h001F    // blue
                  : (colidx == 3'd3) ? 16'hFFFF    // white
                  :                    16'h0000;   // black

  always_ff @(posedge sysclk) begin
    start <= 1'b0;
    case (state)
      S_POR: begin                                   // let the panel settle
        delay <= delay + 1'b1;
        if (&delay) begin state <= S_INIT; delay <= 0; end
      end

      S_INIT: if (!busy && !start) begin
        tosend <= initrom(int'(idx));
        start  <= 1'b1;
        idx    <= idx + 1'b1;
        if (idx == 5'd0) state <= S_WAIT;            // SLPOUT needs 120 ms
        else if (idx == 5'(INIT_N - 1)) state <= S_PIX;
      end

      S_WAIT: begin
        delay <= delay + 1'b1;
        if (&delay) begin state <= S_INIT; delay <= 0; end
      end

      S_PIX: if (!busy && !start) begin
        tosend <= {1'b1, hi ? pix[15:8] : pix[7:0]};
        start  <= 1'b1;
        hi     <= ~hi;
        if (!hi) begin                               // finished a pixel
          if (x == 9'(W - 1)) begin
            x <= 0;
            if (y == 8'(H - 1)) begin
              y      <= 8'd0;
              colidx <= (colidx == 3'd4) ? 3'd0 : colidx + 1'b1;
            end else y <= y + 1'b1;
          end else x <= x + 1'b1;
        end
      end
      default: state <= S_POR;
    endcase
  end

  // ---- signs of life ------------------------------------------------------
  logic [25:0] raw = 0;
  always_ff @(posedge clk) raw <= raw + 1'b1;
  assign led_reset = raw[25];                        // still ticking
  assign led_lock  = (state == S_PIX) ? raw[23] : 1'b1;  // fast once streaming

  assign audio_pwm   = 1'b0;
  assign audio_pwm_r = 1'b0;
  assign hp_bck = 1'b0;
  assign hp_ws  = 1'b0;
  assign hp_din = 1'b0;
  assign pa_en  = 1'b0;

  /* verilator lint_off UNUSED */
  wire unused = &{key1, key2, pll_locked, pllclk, y, raw[24], raw[22:0]};
  /* verilator lint_on UNUSED */
endmodule
