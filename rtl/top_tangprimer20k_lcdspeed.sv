`include "pll_gowin.v"

/**
 * SPI clock sweep for the MuseLab PMOD-TFTLCD on the Tang Primer 20K Dock.
 * NOT the console - this finds one number: how fast will this panel clock?
 *
 * That number decides the display architecture, so it is worth measuring rather
 * than reading off a datasheet. The arithmetic is unforgiving: a 320x240 frame
 * at 16 bpp is 1,228,800 bits, so 60 fps needs 73.7 Mbit/s on a single lane.
 * ILI9341's datasheet write cycle is 100 ns (10 MHz) and ST7789's is 66 ns
 * (15 MHz), yet modules routinely run several times that. Guessing either way
 * would be wrong - hence a sweep.
 *
 * HOW TO READ IT. The panel is filled with a solid colour, and each colour is a
 * different SPI clock. Six steps, ~2 s each, then it repeats:
 *
 *     RED      3.52 MHz     (what the console does today)
 *     GREEN    7.03 MHz
 *     BLUE    14.06 MHz
 *     YELLOW  18.75 MHz     (psgclk - one obvious place to take the clock from)
 *     CYAN    28.13 MHz
 *     WHITE   56.25 MHz     (pllclk/2 - the fastest integer option here)
 *
 * Each step draws its colour as a background with a 16-pixel GRID over it. The
 * grid is the point: a flat fill cannot reveal a bit slip, because losing a bit
 * from a run of identical bytes still yields identical bytes. A grid puts a
 * per-pixel phase in the stream, so any slip shows as drifting, jagged or
 * banded lines. Report the last step whose grid is straight and evenly spaced -
 * 20 vertical by 15 horizontal lines, all square.
 *
 * The initialisation sequence is always sent at the slowest rate, so a failure
 * is always the pixel stream and never a missed command. Both LEDs blink
 * throughout as proof the board is still configured and sweeping.
 *
 *   make tangprimer20k-lcdspeed && make tangprimer20k-lcdspeed-prog
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

  wire pllclk, pllclk_div32, pll_locked;      // 112.5 MHz, 3.515625 MHz
  pll_gowin pll0(.clock_in(clk), .clock_out(pllclk), .clock_div(pllclk_div32),
                 .locked(pll_locked));

  assign cs      = 1'b0;                      // never deselected
  assign lcd_rst = 1'b1;                      // module ties panel RESET to 3V3

  // ---- the sweep ---------------------------------------------------------
  // Half-period in pllclk cycles, so the bit rate is 112.5/(2*HALF) MHz.
  localparam int NSTEP = 6;
  function automatic logic [4:0] halfper(input int s);
    case (s)
      0: halfper = 5'd16;   //  3.52 MHz
      1: halfper = 5'd8;    //  7.03
      2: halfper = 5'd4;    // 14.06
      3: halfper = 5'd3;    // 18.75
      4: halfper = 5'd2;    // 28.13
      default: halfper = 5'd1;  // 56.25
    endcase
  endfunction
  function automatic logic [15:0] stepcolour(input int s);
    case (s)
      0: stepcolour = 16'hF800;  // red
      1: stepcolour = 16'h07E0;  // green
      2: stepcolour = 16'h001F;  // blue
      3: stepcolour = 16'hFFE0;  // yellow
      4: stepcolour = 16'h07FF;  // cyan
      default: stepcolour = 16'hFFFF;  // white
    endcase
  endfunction

  logic [2:0] step = 0;
  logic       sweeping = 0;                   // 0 while initialising
  wire [4:0]  half = sweeping ? halfper(int'(step)) : 5'd16;

  // ---- init table: commands both controllers implement --------------------
  localparam int INIT_N = 18;
  function automatic logic [8:0] initrom(input int i);
    case (i)
      0:  initrom = 9'h011;              // SLPOUT, then 120 ms
      1:  initrom = 9'h03A;              // COLMOD
      2:  initrom = 9'h155;              //   16 bpp
      3:  initrom = 9'h036;              // MADCTL
      4:  initrom = 9'h168;              //   landscape + BGR (measured)
      5:  initrom = 9'h02A;              // CASET
      6:  initrom = 9'h100;
      7:  initrom = 9'h100;
      8:  initrom = 9'h101;
      9:  initrom = 9'h13F;              //   0..319
      10: initrom = 9'h02B;              // RASET
      11: initrom = 9'h100;
      12: initrom = 9'h100;
      13: initrom = 9'h100;
      14: initrom = 9'h1EF;              //   0..239
      15: initrom = 9'h020;              // INVOFF (this panel does not invert)
      16: initrom = 9'h029;              // DISPON
      17: initrom = 9'h02C;              // RAMWR
      default: initrom = 9'h000;
    endcase
  endfunction

  // ---- byte shifter on pllclk, programmable rate --------------------------
  logic [7:0] shreg;
  logic [3:0] nbit;
  logic [4:0] cnt;
  logic       phase;
  logic       busy;
  logic       start;
  logic [8:0] tosend;

  always_ff @(posedge pllclk) begin
    if (!busy) begin
      scl <= 1'b0;
      cnt <= 5'd1;
      if (start) begin
        shreg <= tosend[7:0];
        rs    <= tosend[8];
        sda   <= tosend[7];
        nbit  <= 4'd8;
        phase <= 1'b0;
        busy  <= 1'b1;
      end
    end else if (cnt != half) begin
      cnt <= cnt + 1'b1;                 // hold the current half-period
    end else begin
      cnt <= 5'd1;
      if (!phase) begin
        scl   <= 1'b1;                   // panel samples here
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
  end

  // ---- sequencer ---------------------------------------------------------
  localparam int S_POR = 0, S_INIT = 1, S_WAIT = 2, S_PIX = 3;
  logic [1:0]  state = S_POR;
  logic [23:0] delay = 0;                // 112.5 MHz: 2^24 is 149 ms
  logic [4:0]  idx   = 0;
  logic [8:0]  x     = 0;
  logic [7:0]  y     = 0;
  logic        hi    = 1'b1;
  logic [27:0] dwell = 0;                // ~2.4 s per step at 112.5 MHz

  // A SOLID FILL CANNOT DETECT A BIT SLIP - lose a bit in a run of identical
  // bytes and you get identical bytes, so the panel looks perfect while the link
  // is broken. Overlay a 16-pixel grid: the background still identifies the
  // step, and any lost or smeared bit shifts the line phase, which turns the
  // grid into visible drift, jags or banding. Lines are the background inverted
  // so they contrast against every step colour including white.
  wire        grid = (x[3:0] == 4'd0) || (y[3:0] == 4'd0);
  wire [15:0] bg   = stepcolour(int'(step));
  wire [15:0] pix  = grid ? ~bg : bg;

  always_ff @(posedge pllclk) begin
    start <= 1'b0;
    case (state)
      S_POR: begin
        delay <= delay + 1'b1;
        if (&delay) begin state <= S_INIT; delay <= 0; end
      end

      S_INIT: if (!busy && !start) begin
        tosend <= initrom(int'(idx));
        start  <= 1'b1;
        idx    <= idx + 1'b1;
        if (idx == 5'd0) state <= S_WAIT;
        else if (idx == 5'(INIT_N - 1)) begin
          state    <= S_PIX;
          sweeping <= 1'b1;              // rate now follows `step`
        end
      end

      S_WAIT: begin
        delay <= delay + 1'b1;
        if (&delay) begin state <= S_INIT; delay <= 0; end
      end

      S_PIX: begin
        dwell <= dwell + 1'b1;
        if (&dwell) step <= (step == 3'(NSTEP - 1)) ? 3'd0 : step + 1'b1;
        if (!busy && !start) begin
          tosend <= {1'b1, hi ? pix[15:8] : pix[7:0]};
          start  <= 1'b1;
          hi     <= ~hi;
          if (!hi) begin
            if (x == 9'(W - 1)) begin
              x <= 0;
              y <= (y == 8'(H - 1)) ? 8'd0 : y + 1'b1;
            end else x <= x + 1'b1;
          end
        end
      end
      default: state <= S_POR;
    endcase
  end

  // ---- signs of life ------------------------------------------------------
  logic [25:0] raw = 0;
  always_ff @(posedge clk) raw <= raw + 1'b1;
  assign led_reset = raw[25];
  assign led_lock  = raw[23];

  assign audio_pwm   = 1'b0;
  assign audio_pwm_r = 1'b0;
  assign hp_bck = 1'b0;
  assign hp_ws  = 1'b0;
  assign hp_din = 1'b0;
  assign pa_en  = 1'b0;

  /* verilator lint_off UNUSED */
  wire unused = &{key1, key2, pll_locked, pllclk_div32, y, raw[24], raw[22:0]};
  /* verilator lint_on UNUSED */
endmodule
