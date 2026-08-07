// Parameters come BEFORE the port list on purpose. They used to be declared in
// the module body while the ports referenced them, which yosys and Verilator
// accept but iverilog does not:
//
//   rtl/lcd.sv:7: error: Unable to bind wire/reg/memory `WIDTH' in `lcd'
//
// That is why this file had no bench for so long - it could not be elaborated
// by the simulator the rest of the benches use. rtl/lcd_tb.sv is that bench.
//
// ---------------------------------------------------------------------------
// SPI panel driver. Rewritten 2026-08-07 after the first hardware bring-up.
// ---------------------------------------------------------------------------
//
// TWO DEFECTS THIS REPLACES, both found on real hardware and neither visible in
// simulation:
//
// 1. CS DEASSERTED BETWEEN EVERY BYTE. The old version used the serialiser's
//    `ordy` as BOTH the panel's chip select and the clock of this state machine
//    (`always_ff @(posedge cs)`), so CS necessarily went high once per byte.
//    Both plausible controllers - ST7789 and ILI9341 - specify that a high CSX
//    RESETS the serial interface, which breaks precisely the multi-byte traffic
//    the panel needs: CASET, RASET and the pixel stream after RAMWR. Single-byte
//    commands still land, so the panel accepted DISPON and showed uninitialised
//    RAM: a white screen with every other subsystem working. The panel only came
//    up once a bring-up top drove it with CS tied low.
//
//    CS is now an ordinary output, asserted low for the whole session, and the
//    state machine has a real clock.
//
// 2. IT RAN AT THE CHIP CLOCK. Shifting one bit per 3.515625 MHz videoclk with a
//    dead cycle between bytes is 9 clocks per byte: 393 ms per 320x240 frame, or
//    2.5 fps, on a board carrying a 112.5 MHz PLL. This now runs on `clk` =
//    pllclk with a divided SCL.
//
// THE CLOCK, AND WHY IT IS NOT AS FAST AS THE PANEL ALLOWS. The panel was
// measured on hardware carrying 56.25 MHz cleanly - with a per-pixel grid
// pattern, because a flat fill cannot reveal a bit slip. The limit here is the
// PPU, not the link: `sprite_compositor.sv` needs 483 clocks per 160-pixel
// console line, i.e. 3.02 masterclk per console pixel, and the compositor only
// gets the clock slots the display leaves. SPI_HALF=2 gives SCL = pllclk/4 =
// 28.125 MHz, one LCD pixel per 64 pllclk, so a console pixel changes every 4
// masterclk and the compositor keeps its budget. That is 1.758 Mpx/s, 22.9 fps.
//
// Going faster needs the compositor to stop compositing every console line
// twice (it is triggered per LCD line, and the 2x upscale makes half of that
// work redundant) and a hold buffer so the duplicated LCD line does not consume
// ppu_line's single read port. Those unlock ~60 fps and are separate changes;
// this file deliberately stops short so each is measurable on its own.
//
// WHY NOT A FAST SHIFTER WITH A SLOW PIXEL SIDE. Because a per-byte handshake
// across the pllclk/masterclk boundary costs ~2 slow clocks - 569 ns - against
// the 142 ns the byte itself takes, so the crossing would dominate. Running the
// whole module in one domain avoids the question entirely until the hold buffer
// exists to answer it properly.
module lcd #(parameter WIDTH = 320,
             parameter HEIGHT = 240,
             parameter RGBSIZE = 16,
             // Byte-times spent in reset_lcd before initialisation begins. The
             // panel needs the real 65536; a bench does not, and simulating
             // them costs ~590k clocks before anything interesting happens.
             parameter RESET_WAIT = 16'hFFFF,
             // `clk` cycles per SCL half-period. SCL = clk / (2*SPI_HALF).
             parameter SPI_HALF = 2)
          (input bit clk, input bit reset,
           input logic [RGBSIZE-1:0] rgb,
           output bit sda, output bit scl, output bit cs, output bit rs,
           output bit vsync, output bit hsync,
           output logic [$clog2(HEIGHT)-1:0] vpos, output logic [$clog2(WIDTH)-1:0] hpos);

  localparam INIT_SIZE = 15;
  localparam WORD = 2;
  localparam RESOLUTION = WIDTH*HEIGHT*WORD;
  localparam DIVW = (SPI_HALF < 2) ? 1 : $clog2(SPI_HALF);
  // `clk` cycles the shifter takes per LCD pixel: two bytes, eight bits each,
  // two SCL phases per bit. Blanking reuses this so a blanked position is held
  // for exactly as long as a streamed one.
  localparam PIXCLK = 32 * SPI_HALF;
  localparam LINEBYTES = 2 * WIDTH;      // exactly two bytes per visible pixel

  // The panel is selected for the whole session. See defect 1 above.
  assign cs = 1'b0;

  logic [$clog2(WIDTH*HEIGHT):0] pos;

  assign hsync = hpos == WIDTH-1;

  logic [7:0] dataout;
  enum logic [2:0] { reset_lcd, initialize, start_frame, send_frame,
                     h_blank, v_blank } state;

  // Declared after `state`, not before it: iverilog requires declaration
  // before use and rejected the original ordering.
  // vsync marks the frame boundary. It USED to be `state == start_frame`, but
  // the frame now re-issues RAMWR from the blanking state without passing
  // through start_frame, so that expression never asserted - and the console
  // ticks its game loop on vsync, so the picture rendered while nothing moved.
  // Blanking with vpos at HEIGHT is the real frame boundary, and it lasts three
  // blanking ticks, far wider than one masterclk period.
  assign vsync = (state == h_blank) && (vpos == HEIGHT);

  // ---- byte shifter, SPI mode 0 ------------------------------------------
  // Data changes while SCL is low and the panel samples it on the rising edge.
  // `byte_done` is a single-cycle pulse as the last bit's high phase ends.
  logic [7:0]      shreg;
  logic [3:0]      nbit;
  logic [DIVW-1:0] divcnt;
  logic            sclph;              // 0: SCL low half, 1: SCL high half
  logic            busy;
  logic            byte_done;
  logic            load;               // state machine asks for a byte

  always_ff @(posedge clk) begin
    byte_done <= 1'b0;
    if (reset) begin
      busy   <= 1'b0;
      scl    <= 1'b0;
      sda    <= 1'b0;
      nbit   <= 4'd0;
      divcnt <= '0;
      sclph  <= 1'b0;
    end else if (!busy) begin
      scl <= 1'b0;
      if (load) begin
        shreg  <= dataout;
        sda    <= dataout[7];
        nbit   <= 4'd8;
        sclph  <= 1'b0;
        divcnt <= '0;
        busy   <= 1'b1;
      end
    end else if (divcnt != DIVW'(SPI_HALF - 1)) begin
      divcnt <= divcnt + 1'b1;
    end else begin
      divcnt <= '0;
      if (!sclph) begin
        scl   <= 1'b1;                 // sample edge; sda has been stable
        sclph <= 1'b1;
      end else begin
        scl   <= 1'b0;
        sclph <= 1'b0;
        nbit  <= nbit - 1'b1;
        if (nbit == 4'd1) begin
          busy      <= 1'b0;
          byte_done <= 1'b1;
        end else begin
          shreg <= {shreg[6:0], 1'b0};
          sda   <= shreg[6];
        end
      end
    end
  end

  // ---- initialisation table ----------------------------------------------
  logic  [3:0] counter;
  logic [15:0] waittimer;
  logic [$clog2(32*64)-1:0] blkcnt;
  logic [$clog2(2*WIDTH)-1:0] bcnt;      // byte within the current line
  wire  [$clog2(2*WIDTH)-1:0] bcnt_next = bcnt + 1'b1;
  logic [RGBSIZE-1:0] pixreg;            // the pixel currently being sent
  logic  [8:0] rom [0:INIT_SIZE];
  wire   [8:0] command = rom[counter];

  initial $readmemh("setup_st7789_565.hex", rom);

  // ---- sequencer ----------------------------------------------------------
  // Advances one byte per `byte_done`. hpos/vpos are consumed by the PPU in the
  // masterclk domain; a pixel is 32*SPI_HALF `clk` cycles, always a multiple of
  // the 32:1 pllclk:masterclk ratio, so a naive update would land exactly on a
  // masterclk edge every time. Updating on `byte_done` - one cycle after the
  // last SCL falling edge - offsets it by one pllclk and leaves 31 cycles of
  // setup before the masterclk edge that samples it.
  always_ff @(posedge clk) begin
    if (reset) begin
      dataout   <= 0;
      counter   <= 0;
      state     <= reset_lcd;
      waittimer <= RESET_WAIT;
      load      <= 1'b1;
      rs        <= 1'b0;
      pos       <= 0;
      bcnt      <= '0;
      hpos      <= 0;
      vpos      <= 0;
    end else begin
      load <= 1'b0;                    // one-cycle request per completed byte

      // Blanking advances the position counters on a timer rather than on byte
      // completions, because no bytes are sent. Each blanked position is held
      // for one pixel time so the PPU, sampling on its own slower clock, cannot
      // miss the hpos == H_DISPLAY edge that swaps the bank.
      if (state == h_blank || state == v_blank) begin
        blkcnt <= blkcnt + 1'b1;
        if (blkcnt == PIXCLK[$bits(blkcnt)-1:0]) begin
          blkcnt <= '0;
          // hpos walks 320 -> 321 -> 0, and only the tick AFTER it reaches 0
          // resumes streaming. That extra tick is what makes the first pixel of
          // the line correct: `pixreg <= rgb` needs hpos AND vpos already at
          // their new values, and updating them on the same edge as the latch
          // samples the end of the previous row instead. vpos is advanced when
          // hpos wraps, one tick early, for the same reason.
          if (hpos == 0) begin
            if (vpos == HEIGHT) begin
              // FRAME END. Re-issue RAMWR to reset the panel's address pointer.
              // Reaching HEIGHT is the only frame-end signal: dropping this test
              // let the counter run past the last row into 240, 241, ... and the
              // panel's 320x240 window wrapped, scrolling the picture upward one
              // row per frame.
              state   <= send_frame;
              bcnt    <= '1;
              hpos    <= 0;
              vpos    <= 0;
              rs      <= 1'b0;
              dataout <= 8'h2C;
              load    <= 1'b1;
            end else begin
              // Re-issue RAMWR directly rather than routing through
              // start_frame. Going via start_frame meant this cycle had to
              // assert `load` to restart the idle shifter, which emitted a
              // STALE dataout byte before RAMWR - one extra byte per frame, so
              // every frame began one byte further on and the picture scrolled
              // upward a row at a time. The bench decodes a single frame and is
              // structurally blind to inter-frame drift.
              state   <= send_frame;      // next line
              bcnt    <= '0;
              pixreg  <= rgb;             // hpos=0, vpos already advanced
              dataout <= rgb[RGBSIZE-1:8];
              rs      <= 1'b1;
              load    <= 1'b1;
            end
          end else begin
            hpos <= hpos + 1;
            if (hpos >= WIDTH + 1) begin
              hpos <= 0;
              vpos <= vpos + 1;           // may reach HEIGHT: the frame marker
            end
          end
        end
      end else if (byte_done) begin
        load <= 1'b1;
        case (state)
          reset_lcd: begin
            rs      <= 0;
            dataout <= 8'h11;
            waittimer <= waittimer - 1;
            if (waittimer == 0) state <= initialize;
          end

          initialize: begin
            if (counter == INIT_SIZE) state <= start_frame;
            counter <= counter + 1;
            rs      <= command[8];
            dataout <= command[7:0];
          end

          start_frame: begin
            pos     <= 0;
            // bcnt starts at all-ones so bcnt_next wraps to 0, an EVEN index,
            // and the first send_frame cycle therefore queues a pixel's HIGH
            // byte. Starting it at 0 makes that first cycle see an odd index and
            // emit a low byte from a stale pixreg - one extra byte before the
            // pixel stream, which shifts every pixel to {lo(n), hi(n+1)} and
            // makes the whole frame look byte-swapped.
            bcnt    <= '1;
            hpos    <= 0;
            vpos    <= 0;
            rs      <= 0;
            dataout <= 8'h2C;
            state   <= send_frame;
          end

          send_frame: begin
            rs      <= 1;
            // BOTH BYTES OF A PIXEL MUST COME FROM ONE SAMPLE OF `rgb`. hpos
            // advances on the same cycle that queues a byte, so reading rgb
            // twice - once per byte - straddles two pixels: the high byte from
            // one and the low byte from the next. On hardware that produced
            // colours no inversion or channel swap can explain, white text
            // coming out green being the giveaway (white is symmetric under
            // both). Latch the pixel when queueing its high byte and serve the
            // low byte from the latch.
            if (!bcnt_next[0]) begin
              pixreg  <= rgb;
              dataout <= rgb[15:8];
            end else
              dataout <= pixreg[7:0];

            // Pixels are streamed only for the visible window. THE BLANKING
            // IS NOT COSMETIC: sprite_compositor.sv swaps the line-buffer bank
            // on `hpos == H_DISPLAY` (160 in console coordinates) and composes
            // `vpos + 1`, so the console's hpos MUST reach 160 and its vpos
            // MUST reach 120 or the bank never swaps and the display reads a
            // buffer the engine never released - a black screen. scalescreen
            // halves these, so the LCD counters have to run two columns and two
            // rows past the visible area. Those positions carry no bytes to the
            // panel, which only wants 320x240, so they are timed out here
            // instead of being driven by byte completions.
            // STRIDE MUST BE EXACT. hpos used to be incremented on pos[1],
            // which fires at pos = 2,3 mod 4 - so it advanced in bursts and hit
            // WIDTH-1 after ~638 bytes rather than exactly 640. The original
            // code streamed RESOLUTION bytes straight through and let the
            // panel's own address auto-increment find the row boundaries, so
            // the phase never mattered; adding a per-line boundary made it
            // matter and sheared every row against the one above. Derive the
            // position from the byte counter instead of accumulating it.
            // `dataout`/`load` are a one-deep pipeline: this cycle queues the
            // byte the shifter will send NEXT. So everything here addresses
            // bcnt+1, and the line ends by SUPPRESSING the load rather than by
            // stopping the counter - otherwise the entering-blank cycle emits
            // one byte too many, the leaving-blank cycle emits another, and the
            // line is 642 bytes instead of 640. Two extra bytes is one extra
            // pixel, which walks every row one pixel right of the one above.
            if (bcnt_next == LINEBYTES) begin
              load   <= 1'b0;                    // this line is complete
              bcnt   <= '0;
              hpos   <= WIDTH;                   // blanking starts at 320
              state  <= h_blank;
              blkcnt <= '0;
            end else begin
              bcnt <= bcnt_next;
              // hpos LEADS the latch by one pixel. `pixreg <= rgb` happens on
              // the same edge that advances hpos, so without the lead the sample
              // belongs to the previous pixel and the whole image lags one
              // column - 7,739 pixels wrong in the bench, all of them the
              // neighbour's colour.
              hpos <= bcnt_next[$bits(bcnt)-1:1] + 1;
            end
          end

          h_blank: ;                       // handled outside the byte_done gate
          v_blank: ;
        endcase
      end
    end
  end
endmodule
