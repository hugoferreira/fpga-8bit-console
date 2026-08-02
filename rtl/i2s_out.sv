/**
 * I2S transmitter, for a board with a real audio amplifier on it.
 *
 * rtl/dsigma.sv is the output stage for a board that has nothing: it turns the
 * PSG's signed 16-bit PCM into a 1-bit density stream that an RC network and
 * an amplifier off-board reconstruct. The Tang Nano 20K does not need that -
 * it carries a MAX98357A, a mono class-D amplifier with an I2S input, wired to
 * the speaker pads. This feeds it directly, so the board makes sound with a
 * speaker and no other parts.
 *
 * Standard (Philips) I2S, 16 bits per channel slot, MSB first, LRCK and data
 * changing on the falling edge of BCLK and sampled by the receiver on the
 * rising edge. LRCK changes while the preceding channel's LSB is present, one
 * BCLK before the following channel's MSB. This is the 32-BCLK frame shape
 * used by Sipeed's working Tang Nano 20K audio example.
 *
 * The same sample goes to both slots. The MAX98357A's channel select is a
 * board-level resistor (left, right, or (L+R)/2) and the Tang Nano 20K does
 * not break it out, so a mono source has to be duplicated to be heard whatever
 * that resistor says.
 *
 *   BCLK = clk / (2 * HALF)
 *   LRCK = BCLK / 32
 *
 * The PSG's virtual sample rate is 22050 Hz, so each PSG sample is sent about
 * twice - a zero-order hold, which is what the modulator in dsigma.sv does to
 * the same signal at a far higher rate. The owner chooses HALF so LRCK remains
 * inside the MAX98357A's 8-96 kHz window.
 */
module i2s_out #(
    parameter int HALF = 40,             // clk cycles per BCLK half-period
    parameter int ATTEN_SHIFT = 0,       // arithmetic right shift (6 dB/bit)
    parameter bit BOOST_50_PERCENT = 0   // multiply the attenuated word by 3/2
  ) (
    input  logic               clk,      // serializer clock
    input  logic               reset,
    input  logic signed [15:0] pcm,      // PSG output, updated at 22050 Hz
    output logic               bclk,
    output logic               lrck,
    output logic               din
  );

  localparam int DIVW = $clog2(HALF);

  logic [DIVW-1:0]    div;
  logic [4:0]         bitcnt;            // 0..31: two 16-bit slots
  logic signed [15:0] hold;              // one frame's sample, repeated
  wire  signed [15:0] atten_pcm = pcm >>> ATTEN_SHIFT;
  wire  signed [16:0] atten_ext = {atten_pcm[15], atten_pcm};
  wire  signed [16:0] boosted_pcm =
    (atten_ext + (atten_ext <<< 1)) >>> 1;
  wire  signed [15:0] scaled_pcm = BOOST_50_PERCENT
                                      ? boosted_pcm[15:0] : atten_pcm;

  // No declaration initialisers and no `initial`: every one of these is written
  // in the reset branch below, and the owner holds reset through clock lock,
  // so there is no window in which an
  // uninitialised value reaches a pin.
  always_ff @(posedge clk) begin
    if (reset) begin
      div    <= '0;
      bitcnt <= '0;
      bclk   <= 1'b0;
      lrck   <= 1'b0;
      din    <= 1'b0;
      hold   <= '0;
    end else if (div != DIVW'(HALF - 1)) begin
      div <= div + 1'b1;
    end else begin
      div  <= '0;
      bclk <= ~bclk;

      // Falling edge of BCLK: advance the frame and present the bit the
      // receiver will sample on the next rising edge.
      if (bclk) begin
        bitcnt <= bitcnt + 1'b1;
        din <= hold[4'd15 - bitcnt[3:0]];

        // LRCK moves with the old channel's LSB. The next BCLK therefore
        // carries the new channel's MSB, exactly one clock after the edge.
        if (bitcnt == 5'd15)
          lrck <= 1'b1;
        else if (bitcnt == 5'd31) begin
          lrck <= 1'b0;
          hold <= scaled_pcm;
        end
      end
    end
  end

endmodule
