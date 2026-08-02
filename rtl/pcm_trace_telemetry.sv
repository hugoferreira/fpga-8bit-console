// Capture the first exact committed PCM words and expose them three at a time.
//
// The 64-bit page format is:
//   [63:56]  A5 marker
//   [55:48]  page number
//   [47:32]  first signed PCM word
//   [31:16]  second signed PCM word
//   [15:0]   third signed PCM word
module pcm_trace_telemetry #(
    parameter integer WORD_COUNT = 33,
    parameter integer START_WORD = 1,
    parameter integer PAGE_BASE = (START_WORD - 1) / 3,
    parameter integer PAGE_CYCLES = 9_375_000
  ) (
    input  logic               clk,
    input  logic               reset,
    input  logic               enable,
    input  logic               commit,
    input  logic signed [15:0] pcm,
    output logic [63:0]        debug
  );

  localparam integer PAGE_COUNT = (WORD_COUNT + 2) / 3;
  localparam integer WORD_CW = WORD_COUNT <= 1 ? 1 : $clog2(WORD_COUNT + 1);
  localparam integer PAGE_CW = PAGE_COUNT <= 1 ? 1 : $clog2(PAGE_COUNT);
  localparam integer DIV_CW = PAGE_CYCLES <= 1 ? 1 : $clog2(PAGE_CYCLES);

  logic signed [15:0] trace_words [0:WORD_COUNT-1];
  logic [WORD_CW-1:0] captured;
  logic [15:0]          seen;
  logic                 started;
  logic [PAGE_CW-1:0]  page;
  logic [DIV_CW-1:0]   page_div;

  always_ff @(posedge clk) begin
    if (reset || !enable) begin
      captured <= '0;
      seen      <= '0;
      started  <= 1'b0;
      page     <= '0;
      page_div <= '0;
    end else begin
      if (commit) begin
        if (!started && pcm != 16'sd0) begin
          seen    <= 16'd1;
          started <= 1'b1;
          if (START_WORD <= 1 && captured < WORD_CW'(WORD_COUNT)) begin
            trace_words[captured] <= pcm;
            captured <= captured + 1'b1;
          end
        end else if (started) begin
          seen <= seen + 1'b1;
          if (seen + 1'b1 >= START_WORD &&
              captured < WORD_CW'(WORD_COUNT)) begin
            trace_words[captured] <= pcm;
            captured <= captured + 1'b1;
          end
        end
      end

      if (PAGE_CYCLES <= 1 || page_div == DIV_CW'(PAGE_CYCLES - 1)) begin
        page_div <= '0;
        if (page == PAGE_CW'(PAGE_COUNT - 1))
          page <= '0;
        else
          page <= page + 1'b1;
      end else begin
        page_div <= page_div + 1'b1;
      end
    end
  end

  logic signed [15:0] word0, word1, word2;
  integer base;
  always_comb begin
    base = page * 3;
    word0 = 16'sd0;
    word1 = 16'sd0;
    word2 = 16'sd0;
    if (base < captured)
      word0 = trace_words[base];
    if (base + 1 < captured)
      word1 = trace_words[base + 1];
    if (base + 2 < captured)
      word2 = trace_words[base + 2];
    debug = {8'ha5, 8'(PAGE_BASE + page), word0, word1, word2};
  end
endmodule
