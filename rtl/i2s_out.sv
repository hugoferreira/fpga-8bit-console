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
 * Standard (Philips) I2S, 32 bits per channel slot, MSB first, LRCK and data
 * changing on the falling edge of BCLK and sampled by the receiver on the
 * rising edge. The one-BCLK delay between the LRCK edge and the MSB - the
 * detail that distinguishes I2S from left-justified - is the explicit pad bit
 * driven at the slot boundary below.
 *
 * The same sample goes to both slots. The MAX98357A's channel select is a
 * board-level resistor (left, right, or (L+R)/2) and the Tang Nano 20K does
 * not break it out, so a mono source has to be duplicated to be heard whatever
 * that resistor says.
 *
 *   BCLK = clk / (2 * HALF) = 112.5 MHz / 40 = 2.8125 MHz
 *   LRCK = BCLK / 64        = 43.945 kHz
 *
 * The PSG's virtual sample rate is 22050 Hz, so each PSG sample is sent about
 * twice - a zero-order hold, which is what the modulator in dsigma.sv does to
 * the same signal at a far higher rate. 43.945 kHz is inside the MAX98357A's
 * 8-96 kHz window with room on both sides, and it is what an integer division
 * of 112.5 MHz gives: there is no exact 44.1 or 48 kHz from this clock, and
 * there does not need to be, because nothing downstream is clocked by it.
 */
module i2s_out #(
    parameter int HALF = 20              // clk cycles per BCLK half-period
  ) (
    input  logic               clk,      // 112.5 MHz (psgclk)
    input  logic               reset,
    input  logic signed [15:0] pcm,      // PSG output, updated at 22050 Hz
    output logic               bclk,
    output logic               lrck,
    output logic               din
  );

  localparam int DIVW = $clog2(HALF);

  logic [DIVW-1:0]    div;
  logic [5:0]         bitcnt;            // 0..63: two 32-bit slots
  logic [31:0]        sr;
  logic signed [15:0] hold;              // the left slot's sample, repeated

  // No declaration initialisers and no `initial`: every one of these is written
  // in the reset branch below, and the console holds reset for 65536 master
  // clocks at power-on (rtl/clocks.sv), so there is no window in which an
  // uninitialised value reaches a pin.
  always_ff @(posedge clk) begin
    if (reset) begin
      div    <= '0;
      bitcnt <= '0;
      bclk   <= 1'b0;
      lrck   <= 1'b0;
      din    <= 1'b0;
      sr     <= '0;
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
        case (bitcnt)
          // Slot boundaries. LRCK moves and the pad bit goes out here; the
          // MSB follows one BCLK later, off the freshly loaded register.
          6'd63: begin lrck <= 1'b0; hold <= pcm; sr <= {pcm,  16'b0}; din <= 1'b0; end
          6'd31: begin lrck <= 1'b1;              sr <= {hold, 16'b0}; din <= 1'b0; end
          default: begin sr <= {sr[30:0], 1'b0}; din <= sr[31]; end
        endcase
      end
    end
  end

endmodule
