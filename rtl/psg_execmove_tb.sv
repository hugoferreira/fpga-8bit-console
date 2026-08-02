`timescale 1ns/1ps
`include "psg_execmove.sv"

module psg_execmove_tb;
  bit clk;
  logic active, hold, owner;
  logic [2:0] op;
  logic [6:0] action;
  logic [5:0] state_word;
  logic state_ra_override, state_we_extra, copy_state_q;
  logic [5:0] state_ra_word, state_wa_word;
  logic [15:0] state_q;
  logic [15:0] mem[0:63];

  localparam logic [2:0] OP_READ = 3'd0, OP_WRITE = 3'd1, OP_EXEC = 3'd7;

  wire [5:0] ra = state_ra_override ? state_ra_word : state_word;
  wire we = active && !hold && (op == OP_WRITE || state_we_extra);
  wire [5:0] wa = state_we_extra ? state_wa_word : state_word;
  wire [15:0] wd = copy_state_q ? state_q : 16'hdead;

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  psg_execmove dut(.*);

  always_ff @(posedge clk) begin
    if (we)
      mem[wa] <= wd;
    state_q <= mem[ra];
  end

  task automatic step(input logic [2:0] next_op,
                      input logic [6:0] next_action,
                      input logic [5:0] next_word);
    op = next_op;
    action = next_action;
    state_word = next_word;
    @(posedge clk);
    #1;
  endtask

  logic [15:0] source[0:6];
  int load_words[0:7] = '{3, 4, 5, 8, 9, 26, 32, 26};
  int scratch_words[0:6] = '{48, 49, 50, 51, 52, 53, 54};
  int store_src[0:4] = '{48, 49, 50, 52, 54};
  int store_dst[0:4] = '{3, 4, 5, 9, 32};

  task automatic check_store(input logic [2:0] prime_op,
                             input logic [6:0] prime_action);
    for (int i = 0; i < 5; i++) begin
      mem[store_src[i]] = 16'h4100 + 16'(i);
      mem[store_dst[i]] = 16'h9000 + 16'(i);
    end
    step(prime_op, prime_action, 6'd27);
    for (int i = 0; i < 5; i++)
      step(OP_WRITE, 7'(8 + i), 6'(store_dst[i]));
    for (int i = 0; i < 5; i++)
      if (mem[store_dst[i]] !== 16'h4100 + 16'(i))
        $fatal(1, "store %0d: word %0d got=%h expected=%h",
               i, store_dst[i], mem[store_dst[i]], 16'h4100 + 16'(i));
  endtask

  initial begin
    active = 1'b1;
    hold = 1'b0;
    owner = 1'b1;
    op = OP_EXEC;
    action = 0;
    state_word = 0;
    for (int i = 0; i < 64; i++)
      mem[i] = 16'h8000 + 16'(i);
    for (int i = 0; i < 7; i++)
      source[i] = mem[load_words[i]];

    // V_LD0..7, then K_ADV drains the final synchronous read.
    for (int i = 0; i < 8; i++)
      step(OP_READ, 7'(i), 6'(load_words[i]));
    step(OP_EXEC, 7'h40, 6'd0);
    for (int i = 0; i < 7; i++)
      if (mem[scratch_words[i]] !== source[i])
        $fatal(1, "load %0d: scratch %0d got=%h expected=%h",
               i, scratch_words[i], mem[scratch_words[i]], source[i]);

    // Pretend macro arithmetic updated the address-selected working words.
    // Both real predecessors of V_ST0 must prime scratch 48: P_W3 on the
    // evaluated path, and PC3 on the skipped-slot publication-copy path.
    check_store(OP_WRITE, 7'h56);
    check_store(OP_READ, 7'h5a);

    // Owner and hold both suppress side effects.
    owner = 1'b0;
    step(OP_READ, 7'd1, 6'd3);
    if (state_we_extra || copy_state_q)
      $fatal(1, "sample owner activated tick movement");
    owner = 1'b1;
    hold = 1'b1;
    step(OP_READ, 7'd1, 6'd3);
    if (state_we_extra || copy_state_q)
      $fatal(1, "held tick movement remained active");

    $display("psg_execmove_tb: PASS (8 loads, 2x5 stores)");
    $finish;
  end
endmodule
