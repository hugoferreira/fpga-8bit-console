/**
 * Colour-depth reduction at the output stage.
 *
 * The console's pipeline is RGB565 and stays that way: the palette, the PPU and
 * the compositor are all 16-bit, and a future parallel or TMDS output wants that
 * depth intact. This module exists so a NARROWER sink can be fed without
 * narrowing anything upstream of it - today that sink is the SPI panel in 12-bit
 * mode, where RGB444 costs 25% of the bytes per frame and therefore buys 33%
 * more frames per second on a link that is the binding constraint.
 *
 *   RGB565 -> RGB444   1.5 bytes/pixel instead of 2
 *   60 fps at 320x240  needs 55.3 Mbit/s instead of 73.7
 *
 * Purely combinational and parameterised per channel, so the same instance
 * serves RGB565->RGB444 for the panel and RGB565->RGB888 promotion for a
 * display that wants wider - IN and OUT widths are independent and either
 * direction works.
 *
 * NARROWING IS TOP-BITS TRUNCATION, AND THAT IS NOT LAZINESS - IT IS MEASURED.
 * This module first rounded to nearest, on the reasoning that dropping low bits
 * biases a channel downward and darkens the image. rtl/rgb_quant_tb.sv refuted
 * it: summed squared error against the ideal v*15/63 came out 21.9 for rounding
 * against 7.6 for truncation, three times worse.
 *
 * The reason is that the two scales are not the same. Truncating d bits divides
 * by 2^d, but the correct map for n bits to m is (2^m - 1)/(2^n - 1) - for 6 to
 * 4 that is 15/63 = 0.238, not 1/4 = 0.25. The shift already overshoots the
 * ideal, so adding half an LSB overshoots further. And truncation needs no
 * defending on endpoints either: 63 -> 15 and 0 -> 0, both exact, so there is no
 * darkening to correct. It costs zero logic - a bit select.
 *
 * (The concern was real, just misplaced. It applies going the other way: 4'hF
 * widened by shifting is 8'hF0, which is NOT full scale. Hence replication.)
 *
 * SCALING, NOT SHIFTING, ON THE WAY BACK UP. A 4-bit channel promoted to 8 bits
 * must become v*17 (0xF -> 0xFF), not v<<4 (0xF -> 0xF0), or full scale stops
 * being full scale. Bit replication does exactly that for integer ratios and is
 * what this uses.
 */
module chan_requant #(parameter int IN_W = 6, parameter int OUT_W = 4)
                    (input logic [IN_W-1:0] din, output logic [OUT_W-1:0] dout);
  // Widths must be elaboration-time constants for the selects below, which is
  // why this is a submodule rather than a function taking widths as arguments.
  localparam int REP = (OUT_W + IN_W - 1) / IN_W;

  generate
    if (OUT_W == IN_W) begin : g_same
      assign dout = din;
    end else if (OUT_W < IN_W) begin : g_narrow
      // Top bits. Both endpoints are exact and it is closer to the ideal linear
      // map than rounding is - see the header. No adder, no clamp, no logic.
      assign dout = din[IN_W-1 -: OUT_W];
    end else begin : g_widen
      // Replicate so full scale stays full scale: 4'hF -> 8'hFF.
      wire [REP*IN_W-1:0] rep = {REP{din}};
      assign dout = rep[REP*IN_W-1 -: OUT_W];
    end
  endgenerate
endmodule

module rgb_quant #(parameter int IN_R  = 5, parameter int IN_G  = 6,
                   parameter int IN_B  = 5,
                   parameter int OUT_R = 4, parameter int OUT_G = 4,
                   parameter int OUT_B = 4)
                 (input  logic [IN_R + IN_G + IN_B - 1:0]    din,
                  output logic [OUT_R + OUT_G + OUT_B - 1:0] dout);

  wire [IN_R-1:0] r_in = din[IN_R + IN_G + IN_B - 1 -: IN_R];
  wire [IN_G-1:0] g_in = din[IN_G + IN_B - 1 -: IN_G];
  wire [IN_B-1:0] b_in = din[IN_B - 1 -: IN_B];

  wire [OUT_R-1:0] r_out;
  wire [OUT_G-1:0] g_out;
  wire [OUT_B-1:0] b_out;

  chan_requant #(.IN_W(IN_R), .OUT_W(OUT_R)) qr(.din(r_in), .dout(r_out));
  chan_requant #(.IN_W(IN_G), .OUT_W(OUT_G)) qg(.din(g_in), .dout(g_out));
  chan_requant #(.IN_W(IN_B), .OUT_W(OUT_B)) qb(.din(b_in), .dout(b_out));

  assign dout = {r_out, g_out, b_out};

endmodule
