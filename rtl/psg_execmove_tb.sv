`timescale 1ns/1ps
`include "psg_execmove.sv"

module psg_execmove_tb;
  bit clk;
  logic active, hold, owner;
  logic [2:0] op;
  logic [6:0] action;
  logic [5:0] state_word;
  logic [15:0] acc;
  logic spar_bank, join_stage, trig_req, walk_tick, playing, ins_use;
  logic released, cpz;
  logic state_ra_override, state_we_extra, state_wd_override;
  logic [5:0] state_ra_word, state_wa_word;
  logic [15:0] state_q_mem, state_q_direct, state_wd_fixed;
  logic direct_q;
  wire [15:0] state_q = direct_q ? state_q_direct : state_q_mem;
  logic [3:0] cond_adv;
  logic voice_stop, cpz_we, cpz_next;
  logic [15:0] mem[0:63];

  localparam logic [2:0] OP_READ = 3'd0, OP_WRITE = 3'd1, OP_EXEC = 3'd7;

  wire [5:0] ra = state_ra_override ? state_ra_word : state_word;
  wire we = active && !hold && (op == OP_WRITE || state_we_extra);
  wire [5:0] wa = state_we_extra ? state_wa_word : state_word;
  wire [15:0] wd = state_wd_override ? state_wd_fixed : 16'hdead;

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  psg_execmove dut(.*);

  always_ff @(posedge clk) begin
    if (we)
      mem[wa] <= wd;
    state_q_mem <= mem[ra];
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

  task automatic check_fixed(input logic [2:0] next_op,
                             input logic [6:0] next_action,
                             input logic [15:0] next_q,
                             input logic [15:0] next_acc,
                             input logic [5:0] expected_wa,
                             input logic [15:0] expected_wd);
    @(negedge clk);
    op = next_op;
    action = next_action;
    state_word = 0;
    direct_q = 1'b1;
    state_q_direct = next_q;
    acc = next_acc;
    #1;
    if (!state_wd_override || wd !== expected_wd
        || (next_op == OP_READ && (!state_we_extra
                                   || state_wa_word != expected_wa)))
      $fatal(1, "action %h fixed write got=%b/%0d/%h expected=%0d/%h",
             next_action, state_wd_override, state_wa_word, wd,
             expected_wa, expected_wd);
    direct_q = 1'b0;
  endtask

  task automatic check_copy_bank(input logic next_bank,
                                 input logic zero_last);
    logic [5:0] src_base, dst_base;
    begin
      spar_bank = next_bank;
      join_stage = 1'b0;
      cpz = zero_last;
      src_base = next_bank ? 6'd28 : 6'd24;
      dst_base = next_bank ? 6'd24 : 6'd28;
      for (int i = 0; i < 4; i++) begin
        mem[src_base + i] = 16'ha100 + 16'(i);
        mem[dst_base + i] = 16'h5e00 + 16'(i);
      end
      step(OP_EXEC, 7'h5e, 0);
      for (int i = 0; i < 4; i++)
        step(OP_READ, 7'(7'h57 + i), 6'(24 + i));
      for (int i = 0; i < 4; i++) begin
        if (mem[dst_base + i] !== (zero_last && i == 3
                                  ? 16'ha100 : 16'ha100 + 16'(i)))
          $fatal(1, "copy bank %0d word %0d got=%h", next_bank, i,
                 mem[dst_base + i]);
      end
    end
  endtask

  initial begin
    active = 1'b1;
    hold = 1'b0;
    owner = 1'b1;
    op = OP_EXEC;
    action = 0;
    state_word = 0;
    acc = 0;
    spar_bank = 1'b0;
    join_stage = 1'b0;
    trig_req = 1'b0;
    walk_tick = 1'b0;
    playing = 1'b0;
    ins_use = 1'b0;
    released = 1'b0;
    cpz = 1'b0;
    direct_q = 1'b0;
    state_q_direct = 16'd0;
    for (int i = 0; i < 64; i++)
      mem[i] = 16'h8000 + 16'(i);
    for (int i = 0; i < 7; i++)
      source[i] = mem[load_words[i]];

    // V_LD0..7 normalize constants 1/32 while streaming the seven raw words.
    for (int i = 0; i < 8; i++)
      step(OP_READ, 7'(i), 6'(load_words[i]));
    step(OP_EXEC, 7'h40, 6'd0);
    if (mem[34] !== 16'd1 || mem[35] !== 16'd32)
      $fatal(1, "normalization constants got=%h/%h expected=1/32",
             mem[34], mem[35]);
    for (int i = 0; i < 7; i++)
      if (mem[scratch_words[i]] !== source[i])
        $fatal(1, "load %0d: scratch %0d got=%h expected=%h",
               i, scratch_words[i], mem[scratch_words[i]], source[i]);

    // The same generated placeholders select par1+2 when bank one is active.
    spar_bank = 1'b1;
    mem[30] = 16'h3ace;
    for (int i = 0; i < 8; i++)
      step(OP_READ, 7'(i), 6'(load_words[i]));
    step(OP_EXEC, 7'h40, 6'd0);
    if (mem[53] !== 16'h3ace)
      $fatal(1, "bank-one parameter load got=%h", mem[53]);

    // Pretend macro arithmetic updated the address-selected working words.
    // Both real predecessors of V_ST0 must prime scratch 48: P_W3 on the
    // evaluated path, and PC3 on the skipped-slot publication-copy path.
    check_store(OP_WRITE, 7'h56);
    check_store(OP_READ, 7'h5a);

    // Fixed projection and merge shapes, including the definitive word-9
    // instrument previous-pitch/volume layout.
    check_fixed(OP_READ, 7'h47, 16'hc35a, 0, 6'd36, 16'h005a);
    check_fixed(OP_READ, 7'h48, 16'hc35a, 0, 6'd37, 16'h00c3);
    check_fixed(OP_READ, 7'h4a, 16'h2a55, 0, 6'd39, 16'h002a);
    check_fixed(OP_READ, 7'h1c, 16'h0007, 0, 6'd43, 16'd7);
    check_fixed(OP_READ, 7'h1c, 16'h0020, 0, 6'd43, 16'd32);
    check_fixed(OP_READ, 7'h1c, 16'h0107, 0, 6'd43, 16'd32);
    check_fixed(OP_WRITE, 7'h4e, 16'hd2ab, 0, 0,
                (16'hd2ab & 16'hf03f) | ((16'hd2ab & 16'h003f) << 6));
    check_fixed(OP_WRITE, 7'h4f, 16'ha51d, 0, 0,
                (16'ha51d & 16'hfe3f) | ((16'ha51d & 7) << 6));
    check_fixed(OP_WRITE, 7'h29, 16'hc0a5, 16'h002b, 0, 16'heba5);
    check_fixed(OP_WRITE, 7'h2e, 16'hd2ab, 16'h2d00, 0, 16'hd2ad);
    check_fixed(OP_WRITE, 7'h2f, 16'hd2ab, 16'ha000, 0, 16'hdaab);
    check_fixed(OP_WRITE, 7'h3e, 16'ha61b, 16'h0012, 0,
                {6'h29, 5'h12, 5'h1b});

    // Copy publication reads the selected source bank and always writes the
    // inactive bank; PC3 alone applies the existing cpz amplitude mask.
    check_copy_bank(1'b0, 1'b1);
    check_copy_bank(1'b1, 1'b0);
    @(negedge clk);
    spar_bank = 1'b0;
    op = OP_WRITE;
    action = 7'h53;
    #1;
    if (!state_we_extra || state_wa_word != 6'd28)
      $fatal(1, "P_W0 bank-zero destination mismatch");
    spar_bank = 1'b1;
    #1;
    if (!state_we_extra || state_wa_word != 6'd24)
      $fatal(1, "P_W0 bank-one destination mismatch");

    // The four external branch facts occupy conditions 8..11 exactly.
    trig_req = 1'b1;
    walk_tick = 1'b1;
    playing = 1'b1;
    ins_use = 1'b0;
    released = 1'b1;
    #1;
    if (cond_adv !== 4'b1011)
      $fatal(1, "advance condition map mismatch %b", cond_adv);
    action = 7'h2a;
    #1;
    if (!voice_stop || !cpz_we || !cpz_next)
      $fatal(1, "voice-stop effects mismatch");
    action = 7'h2b;
    playing = 1'b0;
    #1;
    if (voice_stop || !cpz_we || !cpz_next)
      $fatal(1, "skip cpz effect mismatch");

    // Owner and hold both suppress side effects.
    owner = 1'b0;
    step(OP_READ, 7'd1, 6'd3);
    if (state_we_extra || state_wd_override)
      $fatal(1, "sample owner activated tick movement");
    owner = 1'b1;
    hold = 1'b1;
    step(OP_READ, 7'd1, 6'd3);
    if (state_we_extra || state_wd_override)
      $fatal(1, "held tick movement remained active");

    $display("psg_execmove_tb: PASS (dynamic loads/stores, actions, banks, effects)");
    $finish;
  end
endmodule
