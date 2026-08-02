// Fixed-window signature for committed PSG PCM words.
//
// Leading zero words are ignored so a board controller and a focused PSG
// simulation can start music at different sample-grid phases yet sign the same
// audible stream. Once the first non-zero word arrives, every commit counts.
module pcm_signature #(
    parameter integer WORD_COUNT = 4096
  ) (
    input  logic               clk,
    input  logic               reset,
    input  logic               enable,
    input  logic               commit,
    input  logic signed [15:0] pcm,
    output logic [31:0]        signature,
    output logic [12:0]        count,
    output logic               done
  );

  localparam logic [31:0] INITIAL = 32'h811c9dc5;
  logic started;

  function automatic logic [31:0] mix_word(
      input logic [31:0] state,
      input logic signed [15:0] word);
    mix_word = {state[26:0], state[31:27]} ^ {word, word} ^
               32'h9e3779b9;
  endfunction

  always_ff @(posedge clk) begin
    if (reset || !enable) begin
      signature <= INITIAL;
      count     <= '0;
      started   <= 1'b0;
      done      <= 1'b0;
    end else if (commit && !done) begin
      if (!started) begin
        if (pcm != 16'sd0) begin
          signature <= mix_word(INITIAL, pcm);
          count     <= 13'd1;
          started   <= 1'b1;
          if (WORD_COUNT == 1)
            done <= 1'b1;
        end
      end else begin
        signature <= mix_word(signature, pcm);
        count     <= count + 1'b1;
        if (count == WORD_COUNT - 1)
          done <= 1'b1;
      end
    end
  end
endmodule
