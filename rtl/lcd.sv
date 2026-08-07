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
// THE CLOCK, AND WHAT ACTUALLY SETS THE FRAME RATE. The panel was measured on
// hardware carrying 56.25 MHz cleanly - with a per-pixel grid pattern, because
// a flat fill cannot reveal a bit slip. Frame time is
//
//     240 lines * 322 pixel-slots * PIXCLK pllclk,
//     PIXCLK = bits_per_pixel * 2 * SPI_HALF
//
// so RGB565 at SPI_HALF=1 is 45.5 fps and RGB444 at SPI_HALF=1 is 60.6.
//
// THE COMPOSITOR IS NOT THE LIMIT, and this file used to say it was. The claim
// was that sprite_compositor.sv "needs 483 clocks per console line, i.e. 3.02
// masterclk per console pixel". 483 is the BUDGET - 161 console pixels at the
// 3 clocks ppu_display takes for each - not the demand. The demand is measured
// and committed in rtl/golden/ppu_cycles.txt, and its worst case across ten
// scenes is 313. The engine has never been within 35% of running out.
//
// What limited the machine was the chip-clock divider, through two constraints
// that have nothing to do with how much work the engine does:
//
//   1. ppu_display needs >= 3 chip clocks per CONSOLE pixel, and a console
//      pixel is 2*PIXCLK pllclk. At the old 32:1 divider that forced
//      PIXCLK >= 48 - RGB444 at SPI_HALF=2, 30.3 fps, and no arrangement of
//      the PPU could beat it.
//   2. PIXCLK must stay an integer multiple of the divider, for the phase
//      argument in the sequencer below.
//
// At 8:1 both hold for PIXCLK=24: 60.6 fps, a console pixel every 6 chip
// clocks, and 966 chip clocks a line against the engine's 313.
//
// WHY NOT A FAST SHIFTER WITH A SLOW PIXEL SIDE. Because a per-byte handshake
// across the pllclk/masterclk boundary costs ~2 slow clocks against the ~142 ns
// the byte itself takes, so the crossing would dominate. Running the whole
// module in one domain avoids the question entirely.
module lcd #(parameter WIDTH = 320,
             parameter HEIGHT = 240,
             // 16 = RGB565, two bytes a pixel, COLMOD 0x05.
             // 12 = RGB444, THREE BYTES PER TWO PIXELS, COLMOD 0x03. 25% fewer
             // bytes a frame on a link that is the frame-rate constraint, which
             // is the whole reason the mode exists: 45.5 -> 60.6 fps at
             // SPI_HALF=1. Set INIT_FILE to match, or the panel unpacks the
             // stream with the wrong stride and the picture shears.
             parameter RGBSIZE = 16,
             parameter INIT_FILE = "setup_st7789_565.hex",
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
  localparam DIVW = (SPI_HALF < 2) ? 1 : $clog2(SPI_HALF);

  // The pixel group: the smallest run of whole bytes that carries a whole
  // number of pixels. RGB565 packs one pixel into two bytes; RGB444 packs two
  // into three, so the byte-to-pixel phase stops being a single bit and becomes
  // a modulo-3 counter. WIDTH must be a multiple of GRP_PIX - 320 is.
  localparam GRP_BYTES = (RGBSIZE == 12) ? 3 : 2;
  localparam GRP_PIX   = (RGBSIZE == 12) ? 2 : 1;
  localparam LINEBYTES = (WIDTH / GRP_PIX) * GRP_BYTES;

  // `clk` cycles the shifter takes per LCD pixel: RGBSIZE bits, two SCL phases
  // each, SPI_HALF cycles a phase. Blanking reuses this so a blanked position
  // is held for exactly as long as a streamed one.
  //
  // PIXCLK MUST STAY AN INTEGER MULTIPLE of the pllclk:masterclk ratio - see
  // the sequencer's phase argument below, and the header of rtl/pll_gowin.v.
  localparam PIXCLK = 2 * RGBSIZE * SPI_HALF;

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
  // Byte position within the pixel group, tracking bcnt_next rather than bcnt:
  // `dataout` is a one-deep pipeline, so every decision here is about the byte
  // the shifter will send NEXT. Reset per line alongside bcnt, so a miscount
  // cannot accumulate across lines.
  logic [1:0] ph;
  wire  [1:0] ph_next = (ph == GRP_BYTES[1:0] - 2'd1) ? 2'd0 : ph + 2'd1;
  // Whether the byte at this phase is built from a FRESH sample of `rgb`. The
  // first GRP_PIX phases of a group each latch one pixel; the rest are served
  // from those latches, because both halves of a pixel must come from ONE
  // sample - see the note in send_frame.
  wire        ph_samples = ph < GRP_PIX[1:0];
  logic [RGBSIZE-1:0] pixreg;            // first pixel of the group
  logic [RGBSIZE-1:0] pixreg_b;          // second pixel; RGB444 only, trimmed at 565
  logic  [8:0] rom [0:INIT_SIZE];
  wire   [8:0] command = rom[counter];

  initial $readmemh(INIT_FILE, rom);

  // ---- sequencer ----------------------------------------------------------
  // Advances one byte per `byte_done`. hpos/vpos are consumed by the PPU in the
  // masterclk domain across NO SYNCHRONISER, and what makes that safe is a
  // phase argument, not a timing margin: PIXCLK is an integer multiple of the
  // pllclk:masterclk ratio (8:1, rtl/pll_gowin.v DYN_SDIV_SEL), so every pixel
  // boundary lands exactly on a masterclk edge and a naive update would change
  // hpos/vpos on the very edge that samples them. Updating on `byte_done` - one
  // cycle after the last SCL falling edge - offsets it by one pllclk and leaves
  // 7 of the 8 cycles as setup.
  //
  // THAT ARGUMENT IS THE CONSTRAINT ON PIXCLK, and it is why the divider and
  // the colour depth are chosen together. Break the integer ratio and the
  // update walks in phase until it lands on the sampling edge, which is a
  // multi-bit bus tearing rather than a signal arriving late - a fault that
  // looks like geometry, not like timing.
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
      ph        <= 2'd0;
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
              ph      <= 2'd0;
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
              // This cycle IS the group's phase 0: the shifter is idle, so
              // the `load` that restarts it has to carry a real byte, and that
              // byte is the one phase 0 would have produced. So it latches the
              // pixel, emits the first byte, advances hpos past it and hands
              // send_frame a group already one phase in.
              state   <= send_frame;      // next line
              bcnt    <= '0;
              ph      <= 2'd1;
              pixreg  <= rgb;             // hpos=0, vpos already advanced
              dataout <= rgb[RGBSIZE-1 -: 8];
              hpos    <= 1;
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
            ph      <= 2'd0;
            hpos    <= 0;
            vpos    <= 0;
            rs      <= 0;
            dataout <= 8'h2C;
            state   <= send_frame;
          end

          send_frame: begin
            rs      <= 1;
            ph      <= ph_next;
            // EVERY BYTE OF A PIXEL MUST COME FROM ONE SAMPLE OF `rgb`. hpos
            // advances on the same cycle that queues a byte, so reading rgb
            // once per byte straddles two pixels. On hardware that produced
            // colours no inversion or channel swap can explain, white text
            // coming out green being the giveaway (white is symmetric under
            // both). Latch the pixel on the phase that first needs it and serve
            // the remaining bytes from the latch.
            //
            // RGB565, two bytes a pixel:   [RRRRRGGG][GGGBBBBB]
            // RGB444, three bytes per two: [R1G1][B1R2][G2B2]
            //
            // Phase 1 of RGB444 is the only byte that spans two pixels, and it
            // takes the first from the latch and the second from a fresh sample
            // - which is exactly the straddle the rule above forbids, done
            // deliberately and once, because the format is defined that way.
            if (ph == 2'd0) begin
              pixreg  <= rgb;
              dataout <= rgb[RGBSIZE-1 -: 8];
            end else if (RGBSIZE == 12 && ph == 2'd1) begin
              pixreg_b <= rgb;
              dataout  <= {pixreg[3:0], rgb[RGBSIZE-1 -: 4]};
            end else if (RGBSIZE == 12) begin
              dataout <= pixreg_b[7:0];
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
            // code streamed the whole frame straight through and let the panel's
            // own address auto-increment find the row boundaries, so the phase
            // never mattered; adding a per-line boundary made it matter and
            // sheared every row against the one above.
            //
            // The fix then was to DERIVE hpos from the byte counter (bcnt>>1),
            // which only works while a pixel is a whole number of bytes. RGB444
            // makes it 1.5, so the position is stepped off `ph` instead - once
            // per pixel the group carries. That is accumulation again, and it is
            // exact for the reason the old version was not: `ph` is reset with
            // `bcnt` at every line start, so nothing survives a line to drift,
            // and LINEBYTES is a whole number of groups. The two-frame per-pixel
            // assertion in rtl/lcd_tb.sv is what actually holds this down.
            //
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
              ph     <= 2'd0;
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
              if (ph_samples) hpos <= hpos + 1'b1;
            end
          end

          h_blank: ;                       // handled outside the byte_done gate
          v_blank: ;
        endcase
      end
    end
  end
endmodule
