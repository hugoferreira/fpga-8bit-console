/**
 * PT8211 transmitter, for a board whose audio DAC is not an I2S receiver.
 *
 * The third output stage in this design, and it exists because the Tang Primer
 * 20K Dock's 3.5mm headphone jack is fed by a PT8211 (a 16-bit stereo DAC)
 * into an LPA4809 headphone amplifier - not by an I2S amplifier like the Tang
 * Nano 20K's MAX98357A. The three stages, by what the board carries:
 *
 *   rtl/dsigma.sv      nothing at all. 1-bit density stream, RC + amp off-board.
 *   rtl/i2s_out.sv     an I2S amplifier (MAX98357A). Standard Philips framing.
 *   rtl/pt8211_out.sv  a PT8211 DAC. LSB-justified framing, see below.
 *
 * PT8211 IS NOT PHILIPS I2S, and feeding it i2s_out.sv would not merely sound
 * wrong at the edges - it would be a whole bit out. Two differences, both
 * mandatory:
 *
 *   1. NO ONE-BCK DELAY. Philips I2S moves LRCK one BCK *before* the MSB of the
 *      slot it selects. PT8211 changes WS *coincident* with the MSB. With a
 *      16-bit word in a 16-BCK half-frame there is no padding to absorb the
 *      difference, so a Philips stream arrives across a slot boundary. Measured
 *      in rtl/pt8211_out_tb.sv by driving i2s_out.sv into a PT8211 decoder:
 *      16'sh1234 comes out as 16'shdcbb. Not quiet, not slightly wrong - noise.
 *
 *   2. THE OTHER CLOCK EDGE. i2s_out.sv changes data on the falling edge of
 *      BCLK because a Philips receiver samples on the rising one. PT8211 latches
 *      on the FALLING edge of BCK, so this changes data on the rising edge.
 *      Either way the receiver sees a bit that settled half a BCK period ago.
 *
 * Both are read off Sipeed's own PT8211 driver for this board
 * (TangPrimer-20K-example/PT8211/src/pt8211_drive.v), which loads a fresh word
 * so that its MSB is presented on exactly the clock where WS moves.
 *
 *   BCK = clk / (2 * HALF)
 *   WS  = BCK / 32                 (32 BCK per frame, 16 per channel)
 *
 * WS low is the left channel. The same sample goes to both slots: the PSG is
 * mono, and a stereo DAC driven on one channel only would halve the level and
 * put it in one ear.
 *
 * At the owner's default HALF = 40 on a 112.5 MHz psgclk this is BCK = 1.40625
 * MHz and WS = 43.945 kHz, close to the 1.536 MHz / 48 kHz Sipeed's own example
 * runs the part at. The PSG's virtual sample rate is 22050 Hz, so each sample
 * is sent about twice - a zero-order hold, as in i2s_out.sv.
 */
module pt8211_out #(
    parameter int HALF = 40,             // clk cycles per BCK half-period
    parameter int ATTEN_SHIFT = 0        // arithmetic right shift (6 dB/bit)
  ) (
    input  logic               clk,      // serializer clock
    input  logic               reset,
    input  logic signed [15:0] pcm,      // PSG output, updated at 22050 Hz
    output logic               bck,
    output logic               ws,
    output logic               din
  );

  localparam int DIVW = $clog2(HALF);

  logic [DIVW-1:0]    div;
  logic [4:0]         bitcnt;            // 0..31: two 16-bit slots
  logic signed [15:0] hold;              // one frame's sample, repeated
  wire  signed [15:0] scaled_pcm = pcm >>> ATTEN_SHIFT;

  // The slot being ENTERED, not the one being left. This is the whole of
  // difference 1 above: i2s_out.sv indexes the bit off the outgoing count,
  // which is what puts a Philips stream one BCK behind its LRCK edge.
  wire [4:0] next = bitcnt + 1'b1;

  // No declaration initialisers and no `initial`: every one of these is written
  // in the reset branch below, and the owner holds reset through clock lock, so
  // there is no window in which an uninitialised value reaches a pin.
  always_ff @(posedge clk) begin
    if (reset) begin
      div    <= '0;
      bitcnt <= '0;
      bck    <= 1'b0;
      ws     <= 1'b0;
      din    <= 1'b0;
      hold   <= '0;
    end else if (div != DIVW'(HALF - 1)) begin
      div <= div + 1'b1;
    end else begin
      div <= '0;
      bck <= ~bck;

      // Rising edge of BCK: present the bit and the channel select together.
      // PT8211 latches both on the falling edge, half a period from here.
      if (!bck) begin
        bitcnt <= next;
        din    <= hold[4'd15 - next[3:0]];
        ws     <= next[4];              // slots 0-15 left, 16-31 right

        // One slot early, so `hold` is already the new sample on the clock that
        // presents its MSB. The read above still sees the outgoing word, which
        // is what slot 31 - the right channel's LSB - is owed.
        if (next == 5'd31) hold <= scaled_pcm;
      end
    end
  end

endmodule
