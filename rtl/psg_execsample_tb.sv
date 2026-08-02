`timescale 1ns/1ps
`include "psg_execctl.sv"
`include "psg_execmove.sv"

// R.84H-B production-image proof of the owner-zero memory boundary.  The
// synthetic write-data function stands in for later services at the existing
// single state_wd_i port; neither the controller nor movement decoder stores
// an oscillator-record mirror or selects a semantic result.
module psg_execsample_tb;
  bit clk;
  bit reset;
  logic start, start_owner, hold;
  logic [7:0] start_pc;
  logic spar_bank;

  logic active, done, owner, state_re, state_we;
  logic [2:0] slot, op;
  logic [8:0] state_ra, state_wa;
  logic [15:0] state_wd, ir;
  logic [6:0] action;
  logic [5:0] state_word;
  logic [7:0] pc;
  logic [15:0] cond;

  logic [15:0] state_q;
  logic state_ra_override, state_we_extra, state_wd_override;
  logic [5:0] state_ra_word, state_wa_word;
  logic [15:0] state_wd_fixed;
  logic [3:0] cond_adv;
  logic voice_stop, cpz_we, cpz_next;

  logic [15:0] mem[0:511];
  logic [15:0] expected_mem[0:511];
  logic pending_read;
  logic [15:0] pending_data;
  logic [6:0] pending_consumer;
  integer read_count, write_count, active_edge_count;
  integer op_count[0:7];

  integer fold_a[0:6] = '{0, 2, 0, 4, 6, 4, 0};
  integer fold_b[0:6] = '{1, 3, 2, 5, 7, 6, 4};
  integer fold_dst[0:6] = '{0, 2, 0, 4, 6, 4, 0};

  localparam logic [2:0] OP_READ = 3'd0;

  always #5 clk = ~clk;

  function automatic logic [15:0] synthetic_wd(
      input logic [2:0] fn_slot,
      input logic [6:0] fn_action,
      input logic [7:0] fn_pc);
    synthetic_wd = {fn_slot, fn_action, fn_pc[5:0]};
  endfunction

  function automatic logic [6:0] expected_consumer(input integer index);
    integer pos;
    begin
      if (index < 144) begin
        pos = index % 18;
        if (pos < 14)
          expected_consumer = 7'(pos + 1);
        else begin
          case (pos)
            14: expected_consumer = 7'h10;
            15: expected_consumer = 7'h11;
            16: expected_consumer = 7'h12;
            default: expected_consumer = 7'h20;
          endcase
        end
      end else begin
        case ((index - 144) % 4)
          0: expected_consumer = 7'h51;
          1: expected_consumer = 7'h52;
          2: expected_consumer = 7'h53;
          default: expected_consumer = 7'h54;
        endcase
      end
    end
  endfunction

  always_comb begin
    cond = 16'd0;
    cond[8] = slot == 3'd0;
  end

  psg_execmove u_move(
    .active(active), .hold(hold), .owner(owner), .op(op), .action(action),
    .state_word(state_word), .state_q(state_q), .acc(16'd0),
    .spar_bank(spar_bank), .join_stage(1'b0), .trig_req(1'b0),
    .walk_tick(1'b0), .playing(1'b0), .ins_use(1'b0), .released(1'b0),
    .cpz(1'b0), .state_ra_override(state_ra_override),
    .state_ra_word(state_ra_word), .state_we_extra(state_we_extra),
    .state_wa_word(state_wa_word), .state_wd_override(state_wd_override),
    .state_wd_fixed(state_wd_fixed), .cond_adv(cond_adv),
    .voice_stop(voice_stop), .cpz_we(cpz_we), .cpz_next(cpz_next));

  psg_execctl u_ctl(
    .clk(clk), .reset(reset), .start(start), .start_owner(start_owner),
    .start_pc(start_pc), .hold(hold), .cond(cond),
    .state_wd_i(synthetic_wd(slot, action, pc)),
    .state_ra_override_i(state_ra_override),
    .state_ra_word_i(state_ra_word), .state_we_i(state_we_extra),
    .state_wa_word_i(state_wa_word), .active(active), .done(done),
    .owner(owner), .slot(slot), .state_re(state_re), .state_ra(state_ra),
    .state_we(state_we),
    .state_wa(state_wa), .state_wd(state_wd), .action(action),
    .state_word(state_word), .op_dbg(op), .pc_dbg(pc), .ir_dbg(ir));

  always_ff @(posedge clk) begin
    if (reset)
      state_q <= 16'd0;
    else if (state_re)
      state_q <= mem[state_ra];
    if (state_we)
      mem[state_wa] <= state_wd;
  end

  task automatic check_read_address(input integer index);
    integer voice, pos, node, lane, expected_slot, expected_word;
    logic [6:0] expected_action;
    begin
      if (index < 144) begin
        voice = index / 18;
        pos = index % 18;
        expected_slot = voice;
        expected_word = pos < 14 ? 10 + pos
                                 : (spar_bank ? 28 : 24) + pos - 14;
        if (pos < 14)
          expected_action = 7'(pos);
        else begin
          case (pos)
            14: expected_action = 7'h0e;
            15: expected_action = 7'h10;
            16: expected_action = 7'h11;
            default: expected_action = 7'h12;
          endcase
        end
        if (state_word != (pos < 14 ? 10 + pos : 24 + pos - 14))
          $fatal(1, "read %0d literal word got=%0d", index, state_word);
        if ((pos >= 14) != state_ra_override)
          $fatal(1, "read %0d parameter override mismatch %b", index,
                 state_ra_override);
      end else begin
        node = (index - 144) / 4;
        lane = (index - 144) % 4;
        expected_slot = lane < 2 ? fold_a[node] : fold_b[node];
        expected_word = 48 + (lane & 1);
        case (lane)
          0: expected_action = 7'h50;
          1: expected_action = 7'h51;
          2: expected_action = 7'h50;
          default: expected_action = 7'h53;
        endcase
        if (state_ra_override)
          $fatal(1, "fold read %0d unexpectedly overridden", index);
      end
      if (state_ra != {expected_slot[2:0], expected_word[5:0]}
          || action != expected_action)
        $fatal(1, "read %0d got slot/word/action=%0d/%0d/%h expected=%0d/%0d/%h",
               index, state_ra[8:6], state_ra[5:0], action,
               expected_slot, expected_word, expected_action);
    end
  endtask

  task automatic check_write(input integer index);
    integer voice, pos, node, lane, expected_slot, expected_word;
    logic [6:0] expected_action;
    begin
      if (index < 144) begin
        voice = index / 18;
        pos = index % 18;
        expected_slot = voice;
        if (pos < 14) begin
          expected_word = 10 + pos;
          expected_action = 7'h30 + 7'(pos);
        end else begin
          case (pos)
            14: begin expected_word = 15; expected_action = 7'h40; end
            15: begin expected_word = 14; expected_action = 7'h41; end
            16: begin expected_word = 48; expected_action = 7'h42; end
            default: begin expected_word = 49; expected_action = 7'h43; end
          endcase
        end
      end else begin
        node = (index - 144) / 2;
        lane = (index - 144) % 2;
        expected_slot = fold_dst[node];
        expected_word = 48 + lane;
        expected_action = lane ? 7'h57 : 7'h56;
      end
      if (state_wa != {expected_slot[2:0], expected_word[5:0]}
          || action != expected_action || state_word != expected_word)
        $fatal(1, "write %0d got slot/word/action=%0d/%0d/%h expected=%0d/%0d/%h",
               index, state_wa[8:6], state_wa[5:0], action,
               expected_slot, expected_word, expected_action);
      if (state_wd !== synthetic_wd(slot, action, pc))
        $fatal(1, "write %0d data got=%h expected=%h", index, state_wd,
               synthetic_wd(slot, action, pc));
    end
  endtask

  // Observe the instruction after the EBR fetch edge.  A value issued by the
  // previous READ must now be paired with its exact consuming action.
  always @(negedge clk) begin
    if (!reset && active && !hold) begin
      if (!state_re)
        $fatal(1, "active instruction did not enable state memory");
      active_edge_count = active_edge_count + 1;
      op_count[op] = op_count[op] + 1;
      if (owner)
        $fatal(1, "sample program changed owner");
      if (state_we_extra || state_wd_override)
        $fatal(1, "sample movement grew hidden write/data state");
      if (pending_read) begin
        if (state_q !== pending_data || action != pending_consumer)
          $fatal(1, "read consume got data/action=%h/%h expected=%h/%h",
                 state_q, action, pending_data, pending_consumer);
        pending_read = 1'b0;
      end
      if (op == OP_READ) begin
        check_read_address(read_count);
        pending_data = mem[state_ra];
        pending_consumer = expected_consumer(read_count);
        pending_read = 1'b1;
        read_count = read_count + 1;
      end
      if (state_we) begin
        check_write(write_count);
        expected_mem[state_wa] = state_wd;
        write_count = write_count + 1;
      end
    end
  end

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  task automatic run_bank(input logic next_bank, input logic test_hold);
    integer n, cycles, saved_reads, saved_writes;
    logic [7:0] saved_pc;
    logic [15:0] saved_ir, saved_state_q;
    logic [2:0] saved_slot;
    begin
      reset = 1'b1;
      start = 1'b0;
      start_owner = 1'b0;
      start_pc = 8'd1;
      hold = 1'b0;
      spar_bank = next_bank;
      pending_read = 1'b0;
      read_count = 0;
      write_count = 0;
      active_edge_count = 0;
      for (n = 0; n < 8; n++)
        op_count[n] = 0;
      for (n = 0; n < 512; n++) begin
        mem[n] = 16'(16'h4000 + n * 16'h25 + next_bank);
        expected_mem[n] = mem[n];
      end
      step();
      step();
      reset = 1'b0;

      start = 1'b1;
      step();
      start = 1'b0;

      if (test_hold) begin
        while (!(active && pc == 8'd5))
          step();
        saved_pc = pc;
        saved_ir = ir;
        saved_state_q = state_q;
        saved_slot = slot;
        saved_reads = read_count;
        saved_writes = write_count;
        hold = 1'b1;
        repeat (3) step();
        if (pc != saved_pc || ir != saved_ir || slot != saved_slot
            || read_count != saved_reads || write_count != saved_writes
            || state_re || state_we || state_q != saved_state_q)
          $fatal(1, "hold changed controller or memory transaction counts");
        hold = 1'b0;
      end

      cycles = 0;
      while (!done && cycles < 900) begin
        step();
        cycles = cycles + 1;
      end
      if (!done)
        $fatal(1, "sample program did not complete");
      if (pending_read)
        $fatal(1, "sample program left an unconsumed read");
      if (read_count != 172 || write_count != 158)
        $fatal(1, "transaction count got reads/writes=%0d/%0d", read_count,
               write_count);
      if (active_edge_count != 782)
        $fatal(1, "active instruction count got=%0d expected=782",
               active_edge_count);
      if (op_count[0] != 172 || op_count[1] != 158
          || op_count[2] != 8 || op_count[3] != 29
          || op_count[4] != 8 || op_count[5] != 0
          || op_count[6] != 1 || op_count[7] != 406)
        $fatal(1, "instruction distribution mismatch");
      for (n = 0; n < 512; n++)
        if (mem[n] !== expected_mem[n])
          $fatal(1, "memory mismatch at %0d got=%h expected=%h", n,
                 mem[n], expected_mem[n]);
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    run_bank(1'b0, 1'b1);
    run_bank(1'b1, 1'b0);
    $display("psg_execsample_tb: PASS (2 banks x 172 reads + 158 writes)");
    $finish;
  end
endmodule
