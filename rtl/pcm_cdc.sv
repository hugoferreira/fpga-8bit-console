// Transfer the slowly changing PSG PCM word into a faster serializer domain.
//
// src_hold is written before src_toggle changes and remains stable for an
// entire 22.05 kHz sample period. The two-flop toggle synchronizer therefore
// gives the payload thousands of destination clocks to settle before dst_pcm
// captures it. No acknowledgement is needed at this fixed 18.75/112.5 MHz
// clock ratio: a new source sample cannot arrive during the synchronizer
// latency.
module pcm_cdc (
    input  logic               src_clk,
    input  logic               dst_clk,
    input  logic               reset,
    input  logic signed [15:0] src_pcm,
    output logic signed [15:0] dst_pcm
  );

  logic signed [15:0] src_hold;
  logic               src_toggle;
  (* async_reg = "true" *) logic toggle_meta;
  (* async_reg = "true" *) logic toggle_sync;
  logic               toggle_seen;

  always_ff @(posedge src_clk) begin
    if (reset) begin
      src_hold   <= '0;
      src_toggle <= 1'b0;
    end else if (src_pcm != src_hold) begin
      src_hold   <= src_pcm;
      src_toggle <= ~src_toggle;
    end
  end

  always_ff @(posedge dst_clk) begin
    if (reset) begin
      toggle_meta <= 1'b0;
      toggle_sync <= 1'b0;
      toggle_seen <= 1'b0;
      dst_pcm     <= '0;
    end else begin
      toggle_meta <= src_toggle;
      toggle_sync <= toggle_meta;
      if (toggle_sync != toggle_seen) begin
        dst_pcm     <= src_hold;
        toggle_seen <= toggle_sync;
      end
    end
  end
endmodule
