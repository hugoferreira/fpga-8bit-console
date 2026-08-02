// Freeze rolling PCM signatures at power-of-two commit counts and expose one
// checkpoint per telemetry page.
//
// The 64-bit page format is:
//   [63:56]  A6 marker
//   [55]     checkpoint valid
//   [54:48]  page number (0..6)
//   [47:32]  committed-word count
//   [31:0]   signature after that word
module pcm_checkpoint_telemetry #(
    parameter integer PAGE_CYCLES = 9_375_000
  ) (
    input  logic               clk,
    input  logic               reset,
    input  logic               enable,
    input  logic               commit,
    input  logic signed [15:0] pcm,
    output logic [63:0]        debug
  );

  localparam integer PAGE_COUNT = 7;
  localparam integer DIV_CW = PAGE_CYCLES <= 1 ? 1 : $clog2(PAGE_CYCLES);
  localparam logic [31:0] INITIAL = 32'h811c9dc5;

  logic [31:0] signature;
  logic [12:0] count;
  logic        started;
  logic [31:0] checkpoint_signature [0:PAGE_COUNT-1];
  logic [PAGE_COUNT-1:0] checkpoint_valid;
  logic [2:0] page;
  logic [DIV_CW-1:0] page_div;

  function automatic logic [31:0] mix_word(
      input logic [31:0] state,
      input logic signed [15:0] word);
    mix_word = {state[26:0], state[31:27]} ^ {word, word} ^
               32'h9e3779b9;
  endfunction

  always_ff @(posedge clk) begin
    if (reset || !enable) begin
      signature        <= INITIAL;
      count            <= '0;
      started          <= 1'b0;
      checkpoint_valid <= '0;
      page             <= '0;
      page_div         <= '0;
    end else begin
      if (commit) begin
        if (!started) begin
          if (pcm != 16'sd0) begin
            signature <= mix_word(INITIAL, pcm);
            count     <= 13'd1;
            started   <= 1'b1;
          end
        end else if (count < 13'd4096) begin
          signature <= mix_word(signature, pcm);
          count     <= count + 1'b1;
          case (count)
            13'd63: begin
              checkpoint_signature[0] <= mix_word(signature, pcm);
              checkpoint_valid[0] <= 1'b1;
            end
            13'd127: begin
              checkpoint_signature[1] <= mix_word(signature, pcm);
              checkpoint_valid[1] <= 1'b1;
            end
            13'd255: begin
              checkpoint_signature[2] <= mix_word(signature, pcm);
              checkpoint_valid[2] <= 1'b1;
            end
            13'd511: begin
              checkpoint_signature[3] <= mix_word(signature, pcm);
              checkpoint_valid[3] <= 1'b1;
            end
            13'd1023: begin
              checkpoint_signature[4] <= mix_word(signature, pcm);
              checkpoint_valid[4] <= 1'b1;
            end
            13'd2047: begin
              checkpoint_signature[5] <= mix_word(signature, pcm);
              checkpoint_valid[5] <= 1'b1;
            end
            13'd4095: begin
              checkpoint_signature[6] <= mix_word(signature, pcm);
              checkpoint_valid[6] <= 1'b1;
            end
            default: begin end
          endcase
        end
      end

      if (PAGE_CYCLES <= 1 || page_div == DIV_CW'(PAGE_CYCLES - 1)) begin
        page_div <= '0;
        if (page == 3'd6)
          page <= '0;
        else
          page <= page + 1'b1;
      end else begin
        page_div <= page_div + 1'b1;
      end
    end
  end

  logic [15:0] checkpoint_count;
  always_comb begin
    case (page)
      3'd0: checkpoint_count = 16'd64;
      3'd1: checkpoint_count = 16'd128;
      3'd2: checkpoint_count = 16'd256;
      3'd3: checkpoint_count = 16'd512;
      3'd4: checkpoint_count = 16'd1024;
      3'd5: checkpoint_count = 16'd2048;
      default: checkpoint_count = 16'd4096;
    endcase
    debug = {8'ha6, checkpoint_valid[page], 4'b0, page,
             checkpoint_count,
             checkpoint_valid[page] ? checkpoint_signature[page] : 32'b0};
  end
endmodule
